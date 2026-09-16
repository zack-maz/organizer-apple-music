//
// Theme.swift
//
// The brand tokens from BRAND/website/design/System.dc.html, translated to
// SwiftUI. Dark only. Zima is the one accent and is rationed to a single thing
// per view -- the running indicator or the confirm button, never both.
//

import SwiftUI
import AppKit

enum Palette {
    static let void = Color(hex: 0x0A0A0A)      // window ground
    static let panel = Color(hex: 0x0D0F12)     // raised surfaces: the console
    static let hairline = Color(hex: 0x1E2227)  // rules, never boxes
    static let muted = Color(hex: 0x7C848D)     // labels, metadata
    static let text = Color(hex: 0xC9CDD2)      // body
    static let bright = Color(hex: 0xE8EBED)    // headings, active row
    static let zima = Color(hex: 0x7AA2F7)      // the accent, once per view
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Instrument Sans + JetBrains Mono when installed, otherwise the system font
/// and Menlo with the same sizes and tracking. Nothing is downloaded.
enum Typeface {
    static let sansFamily: String? = firstInstalled(["Instrument Sans", "InstrumentSans"])
    static let monoFamily: String? = firstInstalled([
        "JetBrains Mono", "JetBrainsMono Nerd Font Mono", "JetBrainsMono Nerd Font",
        "JetBrainsMonoNL Nerd Font Mono", "JetBrainsMono NFM",
    ])

    static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let family = sansFamily { return .custom(family, size: size).weight(weight) }
        return .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let family = monoFamily { return .custom(family, size: size).weight(weight) }
        return .custom("Menlo", size: size).weight(weight)
    }

    private static func firstInstalled(_ families: [String]) -> String? {
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        return families.first(where: installed.contains)
    }
}

/// Type roles from the system, so views name the role rather than the size.
extension Text {
    /// "Label": mono, 11pt, uppercase, tracked 0.08em. Short strings only.
    func label(_ color: Color = Palette.muted) -> some View {
        self.font(Typeface.mono(11)).textCase(.uppercase).tracking(0.88).foregroundStyle(color)
    }

    /// "Small": 15pt, the size for names, navigation and metadata values.
    func small(_ color: Color = Palette.text, weight: Font.Weight = .regular) -> Text {
        self.font(Typeface.text(15, weight: weight)).foregroundColor(color)
    }

    /// Secondary body, 13pt.
    func caption(_ color: Color = Palette.muted) -> Text {
        self.font(Typeface.text(13)).foregroundColor(color)
    }

    /// "Title": large, light, tight -- the overview numbers.
    func title(_ color: Color = Palette.bright) -> some View {
        self.font(Typeface.text(36, weight: .medium)).tracking(-0.54).foregroundStyle(color)
    }
}

/// A 1pt rule in Hairline. The system draws rules, not boxes.
struct Hairline: View {
    enum Axis { case horizontal, vertical }
    var axis: Axis = .horizontal

    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(width: axis == .vertical ? 1 : nil, height: axis == .horizontal ? 1 : nil)
    }
}
