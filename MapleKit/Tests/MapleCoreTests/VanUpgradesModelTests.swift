import Testing
@testable import MapleCore

@Suite("The van's machines: what the upgrade screen says")
struct VanUpgradesModelTests {
    private let tuning = WorkshopTuning(
        leavesPerHour: 54, baseTenthsPerLeaf: 10,
        ladders: [
            .evaporator: .init(prices: [40, 100], bonusTenths: [2, 5]),
            .filterPress: .init(prices: [80], bonusTenths: [1]),
        ]
    )

    private func model(leaves: Int, levels: [WorkshopMachine: Int] = [:]) -> VanUpgradesModel {
        VanUpgradesModel(leaves: leaves, levels: levels, tuning: tuning)
    }

    @Test("Before any upgrade a leaf cooks into one bottle, and each machine says what its first level costs and gives")
    func fresh() {
        let shown = model(leaves: 45)
        #expect(shown.yieldText == "1 leaf cooks into 1 bottle of syrup")
        #expect(shown.leavesText == "45 leaves to spend")
        #expect(shown.rows.map(\.machine) == [.evaporator, .filterPress])
        let pan = shown.rows[0]
        #expect(pan.name == "Evaporator")
        #expect(pan.levelText == "Level 0 of 2")
        #expect(pan.nowText == "Not upgraded yet")
        #expect(pan.nextText == "Next level: each leaf gives 0.2 more syrup")
        #expect(pan.price == 40 && pan.canAfford && !pan.isAtTop)
        #expect(pan.buttonTitle == "Upgrade · 40 leaves")
    }

    @Test("A machine the van can't pay for yet says how many leaves are still to go, and its button does nothing")
    func short() {
        let press = model(leaves: 45).rows[1]
        #expect(press.name == "Filter press")
        #expect(!press.canAfford)
        #expect(press.buttonTitle == "80 leaves · 35 to go")
        #expect(model(leaves: 79).rows[1].buttonTitle == "80 leaves · 1 to go")
        #expect(model(leaves: 1).leavesText == "1 leaf to spend")
        #expect(model(leaves: 0).leavesText == "No leaves to spend")
    }

    @Test("Upgraded machines add up, and a machine at the top of its ladder has nothing left to buy")
    func upgraded() {
        let shown = model(leaves: 500, levels: [.evaporator: 1, .filterPress: 1])
        #expect(shown.yieldText == "1 leaf cooks into 1.3 bottles of syrup")
        let pan = shown.rows[0]
        #expect(pan.levelText == "Level 1 of 2")
        #expect(pan.nowText == "Each leaf gives 0.2 more syrup")
        #expect(pan.nextText == "Next level: each leaf gives 0.5 more syrup")
        #expect(pan.buttonTitle == "Upgrade · 100 leaves")
        let press = shown.rows[1]
        #expect(press.isAtTop && press.price == nil && press.nextText == nil && press.buttonTitle == nil)
        #expect(press.levelText == "Level 1 of 1 · the top")
        #expect(model(leaves: 0, levels: [.evaporator: 2, .filterPress: 1]).yieldText == "1 leaf cooks into 1.6 bottles of syrup")
    }

    @Test("A level outside a ladder reads as its nearest end, and whole bottles read without a decimal")
    func odd() {
        #expect(model(leaves: 0, levels: [.evaporator: 9]).rows[0].isAtTop)
        #expect(model(leaves: 0, levels: [.evaporator: -3]).rows[0].levelText == "Level 0 of 2")
        let round = WorkshopTuning(leavesPerHour: 54, baseTenthsPerLeaf: 10, ladders: [.evaporator: .init(prices: [5], bonusTenths: [10])])
        #expect(VanUpgradesModel(leaves: 0, levels: [.evaporator: 1], tuning: round).yieldText == "1 leaf cooks into 2 bottles of syrup")
    }
}
