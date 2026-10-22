//
//  ThreatZonesViewModel.swift
//  AlertRadar
//
//  Holds the map overlay: one poll of GET /api/v1/threats/zones, revalidated with the
//  ETag from the previous answer, and the local clock work that keeps it honest between
//  polls — dropping zones as they expire and decaying the arrival window every tick.
//
//  Deliberately knows nothing about where the user is. The overlay is the same payload
//  for every client, and fetching it tells the server nothing.
//

import CoreLocation
import Foundation
import Observation

@Observable
@MainActor
final class ThreatZonesViewModel {
    /// Live zones, already stripped of anything past its `expires_at`.
    private(set) var zones: [ThreatZone] = []
    /// Last successful exchange, 304s included — this is "the overlay is current", not
    /// "the overlay changed".
    private(set) var lastUpdated: Date?
    private(set) var lastError: (any Error)?
    /// True once a payload has landed. Until then the map has no geometry to draw and
    /// falls back to the locally generated wash.
    private(set) var hasLoaded = false

    /// Moves on every prune. Anything rendering a decaying label reads this so the label
    /// is recomputed as it ages, without a one-second timer invalidating the whole map.
    private(set) var tick: Date = .now

    /// The unpruned payload. Kept whole so pruning is a filter over the server's own data
    /// rather than a destructive edit we could never undo without re-fetching.
    @ObservationIgnored private var payload: [ThreatZone] = []
    @ObservationIgnored private var etag: String?

    /// The worker batches Telegram messages over 45 s, so the snapshot version cannot
    /// move faster than that. Polling at half the window sees a new one within a batch,
    /// and the steady state costs a 304 with no body.
    private let pollInterval: Duration = .seconds(30)
    /// Expiry is enforced locally between polls: `expires_at` can pass a full janitor
    /// interval before the version bumps and the payload stops mentioning the zone.
    private let pruneInterval: Duration = .seconds(10)
    /// A failed poll is worth retrying sooner than a successful one — but not so soon
    /// that a dead backend turns into a request loop.
    private let retryInterval: Duration = .seconds(10)

    private let service: any ThreatNetworkServiceProtocol

    init(service: (any ThreatNetworkServiceProtocol)? = nil) {
        self.service = service ?? ThreatNetworkService()
    }

    /// Distinct threats among the live zones. Counting Features would overcount — every
    /// threat travels as a `core` and a `risk` shape, and the merged drawing layer carries
    /// one synthetic Feature per threat type on top of that.
    var activeThreatCount: Int {
        Set(zones.filter { $0.kind.isThreatShape }.map(\.threatID)).count
    }

    var errorMessage: String? {
        guard let lastError else { return nil }
        return (lastError as? LocalizedError)?.errorDescription ?? lastError.localizedDescription
    }

    // MARK: Driving

    /// Runs for as long as the app is on screen: fetch, then prune every few seconds
    /// until the next fetch is due.
    func run() async {
        while !Task.isCancelled {
            await refresh()

            var waited: Duration = .zero
            let interval = lastError == nil ? pollInterval : retryInterval
            while waited < interval {
                do {
                    try await Task.sleep(for: pruneInterval)
                } catch {
                    return  // cancelled — the view went away
                }
                waited += pruneInterval
                prune()
            }
        }
    }

    /// One conditional fetch. A 304 is a success: it confirms the payload in hand.
    func refresh() async {
        do {
            switch try await service.threatZones(ifNoneMatch: etag) {
            case .unchanged:
                lastUpdated = .now
                lastError = nil
            case .updated(let collection, let newETag):
                etag = newETag
                payload = collection.zones
                zones = collection.active(at: .now)
                hasLoaded = true
                lastUpdated = .now
                lastError = nil
            }
        } catch is CancellationError {
            // Superseded or torn down; leave the last payload alone.
        } catch {
            // The overlay stays on screen. Zones carry their own expiry, so a backend we
            // cannot reach empties the map on its own within one TTL instead of freezing
            // a stale threat there for ever.
            lastError = error
        }
    }

    private func prune() {
        tick = .now
        let live = payload.filter { $0.expiresAt > tick }
        // Pruning only ever removes, so the count settles it — and skipping the write
        // keeps the map from re-diffing its overlays every few seconds.
        guard live.count != zones.count else { return }
        zones = live
    }

    // MARK: Reading the overlay

    /// The threat most worth naming at a coordinate, ranked the way the backend ranks
    /// overlapping threats: a direct hit first, then missile over shahed over recon, then
    /// confidence. `directHit` rather than `kind == .core` on purpose — that is the same
    /// gate `ThreatIndex.lookup` applies before it will rank a shape as a hit.
    ///
    /// This picks *which* threat's arrival window to show. It is not a second opinion on
    /// the risk level — that stays with `/threats/check`, which runs the same test against
    /// unsimplified geometry. Measured against the live gazetteer, thinning moves an
    /// oblast-sized boundary by up to 4.3 km and paints ~985 km² as core that is not, so
    /// the two genuinely disagree well inland, not just along an edge. The server wins.
    ///
    /// Merged shapes are skipped: they span several threats, so a count or an arrival
    /// window read off one would belong to no particular threat.
    func dominantZone(at coordinate: CLLocationCoordinate2D) -> ThreatZone? {
        var best: ThreatZone?
        var bestRank = (-1, -1, -1.0)

        for zone in zones where zone.kind.isThreatShape && zone.contains(coordinate) {
            let isHit = zone.kind == .core && zone.directHit
            let rank = (isHit ? 2 : 1, zone.threatType.priority, zone.confidence)
            if rank > bestRank {
                bestRank = rank
                best = zone
            }
        }
        return best
    }

    /// The earliest report among every threat standing over a coordinate. Each new report
    /// arrives as a threat of its own, so reading `firstSeenAt` off the dominant zone alone
    /// restarts the clock whenever a newer threat outranks the one that started the alert.
    func earliestFirstSeen(at coordinate: CLLocationCoordinate2D) -> Date? {
        zones
            .filter { $0.kind.isThreatShape && $0.contains(coordinate) }
            .map(\.firstSeenAt)
            .min()
    }
}
