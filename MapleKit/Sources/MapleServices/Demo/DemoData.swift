#if DEBUG
import Foundation
import MapleCore

/// DEBUG only: deterministic, plausible collections for screenshots and previews (`-MapleDemoSpecies`,
/// `-MapleDemoDays`, `-MapleDemoWaiting`). Demo collections live in memory and never replace the member's file.
nonisolated public enum DemoData {
    /// Every demo collection grows the same tree.
    public static let profileID = UUID(uuidString: "6D61706C-6500-4D41-504C-450000000001")!
    public static let defaultSpecies = 23
    public static let defaultDays = 41
    /// Permissions a demo collection assumes unless `-MapleDemoPermissions` says otherwise.
    public static let defaultPermissions: GrantedPermissions = [.appleHealth, .sleepTracker]

    /// A collection of `species` leaves earned over `tendedDays` days, ending yesterday.
    ///
    /// - The cheapest rungs (threshold ÷ design pace) come first, from categories that are shipped and available
    ///   with `permissions`, so ladders fill from the bottom and counters match them; other categories fill only
    ///   after those run out. The Sugar maple (the first leaf) is always there.
    /// - Counters sit part-way to each category's next rung, so next-leaf bars show progress.
    /// - Unlock dates spread over about 1.6 × `tendedDays`, at noon, so pressed colourways mix seasons.
    /// - The `waiting` newest leaves are unopened and can be opened in morning, day and evening.
    public static func snapshot(
        species count: Int, tendedDays days: Int, waiting: Int, now: Date, calendar: Calendar = .current,
        hemisphere: Hemisphere = .current, permissions: GrantedPermissions = defaultPermissions,
        features: ShippedFeatures = .current
    ) -> CollectionSnapshot {
        let rewards = RewardCatalog.shared
        let total = min(max(0, count), rewards.assignments.count)
        let today = LocalDay(now, calendar: calendar)
        let span = max(Int((Double(max(0, days)) * 1.6).rounded()), days + 1, total + 1, 2)
        let start = today.adding(days: -span, calendar: calendar)
        var snapshot = CollectionSnapshot.empty(profileID: profileID, createdAt: noon(of: start, calendar: calendar))
        guard total > 0 else { return snapshot }

        // Choose rungs: available categories first, each in order of cost.
        func isAvailable(_ category: RewardCategoryID) -> Bool {
            LeafAvailability(category: category, permissions: permissions, features: features) == .available
        }
        func cost(_ rung: RewardAssignment) -> Double {
            rung.categoryID == .firstLeaf ? 0 : rung.threshold / RewardCategoryInfo(rung.categoryID).designPace
        }
        let ranked = rewards.assignments.sorted { a, b in
            let pa = isAvailable(a.categoryID) ? 0 : 1, pb = isAvailable(b.categoryID) ? 0 : 1
            if pa != pb { return pa < pb }
            if cost(a) != cost(b) { return cost(a) < cost(b) }
            let oa = RewardCategoryInfo(a.categoryID).order, ob = RewardCategoryInfo(b.categoryID).order
            return oa != ob ? oa < ob : a.threshold < b.threshold
        }
        let chosen = Array(ranked.prefix(total))
        let maxCost = max(1, chosen.map(cost).max() ?? 1)

        // Unlocks, dated by cost across the span (the newest yesterday).
        let species = LeafCatalog.shared
        var unlocks = chosen.map { rung -> LeafUnlock in
            let dayIndex = Int((cost(rung) / maxCost * Double(span - 1)).rounded())
            let date = noon(of: start.adding(days: dayIndex, calendar: calendar), calendar: calendar)
            let season = Season(for: date, hemisphere: hemisphere, calendar: calendar)
            let evergreen = species.species(id: rung.speciesID)?.evergreen ?? false
            return LeafUnlock(speciesID: rung.speciesID, date: date, season: season,
                              colourway: LeafColourway.pressed(in: season, evergreen: evergreen), revealed: true, seen: true)
        }
        unlocks = unlocks.enumerated().sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }.map(\.element)
        let waitingCount = min(max(0, waiting), total - 1)
        for index in unlocks.indices.suffix(waitingCount) {
            unlocks[index].revealed = false
            unlocks[index].seen = false
        }
        if let newest = unlocks.lastIndex(where: \.revealed), newest > 0 {
            unlocks[newest].seen = false
        }
        snapshot.unlocks = unlocks
        snapshot.revealedAt = Dictionary(uniqueKeysWithValues: unlocks.filter(\.revealed).map { ($0.speciesID, $0.date.addingTimeInterval(30 * 60)) })
        snapshot.revealsOpened = total - waitingCount

        // Counters: each category part-way from its top earned rung to the next.
        var counters: [RewardCategoryID: Double] = [:]
        let earnedIDs = Set(chosen.map(\.speciesID))
        for category in rewards.categories {
            let rungs = rewards.rungs(in: category.id)
            let earned = rungs.filter { earnedIDs.contains($0.speciesID) }
            let floor = earned.last?.threshold ?? 0
            guard let next = rungs.dropFirst(earned.count).first?.threshold else {
                if floor > 0 { counters[category.id] = floor }
                continue
            }
            guard !earned.isEmpty || isAvailable(category.id) else { continue }
            let gap = next - floor
            let value = floor + (gap >= 2 ? max(1, (gap * (earned.isEmpty ? 0.45 : 0.55)).rounded(.down)) : 0)
            if value > 0 { counters[category.id] = min(value, next - 1) }
        }
        snapshot.counters = counters

        // History: a baseline 14 days ago and today's closing counters, so the pace matches the span.
        let fraction = 1 - Double(LeafPace.window) / Double(span)
        let baseline = counters.mapValues { ($0 * fraction).rounded(.down) }
        snapshot.history = [
            DailyCounters(day: today.adding(days: -LeafPace.window, calendar: calendar), counters: baseline),
            DailyCounters(day: today, counters: counters),
        ]

        // Tended days spread over the span, ending today.
        let tended = max(0, days)
        snapshot.tendedDays = tended == 0 ? [] : (0..<tended).map { index in
            let offset = tended == 1 ? 0 : Int((Double(index) * Double(span - 1) / Double(tended - 1)).rounded())
            return today.adding(days: -offset, calendar: calendar)
        }.sorted()

        // A good week: on time 6 of 7, full nights 5 of 7 when Apple Health is on.
        let onTime = [true, true, false, true, true, true, true]
        let full = [true, false, true, true, false, true, true]
        snapshot.recentNights = (0..<7).map { index in
            NightRecord(day: today.adding(days: index - 7, calendar: calendar), onTime: onTime[index],
                        fullNight: permissions.contains(.sleepTracker) ? full[index] : nil, scrollFree: nil)
        }
        return snapshot
    }

    private static func noon(of day: LocalDay, calendar: Calendar) -> Date {
        calendar.date(byAdding: .hour, value: 12, to: day.startDate(in: calendar)) ?? day.startDate(in: calendar)
    }
}
#endif
