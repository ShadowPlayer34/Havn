import Foundation
import Observation
import UserNotifications
import WidgetKit

/// Keeps the home district's alert state current while the app runs, and says so out loud
/// when it changes: "🔴 Alert in Kyiv: Shevchenkivskyi district".
///
/// These are local notifications, raised from the overlay the app is already polling — so
/// they only fire while the app is alive. Reaching a phone whose app is closed needs APNs
/// (ROADMAP 1.2); until then the widget covers that case on its own timeline.
@Observable
final class DistrictAlertMonitor: NSObject, UNUserNotificationCenterDelegate {
    private(set) var district: KyivDistrict? = DistrictAlertStore.homeDistrict
    private(set) var state: DistrictAlertState? = DistrictAlertStore.load()
    /// Nil until the system has been asked.
    private(set) var notificationsAllowed: Bool?

    /// How long the district must stay clear before the all-clear is announced. Reports
    /// expire one by one, and "all clear" followed a minute later by "alert" is worse than
    /// a short wait — see `DistrictAlertStore.resumeWindow`, which this sits inside.
    private let clearHold: TimeInterval = 90

    /// Whether the last notification sent was an alert, so a relaunch does not announce
    /// again what was already said — and does announce what changed while it was closed.
    @ObservationIgnored private var announced: Announced? {
        get {
            UserDefaults.standard.data(forKey: Self.announcedKey)
                .flatMap { try? JSONDecoder().decode(Announced.self, from: $0) }
        }
        set {
            UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.announcedKey)
        }
    }

    private struct Announced: Codable {
        var district: KyivDistrict
        var alerted: Bool
    }

    private static let announcedKey = "district.announced"

    override init() {
        super.init()
        // Without a delegate a notification raised while the app is in front is dropped,
        // and in front is exactly where this one is raised.
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: Choosing

    /// The moment someone picks a district is the moment asking for notifications makes
    /// sense to them, so this is where it is asked.
    func choose(_ district: KyivDistrict, zones: ThreatZonesViewModel) async {
        DistrictAlertStore.setHomeDistrict(district)
        self.district = district
        state = nil
        announced = nil
        evaluate(zones)

        let granted = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
        notificationsAllowed = granted ?? false
    }

    func refreshAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: notificationsAllowed = true
        case .denied: notificationsAllowed = false
        default: notificationsAllowed = nil
        }
    }

    // MARK: Watching

    /// Fold the overlay in hand into the district's state. Only a read that actually
    /// succeeded counts — a backend that stopped answering is not an all-clear.
    func evaluate(_ zones: ThreatZonesViewModel) {
        guard let district, zones.hasLoaded, zones.lastError == nil else { return }
        let now = Date.now
        let alert = district.alert(in: zones.zones, at: now)
        guard let next = DistrictAlertStore.record(
            level: alert.level, earliestReport: alert.earliestReport, at: now
        ) else { return }

        if !next.reads(sameAs: state) {
            WidgetCenter.shared.reloadTimelines(ofKind: DistrictAlertStore.kind)
        }
        state = next
        announce(next, at: now)
    }

    /// Only a direct hit is announced, and the all-clear only once nothing at all is left
    /// over the district. `nearby` stays silent either way: a missile's corridor crosses
    /// every district in the city, and a buffer still reaching yours is not "all clear".
    private func announce(_ state: DistrictAlertState, at now: Date) {
        guard let last = announced, last.district == state.district else {
            // First look at this district: what is already true is not news.
            announced = Announced(district: state.district, alerted: state.level == .alert)
            return
        }

        if state.level == .alert, !last.alerted {
            post(alertContent(for: state))
            announced = Announced(district: state.district, alerted: true)
        } else if state.level == .clear, last.alerted,
                  let ended = state.endedAt, now.timeIntervalSince(ended) >= clearHold {
            post(clearContent(for: state, endedAt: ended))
            announced = Announced(district: state.district, alerted: false)
        }
    }

    // MARK: Notifications

    private func alertContent(for state: DistrictAlertState) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "🔴 Alert in Kyiv: \(state.district.name)")
        // The nearest shelter is the one the app last measured from where the phone was,
        // which is where its owner has to walk from. Older than an hour it is not offered.
        if let snapshot = WidgetSnapshotStore.load(), let shelter = snapshot.shelter,
           Date.now.timeIntervalSince(snapshot.capturedAt) < 3_600 {
            content.body = String(localized: "Go to a shelter. Nearest — \(shelter.name), \(distanceLabel(shelter.metres)).")
        } else {
            content.body = String(localized: "Go to a shelter.")
        }
        content.sound = .default
        return content
    }

    private func clearContent(for state: DistrictAlertState, endedAt: Date) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "🟢 All clear in Kyiv: \(state.district.name)")
        if let started = state.startedAt {
            let minutes = max(1, Int(endedAt.timeIntervalSince(started) / 60))
            content.body = String(localized: "The alert lasted \(minutes) min. You can leave the shelter.")
        } else {
            content.body = String(localized: "You can leave the shelter.")
        }
        content.sound = .default
        return content
    }

    private func post(_ content: UNMutableNotificationContent) {
        // One thread, so a night of alerts stacks as one conversation in Notification Centre.
        content.threadIdentifier = DistrictAlertStore.kind
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// "240 m" / "1.4 km" — the wording the shelter widget uses for the same number.
    private func distanceLabel(_ metres: Int) -> String {
        metres < 1_000 ? String(localized: "\(metres) m") : String(format: String(localized: "%.1f km"), Double(metres) / 1_000)
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
