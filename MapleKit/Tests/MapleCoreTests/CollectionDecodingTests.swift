import Foundation
import Testing
@testable import MapleCore

/// What the collection's tolerant decoder reports: a field that is there but unreadable takes its default and is
/// counted as a loss (the store then keeps a copy of the file); a field that is simply missing is not.
@Suite("Collection decoding")
struct CollectionDecodingTests {
    private let context = CollectionContext(schedule: .standard, permissions: [.appleHealth], calendar: utc, hemisphere: .northern)

    /// Two unlocks (the Sugar maple and the first hours leaf) and some counters.
    private func twoLeaves() -> CollectionSnapshot {
        var snapshot = CollectionSnapshot.empty(profileID: UUID(), createdAt: at(2026, 10, 1))
        snapshot.raise(.firstLeaf, to: 1, at: at(2026, 10, 1, 21), calendar: utc)
        snapshot.runEngine(at: at(2026, 10, 1, 21), context: context)
        snapshot.record([.hoursSaved: 1], at: at(2026, 10, 2, 9), calendar: utc)
        snapshot.runEngine(at: at(2026, 10, 2, 9), context: context)
        return snapshot
    }

    private func object(_ snapshot: CollectionSnapshot) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws -> CollectionSnapshot {
        try JSONDecoder().decode(CollectionSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }

    @Test("A clean file decodes without losses, and so does one with keys missing")
    func clean() throws {
        let snapshot = twoLeaves()
        #expect(!snapshot.decodedWithLosses)
        var current = try object(snapshot)
        #expect(!(try decode(current)).decodedWithLosses)
        // A version 1 file has no focus key, and may lack other optional keys.
        current["version"] = 1
        for key in ["focus", "nights", "pinnedSpeciesID", "rarityConsent", "revealsOpened", "recentNights"] { current[key] = nil }
        let old = try decode(current)
        #expect(!old.decodedWithLosses)
        #expect(old.unlocks.count == 2)
        // null is the same as missing.
        current["history"] = NSNull()
        #expect(!(try decode(current)).decodedWithLosses)
    }

    @Test("A field that is there but unreadable takes its default and counts as a loss", arguments: [
        "history", "tendedDays", "recentNights", "revealsOpened", "rarityConsent", "revealedAt", "nights", "focus", "version",
        "pinnedSpeciesID", "counters", "unlocks",
    ])
    func damagedField(key: String) throws {
        var current = try object(twoLeaves())
        // A string is readable as an optional string, so that field gets a number instead.
        current[key] = key == "pinnedSpeciesID" ? 12 : "damaged"
        #expect(try decode(current).decodedWithLosses, "\(key)")
    }

    @Test("One bad unlock drops only itself, and the maple stays planted")
    func badUnlock() throws {
        let snapshot = twoLeaves()
        var current = try object(snapshot)
        let unlocks = try #require(current["unlocks"] as? [Any])
        current["unlocks"] = ["garbage", unlocks[0], ["speciesID": "x", "season": "monsoon"], unlocks[1]]
        let decoded = try decode(current)
        #expect(decoded.unlocks == snapshot.unlocks)
        #expect(decoded.hasPlantedMaple)
        #expect(decoded.decodedWithLosses)
        // The rest of the file is untouched.
        #expect(decoded.counters == snapshot.counters)
        #expect(decoded.history == snapshot.history)
    }

    @Test("The loss flag is never saved, so a repaired file reads clean")
    func notEncoded() throws {
        var current = try object(twoLeaves())
        current["history"] = "damaged"
        let lossy = try decode(current)
        #expect(lossy.decodedWithLosses)
        let saved = try object(lossy)
        #expect(saved["decodedWithLosses"] == nil)
        #expect(!(try decode(saved)).decodedWithLosses)
    }
}
