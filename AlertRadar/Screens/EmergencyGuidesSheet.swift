import CoreLocation
import MessageUI
import SwiftUI

/// One "what to do" guide. The text ships in the app, so it reads the same with no signal.
struct EmergencyGuide: Identifiable, Equatable {
    struct Step: Equatable {
        let title: String
        let detail: String
    }

    let id: String
    let title: String
    let color: Color
    let lead: String
    let steps: [Step]
    let warning: String

    /// Content as written in the design document, which credits State Emergency Service
    /// (DSNS) guidance.
    static let all: [EmergencyGuide] = [
        EmergencyGuide(
            id: "rubble",
            title: String(localized: "Trapped under rubble"),
            color: VA.red,
            lead: String(localized: "Rescuers search by sound first. Your job is to stay still, breathe clean air and be heard."),
            steps: [
                Step(title: String(localized: "Stay still and check yourself"), detail: String(localized: "Move slowly. Sudden movement can shift debris above you.")),
                Step(title: String(localized: "Cover your nose and mouth"), detail: String(localized: "Use clothing or any fabric to filter dust.")),
                Step(title: String(localized: "No matches or lighters"), detail: String(localized: "There may be a gas leak nearby.")),
                Step(title: String(localized: "Tap on a pipe or wall"), detail: String(localized: "Three knocks, pause, repeat. Use a whistle if you have one. Shout only as a last resort — it makes you inhale dust.")),
                Step(title: String(localized: "Save your battery"), detail: String(localized: "Send an SMS with your location to 112 or a contact instead of calling. Turn on Low Power Mode.")),
                Step(title: String(localized: "If a limb is pinned, wait"), detail: String(localized: "Do not pull it free yourself after a long time trapped. Tell rescuers how long it has been.")),
            ],
            warning: String(localized: "Do not try to dig yourself out if debris above you is unstable. Wait for DSNS rescuers.")
        ),
        EmergencyGuide(
            id: "blast",
            title: String(localized: "Explosion nearby"),
            color: VA.orange,
            lead: String(localized: "If you hear a launch or explosion and are not in a shelter, drop immediately."),
            steps: [
                Step(title: String(localized: "Lie face down"), detail: String(localized: "Cover your head with your hands, mouth slightly open to protect your eardrums.")),
                Step(title: String(localized: "Use any cover"), detail: String(localized: "A curb, ditch or wall between you and the blast. Stay away from windows.")),
                Step(title: String(localized: "Stay down"), detail: String(localized: "Wait at least a few minutes. Secondary explosions are common.")),
                Step(title: String(localized: "Move to shelter"), detail: String(localized: "Go to the nearest shelter, not toward the impact site.")),
            ],
            warning: String(localized: "Do not film or approach the impact site. Debris and unexploded parts can be dangerous.")
        ),
        EmergencyGuide(
            id: "fire",
            title: String(localized: "Fire and smoke"),
            color: Color(hex: 0xFF6B3D),
            lead: String(localized: "Smoke is the main danger. Stay low and leave early."),
            steps: [
                Step(title: String(localized: "Stay low"), detail: String(localized: "Cleaner air is close to the floor. Cover your face with damp fabric.")),
                Step(title: String(localized: "Check doors before opening"), detail: String(localized: "If the handle is hot, use another way out.")),
                Step(title: String(localized: "Use stairs, not lifts"), detail: String(localized: "Lifts can stop when power goes out.")),
                Step(title: String(localized: "Call 101 once outside"), detail: String(localized: "Give the address, floor and whether anyone is still inside.")),
            ],
            warning: String(localized: "If you cannot leave, seal the door gaps with wet cloth and signal from a window.")
        ),
        EmergencyGuide(
            id: "bleed",
            title: String(localized: "Severe bleeding"),
            color: Color(hex: 0xFF2D55),
            lead: String(localized: "Heavy bleeding can be fatal within minutes. Press first, then call."),
            steps: [
                Step(title: String(localized: "Press hard on the wound"), detail: String(localized: "Use cloth or your hand. Keep constant pressure.")),
                Step(title: String(localized: "Tourniquet for limbs"), detail: String(localized: "Place it 5–7 cm above the wound, tighten until bleeding stops.")),
                Step(title: String(localized: "Note the time"), detail: String(localized: "Write the time the tourniquet was applied on the skin or tourniquet.")),
                Step(title: String(localized: "Call 103"), detail: String(localized: "Keep the person warm and lying down until help arrives.")),
            ],
            warning: String(localized: "Never loosen a tourniquet once applied. Medics will remove it.")
        ),
        EmergencyGuide(
            id: "gas",
            title: String(localized: "Gas smell"),
            color: Color(hex: 0xFFD60A),
            lead: String(localized: "Treat any gas smell as a leak."),
            steps: [
                Step(title: String(localized: "No switches or flames"), detail: String(localized: "Do not turn lights on or off, do not use a lighter.")),
                Step(title: String(localized: "Open windows"), detail: String(localized: "Ventilate if it is safe to do so.")),
                Step(title: String(localized: "Leave the building"), detail: String(localized: "Warn neighbours by knocking, not by doorbell.")),
                Step(title: String(localized: "Call 104 from outside"), detail: String(localized: "Do not call from inside the building.")),
            ],
            warning: String(localized: "Do not use a phone inside a room where gas is strong.")
        ),
        EmergencyGuide(
            id: "bag",
            title: String(localized: "Go-bag and shelter kit"),
            color: VA.green,
            lead: String(localized: "Keep a bag ready by the door."),
            steps: [
                Step(title: String(localized: "Documents"), detail: String(localized: "Passport, ID and copies in a waterproof pouch.")),
                Step(title: String(localized: "Water and food"), detail: String(localized: "2 litres of water per person, food for 2–3 days.")),
                Step(title: String(localized: "Power and light"), detail: String(localized: "Charged power bank, torch, spare batteries.")),
                Step(title: String(localized: "Medical"), detail: String(localized: "First-aid kit, tourniquet, personal medicines for a week.")),
                Step(title: String(localized: "Whistle and warm layer"), detail: String(localized: "A whistle helps rescuers find you.")),
            ],
            warning: String(localized: "Check expiry dates and charge levels once a month.")
        ),
    ]
}

/// Emergency guides — design option 3b. A list, and one guide at a time with its steps,
/// a warning, and the two things someone in it is most likely to need: 101 and a way to
/// tell people where they are.
struct EmergencyGuidesSheet: View {
    /// Shown on the dial confirm card and put in the "Send location" message.
    var coordinate: CLLocationCoordinate2D?

    @State private var open: EmergencyGuide?
    @State private var pending: EmergencyLine?
    @State private var contacts = EmergencyContactsStore()
    @State private var pickingContacts = false
    @State private var composingMessage = false
    @State private var messagesUnavailable = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if let open {
                detail(open)
                    .transition(.move(edge: .trailing))
            } else {
                list
                    .transition(.move(edge: .leading))
            }

            DialConfirmOverlay(line: $pending, coordinate: coordinate)
        }
        .animation(.snappy(duration: 0.3), value: open)
        .animation(.snappy(duration: 0.3), value: pending)
        .background(VA.canvas)
        .background {
            ContactPicker(isPresented: $pickingContacts) { picked in
                contacts.add(picked.compactMap(EmergencyContact.init))
            }
            MessageComposer(
                isPresented: $composingMessage,
                recipients: contacts.contacts.map(\.phone),
                messageText: helpMessage
            ) { _ in }
        }
        .alert("Messages unavailable", isPresented: $messagesUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device cannot send text messages.")
        }
    }

    // MARK: List

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom, spacing: 10) {
                    Text("Guides")
                        .font(VAFont.display(34, .bold))
                        .tracking(em: -0.02, size: 34)
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    savedOfflineBadge
                        .padding(.bottom, 6)
                }
                .padding(.horizontal, 4)

                Text("Short steps you can follow without signal. Based on State Emergency Service (DSNS) guidance.")
                    .font(VAFont.display(14, .regular))
                    .foregroundStyle(VA.secondary(0.6))
                    .padding(.horizontal, 4)

                VStack(spacing: 8) {
                    ForEach(Array(EmergencyGuide.all.enumerated()), id: \.element.id) { index, guide in
                        Button {
                            open = guide
                        } label: {
                            guideRow(guide, number: index + 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            // Clear of the system grabber.
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private var savedOfflineBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(VA.green)
                .frame(width: 6, height: 6)
            Text("Saved offline")
                .font(VAFont.display(11))
                .foregroundStyle(VA.green)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(VA.green.opacity(0.14)))
        .overlay(Capsule().strokeBorder(VA.green.opacity(0.35), lineWidth: 0.5))
    }

    private func guideRow(_ guide: EmergencyGuide, number: Int) -> some View {
        HStack(spacing: 13) {
            Text("\(number)")
                .font(VAFont.rounded(15))
                .foregroundStyle(guide.color)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12).fill(guide.color.opacity(0.16)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(guide.color, lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 4) {
                Text(guide.title)
                    .font(VAFont.display(16))
                    .foregroundStyle(.white)
                Text("\(guide.steps.count) steps · works offline")
                    .font(VAFont.display(12.5, .regular))
                    .foregroundStyle(VA.secondary(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(VA.secondary(0.3))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22).fill(.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .contentShape(RoundedRectangle(cornerRadius: 22))
    }

    // MARK: Detail

    private func detail(_ guide: EmergencyGuide) -> some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    backButton

                    VStack(alignment: .leading, spacing: 6) {
                        Text(guide.title)
                            .font(VAFont.display(30, .bold))
                            .tracking(em: -0.02, size: 30)
                            .foregroundStyle(.white)
                        Text(guide.lead)
                            .font(VAFont.display(14, .regular))
                            .foregroundStyle(VA.secondary(0.6))
                    }
                    .padding(.horizontal, 4)

                    VStack(spacing: 8) {
                        ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                            stepCard(step, number: index + 1)
                        }
                    }

                    warningCard(guide.warning)
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                // Clear of the action bar.
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)

            actionBar
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }

    private var backButton: some View {
        Button {
            open = nil
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                Text("Guides")
                    .font(VAFont.display(15))
            }
            .foregroundStyle(Color(hex: 0x5CC2F0))
            .padding(.leading, 12)
            .padding(.trailing, 16)
            .frame(height: 44)
            .vaGlass(Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func stepCard(_ step: EmergencyGuide.Step, number: Int) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Text("\(number)")
                .font(VAFont.rounded(14))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(0.12)))
            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(VAFont.display(15.5))
                    .foregroundStyle(.white)
                Text(step.detail)
                    .font(VAFont.display(13, .regular))
                    .foregroundStyle(VA.secondary(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20).fill(.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
    }

    private func warningCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            RoundedRectangle(cornerRadius: 2)
                .fill(VA.orange)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            Text(text)
                .font(VAFont.display(13.5, .medium))
                .foregroundStyle(Color(hex: 0xFFC777))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20).fill(VA.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(VA.orange.opacity(0.4), lineWidth: 0.5))
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                pending = EmergencyLine.services.first { $0.number == "101" }
            } label: {
                Text("Call 101")
                    .font(VAFont.display(16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        Capsule().fill(LinearGradient(
                            colors: [Color(hex: 0xFF5A52, opacity: 0.95), Color(hex: 0xFF2D22, opacity: 0.92)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                    )
                    .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Button {
                sendLocation()
            } label: {
                Text("Send location")
                    .font(VAFont.display(16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Capsule().fill(.white.opacity(0.1)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .vaGlass(RoundedRectangle(cornerRadius: 36))
    }

    // MARK: Send location

    /// Goes to the emergency contacts, the same people "I'm safe" goes to. The design's
    /// version texted 112; whether 112 takes SMS varies by region, so this does not rely
    /// on it. With nobody chosen yet the first tap opens the picker.
    private func sendLocation() {
        guard !contacts.contacts.isEmpty else {
            pickingContacts = true
            return
        }
        guard MFMessageComposeViewController.canSendText() else {
            messagesUnavailable = true
            return
        }
        composingMessage = true
    }

    private var helpMessage: String {
        guard let coordinate else { return String(localized: "I need help.") }
        return String(localized: "I need help. My location: \(coordinate.mapsLink)")
    }
}

#Preview {
    EmergencyGuidesSheet(coordinate: CLLocationCoordinate2D(latitude: 50.4501, longitude: 30.5234))
        .preferredColorScheme(.dark)
}
