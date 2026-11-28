import Foundation
import Testing
@testable import MapleCore

private let small = WorkshopFixtures.small

private func decode(_ json: String) throws -> WorkshopBank {
    try JSONDecoder().decode(WorkshopBank.self, from: Data(json.utf8))
}

private func reopened(_ bank: WorkshopBank) throws -> WorkshopBank {
    try JSONDecoder().decode(WorkshopBank.self, from: JSONEncoder().encode(bank))
}

@Suite("The syrup van's bank")
struct WorkshopBankTests {
    @Test("A new van is empty, with every machine as it comes")
    func empty() {
        let bank = WorkshopBank()
        #expect(bank.leaves == 0 && bank.syrupTenths == 0)
        #expect(bank.level(of: .evaporator, tuning: small) == 0)
        #expect(bank.tenthsPerLeaf(tuning: small) == 10)
        #expect(bank.price(of: .evaporator, tuning: small) == 5)
    }

    @Test("Leaves arrive as the ledger's total grows, and only the new ones are reported")
    func earning() {
        var bank = WorkshopBank()
        #expect(bank.noteEarned(10) == 10)
        #expect(bank.leaves == 10)
        #expect(bank.noteEarned(12) == 2)
        #expect(bank.leaves == 12)
    }

    @Test("The van's leaves never go down when the ledger shows fewer")
    func neverDown() {
        var bank = WorkshopBank()
        bank.noteEarned(10)
        #expect(bank.noteEarned(7) == 0)
        #expect(bank.noteEarned(-3) == 0)
        #expect(bank.leaves == 10)
    }

    @Test("Cooking turns leaves into syrup, a bottle a leaf before any upgrade")
    func cooking() {
        var bank = WorkshopBank()
        bank.noteEarned(10)
        #expect(bank.cook(3, tuning: small) == 3)
        #expect(bank.leaves == 7)
        #expect(bank.syrupTenths == 30)
    }

    @Test("Cooking never takes more leaves than the van holds, and nothing or less cooks nothing")
    func cookingBounds() {
        var bank = WorkshopBank()
        bank.noteEarned(4)
        #expect(bank.cook(0, tuning: small) == 0)
        #expect(bank.cook(-2, tuning: small) == 0)
        #expect(bank.leaves == 4 && bank.syrupTenths == 0)
        #expect(bank.cook(100, tuning: small) == 4)
        #expect(bank.leaves == 0 && bank.syrupTenths == 40)
        #expect(bank.cook(1, tuning: small) == 0)
    }

    @Test("An upgrade costs leaves and makes each later leaf give more syrup; syrup already made stays as it was")
    func upgrading() {
        var bank = WorkshopBank()
        bank.noteEarned(10)
        bank.cook(1, tuning: small)
        #expect(bank.upgrade(.evaporator, tuning: small) == .upgraded(level: 1))
        #expect(bank.leaves == 4)
        #expect(bank.level(of: .evaporator, tuning: small) == 1)
        #expect(bank.syrupTenths == 10)
        #expect(bank.tenthsPerLeaf(tuning: small) == 12)
        bank.cook(1, tuning: small)
        #expect(bank.syrupTenths == 22)
        #expect(bank.price(of: .evaporator, tuning: small) == 8)
    }

    @Test("An upgrade the van can't afford changes nothing and says how many leaves it is short")
    func short() {
        var bank = WorkshopBank()
        bank.noteEarned(4)
        let before = bank
        #expect(bank.upgrade(.evaporator, tuning: small) == .short(by: 1))
        #expect(bank == before)
    }

    @Test("A machine at the top of its ladder can't be upgraded, and costs nothing to ask")
    func atTop() {
        var bank = WorkshopBank()
        bank.noteEarned(50)
        #expect(bank.upgrade(.filterPress, tuning: small) == .upgraded(level: 1))
        let before = bank
        #expect(bank.upgrade(.filterPress, tuning: small) == .atTop)
        #expect(bank == before)
        #expect(bank.price(of: .filterPress, tuning: small) == nil)
    }

    @Test("Machines add up: both upgraded give the base plus both bonuses")
    func bothMachines() {
        var bank = WorkshopBank()
        bank.noteEarned(50)
        bank.upgrade(.evaporator, tuning: small)
        bank.upgrade(.evaporator, tuning: small)
        bank.upgrade(.filterPress, tuning: small)
        #expect(bank.leaves == 50 - 5 - 8 - 3)
        #expect(bank.tenthsPerLeaf(tuning: small) == 16)
    }

    @Test("The van is saved and read back as it was")
    func roundTrip() throws {
        var bank = WorkshopBank()
        bank.noteEarned(40)
        bank.cook(6, tuning: small)
        bank.upgrade(.evaporator, tuning: small)
        let again = try reopened(bank)
        #expect(again == bank)
        #expect(!again.decodedWithLosses)
        #expect(again.leaves == 29 && again.syrupTenths == 60)
    }

    @Test("An empty or older file reads as a new van, with nothing lost")
    func missingKeys() throws {
        let bank = try decode("{}")
        #expect(bank == WorkshopBank())
        #expect(!bank.decodedWithLosses)
    }

    @Test("A machine this build doesn't know is kept as it was saved")
    func unknownMachine() throws {
        var bank = try decode(#"{"earned":20,"levels":{"evaporator":1,"centrifuge":3}}"#)
        #expect(!bank.decodedWithLosses)
        bank.cook(1, tuning: small)
        let saved = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(bank)) as? [String: Any])
        #expect((saved["levels"] as? [String: Int])?["centrifuge"] == 3)
    }

    @Test("Damaged numbers read as the nearest sane value, and the van says it lost something")
    func damaged() throws {
        let bank = try decode(#"{"earned":"lots","cooked":-4,"spentOnUpgrades":2,"syrupMadeTenths":-9,"levels":{"evaporator":-2}}"#)
        #expect(bank.decodedWithLosses)
        #expect(bank.leaves == 0)
        #expect(bank.syrupTenths == 0)
        #expect(bank.level(of: .evaporator, tuning: small) == 0)
        let unreadableLevels = try decode(#"{"earned":5,"levels":[1,2]}"#)
        #expect(unreadableLevels.decodedWithLosses)
        #expect(unreadableLevels.leaves == 5)
    }

    @Test("A file that cooked or spent more than it earned never shows fewer than no leaves")
    func overspent() throws {
        var bank = try decode(#"{"earned":3,"cooked":8,"spentOnUpgrades":5}"#)
        #expect(bank.decodedWithLosses)
        #expect(bank.leaves == 0)
        #expect(bank.noteEarned(10) == 0)
        #expect(bank.noteEarned(15) == 2)
        #expect(bank.leaves == 2)
    }

    @Test("Numbers too big to be real are capped, so cooking them can't overflow")
    func huge() throws {
        var bank = try decode(#"{"earned":9223372036854775807}"#)
        #expect(bank.decodedWithLosses)
        #expect(bank.leaves == WorkshopBank.limit)
        #expect(bank.cook(Int.max, tuning: small) == WorkshopBank.limit)
        #expect(bank.syrupTenths == WorkshopBank.limit * 10)
        var fresh = WorkshopBank()
        #expect(fresh.noteEarned(Int.max) == WorkshopBank.limit)
    }

    @Test("After a retune that shortens a ladder, a saved level reads as the new top")
    func retuned() throws {
        var bank = try decode(#"{"earned":30,"syrupMadeTenths":70,"levels":{"evaporator":2}}"#)
        var shorter = small
        shorter.ladders[.evaporator] = WorkshopTuning.Ladder(prices: [5], bonusTenths: [2])
        #expect(bank.level(of: .evaporator, tuning: shorter) == 1)
        #expect(bank.tenthsPerLeaf(tuning: shorter) == 12)
        #expect(bank.upgrade(.evaporator, tuning: shorter) == .atTop)
        bank.cook(1, tuning: shorter)
        #expect(bank.syrupTenths == 82)
        #expect(!bank.decodedWithLosses)
    }

    @Test("After the pace is slowed, leaves already earned stay and the next session still earns")
    func slowerPace() {
        var bank = WorkshopBank()
        bank.noteEarned(600, tuning: small)
        bank.cook(100, tuning: small)
        var slower = small
        slower.leavesPerHour = 10
        #expect(bank.noteEarned(500, tuning: slower) == 0)
        #expect(bank.leaves == 500)
        #expect(bank.noteEarned(508, tuning: slower) == 8)
        #expect(bank.leaves == 508)
    }

    @Test("After the pace is quickened, the same sessions don't pay out a second time")
    func quickerPace() {
        var bank = WorkshopBank()
        bank.noteEarned(600, tuning: small)
        var quicker = small
        quicker.leavesPerHour = 15
        #expect(bank.noteEarned(750, tuning: quicker) == 0)
        #expect(bank.leaves == 600)
        #expect(bank.noteEarned(762, tuning: quicker) == 12)
        #expect(bank.leaves == 612)
    }

    @Test("A change to the earning rules starts a new count the same way: nothing lost, nothing paid twice")
    func newRules() {
        var bank = WorkshopBank()
        bank.noteEarned(600, tuning: small, rules: 1)
        #expect(bank.noteEarned(540, tuning: small, rules: 2) == 0)
        #expect(bank.leaves == 600)
        #expect(bank.noteEarned(550, tuning: small, rules: 2) == 10)
        #expect(bank.leaves == 610)
    }

    @Test("The count the ledger was last seen at is saved with its pace, so a relaunch pays nothing twice")
    func baselineSaved() throws {
        var slower = small
        slower.leavesPerHour = 10
        var bank = WorkshopBank()
        bank.noteEarned(600, tuning: small)
        bank.noteEarned(500, tuning: slower)
        var again = try reopened(bank)
        #expect(again == bank)
        #expect(again.noteEarned(500, tuning: slower) == 0)
        #expect(again.noteEarned(503, tuning: slower) == 3)
        #expect(again.leaves == 603)
    }

    @Test("A short read of the ledger at the same pace changes nothing, and the full read after it pays nothing twice")
    func shortRead() {
        var bank = WorkshopBank()
        bank.noteEarned(600, tuning: small)
        #expect(bank.noteEarned(450, tuning: small) == 0)
        #expect(bank.noteEarned(600, tuning: small) == 0)
        #expect(bank.noteEarned(604, tuning: small) == 4)
        #expect(bank.leaves == 604)
    }

    @Test("Two vans with the same contents are equal, whether or not one was read with losses")
    func equality() throws {
        #expect(try decode(#"{"earned":0,"cooked":-1}"#) == WorkshopBank())
    }
}
