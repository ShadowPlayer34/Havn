import SwiftUI

// Floating chrome uses the system's Liquid Glass as-is. The design document draws a hairline
// rim, a specular top edge and a drop shadow on every surface because CSS has no glass to
// call on — iOS 26 draws all three itself, so the only thing worth carrying over is the tint,
// which is what makes an accent mean something.

extension View {
    func vaGlass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glassEffect(glass, in: shape)
    }
}

// MARK: - Motion

// The document's `vaSweep` breathing on the heat bands has no equivalent here: the wash is
// map content now, and MapKit overlays are not animatable views. The live indicators below
// still blink, and the countdown still ticks.

/// `vaBlink` — opacity 1 → .25 → 1, ease-in-out, infinite.
struct BlinkMotion: ViewModifier {
    let duration: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion ? 1 : (dim ? 0.25 : 1))
            .animation(
                reduceMotion ? nil : .easeInOut(duration: duration / 2).repeatForever(autoreverses: true),
                value: dim
            )
            .onAppear { dim = true }
    }
}

extension View {
    func blink(_ duration: Double) -> some View { modifier(BlinkMotion(duration: duration)) }
}

// MARK: - Shared chrome

/// Status pill: a coloured dot on a tinted surface — "1 Active Threat", "Sector clear".
/// Inline content rather than floating chrome, so it stays a flat tint, not glass.
struct StatusPill<Content: View>: View {
    var dot: Color
    var blinkDuration: Double?
    var tint: Color
    var stroke: Color
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(dot)
                .frame(width: 7, height: 7)
                .modifier(OptionalBlink(duration: blinkDuration))
            content
        }
        .padding(.leading, 10)
        .padding(.trailing, 13)
        .padding(.vertical, 6)
        .background(Capsule().fill(tint))
        .overlay(Capsule().strokeBorder(stroke, lineWidth: 0.5))
    }
}

private struct OptionalBlink: ViewModifier {
    let duration: Double?
    func body(content: Content) -> some View {
        if let duration {
            content.blink(duration)
        } else {
            content
        }
    }
}
