import SwiftUI
import WidgetKit

@main
struct AlertRadarWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ThreatLiveActivity()
        SafetyGaugeWidget()
        NearestShelterWidget()
    }
}
