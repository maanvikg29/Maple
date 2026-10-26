import Foundation
import Testing
@testable import MapleCore
@testable import MapleServices

/// The build Maple ships once F1 is flipped on (F1 design §9): Focus has shipped, and a free build can't block
/// (F1-17). So its Screen Time leaves read "Not available in this build", F2's stay dormant, and Home's next leaf
/// stays on Rested nights, the one ladder it can earn.
@Suite("The shipped free build")
@MainActor
struct FreeBuildTests {
    private let now = at(2026, 10, 10, 15)

    @Test("This build ships M1 and F1, never F2")
    func ships() {
        #expect(ShippedFeatures.current == ShippedFeatures(releases: [.m1, .f1]))
        #expect(ShippedFeatures.current.focus && ShippedFeatures.current.screenTime)
        #expect(!ShippedFeatures.current.sleepSounds)
    }

    @Test("A live launch that can't block shows Screen Time leaves as not in this build and keeps Home on Rested nights")
    func freeBuild() async throws {
        let folder = try temporaryDirectory()
        let stores = MapleStores.live(directory: folder, calendar: utc, now: now, healthAuthorizer: FakeHealthAuthorizer())
        #expect(stores.collection.context.features == .current)
        #expect(stores.collection.context.blocking == .unavailableInBuild)
        for category in [RewardCategoryID.hoursSaved, .sessionsFinished, .focusStreak] {
            #expect(stores.collection.availability(of: category) == .notInThisBuild, "\(category)")
        }
        for category in [RewardCategoryID.phoneFreeMornings, .bedtimeKept] {
            #expect(stores.collection.availability(of: category) == .dormant, "\(category)")
        }

        stores.schedule.save(.standard, at: at(2026, 10, 1, 21))
        #expect(await stores.health.requestAccess(at: now))
        stores.health.apply(to: stores.collection)
        let evening = at(2026, 10, 10, 21)
        let next = try #require(stores.collection.nextLeaf(at: evening))
        #expect(RewardCatalog.shared.reward(forSpecies: next.speciesID)?.categoryID == .restedNights)
        #expect(next.speciesID == "saccharinum")                   // Rested nights' first rung
        #expect(stores.collection.permissionPrompt(at: evening) == nil)
    }
}
