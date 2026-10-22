import Foundation
import OSLog
import WidgetKit

/// Whether an alert stands over the district someone said they live in, and since when.
///
/// Written by whichever side read the overlay last — the app on every poll while it is
/// open, the widget on its own timeline while it is not — into the same App Group
/// container as `WidgetSnapshot`.
nonisolated struct DistrictAlertState: Codable, Equatable, Sendable {
    var district: KyivDistrict
    var level: DistrictAlertLevel
    /// When threats first stood over the district. Kept through the all-clear so that can
    /// say how long it lasted.
    var startedAt: Date?
    /// When the district was first seen clear again. Nil while anything is over it, and
    /// before anything has been seen at all.
    var endedAt: Date?
    /// The last successful read of the overlay — not the last time anything changed.
    var checkedAt: Date

    var isActive: Bool { level != .clear }

    /// Whether a widget drawing `other` would draw this the same. The clock is left out: it
    /// moves on every poll, and a reload spent on it changes nothing on screen.
    func reads(sameAs other: DistrictAlertState?) -> Bool {
        guard let other else { return false }
        return district == other.district && level == other.level
            && startedAt == other.startedAt && endedAt == other.endedAt
    }
}

/// The same two levels `/threats/check` rates a coordinate, read for a whole district.
nonisolated enum DistrictAlertLevel: String, Codable, Sendable {
    case clear
    /// Only a buffer or an approach corridor reaches the district, or a direct hit clips
    /// its edge — what the backend calls `elevated`.
    case nearby
    /// A direct hit over the district itself.
    case alert
}

// MARK: - Reading the overlay

nonisolated extension KyivDistrict {
    /// How hard the live threat shapes stand over the district, and the earliest report
    /// among those that reach it at all.
    ///
    /// Only a `core` the backend counts as a direct hit makes it an alert — and only when
    /// it covers the district rather than clipping it. Cores are whole reported districts,
    /// so a real hit covers the interior point; a sliver along the boundary is the
    /// simplifier moving a neighbour's edge, or a point report's radius reaching across.
    /// Everything else that reaches it is `nearby`: a missile's buffer and its corridor
    /// from Brovary cross every district in the city, and calling all ten "alert" would
    /// make the one choice this widget asks for meaningless.
    ///
    /// The earliest report rather than the dominant threat's, for the reason
    /// `ThreatZonesViewModel.earliestFirstSeen` gives: each report arrives as a threat of
    /// its own, and the clock must not restart whenever a newer one outranks the first.
    func alert(in zones: [ThreatZone], at now: Date = .now) -> (level: DistrictAlertLevel, earliestReport: Date?) {
        let points = samplePoints
        var level = DistrictAlertLevel.clear
        var earliest: Date?

        for zone in zones where zone.kind.isThreatShape && zone.expiresAt > now {
            let covered = points.filter(zone.contains).count
            guard covered > 0 else { continue }
            earliest = min(earliest ?? zone.firstSeenAt, zone.firstSeenAt)

            let coversDistrict = zone.contains(points[0]) || covered * 4 >= points.count
            if zone.kind == .core, zone.directHit, coversDistrict {
                level = .alert
            } else if level == .clear {
                level = .nearby
            }
        }
        return (level, earliest)
    }
}

// MARK: - Store

/// The district and its state, shared between the app and the widget extension.
nonisolated enum DistrictAlertStore {
    static let kind = "com.vectoralert.district-alert"

    /// A report that lands within this long of the all-clear continues the episode it
    /// interrupted instead of starting a new one. Every report is a threat with a TTL of
    /// its own, so a short gap between one expiring and the next arriving is routine, and
    /// "for 2 min" straight after "for 40 min" would be the clock lying.
    static let resumeWindow: TimeInterval = 120

    private static let districtKey = "district.home"
    private static let stateKey = "district.alert"
    private static let logger = Logger(subsystem: "com.vectoralert.alertradar", category: "widgets")

    private static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetSnapshotStore.appGroup) }

    static var homeDistrict: KyivDistrict? {
        defaults?.string(forKey: districtKey).flatMap(KyivDistrict.init(rawValue:))
    }

    /// Choose where someone lives. The old district's state goes with it: an alert that was
    /// on over Obolon says nothing about Pechersk.
    static func setHomeDistrict(_ district: KyivDistrict) {
        guard let defaults else {
            logger.error("App Group \(WidgetSnapshotStore.appGroup, privacy: .public) unavailable — district widget will stay empty")
            return
        }
        guard district != homeDistrict else { return }
        defaults.set(district.rawValue, forKey: districtKey)
        defaults.removeObject(forKey: stateKey)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }

    /// The stored state, provided it is about the district currently chosen.
    static func load() -> DistrictAlertState? {
        guard let defaults, let data = defaults.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(DistrictAlertState.self, from: data),
              state.district == homeDistrict
        else { return nil }
        return state
    }

    /// Fold one successful read of the overlay into the stored state, and return the result.
    /// Nil when no district has been chosen.
    @discardableResult
    static func record(level: DistrictAlertLevel, earliestReport: Date?, at now: Date = .now) -> DistrictAlertState? {
        guard let defaults, let district = homeDistrict else { return nil }
        let previous = load()

        var next = DistrictAlertState(
            district: district,
            level: level,
            startedAt: previous?.startedAt,
            endedAt: previous?.endedAt,
            checkedAt: now
        )

        if next.isActive {
            let reported = earliestReport ?? now
            if let previous, previous.isActive {
                next.startedAt = min(previous.startedAt ?? reported, reported)
            } else if let previous, let ended = previous.endedAt,
                      now.timeIntervalSince(ended) < resumeWindow, let started = previous.startedAt {
                next.startedAt = min(started, reported)
            } else {
                next.startedAt = reported
            }
            next.endedAt = nil
        } else if previous?.isActive == true {
            next.endedAt = now
        }

        if let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: stateKey)
        }
        return next
    }
}
