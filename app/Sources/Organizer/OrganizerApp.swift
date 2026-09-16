//
// OrganizerApp.swift
//
// One window. Dark appearance is forced because the brand is dark only.
//

import SwiftUI
import AppKit

@main
struct OrganizerApp: App {
    @StateObject private var model = AppModel()

    init() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }

    var body: some Scene {
        WindowGroup("Organizer") {
            RootView()
                .environmentObject(model)
                .onAppear { model.handleLaunchArguments(CommandLine.arguments) }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1240, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// Reaches the NSWindow behind the SwiftUI view to set the ground colour and
/// let the window be dragged by its background, since the title bar is hidden.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView.window)
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Palette.void)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        // No field should start focused; the console is the thing to look at.
        DispatchQueue.main.async { window.makeFirstResponder(nil) }
    }
}
