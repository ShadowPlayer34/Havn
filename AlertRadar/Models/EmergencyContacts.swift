import Contacts
import Foundation
import Observation

/// One person who gets the "I'm safe" message. Copied out of the address book at pick time
/// rather than looked up again: the app holds no Contacts permission, only what was picked.
nonisolated struct EmergencyContact: Codable, Identifiable, Equatable, Sendable {
    /// `CNContact.identifier`, so picking the same person twice does not add them twice.
    let id: String
    /// First name where there is one — the tile has room for "Олена", not a full name.
    let name: String
    let phone: String

    var initial: String { name.first.map { String($0).uppercased() } ?? "?" }

    /// Nil for a contact with no phone number; the picker greys those out, but a contact
    /// card can change between the predicate running and the tap.
    init?(_ contact: CNContact) {
        guard contact.isKeyAvailable(CNContactPhoneNumbersKey) else { return nil }
        let numbers = contact.phoneNumbers
        let mobileLabels: Set<String> = [CNLabelPhoneNumberMobile, CNLabelPhoneNumberiPhone]
        let number = numbers.first { mobileLabels.contains($0.label ?? "") } ?? numbers.first
        guard let phone = number?.value.stringValue, !phone.isEmpty else { return nil }

        let given = contact.isKeyAvailable(CNContactGivenNameKey) ? contact.givenName : ""
        let family = contact.isKeyAvailable(CNContactFamilyNameKey) ? contact.familyName : ""
        let name = given.isEmpty ? family : given

        self.id = contact.identifier
        self.name = name.isEmpty ? phone : name
        self.phone = phone
    }
}

/// The chosen contacts and when "I'm safe" last went out, kept in `UserDefaults` so they
/// survive the sheet closing and the app relaunching.
@Observable
final class EmergencyContactsStore {
    /// Matches the design's row of tiles; more than this stops fitting one line.
    static let limit = 3

    /// How long the button keeps saying "Sent" — long enough to cover one alert, short
    /// enough that the next one starts from "Send" again.
    static let sentWindow: TimeInterval = 60 * 60

    private static let contactsKey = "emergency.contacts"
    private static let sentAtKey = "emergency.safe.sent-at"
    private static let sentCountKey = "emergency.safe.sent-count"

    private(set) var contacts: [EmergencyContact]
    private(set) var lastSent: (at: Date, count: Int)?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        contacts = defaults.data(forKey: Self.contactsKey)
            .flatMap { try? JSONDecoder().decode([EmergencyContact].self, from: $0) } ?? []
        if let at = defaults.object(forKey: Self.sentAtKey) as? Date {
            lastSent = (at, defaults.integer(forKey: Self.sentCountKey))
        }
    }

    var isFull: Bool { contacts.count >= Self.limit }

    /// Picks past the limit are dropped rather than replacing anyone already chosen.
    func add(_ picked: [EmergencyContact]) {
        for contact in picked where !contacts.contains(where: { $0.id == contact.id }) {
            guard !isFull else { break }
            contacts.append(contact)
        }
        save()
    }

    func remove(_ contact: EmergencyContact) {
        contacts.removeAll { $0.id == contact.id }
        save()
    }

    func markSent(to count: Int, at date: Date = .now) {
        lastSent = (date, count)
        defaults.set(date, forKey: Self.sentAtKey)
        defaults.set(count, forKey: Self.sentCountKey)
    }

    func recentlySent(at now: Date = .now) -> (at: Date, count: Int)? {
        guard let lastSent, now.timeIntervalSince(lastSent.at) < Self.sentWindow else { return nil }
        return lastSent
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(contacts), forKey: Self.contactsKey)
    }
}
