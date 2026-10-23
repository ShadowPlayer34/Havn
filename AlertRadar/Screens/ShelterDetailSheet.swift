//
//  ShelterDetailSheet.swift
//  AlertRadar
//
//  What you get when you tap a shelter pin. Everything here answers one question:
//  can I actually get into this place, right now. Below the register's answer, what
//  people who have been there say about it.
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
    /// Nil until the first fetch lands; the sheet is usable long before then.
    @State private var reviews: ShelterReviewsResponse?
    @State private var reviewsFailed = false
    @State private var composingReview = false

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
                    reviewsSection
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
        .task { await loadReviews() }
        .sheet(isPresented: $composingReview) {
            ShelterReviewSheet(shelter: shelter, existing: reviews?.mine) { reviews = $0 }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    /// The fetched rating once there is one — it is newer than the copy the pin carried
    /// in, and it is what changes when this device writes a review.
    private var rating: ShelterRating? {
        reviews.map(\.rating) ?? shelter.rating
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
            if let placeName = shelter.placeName {
                Text(placeName)
                    .font(VAFont.display(14, .regular))
                    .foregroundStyle(VA.secondary(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Text(shelter.typeTitle)
                    .font(VAFont.display(12))
                    .foregroundStyle(VA.greenText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(VA.green.opacity(0.16)))
                if let rating {
                    RatingChip(rating: rating)
                }
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
        // Once a minute, so "until 17:00" turns into "Closed" while the sheet is open.
        TimelineView(.everyMinute) { context in
            let status = shelter.hours.status(at: context.date)
            HStack(spacing: 8) {
                stat(shelter.distanceLabel, caption: String(localized: "\(shelter.walkMinutes) min walk"), tint: VA.green)
                stat(Self.value(status), caption: Self.caption(status), tint: Self.tint(status))
            }
            // Both cards as tall as the taller caption.
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func value(_ status: ShelterHours.Status) -> String {
        switch status {
        case .alwaysOpen: "24/7"
        case .open: String(localized: "Open")
        case .closed, .unavailable: String(localized: "Closed")
        case .duringAlerts: String(localized: "On alert")
        case .unknown: "Limited"
        }
    }

    private static func caption(_ status: ShelterHours.Status) -> String {
        switch status {
        case .alwaysOpen: "always open"
        case .open(let closesAt): String(localized: "until \(clock(closesAt))")
        case .closed(let opensAt, let daysAhead, let weekday):
            switch daysAhead {
            case 0: String(localized: "opens \(clock(opensAt))")
            case 1: String(localized: "opens tomorrow \(clock(opensAt))")
            default: String(localized: "opens \(weekdayName(weekday)) \(clock(opensAt))")
            }
        case .duringAlerts: String(localized: "opens during alerts")
        case .unavailable: String(localized: "out of service")
        case .unknown: "check hours"
        }
    }

    /// Green only where the register says the door is open now, or will be on an alert.
    private static func tint(_ status: ShelterHours.Status) -> Color {
        switch status {
        case .alwaysOpen, .open, .duringAlerts: VA.green
        case .closed, .unavailable, .unknown: VA.orange
        }
    }

    /// The register's own wall-clock time, so no time-zone conversion: "08:00", "24:00".
    private static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    /// "Mon", "пн", in the language the app is running in.
    private static func weekdayName(_ isoWeekday: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        return calendar.shortStandaloneWeekdaySymbols[isoWeekday % 7]
    }

    private func stat(_ value: String, caption: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedStringKey(value))
                .font(VAFont.rounded(28))
                .tracking(em: -0.02, size: 28)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(LocalizedStringKey(caption))
                .font(VAFont.display(11, .medium))
                .foregroundStyle(VA.secondary(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22).fill(tint.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(tint.opacity(0.3), lineWidth: 0.5))
    }

    private var details: some View {
        VStack(spacing: 0) {
            // No compass on screen: an arrow would only be right with the phone facing north.
            if let origin = threats.sheltersOrigin, let direction = shelter.direction(from: origin) {
                row("DIRECTION", value: direction.title)
                divider
            }
            if let kind = shelter.kind {
                row("TYPE", value: kind)
                divider
            }
            if let building = shelter.buildingDescription {
                row("BUILDING", value: building)
                divider
            }
            if let workingTime = shelter.workingTime {
                row("HOURS", value: workingTime, accent: shelter.isAlwaysOpen ? VA.green : VA.orange,
                    checked: .hours)
                divider
            }
            if let accessible = shelter.accessible {
                row("STEP-FREE", value: accessible ? String(localized: "Yes") : String(localized: "No"),
                    accent: accessible ? VA.green : VA.secondary(0.8), checked: .accessible)
                divider
            }
            if let wifi = shelter.wifi {
                row("WI-FI", value: wifi ? String(localized: "Yes") : String(localized: "No"),
                    accent: wifi ? VA.green : VA.secondary(0.8), checked: .wifi)
                divider
            }
            if let district = shelter.district {
                row("DISTRICT", value: district)
                divider
            }
            if let note = shelter.notes {
                row("NOTE", value: note)
                divider
            }
            if let phone = shelter.phone {
                phoneRow(phone)
                divider
            }
            // Whether the pin is where the door is: a question about the register's
            // position, which is what this row is already answering.
            row("SOURCE", value: shelter.provenanceLabel,
                accent: shelter.isCityRegister ? VA.secondary(0.8) : VA.orangeText, checked: .location)
        }
        .background(RoundedRectangle(cornerRadius: 24).fill(.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.12)).frame(height: 0.5)
    }

    /// `checked` names the register fact this row states, so what reviewers found when
    /// they checked it can sit right under the claim.
    private func row(
        _ label: String, value: String, accent: Color = .white, checked fact: ShelterFact? = nil
    ) -> some View {
        let tally = fact.flatMap { reviews?.facts[$0] }
        return row(label) {
            VStack(alignment: .leading, spacing: 5) {
                Text(value)
                    .font(VAFont.display(14, .regular))
                    // A green "Yes" over "2 say it's wrong" would be the sheet arguing
                    // with itself.
                    .foregroundStyle(tally?.isDisputed == true ? VA.orangeText : accent)
                    .fixedSize(horizontal: false, vertical: true)
                if let fact, let tally, !tally.isEmpty {
                    FactTallyLine(fact: fact, tally: tally)
                }
            }
        }
    }

    private func row<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(LocalizedStringKey(label))
                .font(VAFont.mono(10, .semibold))
                .tracking(em: 0.06, size: 10)
                .foregroundStyle(VA.secondary(0.4))
                .frame(width: 78, alignment: .leading)
            value()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    /// Each number the register printed, ready to call. The raw text when none of it
    /// reads as a number that can be dialled.
    @ViewBuilder
    private func phoneRow(_ phone: String) -> some View {
        let numbers = shelter.phoneNumbers
        if numbers.isEmpty {
            row("PHONE", value: phone)
        } else {
            row("PHONE") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(numbers, id: \.self) { number in
                        Link(destination: number.url) {
                            Label(number.display, systemImage: "phone.fill")
                                .font(VAFont.display(14, .medium))
                                .foregroundStyle(VA.cyan)
                        }
                        .accessibilityLabel(Text("Call \(number.display)"))
                    }
                }
            }
        }
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

    // MARK: Reviews

    private func loadReviews() async {
        reviewsFailed = false
        do {
            reviews = try await threats.reviews(for: shelter)
        } catch is CancellationError {
            // The sheet went away.
        } catch {
            reviewsFailed = true
        }
    }

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("REVIEWS")
                .font(VAFont.mono(10, .semibold))
                .tracking(em: 0.06, size: 10)
                .foregroundStyle(VA.secondary(0.4))
                .padding(.top, 6)
            reviewsSummary
            if let mine = reviews?.mine {
                ReviewCard(review: mine, isMine: true) { composingReview = true }
            }
            ForEach(reviews?.reviews ?? []) { review in
                ReviewCard(review: review)
            }
        }
    }

    private var reviewsSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let reviews {
                if let rating = reviews.rating {
                    HStack(alignment: .center, spacing: 12) {
                        Text(rating.averageLabel)
                            .font(VAFont.rounded(36))
                            .foregroundStyle(.white)
                        VStack(alignment: .leading, spacing: 4) {
                            StarsView(rating: rating.average, size: 14)
                            Text("\(rating.count) reviews")
                                .font(VAFont.display(12, .medium))
                                .foregroundStyle(VA.secondary(0.55))
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Rated \(rating.averageLabel) out of 5. Reviews: \(rating.count)"))
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No reviews yet")
                            .font(VAFont.display(15))
                            .foregroundStyle(.white)
                        Text("Been here? Tell others what it's like inside and whether the register is right.")
                            .font(VAFont.display(13, .regular))
                            .foregroundStyle(VA.secondary(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                writeReviewButton(editing: reviews.mine != nil)
            } else if reviewsFailed {
                HStack(spacing: 10) {
                    Text("Could not load reviews.")
                        .font(VAFont.display(13, .regular))
                        .foregroundStyle(VA.secondary(0.6))
                    Spacer(minLength: 0)
                    Button("Retry") { Task { await loadReviews() } }
                        .font(VAFont.display(13))
                        .foregroundStyle(VA.cyan)
                        .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading reviews…")
                        .font(VAFont.display(13, .regular))
                        .foregroundStyle(VA.secondary(0.6))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24).fill(.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
    }

    private func writeReviewButton(editing: Bool) -> some View {
        Button {
            composingReview = true
        } label: {
            Label(
                editing ? String(localized: "Edit your review") : String(localized: "Write a review"),
                systemImage: editing ? "pencil" : "star.bubble"
            )
            .font(VAFont.display(14))
            .foregroundStyle(VA.cyanText)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Capsule().fill(VA.cyan.opacity(0.16)))
        }
        .buttonStyle(.plain)
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
