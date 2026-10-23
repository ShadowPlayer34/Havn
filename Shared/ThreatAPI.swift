import Foundation

nonisolated enum ThreatAPI {
    /// Override per environment with a `ThreatAPIBaseURL` string in the Info.plist of the
    /// bundle asking — the app's, and the widget extension's for the district widget,
    /// which reads the overlay itself when the app is not running.
    static var baseURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "ThreatAPIBaseURL") as? String,
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "http://127.0.0.1:8000")!
    }

    static let checkPath = "/api/v1/threats/check"
    static let nearestSheltersPath = "/api/v1/shelters/nearest"
    /// One shelter's own endpoints hang off this: `/{id}/report`, `/{id}/reviews`, `/{id}/review`.
    static let sheltersPath = "/api/v1/shelters"
    static let zonesPath = "/api/v1/threats/zones"

    /// Fail fast. The caller retries on the next location update.
    static let requestTimeout: TimeInterval = 4
    static let resourceTimeout: TimeInterval = 8
    /// The overlay is tens of kilobytes rather than a couple of hundred bytes, and the map
    /// keeps drawing the last payload while it is in flight — worth waiting longer for than
    /// an answer about the coordinate someone is standing on. Capped by the session's
    /// resource timeout, which is what this matches: a longer value would not buy anything.
    static let zonesTimeout: TimeInterval = resourceTimeout
}
