import SwiftUI

/// Option 3a — "Where I live": the district the widget and its notifications watch,
/// with the widget itself drawn above the picker so the choice shows what it does.
struct HomeDistrictSheet: View {
    @Environment(DistrictAlertMonitor.self) private var districtAlerts
    @Environment(ThreatZonesViewModel.self) private var zones
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header

                section("HOME SCREEN · LOCK SCREEN") {
                    // Ticks with the minute, as the real widget's entries do.
                    TimelineView(.everyMinute) { context in
                        let reading = DistrictAlertReading(
                            district: districtAlerts.district, state: districtAlerts.state, now: context.date
                        )
                        HStack(alignment: .top, spacing: 14) {
                            DistrictAlertTile(reading: reading)
                                .padding(14)
                                .frame(width: 158, height: 158)
                                .background { DistrictAlertTileBackground(reading: reading) }
                                .containerShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                            DistrictAlertRectangular(reading: reading)
                                .foregroundStyle(.white)
                                .padding(.vertical, 7)
                                .padding(.horizontal, 10)
                                .frame(width: 172)
                                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }

                picker

                if districtAlerts.notificationsAllowed == false {
                    Text("Notifications are off for Havn. Turn them on in Settings to hear about alerts in your district.")
                        .font(VAFont.display(12, .regular))
                        .foregroundStyle(VA.orangeText)
                        .lineHeight(1.45, size: 12)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
        }
        .background(Color(hex: 0x0B0B0C).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .task { await districtAlerts.refreshAuthorization() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("My District")
                .font(VAFont.title)
                .tracking(em: -0.02, size: 24)
                .foregroundStyle(.white)
            Spacer()
            Button("Done") { dismiss() }
                .font(VAFont.display(15))
                .foregroundStyle(VA.cyan)
                .buttonStyle(.plain)
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Where I live")
                    .font(VAFont.display(15))
                    .foregroundStyle(.white)
                Spacer()
                Text("Kyiv")
                    .font(VAFont.display(12, .medium))
                    .foregroundStyle(VA.secondary(0.45))
            }

            ChipFlow(spacing: 6) {
                ForEach(KyivDistrict.allCases) { district in
                    chip(district)
                }
            }

            Text("Alerts for this district reach the widget and notifications even when location access is off.")
                .font(VAFont.display(11.5, .regular))
                .foregroundStyle(VA.secondary(0.45))
                .lineHeight(1.45, size: 11.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(VA.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: 1)
        }
    }

    private func chip(_ district: KyivDistrict) -> some View {
        let selected = district == districtAlerts.district
        return Button {
            Task { await districtAlerts.choose(district, zones: zones) }
        } label: {
            Text(district.shortName)
                .font(VAFont.display(12))
                .foregroundStyle(selected ? .white : VA.secondary(0.5))
                .padding(.vertical, 8)
                .padding(.horizontal, 11)
                .background(
                    selected ? VA.red.opacity(0.18) : .white.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(selected ? VA.red.opacity(0.45) : .white.opacity(0.09), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(VAFont.mono(10, .semibold))
                .tracking(em: 0.12, size: 10)
                .foregroundStyle(VA.secondary(0.4))
            content()
        }
    }
}

/// Chips left to right, wrapping onto a new row when the next one would not fit.
private struct ChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
