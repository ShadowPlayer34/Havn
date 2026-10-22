import MapKit
import SwiftUI

/// Gaussian density over real geography — the estimate is an area, never a point, and it
/// scales and rotates with the map instead of floating over it.
///
/// Fallback only. Real threat geometry comes from `/api/v1/threats/zones` and is drawn by
/// `ThreatZonesOverlay`; this wash stands in when that payload has never arrived and
/// `/threats/check` still says there is something in the sector.
struct RiskHeatOverlay: MapContent {
    let scenario: ThreatScenario

    var body: some MapContent {
        HeatRings(rings: scenario.heatRings)
    }
}

/// Concentric flat circles, largest first — the falloff a gradient fill can't give here.
struct HeatRings: MapContent {
    let rings: [ThreatScenario.HeatRing]

    var body: some MapContent {
        ForEach(rings) { ring in
            MapCircle(center: ring.centre, radius: ring.radius)
                .foregroundStyle(ring.colour.opacity(ring.alpha))
        }
    }
}

// MARK: - Annotation content

/// A shelter from the register. The nearest one carries its address; the rest stay
/// as dots until tapped, because a dozen labels inside 300 m is not a map.
struct ShelterPin: View {
    let shelter: Shelter
    let isPrimary: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            if isPrimary {
                HStack(spacing: 7) {
                    marker
                    VStack(alignment: .leading, spacing: 1) {
                        Text(shelter.shortLabel)
                            .font(VAFont.display(10.5))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("\(shelter.distanceLabel) · \(shelter.walkMinutes) min")
                            .font(VAFont.display(9, .medium))
                            .foregroundStyle(VA.greenText)
                    }
                    .fixedSize()
                }
                .padding(.leading, 6)
                .padding(.trailing, 10)
                .padding(.vertical, 5)
                .vaGlass(RoundedRectangle(cornerRadius: 16), tint: VA.green.opacity(0.38))
            } else {
                marker
                    .padding(5)
                    .vaGlass(Circle(), tint: VA.green.opacity(0.3))
            }
        }
        .buttonStyle(.plain)
    }

    /// Hollow when the register puts a caveat on the hours — a closed shelter should
    /// not look identical to one you can walk into.
    private var marker: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(shelter.isAlwaysOpen ? VA.green : .clear)
            .frame(width: 12, height: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(VA.green, lineWidth: shelter.isAlwaysOpen ? 0 : 2)
            )
    }
}

// MARK: - Legend

/// What the colours on the overlay mean, shown on demand and then got out of the way.
///
/// The map's palette is per *threat type* and the chrome's is per *risk level*, and both
/// draw from the same four accents — so orange on the map reads as "medium risk" when it
/// says "shahed". That is worth answering once, when the layer is switched on or asked
/// for. It is not worth a card parked over the city for the rest of the night, which is
/// what a permanent key turned out to be.
///
/// Swatches are drawn from `ThreatFill` over `VA.mapBase`, so they are the overlay's own
/// colours at the overlay's own weights rather than an approximation of them. The first
/// version used neutral white squares and the immediate reaction was that no such colour
/// appears anywhere on the map — which was true.
struct MapLegend: View {
    let zones: [ThreatZone]

    /// Most severe first, so the eye lands on the colour that matters. Read off the drawn
    /// layer, falling back to the per-threat shapes against a backend that sends no
    /// merged Features — the legend has to describe whatever `ThreatZonesOverlay` chose.
    private var kinds: [ThreatKind] {
        let drawn = Set(zones.filter { $0.kind.isDrawn }.map(\.threatType))
        let perThreat = Set(zones.filter { $0.kind.isThreatShape }.map(\.threatType))
        return (drawn.isEmpty ? perThreat : drawn).sorted { $0.priority > $1.priority }
    }

    var body: some View {
        if !kinds.isEmpty {
            // A grid rather than two stacked lists: weight is the overlay's second axis,
            // and giving it a column says "these are the same colour at two strengths".
            // As separate rows it read as a third and fourth threat class.
            Grid(alignment: .leading, horizontalSpacing: 9, verticalSpacing: 6) {
                GridRow {
                    Color.clear.frame(width: 0, height: 0)
                    header("DIRECT HIT")
                    header("RISK AREA")
                }
                ForEach(kinds, id: \.self) { kind in
                    GridRow {
                        Text(kind.localizedName)
                            .font(VAFont.display(10.5, .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                        swatch(kind.accent, dense: true)
                        swatch(kind.accent, dense: false)
                    }
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .vaGlass(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func header(_ text: String) -> some View {
        Text(LocalizedStringKey(text))
            .font(VAFont.mono(7.5, .semibold))
            .tracking(em: 0.1, size: 7.5)
            .foregroundStyle(.white.opacity(0.45))
            .fixedSize()
    }

    /// Wide and short rather than square: a 15% wash in an 11-point box is a smudge, and
    /// the whole point of the row is that you can tell it from the 32% one beside it.
    private func swatch(_ accent: Color, dense: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3)
        return shape
            // `VA.elevated`, not `VA.mapBase`: the token named for the map base is darker
            // than anything `.standard(emphasis: .muted)` actually renders, and a 15% wash
            // over near-black comes out as a black square. The swatch has to sit on the
            // tone the overlay really sits on or it misrepresents the very thing it is
            // there to explain.
            .fill(VA.elevated)
            .overlay(shape.fill(accent.opacity(dense ? ThreatFill.hit : ThreatFill.area)))
            .overlay(
                shape.strokeBorder(
                    accent.opacity(dense ? ThreatFill.hitStroke : ThreatFill.areaStroke),
                    lineWidth: dense ? ThreatFill.hitStrokeWidth : ThreatFill.areaStrokeWidth
                )
            )
            .frame(width: 30, height: 15)
    }
}

struct RiskAreaCaption: View {
    /// Second line: the zone's own numbers when the shape came from the backend, and a
    /// plain statement that it did not when the wash is generated locally.
    var detail: String
    var accent: Color = VA.orange
    var title: LocalizedStringKey = "Estimated Risk Area (OSINT-based)"

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(VAFont.display(10.5, .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Text(detail)
                    .font(VAFont.mono(9))
                    .tracking(em: 0.06, size: 9)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .vaGlass(RoundedRectangle(cornerRadius: 16))
    }
}

/// The one precise point on the map: you.
struct UserLocationDot: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    stops: [
                        .init(color: VA.cyan.opacity(0.22), location: 0),
                        .init(color: .clear, location: 0.7)
                    ],
                    center: .center, startRadius: 0, endRadius: 37
                ))
                .frame(width: 74, height: 74)
            Circle()
                .fill(VA.cyan)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
        }
    }
}

// MARK: - Scale bar

/// The design's scale slot, telling the truth about the current camera.
struct MapScale {
    var barWidth: CGFloat
    var distanceLabel: String
    var ratioLabel: String
    var zoomLabel: String

    /// Points per metre of physical screen at 160 pt/inch.
    private static let pointsPerMetre = 2835.0
    private static let steps: [Double] = [50, 100, 200, 500, 1_000, 2_000, 5_000, 10_000, 20_000, 50_000]

    init(region: MKCoordinateRegion, mapHeight: CGFloat) {
        let metresPerPoint = max(0.1, region.span.latitudeDelta * 111_320 / max(1, mapHeight))
        // Pick the round distance whose bar lands closest to the design's 62 pt.
        let distance = Self.steps.min { lhs, rhs in
            abs(lhs / metresPerPoint - 62) < abs(rhs / metresPerPoint - 62)
        } ?? 1_000
        barWidth = min(96, max(34, distance / metresPerPoint))
        distanceLabel = distance >= 1_000
            ? String(localized: "\(Int(distance / 1_000)) km")
            : String(localized: "\(Int(distance)) m")

        let ratio = metresPerPoint * Self.pointsPerMetre
        let magnitude = pow(10, (log10(ratio)).rounded(.down))
        let rounded = Int((ratio / magnitude).rounded() * magnitude)
        ratioLabel = "1:" + rounded.formatted(.number.grouping(.automatic)).replacingOccurrences(of: ",", with: " ")

        zoomLabel = switch ratio {
        case 100_000...: String(localized: "REGION")
        case 25_000...: String(localized: "CITY OVERVIEW")
        case 8_000...: String(localized: "DISTRICT")
        default: String(localized: "STREET LEVEL")
        }
    }
}
