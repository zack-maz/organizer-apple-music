//
// ScriptLocator.swift
//
// Where the .applescript files live. Order of preference: a folder the user
// pointed the app at (so edits in the repo are picked up without a rebuild),
// then the copies build.sh put in the bundle, then -- for `swift run` during
// development -- the nearest ancestor of the executable that holds the repo.
//

import Foundation

public struct ScriptLocator: Sendable {
    public enum Source: Equatable, Sendable {
        case override(URL)
        case bundled(URL)
        case repository(URL)
        case missing
    }

    public let source: Source

    public init(overridePath: String?, bundleResources: URL?, executable: URL?, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        let marker = ActionKind.buildGenres.scriptFile
        if let path = overridePath, !path.isEmpty, fileExists(path + "/" + marker) {
            source = .override(URL(fileURLWithPath: path, isDirectory: true))
        } else if let resources = bundleResources, fileExists(resources.appendingPathComponent("scripts/" + marker).path) {
            source = .bundled(resources.appendingPathComponent("scripts", isDirectory: true))
        } else if let root = Self.findRepository(above: executable, marker: marker, fileExists: fileExists) {
            source = .repository(root)
        } else {
            source = .missing
        }
    }

    public var directory: URL? {
        switch source {
        case .override(let u), .bundled(let u), .repository(let u): return u
        case .missing: return nil
        }
    }

    public func url(for kind: ActionKind) -> URL? {
        directory?.appendingPathComponent(kind.scriptFile)
    }

    /// Short text for the footer.
    public var description: String {
        switch source {
        case .override(let u): return u.path
        case .bundled: return "bundled with the app"
        case .repository(let u): return u.path + "  (repo)"
        case .missing: return "not found"
        }
    }

    private static func findRepository(above executable: URL?, marker: String, fileExists: (String) -> Bool) -> URL? {
        guard var dir = executable?.deletingLastPathComponent() else { return nil }
        for _ in 0..<8 {
            if fileExists(dir.appendingPathComponent(marker).path) { return dir }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }
}
