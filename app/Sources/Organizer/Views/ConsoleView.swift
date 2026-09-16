//
// ConsoleView.swift
//
// The running script, in the user's terminal terms, on a Panel ground. Two
// bodies: the raw log (every `log` line as it streams in, the return value at
// the end) and, for a run that speaks the progress protocol, a live feed of
// the items with a progress bar above it. The feed comes forward when a run
// says `@@ begin`; the log is one label away throughout. Below the body: the
// Automation notice when Music refused, and the confirm bar after a dry run.
//
// Zima is spent once here: the progress bar's fill, which the running mark in
// the header shares. Kinds are told apart by glyph and weight, never colour.
//

import SwiftUI
import AppKit
import OrganizerCore

struct ConsoleView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
            Hairline()
            if let progress = model.progress {
                ProgressStrip(progress: progress)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                Hairline()
            }
            if model.consoleMode == .feed, let progress = model.progress {
                FeedView(progress: progress)
            } else {
                LogView()
            }
            if model.automationDenied {
                Hairline()
                AutomationNotice()
            }
            if let pending = model.pendingConfirm {
                Hairline()
                ConfirmBar(pending: pending)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text("console").label()
            if model.progress != nil {
                HStack(spacing: 18) {
                    ForEach(ConsoleMode.allCases) { mode in
                        LabelTab(title: mode.rawValue, selected: model.consoleMode == mode) { model.consoleMode = mode }
                    }
                }
                .padding(.leading, 22)
            }
            Spacer()
            StatusLine(phase: model.phase, summary: model.progress?.summary ?? "")
            if model.isRunning {
                Button("Stop") { model.stop() }
                    .buttonStyle(HairlineButtonStyle())
                    .help("Terminates the script. A download already queued in Music keeps going.")
            }
        }
    }
}

/// `mm:ss`, used by the status line and the progress strip.
private func clock(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds.rounded()))
    return String(format: "%02d:%02d", s / 60, s % 60)
}

// MARK: - Header status

private struct StatusLine: View {
    let phase: Phase
    /// Counts by kind from the progress run, shown where "done" lands.
    let summary: String

    var body: some View {
        HStack(spacing: 10) {
            switch phase {
            case .idle:
                EmptyView()
            case .running(let label, let startedAt):
                RunningMark()
                Text(label).font(Typeface.mono(12)).foregroundStyle(Palette.text).lineLimit(1).truncationMode(.middle)
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    Text(clock(context.date.timeIntervalSince(startedAt)))
                        .font(Typeface.mono(12)).foregroundStyle(Palette.muted).monospacedDigit()
                }
            case .finished(let status, let seconds):
                counts
                Text(status == 0 ? "done" : "exited \(status)")
                    .font(Typeface.mono(12)).foregroundStyle(status == 0 ? Palette.muted : Palette.bright)
                Text(clock(seconds)).font(Typeface.mono(12)).foregroundStyle(Palette.muted)
            case .stopped(let seconds):
                counts
                Text("stopped").font(Typeface.mono(12)).foregroundStyle(Palette.bright)
                Text(clock(seconds)).font(Typeface.mono(12)).foregroundStyle(Palette.muted)
            }
        }
    }

    @ViewBuilder private var counts: some View {
        if !summary.isEmpty {
            Text(summary)
                .font(Typeface.mono(12)).foregroundStyle(Palette.text).monospacedDigit()
                .lineLimit(1).truncationMode(.tail)
                .padding(.trailing, 6)
        }
    }
}

// MARK: - Progress strip

/// A hairline track with a Zima fill, then in mono: n / N, the unit, elapsed,
/// and a rough ETA once a few items are in.
private struct ProgressStrip: View {
    let progress: ProgressState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 18) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Palette.hairline)
                    Rectangle()
                        .fill(Palette.zima)
                        .frame(width: geo.size.width * (progress.fraction ?? 0))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: progress.fraction)
                }
            }
            .frame(height: 2)
            Text(position)
                .font(Typeface.mono(12)).foregroundStyle(Palette.bright).monospacedDigit()
                .fixedSize()
            Text(progress.unit.isEmpty ? "items" : progress.unit).label()
                .fixedSize()
            TimelineView(.animation(minimumInterval: 1, paused: progress.ended)) { context in
                HStack(spacing: 18) {
                    Text(clock(progress.elapsed(at: context.date)))
                        .font(Typeface.mono(12)).foregroundStyle(Palette.muted).monospacedDigit()
                    Text(eta(at: context.date))
                        .font(Typeface.mono(12)).foregroundStyle(Palette.muted).monospacedDigit()
                        .frame(width: 92, alignment: .leading)
                }
            }
            .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var position: String {
        let done = ProgressState.grouped(progress.done)
        guard let total = progress.total else { return done }
        return "\(done) / \(ProgressState.grouped(total))"
    }

    private func eta(at date: Date) -> String {
        if progress.ended { return "" }
        guard let left = progress.eta(at: date) else { return "" }
        return "~\(clock(left)) left"
    }

    private var accessibilityText: String {
        "\(position) \(progress.unit)" + (progress.ended ? ", finished" : "")
    }
}

// MARK: - Feed

private struct FeedView: View {
    let progress: ProgressState
    /// Follows the newest row until the user scrolls up; back at the bottom,
    /// it follows again.
    @State private var following = true
    @State private var lastWheel = Date.distantPast

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { outer in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if progress.droppedRows > 0 {
                            Text("\(ProgressState.grouped(progress.droppedRows)) earlier rows are not shown; the log has every line.")
                                .caption()
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                        }
                        if progress.rows.isEmpty {
                            Text(progress.ended ? "Nothing to report." : "Waiting for the first item…")
                                .caption()
                                .padding(20)
                        }
                        ForEach(progress.rows) { row in
                            FeedRowView(row: row).id(row.id)
                        }
                        Color.clear.frame(height: 1).id("feed-bottom")
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GeometryReader { inner in
                        Color.clear.preference(key: FeedBottomKey.self, value: inner.frame(in: .named("feed")).maxY)
                    })
                }
                .coordinateSpace(name: "feed")
                .onPreferenceChange(FeedBottomKey.self) { maxY in
                    let distance = maxY - outer.size.height
                    if distance < 48 {
                        following = true
                    } else if Date().timeIntervalSince(lastWheel) < 0.5 {
                        // the user scrolled, and away from the bottom
                        following = false
                    }
                }
                .onChange(of: progress.changeCount) { _, _ in
                    guard following else { return }
                    // after layout, so the anchor reflects the rows just added.
                    // A new row: stay on the bottom. A row changed in place (a
                    // pending track landed): bring it into view, in its group.
                    let changed = progress.lastChangedRowID
                    let appended = changed == progress.rows.last?.id
                    DispatchQueue.main.async {
                        if appended || changed == nil {
                            proxy.scrollTo("feed-bottom", anchor: .bottom)
                        } else {
                            proxy.scrollTo(changed!, anchor: .center)
                        }
                    }
                }
                .background(ScrollWheelWatcher { lastWheel = Date() })
            }
        }
        .background(Palette.panel)
    }
}

private struct FeedBottomKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// One item. The playlist rule and label open a group when it changes. A row
/// whose kind changes (pending became downloaded) is emphasised for a moment:
/// the artist joins the title in Bright and a Hairline wash sits behind the
/// row, then both ease away -- or, under Reduce Motion, simply switch off.
private struct FeedRowView: View {
    let row: FeedRow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var emphasised = false

    var body: some View {
        content
            .background(Palette.hairline.opacity(emphasised ? 0.9 : 0))
            .onChange(of: row.revision) { _, _ in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { emphasised = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.9)) { emphasised = false }
                }
            }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if row.startsGroup {
                Text(row.playlist.isEmpty ? "—" : row.playlist)
                    .label()
                    .lineLimit(1)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                Hairline()
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(Kind.glyph(for: row.kind))
                    .font(Typeface.mono(12, weight: Kind.isEmphatic(row.kind) ? .medium : .regular))
                    .foregroundStyle(Kind.isEmphatic(row.kind) ? Palette.bright : Palette.muted)
                    .frame(width: 12, alignment: .center)
                Text(row.kind)
                    .font(Typeface.mono(11)).foregroundStyle(Palette.muted)
                    .frame(width: 84, alignment: .leading)
                    .lineLimit(1)
                song
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 16)
                Text(row.playlist)
                    .font(Typeface.mono(11)).foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            .padding(.vertical, 5)
        }
        .padding(.horizontal, 20)
    }

    private var song: Text {
        let title = Text(row.title).font(Typeface.text(13, weight: .medium)).foregroundColor(Palette.bright)
        guard !row.artist.isEmpty else { return title }
        return Text(row.artist).font(Typeface.text(13)).foregroundColor(emphasised ? Palette.bright : Palette.text)
            + Text(" — ").font(Typeface.text(13)).foregroundColor(Palette.muted)
            + title
    }
}

/// Glyph and weight per kind. No colour: meaning is never in colour alone,
/// and the view's one blue is already spent on the bar.
private enum Kind {
    static func glyph(for kind: String) -> String {
        switch kind {
        case "added", "restored", "backed-up": return "✓"
        case "downloaded": return "●"
        case "pending", "unfiled": return "○"
        case "unavailable", "missing": return "×"
        case "queued": return "→"
        case "created": return "+"
        case "removed": return "−"
        case "duplicates": return "≡"
        case "checked": return "·"
        default: return "·"
        }
    }

    /// Bright for something that happened; Muted for a state observed.
    static func isEmphatic(_ kind: String) -> Bool {
        switch kind {
        case "added", "restored", "backed-up", "downloaded", "created", "removed", "queued": return true
        default: return false
        }
    }
}

/// Tells the feed when the user turns the wheel over it, which is the only
/// way to know a scroll was theirs and not the feed following new rows.
private struct ScrollWheelWatcher: NSViewRepresentable {
    let onScroll: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScroll: onScroll) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak view] event in
            if let view, let window = view.window, event.window === window,
               view.bounds.contains(view.convert(event.locationInWindow, from: nil)) {
                coordinator.onScroll()
            }
            return event
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onScroll = onScroll
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        coordinator.monitor = nil
    }

    final class Coordinator {
        var monitor: Any?
        var onScroll: () -> Void
        init(onScroll: @escaping () -> Void) { self.onScroll = onScroll }
    }
}

// MARK: - Log

private struct LogView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // A plain VStack: a run is at most a few hundred lines, and it
                // lets scrollTo land on the true bottom after a burst of output.
                VStack(alignment: .leading, spacing: 3) {
                    if model.lines.isEmpty {
                        Text("Nothing has run yet. Refresh reads the library; Preview shows a plan before anything changes.")
                            .caption()
                            .lineSpacing(4)
                    }
                    ForEach(model.lines) { line in
                        ConsoleLineView(line: line)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Palette.panel)
            .onAppear {
                DispatchQueue.main.async { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: model.lines.count) { _, _ in
                // after layout, so the anchor reflects the lines just added
                DispatchQueue.main.async { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: model.pendingConfirm) { _, _ in
                DispatchQueue.main.async { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }
}

private struct ConsoleLineView: View {
    let line: ConsoleLine
    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(Self.time.string(from: line.time))
                .font(Typeface.mono(11)).foregroundStyle(Palette.muted).monospacedDigit()
            Text(tag)
                .font(Typeface.mono(11)).foregroundStyle(Palette.muted)
                .frame(width: 24, alignment: .leading)
            Text(line.text)
                .font(Typeface.mono(12))
                .foregroundStyle(colour)
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tag: String {
        switch line.kind {
        case .command: return ""
        case .stderr: return "log"
        case .stdout: return "out"
        case .note: return "app"
        }
    }

    private var colour: Color {
        switch line.kind {
        case .command: return Palette.bright
        case .stdout, .stderr: return Palette.text
        case .note: return Palette.muted
        }
    }
}

// MARK: - Notices

/// The dry run finished: offer the real thing, once.
private struct ConfirmBar: View {
    @EnvironmentObject private var model: AppModel
    let pending: PendingConfirm

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Dry run finished. Run \(pending.kind.rawValue) for real?").small(Palette.bright, weight: .medium)
                Text(pending.message)
                    .caption(Palette.text)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if pending.offersBackup {
                Toggle("back up playlists first", isOn: $model.backupFirst).toggleStyle(SquareToggleStyle())
            }
            Button("Cancel") { model.cancelConfirm() }.buttonStyle(HairlineButtonStyle())
            Button("Run for real") { model.confirm() }.buttonStyle(HairlineButtonStyle(role: .primary))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

/// Music refused Apple events (-1743): say where to fix it.
private struct AutomationNotice: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Music refused automation (error -1743).").small(Palette.bright, weight: .medium)
                Text("Allow Organizer to control Music under System Settings → Privacy & Security → Automation, then run again.")
                    .caption(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Open System Settings") { model.openAutomationSettings() }.buttonStyle(HairlineButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}
