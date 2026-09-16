import XCTest
@testable import OrganizerCore

final class ArgumentsTests: XCTestCase {
    private let fixedDate: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 9; c.day = 16; c.hour = 12; c.minute = 1; c.second = 2
        c.timeZone = TimeZone.current
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    func testBuildGenresDefaultsToIncremental() {
        var o = ActionOptions()
        XCTAssertFalse(o.replace)
        XCTAssertEqual(Arguments.build(.buildGenres, options: o, dryRun: true), ["--dry-run"])
        XCTAssertEqual(Arguments.build(.buildGenres, options: o, dryRun: false), [])
        o.replace = true
        XCTAssertEqual(Arguments.build(.buildGenres, options: o, dryRun: true), ["--dry-run", "--replace"])
        XCTAssertEqual(Arguments.build(.buildGenres, options: o, dryRun: false), ["--replace"])
    }

    func testBackupIsOfferedOnlyForTheReplacePath() {
        XCTAssertTrue(ScriptInvocation(kind: .buildGenres, arguments: ["--replace"]).replacesFolder)
        XCTAssertFalse(ScriptInvocation(kind: .buildGenres, arguments: []).replacesFolder)
        XCTAssertFalse(ScriptInvocation(kind: .dedupePlaylists, arguments: ["--replace"]).replacesFolder)
    }

    func testBuildGenresConfirmCopyFollowsTheMode() {
        XCTAssertTrue(ActionKind.buildGenres.confirmMessage(for: ["--replace"]).contains("deletes the existing genre folder"))
        XCTAssertTrue(ActionKind.buildGenres.confirmMessage(for: []).contains("Nothing existing is removed"))
        XCTAssertTrue(ActionKind.dedupePlaylists.confirmMessage(for: []).contains("duplicate rows"))
        XCTAssertEqual(ActionKind.whatsNew.confirmMessage(for: []), "")
    }

    func testBuildGenresCustomOptions() {
        var o = ActionOptions()
        o.folder = "mine"
        o.minTracks = 3
        XCTAssertEqual(Arguments.build(.buildGenres, options: o, dryRun: false), ["--folder", "mine", "--min-tracks", "3"])
    }

    func testDefaultFolderAndMinTracksAreOmitted() {
        var o = ActionOptions()
        o.folder = " genres "
        o.minTracks = 1
        XCTAssertEqual(Arguments.build(.dedupePlaylists, options: o, dryRun: false), [])
    }

    func testWhatsNewNeverTakesDryRun() {
        var o = ActionOptions()
        XCTAssertEqual(Arguments.build(.whatsNew, options: o, dryRun: true), [])
        o.days = 30
        o.showAll = true
        o.folder = "x"
        XCTAssertEqual(Arguments.build(.whatsNew, options: o, dryRun: false), ["--days", "30", "--all", "--folder", "x"])
    }

    func testDedupeAndDownloads() {
        var o = ActionOptions()
        XCTAssertEqual(Arguments.build(.dedupePlaylists, options: o, dryRun: true), ["--dry-run"])
        XCTAssertEqual(Arguments.build(.downloadReport, options: o, dryRun: true), [])
        XCTAssertEqual(Arguments.build(.downloadGenres, options: o, dryRun: true), ["--dry-run"])
        o.folder = "y"
        XCTAssertEqual(Arguments.build(.downloadGenres, options: o, dryRun: false), ["--folder", "y"])
        XCTAssertEqual(Arguments.build(.downloadReport, options: o, dryRun: false), ["--folder", "y"])
    }

    func testWatchDownloadsIsReadOnlyAndTakesAnInterval() {
        var o = ActionOptions()
        XCTAssertFalse(ActionKind.watchDownloads.isDestructive)
        XCTAssertEqual(ActionKind.watchDownloads.group, .downloads)
        XCTAssertEqual(Arguments.build(.watchDownloads, options: o, dryRun: true), [])
        o.watchInterval = 10
        o.folder = "g"
        XCTAssertEqual(Arguments.build(.watchDownloads, options: o, dryRun: false), ["--folder", "g", "--interval", "10"])
        o.watchInterval = 0
        XCTAssertEqual(Arguments.build(.watchDownloads, options: o, dryRun: false), ["--folder", "g"])
    }

    func testMarkUnavailableName() {
        var o = ActionOptions()
        XCTAssertEqual(Arguments.build(.markUnavailable, options: o, dryRun: true), ["--dry-run"])
        o.unavailableName = "never coming"
        XCTAssertEqual(Arguments.build(.markUnavailable, options: o, dryRun: false), ["--name", "never coming"])
        o.unavailableName = "   "
        XCTAssertEqual(Arguments.build(.markUnavailable, options: o, dryRun: false), [])
    }

    func testBackupGetsAStampedDirectory() {
        var o = ActionOptions()
        o.backupsRoot = "/Users/me/repo/backups/"
        XCTAssertEqual(Arguments.build(.backupPlaylists, options: o, dryRun: true, now: fixedDate),
                       ["/Users/me/repo/backups/playlists-20260916-120102"])
    }

    func testRestorePreviewAndReal() {
        var o = ActionOptions()
        o.restoreDirectory = "/b/playlists-20260905-141540"
        o.restoreNames = " Road Trip, Focus ,, "
        XCTAssertEqual(Arguments.build(.restorePlaylists, options: o, dryRun: true),
                       ["--dry-run", "/b/playlists-20260905-141540", "Road Trip", "Focus"])
        o.restoreNames = ""
        XCTAssertEqual(Arguments.build(.restorePlaylists, options: o, dryRun: false), ["/b/playlists-20260905-141540"])
    }

    func testRefreshIsReadOnlyAndAsksForJSON() {
        var o = ActionOptions()
        XCTAssertEqual(Arguments.refreshInvocations(options: o), [
            ScriptInvocation(kind: .whatsNew, arguments: ["--json"]),
            ScriptInvocation(kind: .dedupePlaylists, arguments: ["--dry-run", "--json"]),
        ])
        o.folder = "g2"
        XCTAssertEqual(Arguments.refreshInvocations(options: o).map(\.arguments),
                       [["--folder", "g2", "--json"], ["--dry-run", "--folder", "g2", "--json"]])
    }

    func testCommandLineQuotesSpaces() {
        let inv = ScriptInvocation(kind: .restorePlaylists, arguments: ["--dry-run", "/b/x", "Road Trip"])
        XCTAssertEqual(inv.commandLine, "$ osascript restore-playlists.applescript --dry-run /b/x \"Road Trip\"")
    }

    func testEveryKindBelongsToExactlyOneGroup() {
        let grouped = ActionGroup.allCases.flatMap(\.kinds)
        XCTAssertEqual(Set(grouped), Set(ActionKind.allCases))
        XCTAssertEqual(grouped.count, ActionKind.allCases.count)
    }
}
