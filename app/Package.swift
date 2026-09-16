// swift-tools-version:5.9
//
// Organizer -- a native macOS front end for the AppleScript tools in this repo.
//
// Two targets: OrganizerCore holds everything that can be unit-tested without
// Music.app (argument building, output parsing, the osascript process wrapper);
// Organizer is the SwiftUI app. build.sh turns the executable into a .app.
//
import PackageDescription

let package = Package(
    name: "Organizer",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "OrganizerCore"),
        .executableTarget(name: "Organizer", dependencies: ["OrganizerCore"]),
        .testTarget(name: "OrganizerCoreTests", dependencies: ["OrganizerCore"]),
    ]
)
