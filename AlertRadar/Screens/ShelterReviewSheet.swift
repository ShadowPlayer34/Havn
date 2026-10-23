//
//  ShelterReviewSheet.swift
//  AlertRadar
//
//  Writing a review: how good the shelter is, which of the register's lines held up,
//  and anything else worth knowing before you go. Only the stars are required — the
//  person filling this in may have just come up out of a basement.
//

import SwiftUI

struct ShelterReviewSheet: View {
    let shelter: Shelter
    /// This device's earlier review, which writing again replaces.
    let existing: ShelterReview?
    let onSaved: (ShelterReviewsResponse) -> Void

    @Environment(ThreatViewModel.self) private var threats
    @Environment(\.dismiss) private var dismiss
    @State private var rating: Int
    @State private var checks: ReviewChecks
    @State private var text: String
    @State private var state: SubmitState = .idle
    @State private var confirmingDelete = false
    @FocusState private var writing: Bool

    private enum SubmitState: Equatable {
        case idle, sending, failed(String)
    }

    /// The server's limit, enforced while typing rather than as an error afterwards.
    static let maxLength = 500
    private static let textAnchor = "text-counter"

    init(shelter: Shelter, existing: ShelterReview?, onSaved: @escaping (ShelterReviewsResponse) -> Void) {
        self.shelter = shelter
        self.existing = existing
        self.onSaved = onSaved
        _rating = State(initialValue: existing?.rating ?? 0)
        _checks = State(initialValue: existing?.checks ?? ReviewChecks())
        _text = State(initialValue: existing?.text ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        starPicker
                        factsSection
                        textSection
                        Text("Reviews are anonymous. Anyone using the app can read them.")
                            .font(VAFont.display(12, .regular))
                            .foregroundStyle(VA.secondary(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 36)
                    .padding(.bottom, 16)
                    // A tap anywhere that is not a control puts the keyboard away. Behind
                    // the content rather than on it, so a tap inside the editor still
                    // reaches the editor.
                    .background {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { writing = false }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: writing) {
                    guard writing else { return }
                    // The system only scrolls far enough to show the caret, which leaves
                    // one line of the editor between the keyboard and the send button.
                    // Once the keyboard has settled, bring the whole box up.
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        withAnimation { proxy.scrollTo(Self.textAnchor, anchor: .bottom) }
                    }
                }
            }

            // Stays above the keyboard: someone who has finished typing should be able to
            // send without hunting for a way to put the keyboard away first.
            bottomBar
        }
        .preferredColorScheme(.dark)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if case .failed(let message) = state {
                Text(message)
                    .font(VAFont.display(13, .regular))
                    .foregroundStyle(VA.orangeText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            submitButton
            if existing != nil {
                deleteButton
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(existing == nil ? "Rate this shelter" : "Edit your review")
                    .font(VAFont.display(22))
                    .tracking(em: -0.02, size: 22)
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Button("Cancel") { dismiss() }
                    .font(VAFont.display(15))
                    .foregroundStyle(Color(hex: 0x5CC2F0))
                    .buttonStyle(.plain)
            }
            Text(shelter.address ?? shelter.name)
                .font(VAFont.display(14, .regular))
                .foregroundStyle(VA.secondary(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Stars

    private var starPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("OVERALL")
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        rating = star
                        writing = false
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(star <= rating ? VA.yellow : VA.secondary(0.35))
                            .frame(width: 48, height: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(star) out of 5"))
                    .accessibilityAddTraits(star == rating ? .isSelected : [])
                }
            }
            .sensoryFeedback(.selection, trigger: rating)
            Text(Self.ratingCaption(rating))
                .font(VAFont.display(13, .medium))
                .foregroundStyle(rating == 0 ? VA.secondary(0.5) : VA.yellow)
        }
    }

    private static func ratingCaption(_ rating: Int) -> String {
        switch rating {
        case 1: String(localized: "Unusable")
        case 2: String(localized: "Poor")
        case 3: String(localized: "Okay")
        case 4: String(localized: "Good")
        case 5: String(localized: "Excellent")
        default: String(localized: "Tap a star to rate")
        }
    }

    // MARK: Register checks

    /// One row per line of the register that can be checked at the door. Nothing is
    /// preselected: a verdict means somebody looked.
    private var factsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("IS THE REGISTER RIGHT?")
            Text("Answer only what you saw yourself. Leave the rest.")
                .font(VAFont.display(13, .regular))
                .foregroundStyle(VA.secondary(0.6))
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(Array(shelter.checkableFacts.enumerated()), id: \.element) { index, fact in
                    if index > 0 {
                        Rectangle().fill(.white.opacity(0.12)).frame(height: 0.5)
                    }
                    factRow(fact)
                }
            }
            .background(RoundedRectangle(cornerRadius: 24).fill(.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        }
    }

    private func factRow(_ fact: ShelterFact) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(fact.label))
                    .font(VAFont.mono(10, .semibold))
                    .tracking(em: 0.06, size: 10)
                    .foregroundStyle(VA.secondary(0.4))
                Text(shelter.registerClaim(fact))
                    .font(VAFont.display(14, .regular))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                verdictButton(fact, isRight: true)
                verdictButton(fact, isRight: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    /// Tapping the chosen verdict again takes it back to "didn't check".
    private func verdictButton(_ fact: ShelterFact, isRight: Bool) -> some View {
        let selected = checks[fact] == isRight
        let tint = isRight ? VA.green : VA.orange
        return Button {
            checks[fact] = selected ? nil : isRight
            writing = false
        } label: {
            Label(
                isRight ? String(localized: "Right") : String(localized: "Wrong"),
                systemImage: isRight ? "checkmark" : "xmark"
            )
            .font(VAFont.display(13))
            .foregroundStyle(selected ? (isRight ? VA.greenText : VA.orangeText) : VA.secondary(0.6))
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(Capsule().fill(selected ? tint.opacity(0.22) : .white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(selected ? tint.opacity(0.5) : .white.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Text

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("WHAT IS IT LIKE INSIDE?")
            TextEditor(text: $text)
                .focused($writing)
                .font(VAFont.display(15, .regular))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Water, toilets, seating, mobile signal, how crowded it gets…")
                            .font(VAFont.display(15, .regular))
                            .foregroundStyle(VA.secondary(0.35))
                            .padding(.horizontal, 17)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 20).fill(.white.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
                .onChange(of: text) {
                    if text.count > Self.maxLength {
                        text = String(text.prefix(Self.maxLength))
                    }
                }
            Text(verbatim: "\(text.count)/\(Self.maxLength)")
                .font(VAFont.mono(10.5))
                .foregroundStyle(VA.secondary(0.4))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .id(Self.textAnchor)
        }
    }

    private func sectionLabel(_ label: String) -> some View {
        Text(LocalizedStringKey(label))
            .font(VAFont.mono(10, .semibold))
            .tracking(em: 0.06, size: 10)
            .foregroundStyle(VA.secondary(0.4))
    }

    // MARK: Sending

    private var submitButton: some View {
        Button(action: submit) {
            Group {
                if state == .sending {
                    ProgressView().tint(VA.cyanInk)
                } else {
                    Text(existing == nil ? "Post review" : "Save changes")
                }
            }
            .font(VAFont.display(17))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .buttonStyle(.glassProminent)
        .tint(VA.cyan)
        .foregroundStyle(VA.cyanInk)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .disabled(rating == 0 || state == .sending)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            confirmingDelete = true
        } label: {
            Text("Delete my review")
                .font(VAFont.display(14, .medium))
                .foregroundStyle(VA.redText)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
        }
        .buttonStyle(.plain)
        .disabled(state == .sending)
        .confirmationDialog("Delete your review?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: withdraw)
            Button("Cancel", role: .cancel) { }
        }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A verdict left over on a fact this entry no longer states would be dropped by
        // the server anyway; not sending it keeps the form and the result in agreement.
        var sent = ReviewChecks()
        for fact in shelter.checkableFacts {
            sent[fact] = checks[fact]
        }
        let request = ShelterReviewRequest(rating: rating, checks: sent, text: trimmed.isEmpty ? nil : trimmed)
        perform { try await threats.review(shelter, request) }
    }

    private func withdraw() {
        perform { try await threats.withdrawReview(of: shelter) }
    }

    private func perform(_ call: @escaping () async throws -> ShelterReviewsResponse) {
        writing = false
        state = .sending
        Task {
            do {
                onSaved(try await call())
                dismiss()
            } catch ThreatServiceError.server(status: 429) {
                state = .failed(String(localized: "You have reviewed a lot of shelters in the last hour. Try again later."))
            } catch {
                state = .failed(String(localized: "Could not send that just now. Try again in a moment."))
            }
        }
    }
}
