import XCTest
@testable import OrganizerCore

final class ScriptLocatorTests: XCTestCase {
    func testOverrideWinsWhenItHoldsTheScripts() {
        let l = ScriptLocator(overridePath: "/repo", bundleResources: URL(fileURLWithPath: "/App/Resources"), executable: nil,
                              fileExists: { $0 == "/repo/build-genres.applescript" })
        XCTAssertEqual(l.source, .override(URL(fileURLWithPath: "/repo", isDirectory: true)))
        XCTAssertEqual(l.url(for: .whatsNew)?.path, "/repo/whats-new.applescript")
    }

    func testFallsBackToBundleThenRepository() {
        let bundled = ScriptLocator(overridePath: "/nowhere", bundleResources: URL(fileURLWithPath: "/App/Resources"), executable: nil,
                                    fileExists: { $0 == "/App/Resources/scripts/build-genres.applescript" })
        XCTAssertEqual(bundled.url(for: .buildGenres)?.path, "/App/Resources/scripts/build-genres.applescript")

        let repo = ScriptLocator(overridePath: nil, bundleResources: nil, executable: URL(fileURLWithPath: "/repo/app/.build/debug/Organizer"),
                                 fileExists: { $0 == "/repo/build-genres.applescript" })
        XCTAssertEqual(repo.directory?.path, "/repo")
        XCTAssertEqual(repo.description, "/repo  (repo)")

        let none = ScriptLocator(overridePath: nil, bundleResources: nil, executable: nil, fileExists: { _ in false })
        XCTAssertEqual(none.source, .missing)
        XCTAssertNil(none.url(for: .buildGenres))
    }
}
