import Foundation
import Testing
@testable import MapleCore

@Suite("Next leaf picker")
struct NextLeafPickerTests {
    private let earned = LeafState.earned(LeafUnlock(speciesID: "x", date: .distantPast, season: .autumn, colourway: .autumn, revealed: true))

    @Test("Candidates are each available category's lowest locked rung")
    func candidates() {
        let rows = [
            progressRow("a1", .bedtimeKept, threshold: 1, state: earned, estimate: nil),
            progressRow("a2", .bedtimeKept, threshold: 3, current: 1, estimate: 4),
            progressRow("a3", .bedtimeKept, threshold: 7, current: 1, estimate: 9),
            progressRow("b1", .restedNights, threshold: 1, estimate: 1.4),
            progressRow("m1", .phoneFreeMornings, threshold: 3, availability: .needsAppleHealth, estimate: nil),
            progressRow("f1", .hoursSaved, threshold: 1, availability: .dormant, estimate: nil),
        ]
        #expect(NextLeafPicker(progress: rows).candidates.map(\.speciesID) == ["a2", "b1"])
    }

    @Test("Waiting leaves are never candidates")
    func waiting() {
        let unlock = LeafUnlock(speciesID: "a1", date: .distantPast, season: .autumn, colourway: .autumn)
        let rows = [
            progressRow("a1", .restedNights, threshold: 1, state: .waiting(unlock), estimate: nil),
            progressRow("a2", .restedNights, threshold: 3, current: 1, estimate: 4),
        ]
        #expect(NextLeafPicker(progress: rows).candidates.map(\.speciesID) == ["a2"])
    }

    @Test("A pinned leaf wins while it is locked and available")
    func pinned() {
        let rows = [
            progressRow("a1", .sessionsFinished, threshold: 1, estimate: 1),
            progressRow("a2", .sessionsFinished, threshold: 3, estimate: 3),
            progressRow("w1", .focusStreak, threshold: 1, estimate: 10),
            progressRow("m1", .phoneFreeMornings, threshold: 3, availability: .needsAppleHealth, estimate: nil),
        ]
        let picker = NextLeafPicker(progress: rows)
        // Any locked, available rung can be pinned, not only a category's lowest.
        #expect(picker.next(pinned: "a2")?.speciesID == "a2")
        #expect(picker.next(pinned: "w1")?.speciesID == "w1")
        #expect(picker.next(pinned: "m1")?.speciesID == "a1")
        #expect(picker.next(pinned: "unknown")?.speciesID == "a1")
        let earnedPin = NextLeafPicker(progress: [progressRow("a1", .sessionsFinished, threshold: 1, state: earned, estimate: nil)] + rows.dropFirst())
        #expect(earnedPin.next(pinned: "a1")?.speciesID == "a2")
    }

    @Test("Ties: higher fraction, then canonical category order, then lower threshold")
    func ties() {
        let fraction = NextLeafPicker(progress: [
            progressRow("low", .sessionsFinished, threshold: 10, current: 2, estimate: 5),
            progressRow("high", .focusStreak, threshold: 10, current: 6, estimate: 5),
        ])
        #expect(fraction.next(pinned: nil)?.speciesID == "high")

        let order = NextLeafPicker(progress: [
            progressRow("later", .bedtimeKept, threshold: 3, estimate: 5),
            progressRow("earlier", .phoneFreeMornings, threshold: 3, estimate: 5),
        ])
        #expect(order.next(pinned: nil)?.speciesID == "earlier")

        // Within one category only one rung is a candidate, so the threshold tie-break shows in Almost there.
        let rungs = NextLeafPicker(progress: [
            progressRow("seven", .restedNights, threshold: 7, estimate: 5),
            progressRow("three", .restedNights, threshold: 3, estimate: 5),
        ])
        #expect(rungs.almostThere().map(\.speciesID) == ["three", "seven"])
    }

    @Test("Buds are the top 3 by estimate, with Home's pick first")
    func buds() {
        let rows = [
            progressRow("a", .restedNights, threshold: 1, estimate: 1),
            progressRow("b", .bedtimeKept, threshold: 1, estimate: 2),
            progressRow("c", .phoneFreeMornings, threshold: 3, estimate: 3),
            progressRow("d", .sessionsFinished, threshold: 1, estimate: 10),
            progressRow("e", .hoursSaved, threshold: 1, estimate: 4),
        ]
        let picker = NextLeafPicker(progress: rows)
        // The hours rung is Home's pick and takes the first place.
        #expect(picker.buds(pinned: nil).map(\.speciesID) == ["e", "a", "b"])
        #expect(picker.buds(pinned: "d").map(\.speciesID) == ["d", "a", "b"])
        #expect(NextLeafPicker(progress: Array(rows.prefix(2))).buds(pinned: nil).count == 2)
        #expect(NextLeafPicker(progress: []).buds(pinned: nil).isEmpty)
    }

    @Test("Almost there: within 60 days, up to 6, from the next 3 rungs of available categories")
    func almostThere() {
        var rows: [LeafProgress] = []
        for (index, threshold) in [1.0, 3, 7, 14].enumerated() {
            rows.append(progressRow("n\(index)", .restedNights, threshold: threshold, estimate: threshold))
        }
        rows.append(progressRow("o0", .bedtimeKept, threshold: 1, estimate: 1.5))
        rows.append(progressRow("o1", .bedtimeKept, threshold: 3, estimate: 4.5))
        rows.append(progressRow("w0", .sessionsFinished, threshold: 1, estimate: 61))
        rows.append(progressRow("m0", .phoneFreeMornings, threshold: 3, availability: .needsAppleHealth, estimate: nil))
        rows.append(progressRow("f0", .hoursSaved, threshold: 1, availability: .dormant, estimate: nil))
        let picker = NextLeafPicker(progress: rows)
        // n3 is the 4th locked rung of its category, w0 is past 60 days.
        #expect(picker.almostThere().map(\.speciesID) == ["n0", "o0", "n1", "o1", "n2"])
        #expect(picker.nextRungIDs == ["n0", "n1", "n2", "o0", "o1", "w0"])
    }

    @Test("Almost there stops at 6")
    func almostThereLimit() {
        let categories: [RewardCategoryID] = [.restedNights, .bedtimeKept, .focusStreak, .sessionsFinished]
        let rows = categories.flatMap { category in
            [1.0, 2, 3].map { progressRow("\(category.rawValue)\($0)", category, threshold: $0, estimate: $0) }
        }
        #expect(NextLeafPicker(progress: rows).almostThere().count == 6)
    }

    @Test("A new member with Apple Health is pointed at a first rung")
    func newMember() throws {
        let unlock = LeafUnlock(speciesID: "saccharum", date: at(2026, 10, 10, 9), season: .autumn, colourway: .autumn, revealed: true)
        let rows = LeafProgressBuilder(permissions: [.appleHealth], features: .current)
            .progress(counters: [.firstLeaf: 1], unlocks: [unlock], history: [], today: LocalDay(year: 2026, month: 10, day: 10), calendar: utc)
        let picker = NextLeafPicker(progress: rows)
        let next = try #require(picker.next(pinned: nil))
        #expect(next.speciesID == species(.restedNights, rung: 0))
        #expect(picker.candidates.allSatisfy { $0.availability == .available })
        // Before F1 ships, Rested nights is the only ladder that can be earned.
        #expect(picker.candidates.map(\.category) == [.restedNights])
        #expect(picker.buds(pinned: nil).map(\.speciesID) == [species(.restedNights, rung: 0)])
        #expect(picker.permissionPrompt() == nil)
    }

    @Test("Without Apple Health nothing is a candidate; Home offers the cheapest sleep leaf to turn it on for")
    func withoutAppleHealth() throws {
        let unlock = LeafUnlock(speciesID: "saccharum", date: at(2026, 10, 10, 9), season: .autumn, colourway: .autumn, revealed: true)
        let rows = LeafProgressBuilder(permissions: [], features: .current)
            .progress(counters: [.firstLeaf: 1], unlocks: [unlock], history: [], today: LocalDay(year: 2026, month: 10, day: 10), calendar: utc)
        let picker = NextLeafPicker(progress: rows)
        // D9: excluded from the next leaf, buds, Almost there and pacing.
        #expect(picker.candidates.isEmpty)
        #expect(picker.next(pinned: nil) == nil)
        #expect(picker.buds(pinned: nil).isEmpty)
        #expect(picker.almostThere().isEmpty)
        #expect(picker.nextRungIDs.isEmpty)
        #expect(rows.filter { $0.availability == .needsAppleHealth }.allSatisfy { $0.estimatedDays == nil })
        // A pinned sleep leaf can't be the next leaf either.
        #expect(picker.next(pinned: species(.restedNights, rung: 0)) == nil)

        let prompt = try #require(picker.permissionPrompt())
        #expect(prompt.speciesID == species(.restedNights, rung: 0))
        #expect(prompt.availability == .needsAppleHealth)
    }

    @Test("The permission prompt picks by design pace, only what can be turned on, and only when nothing else can be earned")
    func permissionPrompt() {
        let kept = progressRow("k1", .bedtimeKept, threshold: 1, availability: .needsAppleHealth, estimate: nil)        // 2 days
        let streak = progressRow("s1", .focusStreak, threshold: 3, availability: .needsAppleHealth, estimate: nil)      // about 3.8
        let hours = progressRow("o1", .hoursSaved, threshold: 1, availability: .needsAppleHealth, estimate: nil)        // about 0.5
        let hoursNext = progressRow("o2", .hoursSaved, threshold: 3, availability: .needsAppleHealth, estimate: nil)
        let full = progressRow("f1", .restedNights, threshold: 3, availability: .needsSleepTracker, estimate: nil)      // hardware
        let focus = progressRow("d1", .sessionsFinished, threshold: 1, availability: .dormant, estimate: nil)
        #expect(NextLeafPicker(progress: [kept, streak, hours, hoursNext, full, focus]).permissionPrompt()?.speciesID == "o1")
        // Only hardware is missing: nothing to turn on.
        #expect(NextLeafPicker(progress: [full, focus]).permissionPrompt() == nil)
        // Something can be earned: no prompt.
        let mornings = progressRow("n1", .phoneFreeMornings, threshold: 1, estimate: 1.1)
        #expect(NextLeafPicker(progress: [kept, streak, hours, mornings]).permissionPrompt() == nil)
        #expect(LeafAvailability.needsAppleHealth.canBeTurnedOn && LeafAvailability.needsScreenTime.canBeTurnedOn)
        #expect(!LeafAvailability.needsSleepTracker.canBeTurnedOn && !LeafAvailability.dormant.canBeTurnedOn)
    }

    @Test("Home's pick is the lowest hours-saved rung, ahead of anything closer")
    func hoursFirst() {
        let rows = [
            progressRow("h2", .hoursSaved, threshold: 2, current: 0.5, estimate: 0.8),
            progressRow("s1", .sessionsFinished, threshold: 1, estimate: 0.2),
            progressRow("r1", .restedNights, threshold: 3, current: 2, estimate: 0.1),
        ]
        let picker = NextLeafPicker(progress: rows)
        #expect(picker.next(pinned: nil)?.speciesID == "h2")
        #expect(picker.buds(pinned: nil).first?.speciesID == "h2")
        #expect(picker.permissionPrompt() == nil)
    }

    @Test("Before focus ships, Rested nights is Home's pick")
    func beforeFocusShips() {
        let rows = [
            progressRow("h1", .hoursSaved, threshold: 1, availability: .dormant, estimate: nil),
            progressRow("r1", .restedNights, threshold: 3, current: 1, estimate: 3),
        ]
        #expect(NextLeafPicker(progress: rows).next(pinned: nil)?.speciesID == "r1")
    }

    @Test("Once focus ships, Rested nights is never Home's pick; without Screen Time Home offers to turn it on")
    func focusWithoutScreenTime() {
        let rows = [
            progressRow("h1", .hoursSaved, threshold: 1, availability: .needsScreenTime, estimate: nil),
            progressRow("s1", .sessionsFinished, threshold: 1, availability: .needsScreenTime, estimate: nil),
            progressRow("r1", .restedNights, threshold: 3, current: 2, estimate: 1),
        ]
        let picker = NextLeafPicker(progress: rows)
        #expect(picker.next(pinned: nil) == nil)
        #expect(picker.permissionPrompt()?.speciesID == "h1")
        // Rested nights still grows on the tree and shows in Almost there.
        #expect(picker.buds(pinned: nil).map(\.speciesID) == ["r1"])
        #expect(picker.almostThere().map(\.speciesID) == ["r1"])
    }

    @Test("A pin is by species, so it survives the re-cut and still wins")
    func pinnedSurvivesRecut() {
        let rows = [
            progressRow("h1", .hoursSaved, threshold: 1, estimate: 0.5),
            progressRow("r1", .restedNights, threshold: 3, estimate: 5),
        ]
        #expect(NextLeafPicker(progress: rows).next(pinned: "r1")?.speciesID == "r1")
    }
}
