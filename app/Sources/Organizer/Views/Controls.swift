//
// Controls.swift
//
// Buttons, toggles and fields drawn in the brand rather than AppKit's defaults:
// hairline borders, mono labels, Bright on hover. The primary button is the
// one place a view may spend its Zima.
//

import SwiftUI
import AppKit

struct HairlineButtonStyle: ButtonStyle {
    enum Role { case quiet, primary }
    var role: Role = .quiet

    func makeBody(configuration: Configuration) -> some View {
        HairlineButtonBody(configuration: configuration, role: role)
    }
}

private struct HairlineButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let role: HairlineButtonStyle.Role
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(Typeface.mono(11, weight: .medium))
            .textCase(.uppercase)
            .tracking(0.88)
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(role == .primary ? Palette.zima : Color.clear)
            .overlay(Rectangle().stroke(border, lineWidth: 1))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.35)
            .onHover { hovering = $0 }
    }

    private var foreground: Color {
        switch role {
        case .primary: return Palette.void
        case .quiet: return (hovering || configuration.isPressed) && isEnabled ? Palette.bright : Palette.text
        }
    }

    private var border: Color {
        switch role {
        case .primary: return Palette.zima
        case .quiet: return (hovering || configuration.isPressed) && isEnabled ? Palette.muted : Palette.hairline
        }
    }
}

/// A mono label with a rule under it when selected: the Actions / Docs switch
/// and the console's feed / log switch. Bright when selected, Text on hover.
struct LabelTab: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(title).label(selected ? Palette.bright : (hovering ? Palette.text : Palette.muted))
                Rectangle()
                    .fill(selected ? Palette.bright : Color.clear)
                    .frame(height: 1)
            }
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A 10pt square that fills Bright when on; the label sits beside it.
struct SquareToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(configuration.isOn ? Palette.bright : Color.clear)
                    .frame(width: 10, height: 10)
                    .overlay(Rectangle().stroke(configuration.isOn ? Palette.bright : Palette.muted, lineWidth: 1))
                configuration.label
                    .font(Typeface.text(13))
                    .foregroundStyle(Palette.text)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// `label  value` with a hairline under the value. Text and number variants.
struct OptionField: View {
    let label: String
    @Binding var text: String
    var width: CGFloat = 96

    var body: some View {
        HStack(spacing: 8) {
            Text(label).label().fixedSize()
            VStack(spacing: 3) {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.leading)
                    .font(Typeface.mono(12))
                    .foregroundStyle(Palette.bright)
                Hairline()
            }
            .frame(width: width)
        }
    }
}

struct OptionNumberField: View {
    let label: String
    @Binding var value: Int
    var width: CGFloat = 40

    var body: some View {
        HStack(spacing: 8) {
            Text(label).label().fixedSize()
            VStack(spacing: 3) {
                TextField("", value: $value, format: .number)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.leading)
                    .font(Typeface.mono(12))
                    .foregroundStyle(Palette.bright)
                Hairline()
            }
            .frame(width: width)
        }
    }
}

/// The Zima square that marks the running job. Pulses unless Reduce Motion.
struct RunningMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        Rectangle()
            .fill(Palette.zima)
            .frame(width: 10, height: 10)
            .opacity(dim ? 0.35 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

enum Panels {
    /// Folder picker; returns nil when cancelled.
    @MainActor static func chooseDirectory(title: String, startingAt: String? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let start = startingAt, !start.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: start, isDirectory: true)
        }
        return panel.runModal() == .OK ? panel.url : nil
    }
}
