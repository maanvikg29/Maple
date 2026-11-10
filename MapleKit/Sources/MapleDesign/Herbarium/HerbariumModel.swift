import Foundation
import MapleCore

// The Herbarium's pure model (spec §5.3, §5.4): what each leaf is, how the 155 are grouped, sorted, filtered and
// searched, and which tiles a collapsed section shows. Views only draw what this returns, so every rule is tested.

/// One leaf as the Herbarium sees it: the species, where it stands, and how many members hold it.
nonisolated public struct HerbariumEntry: Sendable, Equatable, Identifiable {
    /// How the leaf is presented (spec §5.2).
    public enum Status: Sendable, Equatable {
        case earned(LeafUnlock)
        /// Earned, not opened yet. The species stays hidden until the reveal.
        case waiting(LeafUnlock)
        /// One of the next 3 locked rungs of an available category.
        case next
        /// A further locked rung of an available category.
        case locked
        /// The category ships but needs Apple Health, a sleep tracker or Screen Time.
        case needsPermission(LeafAvailability)
        /// The category hasn't shipped: "Not earnable yet".
        case dormant
    }

    public var id: String { species.id }
    public let species: LeafSpecies
    public let progress: LeafProgress
    /// The rung's rule, the assignment's `unlock_text` ("Fall asleep on time 14 nights").
    public let rule: String
    public let isNextRung: Bool
    /// Earned and not looked at yet: the amber dot.
    public let isUnseen: Bool
    public let share: MemberShare
    /// The number behind a fresh share ("Rarest first", "Your rarest"); nil in every other state.
    public let estimate: ShareEstimate?
    /// A waiting leaf that can be opened right now (not held, not wind-down or night).
    public let opensNow: Bool

    public init(
        species: LeafSpecies, progress: LeafProgress, rule: String, isNextRung: Bool, isUnseen: Bool = false,
        share: MemberShare, estimate: ShareEstimate? = nil, opensNow: Bool = false
    ) {
        self.species = species
        self.progress = progress
        self.rule = rule
        self.isNextRung = isNextRung
        self.isUnseen = isUnseen
        self.share = share
        self.estimate = estimate
        self.opensNow = opensNow
    }

    public var status: Status {
        switch progress.state {
        case .earned(let unlock): return .earned(unlock)
        case .waiting(let unlock): return .waiting(unlock)
        case .locked:
            switch progress.availability {
            case .available: return isNextRung ? .next : .locked
            case .dormant: return .dormant
            case .needsAppleHealth, .needsScreenTime: return .needsPermission(progress.availability)
            }
        }
    }

    /// Earned or waiting: the leaf is the member's (it shows in the Earned scope, as a leaf or a bud).
    public var isUnlocked: Bool {
        if case .locked = progress.state { false } else { true }
    }

    public var isWaiting: Bool { progress.state.isWaiting }

    /// Opened and in the collection: the only leaves "N of 155" counts (`LeafCount`).
    public var isEarned: Bool { progress.isOpened }

    public var unlock: LeafUnlock? {
        switch progress.state {
        case .earned(let unlock), .waiting(let unlock): unlock
        case .locked: nil
        }
    }

    /// Canonical rung order: category, then threshold (spec §5.1).
    var rungKey: (Int, Double) {
        (RewardCategoryInfo(progress.category).order, progress.threshold)
    }
}

/// The All / Earned / Locked chips. The Earned scope also shows leaves still waiting to be opened (as buds), but
/// its chip counts opened leaves only, like every "N of 155" (`LeafCount`).
nonisolated public enum HerbariumScope: String, Sendable, CaseIterable, Identifiable {
    case all, earned, locked

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All"
        case .earned: "Earned"
        case .locked: "Locked"
        }
    }

    public func includes(_ entry: HerbariumEntry) -> Bool {
        switch self {
        case .all: true
        case .earned: entry.isUnlocked
        case .locked: !entry.isUnlocked
        }
    }

    /// The number on the chip: "All 155", "Earned 23" (opened leaves only, never waiting ones), "Locked 131".
    public func count(in entries: [HerbariumEntry]) -> Int {
        switch self {
        case .all: entries.count
        case .earned: LeafCount(entries.map(\.progress)).opened
        case .locked: entries.filter { !$0.isUnlocked }.count
        }
    }
}

/// "Group by" in the Group menu (spec §5.4).
nonisolated public enum HerbariumGrouping: String, Sendable, CaseIterable, Identifiable {
    case category, region, autumnColour, leafForm, tier

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .category: "Category"
        case .region: "Region"
        case .autumnColour: "Autumn colour"
        case .leafForm: "Leaf form"
        case .tier: "Tier"
        }
    }
}

/// "Sort" in the Group menu (spec §5.4).
nonisolated public enum HerbariumSort: String, Sendable, CaseIterable, Identifiable {
    case nextToEarn, rarestFirst, newestFirst, alphabetical

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .nextToEarn: "Next to earn"
        case .rarestFirst: "Rarest first"
        case .newestFirst: "Newest first"
        case .alphabetical: "A–Z"
        }
    }

    /// The sorts the menu offers. "Rarest first" needs real rarity: without a single fresh share it would only
    /// repeat rung order, so it is absent until there is one (spec §1.5).
    public static func offered(hasRarity: Bool) -> [HerbariumSort] {
        hasRarity ? allCases : allCases.filter { $0 != .rarestFirst }
    }
}

/// One entry of a Herbarium VoiceOver rotor, pointing at a tile that is drawn.
nonisolated public struct HerbariumRotorEntry: Sendable, Equatable, Identifiable {
    /// The tile's rotor id (`HerbariumLayout.rotorID(section:species:)`).
    public let id: String
    public let name: String
}

nonisolated extension HerbariumLayout {
    /// A tile's rotor id. Section-qualified, because a species can sit in two sections at once (Region grouping).
    public static func rotorID(section: String, species: String) -> String {
        "\(section)/\(species)"
    }

    /// The "Earned leaves" rotor: each earned leaf among the tiles `sections` draw, once (its first tile), in
    /// screen order. Leaves a chip, a filter or a collapsed section hides are not in it.
    public static func earnedRotor(_ sections: [HerbariumSection]) -> [HerbariumRotorEntry] {
        var seen: Set<String> = []
        var rotor: [HerbariumRotorEntry] = []
        for section in sections {
            for entry in section.entries where entry.isEarned && seen.insert(entry.id).inserted {
                rotor.append(HerbariumRotorEntry(id: rotorID(section: section.id, species: entry.id), name: entry.species.displayName))
            }
        }
        return rotor
    }
}

/// The Filter sheet's choices (spec §5.4). Within a facet any choice matches; facets combine.
nonisolated public struct HerbariumFilters: Sendable, Equatable {
    public var regions: Set<LeafSpecies.Region> = []
    public var autumnColours: Set<LeafSpecies.AutumnColor> = []
    public var forms: Set<LeafSpecies.Form> = []
    public var evergreenOnly = false
    public var approximateOnly = false
    /// Locked leaves whose category can be earned on this iPhone now.
    public var earnableNowOnly = false

    public init() {}

    /// The filter circle's badge: every chosen value and toggle.
    public var activeCount: Int {
        regions.count + autumnColours.count + forms.count
            + [evergreenOnly, approximateOnly, earnableNowOnly].filter(\.self).count
    }

    public var isActive: Bool { activeCount > 0 }

    public func matches(_ entry: HerbariumEntry) -> Bool {
        let species = entry.species
        if !regions.isEmpty, regions.isDisjoint(with: species.regions) { return false }
        if !autumnColours.isEmpty, !autumnColours.contains(species.autumn) { return false }
        if !forms.isEmpty, !forms.contains(species.form) { return false }
        if evergreenOnly, !species.evergreen { return false }
        if approximateOnly, !species.confidence.isApproximate { return false }
        if earnableNowOnly, entry.isUnlocked || entry.progress.availability != .available { return false }
        return true
    }
}

/// One section of the grid, ready to draw.
nonisolated public struct HerbariumSection: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    /// "6 of 15" (opened leaves only, `LeafCount`), or "82 leaves" for the Dormant section.
    public let count: String
    public let spokenCount: String
    /// The category definition, or the Dormant line.
    public let definition: String?
    /// A 10pt colour dot before the title (Group by autumn colour).
    public let dot: LeafColor?
    /// A missing permission the whole section needs, for the header's "Needs …" line.
    public let permission: LeafAvailability?
    /// Tiles to draw, in order.
    public let entries: [HerbariumEntry]
    /// Tiles behind the expand row.
    public let hiddenCount: Int
    /// "Show 9 more" or "Show all"; nil when nothing is hidden.
    public let expandTitle: String?
}

/// Builds the Herbarium's sections (spec §5.3, §5.4). Pure.
nonisolated public enum HerbariumLayout {
    /// The id of the section every unshipped category collapses into.
    public static let dormantSectionID = "dormant"
    /// Locked tiles a collapsed section shows after its earned and waiting leaves (the next 3 rungs).
    public static let collapsedLockedCount = NextLeafPicker.nextRungsPerCategory
    /// Tiles the Dormant section shows before "Show all".
    public static let dormantPreviewCount = 6

    /// - Parameters:
    ///   - entries: All 155 leaves, in canonical order.
    ///   - expanded: Section ids the member opened with "Show more" (remembered for the session).
    public static func sections(
        _ entries: [HerbariumEntry], grouping: HerbariumGrouping = .category, sort: HerbariumSort = .nextToEarn,
        scope: HerbariumScope = .all, filters: HerbariumFilters = HerbariumFilters(), expanded: Set<String> = []
    ) -> [HerbariumSection] {
        // Filters and the Locked and Earned chips show everything; only the full, unfiltered view collapses.
        let collapses = scope == .all && !filters.isActive
        let pool = entries.filter { scope.includes($0) && filters.matches($0) }
        return groups(entries, grouping: grouping).compactMap { group in
            let ids = Set(group.members.map(\.id))
            let shown = ordered(pool.filter { ids.contains($0.id) }, sort: sort, grouping: grouping)
            guard !shown.isEmpty else { return nil }
            let visible: [HerbariumEntry]
            if !collapses || expanded.contains(group.id) {
                visible = shown
            } else if group.id == dormantSectionID {
                visible = Array(shown.prefix(dormantPreviewCount))
            } else {
                var lockedShown = 0
                visible = shown.filter { entry in
                    if entry.isUnlocked { return true }
                    lockedShown += 1
                    return lockedShown <= collapsedLockedCount
                }
            }
            let hidden = shown.count - visible.count
            let expandTitle: String? = hidden == 0 ? nil : group.id == dormantSectionID ? "Show all" : "Show \(hidden) more"
            return HerbariumSection(
                id: group.id, title: group.title, count: group.count, spokenCount: group.spokenCount,
                definition: group.definition, dot: group.dot, permission: group.permission,
                entries: visible, hiddenCount: hidden, expandTitle: expandTitle
            )
        }
    }

    /// The order of tiles inside a section.
    public static func ordered(_ entries: [HerbariumEntry], sort: HerbariumSort, grouping: HerbariumGrouping) -> [HerbariumEntry] {
        func rung(_ a: HerbariumEntry, _ b: HerbariumEntry) -> Bool { a.rungKey < b.rungKey }
        switch sort {
        case .nextToEarn:
            // A category is a ladder, so its rungs are the order; earned rungs are always the lowest.
            guard grouping != .category else { return entries.sorted(by: rung) }
            return entries.sorted { a, b in
                let ka = nextKey(a), kb = nextKey(b)
                if ka.rank != kb.rank { return ka.rank < kb.rank }
                if ka.days != kb.days { return ka.days < kb.days }
                return rung(a, b)
            }
        case .rarestFirst:
            return entries.sorted { a, b in
                switch (a.estimate?.percent, b.estimate?.percent) {
                case let (pa?, pb?): pa != pb ? pa < pb : rung(a, b)
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): rung(a, b)
                }
            }
        case .newestFirst:
            return entries.sorted { a, b in
                switch (a.unlock?.date, b.unlock?.date) {
                case let (da?, db?): da != db ? da > db : rung(a, b)
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): rung(a, b)
                }
            }
        case .alphabetical:
            // Waiting leaves come first: their names stay hidden until they open.
            return entries.sorted { a, b in
                if a.isWaiting != b.isWaiting { return a.isWaiting }
                let order = a.species.displayName.localizedStandardCompare(b.species.displayName)
                return order != .orderedSame ? order == .orderedAscending : rung(a, b)
            }
        }
    }

    /// Waiting, earned, then what can be earned soonest, then what needs a permission, then the dormant.
    private static func nextKey(_ entry: HerbariumEntry) -> (rank: Int, days: Double) {
        switch entry.status {
        case .waiting: (0, 0)
        case .earned: (1, 0)
        case .next, .locked: (2, entry.progress.estimatedDays ?? .infinity)
        case .needsPermission: (3, 0)
        case .dormant: (4, 0)
        }
    }

    // MARK: Groups

    private struct Group {
        var id: String
        var title: String
        var members: [HerbariumEntry]
        var count: String
        var spokenCount: String
        var definition: String?
        var dot: LeafColor?
        var permission: LeafAvailability?

        init(id: String, title: String, members: [HerbariumEntry], definition: String? = nil, dot: LeafColor? = nil,
             permission: LeafAvailability? = nil) {
            self.id = id
            self.title = title
            self.members = members
            let leaves = LeafCount(members.map(\.progress))
            count = leaves.text
            spokenCount = leaves.spoken
            self.definition = definition
            self.dot = dot
            self.permission = permission
        }
    }

    private static func groups(_ entries: [HerbariumEntry], grouping: HerbariumGrouping) -> [Group] {
        switch grouping {
        case .category:
            let catalog = RewardCatalog.shared
            var groups: [Group] = []
            var dormant: [HerbariumEntry] = []
            for category in catalog.categories {
                let members = entries.filter { $0.progress.category == category.id }
                guard let first = members.first else { continue }
                if first.progress.availability == .dormant {
                    dormant += members
                    continue
                }
                let permission: LeafAvailability? = first.progress.availability == .available ? nil : first.progress.availability
                groups.append(Group(id: category.id.rawValue, title: category.name, members: members,
                                    definition: category.info.definition, permission: permission))
            }
            if !dormant.isEmpty {
                var group = Group(id: dormantSectionID, title: "Dormant", members: dormant,
                                  definition: "These can't be earned in Maple yet.")
                group.count = "\(dormant.count) \(dormant.count == 1 ? "leaf" : "leaves")"
                group.spokenCount = group.count
                groups.append(group)
            }
            return groups
        case .region:
            return LeafSpecies.Region.allCases.map { region in
                Group(id: "region-\(region.rawValue)", title: region.displayName,
                      members: entries.filter { $0.species.regions.contains(region) })
            }
        case .autumnColour:
            return LeafSpecies.AutumnColor.allCases.map { colour in
                Group(id: "autumn-\(colour.rawValue)", title: colour.displayName,
                      members: entries.filter { $0.species.autumn == colour }, dot: colour.color)
            }
        case .leafForm:
            return LeafSpecies.Form.allCases.map { form in
                Group(id: "form-\(form.rawValue)", title: form.displayName, members: entries.filter { $0.species.form == form })
            }
        case .tier:
            return RewardTier.allCases.map { tier in
                Group(id: "tier-\(tier.rawValue)", title: tier.displayName, members: entries.filter { $0.progress.tier == tier })
            }
        }
    }
}

// MARK: - Search

/// The Search sheet's matching (spec §5.4): every word of the query must start a word of the common name,
/// scientific name, series or range. Case and accents are ignored.
nonisolated public enum HerbariumSearch {
    public static func matches(_ species: LeafSpecies, query: String) -> Bool {
        let terms = words(query)
        guard !terms.isEmpty else { return false }
        let haystack = words([species.common, species.name, species.series, species.range].joined(separator: " "))
        return terms.allSatisfy { term in haystack.contains { $0.hasPrefix(term) } }
    }

    /// Matching species, best first: names that match before series and range, then A–Z. Waiting leaves are left
    /// out, so a search never gives away a leaf before its reveal.
    public static func results(_ entries: [HerbariumEntry], query: String) -> [HerbariumEntry] {
        let terms = words(query)
        guard !terms.isEmpty else { return [] }
        func nameMatch(_ species: LeafSpecies) -> Bool {
            let names = words(species.common + " " + species.name)
            return terms.allSatisfy { term in names.contains { $0.hasPrefix(term) } }
        }
        return entries
            .filter { !$0.isWaiting && matches($0.species, query: query) }
            .sorted { a, b in
                let na = nameMatch(a.species), nb = nameMatch(b.species)
                if na != nb { return na }
                return a.species.displayName.localizedStandardCompare(b.species.displayName) == .orderedAscending
            }
    }

    /// Lower-cased, accent-free words, split on anything that isn't a letter or digit.
    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}

// MARK: - Names

extension LeafSpecies.AutumnColor {
    /// "Crimson", "Scarlet", "Orange", "Gold", "Stays green".
    nonisolated public var displayName: String {
        switch self {
        case .crimson: "Crimson"
        case .scarlet: "Scarlet"
        case .orange: "Orange"
        case .gold: "Gold"
        case .staysGreen: "Stays green"
        }
    }
}

extension LeafSpecies.Form {
    /// "Palmate", "Unlobed", "Three leaflets", "Pinnate", "Palmately compound".
    nonisolated public var displayName: String {
        switch self {
        case .palmate: "Palmate"
        case .unlobed: "Unlobed"
        case .trifoliate: "Three leaflets"
        case .pinnate: "Pinnate"
        case .palmcompound: "Palmately compound"
        }
    }
}
