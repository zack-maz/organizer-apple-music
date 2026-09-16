import XCTest
@testable import OrganizerCore

/// Runs a throwaway script through the real osascript. It never mentions
/// Music, so it needs no permissions -- it only checks that `log` lines arrive
/// on stderr as they happen and the return value on stdout at the end.
final class ScriptRunnerTests: XCTestCase {
    private func writeScript(_ body: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("organizer-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("probe.applescript")
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testStreamsLogsThenReturnValue() async throws {
        let url = try writeScript("""
        on run argv
            log "first " & (item 1 of argv)
            log "second"
            return "result" & linefeed & "{\\"library\\":3,\\"filed\\":2,\\"playlists\\":1,\\"folders\\":0,\\"unfiled\\":1}"
        end run
        """)
        var lines: [OutputLine] = []
        var exit: (Int32, Bool)?
        for await event in ScriptRunner().run(script: url, arguments: ["arg"]) {
            switch event {
            case .started: break
            case .line(let l): lines.append(l)
            case .exited(let status, let stopped): exit = (status, stopped)
            }
        }
        XCTAssertEqual(exit?.0, 0)
        XCTAssertEqual(exit?.1, false)
        XCTAssertEqual(lines.filter { $0.channel == .stderr }.map(\.text), ["first arg", "second"])
        let stdout = lines.filter { $0.channel == .stdout }.map(\.text).joined(separator: "\n")
        XCTAssertEqual(OutputParser.decode(WhatsNewSummary.self, from: stdout)?.unfiled, 1)
    }

    func testStopTerminatesALongScript() async throws {
        let url = try writeScript("""
        on run argv
            log "sleeping"
            delay 30
            return "never"
        end run
        """)
        let runner = ScriptRunner()
        var exit: (Int32, Bool)?
        let started = Date()
        for await event in runner.run(script: url, arguments: []) {
            switch event {
            case .line(let l) where l.text == "sleeping": runner.stop()
            case .exited(let status, let stopped): exit = (status, stopped)
            default: break
            }
        }
        XCTAssertNotNil(exit)
        XCTAssertEqual(exit?.1, true)
        XCTAssertNotEqual(exit?.0, 0)
        XCTAssertLessThan(Date().timeIntervalSince(started), 20)
    }

    func testMissingScriptExitsNonZero() async {
        var exit: Int32?
        for await event in ScriptRunner().run(script: URL(fileURLWithPath: "/nonexistent/x.applescript"), arguments: []) {
            if case .exited(let status, _) = event { exit = status }
        }
        XCTAssertNotEqual(exit, 0)
    }
}
