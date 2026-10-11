import Foundation
import MapleCore

/// The Herbarium's words (spec §5.2–§5.7, §9), kept pure so every line is tested. Dates follow the locale.
nonisolated public struct HerbariumCopy: Sendable {
    public var locale: Locale
    public var timeZone: TimeZone

    public init(locale: Locale = .current, timeZone: TimeZone = .current) {
        self.locale = locale
        self.timeZone = timeZone
    }

    // MARK: States

    /// "Needs Apple Health", "Needs a sleep tracker", "Needs Screen Time"; nil when nothing is missing.
    public static func permissionLine(_ availability: LeafAvailability) -> String? {
        switch availability {
        case .needsAppleHealth: "Needs Apple Health"
        case .needsSleepTracker: "Needs a sleep tracker"
        case .needsScreenTime: "Needs Screen Time"
        case .available, .dormant: nil
        }
    }

    /// The capsule that asks for a missing permission; nil when there is nothing the member can turn on here.
    public static func turnOnTitle(_ availability: LeafAvailability) -> String? {
        switch availability {
        case .needsAppleHealth: "Turn on Apple Health"
        case .needsScreenTime: "Turn on Screen Time"
        case .needsSleepTracker, .available, .dormant: nil
        }
    }

    public static let notEarnableYet = "Not earnable yet"
    public static let waitingName = "A new leaf"
    public static let source = "Species list: Plants of the World Online, Royal Botanic Gardens, Kew."

    /// "Endangered · IUCN Red List, 2020", plus the sourced note when there is one; nil unless the species is
    /// threatened (Critically endangered, Endangered or Vulnerable). Focus spec §4.3.
    public static func conservationLine(_ status: LeafSpecies.Conservation?) -> String? {
        guard let status, status.category.isThreatened else { return nil }
        var parts = [status.category.displayName, "IUCN Red List, \(status.year)"]
        if let note = status.note, !note.isEmpty { parts.append(note) }
        return parts.joined(separator: " · ")
    }

    // MARK: Dates

    /// "4 Oct" (tile meta when there is no share).
    public func shortDay(_ date: Date) -> String {
        date.formatted(style.day().month(.abbreviated))
    }

    /// "4 October" (VoiceOver).
    public func spokenDay(_ date: Date) -> String {
        date.formatted(style.day().month(.wide))
    }

    /// "Pressed Saturday, October 4, 2026" in the locale's order (the status tile's first line).
    public func pressedLong(_ date: Date) -> String {
        "Pressed " + date.formatted(style.weekday(.wide).day().month(.wide).year())
    }

    /// "4 Oct 2026" (share card).
    public func pressedShort(_ date: Date) -> String {
        date.formatted(style.day().month(.abbreviated).year())
    }

    private var style: Date.FormatStyle {
        Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, timeZone: timeZone)
    }

    // MARK: Lines

    /// "Pressed in autumn" under the colourway control.
    public static func pressedIn(_ season: Season) -> String {
        "Pressed in \(season.rawValue)"
    }

    /// "For 14 on-time bedtimes · in autumn" (status tile).
    public static func earnedLine(_ progress: LeafProgress, season: Season) -> String {
        "\(RewardCategoryInfo(progress.category).earnedLine(progress.threshold)) · in \(season.rawValue)"
    }

    /// "Pressed 4 Oct 2026 · for 14 on-time bedtimes" (share card).
    public func shareCardLine(pressedOn date: Date, progress: LeafProgress) -> String {
        "Pressed \(pressedShort(date)) · \(Self.lowercasingFirst(RewardCategoryInfo(progress.category).earnedLine(progress.threshold)))"
    }

    /// "Palmate · 3 lobes · toothed".
    public static func leafDescription(_ species: LeafSpecies) -> String {
        var parts = [species.form.displayName]
        switch species.form {
        case .palmate:
            if species.lobes > 1 { parts.append("\(species.lobes) lobes") }
        case .pinnate, .palmcompound:
            if species.lobes > 1 { parts.append("\(species.lobes) leaflets") }
        case .unlobed, .trifoliate:
            break
        }
        parts.append(margin(species.margin))
        return parts.joined(separator: " · ")
    }

    public static func margin(_ margin: LeafSpecies.Margin) -> String {
        switch margin {
        case .smooth: "smooth-edged"
        case .toothed: "toothed"
        case .doubleToothed: "double-toothed"
        }
    }

    /// "9 of 14 · about 5 nights at your pace". The estimate is left out when the member has no pace yet
    /// (`rate` 0), so it never guesses from the design pace (spec §5.6).
    public static func progressLine(_ progress: LeafProgress, rate: Double) -> String {
        let amount = LeafRemainder(progress, phase: .day).amount
        guard rate > 0, progress.remaining > 0 else { return amount }
        return "\(amount) · about \(duration(days: progress.remaining / rate, category: progress.category)) at your pace"
    }

    /// A time estimate: in the category's own unit where one night, morning or evening is one day and the wait is
    /// under two months ("5 nights"), otherwise in days, weeks, months or years ("3 years", never "1015 nights").
    public static func duration(days: Double, category: RewardCategoryID) -> String {
        let whole = max(1, Int(days.rounded()))
        func count(_ number: Int, _ word: String) -> String { "\(number) \(number == 1 ? word : word + "s")" }
        if days < 60 {
            switch category {
            case .nightsTracked, .onTimeBedtimes, .bedtimeRun, .fullNights, .soundWindDowns, .bedtimeShieldKept:
                return count(whole, "night")
            case .steadyMornings, .phoneFreeMornings:
                return count(whole, "morning")
            case .scrollFreeWindDowns, .windDownRituals:
                return count(whole, "evening")
            default:
                break
            }
        }
        if days < 14 { return count(whole, "day") }
        if days < 70 { return count(max(2, Int((days / 7).rounded())), "week") }
        if days < 548 { return count(max(2, Int((days / 30.44).rounded())), "month") }
        return count(max(2, Int((days / 365.25).rounded())), "year")
    }

    /// "3 nights to go", or "Tonight" / "Today" when one more completes it (Almost-there cards).
    public static func toGo(_ remainder: LeafRemainder) -> String {
        switch remainder.text {
        case "Tonight", "Today": remainder.text
        default: "\(remainder.text) to go"
        }
    }

    static func lowercasingFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }

    static func capitalisingFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}

/// One Herbarium tile, as words and a variant (spec §5.5, §9). Pure.
nonisolated public struct LeafCellModel: Sendable, Equatable, Identifiable {
    public enum Variant: Sendable, Equatable {
        /// Level-1 tile with the specimen in its pressed colourway.
        case earned(LeafColourway)
        /// Level-1 tile with the amber bud.
        case waiting
        /// No container; a season-tint skeleton filling from the stalk in the colourway it would be pressed in now.
        case next(progress: Double, colourway: LeafColourway)
        case locked
        case needsPermission
        case dormant

        /// Earned and waiting tiles sit on a Level-1 container; locked ones sit on the black.
        public var hasContainer: Bool {
            switch self {
            case .earned, .waiting: true
            case .next, .locked, .needsPermission, .dormant: false
            }
        }

        public var specimenState: SpecimenState {
            switch self {
            case .earned: .earned
            case .waiting: .waiting
            case .next(let progress, _): .next(progress: progress)
            case .locked: .locked
            case .needsPermission: .needsPermission
            case .dormant: .dormant
            }
        }

        public var colourway: LeafColourway {
            switch self {
            case .earned(let colourway), .next(_, let colourway): colourway
            case .waiting, .locked, .needsPermission, .dormant: .autumn
            }
        }
    }

    public enum Meta: Sendable, Equatable {
        case text(String)
        /// "9 of 14" over a 2pt × 56pt tint bar.
        case amount(String, fraction: Double)

        public var text: String {
            switch self {
            case .text(let text), .amount(let text, _): text
            }
        }
    }

    public var id: String { species.id }
    public let species: LeafSpecies
    public let variant: Variant
    public let name: String
    /// Unnamed species show their scientific name in New York italic.
    public let nameIsScientific: Bool
    /// Locked tiles name the leaf in `textSecondary`.
    public let nameIsSecondary: Bool
    public let meta: Meta
    /// The 11pt "≈" in the top-left corner (confidence i or u).
    public let showsApproximateMark: Bool
    /// The 6pt amber dot in the top-right corner (earned, not looked at yet).
    public let showsUnseenDot: Bool
    public let accessibilityLabel: String
    public let accessibilityHint: String?

    /// - Parameters:
    ///   - season: Today's season: a next rung fills in the colourway it would be pressed in now.
    ///   - showsRarity: "Rarest first": every tile's meta is its share ("No rarity yet" without one).
    public init(_ entry: HerbariumEntry, season: Season, showsRarity: Bool = false, copy: HerbariumCopy = HerbariumCopy()) {
        let species = entry.species
        let progress = entry.progress
        let shares = MemberShareCopy(locale: copy.locale, timeZone: copy.timeZone)
        let info = RewardCategoryInfo(progress.category)
        self.species = species

        var spoken: [String] = []
        let fullName = species.common.isEmpty ? species.name : "\(species.common), \(species.name)"
        switch entry.status {
        case .earned(let unlock):
            variant = .earned(unlock.colourway)
            meta = .text(shares.tile(entry.share, pressedOn: unlock.date))
            spoken.append(fullName)
            spoken.append("Pressed \(copy.spokenDay(unlock.date))")
            if case .value(let display, _) = entry.share { spoken.append("\(display) of members have it") }
            if case .stale(let display, _) = entry.share { spoken.append("\(display) of members have it") }
        case .waiting:
            variant = .waiting
            meta = .text("Waiting")
            spoken.append("A new leaf is waiting")
        case .next:
            let colourway = LeafColourway.pressed(in: season, evergreen: species.evergreen)
            variant = .next(progress: progress.fraction, colourway: colourway)
            let amount = LeafRemainder(progress, phase: .day).amount
            meta = showsRarity ? .text(shares.tile(entry.share, pressedOn: nil)) : .amount(amount, fraction: progress.fraction)
            spoken += ["\(species.displayName), locked", entry.rule, amount]
        case .locked:
            variant = .locked
            meta = .text(showsRarity ? shares.tile(entry.share, pressedOn: nil) : info.shortRule(progress.threshold))
            spoken += ["\(species.displayName), locked", entry.rule]
        case .needsPermission(let availability):
            variant = .needsPermission
            let line = HerbariumCopy.permissionLine(availability) ?? ""
            meta = .text(showsRarity ? shares.tile(entry.share, pressedOn: nil) : line)
            spoken += ["\(species.displayName), locked", entry.rule, line]
        case .dormant:
            variant = .dormant
            meta = .text(HerbariumCopy.notEarnableYet)
            spoken += ["\(species.displayName), locked", entry.rule, HerbariumCopy.notEarnableYet]
        }

        let hidesSpecies = variant == .waiting
        name = hidesSpecies ? HerbariumCopy.waitingName : species.displayName
        nameIsScientific = !hidesSpecies && species.common.isEmpty
        nameIsSecondary = !variant.hasContainer
        showsApproximateMark = !hidesSpecies && species.confidence.isApproximate
        showsUnseenDot = entry.isEarned && entry.isUnseen
        if !hidesSpecies, let approximate = species.confidence.approximateSpokenLabel {
            spoken.append(approximate.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
        }
        if showsUnseenDot { spoken.append("New") }
        accessibilityLabel = spoken.filter { !$0.isEmpty }.map(Self.sentence).joined(separator: " ")
        accessibilityHint = switch variant {
        case .waiting: entry.opensNow ? "Opens the new leaf." : "Opens in the morning."
        default: nil
        }
    }

    /// Ends a fragment with a full stop, so VoiceOver pauses between them.
    private static func sentence(_ text: String) -> String {
        text.hasSuffix(".") ? text : text + "."
    }
}
