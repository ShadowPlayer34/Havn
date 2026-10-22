import SwiftUI

// The district widget from option 3a, drawn once so the home screen tile, the lock screen
// line and the app's preview of both cannot disagree.

/// What the district widget says at a given minute.
nonisolated struct DistrictAlertReading: Sendable {
    enum Status { case unchosen, unknown, alert, nearby, clear }

    let district: KyivDistrict?
    let state: DistrictAlertState?
    let now: Date

    /// Past this, the widget stops vouching for its answer and says when it was last true.
    /// Twice the widget's own refresh interval, so one failed fetch is not enough to trip it.
    static let staleAfter: TimeInterval = 30 * 60

    var status: Status {
        guard district != nil else { return .unchosen }
        guard let state else { return .unknown }
        return switch state.level {
        case .alert: .alert
        case .nearby: .nearby
        case .clear: .clear
        }
    }

    var isStale: Bool {
        guard let state else { return false }
        return now.timeIntervalSince(state.checkedAt) > Self.staleAfter
    }

    /// "Alert in Kyiv" / "All clear" — the lock screen headline.
    var title: String {
        switch status {
        case .unchosen: String(localized: "Pick your district")
        case .unknown: String(localized: "No data yet")
        case .alert: String(localized: "Alert in Kyiv")
        case .nearby: String(localized: "Threat nearby")
        case .clear: String(localized: "All clear")
        }
    }

    /// The one word the home screen tile sets large.
    var shortTitle: String {
        switch status {
        case .unchosen: String(localized: "Pick your district")
        case .unknown: "—"
        case .alert: String(localized: "Alert")
        case .nearby: String(localized: "Threat")
        case .clear: String(localized: "Clear")
        }
    }

    /// "for 23 min" / "at 09:18", or "as of 09:18" once the answer is too old to stand on.
    var since: String? {
        guard let state else { return nil }
        if isStale {
            return String(localized: "as of \(time(state.checkedAt))")
        }
        if state.isActive, let started = state.startedAt {
            return String(localized: "for \(minutes(since: started)) min")
        }
        return state.endedAt.map { String(localized: "at \(time($0))") }
    }

    /// The tile's corner: "23 min" / "09:18".
    var sinceShort: String? {
        guard let state else { return nil }
        if isStale { return since }
        if state.isActive, let started = state.startedAt {
            return String(localized: "\(minutes(since: started)) min")
        }
        return state.endedAt.map(time)
    }

    var dot: Color {
        switch status {
        case .alert: VA.red
        case .nearby: VA.orange
        case .clear: VA.green
        case .unchosen, .unknown: VA.secondary(0.45)
        }
    }

    /// Amber, not the status colour, once the answer is stale — as the shelter widget
    /// does. On `nearby` the two coincide, and the words underneath carry the difference.
    var accent: Color {
        if isStale { return VA.orange }
        return switch status {
        case .alert: VA.redText
        case .nearby: VA.orangeText
        case .clear: Color(hex: 0x7EE29A)
        case .unchosen, .unknown: VA.secondary(0.5)
        }
    }

    var tint: Color {
        switch status {
        case .alert: VA.red.opacity(0.22)
        case .nearby: VA.orange.opacity(0.2)
        case .clear: VA.green.opacity(0.18)
        case .unchosen, .unknown: Color.white.opacity(0.08)
        }
    }

    var edge: Color {
        switch status {
        case .alert: VA.red.opacity(0.5)
        case .nearby: VA.orange.opacity(0.45)
        case .clear: VA.green.opacity(0.45)
        case .unchosen, .unknown: Color.white.opacity(0.18)
        }
    }

    var districtName: String {
        district?.name ?? String(localized: "Open Havn and choose where you live.")
    }

    /// Floored and never zero: "for 0 min" reads as no alert at all.
    private func minutes(since start: Date) -> Int {
        max(1, Int(now.timeIntervalSince(start) / 60))
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

/// The home screen tile.
struct DistrictAlertTile: View {
    let reading: DistrictAlertReading

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(reading.dot)
                    .frame(width: 9, height: 9)
                    .shadow(color: reading.dot, radius: 5)
                Text("Kyiv")
                    .font(VAFont.display(11))
                    .foregroundStyle(.white.opacity(0.75))
            }

            Text(reading.shortTitle)
                .font(VAFont.rounded(26))
                .tracking(em: -0.02, size: 26)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.6)

            Text(reading.districtName)
                .font(VAFont.display(12, .medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(reading.district == nil ? 3 : 2)

            Spacer(minLength: 0)

            if let sinceShort = reading.sinceShort {
                Text(sinceShort)
                    .font(VAFont.mono(12, .semibold))
                    .foregroundStyle(reading.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Behind the tile: the status as a wash over the card colour, edged in the same hue.
struct DistrictAlertTileBackground: View {
    let reading: DistrictAlertReading

    var body: some View {
        ZStack {
            VA.card
            reading.tint
            ContainerRelativeShape()
                .strokeBorder(reading.edge, lineWidth: 1)
        }
    }
}

/// The lock screen accessory: the same reading in the three lines a rectangular slot has.
struct DistrictAlertRectangular: View {
    let reading: DistrictAlertReading

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(reading.dot)
                    .frame(width: 8, height: 8)
                Text(reading.title)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
            }
            Text(reading.districtName)
                .font(.system(size: 12, weight: .medium))
                .opacity(0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let since = reading.since {
                Text(since)
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.55)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
