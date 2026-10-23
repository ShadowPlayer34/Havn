//
//  ThreatViewModel.swift
//  AlertRadar
//
//  Owns the check state. Location updates are debounced by displacement and by time so a
//  walk down the street does not turn into a request per second.
//

import CoreLocation
import Foundation
import Observation

@Observable
@MainActor
final class ThreatViewModel {
    enum State {
        case idle
        case loading
        case success(ThreatCheckResponse)
        case failure(any Error)

        var response: ThreatCheckResponse? {
            if case .success(let response) = self { return response }
            return nil
        }

        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }

    private(set) var state: State = .idle
    private(set) var lastUpdated: Date?
    /// Received-at ... earliest-arrival, when the response carried an ETA. The fallback
    /// countdown for when there is no overlay geometry to compute a proper window from:
    /// `/check` sends no `updated_at`, so this can only be anchored at the moment it
    /// arrived, and it restarts on every check rather than decaying.
    private(set) var arrivalRange: ClosedRange<Date>?
    /// The first check that came back with a risk, held until a check comes back clear.
    /// `/check` sends no alert start, so this is the closest the app can get without
    /// overlay geometry.
    private(set) var alertStartedAt: Date?
    /// Nearest shelters for the last checked coordinate, closest first.
    private(set) var shelters: [Shelter] = []
    /// Where `shelters` were measured from: their distances, and the direction to them,
    /// are relative to this point rather than to wherever the phone is now.
    private(set) var sheltersOrigin: CLLocationCoordinate2D?
    /// Kept separate from `state` so a failed refresh does not blank the last good answer.
    private(set) var lastGoodResponse: ThreatCheckResponse?

    /// Skip a check unless the user moved this far…
    private let minimumDisplacement: CLLocationDistance = 50
    /// …or this long passed since the last one.
    private let minimumInterval: TimeInterval = 30
    /// How often `run()` re-offers the last known coordinate.
    private let heartbeat: Duration = .seconds(10)

    private let service: any ThreatNetworkServiceProtocol
    @ObservationIgnored private var lastCheckedLocation: CLLocation?
    @ObservationIgnored private var lastCheckedAt: Date?
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    /// Built inside the initialiser rather than as a default argument, so the actor is
    /// created in this type's isolation instead of the caller's.
    init(service: (any ThreatNetworkServiceProtocol)? = nil) {
        self.service = service ?? ThreatNetworkService()
    }

    /// Current risk, falling back to the last good answer while a refresh is in flight.
    var riskLevel: RiskLevel {
        (state.response ?? lastGoodResponse)?.riskLevel ?? .none
    }

    var response: ThreatCheckResponse? { state.response ?? lastGoodResponse }

    /// The register lists one physical location more than once — a school basement and
    /// the same building as a dual-purpose structure are separate rows at identical
    /// coordinates. Two pins on one doorway is noise, so collapse them and keep the
    /// entry a person would rather be sent to: open around the clock first, then
    /// official over community-mapped.
    nonisolated static func deduplicated(_ shelters: [Shelter]) -> [Shelter] {
        var best: [String: Shelter] = [:]
        var order: [String] = []

        for shelter in shelters {
            let key = String(format: "%.5f,%.5f", shelter.latitude, shelter.longitude)
            guard let incumbent = best[key] else {
                best[key] = shelter
                order.append(key)
                continue
            }
            let candidateRank = (shelter.isAlwaysOpen ? 2 : 0) + (shelter.isCityRegister ? 1 : 0)
            let incumbentRank = (incumbent.isAlwaysOpen ? 2 : 0) + (incumbent.isCityRegister ? 1 : 0)
            if candidateRank > incumbentRank {
                best[key] = shelter
            }
        }
        return order.compactMap { best[$0] }
    }

    /// File a report and reflect the new count locally, so the pin the user is looking
    /// at updates without waiting for the next location fix.
    func reportShelter(_ shelter: Shelter, reason: ShelterReportReason) async throws -> Int {
        let total = try await service.reportShelter(id: shelter.id, reason: reason, note: nil)
        if let index = shelters.firstIndex(where: { $0.id == shelter.id }) {
            var updated = shelters
            updated[index] = shelter.withReports(total)
            shelters = updated
        }
        return total
    }

    /// What people who have been there say. Fetched each time the sheet opens rather
    /// than cached: it is read rarely, and only ever by someone looking at it.
    func reviews(for shelter: Shelter) async throws -> ShelterReviewsResponse {
        let response = try await service.shelterReviews(id: shelter.id)
        applyRating(response.rating, to: shelter.id)
        return response
    }

    /// Write or replace this device's review, and carry the new rating to the pin.
    func review(_ shelter: Shelter, _ review: ShelterReviewRequest) async throws -> ShelterReviewsResponse {
        let response = try await service.reviewShelter(id: shelter.id, review: review)
        applyRating(response.rating, to: shelter.id)
        return response
    }

    func withdrawReview(of shelter: Shelter) async throws -> ShelterReviewsResponse {
        let response = try await service.deleteShelterReview(id: shelter.id)
        applyRating(response.rating, to: shelter.id)
        return response
    }

    private func applyRating(_ rating: ShelterRating?, to shelterID: String) {
        guard let index = shelters.firstIndex(where: { $0.id == shelterID }),
              shelters[index].rating != rating
        else { return }
        var updated = shelters
        updated[index] = shelters[index].withRating(rating)
        shelters = updated
    }

    var errorMessage: String? {
        guard case .failure(let error) = state else { return nil }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: Driving

    /// Keeps the risk level current for as long as the app is on screen, whether or not
    /// anybody moves.
    ///
    /// The answer this view model holds is about the *world*, not about where the user is
    /// standing: a threat can enter the district while the phone lies on a table and the
    /// coordinate never changes again. Driven only by location updates, the level would
    /// sit frozen — the symptom being that it moved only after opening the dashboard,
    /// which starts a location stream of its own and incidentally triggered a check.
    ///
    /// Re-*offers* the coordinate rather than forcing a request: `shouldCheck` still
    /// applies, so a movement-driven check that just landed is not thrown away and this
    /// acts as a floor on freshness instead of a second drumbeat competing with the first.
    func run() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: heartbeat)
            } catch {
                return  // cancelled — the app went away
            }
            // Nothing to re-check until a fix has produced a first answer. The screen
            // already says it is waiting for location in that state.
            guard let location = lastCheckedLocation else { continue }
            check(at: location, force: false)
        }
    }

    /// Consumes location updates for as long as the view is on screen.
    func observe(_ locationManager: LocationManager) async {
        for await location in locationManager.locationUpdates {
            check(at: location, force: false)
        }
    }

    /// Pull-to-refresh: always goes to the network, and awaits the result so the spinner
    /// stays up for as long as the work does.
    func refresh(coordinate: CLLocationCoordinate2D?) async {
        guard let coordinate else { return }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        check(at: location, force: true)
        await inFlight?.value
    }

    func check(at location: CLLocation, force: Bool) {
        guard force || shouldCheck(for: location) else { return }

        inFlight?.cancel()
        lastCheckedLocation = location
        lastCheckedAt = .now
        state = .loading

        inFlight = Task { [service] in
            do {
                let response = try await service.checkThreat(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
                guard !Task.isCancelled else { return }
                lastGoodResponse = response
                lastUpdated = .now
                // Same fix, same round trip. Shelters change far more slowly than
                // threats, so a failure here must not disturb the risk answer.
                if let fetched = try? await service.nearestShelters(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    limit: 8
                ) {
                    shelters = Self.deduplicated(fetched)
                    sheltersOrigin = location.coordinate
                    // The widgets have no network and no location of their own — this
                    // write is the only way a real distance reaches the home screen.
                    // Left alone on a failed fetch, so the last good answer survives.
                    WidgetSnapshotStore.publish(
                        shelter: shelters.first.map(WidgetSnapshot.NearestShelter.init)
                    )
                }
                if let minutes = response.etaMinutes, minutes > 0 {
                    let now = Date.now
                    arrivalRange = now...now.addingTimeInterval(Double(minutes) * 60)
                } else {
                    arrivalRange = nil
                }
                if response.riskLevel == .none {
                    alertStartedAt = nil
                } else if alertStartedAt == nil {
                    alertStartedAt = .now
                }
                state = .success(response)
            } catch is CancellationError {
                // Superseded by a newer check — leave the state to the newer one.
            } catch {
                guard !Task.isCancelled else { return }
                // A failed check should not clear the last known risk; the view keeps
                // showing it alongside the error.
                state = .failure(error)
            }
        }
    }

    /// Displacement OR elapsed time — either one on its own is enough to justify a check.
    private func shouldCheck(for location: CLLocation) -> Bool {
        guard let lastCheckedLocation, let lastCheckedAt else { return true }
        if location.distance(from: lastCheckedLocation) >= minimumDisplacement { return true }
        if Date.now.timeIntervalSince(lastCheckedAt) >= minimumInterval { return true }
        return false
    }

    func cancel() {
        inFlight?.cancel()
        inFlight = nil
    }
}
