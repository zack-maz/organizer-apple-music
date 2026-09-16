import XCTest
@testable import OrganizerCore

final class ProgressProtocolTests: XCTestCase {
    private let t = "\t"

    func testWellFormedLines() {
        XCTAssertEqual(ProgressProtocol.parse("@@ begin\(t)total=2494\(t)unit=tracks"), .begin(total: 2494, unit: "tracks"))
        XCTAssertEqual(ProgressProtocol.parse("@@ end"), .end)
        let item = ProgressProtocol.parse("@@ item\(t)i=3\(t)of=100\(t)kind=downloaded\(t)playlist=hip-hop & rap\(t)artist=A Tribe Called Quest\(t)title=Can I Kick It?")
        XCTAssertEqual(item, .item(ProgressItem(index: 3, total: 100, kind: "downloaded", playlist: "hip-hop & rap",
                                                artist: "A Tribe Called Quest", title: "Can I Kick It?")))
    }

    func testSpaceSeparatedFormIsAcceptedWhenValuesHaveNoSpaces() {
        XCTAssertEqual(ProgressProtocol.parse("@@ begin total=5 unit=playlists"), .begin(total: 5, unit: "playlists"))
        XCTAssertEqual(ProgressProtocol.parse("@@ item i=1 of=5 kind=queued playlist=rock"),
                       .item(ProgressItem(index: 1, total: 5, kind: "queued", playlist: "rock")))
    }

    func testUncountedItemHasNoIndex() {
        let e = ProgressProtocol.parse("@@ item\(t)kind=created\(t)playlist=jazz\(t)title=12 tracks")
        XCTAssertEqual(e, .item(ProgressItem(index: nil, total: nil, kind: "created", playlist: "jazz", artist: "", title: "12 tracks")))
    }

    func testGarbageIsNotAnEvent() {
        XCTAssertNil(ProgressProtocol.parse("Reading library..."))
        XCTAssertNil(ProgressProtocol.parse("  hip-hop: 120/134"))
        XCTAssertNil(ProgressProtocol.parse(""))
        XCTAssertNil(ProgressProtocol.parse("@@"))
        XCTAssertNil(ProgressProtocol.parse("@@ "))
        XCTAssertNil(ProgressProtocol.parse("@@item i=1"))
        XCTAssertNil(ProgressProtocol.parse("@@ bogus\(t)i=1"))
        XCTAssertNil(ProgressProtocol.parse("email me @@ home"))
        // malformed fields are skipped, the event still parses
        XCTAssertEqual(ProgressProtocol.parse("@@ begin\(t)total=abc\(t)=x\(t)unit"), .begin(total: nil, unit: ""))
        XCTAssertEqual(ProgressProtocol.parse("@@ item\(t)i=notanumber\(t)kind=added"),
                       .item(ProgressItem(index: nil, total: nil, kind: "added")))
    }

    func testValuesMayContainEqualsAndUnicode() {
        let e = ProgressProtocol.parse("@@ item\(t)i=1\(t)of=2\(t)kind=added\(t)playlist=música mexicana\(t)artist=Björk\(t)title=E=MC² (feat. Sigur Rós)")
        guard case .item(let item)? = e else { return XCTFail("not an item: \(String(describing: e))") }
        XCTAssertEqual(item.playlist, "música mexicana")
        XCTAssertEqual(item.artist, "Björk")
        XCTAssertEqual(item.title, "E=MC² (feat. Sigur Rós)")
    }

    func testInterleavedWithHumanLogLines() {
        let stderr = [
            "Reading library...",
            "@@ begin\(t)total=3\(t)unit=tracks",
            "  hip-hop",
            "@@ item\(t)i=1\(t)of=3\(t)kind=added\(t)playlist=hip-hop\(t)artist=X\(t)title=Y",
            "    could not fill rock: -1728",
            "@@ item\(t)i=2\(t)of=3\(t)kind=added\(t)playlist=hip-hop\(t)artist=X\(t)title=Z",
            "@@ end",
            "Created 1 playlists holding 2 tracks in \"genres\".",
        ]
        var events: [ProgressEvent] = []
        var human: [String] = []
        for line in stderr {
            if let e = ProgressProtocol.parse(line) { events.append(e) } else { human.append(line) }
        }
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events.first, .begin(total: 3, unit: "tracks"))
        XCTAssertEqual(events.last, .end)
        XCTAssertEqual(human, ["Reading library...", "  hip-hop", "    could not fill rock: -1728",
                               "Created 1 playlists holding 2 tracks in \"genres\"."])
    }
}

final class ProgressStateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func item(_ i: Int?, _ kind: String, playlist: String = "p", title: String = "t") -> ProgressEvent {
        .item(ProgressItem(index: i, kind: kind, playlist: playlist, artist: "a", title: title))
    }

    func testCountsAndFraction() {
        var s = ProgressState(total: 10, unit: "tracks", at: t0)
        XCTAssertEqual(s.fraction, 0)
        XCTAssertEqual(s.summary, "")
        s.apply(item(1, "downloaded"), at: t0 + 1)
        s.apply(item(2, "downloaded"), at: t0 + 2)
        s.apply(item(3, "pending"), at: t0 + 3)
        XCTAssertEqual(s.done, 3)
        XCTAssertEqual(s.fraction, 0.3)
        XCTAssertEqual(s.countsByKind, ["downloaded": 2, "pending": 1])
        XCTAssertEqual(s.summary, "2 downloaded · 1 pending")
        XCTAssertFalse(s.ended)

        // an uncounted event: in the feed and the counts, not the bar
        s.apply(item(nil, "queued"), at: t0 + 4)
        XCTAssertEqual(s.done, 3)
        XCTAssertEqual(s.itemCount, 4)
        XCTAssertEqual(s.rows.count, 4)
        XCTAssertEqual(s.summary, "2 downloaded · 1 pending · 1 queued")

        s.apply(.end, at: t0 + 5)
        XCTAssertTrue(s.ended)
        XCTAssertEqual(s.elapsed(at: t0 + 60), 5)
        XCTAssertEqual(s.fraction, 0.3)
    }

    func testSummaryOrdersByCountThenFirstSeenAndGroupsThousands() {
        var s = ProgressState(total: nil, unit: "tracks", at: t0)
        for i in 1...20 { s.apply(item(i, "unavailable"), at: t0) }
        for i in 21...354 { s.apply(item(i, "pending"), at: t0) }
        for i in 355...2495 { s.apply(item(i, "downloaded"), at: t0) }
        s.apply(item(nil, "queued"), at: t0)
        s.apply(item(nil, "created"), at: t0)
        XCTAssertEqual(s.summary, "2,141 downloaded · 334 pending · 20 unavailable · 1 queued · 1 created")
    }

    func testTotalFromItemsAndUnknownTotal() {
        var s = ProgressState(total: nil, unit: "tracks", at: t0)
        XCTAssertNil(s.fraction)
        s.apply(.item(ProgressItem(index: 4, total: 8, kind: "added")), at: t0)
        XCTAssertEqual(s.total, 8)
        XCTAssertEqual(s.fraction, 0.5)
        var unknown = ProgressState(total: nil, unit: "", at: t0)
        unknown.finish(at: t0 + 1)
        XCTAssertEqual(unknown.fraction, 1)
        XCTAssertEqual(ProgressState(total: 0, unit: "tracks", at: t0).fraction, 1)
    }

    func testETAAppearsAfterAFewItemsAndUsesTheAverageRate() {
        var s = ProgressState(total: 20, unit: "tracks", at: t0)
        for i in 1...4 { s.apply(item(i, "downloaded"), at: t0 + Double(i)) }
        XCTAssertNil(s.eta(at: t0 + 4), "too few items")
        s.apply(item(5, "downloaded"), at: t0 + 10)
        // 5 done in 10 s -> 0.5/s -> 15 left -> 30 s
        XCTAssertEqual(s.eta(at: t0 + 10), 30)
        // a stall lengthens it
        XCTAssertEqual(s.eta(at: t0 + 20), 60)
        for i in 6...20 { s.apply(item(i, "downloaded"), at: t0 + 30) }
        XCTAssertNil(s.eta(at: t0 + 30), "complete")
        XCTAssertEqual(s.fraction, 1)
        var early = ProgressState(total: 20, unit: "tracks", at: t0)
        for i in 1...6 { early.apply(item(i, "x"), at: t0 + 0.1) }
        XCTAssertNil(early.eta(at: t0 + 0.5), "under a second in")
    }

    func testRowsAreCappedButCountsStayExact() {
        var s = ProgressState(total: 3000, unit: "tracks", at: t0)
        for i in 1...3000 { s.apply(item(i, "added", playlist: "p\(i / 100)"), at: t0) }
        XCTAssertLessThanOrEqual(s.rows.count, ProgressState.rowCap + ProgressState.rowCap / 10)
        XCTAssertGreaterThanOrEqual(s.rows.count, ProgressState.rowCap)
        XCTAssertEqual(s.rows.count + s.droppedRows, 3000)
        XCTAssertEqual(s.itemCount, 3000)
        XCTAssertEqual(s.done, 3000)
        XCTAssertEqual(s.countsByKind["added"], 3000)
        XCTAssertEqual(s.rows.last?.id, 2999)
    }

    func testGroupStartsWhenThePlaylistChanges() {
        var s = ProgressState(total: 4, unit: "tracks", at: t0)
        s.apply(item(1, "added", playlist: "jazz"), at: t0)
        s.apply(item(2, "added", playlist: "jazz"), at: t0)
        s.apply(item(3, "added", playlist: "blues"), at: t0)
        s.apply(item(nil, "created", playlist: "blues"), at: t0)
        XCTAssertEqual(s.rows.map(\.startsGroup), [true, false, true, false])
    }

    func testASecondBeginKeepsTheFeedAndRestartsTheBar() {
        var s = ProgressState(total: 2, unit: "playlists", at: t0)
        s.apply(item(1, "backed-up", playlist: "Road Trip"), at: t0 + 1)
        s.apply(item(2, "backed-up", playlist: "Focus"), at: t0 + 2)
        s.apply(.end, at: t0 + 2)
        s.apply(.begin(total: 100, unit: "tracks"), at: t0 + 5)
        XCTAssertEqual(s.total, 100)
        XCTAssertEqual(s.unit, "tracks")
        XCTAssertEqual(s.done, 0)
        XCTAssertFalse(s.ended)
        XCTAssertEqual(s.startedAt, t0 + 5)
        XCTAssertEqual(s.rows.count, 2)
        s.apply(item(1, "added", playlist: "Focus"), at: t0 + 6)
        XCTAssertTrue(s.rows.last!.startsGroup, "a new step starts a new group even for the same playlist")
        XCTAssertEqual(s.summary, "2 backed-up · 1 added")
    }
}

final class ProgressWatchTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)
    private let t = "\t"

    private func pending(_ id: String, playlist: String = "rock", artist: String = "A", title: String = "T") -> ProgressEvent {
        .item(ProgressItem(id: id, kind: "pending", playlist: playlist, artist: artist, title: title))
    }
    private func landed(_ i: Int, _ id: String, playlist: String = "rock") -> ProgressEvent {
        .item(ProgressItem(index: i, id: id, kind: "downloaded", playlist: playlist, artist: "A", title: "T"))
    }

    func testIDIsParsedAndBlankIDIsNone() {
        let e = ProgressProtocol.parse("@@ item\(t)i=1\(t)of=3\(t)kind=downloaded\(t)id=7F3A2C\(t)playlist=rock\(t)artist=A\(t)title=T")
        XCTAssertEqual(e, .item(ProgressItem(index: 1, total: 3, id: "7F3A2C", kind: "downloaded", playlist: "rock", artist: "A", title: "T")))
        let blank = ProgressProtocol.parse("@@ item\(t)kind=pending\(t)id=\(t)playlist=rock")
        XCTAssertEqual(blank, .item(ProgressItem(id: nil, kind: "pending", playlist: "rock")))
    }

    func testLaterItemWithSameIDUpdatesTheRowInPlace() {
        var s = ProgressState(total: 3, unit: "downloads", at: t0)
        s.apply(pending("a"), at: t0)
        s.apply(pending("b", playlist: "jazz"), at: t0)
        s.apply(pending("c", playlist: "jazz"), at: t0)
        XCTAssertEqual(s.rows.count, 3)
        XCTAssertEqual(s.countsByKind, ["pending": 3])
        XCTAssertEqual(s.done, 0)
        XCTAssertEqual(s.fraction, 0)

        XCTAssertEqual(s.changeCount, 3)
        XCTAssertEqual(s.lastChangedRowID, s.rows[2].id)
        s.apply(landed(1, "b", playlist: "jazz"), at: t0 + 30)
        XCTAssertEqual(s.rows.count, 3, "no new row")
        XCTAssertEqual(s.changeCount, 4)
        XCTAssertEqual(s.lastChangedRowID, s.rows[1].id, "the view follows the row that flipped")
        XCTAssertEqual(s.rows.map(\.kind), ["pending", "downloaded", "pending"])
        XCTAssertEqual(s.rows[1].trackID, "b")
        XCTAssertEqual(s.rows[1].revision, 1)
        XCTAssertEqual(s.rows[0].revision, 0)
        XCTAssertEqual(s.countsByKind, ["pending": 2, "downloaded": 1])
        XCTAssertEqual(s.done, 1)
        XCTAssertEqual(s.itemCount, 4)
        XCTAssertEqual(s.summary, "2 pending · 1 downloaded")

        // the same kind again is not a change: no flash, no count movement
        s.apply(pending("a"), at: t0 + 31)
        XCTAssertEqual(s.rows[0].revision, 0)
        XCTAssertEqual(s.countsByKind, ["pending": 2, "downloaded": 1])
        XCTAssertEqual(s.changeCount, 4, "a re-emitted pending row is not a change")

        // blank fields keep what the row had; filled ones replace
        s.apply(.item(ProgressItem(index: 2, id: "a", kind: "downloaded", playlist: "", artist: "", title: "Better Title")), at: t0 + 60)
        XCTAssertEqual(s.rows[0].kind, "downloaded")
        XCTAssertEqual(s.rows[0].playlist, "rock")
        XCTAssertEqual(s.rows[0].artist, "A")
        XCTAssertEqual(s.rows[0].title, "Better Title")
        XCTAssertEqual(s.rows[0].revision, 1)
    }

    func testItemsWithoutIDStillAppend() {
        var s = ProgressState(total: nil, unit: "tracks", at: t0)
        s.apply(.item(ProgressItem(index: 1, kind: "added", playlist: "p", title: "x")), at: t0)
        s.apply(.item(ProgressItem(index: 2, kind: "added", playlist: "p", title: "x")), at: t0)
        s.apply(.item(ProgressItem(kind: "queued", playlist: "p", title: "3 tracks")), at: t0)
        XCTAssertEqual(s.rows.count, 3)
        XCTAssertNil(s.rows[0].trackID)
    }

    func testWatchProgressMathAndETA() {
        var s = ProgressState(total: 677, unit: "downloads", at: t0)
        for n in 1...677 { s.apply(pending("id\(n)"), at: t0) }
        XCTAssertEqual(s.done, 0)
        XCTAssertEqual(s.fraction, 0)
        XCTAssertEqual(s.etaThreshold, 3)
        XCTAssertNil(s.eta(at: t0 + 30))
        XCTAssertEqual(s.elapsed(at: t0 + 30), 30, "elapsed ticks while nothing has landed")

        s.apply(landed(1, "id5"), at: t0 + 30)
        s.apply(landed(2, "id9"), at: t0 + 60)
        XCTAssertNil(s.eta(at: t0 + 60), "two flips: no rate yet")
        s.apply(landed(3, "id2"), at: t0 + 90)
        XCTAssertEqual(s.done, 3)
        XCTAssertEqual(s.fraction!, 3.0 / 677.0, accuracy: 1e-9)
        // 3 in 90 s -> 674 left at 1/30 s each -> 20,220 s
        XCTAssertEqual(s.eta(at: t0 + 90)!, 20_220, accuracy: 0.5)
        XCTAssertEqual(s.countsByKind, ["pending": 674, "downloaded": 3])
        XCTAssertEqual(s.rows.count, 677, "flips did not add rows")
        XCTAssertEqual(s.summary, "674 pending · 3 downloaded")

        // other units keep the higher threshold
        XCTAssertEqual(ProgressState(total: 10, unit: "tracks", at: t0).etaThreshold, 5)
    }

    func testUpsertSurvivesTheRowCap() {
        var s = ProgressState(total: 3000, unit: "downloads", at: t0)
        for n in 1...3000 { s.apply(pending("id\(n)"), at: t0) }
        XCTAssertGreaterThan(s.droppedRows, 0)
        // a dropped row's id is forgotten: its flip appends a fresh row
        let before = s.rows.count
        s.apply(landed(1, "id1"), at: t0 + 1)
        XCTAssertEqual(s.rows.count, before + 1)
        XCTAssertEqual(s.rows.last?.trackID, "id1")
        // a kept row's id still updates in place
        s.apply(landed(2, "id3000"), at: t0 + 2)
        XCTAssertEqual(s.rows.count, before + 1)
        XCTAssertEqual(s.rows.first { $0.trackID == "id3000" }?.kind, "downloaded")
        XCTAssertEqual(s.done, 2)
    }

    func testWatchFollowsAQueueInTheSameJob() {
        // download-genres reported the same tracks with ids; the watcher's
        // pending items land on those rows, and its begin restarts the bar
        var s = ProgressState(total: 3, unit: "tracks", at: t0)
        s.apply(.item(ProgressItem(index: 1, id: "a", kind: "downloaded", playlist: "rock", title: "x")), at: t0)
        s.apply(.item(ProgressItem(index: 2, id: "b", kind: "pending", playlist: "rock", title: "y")), at: t0)
        s.apply(.item(ProgressItem(index: 3, id: "c", kind: "pending", playlist: "rock", title: "z")), at: t0)
        s.apply(.item(ProgressItem(kind: "queued", playlist: "rock", title: "2 tracks")), at: t0)
        s.apply(.end, at: t0)
        s.apply(.begin(total: 2, unit: "downloads"), at: t0 + 5)
        s.apply(pending("b"), at: t0 + 5)
        s.apply(pending("c"), at: t0 + 5)
        XCTAssertEqual(s.rows.count, 4)
        XCTAssertEqual(s.total, 2)
        XCTAssertEqual(s.done, 0)
        s.apply(landed(1, "c"), at: t0 + 40)
        XCTAssertEqual(s.rows.map(\.kind), ["downloaded", "pending", "downloaded", "queued"])
        XCTAssertEqual(s.fraction, 0.5)
        XCTAssertEqual(s.summary, "2 downloaded · 1 pending · 1 queued")
    }
}
