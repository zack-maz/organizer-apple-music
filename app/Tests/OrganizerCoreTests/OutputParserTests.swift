import XCTest
@testable import OrganizerCore

final class OutputParserTests: XCTestCase {
    func testTrailingJSONIsTheLastNonEmptyLine() {
        let out = """
        Library:        2494 tracks
        Filed in "genres": 2494 tracks across 84 playlists

        Everything in the library is filed. Nothing new since the last rebuild.
        {"library":2494,"filed":2494,"playlists":84,"folders":13,"unfiled":0}

        """
        XCTAssertEqual(OutputParser.trailingJSONLine(in: out),
                       "{\"library\":2494,\"filed\":2494,\"playlists\":84,\"folders\":13,\"unfiled\":0}")
        let summary = OutputParser.decode(WhatsNewSummary.self, from: out)
        XCTAssertEqual(summary, WhatsNewSummary(library: 2494, filed: 2494, playlists: 84, folders: 13, unfiled: 0))
    }

    func testNoJSONWhenAbsentOrNotLast() {
        XCTAssertNil(OutputParser.trailingJSONLine(in: "Library: 12 tracks\n"))
        XCTAssertNil(OutputParser.trailingJSONLine(in: "{\"a\":1}\nDRY RUN - would remove 0 rows\n"))
        XCTAssertNil(OutputParser.trailingJSONLine(in: ""))
        XCTAssertNil(OutputParser.decode(DedupeSummary.self, from: "{\"library\":\"oops\"}"))
    }

    func testDedupeSummaryAndMerge() {
        let dedupe = "  hip-hop: 120 -> 60   (removing 60)\n\nDRY RUN - would remove 60 duplicate rows from 1 of 84 playlists.\nLibrary tracks: 2494 before, 2494 after.\n{\"library\":2494,\"playlists\":84,\"rows\":2554,\"distinct\":2494,\"duplicates\":60,\"touched\":1}\n"
        let d = OutputParser.decode(DedupeSummary.self, from: dedupe)
        XCTAssertEqual(d?.duplicates, 60)
        let merged = LibraryOverview.merge(whatsNew: nil, dedupe: d)
        XCTAssertEqual(merged, LibraryOverview(tracks: 2494, filed: nil, unfiled: nil, playlists: 84, folders: nil, duplicateRows: 60))

        let w = WhatsNewSummary(library: 2500, filed: 2494, playlists: 84, folders: 13, unfiled: 6)
        XCTAssertEqual(LibraryOverview.merge(whatsNew: w, dedupe: d),
                       LibraryOverview(tracks: 2500, filed: 2494, unfiled: 6, playlists: 84, folders: 13, duplicateRows: 60))
    }

    func testAutomationDeniedDetection() {
        XCTAssertTrue(OutputParser.indicatesAutomationDenied("build-genres.applescript:1234:1250: execution error: Not authorized to send Apple events to Music. (-1743)"))
        XCTAssertTrue(OutputParser.indicatesAutomationDenied("error (-1743)"))
        XCTAssertFalse(OutputParser.indicatesAutomationDenied("Reading library..."))
    }

    func testLineBufferSplitsAcrossChunksAndHandlesCRLF() {
        var b = LineBuffer()
        XCTAssertEqual(b.append(Data("Reading lib".utf8)), [])
        XCTAssertEqual(b.append(Data("rary...\n  hip-hop\r\n  ro".utf8)), ["Reading library...", "  hip-hop"])
        XCTAssertEqual(b.append(Data("ck\n\n".utf8)), ["  rock", ""])
        XCTAssertNil(b.flush())
        XCTAssertEqual(b.append(Data("tail".utf8)), [])
        XCTAssertEqual(b.flush(), "tail")
        XCTAssertNil(b.flush())
    }

    func testLineBufferKeepsUTF8Intact() {
        var b = LineBuffer()
        let bytes = Array("música mexicana\n".utf8)
        XCTAssertEqual(b.append(Data(bytes[0..<3])), [])
        XCTAssertEqual(b.append(Data(bytes[3...])), ["música mexicana"])
    }
}

final class QueuedPlaylistsTests: XCTestCase {
    func testQueuedCountFromARealRun() {
        let out = "  rock: 10/137\n\nDownloaded:  1798 of 2495\nPending:     677\nUnavailable: 20  (pulled from the catalogue - these can never download)\nQueued 44 playlists for download.\n"
        XCTAssertEqual(OutputParser.queuedPlaylists(in: out), 44)
        XCTAssertEqual(OutputParser.queuedPlaylists(in: "Queued 0 playlists for download."), 0)
    }

    func testNoQueuedCountOnDryRunOrFailure() {
        XCTAssertNil(OutputParser.queuedPlaylists(in: "Downloaded:  1 of 2\nDRY RUN - nothing queued.\n"))
        XCTAssertNil(OutputParser.queuedPlaylists(in: ""))
        XCTAssertNil(OutputParser.queuedPlaylists(in: "Queued x playlists for download."))
    }
}
