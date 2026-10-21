import Foundation
import OSLog
import WidgetKit

/// What the home-screen widgets are allowed to show, written by the app into the shared
/// App Group container.
///
/// The extension has no network session and no location of its own, and a widget that
/// invented a shelter would be worse than one that admitted it has nothing: the number on
/// it is a distance somebody might walk in the dark. So everything here is copied from a
/// `/shelters/nearest` answer the app actually received, and the timestamp travels with it
/// so the widget can say how old the answer is.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// Denormalised on purpose — the widget target does not link the app's `Shelter` model,
    /// and only these five facts fit on a small widget anyway.
    struct NearestShelter: Codable, Equatable, Sendable {
        var name: String
        var metres: Int
        var walkMinutes: Int
        var isAlwaysOpen: Bool
        /// The register's own wording when it is not round-the-clock.
        var hours: String?
    }

    /// Nil when the app has never had a fix, or the register has nothing nearby.
    var shelter: NearestShelter?
    /// When the app received this, not when the widget drew it.
    var capturedAt: Date
}

/// The one path between the app and its widgets.
nonisolated enum WidgetSnapshotStore {
    /// Must stay in step with `com.apple.security.application-groups` in
    /// `WidgetSupport/AlertRadar.entitlements` and `AlertRadarWidgets.entitlements`.
    /// Without the entitlement on both sides the suite below is nil and nothing crosses.
    static let appGroup = "group.com.vectoralert.alertradar"

    /// Kind identifiers, so a write can reload exactly the widget it affects rather than
    /// every widget the bundle ships.
    static let nearestShelterKind = "com.vectoralert.nearest-shelter"

    private static let key = "widget.snapshot"
    private static let logger = Logger(subsystem: "com.vectoralert.alertradar", category: "widgets")

    static func load() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: key)
        else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Store the nearest shelter and refresh the widget — but only when it would actually
    /// read differently.
    ///
    /// Widget reloads are rationed by the system, and the app re-checks its position every
    /// 30 seconds. Republishing a shelter that moved four metres closer would spend that
    /// budget on a screen nobody can see change.
    static func publish(shelter: WidgetSnapshot.NearestShelter?) {
        guard let defaults = UserDefaults(suiteName: appGroup) else {
            logger.error("App Group \(appGroup, privacy: .public) unavailable — widgets will stay empty")
            return
        }
        guard worthPublishing(shelter, over: load()?.shelter) else { return }

        let snapshot = WidgetSnapshot(shelter: shelter, capturedAt: .now)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadTimelines(ofKind: nearestShelterKind)
    }

    /// A different doorway, a change in whether you can get in, or fifty metres of walking.
    private static func worthPublishing(
        _ new: WidgetSnapshot.NearestShelter?, over old: WidgetSnapshot.NearestShelter?
    ) -> Bool {
        guard let new else { return old != nil }
        guard let old else { return true }
        if new.name != old.name || new.isAlwaysOpen != old.isAlwaysOpen || new.hours != old.hours {
            return true
        }
        return abs(new.metres - old.metres) >= 50
    }
}
