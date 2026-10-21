//
//  ThreatNetworkService.swift
//  AlertRadar
//
//  Talks to GET /api/v1/threats/check, /shelters/nearest and /threats/zones. Short
//  timeouts by design: a threat check that arrives late is worse than one that fails fast
//  and retries on the next fix.
//

import Foundation

// MARK: - Configuration

nonisolated enum ThreatAPI {
    /// Override per environment with a `ThreatAPIBaseURL` string in the app's Info.plist.
    static var baseURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "ThreatAPIBaseURL") as? String,
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "http://127.0.0.1:8000")!
    }

    static let checkPath = "/api/v1/threats/check"
    static let nearestSheltersPath = "/api/v1/shelters/nearest"
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

// MARK: - Errors

nonisolated enum ThreatServiceError: LocalizedError, Equatable {
    case invalidURL
    case offline
    case timedOut
    case server(status: Int)
    case rateLimited
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Could not build the request URL."
        case .offline: "No network connection."
        case .timedOut: "The threat service did not answer in time."
        case .server(let status): "The threat service returned an error (\(status))."
        case .rateLimited: "Too many checks — easing off for a moment."
        case .decoding: "The threat service sent an unexpected response."
        case .transport(let message): message
        }
    }

    /// Whether an immediate retry is worth attempting.
    var isTransient: Bool {
        switch self {
        case .offline, .timedOut, .rateLimited: true
        case .server(let status): status >= 500
        case .invalidURL, .decoding, .transport: false
        }
    }
}

// MARK: - Conditional fetch

/// Outcome of a revalidated GET. `unchanged` carries nothing on purpose: the caller
/// already holds the payload, and a 304 has no body to hand back.
nonisolated enum ThreatZonesResult: Sendable {
    case unchanged
    case updated(ThreatZoneCollection, etag: String?)
}

// MARK: - Protocol

protocol ThreatNetworkServiceProtocol: Sendable {
    func checkThreat(latitude: Double, longitude: Double) async throws -> ThreatCheckResponse
    func nearestShelters(latitude: Double, longitude: Double, limit: Int) async throws -> [Shelter]
    func reportShelter(id: String, reason: ShelterReportReason, note: String?) async throws -> Int
    func threatZones(ifNoneMatch etag: String?) async throws -> ThreatZonesResult
}

// MARK: - Implementation

actor ThreatNetworkService: ThreatNetworkServiceProtocol {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    init(baseURL: URL = ThreatAPI.baseURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.session = session ?? Self.makeSession()
        self.decoder = JSONDecoder()
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = ThreatAPI.requestTimeout
        configuration.timeoutIntervalForResource = ThreatAPI.resourceTimeout
        // Fail rather than queue: a stale answer is not useful here.
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        return URLSession(configuration: configuration)
    }

    func checkThreat(latitude: Double, longitude: Double) async throws -> ThreatCheckResponse {
        try await get(
            path: ThreatAPI.checkPath,
            query: [
                URLQueryItem(name: "latitude", value: String(latitude)),
                URLQueryItem(name: "longitude", value: String(longitude))
            ]
        )
    }

    func nearestShelters(latitude: Double, longitude: Double, limit: Int) async throws -> [Shelter] {
        let response: NearestSheltersResponse = try await get(
            path: ThreatAPI.nearestSheltersPath,
            query: [
                URLQueryItem(name: "latitude", value: String(latitude)),
                URLQueryItem(name: "longitude", value: String(longitude)),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        )
        return response.shelters
    }

    func reportShelter(id: String, reason: ShelterReportReason, note: String?) async throws -> Int {
        let body = ShelterReportRequest(reason: reason, note: note, clientId: ReportingClient.id)
        let ack: ShelterReportAck = try await post(
            path: "\(ThreatAPI.nearestSheltersPath.replacingOccurrences(of: "/nearest", with: ""))/\(id)/report",
            body: body
        )
        return ack.reports
    }

    private func post<Body: Encodable, T: Decodable>(path: String, body: Body) async throws -> T {
        guard let url = URLComponents(
            url: baseURL.appending(path: path), resolvingAgainstBaseURL: false
        )?.url else { throw ThreatServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = ThreatAPI.requestTimeout
        request.httpBody = try JSONEncoder().encode(body)

        let (data, http) = try await send(request)
        guard (200..<300).contains(http.statusCode) else {
            throw ThreatServiceError.server(status: http.statusCode)
        }
        return try decode(T.self, from: data)
    }

    /// One transport for every endpoint: same timeouts, same error mapping.
    private func get<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
        let request = try makeRequest(path: path, query: query)
        let (data, http) = try await send(request)

        switch http.statusCode {
        case 200..<300:
            break
        case 429:
            throw ThreatServiceError.rateLimited
        default:
            throw ThreatServiceError.server(status: http.statusCode)
        }

        return try decode(T.self, from: data)
    }

    /// Every request goes out through here, so a cancelled task, a timeout and a dead
    /// radio are reported the same way whichever endpoint was being called. Status codes
    /// are deliberately *not* interpreted: `/zones` treats 304 as success and the others
    /// treat it as nonsense.
    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            case .timedOut: throw ThreatServiceError.timedOut
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw ThreatServiceError.offline
            default:
                throw ThreatServiceError.transport(error.localizedDescription)
            }
        }

        guard let http = response as? HTTPURLResponse else {
            throw ThreatServiceError.transport("Malformed response.")
        }
        return (data, http)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw ThreatServiceError.decoding(String(describing: error))
        }
    }

    /// The map overlay, revalidated against the ETag of the payload already in hand.
    ///
    /// The 304 is handled here rather than left to `URLCache`. This session is ephemeral
    /// and runs `.reloadIgnoringLocalCacheData`, so the loader holds no copy of the body
    /// to substitute — a "Not Modified" arrives as a 200-shaped response with zero bytes,
    /// and decoding it would blank the overlay every poll. The caller keeps the last
    /// payload; `unchanged` tells it to go on drawing what it has.
    func threatZones(ifNoneMatch etag: String?) async throws -> ThreatZonesResult {
        var request = try makeRequest(path: ThreatAPI.zonesPath, query: [])
        request.setValue("application/geo+json, application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = ThreatAPI.zonesTimeout
        // Sent back verbatim, weak validator prefix and all: the server compares the raw
        // header value against the tag it issued.
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, http) = try await send(request)

        switch http.statusCode {
        case 304:
            return .unchanged
        case 200..<300:
            break
        case 429:
            throw ThreatServiceError.rateLimited
        default:
            throw ThreatServiceError.server(status: http.statusCode)
        }

        let collection = try decode(ThreatZoneCollection.self, from: data)
        return .updated(collection, etag: http.value(forHTTPHeaderField: "ETag"))
    }

    private func makeRequest(path: String, query: [URLQueryItem]) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        ) else {
            throw ThreatServiceError.invalidURL
        }
        // Empty rather than nil would leave a bare "?" on the URL.
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw ThreatServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = ThreatAPI.requestTimeout
        return request
    }
}

// MARK: - Test double

/// Injectable stand-in for previews and tests.
nonisolated struct StubThreatNetworkService: ThreatNetworkServiceProtocol {
    var result: Result<ThreatCheckResponse, ThreatServiceError>
    var delay: Duration = .milliseconds(300)

    var shelters: [Shelter] = []
    var zones: ThreatZoneCollection = .empty

    func checkThreat(latitude: Double, longitude: Double) async throws -> ThreatCheckResponse {
        try await Task.sleep(for: delay)
        return try result.get()
    }

    func nearestShelters(latitude: Double, longitude: Double, limit: Int) async throws -> [Shelter] {
        try await Task.sleep(for: delay)
        return Array(shelters.prefix(limit))
    }

    func reportShelter(id: String, reason: ShelterReportReason, note: String?) async throws -> Int {
        try await Task.sleep(for: delay)
        return 1
    }

    func threatZones(ifNoneMatch etag: String?) async throws -> ThreatZonesResult {
        try await Task.sleep(for: delay)
        // Second and later polls revalidate, exactly as the real one does.
        return etag == nil ? .updated(zones, etag: "W/\"zones-stub\"") : .unchanged
    }
}
