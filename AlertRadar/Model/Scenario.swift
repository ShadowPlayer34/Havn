import CoreLocation
import MapKit
import SwiftUI

/// The sample incident, anchored to wherever you actually are. Bearings, distances and the
/// shape of the smear are the design document's; the origin is your own coordinate, so the
/// scenario reads the same in Kyiv or anywhere else the app is opened.
struct ThreatScenario {
    let anchor: CLLocationCoordinate2D
    /// Drives whether the wash is drawn at all, and how hot it runs. The *shape* is still
    /// generated locally — the endpoint returns a level, not a geometry.
    var risk: RiskLevel = .none

    struct HeatBand {
        let centre: CLLocationCoordinate2D
        let radius: CLLocationDistance
        let colour: Color
        /// Peak alpha at the centre of the band, before blur compensation.
        let alpha: Double
    }

    /// Identities are stable across rebuilds — a fresh UUID per rebuild would make ForEach
    /// tear down and re-create every overlay on each frame of a map drag.
    struct HeatRing: Identifiable {
        let id: String
        let centre: CLLocationCoordinate2D
        let radius: CLLocationDistance
        let colour: Color
        let alpha: Double
    }

    struct Haven: Identifiable {
        let name: String
        let coordinate: CLLocationCoordinate2D
        let metres: Int

        var id: String { name }
        var label: String { "\(name) · \(metres) m" }
    }

    /// Five overlapping bands — Gaussian density, no edges and no target marker. Sized so the
    /// wash runs off the top of the screen at the default camera, the way the design draws it.
    private var heat: [HeatBand] {
        guard risk != .none else { return [] }
        // Elevated keeps the amber end of the ramp; high runs the full design set through red.
        let hot = risk == .high
        let intensity = hot ? 1.0 : 0.72
        return [
            HeatBand(centre: anchor.offset(north: 620, east: 15), radius: 1250,
                     colour: VA.orange, alpha: 0.17 * intensity),
            HeatBand(centre: anchor.offset(north: 640, east: 0), radius: 900,
                     colour: Color(hex: hot ? 0xFF5E3C : 0xFF9500), alpha: 0.30 * intensity),
            HeatBand(centre: anchor.offset(north: 420, east: -230), radius: 580,
                     colour: Color(hex: hot ? 0xFF462D : 0xFFA51F), alpha: 0.28 * intensity),
            HeatBand(centre: anchor.offset(north: 980, east: 320), radius: 480,
                     colour: Color(hex: hot ? 0xFF5032 : 0xFF9500), alpha: 0.22 * intensity),
            HeatBand(centre: anchor.offset(north: 700, east: -40), radius: 390,
                     colour: hot ? VA.red : VA.orange, alpha: 0.32 * intensity)
        ]
    }

    var heatRings: [HeatRing] {
        heat.enumerated().flatMap { index, band in Self.rings(for: band, id: "heat\(index)") }
    }

    /// Shelters ranked by walk time, at the distances the safety protocol quotes.
    var havens: [Haven] {
        [
            Haven(name: "Metro Vokzalna", coordinate: anchor.offset(bearing: 309, metres: 240), metres: 240),
            Haven(name: "Shelter #14", coordinate: anchor.offset(bearing: 236, metres: 610), metres: 610)
        ]
    }

    /// Where the "Estimated Risk Area" caption sits on the wash.
    var captionAnchor: CLLocationCoordinate2D {
        anchor.offset(north: 470, east: -330)
    }

    /// Close enough that both shelters read as walkable, wide enough that the risk area
    /// still runs off the top of the screen.
    static let cameraSpan: CLLocationDistance = 1600

    static func region(around coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate, latitudinalMeters: cameraSpan, longitudinalMeters: cameraSpan)
    }

    // MARK: Falloff

    /// MapKit resolves a gradient fill flat across an overlay, so a band's soft edge is built
    /// from concentric rings instead. Each ring carries the alpha that, stacked, lands on the
    /// band's peak — scaled down because the design's blur spreads its own peak out.
    private static let ringCount = 6
    private static let blurCompensation = 0.62

    private static func rings(for band: HeatBand, id: String) -> [HeatRing] {
        let peak = band.alpha * blurCompensation
        let perRing = 1 - pow(1 - peak, 1 / Double(ringCount))
        return (0..<ringCount).map { step in
            HeatRing(
                id: "\(id)-\(step)",
                centre: band.centre,
                radius: band.radius * (1 - Double(step) / Double(ringCount)),
                colour: band.colour,
                alpha: perRing
            )
        }
    }
}
