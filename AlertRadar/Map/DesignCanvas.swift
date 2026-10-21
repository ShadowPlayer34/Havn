import SwiftUI

/// The design document is authored at 402 × 874 pt — iPhone 16/17 Pro. The lock screen and
/// Dynamic Island mock-ups are still pinned to that grid; the map itself is MapKit now.
enum MapSpace {
    static let width: CGFloat = 402
    static let height: CGFloat = 874
}

/// A fixed coordinate space laid out from the top-left, the way the design positions things:
/// `.offset` reads as CSS `top`/`left`, `.position` as a centre point. Oversized children
/// overhang without dragging the layer's own size.
struct DesignCanvas<Content: View>: View {
    var width: CGFloat = MapSpace.width
    var height: CGFloat = MapSpace.height
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            content
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }
}

/// An elliptical, closest-side radial gradient — CSS `radial-gradient(closest-side, …)`.
struct MapBlob: View {
    var stops: [Gradient.Stop]
    var size: CGSize
    var rotation: Double
    var blur: CGFloat

    var body: some View {
        Circle()
            .fill(RadialGradient(stops: stops, center: .center, startRadius: 0, endRadius: 100))
            .frame(width: 200, height: 200)
            .scaleEffect(x: size.width / 200, y: size.height / 200)
            .rotationEffect(.degrees(rotation))
            .blur(radius: blur)
            .frame(width: size.width, height: size.height)
    }
}
