//
// Actions.swift
//
// The scripts the app fronts, their options, and the exact argv each one
// receives. Pure data and pure functions, so the argument building for every
// action is covered by tests without ever launching osascript.
//

import Foundation

/// The three sections of the Actions column, in display order.
public enum ActionGroup: String, CaseIterable, Identifiable, Sendable {
    case build = "Build & maintain"
    case downloads = "Downloads"
    case backup = "Backup"

    public var id: String { rawValue }
    public var kinds: [ActionKind] { ActionKind.allCases.filter { $0.group == self } }
}

/// One script the app can run. The raw value is the script's basename, so the
/// bundled file is always `<rawValue>.applescript`. The three superseded
/// scripts (organize-by-genre, group-genres, lowercase-names) are left out on
/// purpose -- build-genres replaced them.
public enum ActionKind: String, CaseIterable, Identifiable, Sendable {
    case buildGenres = "build-genres"
    case whatsNew = "whats-new"
    case dedupePlaylists = "dedupe-playlists"
    case markUnavailable = "mark-unavailable"
    case downloadReport = "download-report"
    case downloadGenres = "download-genres"
    case watchDownloads = "watch-downloads"
    case backupPlaylists = "backup-playlists"
    case restorePlaylists = "restore-playlists"

    public var id: String { rawValue }
    public var scriptFile: String { rawValue + ".applescript" }

    public var group: ActionGroup {
        switch self {
        case .buildGenres, .whatsNew, .dedupePlaylists, .markUnavailable: return .build
        case .downloadReport, .downloadGenres, .watchDownloads: return .downloads
        case .backupPlaylists, .restorePlaylists: return .backup
        }
    }

    /// True when the real run changes the library, so the app previews it with
    /// `--dry-run` first and only then offers to run it for real.
    public var isDestructive: Bool {
        switch self {
        case .buildGenres, .dedupePlaylists, .markUnavailable, .downloadGenres, .restorePlaylists: return true
        case .whatsNew, .downloadReport, .watchDownloads, .backupPlaylists: return false
        }
    }

    /// Shown in the confirm bar after the dry run, above "Run for real".
    /// build-genres has two modes, so its copy depends on the argv previewed.
    public func confirmMessage(for arguments: [String]) -> String {
        switch self {
        case .buildGenres:
            if arguments.contains("--replace") {
                return "The real run deletes the existing genre folder and rebuilds it. Playlist deletion is permanent and syncs to every device."
            }
            return "Appends the new tracks to their genre's existing playlist and creates playlists for new genres. Nothing existing is removed. Whether iCloud keeps appended rows is untested; check with whats-new a day later."
        case .dedupePlaylists: return "Removes the duplicate rows listed above. Library tracks are never removed, only playlist rows."
        case .markUnavailable: return "Deletes and recreates the playlist with the tracks listed above."
        case .downloadGenres: return "Queues every gap for download. Music works through the queue in the background over hours; it cannot be cancelled from here."
        case .restorePlaylists: return "Creates the playlists listed above. Tracks no longer in the library are skipped."
        case .whatsNew, .downloadReport, .watchDownloads, .backupPlaylists: return ""
        }
    }
}

/// Every option any action takes, with the scripts' own defaults. One struct
/// rather than one per action keeps the UI bindings trivial.
public struct ActionOptions: Equatable, Sendable {
    public static let defaultFolder = "genres"
    public static let defaultUnavailableName = "wont download"
    public static let defaultWatchInterval = 30

    /// Genre folder name, shared by every script that takes `--folder`.
    public var folder = ActionOptions.defaultFolder
    /// build-genres `--replace`: delete the folder and rebuild. Off means the
    /// incremental mode: only tracks not yet filed are touched.
    public var replace = false
    /// build-genres `--min-tracks N`; the script default is 1.
    public var minTracks = 1
    /// whats-new `--days N`; 0 means off.
    public var days = 0
    /// whats-new `--all`: do not cap the lists at 40 entries.
    public var showAll = false
    /// mark-unavailable `--name NAME`.
    public var unavailableName = ActionOptions.defaultUnavailableName
    /// watch-downloads `--interval SECONDS`; the script default is 30.
    public var watchInterval = ActionOptions.defaultWatchInterval
    /// Directory that receives `playlists-YYYYMMDD-HHMMSS` backup folders.
    public var backupsRoot = ""
    /// restore-playlists: the backup folder to read.
    public var restoreDirectory = ""
    /// restore-playlists: optional comma-separated playlist names.
    public var restoreNames = ""

    public init() {}
}

/// A script plus the argv it will be launched with.
public struct ScriptInvocation: Equatable, Sendable {
    public let kind: ActionKind
    public let arguments: [String]

    public init(kind: ActionKind, arguments: [String]) {
        self.kind = kind
        self.arguments = arguments
    }

    /// The command as it would be typed in a terminal, for the console.
    /// True for a build-genres run that deletes the folder first: the path the
    /// app offers a backup before.
    public var replacesFolder: Bool {
        kind == .buildGenres && arguments.contains("--replace")
    }

    public var commandLine: String {
        (["$ osascript", kind.scriptFile] + arguments.map(Self.quoted)).joined(separator: " ")
    }

    private static func quoted(_ arg: String) -> String {
        arg.contains(" ") ? "\"\(arg)\"" : arg
    }
}

public enum Arguments {
    /// Every script takes this. The app always passes it, last, so the
    /// console can show a progress bar and a live feed; on the command line
    /// it is off and the output is unchanged. It is added at launch rather
    /// than by `build`, which stays the pure option-to-argv mapping.
    public static let progressFlag = "--progress"

    /// argv for `kind` under `options`. `dryRun` only applies to destructive
    /// actions; the others never take the flag, so it is ignored for them.
    public static func build(_ kind: ActionKind, options: ActionOptions, dryRun: Bool, now: Date = Date()) -> [String] {
        var args: [String] = []
        if dryRun && kind.isDestructive { args.append("--dry-run") }

        switch kind {
        case .buildGenres:
            if options.replace { args.append("--replace") }
            args += folderArgs(options)
            if options.minTracks > 1 { args += ["--min-tracks", String(options.minTracks)] }
        case .whatsNew:
            if options.days > 0 { args += ["--days", String(options.days)] }
            if options.showAll { args.append("--all") }
            args += folderArgs(options)
        case .dedupePlaylists, .downloadReport, .downloadGenres:
            args += folderArgs(options)
        case .watchDownloads:
            args += folderArgs(options)
            if options.watchInterval > 0 && options.watchInterval != ActionOptions.defaultWatchInterval {
                args += ["--interval", String(options.watchInterval)]
            }
        case .markUnavailable:
            let name = options.unavailableName.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && name != ActionOptions.defaultUnavailableName { args += ["--name", name] }
        case .backupPlaylists:
            args.append(backupDirectory(root: options.backupsRoot, now: now))
        case .restorePlaylists:
            args.append(options.restoreDirectory)
            args += playlistNames(options.restoreNames)
        }
        return args
    }

    public static func invocation(_ kind: ActionKind, options: ActionOptions, dryRun: Bool, now: Date = Date()) -> ScriptInvocation {
        ScriptInvocation(kind: kind, arguments: build(kind, options: options, dryRun: dryRun, now: now))
    }

    /// The read-only pass behind Refresh: whats-new for library, filed,
    /// playlist and folder counts; dedupe --dry-run for duplicate rows.
    public static func refreshInvocations(options: ActionOptions) -> [ScriptInvocation] {
        [
            ScriptInvocation(kind: .whatsNew, arguments: folderArgs(options) + ["--json"]),
            ScriptInvocation(kind: .dedupePlaylists, arguments: ["--dry-run"] + folderArgs(options) + ["--json"]),
        ]
    }

    /// `<root>/playlists-YYYYMMDD-HHMMSS`, the same shape backup-playlists uses
    /// when run without an argument. The app always passes it explicitly so a
    /// bundled script never writes next to itself inside the .app.
    public static func backupDirectory(root: String, now: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let base = root.hasSuffix("/") ? String(root.dropLast()) : root
        return base + "/playlists-" + f.string(from: now)
    }

    /// "Road Trip, Focus" -> ["Road Trip", "Focus"]; blanks dropped.
    public static func playlistNames(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func folderArgs(_ options: ActionOptions) -> [String] {
        let folder = options.folder.trimmingCharacters(in: .whitespaces)
        if folder.isEmpty || folder == ActionOptions.defaultFolder { return [] }
        return ["--folder", folder]
    }
}
