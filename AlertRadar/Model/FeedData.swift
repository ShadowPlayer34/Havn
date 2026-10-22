import SwiftUI

// Sample data · Kyiv region, verbatim from the design document's script block.

enum FeedCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case confirmed = "Confirmed"
    case airDefence = "Air defence"
    case cleared = "Cleared"

    var id: String { rawValue }
}

enum ReliabilityTag: String {
    case confirmed = "CONFIRMED"
    case corroborated = "CORROBORATED"
    case unverified = "UNVERIFIED"
    case cleared = "CLEARED"

    var foreground: Color {
        switch self {
        case .confirmed: VA.green
        case .corroborated: VA.orange
        case .unverified: VA.secondary(0.65)
        case .cleared: VA.cyan
        }
    }

    var background: Color {
        switch self {
        case .confirmed: VA.green.opacity(0.14)
        case .corroborated: VA.orange.opacity(0.14)
        case .unverified: .white.opacity(0.08)
        case .cleared: VA.cyan.opacity(0.14)
        }
    }
}

struct FeedItem: Identifiable {
    let time: String
    let tag: ReliabilityTag
    let reliability: Int
    let source: String
    let coords: String
    let merged: String
    let summary: String
    let category: FeedCategory

    var id: String { time }

    /// ≥90 clear, ≥75 predicted, otherwise neutral.
    var reliabilityColor: Color {
        if reliability >= 90 { VA.green }
        else if reliability >= 75 { VA.orange }
        else { VA.secondary() }
    }
}

extension FeedItem {
    static let all: [FeedItem] = [
        FeedItem(
            time: "14:32:07", tag: .confirmed, reliability: 96,
            source: String(localized: "UA Air Force · official channel"),
            coords: "50.4021° N, 30.6520° E", merged: String(localized: "7 posts · 3 channels"),
            summary: String(localized: "Group of 4 Shahed-136 crossed the Kyiv region border from the south-east on a north-west heading."),
            category: .confirmed
        ),
        FeedItem(
            time: "14:28:51", tag: .corroborated, reliability: 82,
            source: String(localized: "Cross-checked · 3 independent observers"),
            coords: "49.9835° N, 30.9114° E", merged: String(localized: "12 posts · 5 channels"),
            summary: String(localized: "Ground observation reports engine noise moving north-west. Matches radar track VT-114."),
            category: .confirmed
        ),
        FeedItem(
            time: "14:21:03", tag: .unverified, reliability: 61,
            source: String(localized: "Regional administration repost"),
            coords: "50.2500° N, 30.8000° E", merged: String(localized: "4 posts · 2 channels"),
            summary: String(localized: "Air defence reported active over Boryspil district. No debris reports received so far."),
            category: .airDefence
        ),
        FeedItem(
            time: "14:09:40", tag: .cleared, reliability: 91,
            source: String(localized: "Sensor mesh · acoustic node 118"),
            coords: "50.4501° N, 30.5234° E", merged: String(localized: "2 posts · 1 channel"),
            summary: String(localized: "Acoustic baseline returned to normal for Solomianskyi district. Previous alert closed."),
            category: .cleared
        )
    ]
}
