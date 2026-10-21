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

    var body: some View {
        RadarMapScreen()
            .environment(model)
            .environment(liveActivity)
            .environment(threats)
            .environment(zones)
            .preferredColorScheme(.dark)
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
