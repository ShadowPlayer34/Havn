//
//  ThreatModels.swift
//  AlertRadar
//
//  Wire contract for GET /api/v1/threats/check.
//

import CoreLocation
import SwiftUI

// MARK: - Risk level

/// Server-driven risk classification. Decoding is deliberately strict: an unrecognised level
/// surfaces as an error rather than silently degrading to `.none`, because the one failure
/// mode this app cannot have is telling someone they are clear when they are not.
nonisolated enum RiskLevel: String, Codable, Sendable, CaseIterable {
    case none
    case elevated
    case high

    /// The one accent that carries the meaning.
    var accent: Color {
        switch self {
        case .none: VA.green
        case .elevated: VA.orange
        case .high: VA.red
        }
    }

    /// Text colour on top of `badgeBackground` — lighter than the accent so it stays legible.
    var badgeForeground: Color {
        switch self {
        case .none: VA.greenText
        case .elevated: VA.orangeText
        case .high: VA.redText
        }
    }

    var badgeBackground: Color { accent.opacity(self == .none ? 0.14 : 0.22) }
    var badgeStroke: Color { accent.opacity(self == .none ? 0.32 : 0.45) }

    /// Fill for the map overlay — an area, never a point.
    var overlayFill: Color {
        switch self {
        case .none: accent.opacity(0.10)
        case .elevated: accent.opacity(0.16)
        case .high: accent.opacity(0.22)
        }
    }

    /// Radius of the map overlay in metres.
    var overlayRadius: CLLocationDistance {
        switch self {
        case .none: 400
        case .elevated: 900
        case .high: 1400
        }
    }

    var systemImage: String {
        switch self {
        case .none: "checkmark.shield.fill"
        case .elevated: "exclamationmark.triangle.fill"
        case .high: "exclamationmark.octagon.fill"
        }
    }

    /// Anything other than `.none` warrants showing the protocol.
    var isActionable: Bool { self != .none }

    // MARK: Titles

    var titleEnglish: String {
        switch self {
        case .none: "CLEAR"
        case .elevated: "ELEVATED"
        case .high: "HIGH"
        }
    }

    var titleUkrainian: String {
        switch self {
        case .none: "ЧИСТО"
        case .elevated: "ПІДВИЩЕНИЙ"
        case .high: "ВИСОКИЙ"
        }
    }

    var titleRussian: String {
        switch self {
        case .none: "ЧИСТО"
        case .elevated: "ПОВЫШЕННЫЙ"
        case .high: "ВЫСОКИЙ"
        }
    }

    /// Picks a title from the device language, falling back to English.
    var localizedTitle: String {
        switch Locale.current.language.languageCode?.identifier {
        case "uk": titleUkrainian
        case "ru": titleRussian
        default: titleEnglish
        }
    }

    /// Two or three words for the map's location capsule.
    var localizedShortStatus: String {
        switch (Locale.current.language.languageCode?.identifier, self) {
        case ("uk", .none): "Сектор чистий"
        case ("uk", .elevated): "Підвищена увага"
        case ("uk", .high): "У зоні ризику"
        case ("ru", .none): "Сектор чист"
        case ("ru", .elevated): "Повышенное внимание"
        case ("ru", .high): "В зоне риска"
        case (_, .none): "Sector clear"
        case (_, .elevated): "Elevated attention"
        case (_, .high): "In risk area"
        }
    }

    /// Longer form for the status card subtitle.
    var localizedSummary: String {
        switch (Locale.current.language.languageCode?.identifier, self) {
        case ("uk", .none): "Загроз у вашому секторі немає"
        case ("uk", .elevated): "Ризик у вашому секторі підвищений"
        case ("uk", .high): "Ви в зоні ризику — прямуйте в укриття"
        case ("ru", .none): "Угроз в вашем секторе нет"
        case ("ru", .elevated): "Риск в вашем секторе повышен"
        case ("ru", .high): "Вы в зоне риска — идите в укрытие"
        case (_, .none): "No active threat in your sector"
        case (_, .elevated): "Risk in your sector is elevated"
        case (_, .high): "You are inside the risk area — take cover"
        }
    }
}

// MARK: - Response

/// The exact shape returned by `GET /api/v1/threats/check`.
nonisolated struct ThreatCheckResponse: Codable, Equatable, Sendable {
    let inRiskZone: Bool
    let riskLevel: RiskLevel
    let threatType: String?
    let etaWindow: String?
    let etaMinutes: Int?
    let sectorName: String?
    let originSector: String?
    let sourceRefs: [Int]

    enum CodingKeys: String, CodingKey {
        case inRiskZone = "in_risk_zone"
        case riskLevel = "risk_level"
        case threatType = "threat_type"
        case etaWindow = "eta_window"
        case etaMinutes = "eta_minutes"
        case sectorName = "sector_name"
        case originSector = "origin_sector"
        case sourceRefs = "source_refs"
    }

    /// `source_refs` is optional in practice; an absent array is not an error.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inRiskZone = try container.decode(Bool.self, forKey: .inRiskZone)
        riskLevel = try container.decode(RiskLevel.self, forKey: .riskLevel)
        threatType = try container.decodeIfPresent(String.self, forKey: .threatType)
        etaWindow = try container.decodeIfPresent(String.self, forKey: .etaWindow)
        etaMinutes = try container.decodeIfPresent(Int.self, forKey: .etaMinutes)
        sectorName = try container.decodeIfPresent(String.self, forKey: .sectorName)
        originSector = try container.decodeIfPresent(String.self, forKey: .originSector)
        sourceRefs = try container.decodeIfPresent([Int].self, forKey: .sourceRefs) ?? []
    }

    init(
        inRiskZone: Bool,
        riskLevel: RiskLevel,
        threatType: String? = nil,
        etaWindow: String? = nil,
        etaMinutes: Int? = nil,
        sectorName: String? = nil,
        originSector: String? = nil,
        sourceRefs: [Int] = []
    ) {
        self.inRiskZone = inRiskZone
        self.riskLevel = riskLevel
        self.threatType = threatType
        self.etaWindow = etaWindow
        self.etaMinutes = etaMinutes
        self.sectorName = sectorName
        self.originSector = originSector
        self.sourceRefs = sourceRefs
    }

    /// True when there is something concrete to show beyond the badge.
    var hasThreatDetail: Bool {
        threatType != nil || etaWindow != nil || sectorName != nil
    }

    static let clear = ThreatCheckResponse(inRiskZone: false, riskLevel: .none)
}
