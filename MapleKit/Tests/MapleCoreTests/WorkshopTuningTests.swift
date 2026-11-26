import Foundation
import Testing
@testable import MapleCore

@Suite("The syrup van's numbers")
struct WorkshopTuningTests {
    private let small = WorkshopFixtures.small

    @Test("The starting pace is the owner's: 0.8 leaves a minute, a leaf every 75 seconds, and one bottle a leaf before any upgrade")
    func startingPace() {
        #expect(WorkshopTuning.starting.secondsPerLeaf == 75)
        #expect(WorkshopTuning.starting.baseTenthsPerLeaf == 10)
    }

    @Test("Every machine has a ladder whose prices and syrup both rise with each level")
    func startingLadders() throws {
        for machine in WorkshopMachine.allCases {
            let ladder = try #require(WorkshopTuning.starting.ladders[machine])
            #expect(ladder.prices.count == ladder.bonusTenths.count)
            #expect(ladder.topLevel >= 1)
            #expect(ladder.prices.allSatisfy { $0 > 0 })
            #expect(zip(ladder.prices, ladder.prices.dropFirst()).allSatisfy { $0 < $1 })
            #expect(ladder.bonusTenths.first.map { $0 > 0 } == true)
            #expect(zip(ladder.bonusTenths, ladder.bonusTenths.dropFirst()).allSatisfy { $0 < $1 })
        }
    }

    @Test("A price is the leaves for the next level, and there is none at the top")
    func prices() {
        #expect(small.price(of: .evaporator, after: 0) == 5)
        #expect(small.price(of: .evaporator, after: 1) == 8)
        #expect(small.price(of: .evaporator, after: 2) == nil)
        #expect(small.price(of: .evaporator, after: 9) == nil)
        #expect(small.price(of: .evaporator, after: -1) == 5)
        #expect(small.topLevel(of: .filterPress) == 1)
    }

    @Test("Syrup per leaf is the base plus each machine's bonus at its level")
    func yield() {
        #expect(small.tenthsPerLeaf(levels: [:]) == 10)
        #expect(small.tenthsPerLeaf(levels: [.evaporator: 1]) == 12)
        #expect(small.tenthsPerLeaf(levels: [.evaporator: 2, .filterPress: 1]) == 16)
    }

    @Test("A level outside a ladder reads as its nearest end")
    func clamped() {
        #expect(small.tenthsPerLeaf(levels: [.evaporator: 7]) == 15)
        #expect(small.tenthsPerLeaf(levels: [.evaporator: -3]) == 10)
    }

    @Test("A machine with no ladder can't be upgraded and adds nothing")
    func noLadder() {
        let bare = WorkshopTuning(secondsPerLeaf: 300, baseTenthsPerLeaf: 10, ladders: [:])
        #expect(bare.topLevel(of: .evaporator) == 0)
        #expect(bare.price(of: .evaporator, after: 0) == nil)
        #expect(bare.tenthsPerLeaf(levels: [.evaporator: 2]) == 10)
    }
}
