//
// AppModel.swift
//
// One object holds the whole window's state: the overview numbers, the
// options for each action, the console lines, and the dry-run -> confirm flow.
// A "job" is a short sequence of script invocations run back to back (Refresh
// is two read-only scripts; a confirmed rebuild may be backup then build).
//

import Foundation
import SwiftUI
import OrganizerCore

struct ConsoleLine: Identifiable, Equatable {
    enum Kind { case command, stdout, stderr, note }
    let id: Int
    let time: Date
    let kind: Kind
    let text: String
}

enum Phase: Equatable {
    case idle
    case running(label: String, startedAt: Date)
    case finished(status: Int32, seconds: TimeInterval)
    case stopped(seconds: TimeInterval)
}

/// What a job is for, which decides what happens when it ends.
enum Purpose: Equatable {
    case refresh
    case run(ActionKind)
    /// Carries the real invocation the dry run stands for.
    case preview(ScriptInvocation)
    case confirmed(ActionKind)
}

/// The left column shows either the action rows or their documentation.
enum Tab: String, CaseIterable, Identifiable {
    case actions
    case docs

    var id: String { rawValue }
}

/// The console body shows the live feed of a progress run or the raw log.
/// The feed is chosen when a run says `@@ begin`; the log is always there.
enum ConsoleMode: String, CaseIterable, Identifiable {
    case feed
    case log

    var id: String { rawValue }
}

/// A dry run finished; this is the real run it stands for. The argv is fixed
/// at preview time, so a toggle changed afterwards cannot alter what runs.
struct PendingConfirm: Equatable {
    let real: ScriptInvocation
    var kind: ActionKind { real.kind }
    var message: String { kind.confirmMessage(for: real.arguments) }
    /// Only a `--replace` rebuild deletes playlists, so only it offers a backup.
    var offersBackup: Bool { real.replacesFolder }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var tab: Tab = .actions
    /// Docs entry to scroll to when the Docs column appears (`--doc <action>`).
    @Published var docsTarget: ActionKind?
    @Published var options = ActionOptions()
    @Published var overview = LibraryOverview()
    @Published var lastRefreshed: Date?
    @Published private(set) var lines: [ConsoleLine] = []
    @Published private(set) var phase: Phase = .idle
    /// Set by the first `@@ begin` of a job; nil for runs that report nothing.
    @Published private(set) var progress: ProgressState?
    @Published var consoleMode: ConsoleMode = .log
    @Published var pendingConfirm: PendingConfirm?
    @Published var backupFirst = true
    @Published private(set) var automationDenied = false
    @Published private(set) var locator: ScriptLocator

    private let runner = ScriptRunner()
    private var job: Task<Void, Never>?
    private var nextLineID = 0
    private var stopRequested = false
    /// Protocol events are folded into `progress` in small batches (see
    /// `enqueue`), so a burst of items costs one view update, not hundreds.
    private var pendingProgress: [ProgressEvent] = []
    private var progressFlush: Task<Void, Never>?
    private let defaults = UserDefaults.standard
    private static let scriptsKey = "scriptsFolder"
    private static let backupsKey = "backupsFolder"

    init() {
        locator = Self.makeLocator(overridePath: defaults.string(forKey: Self.scriptsKey))
        options.backupsRoot = defaults.string(forKey: Self.backupsKey) ?? Self.defaultBackupsRoot()
        // A watch can run for hours; quitting the app must take it along
        // rather than leave an orphaned osascript polling Music.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [runner] _ in
            runner.stopAndWait()
        }
    }

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    // MARK: - Entry points

    /// Runs whats-new and dedupe --dry-run, both read-only, and fills the overview.
    func refresh() {
        start(Arguments.refreshInvocations(options: options), purpose: .refresh)
    }

    /// A non-destructive action, run directly.
    func run(_ kind: ActionKind) {
        precondition(!kind.isDestructive)
        start([Arguments.invocation(kind, options: options, dryRun: false)], purpose: .run(kind))
    }

    /// A destructive action: dry-run first; the confirm bar appears on success.
    func preview(_ kind: ActionKind) {
        precondition(kind.isDestructive)
        let real = Arguments.invocation(kind, options: options, dryRun: false)
        start([Arguments.invocation(kind, options: options, dryRun: true)], purpose: .preview(real))
    }

    /// "Run for real" after a preview.
    func confirm() {
        guard let pending = pendingConfirm else { return }
        var steps: [ScriptInvocation] = []
        if pending.offersBackup && backupFirst {
            steps.append(Arguments.invocation(.backupPlaylists, options: options, dryRun: false))
        }
        steps.append(pending.real)
        start(steps, purpose: .confirmed(pending.kind))
    }

    func cancelConfirm() {
        pendingConfirm = nil
    }

    /// Terminates the running script and abandons the rest of the job.
    func stop() {
        stopRequested = true
        runner.stop()
    }

    /// `--refresh`, `--run <action>`, `--preview <action>`, `--tab docs` and
    /// `--doc <action>`, so a run can be scripted
    /// (`open Organizer.app --args --refresh`). `--run` takes only the
    /// non-destructive actions; anything that changes the library still goes
    /// through `--preview` and the confirm bar.
    func handleLaunchArguments(_ args: [String]) {
        if let i = args.firstIndex(of: "--tab"), i + 1 < args.count, let t = Tab(rawValue: args[i + 1]) {
            tab = t
        }
        if let i = args.firstIndex(of: "--doc"), i + 1 < args.count, let kind = ActionKind(rawValue: args[i + 1]) {
            tab = .docs
            docsTarget = kind
        }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            installSnapshotHooks(path: args[i + 1])
        }
        if args.contains("--refresh") { refresh(); return }
        if let i = args.firstIndex(of: "--run"), i + 1 < args.count,
           let kind = ActionKind(rawValue: args[i + 1]), !kind.isDestructive {
            run(kind)
            return
        }
        if let i = args.firstIndex(of: "--preview"), i + 1 < args.count,
           let kind = ActionKind(rawValue: args[i + 1]), kind.isDestructive {
            preview(kind)
        }
    }

    // MARK: - Snapshots

    private var signalSources: [DispatchSourceSignal] = []

    /// `--snapshot <path>`: a hook for scripted verification, since the app
    /// can render its own window where a screen capture would need Screen
    /// Recording permission. `kill -USR1 <pid>` writes the window to `path`
    /// as PNG; `kill -USR2 <pid>` flips the console between feed and log.
    private func installSnapshotHooks(path: String) {
        signal(SIGUSR1, SIG_IGN)
        signal(SIGUSR2, SIG_IGN)
        let shot = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        shot.setEventHandler { [weak self] in self?.snapshot(to: path) }
        shot.resume()
        let flip = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
        flip.setEventHandler { [weak self] in
            guard let self else { return }
            self.consoleMode = self.consoleMode == .feed ? .log : .feed
        }
        flip.resume()
        signalSources = [shot, flip]
    }

    private func snapshot(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }), let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    // MARK: - Folders

    func chooseScriptsFolder() {
        guard let url = Panels.chooseDirectory(title: "Folder holding the .applescript files") else { return }
        defaults.set(url.path, forKey: Self.scriptsKey)
        locator = Self.makeLocator(overridePath: url.path)
    }

    func useBundledScripts() {
        defaults.removeObject(forKey: Self.scriptsKey)
        locator = Self.makeLocator(overridePath: nil)
    }

    func chooseBackupsFolder() {
        guard let url = Panels.chooseDirectory(title: "Folder that receives playlist backups", startingAt: options.backupsRoot) else { return }
        options.backupsRoot = url.path
        defaults.set(url.path, forKey: Self.backupsKey)
    }

    func chooseRestoreFolder() {
        guard let url = Panels.chooseDirectory(title: "Backup folder to restore from", startingAt: options.backupsRoot) else { return }
        options.restoreDirectory = url.path
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Jobs

    private func start(_ steps: [ScriptInvocation], purpose: Purpose) {
        guard !isRunning else { return }
        lines.removeAll()
        nextLineID = 0
        progress = nil
        pendingProgress.removeAll()
        consoleMode = .log
        pendingConfirm = nil
        automationDenied = false
        stopRequested = false
        job = Task { await runJob(steps, purpose: purpose) }
    }

    private func runJob(_ steps: [ScriptInvocation], purpose: Purpose) async {
        let startedAt = Date()
        var status: Int32 = 0
        var stopped = false
        var captured: [ActionKind: String] = [:]
        // A real download-genres run that queued something is followed by the
        // watcher, appended here so it runs in the same console session.
        var queue = steps
        var at = 0

        while at < queue.count {
            let step = queue[at]
            at += 1
            guard let script = locator.url(for: step.kind) else {
                append(.note, "\(step.kind.scriptFile) not found -- choose the scripts folder below.")
                status = 127
                break
            }
            let argv = step.arguments + [Arguments.progressFlag]
            let label = ([step.kind.rawValue] + step.arguments).joined(separator: " ")
            phase = .running(label: label, startedAt: startedAt)
            append(.command, ScriptInvocation(kind: step.kind, arguments: argv).commandLine)

            var stdout = ""
            for await event in runner.run(script: script, arguments: argv) {
                switch event {
                case .started:
                    break
                case .line(let line):
                    // `@@` lines are the progress protocol: they feed the bar
                    // and the feed, and stay out of the human log.
                    if line.channel == .stderr, let progressEvent = ProgressProtocol.parse(line.text) {
                        enqueue(progressEvent)
                        continue
                    }
                    append(line.channel == .stdout ? .stdout : .stderr, line.text, at: line.timestamp)
                    if line.channel == .stdout { stdout += line.text + "\n" }
                    if OutputParser.indicatesAutomationDenied(line.text) { automationDenied = true }
                case .exited(let code, let wasStopped):
                    status = code
                    stopped = wasStopped || stopRequested
                }
            }
            captured[step.kind] = stdout
            if status != 0 || stopped { break }
            if step.kind == .downloadGenres, !step.arguments.contains("--dry-run"),
               let queued = OutputParser.queuedPlaylists(in: stdout), queued > 0 {
                append(.note, "queued \(queued) playlists; watching for each track to land. Stop ends the watch, not the downloads.")
                queue.append(Arguments.invocation(.watchDownloads, options: options, dryRun: false))
            }
        }

        flushProgress()
        progress?.finish()

        let seconds = Date().timeIntervalSince(startedAt)
        if stopped {
            append(.note, "stopped")
            phase = .stopped(seconds: seconds)
        } else {
            phase = .finished(status: status, seconds: seconds)
        }

        switch purpose {
        case .refresh:
            let fresh = LibraryOverview.merge(
                whatsNew: captured[.whatsNew].flatMap { OutputParser.decode(WhatsNewSummary.self, from: $0) },
                dedupe: captured[.dedupePlaylists].flatMap { OutputParser.decode(DedupeSummary.self, from: $0) })
            if fresh != LibraryOverview() {
                overview = fresh
                lastRefreshed = Date()
            }
        case .preview(let real):
            if status == 0 && !stopped { pendingConfirm = PendingConfirm(real: real) }
        case .run, .confirmed:
            break
        }
    }

    private func append(_ kind: ConsoleLine.Kind, _ text: String, at time: Date = Date()) {
        lines.append(ConsoleLine(id: nextLineID, time: time, kind: kind, text: text))
        nextLineID += 1
    }

    // MARK: - Progress

    private func enqueue(_ event: ProgressEvent) {
        pendingProgress.append(event)
        guard progressFlush == nil else { return }
        progressFlush = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            self?.flushProgress()
        }
    }

    private func flushProgress() {
        progressFlush?.cancel()
        progressFlush = nil
        guard !pendingProgress.isEmpty else { return }
        let now = Date()
        var state = progress
        for event in pendingProgress {
            if case .begin(let total, let unit) = event, state == nil {
                state = ProgressState(total: total, unit: unit, at: now)
                // the first begin of a job brings the feed forward
                consoleMode = .feed
            } else {
                state?.apply(event, at: now)
            }
        }
        pendingProgress.removeAll()
        progress = state
    }

    // MARK: - Locations

    private static func makeLocator(overridePath: String?) -> ScriptLocator {
        ScriptLocator(overridePath: overridePath,
                      bundleResources: Bundle.main.resourceURL,
                      executable: Bundle.main.executableURL)
    }

    /// `<repo>/backups` when build.sh recorded the repo root and it still
    /// exists (that folder is gitignored there), else a folder under ~/Music.
    private static func defaultBackupsRoot() -> String {
        if let repo = Bundle.main.infoDictionary?["OrganizerRepoRoot"] as? String,
           FileManager.default.fileExists(atPath: repo) {
            return repo + "/backups"
        }
        let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music")
        return music.appendingPathComponent("organizer-apple-music-backups").path
    }
}
