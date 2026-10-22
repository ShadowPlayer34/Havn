import SwiftUI

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var model = ThreatModel()
    @State private var liveActivity = LiveActivityController()
    /// One checker shared by the map and the dashboard, so the two can never disagree.
    @State private var threats = ThreatViewModel()
    /// The map overlay. Polled on its own clock and independent of location — the zones
    /// payload is the same for every client and needs no coordinate to fetch.
    @State private var zones = ThreatZonesViewModel()
    /// Shared by the map and the SOS / Guides tabs.
    @State private var location = LocationProvider()
    /// Watches the district picked in "My District" — off the same overlay, no location.
    @State private var districtAlerts = DistrictAlertMonitor()

    var body: some View {
        TabView {
            Tab("Map", systemImage: "map") {
                RadarMapScreen(location: location)
            }
            Tab("SOS", systemImage: "phone.fill") {
                EmergencyServicesSheet(coordinate: location.coordinate)
            }
            Tab("Guides", systemImage: "cross.case") {
                EmergencyGuidesSheet(coordinate: location.coordinate)
            }
            Tab("Feed", systemImage: "list.bullet.rectangle") {
                CleanFeedDrawer(embedded: true)
            }
        }
            .environment(model)
            .environment(liveActivity)
            .environment(threats)
            .environment(zones)
            .environment(districtAlerts)
            .preferredColorScheme(.dark)
            // A fresh payload, and every prune between payloads: a zone lapsing on its own
            // `expires_at` is an all-clear too.
            .onChange(of: zones.lastUpdated) { districtAlerts.evaluate(zones) }
            .onChange(of: zones.tick) { districtAlerts.evaluate(zones) }
            .task { await location.start() }
            .task { await model.runCountdown() }
            .task { await zones.run() }
            // The sector check needs its own clock for the same reason the overlay does:
            // left to location updates alone it only refreshes when the user moves.
            .task { await threats.run() }
    }
}

#Preview {
    ContentView()
}
