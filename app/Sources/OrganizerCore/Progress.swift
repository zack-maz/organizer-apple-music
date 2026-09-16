//
// Progress.swift
//
// The `--progress` protocol the scripts emit on stderr, and the model the app
// builds from it: a position in a known total, counts by kind, and a capped
// feed of the items as they arrive. Pure values, so all of it is unit-tested.
//
//   @@ begin<TAB>total=N<TAB>unit=tracks
//   @@ item<TAB>i=n<TAB>of=N<TAB>kind=added<TAB>playlist=…<TAB>artist=…<TAB>title=…
//   @@ end
//
// Fields are tab-separated key=value pairs; values never contain tabs or
// newlines (the scripts fold them to spaces) but may contain anything else,
// including `=`. An item without `i` is an uncounted event (a playlist
// created or queued): it appears in the feed and the counts, not the bar.
// An item with `id` (the track's persistent ID) names a row: a later item
// with the same id updates that row in place -- pending becomes downloaded --
// rather than adding one.
//

import Foundation

public struct ProgressItem: Equatable, Sendable {
    /// 1-based position in the run, when the item counts toward the total.
    public var index: Int?
    /// The total as the script sees it at this point; overrides `begin`'s.
    public var total: Int?
    /// Track persistent ID, when the script knows it. Rows with the same id
    /// are one row.
    public var id: String?
    public var kind: String
    public var playlist: String
    public var artist: String
    public var title: String

    public init(index: Int? = nil, total: Int? = nil, id: String? = nil, kind: String,
                playlist: String = "", artist: String = "", title: String = "") {
        self.index = index
        self.total = total
        self.id = id
        self.kind = kind
        self.playlist = playlist
        self.artist = artist
        self.title = title
    }
}

public enum ProgressEvent: Equatable, Sendable {
    case begin(total: Int?, unit: String)
    case item(ProgressItem)
    case end
}

public enum ProgressProtocol {
    /// Every protocol line starts with this; nothing the scripts say to a
    /// human does.
    public static let marker = "@@"

    /// The event a stderr line carries, or nil for anything else: human log
    /// lines, a bare marker, an unknown event name. Never throws.
    public static func parse(_ line: String) -> ProgressEvent? {
        guard line.hasPrefix(marker) else { return nil }
        let body = line.dropFirst(marker.count)
        guard let first = body.first, first == " " || first == "\t" else { return nil }

        // Tab-separated when tabs are present (the scripts' form); otherwise
        // space-separated, which only works for values without spaces.
        let separator: Character = body.contains("\t") ? "\t" : " "
        let fields = body.split(separator: separator, omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let name = fields.first else { return nil }

        var values: [String: String] = [:]
        for field in fields.dropFirst() {
            guard let eq = field.firstIndex(of: "=") else { continue }
            let key = String(field[..<eq]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            values[key] = String(field[field.index(after: eq)...])
        }

        switch name {
        case "begin":
            return .begin(total: values["total"].flatMap { Int($0) }, unit: values["unit"] ?? "")
        case "item":
            return .item(ProgressItem(
                index: values["i"].flatMap { Int($0) },
                total: values["of"].flatMap { Int($0) },
                id: values["id"].flatMap { $0.isEmpty ? nil : $0 },
                kind: values["kind"] ?? "",
                playlist: values["playlist"] ?? "",
                artist: values["artist"] ?? "",
                title: values["title"] ?? ""))
        case "end":
            return .end
        default:
            return nil
        }
    }
}

/// One line of the feed. `startsGroup` is true when the playlist differs from
/// the row before, so the view can draw the rule and label without lookups.
/// `revision` goes up each time an item with this row's `trackID` changes its
/// kind, which is what the view flashes on.
public struct FeedRow: Identifiable, Equatable, Sendable {
    public let id: Int
    public let trackID: String?
    public internal(set) var kind: String
    public internal(set) var playlist: String
    public internal(set) var artist: String
    public internal(set) var title: String
    public let startsGroup: Bool
    public internal(set) var revision = 0
}

/// What one run has reported so far. `apply` folds events in; the view reads
/// the rest. Counts are exact even after the feed is capped.
public struct ProgressState: Equatable, Sendable {
    /// Rows kept for display. A full-library pass emits a few thousand items;
    /// the oldest are dropped past this so the list stays cheap to draw.
    public static let rowCap = 2000
    /// ETA is not shown until this many counted items are in.
    public static let etaAfterItems = 5
    /// A download watch counts flips, which are rare; a rate is called
    /// established sooner.
    public static let etaAfterDownloads = 3
    public static let downloadsUnit = "downloads"

    public private(set) var total: Int?
    public private(set) var unit: String
    /// Highest `i` seen since `begin`.
    public private(set) var done = 0
    /// Every item event, counted or not.
    public private(set) var itemCount = 0
    public private(set) var countsByKind: [String: Int] = [:]
    /// Kinds in first-seen order, to break ties in the summary.
    public private(set) var kindOrder: [String] = []
    public private(set) var rows: [FeedRow] = []
    /// Rows dropped from the front of `rows` to honour `rowCap`.
    public private(set) var droppedRows = 0
    public private(set) var startedAt: Date
    public private(set) var lastItemAt: Date?
    public private(set) var endedAt: Date?
    private var nextRowID = 0
    private var lastPlaylist: String?
    /// Track persistent ID -> `FeedRow.id`, for rows still held.
    private var rowIDByTrack: [String: Int] = [:]
    /// Goes up on every row added or changed in kind; `lastChangedRowID` is
    /// that row. The view follows this, so a flip deep in the list is shown.
    public private(set) var changeCount = 0
    public private(set) var lastChangedRowID: Int?

    public init(total: Int?, unit: String, at now: Date = Date()) {
        self.total = total
        self.unit = unit
        self.startedAt = now
    }

    public var ended: Bool { endedAt != nil }

    /// A further `begin` in the same job (backup, then build): the bar starts
    /// over, the feed and the counts carry on.
    public mutating func begin(total: Int?, unit: String, at now: Date = Date()) {
        self.total = total
        self.unit = unit
        done = 0
        startedAt = now
        lastItemAt = nil
        endedAt = nil
        lastPlaylist = nil
    }

    public mutating func apply(_ event: ProgressEvent, at now: Date = Date()) {
        switch event {
        case .begin(let total, let unit):
            begin(total: total, unit: unit, at: now)
        case .item(let item):
            itemCount += 1
            lastItemAt = now
            if let i = item.index { done = max(done, i) }
            if let of = item.total { total = of }
            if let trackID = item.id, let rowID = rowIDByTrack[trackID], let at = rowIndex(withID: rowID) {
                update(rowAt: at, with: item)
                return
            }
            if countsByKind[item.kind] == nil { kindOrder.append(item.kind) }
            countsByKind[item.kind, default: 0] += 1
            rows.append(FeedRow(id: nextRowID, trackID: item.id, kind: item.kind, playlist: item.playlist,
                                artist: item.artist, title: item.title,
                                startsGroup: item.playlist != lastPlaylist))
            if let trackID = item.id { rowIDByTrack[trackID] = nextRowID }
            changeCount += 1
            lastChangedRowID = nextRowID
            nextRowID += 1
            lastPlaylist = item.playlist
            // Trim in batches: dropping one row per item would be quadratic.
            if rows.count > Self.rowCap + Self.rowCap / 10 {
                let surplus = rows.count - Self.rowCap
                for dropped in rows.prefix(surplus) {
                    if let trackID = dropped.trackID { rowIDByTrack[trackID] = nil }
                }
                rows.removeFirst(surplus)
                droppedRows += surplus
            }
        case .end:
            endedAt = now
        }
    }

    /// A later item for a row already shown: the kind moves (and the counts
    /// with it), blank fields keep what they had, and only a change of kind
    /// bumps `revision`, so a re-emitted pending row does not flash.
    private mutating func update(rowAt at: Int, with item: ProgressItem) {
        var row = rows[at]
        if !item.kind.isEmpty && item.kind != row.kind {
            countsByKind[row.kind, default: 1] -= 1
            if countsByKind[item.kind] == nil { kindOrder.append(item.kind) }
            countsByKind[item.kind, default: 0] += 1
            row.kind = item.kind
            row.revision += 1
            changeCount += 1
            lastChangedRowID = row.id
        }
        if !item.playlist.isEmpty { row.playlist = item.playlist }
        if !item.artist.isEmpty { row.artist = item.artist }
        if !item.title.isEmpty { row.title = item.title }
        rows[at] = row
    }

    /// Rows are appended with rising ids, so a binary search finds one.
    private func rowIndex(withID id: Int) -> Int? {
        var lo = 0, hi = rows.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if rows[mid].id == id { return mid }
            if rows[mid].id < id { lo = mid + 1 } else { hi = mid - 1 }
        }
        return nil
    }

    /// The script ended without saying `@@ end` (killed, or it errored).
    public mutating func finish(at now: Date = Date()) {
        if endedAt == nil { endedAt = now }
    }

    /// 0...1 when the total is known; nil while it is not. A run with a total
    /// of zero has nothing to do, so it is complete.
    public var fraction: Double? {
        guard let total else { return ended ? 1 : nil }
        guard total > 0 else { return 1 }
        return min(1, Double(done) / Double(total))
    }

    public func elapsed(at now: Date) -> TimeInterval {
        max(0, (endedAt ?? now).timeIntervalSince(startedAt))
    }

    /// Seconds left at the average rate so far, once a few items are in and
    /// at least a second has passed. Nil when unknowable or already complete.
    public var etaThreshold: Int {
        unit == Self.downloadsUnit ? Self.etaAfterDownloads : Self.etaAfterItems
    }

    public func eta(at now: Date) -> TimeInterval? {
        guard !ended, let total, total > 0, done < total, done >= etaThreshold else { return nil }
        let seconds = now.timeIntervalSince(startedAt)
        guard seconds >= 1 else { return nil }
        let rate = Double(done) / seconds
        guard rate > 0 else { return nil }
        return Double(total - done) / rate
    }

    /// `2,141 downloaded · 334 pending · 20 unavailable` -- kinds by count,
    /// ties in first-seen order. Empty when nothing arrived.
    public var summary: String {
        let ordered = kindOrder.enumerated().sorted { a, b in
            let ca = countsByKind[a.element] ?? 0, cb = countsByKind[b.element] ?? 0
            return ca == cb ? a.offset < b.offset : ca > cb
        }
        return ordered
            .map { "\(Self.grouped(countsByKind[$0.element] ?? 0)) \($0.element)" }
            .joined(separator: " · ")
    }

    private static let groupedFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        return f
    }()

    public static func grouped(_ n: Int) -> String {
        groupedFormatter.string(from: NSNumber(value: n)) ?? String(n)
    }
}
