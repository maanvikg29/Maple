import Foundation
import MapleCore
import Synchronization

/// What VoiceOver says on Home, the Tree view and the Streak sheet (spec §3.2, §4.11, §9): full words, full units,
/// one sentence per idea. Pure, so every line is unit-tested.
nonisolated public enum HomeSpeech {
    /// "Autumn, Saturday 10 October".
    public static func header(season: Season, date: Date, locale: Locale = .current, calendar: Calendar = .current) -> String {
        "\(seasonName(season)), \(HomeDateText.long(date, locale: locale, calendar: calendar))"
    }

    /// "Autumn".
    public static func seasonName(_ season: Season) -> String {
        switch season {
        case .spring: "Spring"
        case .summer: "Summer"
        case .autumn: "Autumn"
        case .winter: "Winter"
        }
    }

    /// "12-night bedtime run".
    public static func streak(nights: Int) -> String {
        "\(nights)-night bedtime run"
    }

    /// "23 of 155 leaves, young maple".
    public static func caption(stage: TreeStage, leaves: Int, total: Int) -> String {
        "\(leaves) of \(total) leaves, \(stage.displayName.lowercased())"
    }

    /// The tree's label: "Your maple. Young maple, 23 of 155 leaves, grown over 41 days."
    public static func treeLabel(stage: TreeStage, leaves: Int, total: Int, tendedDays: Int) -> String {
        var text = "Your maple. \(stage.displayName), \(leaves) of \(total) leaves"
        if tendedDays > 0 {
            text += ", grown over \(tendedDays) \(tendedDays == 1 ? "day" : "days")"
        }
        return text + "."
    }

    /// The tree's value: "Newest: Red maple. Next leaf: Paperbark maple, 9 of 14 on-time bedtimes.", plus
    /// "A new leaf is waiting.", "Grew today." and "Resting." when they apply.
    public static func treeValue(newest: String?, next: LeafProgress?, waiting: Int, grewToday: Bool, resting: Bool) -> String {
        var sentences: [String] = []
        if let newest {
            sentences.append("Newest: \(newest).")
        }
        if let next, let name = LeafCatalog.shared.species(id: next.speciesID)?.displayName {
            sentences.append("Next leaf: \(name), \(amount(next)).")
        }
        switch waiting {
        case 0: break
        case 1: sentences.append("A new leaf is waiting.")
        default: sentences.append("\(waiting) new leaves are waiting.")
        }
        if grewToday { sentences.append("Grew today.") }
        if resting { sentences.append("Resting.") }
        return sentences.joined(separator: " ")
    }

    /// The next-leaf row: "Next leaf: Red maple. 11 of 14 on-time bedtimes, 3 to go." Approximate drawings add
    /// "Approximate drawing." or "Uncharted, placeholder drawing."
    public static func nextLeaf(_ progress: LeafProgress) -> String {
        guard let species = LeafCatalog.shared.species(id: progress.speciesID) else { return "Next leaf" }
        let toGo = Int((progress.remaining - 1e-9).rounded(.up))
        var text = "Next leaf: \(species.displayName). \(amount(progress))"
        text += toGo > 0 ? ", \(toGo) to go." : "."
        if let approximate = species.confidence.approximateSpokenLabel {
            text += " " + approximate
        }
        return text
    }

    /// The needs-permission row: "Next leaf: Red maple. Needs Apple Health." Approximate drawings add their label.
    public static func needsPermission(_ progress: LeafProgress) -> String {
        guard let species = LeafCatalog.shared.species(id: progress.speciesID) else { return "Next leaf" }
        var text = "Next leaf: \(species.displayName)."
        if let line = HerbariumCopy.permissionLine(progress.availability) {
            text += " \(line)."
        }
        if let approximate = species.confidence.approximateSpokenLabel {
            text += " " + approximate
        }
        return text
    }

    /// The waiting row: "A new leaf is waiting" or "2 new leaves are waiting".
    public static func waiting(_ count: Int) -> String {
        count == 1 ? "A new leaf is waiting" : "\(count) new leaves are waiting"
    }

    /// Progress in the category's own words: "11 of 14 on-time bedtimes", "3 of 7 nights in a row".
    public static func amount(_ progress: LeafProgress) -> String {
        let current = Int(progress.current.rounded(.down))
        let threshold = Int(progress.threshold.rounded())
        if progress.category == .focusHours || progress.category == .hoursSaved {
            if progress.category == .hoursSaved { return "\(current) of \(threshold) \(threshold == 1 ? "hour" : "hours") saved" }
            return "\(current) of \(threshold) hours of focus"
        }
        return "\(current) of \(threshold) \(noun(for: progress.category, plural: threshold != 1))"
    }

    /// A tree-view rosette: "Red maple, pressed 4 October".
    public static func rosette(name: String, pressed: Date?, locale: Locale = .current, calendar: Calendar = .current) -> String {
        guard let pressed else { return name }
        return "\(name), pressed \(HomeDateText.dayMonth(pressed, locale: locale, calendar: calendar))"
    }

    /// The streak sheet's 14 nights: "Last 14 nights: 12 in your run, 1 forgiven."
    public static func runNights(_ marks: [BedtimeRunNights.Mark]) -> String {
        let inRun = marks.filter { $0 == .inRun }.count
        let forgiven = marks.filter { $0 == .forgiven }.count
        var text = "Last \(marks.count) nights: \(inRun) in your run"
        if forgiven > 0 {
            text += ", \(forgiven) forgiven"
        }
        return text + "."
    }

    private static func noun(for category: RewardCategoryID, plural: Bool) -> String {
        func s(_ singular: String, _ many: String) -> String { plural ? many : singular }
        return switch category {
        case .firstLeaf: s("step", "steps")
        case .hoursSaved: s("hour saved", "hours saved")
        case .sessionsFinished: s("finished session", "finished sessions")
        case .focusStreak: s("day in a row", "days in a row")
        case .bedtimeKept: s("bedtime kept", "bedtimes kept")
        case .restedNights: s("rested night", "rested nights")
        case .firstSteps: s("step", "steps")
        case .nightsTracked: s("night tracked", "nights tracked")
        case .onTimeBedtimes: s("on-time bedtime", "on-time bedtimes")
        case .bedtimeRun: s("night in a row", "nights in a row")
        case .steadyWeeks: s("steady week", "steady weeks")
        case .seasonsInRhythm: s("season in rhythm", "seasons in rhythm")
        case .steadyMornings: s("steady morning", "steady mornings")
        case .fullNights: s("full night", "full nights")
        case .focusHours: s("hour of focus", "hours of focus")
        case .focusDays: s("focus day", "focus days")
        case .focusWeeks: s("focus week", "focus weeks")
        case .soundWindDowns: s("wind-down with sound", "wind-downs with sound")
        case .scrollFreeWindDowns: s("scroll-free wind-down", "scroll-free wind-downs")
        case .phoneFreeMornings: s("phone-free morning", "phone-free mornings")
        case .bedtimeShieldKept: s("shield night", "shield nights")
        case .reflectionWeeks: s("reflection week", "reflection weeks")
        case .caffeineCurfew: s("caffeine curfew kept", "caffeine curfews kept")
        case .windDownRituals: s("wind-down ritual", "wind-down rituals")
        case .communityChallenges: s("community challenge", "community challenges")
        }
    }
}

/// Home's dates in the member's locale: "Sat 10 Oct" in the header, "Saturday 10 October" for VoiceOver.
nonisolated public enum HomeDateText {
    /// "Sat 10 Oct" (en-GB) or "Sat, Oct 10" (en-US).
    public static func short(_ date: Date, locale: Locale = .current, calendar: Calendar = .current) -> String {
        format(date, template: "EEEdMMM", locale: locale, calendar: calendar)
    }

    /// "Saturday 10 October".
    public static func long(_ date: Date, locale: Locale = .current, calendar: Calendar = .current) -> String {
        format(date, template: "EEEEdMMMM", locale: locale, calendar: calendar)
    }

    /// "4 October".
    public static func dayMonth(_ date: Date, locale: Locale = .current, calendar: Calendar = .current) -> String {
        format(date, template: "dMMMM", locale: locale, calendar: calendar)
    }

    /// One configured formatter per template, locale, calendar and time zone. Building one costs about 200 µs, and
    /// the Tree view labels every rosette, so they are made once and reused (formatting is thread-safe; the lock
    /// guards the table).
    private static let formatters = Mutex<[String: DateFormatter]>([:])

    private static func format(_ date: Date, template: String, locale: Locale, calendar: Calendar) -> String {
        let key = "\(template)|\(locale.identifier)|\(calendar.identifier)|\(calendar.timeZone.identifier)"
        return formatters.withLock { table in
            if let formatter = table[key] { return formatter.string(from: date) }
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            table[key] = formatter
            return formatter.string(from: date)
        }
    }
}
