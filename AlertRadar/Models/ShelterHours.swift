//
//  ShelterHours.swift
//  AlertRadar
//
//  The register's opening hours are free text typed by hundreds of different people:
//  "Цілодобово", "пн-пт 08:00-17:00", "з 9-00 до 18-00 , п’ять днів на тиждень". This
//  reads the common shapes well enough to say "open" or "closed" right now. Anything it
//  cannot read with confidence stays unread; the raw text is on screen either way.
//

import Foundation

/// The register's `working_time`, interpreted.
nonisolated enum ShelterHours: Equatable, Sendable {
    /// "Цілодобово".
    case alwaysOpen
    /// "У разі тривоги": unlocked when the siren goes.
    case duringAlerts
    /// Under repair, or in use by the military. The register itself says not to come.
    case unavailable
    case schedule(Schedule)
    /// Missing, or worded in a way that cannot be read safely: "в робочі години закладу",
    /// "під час навчального процесу та з 21:00 до 06:00".
    case unknown

    nonisolated struct Schedule: Equatable, Sendable {
        var intervals: [Interval]
        /// ISO weekdays, 1 = Monday … 7 = Sunday. All seven when the text names none.
        var days: Set<Int>
        /// "в інший час - у разі тривоги": outside these hours it still opens on an alert.
        var alsoDuringAlerts: Bool
    }

    /// Minutes after midnight, Kyiv time. An interval that ends at or before its start
    /// runs past midnight.
    nonisolated struct Interval: Equatable, Sendable {
        var start: Int
        var end: Int

        var crossesMidnight: Bool { end <= start }

        /// The same interval as pieces of a single day.
        fileprivate var segments: [ClosedRange<Int>] {
            crossesMidnight ? [start...1440, 0...end] : [start...end]
        }
    }

    /// What to tell someone looking at the shelter at a given moment.
    nonisolated enum Status: Equatable, Sendable {
        case alwaysOpen
        case duringAlerts
        case unavailable
        /// Open by the schedule until this minute after midnight.
        case open(closesAt: Int)
        /// Closed by the schedule. Opens at `opensAt`, `daysAhead` days from today
        /// (0 = later today), on ISO `weekday`.
        case closed(opensAt: Int, daysAhead: Int, weekday: Int)
        case unknown
    }

    /// Register hours are Kyiv wall-clock time, whatever time zone the phone is in.
    static let kyivCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")
            ?? TimeZone(identifier: "Europe/Kiev")
            ?? .current
        return calendar
    }()

    init(registerText: String?) {
        guard let registerText else {
            self = .unknown
            return
        }
        let text = Self.normalised(registerText)
        // Checked first and on its own, exactly as the map pins and the widget always
        // have: "7:30 - 18:00 та у разі повітряної тривоги (цілодобово)" stays 24/7.
        if text.contains("цілодобово") {
            self = .alwaysOpen
        } else if let schedule = Schedule(normalisedText: text) {
            self = .schedule(schedule)
        } else if ["ремонт", "не функціонує", "силами оборони"].contains(where: text.contains) {
            self = .unavailable
        } else if text.contains("тривог"), Self.isOnlyFiller(text) {
            self = .duringAlerts
        } else {
            self = .unknown
        }
    }

    func status(at date: Date) -> Status {
        switch self {
        case .alwaysOpen: .alwaysOpen
        case .duringAlerts: .duringAlerts
        case .unavailable: .unavailable
        case .unknown: .unknown
        case .schedule(let schedule): schedule.status(at: date)
        }
    }

    // MARK: - Reading the text

    /// Lowercased, with every apostrophe the register uses ("п’ять", "пʼятниця") made one.
    private static func normalised(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "ʼ", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "`", with: "'")
    }

    /// "08:00-17:00", "8.00 до 17.00", "з 9-00 до 18-00", "07.00 год.-17.00 год.".
    fileprivate static let intervalPattern =
        #"(?<![\d.:])(\d{1,2})[:.\-](\d{2})\s*(?:год\.?)?\s*(?:-|–|—|до|по)\s*(\d{1,2})[:.\-](\d{2})(?!\d)"#

    /// One weekday, full or abbreviated: "понеділок", "пон.", "пн", "п'ятниця", "п'ятн.".
    fileprivate static let dayPattern =
        #"(?<![\p{L}'])(понеділ\p{L}*|пон|пн|вівтор\p{L}*|вт|серед\p{L}*|ср|четвер\p{L}*|четв|чт|п'ятниц\p{L}*|п'ятн|пт|субот\p{L}*|сб|неділ\p{L}*|нд)(?![\p{L}'])\.?"#

    /// Words that carry no condition of their own. A schedule is only trusted when,
    /// after its times and days are taken out, nothing but these is left: the moment a
    /// text says "для учнів", "крім вихідних" or "під час навчального процесу", it has a
    /// condition this code does not understand, and showing "Open" would be a guess.
    private static let filler: Set<String> = [
        "з", "із", "зі", "від", "до", "по", "та", "і", "й", "а", "також", "год",
        "щодня", "щоденно", "без", "вихідних", "працює", "відчинено", "відкрито",
        "робочі", "дні", "днів", "п'ять", "на", "тиждень",
        "в", "у", "інший", "час", "разі", "під", "тривоги", "тривога", "повітряної", "оголошення",
    ]

    fileprivate static func isOnlyFiller(_ text: String) -> Bool {
        guard !text.contains(where: \.isNumber) else { return false }
        return matches(of: #"\p{L}[\p{L}']*"#, in: text).allSatisfy { filler.contains($0.text) }
    }

    fileprivate struct Match {
        let range: Range<String.Index>
        let text: String
        let groups: [String]
    }

    fileprivate static func matches(of pattern: String, in text: String) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let groups = (1..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
            return Match(range: range, text: String(text[range]), groups: groups)
        }
    }

    /// `text` with each match blanked out, so what is left can be checked for conditions.
    fileprivate static func removing(_ matches: [Match], from text: String) -> String {
        var text = text
        for match in matches.reversed() {
            text.replaceSubrange(match.range, with: " ")
        }
        return text
    }
}

nonisolated private extension ShelterHours.Schedule {
    init?(normalisedText text: String) {
        let found = ShelterHours.matches(of: ShelterHours.intervalPattern, in: text)
        guard !found.isEmpty else { return nil }

        var intervals: [ShelterHours.Interval] = []
        for match in found {
            let numbers = match.groups.compactMap { Int($0) }
            guard numbers.count == 4,
                  let start = Self.minute(numbers[0], numbers[1]),
                  let end = Self.minute(numbers[2], numbers[3]),
                  start != end
            else { return nil }
            intervals.append(ShelterHours.Interval(start: start % 1440, end: end))
        }
        // Overlapping hours mean alternatives — "07:00-17:00 під час занять; 08:00-17:00 —
        // канікули" — and the text is not saying which one applies today.
        guard !Self.overlap(intervals) else { return nil }

        let withoutTimes = ShelterHours.removing(found, from: text)
        let dayTokens = ShelterHours.matches(of: ShelterHours.dayPattern, in: withoutTimes)
        guard let days = Self.days(dayTokens, in: withoutTimes),
              ShelterHours.isOnlyFiller(ShelterHours.removing(dayTokens, from: withoutTimes))
        else { return nil }

        self.init(intervals: intervals, days: days, alsoDuringAlerts: text.contains("тривог"))
    }

    func status(at date: Date) -> ShelterHours.Status {
        let calendar = ShelterHours.kyivCalendar
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, let hour = parts.hour, let minute = parts.minute else {
            return .unknown
        }
        // Calendar counts from Sunday = 1; the register's week starts on Monday.
        let today = (weekday + 5) % 7 + 1
        let yesterday = (today + 5) % 7 + 1
        let now = hour * 60 + minute

        for interval in intervals {
            let open = interval.crossesMidnight
                ? (days.contains(today) && now >= interval.start) || (days.contains(yesterday) && now < interval.end)
                : days.contains(today) && interval.start <= now && now < interval.end
            if open { return .open(closesAt: interval.end) }
        }
        if alsoDuringAlerts { return .duringAlerts }

        for daysAhead in 0...7 {
            let day = (today - 1 + daysAhead) % 7 + 1
            guard days.contains(day) else { continue }
            let starts = intervals.map(\.start).filter { daysAhead > 0 || $0 > now }
            if let opensAt = starts.min() {
                return .closed(opensAt: opensAt, daysAhead: daysAhead, weekday: day)
            }
        }
        return .unknown
    }

    private static func minute(_ hour: Int, _ minute: Int) -> Int? {
        guard (0...24).contains(hour), (0...59).contains(minute), hour < 24 || minute == 0 else { return nil }
        return hour * 60 + minute
    }

    private static func overlap(_ intervals: [ShelterHours.Interval]) -> Bool {
        for (index, first) in intervals.enumerated() {
            for second in intervals[(index + 1)...] {
                for a in first.segments {
                    for b in second.segments where a.lowerBound < b.upperBound && b.lowerBound < a.upperBound {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// No weekday named: every day, or Monday to Friday when the text says "робочі дні".
    /// Exactly one range of two weekdays: that range. Anything else — single days, lists,
    /// different hours per day — is beyond what one schedule can hold.
    private static func days(_ tokens: [ShelterHours.Match], in text: String) -> Set<Int>? {
        switch tokens.count {
        case 0:
            let workdays = text.range(of: #"робоч\p{L}*\s+дн|п'ять\s+днів"#, options: .regularExpression) != nil
            return workdays ? Set(1...5) : Set(1...7)
        case 2:
            let between = text[tokens[0].range.upperBound..<tokens[1].range.lowerBound]
            guard ["-", "–", "—"].contains(between.trimmingCharacters(in: .whitespaces)),
                  let first = weekday(tokens[0].groups[0]),
                  let last = weekday(tokens[1].groups[0])
            else { return nil }
            var days: Set<Int> = [first]
            var day = first
            while day != last {
                day = day % 7 + 1
                days.insert(day)
            }
            return days
        default:
            return nil
        }
    }

    private static func weekday(_ token: String) -> Int? {
        let prefixes = [["пон", "пн"], ["вів", "вт"], ["сер", "ср"], ["чет", "чт"], ["п'я", "пт"], ["суб", "сб"], ["нед", "нд"]]
        return prefixes.firstIndex { $0.contains(where: token.hasPrefix) }.map { $0 + 1 }
    }
}
