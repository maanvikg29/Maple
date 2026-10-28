import Foundation
import Testing
@testable import MapleCore

// The one count rule (spec §5.2: "N of 155" counts opened leaves only) and the first-run gate (spec §8.8, D12).

@Suite("Leaf count: N of 155 counts opened leaves")
struct LeafCountTests {
    private let context = CollectionContext(schedule: .standard, calendar: utc, hemisphere: .northern)

    /// Planted and opened on 1 Oct, then two hours saved by the 4th: two leaves earned and still waiting.
    private func withWaiting() -> CollectionSnapshot {
        var snapshot = CollectionSnapshot.empty(profileID: UUID(), createdAt: at(2026, 10, 1, 9))
        snapshot.raise(.firstLeaf, to: 1, at: at(2026, 10, 1, 9), calendar: utc)
        snapshot.runEngine(at: at(2026, 10, 1, 9), context: context)
        snapshot.openReveals(nil, at: at(2026, 10, 1, 9, 5), context: context)
        snapshot.record([.hoursSaved: 2], at: at(2026, 10, 4, 7), calendar: utc)
        snapshot.runEngine(at: at(2026, 10, 4, 7), context: context)
        return snapshot
    }

    @Test("Waiting leaves never add to N; they are counted apart")
    func snapshotCount() {
        let snapshot = withWaiting()
        #expect(snapshot.unlocks.count == 3)
        let count = snapshot.leafCount
        #expect(count.opened == 1)
        #expect(count.waiting == 2)
        #expect(count.total == LeafCatalog.shared.species.count)
        #expect(count.text == "1 of 155")
        #expect(count.spoken == "1 of 155 leaves")
        #expect(count.waitingText == "2 waiting")
        #expect(count.spokenWaiting == "2 leaves waiting to open")
        #expect(abs(count.fraction - 1.0 / 155) < 1e-12)
    }

    @Test("Every reader of N agrees: tree stage, tree species, Profile totals")
    func readersAgree() {
        var snapshot = withWaiting()
        let now = at(2026, 10, 4, 13)
        let tree = snapshot.treeInputs(at: now, context: context)
        #expect(tree.species.count == snapshot.leafCount.opened)
        #expect(tree.stage == TreeStage(speciesCount: 1))
        #expect(snapshot.totals(context: context).leaves == 1)
        #expect(snapshot.totals(context: context).stage == .seedling)

        snapshot.openReveals(nil, at: now, context: context)
        #expect(snapshot.leafCount == LeafCount(opened: 3, waiting: 0, total: 155))
        #expect(snapshot.leafCount.waitingText == nil)
        #expect(snapshot.leafCount.spokenWaiting == nil)
        #expect(snapshot.totals(context: context).leaves == 3)
        #expect(snapshot.treeInputs(at: now, context: context).species.count == 3)
    }

    @Test("A group of progress rows counts its opened leaves against its own size")
    func groupCount() {
        let unlock = LeafUnlock(speciesID: "a", date: at(2026, 10, 1), season: .autumn, colourway: .autumn, revealed: true)
        var bud = unlock
        bud.revealed = false
        let rows = [
            progressRow("a", .restedNights, threshold: 1, current: 1, state: .earned(unlock), estimate: nil),
            progressRow("b", .restedNights, threshold: 3, current: 3, state: .waiting(bud), estimate: nil),
            progressRow("c", .restedNights, threshold: 7, current: 3, estimate: 4),
        ]
        let count = LeafCount(rows)
        #expect(count == LeafCount(opened: 1, waiting: 1, total: 3))
        #expect(count.text == "1 of 3")
        #expect(rows.map(\.isOpened) == [true, false, false])
        #expect(rows.map(\.state.isWaiting) == [false, true, false])
        #expect(LeafCount([LeafProgress]()) == LeafCount(opened: 0, total: 0))
        #expect(LeafCount(opened: 0, total: 0).fraction == 0)
    }

    @Test("Counts are never negative")
    func clamped() {
        let count = LeafCount(opened: -1, waiting: -2, total: -3)
        #expect(count == LeafCount(opened: 0, waiting: 0, total: 0))
    }
}

@Suite("First run: where the end of onboarding resumes")
struct FirstRunTests {
    private let context = CollectionContext(schedule: .standard, calendar: utc, hemisphere: .northern)
    private let sugarMaple = LeafUnlock(speciesID: "saccharum", date: at(2026, 10, 1, 22), season: .autumn, colourway: .autumn)

    @Test("The gate decision for every saved state")
    func decisions() {
        var placed = sugarMaple
        placed.revealed = true
        // Fresh install: ask for the schedule.
        #expect(FirstRunStep.resume(hasSavedSchedule: false, firstLeaf: nil) == .schedule)
        // Killed between the schedule file and the collection file: record the leaf, never ask again.
        #expect(FirstRunStep.resume(hasSavedSchedule: true, firstLeaf: nil) == .recordFirstLeaf)
        // Killed after "Save schedule", before "Place on your maple": the sprout for the waiting Sugar maple.
        #expect(FirstRunStep.resume(hasSavedSchedule: true, firstLeaf: sugarMaple) == .sprout)
        // The leaf alone proves the schedule step happened, even if the schedule file is missing.
        #expect(FirstRunStep.resume(hasSavedSchedule: false, firstLeaf: sugarMaple) == .sprout)
        // Placed: the first run is over.
        #expect(FirstRunStep.resume(hasSavedSchedule: true, firstLeaf: placed) == .finished)
        #expect(FirstRunStep.resume(hasSavedSchedule: false, firstLeaf: placed) == .finished)
    }

    @Test("Only a finished run skips onboarding")
    func needsOnboarding() {
        #expect(FirstRunStep.schedule.needsOnboarding)
        #expect(FirstRunStep.recordFirstLeaf.needsOnboarding)
        #expect(FirstRunStep.sprout.needsOnboarding)
        #expect(!FirstRunStep.finished.needsOnboarding)
        #expect(FirstRunStep.firstLeafID == "saccharum")
    }

    @Test("The snapshot finds the first leaf whatever else was earned")
    func snapshotFirstLeaf() {
        var snapshot = CollectionSnapshot.empty(profileID: UUID(), createdAt: at(2026, 10, 1, 22))
        #expect(snapshot.firstLeaf == nil)
        #expect(!snapshot.hasPlacedFirstLeaf)
        snapshot.raise(.firstLeaf, to: 1, at: at(2026, 10, 1, 22), calendar: utc)
        snapshot.runEngine(at: at(2026, 10, 1, 22), context: context)
        #expect(snapshot.firstLeaf?.speciesID == "saccharum")
        #expect(snapshot.hasPlantedMaple)
        #expect(!snapshot.hasPlacedFirstLeaf)
        // Wind-down: other leaves would be held, but the Sugar maple opens at any hour (D12).
        snapshot.openReveals(["saccharum"], at: at(2026, 10, 1, 22, 30), context: context)
        #expect(snapshot.hasPlacedFirstLeaf)
        #expect(FirstRunStep.resume(hasSavedSchedule: true, firstLeaf: snapshot.firstLeaf) == .finished)
    }

    @Test("Awarding the first leaf again never duplicates the Sugar maple")
    func idempotentAward() {
        var snapshot = CollectionSnapshot.empty(profileID: UUID(), createdAt: at(2026, 10, 1, 22))
        for minute in 0..<3 {
            snapshot.raise(.firstLeaf, to: 1, at: at(2026, 10, 1, 22, minute), calendar: utc)
            snapshot.runEngine(at: at(2026, 10, 1, 22, minute), context: context)
        }
        #expect(snapshot.unlocks.map(\.speciesID) == ["saccharum"])
    }
}
