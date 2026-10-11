import Foundation
import MapleCore
import Testing
@testable import MapleDesign

// The Herbarium's pure rules (docs/design/spec.md §5.2–§5.7, §9): what each tile says, how the 155 leaves are
// grouped, sorted, filtered, searched and collapsed, and every line of copy around them.

private let utc = TimeZone(identifier: "UTC")!
private let british = Locale(identifier: "en_GB")
private let copy = HerbariumCopy(locale: british, timeZone: utc)
/// Noon UTC, Sunday 4 October 2026.
private let pressedDay = Date(timeIntervalSince1970: 1_791_115_200)
private let permissions: GrantedPermissions = [.appleHealth, .sleepTracker]

private func species(_ id: String) -> LeafSpecies {
    LeafCatalog.shared.species(id: id)!
}

private func unlock(_ id: String, colourway: LeafColourway = .autumn, date: Date = pressedDay, seen: Bool = true) -> LeafUnlock {
    LeafUnlock(speciesID: id, date: date, season: .autumn, colourway: colourway, revealed: true, seen: seen)
}

/// One leaf with the rung, tier and rule the reward table gives it.
private func entry(
    _ id: String, state: LeafState = .locked, availability: LeafAvailability? = nil, current: Double = 0,
    next: Bool = false, unseen: Bool = false, share: MemberShare = .notEnoughMembers(soFar: nil),
    estimate: ShareEstimate? = nil, days: Double? = nil, opensNow: Bool = true
) -> HerbariumEntry {
    let rung = RewardCatalog.shared.reward(forSpecies: id)!
    let available = availability ?? LeafAvailability(category: rung.categoryID, permissions: permissions, features: .current)
    let progress = LeafProgress(
        speciesID: id, category: rung.categoryID, threshold: rung.threshold, tier: rung.tier, current: current,
        availability: available, state: state, estimatedDays: days
    )
    return HerbariumEntry(species: species(id), progress: progress, rule: rung.unlockText, isNextRung: next, isUnseen: unseen,
                          share: share, estimate: estimate, opensNow: opensNow)
}

/// All 155 leaves in canonical order. `earned` are opened, `waiting` unopened; the 3 lowest locked rungs of each
/// available category are the next rungs, as `NextLeafPicker` draws them.
private func collection(earned: Set<String> = ["saccharum"], waiting: Set<String> = []) -> [HerbariumEntry] {
    let rewards = RewardCatalog.shared
    var entries: [HerbariumEntry] = []
    for category in rewards.categories {
        var lockedSeen = 0
        let availability = LeafAvailability(category: category.id, permissions: permissions, features: .current)
        for rung in rewards.rungs(in: category.id) {
            let id = rung.speciesID
            if earned.contains(id) {
                entries.append(entry(id, state: .earned(unlock(id)), current: rung.threshold))
            } else if waiting.contains(id) {
                var leaf = unlock(id, seen: false)
                leaf.revealed = false
                entries.append(entry(id, state: .waiting(leaf), current: rung.threshold))
            } else {
                let isNext = availability == .available && lockedSeen < 3
                lockedSeen += 1
                entries.append(entry(id, next: isNext, days: availability == .available ? rung.threshold : nil))
            }
        }
    }
    return entries
}

// MARK: - Entries and sections

@Suite("Herbarium layout")
struct HerbariumLayoutTests {
    @Test("A leaf's status follows its state, its category's availability and whether it is a next rung")
    func statuses() {
        #expect(entry("rubrum", state: .earned(unlock("rubrum"))).status == .earned(unlock("rubrum")))
        #expect(entry("tataricum", next: true).status == .next)
        #expect(entry("oligocarpum").status == .locked)
        #expect(entry("campestre", availability: .needsAppleHealth).status == .needsPermission(.needsAppleHealth))
        #expect(entry("griseum").status == .dormant)
        var waiting = unlock("japonicum")
        waiting.revealed = false
        let bud = entry("japonicum", state: .waiting(waiting))
        #expect(bud.status == .waiting(waiting))
        #expect(bud.isUnlocked && bud.isWaiting && !bud.isEarned)
    }

    @Test("Shipped categories get a section each, in canonical order; unshipped ones share one Dormant section")
    func categorySections() {
        let sections = HerbariumLayout.sections(collection(), expanded: Set(RewardCategoryID.allCases.map(\.rawValue) + ["dormant"]))
        let ids = sections.map(\.id)
        #expect(ids == ["first_leaf", "rested_nights", "dormant"])
        #expect(sections.reduce(0) { $0 + $1.entries.count } == 155)
        let dormant = sections.last
        #expect(dormant?.title == "Dormant")
        #expect(dormant?.count == "146 leaves")
        #expect(dormant?.definition == "These can't be earned in Maple yet.")
        let nights = sections.first { $0.id == "rested_nights" }
        #expect(nights?.title == "Rested nights")
        #expect(nights?.count == "0 of 8")
        #expect(nights?.spokenCount == "0 of 8 leaves")
        #expect(nights?.definition == RewardCategoryInfo(.restedNights).definition)
        #expect(sections.first?.count == "1 of 1")
    }

    @Test("A collapsed section shows its earned and waiting leaves, then 3 locked rungs, then Show N more")
    func collapsing() throws {
        let entries = collection(earned: ["saccharum", "saccharinum", "tataricum"], waiting: ["negundo"])
        let nights = try #require(HerbariumLayout.sections(entries).first { $0.id == "rested_nights" })
        #expect(nights.entries.map(\.id) == ["saccharinum", "tataricum", "negundo", "acuminatum", "sutchuenense", "erianthum"])
        #expect(nights.hiddenCount == 2)
        #expect(nights.expandTitle == "Show 2 more")
        // One count rule (spec §5.2): the waiting Box elder is a tile, but not part of "N of 8".
        #expect(nights.count == "2 of 8")
        #expect(nights.spokenCount == "2 of 8 leaves")

        let open = try #require(HerbariumLayout.sections(entries, expanded: ["rested_nights"]).first { $0.id == "rested_nights" })
        #expect(open.entries.count == 8)
        #expect(open.expandTitle == nil)
    }

    @Test("Dormant shows its first 6 leaves, then Show all")
    func dormantPreview() throws {
        let dormant = try #require(HerbariumLayout.sections(collection()).last)
        #expect(dormant.id == HerbariumLayout.dormantSectionID)
        #expect(dormant.entries.count == 6)
        #expect(dormant.expandTitle == "Show all")
        #expect(dormant.entries.allSatisfy { $0.status == .dormant })
    }

    @Test("Chip counts: Earned counts opened leaves only, though its scope also shows the waiting buds")
    func scopeCounts() {
        let entries = collection(earned: ["saccharum", "saccharinum"], waiting: ["tataricum"])
        #expect(HerbariumScope.all.count(in: entries) == 155)
        #expect(HerbariumScope.earned.count(in: entries) == 2)
        #expect(HerbariumScope.locked.count(in: entries) == 152)
        // The earned scope still draws the bud, so it can be opened from there.
        #expect(HerbariumLayout.sections(entries, scope: .earned).flatMap(\.entries).contains { $0.isWaiting })
        // Every section's "N of M" follows the same rule, so the sections add up to the header's N.
        let sections = HerbariumLayout.sections(entries, expanded: Set(RewardCategoryID.allCases.map(\.rawValue)))
        let counted = sections.filter { $0.id != HerbariumLayout.dormantSectionID }
            .compactMap { Int($0.count.split(separator: " ").first ?? "") }
        #expect(counted.reduce(0, +) == LeafCount(entries.map(\.progress)).opened)
        #expect(LeafCount(entries.map(\.progress)) == LeafCount(opened: 2, waiting: 1, total: 155))
    }

    @Test("Filters, the Locked chip and the Earned chip show everything they match, uncollapsed")
    func scopesAndFiltersShowEverything() {
        let entries = collection(earned: ["saccharum", "saccharinum"], waiting: ["tataricum"])
        let locked = HerbariumLayout.sections(entries, scope: .locked)
        #expect(locked.reduce(0) { $0 + $1.entries.count } == 152)
        #expect(locked.allSatisfy { $0.expandTitle == nil })
        #expect(!locked.contains { $0.id == "first_leaf" })

        let earned = HerbariumLayout.sections(entries, scope: .earned)
        #expect(earned.flatMap(\.entries).map(\.id) == ["saccharum", "saccharinum", "tataricum"])

        var filters = HerbariumFilters()
        filters.evergreenOnly = true
        let evergreens = HerbariumLayout.sections(entries, filters: filters)
        #expect(evergreens.reduce(0) { $0 + $1.entries.count } == 24)
        #expect(evergreens.allSatisfy { $0.hiddenCount == 0 })
    }

    @Test("Grouping by region lists a species under each of its regions, with owned-of-total counts")
    func regionGrouping() throws {
        let entries = collection()
        let sections = HerbariumLayout.sections(entries, grouping: .region, scope: .locked)
        let campestre = species("campestre")
        #expect(campestre.regions.count > 1)
        for region in campestre.regions {
            let section = try #require(sections.first { $0.id == "region-\(region.rawValue)" })
            #expect(section.entries.contains { $0.id == "campestre" })
            #expect(section.title == region.displayName)
        }
        let all = HerbariumLayout.sections(entries, grouping: .region, expanded: Set(LeafSpecies.Region.allCases.map { "region-\($0.rawValue)" }))
        let northAmerica = try #require(all.first { $0.id == "region-NA" })
        let total = LeafCatalog.shared.species.filter { $0.regions.contains(.northAmerica) }.count
        #expect(northAmerica.count == "1 of \(total)") // the Sugar maple
    }

    @Test("Rotors list drawn tiles only, once each, with ids that match their section's tile")
    func rotors() throws {
        let campestre = species("campestre")
        let entries = collection(earned: ["saccharum", "campestre", "rubrum"])
        // Region grouping draws a two-region species twice; the rotor lists it once, at its first tile.
        let regions = HerbariumLayout.sections(entries, grouping: .region)
        let rotor = HerbariumLayout.earnedRotor(regions)
        #expect(rotor.filter { $0.name == campestre.displayName }.count == 1)
        #expect(Set(rotor.map(\.id)).count == rotor.count)
        let first = try #require(regions.first { $0.entries.contains { $0.id == "campestre" } })
        #expect(rotor.contains { $0.id == HerbariumLayout.rotorID(section: first.id, species: "campestre") })
        // The Locked chip draws no earned tile, so the rotor is empty rather than pointing at nothing.
        #expect(HerbariumLayout.earnedRotor(HerbariumLayout.sections(entries, scope: .locked)).isEmpty)
        #expect(HerbariumLayout.earnedRotor(HerbariumLayout.sections(entries)).count == 3)
    }

    @Test("Rarest first is offered only once some leaf has rarity")
    func rarestOffered() {
        #expect(!HerbariumSort.offered(hasRarity: false).contains(.rarestFirst))
        #expect(HerbariumSort.offered(hasRarity: false) == [.nextToEarn, .newestFirst, .alphabetical])
        #expect(HerbariumSort.offered(hasRarity: true) == HerbariumSort.allCases)
    }

    @Test("Autumn-colour groups carry their colour dot; form and tier groups follow their spec order")
    func otherGroupings() {
        let entries = collection()
        let colours = HerbariumLayout.sections(entries, grouping: .autumnColour)
        #expect(colours.map(\.title) == ["Crimson", "Scarlet", "Orange", "Gold", "Stays green"])
        #expect(colours.allSatisfy { $0.dot != nil })
        let forms = HerbariumLayout.sections(entries, grouping: .leafForm)
        #expect(forms.map(\.title) == ["Palmate", "Unlobed", "Three leaflets", "Pinnate", "Palmately compound"])
        let tiers = HerbariumLayout.sections(entries, grouping: .tier)
        #expect(tiers.map(\.title) == ["First steps", "Common", "Uncommon", "Rare", "Legendary"])
        #expect(tiers.allSatisfy { $0.dot == nil && $0.definition == nil })
    }

    @Test("Next to earn: rung order in a category; elsewhere waiting, earned, soonest, needs permission, dormant")
    func nextToEarnOrder() {
        var bud = unlock("palmatum")
        bud.revealed = false
        let mixed = [
            entry("griseum"),
            entry("campestre", availability: .needsAppleHealth),
            entry("negundo", next: true, days: 40),
            entry("tataricum", next: true, days: 9),
            entry("rubrum", state: .earned(unlock("rubrum"))),
            entry("palmatum", state: .waiting(bud)),
        ]
        let ordered = HerbariumLayout.ordered(mixed, sort: .nextToEarn, grouping: .region).map(\.id)
        #expect(ordered == ["palmatum", "rubrum", "tataricum", "negundo", "campestre", "griseum"])
        let ladder = HerbariumLayout.ordered([entry("negundo"), entry("saccharinum"), entry("tataricum")], sort: .nextToEarn, grouping: .category)
        #expect(ladder.map(\.id) == ["saccharinum", "tataricum", "negundo"])
    }

    @Test("Rarest first uses fresh shares only, rarest first; leaves without one sort last")
    func rarestFirst() {
        let leaves = [
            entry("rubrum", estimate: ShareEstimate(percent: 22, lower: 21, upper: 23)),
            entry("negundo"),
            entry("amamiense", estimate: ShareEstimate(percent: 0.4, lower: 0.3, upper: 0.5)),
            entry("saccharinum", estimate: ShareEstimate(percent: 70, lower: 69, upper: 71)),
        ]
        let ordered = HerbariumLayout.ordered(leaves, sort: .rarestFirst, grouping: .category).map(\.id)
        #expect(ordered == ["amamiense", "rubrum", "saccharinum", "negundo"])
    }

    @Test("Newest first puts the latest unlocks first, then locked leaves in rung order")
    func newestFirst() {
        let older = unlock("rubrum", date: pressedDay.addingTimeInterval(-86_400 * 30))
        let leaves = [entry("negundo"), entry("rubrum", state: .earned(older)), entry("palmatum", state: .earned(unlock("palmatum")))]
        let ordered = HerbariumLayout.ordered(leaves, sort: .newestFirst, grouping: .tier).map(\.id)
        #expect(ordered == ["palmatum", "rubrum", "negundo"])
    }

    @Test("A–Z sorts by display name, keeping waiting leaves (whose names are hidden) first")
    func alphabetical() {
        var bud = unlock("rubrum")
        bud.revealed = false
        let leaves = [entry("negundo"), entry("zarei"), entry("amamiense"), entry("rubrum", state: .waiting(bud))]
        let ordered = HerbariumLayout.ordered(leaves, sort: .alphabetical, grouping: .category).map(\.id)
        #expect(ordered == ["rubrum", "zarei", "amamiense", "negundo"]) // "Acer zarei" < "Amami maple" < "Box elder"
    }

    @Test("Filters combine facets, match any value within a facet and count every choice")
    func filters() {
        var filters = HerbariumFilters()
        #expect(!filters.isActive)
        #expect(filters.matches(entry("rubrum")))

        filters.regions = [.europe, .northAmerica]
        #expect(filters.matches(entry("rubrum")))     // North America
        #expect(filters.matches(entry("campestre")))  // Europe
        #expect(!filters.matches(entry("palmatum")))  // East Asia

        filters.autumnColours = [.scarlet]
        #expect(filters.matches(entry("rubrum")))
        #expect(!filters.matches(entry("campestre")))  // gold
        #expect(filters.activeCount == 3)

        var approximate = HerbariumFilters()
        approximate.approximateOnly = true
        #expect(approximate.matches(entry("zarei")))
        #expect(!approximate.matches(entry("rubrum")))

        var earnable = HerbariumFilters()
        earnable.earnableNowOnly = true
        #expect(earnable.matches(entry("negundo")))
        #expect(!earnable.matches(entry("griseum")))                                 // dormant
        #expect(!earnable.matches(entry("campestre", availability: .needsAppleHealth)))
        #expect(!earnable.matches(entry("rubrum", state: .earned(unlock("rubrum")))))
        #expect(earnable.activeCount == 1)
    }
}

// MARK: - Search

@Suite("Herbarium search")
struct HerbariumSearchTests {
    @Test("Every query word must start a word of the common name, scientific name, series or range")
    func matching() {
        let rubrum = species("rubrum")
        #expect(HerbariumSearch.matches(rubrum, query: "red"))
        #expect(HerbariumSearch.matches(rubrum, query: "RUBRUM"))
        #expect(HerbariumSearch.matches(rubrum, query: "acer rub"))
        #expect(HerbariumSearch.matches(rubrum, query: rubrum.series))
        #expect(!HerbariumSearch.matches(rubrum, query: "ubrum"))
        #expect(!HerbariumSearch.matches(rubrum, query: "red japan"))
        #expect(!HerbariumSearch.matches(rubrum, query: "   "))
        // Range words, ignoring accents: "Amami Ōshima, Japan".
        #expect(HerbariumSearch.matches(species("amamiense"), query: "oshima"))
        #expect(HerbariumSearch.matches(species("amamiense"), query: "japan"))
    }

    @Test("Results put name matches first, A–Z, and never give away a waiting leaf")
    func results() {
        var bud = unlock("palmatum")
        bud.revealed = false
        let entries = collection().map { $0.id == "palmatum" ? entry("palmatum", state: .waiting(bud)) : $0 }
        let japan = HerbariumSearch.results(entries, query: "japan")
        #expect(!japan.contains { $0.id == "palmatum" })
        let firstRangeOnly = japan.firstIndex { !HerbariumSearch.matches(names: $0.species, query: "japan") } ?? japan.count
        #expect(japan.prefix(firstRangeOnly).allSatisfy { HerbariumSearch.matches(names: $0.species, query: "japan") })
        #expect(japan.contains { $0.id == "pycnanthum" })  // Japanese red maple
        #expect(HerbariumSearch.results(entries, query: "").isEmpty)
    }
}

private extension HerbariumSearch {
    static func matches(names species: LeafSpecies, query: String) -> Bool {
        let names = words(species.common + " " + species.name)
        return words(query).allSatisfy { term in names.contains { $0.hasPrefix(term) } }
    }
}

// MARK: - Tiles

@Suite("Leaf cells")
struct LeafCellModelTests {
    @Test("An earned tile shows the share when there is one, otherwise the pressed date")
    func earned() {
        let withShare = LeafCellModel(entry("rubrum", state: .earned(unlock("rubrum")), share: .value(display: "22%", asOf: pressedDay)),
                                      season: .autumn, copy: copy)
        #expect(withShare.variant == .earned(.autumn))
        #expect(withShare.meta == .text("22% have it"))
        #expect(withShare.name == "Red maple")
        #expect(!withShare.nameIsScientific && !withShare.nameIsSecondary)
        #expect(withShare.accessibilityLabel == "Red maple, Acer rubrum. Pressed 4 October. 22% of members have it.")

        let dated = LeafCellModel(entry("rubrum", state: .earned(unlock("rubrum"))), season: .autumn, copy: copy)
        #expect(dated.meta == .text("4 Oct"))
        #expect(dated.accessibilityLabel == "Red maple, Acer rubrum. Pressed 4 October.")
    }

    @Test("Only an earned leaf not looked at yet gets the amber dot")
    func unseenDot() {
        #expect(LeafCellModel(entry("rubrum", state: .earned(unlock("rubrum", seen: false)), unseen: true), season: .autumn).showsUnseenDot)
        #expect(!LeafCellModel(entry("rubrum", state: .earned(unlock("rubrum"))), season: .autumn).showsUnseenDot)
        #expect(!LeafCellModel(entry("negundo", unseen: true), season: .autumn).showsUnseenDot)
    }

    @Test("A waiting tile is a bud that keeps the species secret")
    func waiting() {
        var bud = unlock("zarei", seen: false)
        bud.revealed = false
        let model = LeafCellModel(entry("zarei", state: .waiting(bud)), season: .autumn, copy: copy)
        #expect(model.variant == .waiting)
        #expect(model.name == "A new leaf")
        #expect(model.meta == .text("Waiting"))
        #expect(!model.showsApproximateMark)
        #expect(!model.accessibilityLabel.contains("zarei"))
        #expect(model.accessibilityHint == "Opens the new leaf.")
        let held = LeafCellModel(entry("zarei", state: .waiting(bud), opensNow: false), season: .autumn)
        #expect(held.accessibilityHint == "Opens in the morning.")
    }

    @Test("A next rung fills in the colourway it would be pressed in now and shows its amount and bar")
    func next() {
        let model = LeafCellModel(entry("tataricum", current: 9, next: true), season: .winter, copy: copy)
        #expect(model.variant == .next(progress: 9.0 / 14, colourway: .frost))
        #expect(model.meta == .amount("9 of 14", fraction: 9.0 / 14))
        #expect(model.nameIsSecondary)
        #expect(model.accessibilityLabel == "Tatar maple, locked. 14 rested nights. 9 of 14.")
        // Evergreens are always pressed green.
        let evergreen = LeafCellModel(entry("oligocarpum", next: true), season: .winter)
        #expect(evergreen.variant == .next(progress: 0, colourway: .summer))
    }

    @Test("Locked, needs-permission and dormant tiles say what they need")
    func locked() {
        #expect(LeafCellModel(entry("oligocarpum"), season: .autumn).meta == .text("365 rested"))
        let health = LeafCellModel(entry("campestre", availability: .needsAppleHealth), season: .autumn)
        #expect(health.variant == .needsPermission)
        #expect(health.meta == .text("Needs Apple Health"))
        #expect(health.accessibilityLabel.hasSuffix("Needs Apple Health."))
        #expect(LeafCellModel(entry("pseudoplatanus", availability: .needsSleepTracker), season: .autumn).meta == .text("Needs a sleep tracker"))
        let dormant = LeafCellModel(entry("griseum", share: .notEarnableYet), season: .autumn)
        #expect(dormant.variant == .dormant)
        #expect(dormant.meta == .text("Not earnable yet"))
    }

    @Test("Approximate drawings carry the ≈ mark and say so to VoiceOver; unnamed species use their scientific name")
    func approximate() {
        let uncharted = LeafCellModel(entry("zarei"), season: .autumn)
        #expect(uncharted.showsApproximateMark)
        #expect(uncharted.nameIsScientific)
        #expect(uncharted.name == "Acer zarei")
        #expect(uncharted.accessibilityLabel.hasSuffix("Uncharted, placeholder drawing."))
        let inferred = LeafCellModel(entry("binzayedii"), season: .autumn)
        #expect(inferred.accessibilityLabel.hasSuffix("Approximate drawing."))
        #expect(!LeafCellModel(entry("rubrum"), season: .autumn).showsApproximateMark)
    }

    @Test("Rarest first shows every tile's share, or No rarity yet")
    func rarityMeta() {
        let locked = LeafCellModel(entry("negundo", next: true, share: .value(display: "31%", asOf: pressedDay)),
                                   season: .autumn, showsRarity: true)
        #expect(locked.meta == .text("31% have it"))
        #expect(LeafCellModel(entry("negundo"), season: .autumn, showsRarity: true).meta == .text("No rarity yet"))
    }

    @Test("Only earned and waiting tiles sit on a container")
    func containers() {
        #expect(LeafCellModel.Variant.earned(.autumn).hasContainer)
        #expect(LeafCellModel.Variant.waiting.hasContainer)
        #expect(!LeafCellModel.Variant.next(progress: 0.5, colourway: .autumn).hasContainer)
        #expect(!LeafCellModel.Variant.dormant.hasContainer)
    }
}

// MARK: - Copy

@Suite("Herbarium copy")
struct HerbariumCopyTests {
    @Test("Leaf detail names a threatened status with its source year; others say nothing")
    func conservationLine() {
        let endangered = LeafSpecies.Conservation(category: .en, year: 2020, source: "https://example.org", note: nil)
        #expect(HerbariumCopy.conservationLine(endangered) == "Endangered · IUCN Red List, 2020")
        let noted = LeafSpecies.Conservation(category: .cr, year: 2019, source: "https://example.org", note: "Fewer than 50 wild trees")
        #expect(HerbariumCopy.conservationLine(noted) == "Critically endangered · IUCN Red List, 2019 · Fewer than 50 wild trees")
        let common = LeafSpecies.Conservation(category: .lc, year: 2020, source: "https://example.org", note: nil)
        #expect(HerbariumCopy.conservationLine(common) == nil)
        #expect(HerbariumCopy.conservationLine(nil) == nil)
    }

    @Test("Leaf descriptions name the form, its lobes or leaflets, and the margin")
    func leafDescriptions() {
        #expect(HerbariumCopy.leafDescription(species("amamiense")) == "Palmate · 5 lobes · toothed")
        #expect(HerbariumCopy.leafDescription(species("griseum")) == "Three leaflets · toothed")
        let unlobed = LeafCatalog.shared.species.first { $0.form == .unlobed && $0.margin == .smooth }
        #expect(unlobed.map(HerbariumCopy.leafDescription) == "Unlobed · smooth-edged")
    }

    @Test("Estimates use nights or mornings for short waits, and days, weeks, months or years otherwise")
    func durations() {
        #expect(HerbariumCopy.duration(days: 5.2, category: .restedNights) == "5 nights")
        #expect(HerbariumCopy.duration(days: 0.4, category: .bedtimeKept) == "1 night")
        #expect(HerbariumCopy.duration(days: 12, category: .phoneFreeMornings) == "12 mornings")
        #expect(HerbariumCopy.duration(days: 9, category: .hoursSaved) == "9 days")
        #expect(HerbariumCopy.duration(days: 35, category: .sessionsFinished) == "5 weeks")
        #expect(HerbariumCopy.duration(days: 40, category: .focusStreak) == "40 days")
        #expect(HerbariumCopy.duration(days: 272, category: .restedNights) == "9 months")
        #expect(HerbariumCopy.duration(days: 1015, category: .restedNights) == "3 years")
    }

    @Test("The progress line adds the estimate only when the member has a pace")
    func progressLine() {
        let leaf = entry("tataricum", current: 9).progress
        #expect(HerbariumCopy.progressLine(leaf, rate: 0) == "9 of 14")
        #expect(HerbariumCopy.progressLine(leaf, rate: 1) == "9 of 14 · about 5 nights at your pace")
    }

    @Test("Almost-there remainders read “to go”, except Tonight and Today")
    func toGo() {
        let leaf = entry("tataricum", current: 11).progress
        #expect(HerbariumCopy.toGo(LeafRemainder(leaf, phase: .day)) == "3 nights to go")
        let last = entry("tataricum", current: 13).progress
        #expect(HerbariumCopy.toGo(LeafRemainder(last, phase: .evening)) == "Tonight")
    }

    @Test("Dates and earned lines for the status tile and share card")
    func pressedLines() {
        // The date's own punctuation follows the locale's data.
        let pressed = copy.pressedLong(pressedDay)
        #expect(pressed.hasPrefix("Pressed Sunday"))
        #expect(["4 October", "2026"].allSatisfy(pressed.contains))
        #expect(copy.shortDay(pressedDay) == "4 Oct")
        let leaf = entry("tataricum").progress
        #expect(HerbariumCopy.earnedLine(leaf, season: .autumn) == "For 14 rested nights · in autumn")
        #expect(copy.shareCardLine(pressedOn: pressedDay, progress: leaf) == "Pressed 4 Oct 2026 · for 14 rested nights")
        #expect(HerbariumCopy.pressedIn(.winter) == "Pressed in winter")
    }

    @Test("Permission lines, and a Turn on capsule only for what the member can turn on")
    func permissions() {
        #expect(HerbariumCopy.permissionLine(.needsScreenTime) == "Needs Screen Time")
        #expect(HerbariumCopy.permissionLine(.available) == nil)
        #expect(HerbariumCopy.turnOnTitle(.needsAppleHealth) == "Turn on Apple Health")
        #expect(HerbariumCopy.turnOnTitle(.needsSleepTracker) == nil)
        #expect(HerbariumCopy.turnOnTitle(.dormant) == nil)
    }
}

// MARK: - Rarity explainer

@Suite("Rarity explainer")
struct RarityExplainerTests {
    /// Monday 28 September 2026, 00:00 UTC.
    private let week = Date(timeIntervalSince1970: 1_790_553_600)

    @Test("With a value, it leads with the members counted and the week they describe")
    func value() {
        let explainer = RarityExplainer(share: .value(display: "22%", asOf: pressedDay), memberCount: 12_400, weekStart: week,
                                        included: true, locale: british, timeZone: utc)
        #expect(explainer.figure == .members("12,400"))
        #expect(explainer.lead.hasPrefix("members shared their leaves in the week of 28 Sep"))
        #expect(explainer.updated == nil)
        #expect(explainer.consent == "Your leaves are counted.")
        #expect(explainer.paragraphs.contains { $0.contains("Under 1%") })
        #expect(explainer.paragraphs.contains("Only which leaves you hold is ever shared, never sleep, health or screen data."))
    }

    @Test("A stale value says when it was last updated")
    func stale() {
        let explainer = RarityExplainer(share: .stale(display: "22%", asOf: pressedDay), memberCount: 12_400, weekStart: nil,
                                        included: false, locale: british, timeZone: utc)
        #expect(explainer.updated == "Last updated 4 Oct")
        #expect(explainer.lead == "members share their leaves")
        #expect(explainer.consent == "Your leaves aren't counted. Rarity looks the same either way.")
    }

    @Test("Below 1,000 members it shows the progress toward them, or just the threshold")
    func notEnoughMembers() {
        let counted = RarityExplainer(share: .notEnoughMembers(soFar: 640), memberCount: nil, weekStart: nil, included: false,
                                      locale: british, timeZone: utc)
        #expect(counted.figure == .progress(soFar: "640", threshold: "1,000", fraction: 0.64))
        #expect(counted.lead == "Rarity appears once 1,000 members share their leaves.")
        let unknown = RarityExplainer(share: .notEnoughMembers(soFar: nil), memberCount: nil, weekStart: nil, included: false,
                                      locale: british, timeZone: utc)
        #expect(unknown.figure == nil)
        #expect(unknown.lead == counted.lead)
    }

    @Test("Offline, new and unshipped leaves each get their own honest line")
    func otherStates() {
        func lead(_ share: MemberShare) -> String {
            RarityExplainer(share: share, memberCount: nil, weekStart: nil, included: false, locale: british, timeZone: utc).lead
        }
        #expect(lead(.neverFetched) == "Rarity shows when you're online.")
        #expect(lead(.newSpecies) == "This leaf is new to Maple. Its rarity appears next week.")
        #expect(lead(.notEarnableYet) == "This leaf can't be earned in Maple yet.")
        #expect(!lead(.loading).isEmpty)
    }
}
