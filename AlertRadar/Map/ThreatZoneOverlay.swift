//
//  ThreatZoneOverlay.swift
//  AlertRadar
//
//  The backend's own geometry on the map. Every shape here came from
//  GET /api/v1/threats/zones — nothing on this layer is generated locally.
//

import MapKit
import SwiftUI

/// Two passes on purpose. The wash is buffer and approach corridor — precaution, several
/// times the size of the observation it surrounds — so it goes down first. Direct hits are
/// the districts a report actually named, and they draw over the top at full weight.
/// Flattening the two into one shape would put most of an oblast under the same red as the
/// street a drone was seen over.
///
/// Both come from the merged Features (`core_union`, `risk_union`): one shape per threat
/// type per pass, disjoint by construction. The per-threat shapes are deliberately not
/// filled — `risk` contains its own `core` and neighbouring reports overlap, so filling
/// them composites alpha and the map ends up drawing *report density* in the colour it
/// reserves for danger. Measured on a live Kyiv night: six stacked layers came out at 59%
/// opacity where one threat is 31%, and nothing on screen said which it was.
struct ThreatZonesOverlay: MapContent {
    let zones: [ThreatZone]

    var body: some MapContent {
        // Declaration order is draw order: every wash first, so one threat type's buffer
        // can never bury another type's direct hit.
        ForEach(layer(merged: .riskUnion, perThreat: .risk)) { zone in
            ThreatZoneShape(zone: zone)
        }
        ForEach(layer(merged: .coreUnion, perThreat: .core)) { zone in
            ThreatZoneShape(zone: zone)
        }
    }

    /// True once the backend has sent anything merged. Decided across both passes rather
    /// than per pass: a payload with one union and one missing must not mix the two
    /// layers, which would paint the merged pass twice.
    private var hasMergedLayer: Bool {
        zones.contains { $0.kind.isDrawn }
    }

    /// The merged shapes, or the per-threat ones against a backend old enough not to send
    /// them. The fallback stacks, but a stacked overlay beats a blank map.
    private func layer(merged: ThreatZoneKind, perThreat: ThreatZoneKind) -> [ThreatZone] {
        let wanted = hasMergedLayer ? merged : perThreat
        return zones.filter { $0.kind == wanted }
    }
}

private struct ThreatZoneShape: MapContent {
    let zone: ThreatZone

    var body: some MapContent {
        ForEach(zone.polygons) { polygon in
            MapPolygon(polygon.mkPolygon)
                .foregroundStyle(zone.fill)
                .stroke(zone.stroke, lineWidth: zone.strokeWidth)
        }
    }
}

// MARK: - Styling

/// The overlay's two weights, in one place.
///
/// Shared with `MapLegend` on purpose: a key that hardcodes its own swatch colours is a
/// key that drifts, and a legend describing a wash the map does not draw is worse than no
/// legend at all.
///
/// The alphas went up when the merged layer landed. They were tuned against a map that
/// stacked — six overlapping shapes composited to ~59% over Kyiv, so 0.26 for a direct hit
/// looked right in situ. Drawn once, 0.26 is a tint you have to look for and 0.10 is barely
/// there at all. These are the values that read as "you are inside something" when nothing
/// is piled on top of them.
nonisolated enum ThreatFill {
    /// Reported districts the backend would rate `high`.
    static let hit: Double = 0.32
    static let hitStroke: Double = 0.85
    static let hitStrokeWidth: CGFloat = 1.4

    /// Buffers, corridors, and reported districts under the confidence gate.
    static let area: Double = 0.15
    static let areaStroke: Double = 0.38
    static let areaStrokeWidth: CGFloat = 1
}

extension ThreatKind {
    /// One accent per threat class, on the same meaning-carries-the-colour rule as the
    /// risk badges: red is the thing you cannot outrun.
    ///
    /// These are the same four accents the chrome uses for *risk level*, which is why the
    /// map ships a legend — orange here means shahed, not "medium".
    var accent: Color {
        switch self {
        case .missile: VA.red
        case .shahed: VA.orange
        case .recon: VA.cyan
        // An unrecognised class is real and inbound; it gets the predicted-threat accent
        // rather than being drawn as though it were nothing.
        case .other: VA.orange
        }
    }
}

extension ThreatZone {
    var accent: Color { threatType.accent }

    /// A 0.4-confidence report should not paint as hard as a corroborated one. The floor
    /// keeps the weakest zone the backend will publish (`min_confidence`, 0.35) visible.
    private var weight: Double { 0.6 + 0.4 * min(1, max(0, confidence)) }

    /// Dense or pale — the only thing the fill encodes besides threat type.
    ///
    /// A reported district under the server's confidence gate counts as pale here even
    /// though it is a `core`. The backend will not call it more than `elevated`
    /// (`ThreatIndex.lookup`), and drawing it as a direct hit is exactly how a user ends
    /// up standing in a dense red polygon reading "Elevated attention" above it.
    private var isDirectHit: Bool {
        switch kind {
        case .coreUnion: true
        case .riskUnion: false
        case .core: directHit
        case .risk: false
        }
    }

    var fill: Color {
        accent.opacity((isDirectHit ? ThreatFill.hit : ThreatFill.area) * weight)
    }

    var stroke: Color {
        accent.opacity(isDirectHit ? ThreatFill.hitStroke * weight : ThreatFill.areaStroke)
    }

    var strokeWidth: CGFloat {
        isDirectHit ? ThreatFill.hitStrokeWidth : ThreatFill.areaStrokeWidth
    }

    /// "6 Shahed · 2 districts" — what the caption says instead of a hardcoded count.
    var captionDetail: String {
        var parts: [String] = []
        parts.append(count > 1 ? "\(count) \(threatType.localizedName)" : threatType.localizedName)
        if !sectors.isEmpty {
            parts.append(String(localized: "\(sectors.count) districts"))
        }
        parts.append(String(localized: "\(Int((confidence * 100).rounded()))% confidence"))
        return parts.joined(separator: " · ").uppercased()
    }
}
