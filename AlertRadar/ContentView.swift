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
            .preferredColorScheme(.dark)
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
