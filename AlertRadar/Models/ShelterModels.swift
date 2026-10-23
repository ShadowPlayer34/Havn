//
//  ShelterModels.swift
//  AlertRadar
//
//  Wire contract for GET /api/v1/shelters/nearest.
//

import CoreLocation
import SwiftUI

/// One shelter from the register, with the detail that decides whether it is any
/// use to you right now: is it open, can you get in, can you get in with a wheelchair.
nonisolated struct Shelter: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let shelterType: String?
    /// "kmda" — the official Kyiv register — or "osm".
    let source: String
    let address: String?
    let district: String?
    /// The register's own wording: "Підвал з пандусом ОЗ", "Станція метрополітену".
    let kind: String?
    let buildingType: String?
    /// "Цілодобово", or the restriction that applies.
    let workingTime: String?
    let phone: String?
    let accessible: Bool?
    /// The oblast register's Wi-Fi column. Nil wherever a register does not say, which
    /// is every city entry.
    let wifi: Bool?
    let notes: String?
    /// How many people have flagged a problem with this entry.
    let reports: Int
    let latitude: Double
    let longitude: Double
    let distanceMeters: Double

    enum CodingKeys: String, CodingKey {
        case id, name, source, address, district, kind, phone, accessible, wifi, notes, reports
        case shelterType = "shelter_type"
        case buildingType = "building_type"
        case workingTime = "working_time"
        case latitude, longitude
        case distanceMeters = "distance_meters"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// "240 m" / "1.4 km" — the number people actually reason about.
    var distanceLabel: String {
        distanceMeters < 1_000
            ? String(localized: "\(Int(distanceMeters.rounded())) m")
            : String(format: String(localized: "%.1f km"), distanceMeters / 1_000)
    }

    /// Rounded up: nobody is reassured by "0 min walk". 80 m/min is a brisk pace.
    var walkMinutes: Int { max(1, Int((distanceMeters / 80).rounded(.up))) }

    /// One anonymous tap should not discredit a shelter for everyone — a person could
    /// flag a perfectly good doorway by mistake, or on purpose. Two independent
    /// reporters is the bar for warning other people; a single one is still recorded
    /// and still visible to whoever filed it.
    var hasCorroboratedProblem: Bool { reports >= 2 }

    /// The register's hours, read as far as they can be read safely.
    var hours: ShelterHours { ShelterHours(registerText: workingTime) }

    /// True when the register says round-the-clock. Anything else carries a caveat
    /// worth showing rather than hiding behind a green pin.
    var isAlwaysOpen: Bool { hours == .alwaysOpen }

    /// What the place is called — "Сквирський ЗЗСО І-ІІІ ст. №3" — for recognising the
    /// building once you are standing in front of it. The city register's `name` is
    /// "<title>, <address>", so the address is trimmed off. Nil when nothing is left
    /// that the header or the rows below it do not already say.
    var placeName: String? {
        guard let address, !address.isEmpty else { return nil }
        var label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if label.hasSuffix(", \(address)") {
            label = String(label.dropLast(address.count + 2))
        }
        let alreadyShown = ["Укриття", address, kind ?? "", buildingType ?? ""]
        guard !label.isEmpty,
              !alreadyShown.contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame })
        else { return nil }
        return label
    }

    /// The city register's kind of building: a school, a block of flats. The oblast
    /// loader fills the same column with the settlement type ("Село"), which the address
    /// already says, so only the city's is worth a row.
    var buildingDescription: String? {
        guard isCityRegister, let buildingType, !buildingType.isEmpty,
              buildingType.caseInsensitiveCompare(kind ?? "") != .orderedSame
        else { return nil }
        return buildingType
    }

    /// A backend from before the `wifi` field passed only a "yes", as this exact note.
    private static let wifiNote = "Wi-Fi available"

    /// Yes, no, or nil when the register does not say.
    var hasWiFi: Bool? {
        wifi ?? (notes == Self.wifiNote ? true : nil)
    }

    /// `notes`, minus the old Wi-Fi flag that now has a row of its own.
    var registerNote: String? { notes == Self.wifiNote ? nil : notes }

    nonisolated struct PhoneNumber: Hashable, Sendable {
        /// As the register prints it.
        let display: String
        let url: URL
    }

    /// The register's `tel` can hold more than one number, in any punctuation. Each one
    /// that reads as a Ukrainian number becomes something to tap; the rest stays text.
    var phoneNumbers: [PhoneNumber] {
        guard let phone, let regex = try? NSRegularExpression(pattern: #"[+(]?\d[\d\s()\-]{4,}\d"#) else { return [] }
        return regex.matches(in: phone, range: NSRange(phone.startIndex..., in: phone)).compactMap { match in
            guard let range = Range(match.range, in: phone) else { return nil }
            let display = String(phone[range])
            let digits = display.filter(\.isNumber)
            let dialled: String
            if digits.count == 12, digits.hasPrefix("380") {
                dialled = "+" + digits
            } else if digits.count == 10, digits.hasPrefix("0") {
                dialled = "+38" + digits
            } else if digits.count == 7, isCityRegister {
                // A Kyiv landline printed without its area code.
                dialled = "+38044" + digits
            } else {
                return nil
            }
            return URL(string: "tel:\(dialled)").map { PhoneNumber(display: display, url: $0) }
        }
    }

    /// Which way to set off from `origin`, to the nearest of eight compass points. Nil
    /// when the shelter is close enough that GPS error would pick the answer.
    func direction(from origin: CLLocationCoordinate2D) -> CompassPoint? {
        guard distanceMeters >= 40 else { return nil }
        let fromLatitude = origin.latitude * .pi / 180
        let toLatitude = latitude * .pi / 180
        let deltaLongitude = (longitude - origin.longitude) * .pi / 180
        let y = sin(deltaLongitude) * cos(toLatitude)
        let x = cos(fromLatitude) * sin(toLatitude) - sin(fromLatitude) * cos(toLatitude) * cos(deltaLongitude)
        let degrees = (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        return CompassPoint.allCases[Int((degrees / 45).rounded()) % 8]
    }

    /// Both registers are official, but they are not equally precise. Kyiv city
    /// coordinates come from KMDA's own GIS layer and sample at a ~20 m median error
    /// against independent geocoding. The oblast set is hand-placed pins on a shared
    /// map, and a few percent sit kilometres from the address printed on them — so the
    /// app names the register rather than implying one standard of accuracy for both.
    var isCityRegister: Bool { source == "kmda" }

    var provenanceLabel: String {
        switch source {
        case "kmda": String(localized: "Kyiv city register")
        case "koda": String(localized: "Kyiv oblast register · position approximate")
        default: String(localized: "Unverified source")
        }
    }

    /// Short label for the map pin.
    var shortLabel: String {
        if let address, !address.isEmpty { return address }
        return name
    }

    /// Same shelter, new report count — the struct is immutable by design.
    func withReports(_ count: Int) -> Shelter {
        Shelter(
            id: id, name: name, shelterType: shelterType, source: source, address: address,
            district: district, kind: kind, buildingType: buildingType, workingTime: workingTime,
            phone: phone, accessible: accessible, wifi: wifi, notes: notes, reports: count,
            latitude: latitude, longitude: longitude, distanceMeters: distanceMeters
        )
    }

    var typeTitle: String {
        switch shelterType {
        case "bomb_shelter": String(localized: "Bomb shelter")
        case "dual_purpose": String(localized: "Dual-purpose structure")
        case "simple_shelter": String(localized: "Simple shelter")
        case "radiation_shelter": String(localized: "Radiation shelter")
        case "civil_defence", "civil_shelter": String(localized: "Civil defence shelter")
        case "emergency_shelter": String(localized: "Emergency shelter")
        case "air_raid": String(localized: "Air raid shelter")
        case "bunker": String(localized: "Bunker")
        default: String(localized: "Shelter")
        }
    }
}

nonisolated enum CompassPoint: CaseIterable, Sendable {
    case north, northEast, east, southEast, south, southWest, west, northWest

    var title: String {
        switch self {
        case .north: String(localized: "North")
        case .northEast: String(localized: "North-east")
        case .east: String(localized: "East")
        case .southEast: String(localized: "South-east")
        case .south: String(localized: "South")
        case .southWest: String(localized: "South-west")
        case .west: String(localized: "West")
        case .northWest: String(localized: "North-west")
        }
    }
}

nonisolated struct NearestSheltersResponse: Codable, Equatable, Sendable {
    let shelters: [Shelter]
}

extension WidgetSnapshot.NearestShelter {
    /// The few facts that fit on a small widget. Address-first, like the map pin: on a
    /// home screen you are looking for where to walk, not what the building is called.
    init(_ shelter: Shelter) {
        self.init(
            name: shelter.shortLabel,
            metres: Int(shelter.distanceMeters.rounded()),
            walkMinutes: shelter.walkMinutes,
            isAlwaysOpen: shelter.isAlwaysOpen,
            hours: shelter.isAlwaysOpen ? nil : shelter.workingTime
        )
    }
}

/// What a person can tell us about an entry that is wrong on the ground.
nonisolated enum ShelterReportReason: String, CaseIterable, Codable, Sendable, Identifiable {
    case wrongLocation = "wrong_location"
    case doesNotExist = "does_not_exist"
    case locked
    case wrongHours = "wrong_hours"
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wrongLocation: String(localized: "It's not at this spot")
        case .doesNotExist: String(localized: "There's no shelter here")
        case .locked: String(localized: "Locked — I couldn't get in")
        case .wrongHours: String(localized: "The hours are wrong")
        case .other: String(localized: "Something else")
        }
    }

    var systemImage: String {
        switch self {
        case .wrongLocation: "mappin.slash"
        case .doesNotExist: "questionmark.circle"
        case .locked: "lock.fill"
        case .wrongHours: "clock.badge.exclamationmark"
        case .other: "exclamationmark.bubble"
        }
    }
}

nonisolated struct ShelterReportRequest: Encodable, Sendable {
    let reason: ShelterReportReason
    let note: String?
    /// Random, stored on device. Stops one phone counting five times; identifies nobody.
    let clientId: String

    enum CodingKeys: String, CodingKey {
        case reason, note
        case clientId = "client_id"
    }
}

nonisolated struct ShelterReportAck: Decodable, Sendable {
    let shelterId: String
    let reports: Int

    enum CodingKeys: String, CodingKey {
        case shelterId = "shelter_id"
        case reports
    }
}

/// The device's reporting identity: a random UUID, created once, never sent anywhere
/// but the report body. Deliberately not the IDFV — this must not follow the user.
nonisolated enum ReportingClient {
    private static let key = "shelter.report.client-id"
    private static let reportedKey = "shelter.report.submitted-ids"

    static var id: String {
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }

    /// The server already refuses a second report on the same entry from the same
    /// device; remembering it here is so the button says so instead of failing.
    static func hasReported(_ shelterID: String) -> Bool {
        submitted().contains(shelterID)
    }

    static func markReported(_ shelterID: String) {
        var ids = submitted()
        ids.insert(shelterID)
        UserDefaults.standard.set(Array(ids), forKey: reportedKey)
    }

    private static func submitted() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: reportedKey) ?? [])
    }
}
