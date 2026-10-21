import ActivityKit
import Foundation
import Observation

/// Starts, feeds and ends the threat Live Activity.
///
/// The widget ticks its own progress bar and countdown from the dates in the content state,
/// so this only has to push when the *words* change — which, on a live threat, is about
/// once a minute as the window decays.
@Observable
final class LiveActivityController {
    private(set) var activity: Activity<ThreatActivityAttributes>?
    private(set) var lastError: String?

    /// The latest description of the threat, fed in by whoever owns the data. Held so the
    /// start button does not have to reach across the app to assemble one, and so an
    /// activity started mid-alert opens with the current state rather than a blank.
    @ObservationIgnored private(set) var latest: ThreatActivityAttributes.ContentState?

    var isRunning: Bool { activity != nil }
    var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Accept a new reading. Pushes only if it actually says something different: the
    /// countdown on screen is running off dates the widget already has, so re-sending an
    /// identical state would cost energy and change nothing.
    func submit(_ state: ThreatActivityAttributes.ContentState) {
        guard saysSomethingNew(state) else { return }
        // Only reached when the content actually changed, so this timestamp is a
        // statement about the words on screen rather than about the last poll.
        var state = state
        state.updated = .now
        latest = state

        guard let activity else { return }
        Task { await activity.update(content(state)) }
    }

    func start() {
        guard activity == nil else { return }
        guard isAvailable else {
            lastError = "Live Activities are turned off for AlertRadar in Settings."
            return
        }
        guard let latest else {
            lastError = "No sector reading yet — the activity would have nothing to show."
            return
        }

        do {
            activity = try Activity.request(
                attributes: ThreatActivityAttributes(),
                content: content(latest)
            )
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// Everything except the timestamp: a state that differs only in `updated` is the same
    /// sentence written again.
    private func saysSomethingNew(_ state: ThreatActivityAttributes.ContentState) -> Bool {
        guard let latest else { return true }
        return state.area != latest.area
            || state.threat != latest.threat
            || state.status != latest.status
            || state.arrival != latest.arrival
            || state.safetyPercent != latest.safetyPercent
    }

    /// Past the far edge of the window we have said all we know, and the system should dim
    /// the activity rather than let it read as current.
    private func content(
        _ state: ThreatActivityAttributes.ContentState
    ) -> ActivityContent<ThreatActivityAttributes.ContentState> {
        ActivityContent(
            state: state,
            staleDate: state.arrival?.latest.addingTimeInterval(60)
                ?? Date.now.addingTimeInterval(15 * 60)
        )
    }
}
