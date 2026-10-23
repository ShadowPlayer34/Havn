//
//  ThreatZone.swift
//  AlertRadar
//
//  Wire contract for GET /api/v1/threats/zones — the country-wide map overlay.
//
//  The endpoint answers a GeoJSON FeatureCollection carrying two kinds of Feature.
//
//  Per threat: `core`, the districts actually named in the reports, and `risk`, the same
//  shape plus the safety buffer and, when an approach direction was known, the corridor.
//  These are for *asking* — which threat is over this coordinate, how many were counted,
//  when it arrives.
//
//  Per threat type: `core_union` and `risk_union`, the same information merged into two
//  shapes that do not overlap each other. These are for *drawing*. The per-threat shapes
//  overlap by construction — `risk` contains its own `core`, and neighbouring reports
//  overlap again — so filling them stacks alpha, and the saturation that comes out says
//  how many reports piled up rather than how dangerous the place is.
//
//  No coordinates are sent to fetch this. The overlay is identical for every client.
//

import CoreLocation
import Foundation
import MapKit

// MARK: - Kind

/// Which of the two shapes a Feature carries.
nonisolated enum ThreatZoneKind: String, Sendable {
    /// Observation: a district a report actually named. Asked, not filled.
    case core
    /// Precaution: core plus buffer and corridor. Asked, not filled.
    case risk
    /// Every direct hit of one threat type, merged. Filled densely.
    case coreUnion = "core_union"
    /// Everything precautionary of one threat type — buffers, corridors, and reported
    /// districts under the server's confidence gate — merged, with `coreUnion` cut out of
    /// it. Filled as a pale wash.
    case riskUnion = "risk_union"

    /// The two a client fills. Disjoint within a threat type, so one pixel is painted
    /// once and the alpha on screen means what it says.
    var isDrawn: Bool { self == .coreUnion || self == .riskUnion }

    /// The two that belong to a single threat, and so can be ranked, counted, and read
    /// an arrival window off.
    var isThreatShape: Bool { self == .core || self == .risk }
}

// MARK: - Threat type

/// `threat_type` as the backend's `ThreatType` enum spells it. An unrecognised value is
/// kept rather than rejected — a threat class added server-side must still appear on the
/// map, just without a tuned colour.
nonisolated enum ThreatKind: Sendable, Hashable {
    case shahed
    case missile
    case recon
    case other(String)

    init(raw: String) {
        switch raw {
        case "shahed": self = .shahed
        case "missile": self = .missile
        case "recon": self = .recon
        default: self = .other(raw)
        }
    }

    /// Mirrors `THREAT_PRIORITY` in the backend's `schemas.py`, so the client picks the
    /// same threat the server would when several cover one point.
    var priority: Int {
        switch self {
        case .missile: 3
        case .shahed: 2
        case .recon: 1
        case .other: 0
        }
    }

    var localizedName: String {
        switch (Locale.current.language.languageCode?.identifier, self) {
        case ("uk", .shahed): "Шахед"
        case ("uk", .missile): "Ракета"
        case ("uk", .recon): "Розвідник"
        case ("ru", .shahed): "Шахед"
        case ("ru", .missile): "Ракета"
        case ("ru", .recon): "Разведчик"
        case (_, .shahed): "Shahed"
        case (_, .missile): "Missile"
        case (_, .recon): "Recon drone"
        case (_, .other(let value)): value.capitalized
        }
    }
}

// MARK: - Geometry

/// One GeoJSON polygon: an exterior ring and any holes, in the order MapKit wants them.
nonisolated struct ThreatZonePolygon: Sendable, Identifiable {
    let id: Int
    let exterior: [CLLocationCoordinate2D]
    let holes: [[CLLocationCoordinate2D]]
    /// Cheap reject before the ray cast, and the anchor for anything captioning the zone.
    let bounds: ThreatZoneBounds

    init?(id: Int, rings: [[CLLocationCoordinate2D]]) {
        guard let exterior = rings.first, exterior.count >= 3,
              let bounds = ThreatZoneBounds(exterior) else { return nil }
        self.id = id
        self.exterior = exterior
        self.holes = rings.dropFirst().filter { $0.count >= 3 }
        self.bounds = bounds
    }

    /// Built at draw time rather than stored: `MKPolygon` is a reference type and this
    /// value crosses from the networking actor to the main actor.
    var mkPolygon: MKPolygon {
        let interiors = holes.map { MKPolygon(coordinates: $0, count: $0.count) }
        return MKPolygon(
            coordinates: exterior,
            count: exterior.count,
            interiorPolygons: interiors.isEmpty ? nil : interiors
        )
    }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard bounds.contains(coordinate), Self.ring(exterior, contains: coordinate) else {
            return false
        }
        return !holes.contains { Self.ring($0, contains: coordinate) }
    }

    /// Ray casting straight in degrees. These zones span tens of kilometres, never cross
    /// the antimeridian and are only ever asked "is this point inside" — the projection
    /// distortion cancels. This decides *which* threat to name, never the risk level: that
    /// still comes from the server's own point-in-polygon in `/threats/check`.
    private static func ring(
        _ ring: [CLLocationCoordinate2D], contains point: CLLocationCoordinate2D
    ) -> Bool {
        var inside = false
        var previous = ring.count - 1
        for current in ring.indices {
            let a = ring[current]
            let b = ring[previous]
            // Equal latitudes fail this test, so the division below can never divide by
            // zero: the edge is horizontal and the ray misses it by construction.
            if (a.latitude > point.latitude) != (b.latitude > point.latitude) {
                let slope = (b.longitude - a.longitude) / (b.latitude - a.latitude)
                if point.longitude < a.longitude + slope * (point.latitude - a.latitude) {
                    inside.toggle()
                }
            }
            previous = current
        }
        return inside
    }
}

nonisolated struct ThreatZoneBounds: Sendable, Equatable {
    let minLatitude: Double
    let maxLatitude: Double
    let minLongitude: Double
    let maxLongitude: Double

    init?(_ coordinates: [CLLocationCoordinate2D]) {
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for coordinate in coordinates.dropFirst() {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        minLatitude = minLat
        maxLatitude = maxLat
        minLongitude = minLon
        maxLongitude = maxLon
    }

    var centre: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
    }

    /// Degrees of latitude across the box — used to rank "biggest shape" without pulling
    /// in a projection.
    var latitudeSpan: Double { maxLatitude - minLatitude }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude >= minLatitude && coordinate.latitude <= maxLatitude
            && coordinate.longitude >= minLongitude && coordinate.longitude <= maxLongitude
    }
}

// MARK: - Zone

/// One Feature: a threat's geometry of one kind, plus the properties both kinds carry.
nonisolated struct ThreatZone: Sendable, Identifiable {
    let threatID: String
    let kind: ThreatZoneKind
    let threatType: ThreatKind
    /// How many of this thing the reports counted.
    let count: Int
    let confidence: Double
    /// Whether standing inside this shape is what the backend calls a direct hit.
    ///
    /// False for a reported district whose confidence sits under the server's
    /// `HIGH_CONFIDENCE` gate: geometrically that is a `core`, but `/threats/check` will
    /// only ever rate it `elevated`, and a dense polygon under a user whose status line
    /// reads `elevated` is the map arguing with the chrome. Absent on payloads from a
    /// backend that predates the flag, where every core counted as a hit.
    let directHit: Bool
    /// District names as the reports gave them.
    let sectors: [String]
    /// Raw, exactly as stored. The arrival window is computed here so it decays between
    /// polls instead of jumping once a snapshot lands.
    let etaMinutes: Int?
    /// When the threat was first reported. `updatedAt` moves on every re-report, so this
    /// is what a "time since alert" clock counts from. Equal to `updatedAt` on payloads
    /// from a backend that predates the field.
    let firstSeenAt: Date
    let updatedAt: Date
    let expiresAt: Date
    let polygons: [ThreatZonePolygon]

    /// Stable across snapshots: the two Features of one threat must not collide, and a
    /// re-fetch of the same threat must reuse the same identity so the map does not tear
    /// the overlay down and rebuild it.
    var id: String { "\(threatID)-\(kind.rawValue)" }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        polygons.contains { $0.contains(coordinate) }
    }

    /// The widest polygon's centre — where a caption for this zone belongs.
    var captionAnchor: CLLocationCoordinate2D? {
        polygons.max { $0.bounds.latitudeSpan < $1.bounds.latitudeSpan }?.bounds.centre
    }

    func arrival(at now: Date = .now) -> ArrivalEstimate? {
        ArrivalEstimate(etaMinutes: etaMinutes, updatedAt: updatedAt, now: now)
    }

    /// The earliest edge of the window as an absolute instant, fixed at the moment of the
    /// report so a countdown against it only ever runs down.
    ///
    /// The window narrows as the estimate decays — a 45-minute ETA reads "38–56" when it
    /// lands and "30–44" ten minutes later, i.e. an earliest edge two minutes *later* in
    /// absolute terms. Recomputing this every tick would make the countdown creep
    /// backwards, which reads as broken; pinning it to the report keeps the conservative
    /// edge, and early is the safe side to be wrong on.
    var earliestArrival: Date? {
        guard let estimate = arrival(at: updatedAt), !estimate.isImminent else { return nil }
        return updatedAt.addingTimeInterval(Double(estimate.earliest) * 60)
    }

    /// The far edge of the same window, pinned the same way.
    var latestArrival: Date? {
        guard let estimate = arrival(at: updatedAt), !estimate.isImminent else { return nil }
        return updatedAt.addingTimeInterval(Double(estimate.latest) * 60)
    }
}

// MARK: - Arrival window

/// Port of `format_eta_window` (backend `app/spatial.py`). The payload is cached per
/// snapshot version, so the server cannot bake a window into it without freezing the
/// countdown; `eta_minutes` and `updated_at` travel raw and this runs on every tick.
///
/// Distinct from `ArrivalWindow` in the Live Activity contract, which widens a countdown
/// the design document owns. This one has to agree with the backend to the minute, because
/// `/threats/check` renders the same window server-side.
nonisolated struct ArrivalEstimate: Sendable, Equatable {
    /// Minutes from now, widened either side of the centre estimate.
    let earliest: Int
    let latest: Int
    /// Inside half a minute: the backend says "now" rather than a window, and so do we.
    let isImminent: Bool

    /// English "now" is not a slip — it is what `/threats/check` returns in `eta_window`,
    /// and the two must never word the same fact differently.
    var label: String { isImminent ? "now" : String(localized: "\(earliest)–\(latest) min") }

    /// The same window where the space is not there — the Dynamic Island's compact
    /// trailing region and the lock screen banner.
    var shortLabel: String { isImminent ? "now" : String(localized: "\(earliest)–\(latest)m") }

    init?(etaMinutes: Int?, updatedAt: Date, now: Date = .now) {
        guard let etaMinutes else { return nil }

        let elapsedMinutes = now.timeIntervalSince(updatedAt) / 60
        let remaining = Double(etaMinutes) - elapsedMinutes
        guard remaining > 0.5 else {
            earliest = 0
            latest = 0
            isImminent = true
            return
        }

        // Round to whole minutes *before* widening, otherwise a freshly stored 10-minute
        // ETA reads as "7–13" because of sub-second elapsed time.
        //
        // `.toNearestOrEven` rather than Swift's default half-away-from-zero: Python's
        // `round` is banker's rounding, and this window is also rendered server-side.
        let minutes = Int(remaining.rounded(.toNearestOrEven))

        // Width grows with the estimate. A 10-minute ETA comes from a source that watched
        // the thing go past; a 45-minute one is derived from an oblast centroid and the
        // real position inside an oblast is unknown by tens of kilometres. Asymmetric on
        // purpose — arriving early is the dangerous side to be wrong on.
        let lower = max(2, Int((Double(minutes) * 0.15).rounded(.toNearestOrEven)))
        let upper = max(3, Int((Double(minutes) * 0.25).rounded(.toNearestOrEven)))

        earliest = max(0, minutes - lower)
        latest = minutes + upper
        isImminent = false
    }
}

// MARK: - Collection

/// The whole FeatureCollection: what the overlay knows at one snapshot version.
nonisolated struct ThreatZoneCollection: Sendable, Decodable {
    let generatedAt: Date?
    /// Redis snapshot version the payload was built from; the ETag is derived from it.
    let version: Int?
    let zones: [ThreatZone]

    static let empty = ThreatZoneCollection(generatedAt: nil, version: nil, zones: [])

    /// `expires_at` is per Feature so a lapsed zone can be dropped locally, without
    /// waiting for the next version bump — the janitor's interval can be a minute away.
    func active(at now: Date = .now) -> [ThreatZone] {
        zones.filter { $0.expiresAt > now }
    }
}

// MARK: - Decoding

nonisolated extension ThreatZoneCollection {
    private enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case version
        case features
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
            .flatMap(APITimestamp.date(from:))
        version = try container.decodeIfPresent(Int.self, forKey: .version)
        zones = try container.decode([FeatureDTO].self, forKey: .features).compactMap(\.zone)
    }
}

/// Features are skipped rather than thrown on. One unreadable shape in a payload of
/// dozens must not blank the whole overlay — and the endpoint is versioned, so a Feature
/// this build does not understand is expected traffic, not corruption.
private nonisolated struct FeatureDTO: Decodable {
    let zone: ThreatZone?

    private enum CodingKeys: String, CodingKey {
        case geometry, properties
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let properties = try container.decode(PropertiesDTO.self, forKey: .properties)
        let geometry = try container.decodeIfPresent(GeometryDTO.self, forKey: .geometry)

        guard let kind = ThreatZoneKind(rawValue: properties.kind),
              // No parsable expiry means no way to drop this locally when it lapses, and
              // a zone that can only disappear on a version bump is worse than none.
              let updatedAt = APITimestamp.date(from: properties.updated_at),
              let expiresAt = APITimestamp.date(from: properties.expires_at),
              let rings = geometry?.polygons, !rings.isEmpty
        else {
            zone = nil
            return
        }

        let polygons = rings.enumerated().compactMap {
            ThreatZonePolygon(id: $0.offset, rings: $0.element)
        }
        guard !polygons.isEmpty else {
            zone = nil
            return
        }

        zone = ThreatZone(
            threatID: properties.id,
            kind: kind,
            threatType: ThreatKind(raw: properties.threat_type),
            count: properties.count ?? 1,
            confidence: properties.confidence_score ?? 0,
            // Absent means a backend from before the flag, where every reported district
            // counted as a hit — and on the merged Features, where the split is carried by
            // the kind itself.
            directHit: properties.direct_hit ?? (kind == .core),
            sectors: properties.sectors ?? [],
            etaMinutes: properties.eta_minutes,
            firstSeenAt: properties.first_seen_at.flatMap(APITimestamp.date(from:)) ?? updatedAt,
            updatedAt: updatedAt,
            expiresAt: expiresAt,
            polygons: polygons
        )
    }
}

/// Wire names kept verbatim — this struct exists only to carry them across.
private nonisolated struct PropertiesDTO: Decodable {
    let id: String
    let kind: String
    let threat_type: String
    let count: Int?
    let confidence_score: Double?
    let direct_hit: Bool?
    let sectors: [String]?
    let eta_minutes: Int?
    let first_seen_at: String?
    let updated_at: String
    let expires_at: String
}

/// Polygon and MultiPolygon flattened to the same shape: a list of polygons, each a list
/// of rings, exterior first.
private nonisolated struct GeometryDTO: Decodable {
    let polygons: [[[CLLocationCoordinate2D]]]

    private enum CodingKeys: String, CodingKey {
        case type, coordinates
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "Polygon":
            let raw = try container.decode([[[Double]]].self, forKey: .coordinates)
            polygons = [raw.map(Self.ring)]
        case "MultiPolygon":
            let raw = try container.decode([[[[Double]]]].self, forKey: .coordinates)
            polygons = raw.map { $0.map(Self.ring) }
        default:
            // The overlay only ever carries areas. Anything else is a shape this screen
            // has no way to draw.
            polygons = []
        }
    }

    /// GeoJSON is x,y — longitude first. Rings arrive closed; the repeated final vertex is
    /// dropped because MapKit closes polygons itself.
    private static func ring(_ raw: [[Double]]) -> [CLLocationCoordinate2D] {
        var coordinates = raw.compactMap { pair -> CLLocationCoordinate2D? in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }
        if let first = coordinates.first, let last = coordinates.last, coordinates.count > 1,
           first.latitude == last.latitude, first.longitude == last.longitude {
            coordinates.removeLast()
        }
        return coordinates
    }
}

/// `datetime.isoformat()` output: an offset, and fractional seconds only when the clock
/// had them. Two format styles rather than one lenient parse, so what is accepted is
/// written down here rather than inherited from Foundation's mood. The overlay's
/// properties parse with it, and so does every `Date` the network service decodes.
nonisolated enum APITimestamp {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let whole = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    static func date(from raw: String) -> Date? {
        (try? fractional.parse(raw)) ?? (try? whole.parse(raw))
    }
}
