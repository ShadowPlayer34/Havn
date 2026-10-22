import SwiftUI

/// The one action on the map opens this: how far the risk is, and what to do about it.
/// Presented as a system sheet, so the grabber, the swipe-to-dismiss and the background
/// are the platform's — only the content is the design's.
///
/// Every number here comes from the same view model the map reads, so the sheet cannot
/// disagree with the screen it was opened from.
struct SafetyProtocolSheet: View {
    @Environment(ThreatViewModel.self) private var threats
    @Environment(\.dismiss) private var dismiss

    /// TEMPORARY — the zone standing over the user, passed in by the map so the sheet can
    /// show how much the backend trusts the report behind the status. Drop this property,
    /// the third card and the argument at the call site to go back to two cards.
    var zone: ThreatZone?

    /// Height of the content, so the sheet opens at exactly its own size.
    static let detentHeight: CGFloat = 450

    var body: some View {
        VStack(spacing: 16) {
            header
            statCards
            protocolList
            Spacer(minLength: 0)
            routeButton
        }
        .padding(.horizontal, 20)
        // Clear of the system grabber.
        .padding(.top, 28)
        .padding(.bottom, 20)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Distance & Safety Protocol")
                .font(VAFont.display(22))
                .tracking(em: -0.02, size: 22)
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Button("Done") { dismiss() }
                .font(VAFont.display(15))
                .foregroundStyle(Color(hex: 0x5CC2F0))
                .buttonStyle(.plain)
        }
    }

    private var statCards: some View {
        HStack(spacing: 8) {
            statCard(
                title: "AREA STATUS",
                value: areaStatus,
                valueColor: hasAnswer ? threats.riskLevel.badgeForeground : VA.secondary(0.75),
                fill: hasAnswer ? threats.riskLevel.badgeBackground : .white.opacity(0.08),
                stroke: hasAnswer ? threats.riskLevel.badgeStroke : .white.opacity(0.16)
            )
            statCard(
                title: "NEAREST SHELTER",
                value: threats.shelters.first?.distanceLabel ?? "—",
                valueColor: hasShelter ? VA.green : VA.secondary(0.75),
                fill: hasShelter ? VA.green.opacity(0.16) : .white.opacity(0.08),
                stroke: hasShelter ? VA.green.opacity(0.35) : .white.opacity(0.16)
            )
            // TEMPORARY — see `zone`.
            statCard(
                title: "CONFIDENCE",
                value: confidenceValue,
                valueColor: confidenceColour,
                fill: .white.opacity(0.08),
                stroke: .white.opacity(0.16)
            )
        }
        .animation(.easeOut(duration: 0.25), value: threats.riskLevel)
    }

    /// TEMPORARY. `confidence_score` as the extraction scored it — the same number the
    /// backend ranks overlapping threats by. Nil when nothing is over this coordinate.
    private var confidenceValue: String {
        guard let zone else { return "—" }
        return "\(Int((zone.confidence * 100).rounded()))%"
    }

    /// TEMPORARY. Amber below the backend's `high_confidence` threshold: under it a direct
    /// hit on the reported district is still only reported as elevated, not high.
    private var confidenceColour: Color {
        guard let zone else { return VA.secondary(0.75) }
        return zone.confidence >= 0.65 ? .white : VA.orange
    }

    /// A check that has not landed is not an all-clear. Until one does the card stays
    /// neutral and says nothing.
    private var hasAnswer: Bool { threats.response != nil }
    private var hasShelter: Bool { threats.shelters.first != nil }

    /// The server's own classification, in the design's title case rather than the
    /// badge's shouting caps.
    private var areaStatus: String {
        hasAnswer ? threats.riskLevel.localizedTitle.capitalized : "—"
    }

    private func statCard(title: String, value: String, valueColor: Color, fill: Color, stroke: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedStringKey(title))
                .font(VAFont.display(9.5))
                .tracking(em: 0.1, size: 9.5)
                .foregroundStyle(.white.opacity(0.55))
                // One line, so the three numbers below sit on the same baseline.
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(VAFont.rounded(30))
                .tracking(em: -0.02, size: 30)
                .foregroundStyle(valueColor)
                // "Підвищений" is twice the width the design drew "88%" in.
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(stroke, lineWidth: 0.5))
    }

    private var protocolList: some View {
        VStack(spacing: 0) {
            if let nearest = threats.shelters.first {
                protocolRow(
                    color: VA.green,
                    text: "\(nearest.shortLabel) — \(nearest.distanceLabel)",
                    detail: String(localized: "\(nearest.walkMinutes) min walk")
                )
            } else {
                protocolRow(color: VA.secondary(0.6), text: "No shelter data for this area", detail: nil)
            }
            divider
            protocolRow(color: VA.orange, text: "Two walls between you and windows", detail: nil)
            divider
            protocolRow(color: VA.cyan, text: "Notify 2 contacts on arrival", detail: nil)
        }
        .background(RoundedRectangle(cornerRadius: 24).fill(.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.12)).frame(height: 0.5)
    }

    private func protocolRow(color: Color, text: String, detail: String?) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(LocalizedStringKey(text))
                .font(VAFont.body)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let detail {
                Text(LocalizedStringKey(detail))
                    .font(VAFont.display(13, .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var routeButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Open Walking Route")
                .font(VAFont.display(17))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
        }
        .buttonStyle(.glassProminent)
        .tint(VA.cyan)
        .foregroundStyle(VA.cyanInk)
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }
}
