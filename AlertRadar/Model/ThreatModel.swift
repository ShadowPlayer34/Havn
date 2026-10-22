import Foundation
import Observation

/// Shared state behind the three surfaces: the map, the Live Activity and the feed.
/// Mirrors the design document's component logic — same countdown, same derived labels.
@Observable
final class ThreatModel {
    /// Threat model knob from the design doc (range 2–40 min, default 12).
    var threatMinutes: Int = 12 {
        didSet { resetCountdown() }
    }
    private(set) var secondsRemaining: Int = 718

    // Map layers
    var showRiskArea = true
    var showHavens = true

    // Feed
    var filter: FeedCategory = .all
    var expandedItems: Set<String> = []

    // Lock screen widget
    var gaugeIndex = 0

    // Presentation
    var safetySheetOpen = false
    var feedDrawerOpen = false
    var systemSurfacesOpen = false
    var dashboardOpen = false
    var emergencyOpen = false
    var guidesOpen = false

    // MARK: Countdown

    var total: Int { max(1, threatMinutes) * 60 }

    func resetCountdown() {
        secondsRemaining = total - 2
    }

    /// Ticks once a second and loops, exactly like the design preview.
    func runCountdown() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            secondsRemaining = secondsRemaining > 1 ? secondsRemaining - 1 : total
        }
    }

    // MARK: Derived labels

    /// Shared with the widget extension so the two can never word the window differently.
    var etaLabel: String { ArrivalWindow.label(secondsRemaining: secondsRemaining) }
    var etaShort: String { ArrivalWindow.shortLabel(secondsRemaining: secondsRemaining) }
    var islandLabel: String { String(localized: "\(etaShort) • Risk") }

    /// Earliest arrival is two minutes ahead of the midpoint estimate.
    private var earliestSeconds: Int { max(0, secondsRemaining - 120) }

    var earliestArrival: String {
        "\(earliestSeconds / 60):" + String(format: "%02d", earliestSeconds % 60)
    }

    var progress: Double { 1 - Double(secondsRemaining) / Double(total) }

    // MARK: Feed

    var visibleFeed: [FeedItem] {
        filter == .all ? FeedItem.all : FeedItem.all.filter { $0.category == filter }
    }

    var feedMeta: String { String(localized: "\(visibleFeed.count) of \(FeedItem.all.count) · de-duplicated") }

    func toggleExpanded(_ item: FeedItem) {
        if expandedItems.contains(item.id) {
            expandedItems.remove(item.id)
        } else {
            expandedItems.insert(item.id)
        }
    }

    // MARK: Lock screen gauge

    var gauge: SafetyGauge { SafetyGauge.all[gaugeIndex % SafetyGauge.all.count] }

    func cycleGauge() {
        gaugeIndex = (gaugeIndex + 1) % SafetyGauge.all.count
    }
}
