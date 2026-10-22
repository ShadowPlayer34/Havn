//
//  ThreatDashboardView.swift
//  AlertRadar
//
//  One screen answering one question: am I in it, and how long have I got.
//

import CoreLocation
import MapKit
import SwiftUI

struct ThreatDashboardView: View {
    @Environment(ThreatViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @State private var location = LocationManager()
    @State private var camera: MapCameraPosition = .automatic

    /// Opens at two-thirds height: enough for the badge, the detail and the map, while
    /// leaving the map screen visible behind it. Drag up for the rest.
    static let detentFraction: CGFloat = 0.68

    var body: some View {
        VStack(spacing: 0) {
            // Pinned, not scrolled: `.refreshable` below consumes the downward swipe that
            // would otherwise dismiss the sheet, so there has to be an exit that is always
            // on screen.
            header

            ScrollView {
                VStack(spacing: 14) {
                    statusCard
                    if let response = viewModel.response, response.hasThreatDetail {
                        detailCard(response)
                    }
                    mapCard
                    if let message = viewModel.errorMessage {
                        errorRow(message)
                    }
                    if location.isDenied {
                        permissionRow
                    }
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.visible)
            .refreshable {
                await viewModel.refresh(coordinate: location.currentLocation)
            }
        }
        .background(VA.canvas.ignoresSafeArea())
        .task {
            location.requestAuthorization()
            await viewModel.observe(location)
        }
        .onChange(of: location.lastFix) {
            guard let coordinate = location.currentLocation else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                camera = .region(MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 2_600,
                    longitudinalMeters: 2_600
                ))
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Threat Check")
                .font(VAFont.title)
                .tracking(em: -0.02, size: 24)
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Button("Done") { dismiss() }
                .font(VAFont.display(15))
                .foregroundStyle(VA.cyan)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: Status

    /// What the badge says. Never green unless a check actually came back clear — the
    /// absence of an answer must not read as safety.
    private struct Status {
        var title: String
        var summary: String
        var accent: Color
        var foreground: Color
        var systemImage: String
        var isActionable: Bool

        init(risk: RiskLevel) {
            title = risk.localizedTitle
            summary = risk.localizedSummary
            accent = risk.accent
            foreground = risk.badgeForeground
            systemImage = risk.systemImage
            isActionable = risk.isActionable
        }

        init(unknownSummary: String) {
            title = switch Locale.current.language.languageCode?.identifier {
            case "uk": "НЕМАЄ ДАНИХ"
            case "ru": "НЕТ ДАННЫХ"
            default: "NO DATA"
            }
            summary = unknownSummary
            accent = VA.secondary(0.5)
            foreground = VA.secondary(0.75)
            systemImage = "questionmark.circle.fill"
            isActionable = false
        }

        var background: Color { accent.opacity(0.16) }
        var stroke: Color { accent.opacity(0.4) }
    }

    private var status: Status {
        if let response = viewModel.response {
            return Status(risk: response.riskLevel)
        }
        if viewModel.errorMessage != nil {
            return Status(unknownSummary: String(localized: "No answer from the threat service yet"))
        }
        return Status(unknownSummary: String(localized: "Checking your sector…"))
    }

    private var statusCard: some View {
        let status = status

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label(status.title, systemImage: status.systemImage)
                    .font(VAFont.display(13))
                    .tracking(em: 0.04, size: 13)
                    .foregroundStyle(status.foreground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(status.background))
                    .overlay(Capsule().strokeBorder(status.stroke, lineWidth: 0.5))

                Spacer(minLength: 0)

                if viewModel.state.isLoading {
                    ProgressView().controlSize(.small).tint(VA.secondary(0.6))
                }
            }

            Text(status.summary)
                .font(VAFont.display(22))
                .tracking(em: -0.02, size: 22)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            if let response = viewModel.response {
                HStack(spacing: 8) {
                    if let threat = response.threatType {
                        tag(threat, color: status.accent)
                    }
                    if response.inRiskZone {
                        tag("IN RISK ZONE", color: VA.red)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26).fill(VA.card))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(status.accent.opacity(status.isActionable ? 0.35 : 0.12), lineWidth: 1)
        )
        .animation(.snappy(duration: 0.3), value: viewModel.riskLevel)
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(LocalizedStringKey(text))
            .font(VAFont.mono(9.5, .semibold))
            .tracking(em: 0.08, size: 9.5)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.14)))
    }

    // MARK: Detail

    private func detailCard(_ response: ThreatCheckResponse) -> some View {
        VStack(spacing: 0) {
            if let sector = response.sectorName {
                detailRow("SECTOR", value: sector, accent: .white)
            }
            if let window = response.etaWindow {
                divider
                detailRow(
                    "ARRIVAL WINDOW",
                    value: window,
                    accent: viewModel.riskLevel.accent,
                    rounded: true
                )
            } else if let minutes = response.etaMinutes {
                divider
                detailRow(
                    "ARRIVAL",
                    value: String(localized: "\(minutes) min"),
                    accent: viewModel.riskLevel.accent,
                    rounded: true
                )
            }
            if let origin = response.originSector {
                divider
                detailRow("ORIGIN", value: origin, accent: VA.secondary(0.85))
            }
            if !response.sourceRefs.isEmpty {
                divider
                detailRow(
                    "SOURCES",
                    value: response.sourceRefs.map(String.init).joined(separator: ", "),
                    accent: VA.cyan,
                    mono: true
                )
            }
        }
        .background(RoundedRectangle(cornerRadius: 22).fill(VA.card))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.07), lineWidth: 1))
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
    }

    private func detailRow(
        _ label: String,
        value: String,
        accent: Color,
        rounded: Bool = false,
        mono: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Text(LocalizedStringKey(label))
                .font(VAFont.mono(10, .semibold))
                .tracking(em: 0.08, size: 10)
                .foregroundStyle(VA.secondary(0.4))
                .frame(width: 118, alignment: .leading)
            Text(value)
                .font(rounded ? VAFont.rounded(20) : (mono ? VAFont.mono(13) : VAFont.display(15, .regular)))
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: Map

    private var mapCard: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom]) {
            // Only drawn once a check has actually answered — no overlay means no claim.
            if let coordinate = location.currentLocation, let risk = viewModel.response?.riskLevel {
                MapCircle(center: coordinate, radius: risk.overlayRadius)
                    .foregroundStyle(risk.overlayFill)
                    .stroke(risk.accent.opacity(0.35), lineWidth: 1)
                Annotation(coordinate: coordinate) {
                    RiskPulse(color: risk.accent, active: risk.isActionable)
                } label: {
                    EmptyView()
                }
            }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.07), lineWidth: 1))
        .allowsHitTesting(false)
    }

    // MARK: Rows

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .foregroundStyle(VA.orange)
            Text(message)
                .font(VAFont.display(12.5, .regular))
                .foregroundStyle(VA.secondary(0.75))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(VA.orange.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(VA.orange.opacity(0.25), lineWidth: 1))
    }

    private var permissionRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.slash.fill").foregroundStyle(VA.red)
            Text("Location access is off, so no sector can be checked. Enable it in Settings.")
                .font(VAFont.display(12.5, .regular))
                .foregroundStyle(VA.secondary(0.75))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(VA.red.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(VA.red.opacity(0.25), lineWidth: 1))
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            Text("Last updated")
                .foregroundStyle(VA.secondary(0.35))
            if let updated = viewModel.lastUpdated {
                Text(updated, style: .relative)
                    .foregroundStyle(VA.secondary(0.6))
                Text("ago")
                    .foregroundStyle(VA.secondary(0.35))
            } else {
                Text("—").foregroundStyle(VA.secondary(0.6))
            }
            Spacer(minLength: 0)
        }
        .font(VAFont.mono(10.5))
        .padding(.top, 2)
    }
}

/// A slow ring on the user's position — motion only when there is something to say.
struct RiskPulse: View {
    let color: Color
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        Circle()
            .strokeBorder(color.opacity(0.55), lineWidth: 2)
            .frame(width: 26, height: 26)
            .scaleEffect(expanded ? 2.4 : 0.8)
            .opacity(expanded ? 0 : 0.9)
            .animation(
                active && !reduceMotion
                    ? .easeOut(duration: 2.2).repeatForever(autoreverses: false)
                    : nil,
                value: expanded
            )
            .onAppear { expanded = active }
            .onChange(of: active) { expanded = active }
            .allowsHitTesting(false)
    }
}

#Preview("High risk") {
    ThreatDashboardView()
        .environment(ThreatViewModel(service: StubThreatNetworkService(result: .success(
            ThreatCheckResponse(
                inRiskZone: true,
                riskLevel: .high,
                threatType: "Shahed-136",
                etaWindow: "9–14 min",
                etaMinutes: 11,
                sectorName: "Solomianskyi",
                originSector: "Boryspil district",
                sourceRefs: [114, 118, 121]
            )
        ))))
}
