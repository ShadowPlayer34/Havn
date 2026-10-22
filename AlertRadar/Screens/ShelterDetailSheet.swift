//
//  ShelterDetailSheet.swift
//  AlertRadar
//
//  What you get when you tap a shelter pin. Everything here answers one question:
//  can I actually get into this place, right now.
//

import MapKit
import SwiftUI

struct ShelterDetailSheet: View {
    let shelter: Shelter
    @Environment(ThreatViewModel.self) private var threats
    @Environment(\.dismiss) private var dismiss
    @State private var showingReport = false
    @State private var reportState: ReportState = .idle
    @State private var alreadyReported = false

    private enum ReportState: Equatable {
        case idle, sending, sent(Int), failed(String)
    }

    /// Tall enough for the route button *and* the report link below it; the sheet
    /// can still be dragged to full height for the longer register notes.
    static let detentHeight: CGFloat = 545

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    statRow
                    if showsBanner {
                        reportBanner
                    }
                    details
                }
                .padding(.horizontal, 20)
                // Clear of the system grabber.
                .padding(.top, 36)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.visible)
            .scrollBounceBehavior(.basedOnSize)

            // Pinned: under an alert the route must never be something you have to
            // scroll to find.
            VStack(spacing: 2) {
                routeButton
                reportButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .background(.ultraThinMaterial)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(shelter.address ?? shelter.name)
                    .font(VAFont.display(22))
                    .tracking(em: -0.02, size: 22)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Done") { dismiss() }
                    .font(VAFont.display(15))
                    .foregroundStyle(Color(hex: 0x5CC2F0))
                    .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Text(shelter.typeTitle)
                    .font(VAFont.display(12))
                    .foregroundStyle(VA.greenText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(VA.green.opacity(0.16)))
                if !shelter.isCityRegister {
                    // Oblast pins are hand-placed; do not let the map imply metre accuracy.
                    Text("APPROX. POSITION")
                        .font(VAFont.mono(9.5, .semibold))
                        .tracking(em: 0.08, size: 9.5)
                        .foregroundStyle(VA.orangeText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(VA.orange.opacity(0.16)))
                }
            }
        }
    }

    private var statRow: some View {
        HStack(spacing: 8) {
            stat(shelter.distanceLabel, caption: String(localized: "\(shelter.walkMinutes) min walk"), tint: VA.green)
            stat(
                shelter.isAlwaysOpen ? "24/7" : "Limited",
                caption: shelter.isAlwaysOpen ? "always open" : "check hours",
                tint: shelter.isAlwaysOpen ? VA.green : VA.orange
            )
        }
    }

    private func stat(_ value: String, caption: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedStringKey(value))
                .font(VAFont.rounded(28))
                .tracking(em: -0.02, size: 28)
                .foregroundStyle(tint)
            Text(LocalizedStringKey(caption))
                .font(VAFont.display(11, .medium))
                .foregroundStyle(VA.secondary(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22).fill(tint.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(tint.opacity(0.3), lineWidth: 0.5))
    }

    private var details: some View {
        VStack(spacing: 0) {
            if let kind = shelter.kind {
                row("TYPE", value: kind)
            }
            if let workingTime = shelter.workingTime {
                divider
                row("HOURS", value: workingTime, accent: shelter.isAlwaysOpen ? VA.green : VA.orange)
            }
            if let accessible = shelter.accessible {
                divider
                row("STEP-FREE", value: accessible ? String(localized: "Yes") : String(localized: "No"),
                    accent: accessible ? VA.green : VA.secondary(0.8))
            }
            if let district = shelter.district {
                divider
                row("DISTRICT", value: district)
            }
            if let notes = shelter.notes {
                divider
                row("NOTE", value: notes)
            }
            if let phone = shelter.phone {
                divider
                row("PHONE", value: phone, accent: VA.cyan)
            }
            divider
            row("SOURCE", value: shelter.provenanceLabel,
                accent: shelter.isCityRegister ? VA.secondary(0.8) : VA.orangeText)
        }
        .background(RoundedRectangle(cornerRadius: 24).fill(.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.12)).frame(height: 0.5)
    }

    private func row(_ label: String, value: String, accent: Color = .white) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(LocalizedStringKey(label))
                .font(VAFont.mono(10, .semibold))
                .tracking(em: 0.06, size: 10)
                .foregroundStyle(VA.secondary(0.4))
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(VAFont.display(14, .regular))
                .foregroundStyle(accent)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    /// Other people's warnings, and the outcome of this person's.
    private var reportBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: bannerIcon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(bannerTint)
            Text(bannerText)
                .font(VAFont.display(13, .regular))
                .foregroundStyle(bannerTint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 18).fill(bannerTint.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(bannerTint.opacity(0.3), lineWidth: 0.5))
    }

    private var bannerIcon: String {
        switch reportState {
        case .sent: "checkmark.circle.fill"
        case .failed: "wifi.exclamationmark"
        default: "exclamationmark.triangle.fill"
        }
    }

    private var bannerTint: Color {
        switch reportState {
        case .sent: VA.green
        case .failed: VA.orange
        default: VA.orange
        }
    }

    /// Shown when two people agree, or when this device has had its say.
    private var showsBanner: Bool {
        if reportState != .idle { return true }
        return shelter.hasCorroboratedProblem || alreadyReported
    }

    private var bannerText: String {
        switch reportState {
        case .sending: String(localized: "Sending your report…")
        case .sent(let total):
            total > 1
                ? String(localized: "Thanks — \(total) people have now flagged this entry.")
                : String(localized: "Thanks — the first report on this entry. We'll check it.")
        case .failed(let message): message
        case .idle:
            if shelter.hasCorroboratedProblem {
                String(localized: "\(shelter.reports) people reported a problem with this entry.")
            } else {
                String(localized: "You reported a problem with this entry.")
            }
        }
    }

    /// Deliberately quiet and below the route button: the priority is getting there,
    /// not filing paperwork. But the register cannot correct itself, and the people
    /// standing in front of the door are the only ones who can.
    private var reportButton: some View {
        Button {
            showingReport = true
        } label: {
            Label(
                alreadyReported ? String(localized: "You reported this") : String(localized: "Report a problem"),
                systemImage: alreadyReported ? "flag.checkered" : "flag"
            )
            .font(VAFont.display(14, .medium))
            .foregroundStyle(VA.secondary(alreadyReported ? 0.4 : 0.7))
            .frame(maxWidth: .infinity)
            .frame(height: 42)
        }
        .buttonStyle(.plain)
        .disabled(alreadyReported || reportState == .sending)
        .onAppear { alreadyReported = ReportingClient.hasReported(shelter.id) }
        .confirmationDialog("What's wrong with this entry?", isPresented: $showingReport, titleVisibility: .visible) {
            ForEach(ShelterReportReason.allCases) { reason in
                Button(reason.title) { send(reason) }
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    private func send(_ reason: ShelterReportReason) {
        reportState = .sending
        Task {
            do {
                let total = try await threats.reportShelter(shelter, reason: reason)
                ReportingClient.markReported(shelter.id)
                alreadyReported = true
                reportState = .sent(total)
            } catch ThreatServiceError.server(status: 429) {
                reportState = .failed(String(localized: "You have reported a lot of shelters in the last hour. Try again later."))
            } catch {
                reportState = .failed(String(localized: "Could not send that just now — it will need retrying."))
            }
        }
    }

    private var routeButton: some View {
        Button {
            // Walking directions in Maps — the one thing you want at this moment.
            let placemark = MKPlacemark(coordinate: shelter.coordinate)
            let item = MKMapItem(placemark: placemark)
            item.name = shelter.address ?? shelter.name
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
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
