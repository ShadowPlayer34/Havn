//
//  ShelterReviewViews.swift
//  AlertRadar
//
//  The pieces of a shelter's reviews that the sheet, the review form and the map pin
//  share: stars, the rating chip, a fact's tally and one person's review.
//

import SwiftUI

/// Five stars, filled to the nearest half.
struct StarsView: View {
    let rating: Double
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: size * 0.15) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: symbol(for: star))
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(VA.yellow)
            }
        }
        .accessibilityHidden(true)
    }

    private func symbol(for star: Int) -> String {
        let halves = (rating * 2).rounded()
        if halves >= Double(star * 2) { return "star.fill" }
        if halves == Double(star * 2 - 1) { return "star.leadinghalf.filled" }
        return "star"
    }
}

/// "★ 4.3 · 12" — beside the shelter type, so it is seen before anything is scrolled.
struct RatingChip: View {
    let rating: ShelterRating

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: 10, weight: .bold))
            Text(verbatim: "\(rating.averageLabel) · \(rating.count)")
                .font(VAFont.display(12))
        }
        .foregroundStyle(VA.yellow)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(VA.yellow.opacity(0.14)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Rated \(rating.averageLabel) out of 5. Reviews: \(rating.count)"))
    }
}

/// Under a register row: how many people found it right, how many found it wrong. Turns
/// orange only once the people saying it is wrong are both corroborated and the
/// majority — one dissenting voice is shown, but not as a warning.
struct FactTallyLine: View {
    let fact: ShelterFact
    let tally: FactTally

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: tally.isDisputed ? "exclamationmark.triangle.fill" : "person.2.fill")
                .font(.system(size: 10, weight: .semibold))
            Text(summary)
                .font(VAFont.display(12, .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tally.isDisputed ? VA.orangeText : VA.secondary(0.55))
    }

    private var summary: String {
        var parts: [String] = []
        if tally.confirmed > 0 {
            parts.append(
                fact == .location
                    ? String(localized: "\(tally.confirmed) found it at the pin")
                    : String(localized: "Confirmed by \(tally.confirmed)")
            )
        }
        if tally.disputed > 0 {
            parts.append(
                fact == .location
                    ? String(localized: "\(tally.disputed) say the pin is in the wrong place")
                    : String(localized: "\(tally.disputed) say it's wrong")
            )
        }
        return parts.joined(separator: " · ")
    }
}

/// One person's review: stars, when, what they wrote, and which register facts they
/// found right or wrong.
struct ReviewCard: View {
    let review: ShelterReview
    var isMine = false
    var onEdit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StarsView(rating: Double(review.rating), size: 11)
                Text(review.updatedAt, format: Self.relative)
                    .font(VAFont.display(11, .medium))
                    .foregroundStyle(VA.secondary(0.45))
                Spacer(minLength: 0)
                if isMine, let onEdit {
                    Button("Edit", action: onEdit)
                        .font(VAFont.display(13))
                        .foregroundStyle(VA.cyan)
                        .buttonStyle(.plain)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("\(review.rating) out of 5"))
            if isMine {
                Text("YOUR REVIEW")
                    .font(VAFont.mono(9.5, .semibold))
                    .tracking(em: 0.08, size: 9.5)
                    .foregroundStyle(VA.cyanText)
            }
            if let text = review.text {
                Text(text)
                    .font(VAFont.display(14, .regular))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let checked = ShelterFact.allCases.compactMap { fact in review.checks[fact].map { (fact, $0) } }
            if !checked.isEmpty {
                HStack(spacing: 6) {
                    ForEach(checked, id: \.0) { fact, isRight in
                        verdictChip(fact, isRight: isRight)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20).fill(.white.opacity(isMine ? 0.1 : 0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(isMine ? VA.cyan.opacity(0.35) : .white.opacity(0.1), lineWidth: 0.5)
        )
    }

    private func verdictChip(_ fact: ShelterFact, isRight: Bool) -> some View {
        Label(fact.title, systemImage: isRight ? "checkmark" : "xmark")
            .font(VAFont.display(11, .medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isRight ? VA.greenText : VA.orangeText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill((isRight ? VA.green : VA.orange).opacity(0.14)))
            .accessibilityLabel(
                isRight ? Text("\(fact.title): as listed") : Text("\(fact.title): not as listed")
            )
    }

    /// "2 days ago", in the app's language rather than the device's — the same reason the
    /// shelter sheet names weekdays this way.
    private static let relative = Date.RelativeFormatStyle(
        presentation: .named,
        locale: Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    )
}
