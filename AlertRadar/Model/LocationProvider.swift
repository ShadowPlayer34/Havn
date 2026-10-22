import CoreLocation
import MapKit
import Observation

/// Real device location. `CLLocationUpdate.liveUpdates()` asks for When In Use authorisation
/// on the first call, so there is no separate permission dance to run.
@Observable
final class LocationProvider {
    private(set) var coordinate: CLLocationCoordinate2D?
    /// The raw fix, for consumers that need distance maths.
    private(set) var lastFix: CLLocation?
    private(set) var placeName: String?
    private(set) var authorizationDenied = false

    @ObservationIgnored private var lastGeocoded: CLLocation?
    @ObservationIgnored private var isResolvingName = false

    /// Solomianskyi, Kyiv — the design document's sample location, used until a fix arrives
    /// and whenever location is unavailable.
    static let fallback = CLLocationCoordinate2D(latitude: 50.4272, longitude: 30.4870)
    static let fallbackPlaceName = "Solomianskyi"

    /// The coordinate every overlay is anchored to.
    var anchor: CLLocationCoordinate2D { coordinate ?? Self.fallback }
    /// Never claims the sample place name once a real fix exists.
    var displayName: String { placeName ?? (hasFix ? String(localized: "Current location") : Self.fallbackPlaceName) }
    /// True once a real fix has been used to place the scenario.
    var hasFix: Bool { coordinate != nil }

    func start() async {
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if update.authorizationDenied || update.authorizationDeniedGlobally {
                    authorizationDenied = true
                    return
                }
                guard let location = update.location else { continue }
                coordinate = location.coordinate
                lastFix = location
                resolvePlaceNameIfNeeded(for: location)
            }
        } catch {
            // Updates stopped (simulator with no location, or the service was cut off).
            // The fallback coordinate keeps every surface readable.
        }
    }

    /// The capsule names where you actually are. Retries while the name is still unknown —
    /// the first lookup often lands before the network is up — and refreshes once you have
    /// moved far enough for the answer to change.
    private func resolvePlaceNameIfNeeded(for location: CLLocation) {
        guard !isResolvingName else { return }
        if placeName != nil, let last = lastGeocoded, location.distance(from: last) < 300 { return }

        isResolvingName = true
        lastGeocoded = location
        Task {
            defer { isResolvingName = false }
            guard let request = MKReverseGeocodingRequest(location: location),
                  let item = try? await request.mapItems.first
            else { return }
            placeName = item.addressRepresentations?.cityWithContext(.short)
                ?? item.address?.shortAddress
                ?? item.name
        }
    }
}

extension CLLocationCoordinate2D {
    /// Offset by metres — north/east on the local tangent plane. Accurate enough at city scale.
    func offset(north: Double, east: Double) -> CLLocationCoordinate2D {
        let metresPerDegree = 111_320.0
        return CLLocationCoordinate2D(
            latitude: latitude + north / metresPerDegree,
            longitude: longitude + east / (metresPerDegree * cos(latitude * .pi / 180))
        )
    }

    /// Offset by a compass bearing in degrees and a distance in metres.
    func offset(bearing: Double, metres: Double) -> CLLocationCoordinate2D {
        let radians = bearing * .pi / 180
        return offset(north: metres * cos(radians), east: metres * sin(radians))
    }
}
