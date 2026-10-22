import ContactsUI
import CoreLocation
import MessageUI
import SwiftUI

/// One number on the emergency screen. `number` is as printed ("15-80"); the dialled form
/// drops everything but the digits.
struct EmergencyLine: Identifiable, Equatable {
    let number: String
    let name: String
    let detail: String
    /// The service's dot on the grid. Nil for city lines, which carry no accent.
    var color: Color?

    var id: String { number }

    var telURL: URL? { URL(string: "tel:\(number.filter(\.isNumber))") }

    static let single = EmergencyLine(
        number: "112", name: String(localized: "Single emergency line"), detail: String(localized: "Connects to any service"), color: VA.red
    )

    static let services: [EmergencyLine] = [
        EmergencyLine(number: "101", name: String(localized: "Rescue · DSNS"), detail: String(localized: "Fire, rubble, rescue"), color: VA.orange),
        EmergencyLine(number: "102", name: String(localized: "Police"), detail: String(localized: "Crime, suspicious objects"), color: VA.cyan),
        EmergencyLine(number: "103", name: String(localized: "Ambulance"), detail: String(localized: "Injuries, medical help"), color: VA.red),
        EmergencyLine(number: "104", name: String(localized: "Gas service"), detail: String(localized: "Gas leaks"), color: Color(hex: 0xFFD60A)),
    ]

    static let cityLines: [EmergencyLine] = [
        EmergencyLine(number: "1551", name: String(localized: "Kyiv city contact centre"), detail: String(localized: "Utilities, heating, shelter access")),
        EmergencyLine(number: "15-80", name: String(localized: "Kyiv emergency hotline"), detail: String(localized: "Damaged buildings after strikes")),
    ]
}

/// Emergency services and quick dial — design option 3c. Every number goes through a
/// confirm card first: a mis-tap on a grid this dense should not ring the police.
///
/// "I'm safe" opens a prefilled message rather than sending one: iOS has no permission
/// that lets an app send SMS by itself, so the person always presses Send.
struct EmergencyServicesSheet: View {
    /// Shown on the confirm card so it can be read out to the operator, and put in the
    /// "I'm safe" message.
    var coordinate: CLLocationCoordinate2D?

    @State private var pending: EmergencyLine?
    @State private var contacts = EmergencyContactsStore()
    @State private var pickingContacts = false
    @State private var composingMessage = false
    @State private var messagesUnavailable = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    singleLineCard
                    servicesGrid
                    sectionLabel("KYIV · CITY LINES")
                    cityList
                    sectionLabel("MY CONTACTS")
                    contactsRow
                    safeButton
                }
                .padding(.horizontal, 16)
                // Clear of the system grabber.
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            DialConfirmOverlay(line: $pending, coordinate: coordinate)
        }
        .animation(.snappy(duration: 0.3), value: pending)
        .background(VA.canvas)
        .background {
            ContactPicker(isPresented: $pickingContacts) { picked in
                contacts.add(picked.compactMap(EmergencyContact.init))
            }
            MessageComposer(
                isPresented: $composingMessage,
                recipients: contacts.contacts.map(\.phone),
                messageText: safeMessage
            ) { result in
                if result == .sent { contacts.markSent(to: contacts.contacts.count) }
            }
        }
        .alert("Messages unavailable", isPresented: $messagesUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device cannot send text messages.")
        }
    }

    // MARK: Directory

    private var header: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text("Emergency")
                .font(VAFont.display(34, .bold))
                .tracking(em: -0.02, size: 34)
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Text("Free · no SIM needed for 112")
                .font(VAFont.display(12, .medium))
                .foregroundStyle(VA.secondary(0.45))
        }
        .padding(.horizontal, 4)
    }

    private var singleLineCard: some View {
        let line = EmergencyLine.single
        return Button {
            pending = line
        } label: {
            HStack(spacing: 16) {
                Text(line.number)
                    .font(VAFont.rounded(46))
                    .tracking(em: -0.02, size: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text(line.name)
                        .font(VAFont.display(17))
                    Text(line.detail)
                        .font(VAFont.display(12.5, .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(LinearGradient(
                        colors: [Color(hex: 0xFF5A52, opacity: 0.9), Color(hex: 0xFF2D22, opacity: 0.86)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
            )
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
            .shadow(color: VA.red.opacity(0.25), radius: 15, y: 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Call 112, \(line.name)")
    }

    private var servicesGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(EmergencyLine.services) { line in
                Button {
                    pending = line
                } label: {
                    serviceTile(line)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Call \(line.number), \(line.name)")
            }
        }
    }

    private func serviceTile(_ line: EmergencyLine) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle()
                    .fill(line.color ?? VA.secondary())
                    .frame(width: 8, height: 8)
                Text(line.name)
                    .font(VAFont.display(12))
                    .foregroundStyle(VA.secondary(0.7))
                    .lineLimit(1)
            }
            Text(line.number)
                .font(VAFont.rounded(36))
                .tracking(em: -0.02, size: 36)
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Text(line.detail)
                .font(VAFont.display(11.5, .regular))
                .foregroundStyle(VA.secondary(0.5))
                .lineLimit(2)
        }
        .padding(14)
        // The design's 118 includes the padding (`box-sizing: border-box`).
        .frame(maxWidth: .infinity, minHeight: 118, maxHeight: 118, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24).fill(.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .contentShape(RoundedRectangle(cornerRadius: 24))
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(VAFont.display(10))
            .tracking(em: 0.1, size: 10)
            .foregroundStyle(VA.secondary(0.45))
            .padding(.horizontal, 4)
            .padding(.top, 6)
    }

    private var cityList: some View {
        VStack(spacing: 0) {
            ForEach(Array(EmergencyLine.cityLines.enumerated()), id: \.element.id) { index, line in
                if index > 0 {
                    Rectangle().fill(.white.opacity(0.1)).frame(height: 0.5)
                }
                Button {
                    pending = line
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(line.name)
                                .font(VAFont.display(15, .medium))
                                .foregroundStyle(.white)
                            Text(line.detail)
                                .font(VAFont.display(12, .regular))
                                .foregroundStyle(VA.secondary(0.5))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(line.number)
                            .font(VAFont.mono(16, .semibold))
                            .foregroundStyle(Color(hex: 0x5CC2F0))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Call \(line.number), \(line.name)")
            }
        }
        .background(RoundedRectangle(cornerRadius: 22).fill(.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
    }

    // MARK: Contacts

    @ViewBuilder private var contactsRow: some View {
        if contacts.contacts.isEmpty {
            Button {
                pickingContacts = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x5CC2F0))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color(hex: 0x3A3A3C)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Choose emergency contacts")
                            .font(VAFont.display(15, .medium))
                            .foregroundStyle(.white)
                        Text("Up to \(EmergencyContactsStore.limit) people get your \"I'm safe\" message")
                            .font(VAFont.display(12, .regular))
                            .foregroundStyle(VA.secondary(0.5))
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 20).fill(.white.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                .contentShape(RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 8) {
                ForEach(contacts.contacts) { contact in
                    contactTile(contact)
                }
                if !contacts.isFull {
                    Button {
                        pickingContacts = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x5CC2F0))
                            .frame(width: 58, height: 58)
                            .background(RoundedRectangle(cornerRadius: 20).fill(.white.opacity(0.07)))
                            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add emergency contact")
                }
            }
        }
    }

    /// Long-press to remove — there is no edit mode for a row of three.
    private func contactTile(_ contact: EmergencyContact) -> some View {
        HStack(spacing: 10) {
            Text(contact.initial)
                .font(VAFont.display(13))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color(hex: 0x3A3A3C)))
            Text(contact.name)
                .font(VAFont.display(14, .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 20).fill(.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20))
        .contextMenu {
            Button("Remove", systemImage: "minus.circle", role: .destructive) {
                contacts.remove(contact)
            }
        }
    }

    private var safeButton: some View {
        let sent = contacts.recentlySent()
        let label: String
        let hue: Color
        let text: Color
        if let sent {
            let people = String(localized: "\(sent.count) contacts")
            label = String(localized: "Sent to \(people) · \(sent.at.formatted(date: .omitted, time: .shortened))")
            hue = VA.green
            text = Color(hex: 0x7EE29A)
        } else {
            label = String(localized: "Send \"I'm safe\" + location")
            hue = VA.cyan
            text = VA.cyanText
        }

        return Button {
            sendSafe()
        } label: {
            Text(label)
                .font(VAFont.display(16))
                .foregroundStyle(text)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Capsule().fill(hue.opacity(0.2)))
                .overlay(Capsule().strokeBorder(hue.opacity(0.5), lineWidth: 0.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// With nobody chosen yet the first tap opens the picker; the message goes out on the
    /// next one. Chaining the composer straight off the picker's dismissal races UIKit's
    /// own dismiss animation.
    private func sendSafe() {
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

    private var safeMessage: String {
        guard let coordinate else { return String(localized: "I'm safe.") }
        return String(localized: "I'm safe. My location: \(coordinate.mapsLink)")
    }
}

extension CLLocationCoordinate2D {
    /// Opens in Apple Maps on an iPhone and as a web page anywhere else.
    var mapsLink: String {
        "https://maps.apple.com/?ll=" + String(format: "%.5f,%.5f", latitude, longitude)
    }
}

// MARK: - Confirm

/// The confirm card every quick-dial number goes through, over a dimmed backdrop. Shared
/// by the emergency screen and the guides; the presenter animates `line`.
struct DialConfirmOverlay: View {
    @Binding var line: EmergencyLine?
    /// Shown on the card so it can be read out to the operator.
    var coordinate: CLLocationCoordinate2D?

    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack(alignment: .bottom) {
            if let line {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { self.line = nil }
                    .transition(.opacity)
                card(line)
                    .padding(8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func card(_ line: EmergencyLine) -> some View {
        VStack(spacing: 6) {
            Text(line.number)
                .font(VAFont.rounded(52))
                .tracking(em: -0.02, size: 52)
                .foregroundStyle(.white)
            Text(line.name)
                .font(VAFont.display(15, .medium))
                .foregroundStyle(VA.secondary(0.7))

            // The design promises the address on screen *during* the call; once the dialler
            // takes over this app is not on screen, so the coordinates go here instead.
            locationNote
                .padding(.top, 6)

            VStack(spacing: 8) {
                Button {
                    self.line = nil
                    if let url = line.telURL { openURL(url) }
                } label: {
                    Text("Call \(line.number)")
                        .font(VAFont.display(17))
                        .foregroundStyle(Color(hex: 0x00210B))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            Capsule().fill(LinearGradient(
                                colors: [Color(hex: 0x48D66E, opacity: 0.95), Color(hex: 0x28B450, opacity: 0.92)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                        )
                        .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                Button {
                    self.line = nil
                } label: {
                    Text("Cancel")
                        .font(VAFont.display(16))
                        .foregroundStyle(Color(hex: 0x5CC2F0))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Capsule().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .background(RoundedRectangle(cornerRadius: 34).fill(.black.opacity(0.32)))
        .padding(8)
        .vaGlass(RoundedRectangle(cornerRadius: 42))
    }

    @ViewBuilder private var locationNote: some View {
        if let coordinate {
            VStack(spacing: 4) {
                Text(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                    .font(VAFont.mono(15, .semibold))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                Text("Your coordinates — read them out if you cannot name the address.")
                    .font(VAFont.display(12.5, .regular))
                    .foregroundStyle(VA.secondary(0.5))
                    .multilineTextAlignment(.center)
            }
        } else {
            Text("No location fix — name the nearest street or landmark.")
                .font(VAFont.display(12.5, .regular))
                .foregroundStyle(VA.secondary(0.5))
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - System pickers

/// The system contact picker. It runs out of process, so the app needs no Contacts
/// permission and only ever sees the people picked.
///
/// Presented from a zero-size host rather than returned as the representable's own
/// controller: embedded in a SwiftUI sheet the picker shows up as an empty wrapper.
struct ContactPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPick: ([CNContact]) -> Void

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard isPresented, host.presentedViewController == nil else { return }
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        host.present(picker, animated: true)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        var parent: ContactPicker

        init(parent: ContactPicker) { self.parent = parent }

        // Implementing the plural form is what turns on multiple selection.
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            parent.isPresented = false
            parent.onPick(contacts)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.isPresented = false
        }
    }
}

/// The system message composer, prefilled. Only the person can press Send.
struct MessageComposer: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var recipients: [String]
    var messageText: String
    var onFinish: (MessageComposeResult) -> Void

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard isPresented, host.presentedViewController == nil else { return }
        let composer = MFMessageComposeViewController()
        composer.messageComposeDelegate = context.coordinator
        composer.recipients = recipients
        composer.body = messageText
        host.present(composer, animated: true)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        var parent: MessageComposer

        init(parent: MessageComposer) { self.parent = parent }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true)
            parent.isPresented = false
            parent.onFinish(result)
        }
    }
}

#Preview {
    EmergencyServicesSheet(coordinate: CLLocationCoordinate2D(latitude: 50.4501, longitude: 30.5234))
        .preferredColorScheme(.dark)
}
