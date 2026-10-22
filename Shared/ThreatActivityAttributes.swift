import ActivityKit
import Foundation

/// The Live Activity contract, shared by the app and the widget extension.
///
/// Dates rather than pre-rendered numbers wherever the system can tick something itself:
/// the progress bar and the countdown run locally in the widget, so the activity stays
/// live between updates instead of freezing on the last pushed value.
///
/// Everything the reader sees lives in `ContentState`. `ActivityAttributes` are fixed at
/// `Activity.request` and can never be updated — a place name or a threat type put there
/// would be stuck at whatever was known when the activity started, which for this app is
/// usually "nothing yet".
struct ThreatActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The district the server's own gazetteer names, or the reverse-geocoded place.
        /// Nil when the device has no fix — the app holds a fallback coordinate so the map
        /// has somewhere to point, and naming that district here would tell someone they
        /// are standing in a place they are not.
        var area: String?
        /// "6 Shahed · area estimate"
        var threat: String
        /// One sentence of what this means for the person reading it.
        var status: String
        /// Nil when nothing is inbound. An empty countdown frame reads as broken rather
        /// than calm, so the widget drops the whole block instead of showing zeroes.
        var arrival: Arrival?
        /// Nil until there is a real measurement behind it. See the note in the widget.
        var safetyPercent: Int?
        /// When the content below last changed — not when it was last pushed.
        var updated: Date

        var title: String { area.map { String(localized: "Risk Area: \($0)") } ?? String(localized: "Threat status") }
    }

    /// The arrival window as instants, so the widget can run the clock itself.
    struct Arrival: Codable, Hashable {
        /// When the report this estimate came from landed. The bar fills from here, which
        /// is what makes it advance across pushes instead of restarting at each one.
        var reportedAt: Date
        /// Earliest the threat can reach the sector.
        var earliest: Date
        /// Latest edge of the estimate.
        var latest: Date
        /// "9–14m" — the window as the design writes it.
        var label: String

        var progressRange: ClosedRange<Date> {
            reportedAt...max(reportedAt.addingTimeInterval(1), earliest)
        }
    }
}

/// The design document's own widening, kept for the mockups on the system-surfaces screen.
///
/// The real activity does not use it: its window comes from `ArrivalEstimate`, which is a
/// port of the backend's `format_eta_window` and has to agree with the server to the minute.
enum ArrivalWindow {
    /// Midpoint minute widened by −2 / +3, matching the design document's logic.
    static func bounds(secondsRemaining: Int) -> (lo: Int, hi: Int) {
        let mid = max(1, Int((Double(secondsRemaining) / 60).rounded(.up)))
        return (max(1, mid - 2), mid + 3)
    }

    static func label(secondsRemaining: Int) -> String {
        let window = bounds(secondsRemaining: secondsRemaining)
        return String(localized: "\(window.lo)–\(window.hi) min")
    }

    static func shortLabel(secondsRemaining: Int) -> String {
        let window = bounds(secondsRemaining: secondsRemaining)
        return String(localized: "\(window.lo)–\(window.hi)m")
    }
}
