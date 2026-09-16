//
// OutputParser.swift
//
// Reads what the scripts print. The human report is shown verbatim in the
// console; the only structure the app relies on is the trailing JSON line that
// `--json` adds, and the -1743 error text that means Automation was denied.
//

import Foundation

/// The numbers STATE.md tracks by hand, from one read-only pass.
public struct LibraryOverview: Equatable, Sendable {
    public var tracks: Int?
    public var filed: Int?
    public var unfiled: Int?
    public var playlists: Int?
    public var folders: Int?
    public var duplicateRows: Int?

    public init(tracks: Int? = nil, filed: Int? = nil, unfiled: Int? = nil,
                playlists: Int? = nil, folders: Int? = nil, duplicateRows: Int? = nil) {
        self.tracks = tracks
        self.filed = filed
        self.unfiled = unfiled
        self.playlists = playlists
        self.folders = folders
        self.duplicateRows = duplicateRows
    }

    /// Combines the two summaries; either may be missing if its script failed.
    public static func merge(whatsNew: WhatsNewSummary?, dedupe: DedupeSummary?) -> LibraryOverview {
        LibraryOverview(
            tracks: whatsNew?.library ?? dedupe?.library,
            filed: whatsNew?.filed,
            unfiled: whatsNew?.unfiled,
            playlists: whatsNew?.playlists ?? dedupe?.playlists,
            folders: whatsNew?.folders,
            duplicateRows: dedupe?.duplicates
        )
    }
}

/// `whats-new --json`.
public struct WhatsNewSummary: Codable, Equatable, Sendable {
    public var library: Int
    public var filed: Int
    public var playlists: Int
    public var folders: Int
    public var unfiled: Int
}

/// `dedupe-playlists --dry-run --json`.
public struct DedupeSummary: Codable, Equatable, Sendable {
    public var library: Int
    public var playlists: Int
    public var rows: Int
    public var distinct: Int
    public var duplicates: Int
    public var touched: Int
}

public enum OutputParser {
    /// The last non-empty line of stdout, if it looks like a JSON object.
    /// Anything else -- no JSON, JSON that is not last -- yields nil.
    public static func trailingJSONLine(in stdout: String) -> String? {
        let last = stdout
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last { !$0.isEmpty }
        guard let line = last, line.hasPrefix("{"), line.hasSuffix("}") else { return nil }
        return line
    }

    public static func decode<T: Decodable>(_ type: T.Type, from stdout: String) -> T? {
        guard let line = trailingJSONLine(in: stdout), let data = line.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// download-genres ends its real run with `Queued N playlists for
    /// download.`; nil on a dry run or a failure. Decides whether the app
    /// starts watching.
    public static func queuedPlaylists(in stdout: String) -> Int? {
        for line in stdout.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("Queued "), t.hasSuffix(" for download.") else { continue }
            let middle = t.dropFirst("Queued ".count).dropLast(" for download.".count)
            if let n = Int(middle.split(separator: " ").first ?? "") { return n }
        }
        return nil
    }

    /// osascript reports a denied Automation permission as
    /// `execution error: Not authorized to send Apple events to Music. (-1743)`.
    public static func indicatesAutomationDenied(_ line: String) -> Bool {
        line.contains("-1743") || line.localizedCaseInsensitiveContains("not authorized to send apple events")
    }
}

/// Splits a byte stream into lines as chunks arrive, holding back a partial
/// last line until the next chunk or a final flush. Tolerates CRLF.
public struct LineBuffer: Sendable {
    private var pending = Data()

    public init() {}

    /// Appends a chunk and returns every line it completed, newline stripped.
    public mutating func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let nl = pending.firstIndex(of: 0x0A) {
            let lineData = pending[pending.startIndex..<nl]
            lines.append(Self.decode(lineData))
            pending.removeSubrange(pending.startIndex...nl)
        }
        return lines
    }

    /// The unterminated remainder, if any, at end of stream.
    public mutating func flush() -> String? {
        guard !pending.isEmpty else { return nil }
        let rest = Self.decode(pending)
        pending.removeAll()
        return rest
    }

    private static func decode(_ data: Data) -> String {
        var text = String(decoding: data, as: UTF8.self)
        if text.hasSuffix("\r") { text.removeLast() }
        return text
    }
}
