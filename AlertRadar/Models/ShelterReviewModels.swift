//
//  ShelterReviewModels.swift
//  AlertRadar
//
//  Wire contract for GET /api/v1/shelters/{id}/reviews and PUT/DELETE …/{id}/review.
//

import Foundation

/// What reviewers make of a place: the mean of their 1–5 ratings, one per device.
nonisolated struct ShelterRating: Codable, Equatable, Sendable {
    let average: Double
    let count: Int

    /// "4.3" — one decimal is all a handful of reviews can support.
    var averageLabel: String { average.formatted(.number.precision(.fractionLength(1))) }
}

/// A line of the register that someone standing at the door can check for themselves.
nonisolated enum ShelterFact: String, CaseIterable, Codable, Sendable, Identifiable {
    case location, hours, accessible, wifi

    var id: String { rawValue }

    /// Same wording as the row it checks on the shelter sheet.
    var label: String {
        switch self {
        case .location: "ENTRANCE"
        case .hours: "HOURS"
        case .accessible: "STEP-FREE"
        case .wifi: "WI-FI"
        }
    }

    /// For a verdict chip on someone's review: "✓ Hours".
    var title: String {
        switch self {
        case .location: String(localized: "Entrance")
        case .hours: String(localized: "Hours")
        case .accessible: String(localized: "Step-free")
        case .wifi: String(localized: "Wi-Fi")
        }
    }
}

/// One person's verdict on each register fact: true when it matched what they found,
/// false when it did not, nil when they did not check.
nonisolated struct ReviewChecks: Codable, Equatable, Sendable {
    var location: Bool?
    var hours: Bool?
    var accessible: Bool?
    var wifi: Bool?

    subscript(fact: ShelterFact) -> Bool? {
        get {
            switch fact {
            case .location: location
            case .hours: hours
            case .accessible: accessible
            case .wifi: wifi
            }
        }
        set {
            switch fact {
            case .location: location = newValue
            case .hours: hours = newValue
            case .accessible: accessible = newValue
            case .wifi: wifi = newValue
            }
        }
    }
}

nonisolated struct ShelterReview: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let rating: Int
    let checks: ReviewChecks
    let text: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, rating, checks, text
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// How one register fact held up across every review of the place.
nonisolated struct FactTally: Codable, Equatable, Sendable {
    var confirmed = 0
    var disputed = 0

    var isEmpty: Bool { confirmed == 0 && disputed == 0 }

    /// The same bar as reports: two independent people, and more of them than say
    /// otherwise, before the app calls the register wrong in front of everyone.
    var isDisputed: Bool { disputed >= 2 && disputed > confirmed }
}

nonisolated struct FactTallies: Codable, Equatable, Sendable {
    var location = FactTally()
    var hours = FactTally()
    var accessible = FactTally()
    var wifi = FactTally()

    subscript(fact: ShelterFact) -> FactTally {
        switch fact {
        case .location: location
        case .hours: hours
        case .accessible: accessible
        case .wifi: wifi
        }
    }
}

nonisolated struct ShelterReviewsResponse: Codable, Equatable, Sendable {
    let shelterId: String
    let rating: ShelterRating?
    let facts: FactTallies
    /// Newest first, without this device's own.
    let reviews: [ShelterReview]
    /// This device's review, so it can be edited rather than written twice.
    let mine: ShelterReview?

    enum CodingKeys: String, CodingKey {
        case shelterId = "shelter_id"
        case rating, facts, reviews, mine
    }
}

nonisolated struct ShelterReviewRequest: Encodable, Sendable {
    let rating: Int
    let checks: ReviewChecks
    let text: String?
}

extension Shelter {
    /// The register lines a review can check here: only what the register states. A
    /// verdict on Wi-Fi for an entry that says nothing about Wi-Fi has nothing to be
    /// right or wrong about, and the server drops it anyway.
    var checkableFacts: [ShelterFact] {
        ShelterFact.allCases.filter { fact in
            switch fact {
            case .location: true
            case .hours: !(workingTime ?? "").isEmpty
            case .accessible: accessible != nil
            case .wifi: wifi != nil
            }
        }
    }

    /// What the register claims, in the words the sheet shows it in.
    func registerClaim(_ fact: ShelterFact) -> String {
        switch fact {
        case .location: String(localized: "The entrance is where the pin is")
        case .hours: workingTime ?? ""
        case .accessible: accessible == true ? String(localized: "Yes") : String(localized: "No")
        case .wifi: wifi == true ? String(localized: "Yes") : String(localized: "No")
        }
    }
}
