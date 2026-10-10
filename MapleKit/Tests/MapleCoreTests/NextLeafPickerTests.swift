import Foundation
import Testing
@testable import MapleCore

@Suite("Next leaf picker")
struct NextLeafPickerTests {
    private let earned = LeafState.earned(LeafUnlock(speciesID: "x", date: .distantPast, season: .autumn, colourway: .autumn, revealed: true))

    @Test("Candidates are each available category's lowest locked rung")
    func candidates() {
        let rows = [
            progressRow("a1", .nightsTracked, threshold: 1, state: earned, estimate: nil),
            progressRow("a2", .nightsTracked, threshold: 3, current: 1, estimate: 4),
            progressRow("a3", .nightsTracked, threshold: 7, current: 1, estimate: 9),
            progressRow("b1", .onTimeBedtimes, threshold: 1, estimate: 1.4),
            progressRow("m1", .steadyMornings, threshold: 3, availability: .needsAppleHealth, estimate: nil),
            progressRow("f1", .focusDays, threshold: 1, availability: .dormant, estimate: nil),
        ]
        #expect(NextLeafPicker(progress: rows).candidates.map(\.speciesID) == ["a2", "b1"])
    }

    @Test("Waiting leaves are never candidates")
    func waiting() {
        let unlock = LeafUnlock(speciesID: "a1", date: .distantPast, season: .autumn, colourway: .autumn)
        let rows = [
            progressRow("a1", .nightsTracked, threshold: 1, state: .waiting(unlock), estimate: nil),
            progressRow("a2", .nightsTracked, threshold: 3, current: 1, estimate: 4),
        ]
        #expect(NextLeafPicker(progress: rows).candidates.map(\.speciesID) == ["a2"])
    }

    @Test("A pinned leaf wins while it is locked and available")
    func pinned() {
        let rows = [
            progressRow("a1", .nightsTracked, threshold: 1, estimate: 1),
            progressRow("a2", .nightsTracked, threshold: 3, estimate: 3),
            progressRow("w1", .steadyWeeks, threshold: 1, estimate: 10),
            progressRow("m1", .steadyMornings, threshold: 3, availability: .needsAppleHealth, estimate: nil),
        ]
        let picker = NextLeafPicker(progress: rows)
        // Any locked, available rung can be pinned, not only a category's lowest.
        #expect(picker.next(phase: .day, pinned: "a2")?.speciesID == "a2")
        #expect(picker.next(phase: .day, pinned: "w1")?.speciesID == "w1")
        #expect(picker.next(phase: .day, pinned: "m1")?.speciesID == "a1")
        #expect(picker.next(phase: .day, pinned: "unknown")?.speciesID == "a1")
        let earnedPin = NextLeafPicker(progress: [progressRow("a1", .nightsTracked, threshold: 1, state: earned, estimate: nil)] + rows.dropFirst())
        #expect(earnedPin.next(phase: .day, pinned: "a1")?.speciesID == "a2")
    }

    @Test("The phase's own leaves win within 7 days; otherwise the global minimum")
    func phasePreference() {
        let rows = [
            progressRow("night", .onTimeBedtimes, threshold: 3, estimate: 6),
            progressRow("day", .focusDays, threshold: 1, estimate: 2),
            progressRow("morning", .steadyMornings, threshold: 3, estimate: 7),
            progressRow("week", .steadyWeeks, threshold: 1, estimate: 1),
        ]
        let picker = NextLeafPicker(progress: rows)
        #expect(picker.next(phase: .evening, pinned: nil)?.speciesID == "week")      // steady weeks is a night category too
        #expect(picker.next(phase: .day, pinned: nil)?.speciesID == "day")
        #expect(picker.next(phase: .morning, pinned: nil)?.speciesID == "morning")

        let far = [
            progressRow("night", .onTimeBedtimes, threshold: 3, estimate: 7.5),
            progressRow("day", .focusDays, threshold: 1, estimate: 2),
        ]
        let farPicker = NextLeafPicker(progress: far)
        #expect(farPicker.next(phase: .night, pinned: nil)?.speciesID == "day")
        #expect(farPicker.next(phase: .windDown, pinned: nil)?.speciesID == "day")
        #expect(farPicker.next(phase: .morning, pinned: nil)?.speciesID == "day")
    }

    @Test("Ties: higher fraction, then canonical category order, then lower threshold")
    func ties() {
        let fraction = NextLeafPicker(progress: [
            progressRow("low", .nightsTracked, threshold: 10, current: 2, estimate: 5),
            progressRow("high", .onTimeBedtimes, threshold: 10, current: 6, estimate: 5),
        ])
        #expect(fraction.next(phase: .day, pinned: nil)?.speciesID == "high")

        let order = NextLeafPicker(progress: [
            progressRow("later", .bedtimeRun, threshold: 3, estimate: 5),
            progressRow("earlier", .nightsTracked, threshold: 3, estimate: 5),
        ])
        #expect(order.next(phase: .day, pinned: nil)?.speciesID == "earlier")

        // Within one category only one rung is a candidate, so the threshold tie-break shows in Almost there.
        let rungs = NextLeafPicker(progress: [
            progressRow("seven", .nightsTracked, threshold: 7, estimate: 5),
            progressRow("three", .nightsTracked, threshold: 3, estimate: 5),
        ])
        #expect(rungs.almostThere().map(\.speciesID) == ["three", "seven"])
    }

    @Test("Buds are the top 3 by estimate, with Home's pick first")
    func buds() {
        let rows = [
            progressRow("a", .nightsTracked, threshold: 1, estimate: 1),
            progressRow("b", .onTimeBedtimes, threshold: 1, estimate: 2),
            progressRow("c", .bedtimeRun, threshold: 3, estimate: 3),
            progressRow("d", .steadyWeeks, threshold: 1, estimate: 10),
            progressRow("e", .focusDays, threshold: 1, estimate: 4),
        ]
        let picker = NextLeafPicker(progress: rows)
        #expect(picker.buds(phase: .evening, pinned: nil).map(\.speciesID) == ["a", "b", "c"])
        // In the day, the day leaf (4 days) is Home's pick and takes the third place.
        #expect(picker.buds(phase: .day, pinned: nil).map(\.speciesID) == ["e", "a", "b"])
        #expect(picker.buds(phase: .evening, pinned: "d").map(\.speciesID) == ["d", "a", "b"])
        #expect(NextLeafPicker(progress: Array(rows.prefix(2))).buds(phase: .evening, pinned: nil).count == 2)
        #expect(NextLeafPicker(progress: []).buds(phase: .evening, pinned: nil).isEmpty)
    }

    @Test("Almost there: within 60 days, up to 6, from the next 3 rungs of available categories")
    func almostThere() {
        var rows: [LeafProgress] = []
        for (index, threshold) in [1.0, 3, 7, 14].enumerated() {
            rows.append(progressRow("n\(index)", .nightsTracked, threshold: threshold, estimate: threshold))
        }
        rows.append(progressRow("o0", .onTimeBedtimes, threshold: 1, estimate: 1.5))
        rows.append(progressRow("o1", .onTimeBedtimes, threshold: 3, estimate: 4.5))
        rows.append(progressRow("w0", .steadyWeeks, threshold: 1, estimate: 61))
        rows.append(progressRow("m0", .steadyMornings, threshold: 3, availability: .needsAppleHealth, estimate: nil))
        rows.append(progressRow("f0", .focusDays, threshold: 1, availability: .dormant, estimate: nil))
        let picker = NextLeafPicker(progress: rows)
        // n3 is the 4th locked rung of its category, w0 is past 60 days.
        #expect(picker.almostThere().map(\.speciesID) == ["n0", "o0", "n1", "o1", "n2"])
        #expect(picker.nextRungIDs == ["n0", "n1", "n2", "o0", "o1", "w0"])
    }

    @Test("Almost there stops at 6")
    func almostThereLimit() {
        let categories: [RewardCategoryID] = [.nightsTracked, .onTimeBedtimes, .bedtimeRun, .steadyWeeks]
        let rows = categories.flatMap { category in
            [1.0, 2, 3].map { progressRow("\(category.rawValue)\($0)", category, threshold: $0, estimate: $0) }
        }
        #expect(NextLeafPicker(progress: rows).almostThere().count == 6)
    }

    @Test("A new member with Apple Health is pointed at a first rung")
    func newMember() throws {
        let unlock = LeafUnlock(speciesID: "saccharum", date: at(2026, 10, 10, 9), season: .autumn, colourway: .autumn, revealed: true)
        let rows = LeafProgressBuilder(permissions: [.appleHealth], features: .current)
            .progress(counters: [.firstSteps: 1], unlocks: [unlock], history: [], today: LocalDay(year: 2026, month: 10, day: 10), calendar: utc)
        let picker = NextLeafPicker(progress: rows)
        for phase in NowPhase.allCases where phase != .morning {
            let next = try #require(picker.next(phase: phase, pinned: nil))
            #expect(next.speciesID == species(.nightsTracked, rung: 0), "\(phase)")
        }
        // Mornings are preferred in the morning (the first rung is within a week).
        #expect(picker.next(phase: .morning, pinned: nil)?.speciesID == species(.steadyMornings, rung: 0))
        #expect(picker.candidates.allSatisfy { $0.availability == .available })
        // Full nights wait for asleep-stage data.
        #expect(!picker.candidates.contains { $0.category == .fullNights })
        #expect(picker.buds(phase: .evening, pinned: nil).map(\.speciesID)
            == [species(.nightsTracked, rung: 0), species(.onTimeBedtimes, rung: 0), species(.bedtimeRun, rung: 0)])
        #expect(picker.permissionPrompt() == nil)
    }

    @Test("Without Apple Health nothing is a candidate; Home offers the cheapest sleep leaf to turn it on for")
    func withoutAppleHealth() throws {
        let unlock = LeafUnlock(speciesID: "saccharum", date: at(2026, 10, 10, 9), season: .autumn, colourway: .autumn, revealed: true)
        let rows = LeafProgressBuilder(permissions: [], features: .current)
            .progress(counters: [.firstSteps: 1], unlocks: [unlock], history: [], today: LocalDay(year: 2026, month: 10, day: 10), calendar: utc)
        let picker = NextLeafPicker(progress: rows)
        // D9: excluded from the next leaf, buds, Almost there and pacing.
        #expect(picker.candidates.isEmpty)
        for phase in NowPhase.allCases {
            #expect(picker.next(phase: phase, pinned: nil) == nil, "\(phase)")
        }
        #expect(picker.buds(phase: .evening, pinned: nil).isEmpty)
        #expect(picker.almostThere().isEmpty)
        #expect(picker.nextRungIDs.isEmpty)
        #expect(rows.filter { $0.availability == .needsAppleHealth }.allSatisfy { $0.estimatedDays == nil })
        // A pinned sleep leaf can't be the next leaf either.
        #expect(picker.next(phase: .evening, pinned: species(.onTimeBedtimes, rung: 0)) == nil)

        let prompt = try #require(picker.permissionPrompt())
        #expect(prompt.speciesID == species(.nightsTracked, rung: 0))
        #expect(prompt.availability == .needsAppleHealth)
    }

    @Test("The permission prompt picks by design pace, only what can be turned on, and only when nothing else can be earned")
    func permissionPrompt() {
        let weeks = progressRow("w1", .steadyWeeks, threshold: 1, availability: .needsAppleHealth, estimate: nil)      // 10 days
        let run = progressRow("b1", .bedtimeRun, threshold: 3, availability: .needsAppleHealth, estimate: nil)         // about 4.3
        let onTime = progressRow("o1", .onTimeBedtimes, threshold: 1, availability: .needsAppleHealth, estimate: nil)  // about 1.4
        let onTimeNext = progressRow("o2", .onTimeBedtimes, threshold: 3, availability: .needsAppleHealth, estimate: nil)
        let full = progressRow("f1", .fullNights, threshold: 1, availability: .needsSleepTracker, estimate: nil)       // hardware
        let focus = progressRow("d1", .focusDays, threshold: 1, availability: .dormant, estimate: nil)
        #expect(NextLeafPicker(progress: [weeks, run, onTime, onTimeNext, full, focus]).permissionPrompt()?.speciesID == "o1")
        // Only hardware is missing: nothing to turn on.
        #expect(NextLeafPicker(progress: [full, focus]).permissionPrompt() == nil)
        // Something can be earned: no prompt.
        let nights = progressRow("n1", .nightsTracked, threshold: 1, estimate: 1.1)
        #expect(NextLeafPicker(progress: [weeks, run, onTime, nights]).permissionPrompt() == nil)
        #expect(LeafAvailability.needsAppleHealth.canBeTurnedOn && LeafAvailability.needsScreenTime.canBeTurnedOn)
        #expect(!LeafAvailability.needsSleepTracker.canBeTurnedOn && !LeafAvailability.dormant.canBeTurnedOn)
    }
}
