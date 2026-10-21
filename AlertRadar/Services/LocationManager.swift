//
//  LocationManager.swift
//  AlertRadar
//
//  CLLocationManager wrapper. Ten-metre accuracy with a 25 m distance filter: precise
//  enough to place someone inside or outside a sector, cheap enough to leave running.
//

import CoreLocation
import Observation

@Observable
@MainActor
final class LocationManager {
    private(set) var currentLocation: CLLocationCoordinate2D?
    private(set) var lastFix: CLLocation?
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var lastError: String?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var delegate: Delegate?
    @ObservationIgnored private var continuations: [UUID: AsyncStream<CLLocation>.Continuation] = [:]

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    init() {
        authorizationStatus = manager.authorizationStatus
        let delegate = Delegate()
        delegate.owner = self
        self.delegate = delegate

        manager.delegate = delegate
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        // The OS drops updates smaller than this before they ever reach us.
        manager.distanceFilter = 25
        manager.pausesLocationUpdatesAutomatically = true
    }

    /// Asks for When In Use and starts updates as soon as it is granted.
    func requestAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            start()
        default:
            break
        }
    }

    func start() {
        guard isAuthorized else { return }
        manager.startUpdatingLocation()
        manager.requestLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    /// Every accepted fix, for consumers that want to react rather than poll.
    var locationUpdates: AsyncStream<CLLocation> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            if let lastFix { continuation.yield(lastFix) }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in self?.continuations[id] = nil }
            }
        }
    }

    // MARK: Delegate plumbing

    fileprivate func handle(location: CLLocation) {
        lastError = nil
        lastFix = location
        currentLocation = location.coordinate
        for continuation in continuations.values {
            continuation.yield(location)
        }
    }

    fileprivate func handle(authorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        if isAuthorized {
            start()
        } else if isDenied {
            stop()
        }
    }

    fileprivate func handle(error: any Error) {
        // A transient "unknown location" is normal indoors; keep the last good fix.
        if let clError = error as? CLError, clError.code == .locationUnknown { return }
        lastError = error.localizedDescription
    }

    private final class Delegate: NSObject, CLLocationManagerDelegate {
        weak var owner: LocationManager?

        nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let latest = locations.last else { return }
            Task { @MainActor [weak owner] in owner?.handle(location: latest) }
        }

        nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            let status = manager.authorizationStatus
            Task { @MainActor [weak owner] in owner?.handle(authorization: status) }
        }

        nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
            Task { @MainActor [weak owner] in owner?.handle(error: error) }
        }
    }
}
