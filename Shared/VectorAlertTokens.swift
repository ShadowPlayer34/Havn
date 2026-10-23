import SwiftUI

// Design tokens from VectorAlert.dc.html · option 1d "Design language · tokens and components".
// One accent per meaning, pitch black canvas for OLED, no siren graphics.

extension Color {
    nonisolated init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

nonisolated enum VA {
    /// #FF3B30 · immediate risk
    static let red = Color(hex: 0xFF3B30)
    /// #FF9500 · predicted
    static let orange = Color(hex: 0xFF9500)
    /// #34C759 · clear
    static let green = Color(hex: 0x34C759)
    /// #32ADE6 · interactive
    static let cyan = Color(hex: 0x32ADE6)
    /// #FFCC00 · people's ratings — kept off orange, which already means "caveat"
    static let yellow = Color(hex: 0xFFCC00)

    /// #000000 · OLED canvas
    static let canvas = Color.black
    /// #1C1C1E
    static let card = Color(hex: 0x1C1C1E)
    /// #2C2C2E
    static let elevated = Color(hex: 0x2C2C2E)
    /// Map base beneath every overlay
    static let mapBase = Color(hex: 0x0A0B0D)

    static let label = Color.white
    /// rgba(235,235,245,.6)
    static func secondary(_ opacity: Double = 0.6) -> Color { Color(hex: 0xEBEBF5, opacity: opacity) }

    // Accent shades used for text on tinted glass
    static let redText = Color(hex: 0xFF8B84)
    static let orangeText = Color(hex: 0xFFB65C)
    static let cyanText = Color(hex: 0x9FDCFA)
    static let greenText = Color(hex: 0x8FE9A8)
    static let cyanInk = Color(hex: 0x00131E)
}

nonisolated enum VAFont {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Window · 40/700 rounded
    static let window = rounded(40)
    /// Title · 24/600
    static let title = display(24)
    /// Body · 15/400
    static let body = display(15, .regular)
    /// Caption · 11/500
    static let caption = display(11, .medium)
    /// Data · 11.5 mono
    static let data = mono(11.5)
}

extension View {
    /// CSS letter-spacing expressed in em, applied at a given point size.
    func tracking(em: CGFloat, size: CGFloat) -> some View {
        tracking(em * size)
    }

    /// CSS `line-height` as a multiple. SwiftUI's line spacing is the gap *between* lines,
    /// so the font's own leading (≈1.2 × size for SF) comes off first.
    func lineHeight(_ multiple: CGFloat, size: CGFloat) -> some View {
        lineSpacing(max(0, size * (multiple - 1.2)))
    }
}
