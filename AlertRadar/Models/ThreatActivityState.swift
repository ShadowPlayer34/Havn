//
//  ThreatActivityState.swift
//  AlertRadar
//
//  Turns what the app knows into what the lock screen says.
//
//  App-side only: the widget extension gets the finished `ContentState` and never sees a
//  `ThreatZone`. Kept in one place so the map cluster and the Live Activity cannot word
//  the same fact differently — they read the same zone and the same check response.
//

import Foundation

extension ThreatActivityAttributes.ContentState {
    init(
        area: String?,
        zone: ThreatZone?,
        response: ThreatCheckResponse?,
        now: Date = .now
    ) {
        self.init(
            area: area,
            threat: Self.threatLine(zone: zone, response: response),
            // Without a check we do not get to say "clear" — that is the one thing this
            // app must never claim on a guess.
            status: response?.riskLevel.localizedSummary ?? "Waiting for a sector check.",
            arrival: ThreatActivityAttributes.Arrival(zone: zone, now: now),
            // The design's "Location Safety: 88%" had nothing behind it and no endpoint
            // answers it, so nothing is sent and the badge stays off the screen.
            safetyPercent: nil,
            updated: now
        )
    }

    /// The overlay knows how many of the thing were counted; the check only knows its type.
    private static func threatLine(zone: ThreatZone?, response: ThreatCheckResponse?) -> String {
        if let zone {
            let subject = zone.count > 1
                ? "\(zone.count) \(zone.threatType.localizedName)"
                : zone.threatType.localizedName
            return "\(subject) · area estimate"
        }
        if let type = response?.threatType {
            return "\(ThreatKind(raw: type).localizedName) · area estimate"
        }
        return "No active threat"
    }
}

extension ThreatActivityAttributes.Arrival {
    /// Absolute instants, fixed at the report rather than recomputed from `now`: the widget
    /// runs its own clock off them, so the countdown keeps ticking between pushes and the
    /// bar advances instead of restarting at every one.
    init?(zone: ThreatZone?, now: Date) {
        guard let zone, let estimate = zone.arrival(at: now) else { return nil }
        // Both edges are nil only when the estimate was already "now" at the report, in
        // which case the window has no width and the bar should read as full.
        self.init(
            reportedAt: zone.updatedAt,
            earliest: zone.earliestArrival ?? zone.updatedAt,
            latest: zone.latestArrival ?? zone.updatedAt,
            label: estimate.shortLabel
        )
    }
}
