import Foundation
import Testing
@testable import MapleCore
@testable import MapleServices

/// Apple Health as the test says it is: whether the prompt is due, and what showing it does.
@MainActor
final class FakeHealthAuthorizer: HealthAuthorizing {
    struct Refused: Error {}

    var isHealthDataAvailable = true
    /// Apple Health's own record: true before the member has answered the prompt.
    var promptDue: Bool? = true
    var fails = false
    private(set) var requests = 0

    func promptIsDue() async -> Bool? { promptDue }

    func requestSleepAccess() async throws {
        requests += 1
        if fails { throw Refused() }
        promptDue = false
    }
}

/// The sleep category, which comes from Apple Health only (spec D9).
private let sleepCategories: [RewardCategoryID] = [.restedNights]

@Suite("Apple Health permission")
@MainActor
struct HealthPermissionTests {
    private let now = at(2026, 10, 10, 15)

    @Test("The live app grants nothing until the member has been through Apple's prompt")
    func liveStartsWithout() throws {
        let folder = try temporaryDirectory()
        let stores = MapleStores.live(directory: folder, calendar: utc, now: now, healthAuthorizer: FakeHealthAuthorizer())
        #expect(!stores.health.isConnected)
        #expect(stores.collection.context.permissions.isEmpty)
        #expect(stores.collection.permissions.isEmpty)
        for category in sleepCategories {
            #expect(stores.collection.availability(of: category) == .needsAppleHealth, "\(category)")
        }
        #expect(stores.collection.availability(of: .firstLeaf) == .available)
        #expect(!files(in: folder).contains(HealthPermission.file))
    }

    @Test("Without Apple Health a new member has nothing to earn: no next leaf, buds, Almost there or totals")
    func newMemberWithout() throws {
        let folder = try temporaryDirectory()
        let stores = MapleStores.live(directory: folder, calendar: utc, now: now, healthAuthorizer: FakeHealthAuthorizer())
        stores.schedule.save(.standard, at: at(2026, 10, 1, 21))
        stores.collection.openReveals(at: at(2026, 10, 1, 21, 5))
        let evening = at(2026, 10, 10, 21)
        #expect(stores.collection.nextLeaf(at: evening) == nil)
        #expect(stores.collection.buds(at: evening).isEmpty)
        #expect(stores.collection.almostThere(at: evening).isEmpty)
        #expect(stores.collection.nextRungIDs(at: evening).isEmpty)
        #expect(stores.collection.totals.nightsOnTime == nil && stores.collection.totals.mornings == nil)
        // Home's row offers the cheapest sleep leaf, with "Turn on Apple Health".
        let prompt = try #require(stores.collection.permissionPrompt(at: evening))
        #expect(prompt.speciesID == "saccharinum")                    // Rested nights' first rung
        #expect(prompt.availability == .needsAppleHealth)
        #expect(prompt.estimatedDays == nil)
    }

    @Test("Completing Apple's prompt connects Apple Health, saves it, and makes the sleep leaves available")
    func connect() async throws {
        let folder = try temporaryDirectory()
        let apple = FakeHealthAuthorizer()
        let stores = MapleStores.live(directory: folder, calendar: utc, now: now, healthAuthorizer: apple)
        stores.schedule.save(.standard, at: at(2026, 10, 1, 21))

        #expect(await stores.health.requestAccess(at: now))
        #expect(apple.requests == 1)
        #expect(stores.health.isConnected)
        #expect(stores.health.connection.promptCompletedAt == now)
        #expect(files(in: folder).contains(HealthPermission.file))

        stores.health.apply(to: stores.collection)
        #expect(stores.collection.context.permissions == [.appleHealth])
        #expect(stores.collection.availability(of: .restedNights) == .available)
        #expect(stores.collection.nextLeaf(at: at(2026, 10, 10, 21)) != nil)
        #expect(stores.collection.permissionPrompt(at: at(2026, 10, 10, 21)) == nil)

        // The next launch starts connected.
        let relaunch = MapleStores.live(directory: folder, calendar: utc, now: now, healthAuthorizer: apple)
        #expect(relaunch.health.isConnected)
        #expect(relaunch.collection.context.permissions == [.appleHealth])
    }

    @Test("A prompt that fails, or a device without Apple Health, connects nothing")
    func notConnected() async throws {
        let failing = FakeHealthAuthorizer()
        failing.fails = true
        let health = HealthPermission(storage: JSONStorage(.memory), authorizer: failing)
        #expect(!(await health.requestAccess(at: now)))
        #expect(!health.isConnected)
        #expect(health.permissions.isEmpty)

        let missing = FakeHealthAuthorizer()
        missing.isHealthDataAvailable = false
        let none = HealthPermission(storage: JSONStorage(.memory), authorizer: missing)
        #expect(!none.canRequest)
        #expect(!(await none.requestAccess(at: now)))
        #expect(missing.requests == 0)
    }

    @Test("The live record follows Apple Health's own: answered elsewhere connects, a reset disconnects")
    func refresh() async throws {
        let folder = try temporaryDirectory()
        let apple = FakeHealthAuthorizer()
        apple.promptDue = false
        let health = HealthPermission.live(directory: folder, authorizer: apple)
        let collection = CollectionStore(storage: JSONStorage(.memory), context: CollectionContext(calendar: utc), now: now)
        await health.refresh(at: now)
        #expect(health.isConnected)
        health.apply(to: collection)
        #expect(collection.context.permissions == [.appleHealth])

        apple.promptDue = true
        await health.refresh(at: now)
        #expect(!health.isConnected)
        health.apply(to: collection)
        #expect(collection.context.permissions.isEmpty)

        // Unknown leaves it as it was.
        apple.promptDue = nil
        await health.refresh(at: now)
        #expect(!health.isConnected)

        // A DEBUG demo keeps what its arguments gave it.
        let demo = HealthPermission(storage: JSONStorage(.memory, initial: HealthConnection(promptCompletedAt: now)), authorizer: apple)
        apple.promptDue = true
        await demo.refresh(at: now)
        #expect(demo.isConnected)
    }

    @Test("Withdrawing Apple Health leaves other permissions alone")
    func applyKeepsOthers() {
        let collection = CollectionStore(
            storage: JSONStorage(.memory), context: CollectionContext(permissions: [.screenTime, .appleHealth, .sleepTracker], calendar: utc),
            now: now
        )
        let health = HealthPermission(storage: JSONStorage(.memory), authorizer: FakeHealthAuthorizer())
        health.apply(to: collection)
        #expect(collection.context.permissions == [.screenTime])
    }

    @Test("Demo launches are granted what their arguments say, and write nothing")
    func demos() throws {
        let folder = try temporaryDirectory()
        func make(_ arguments: [String]) -> MapleStores {
            MapleStores.make(DemoLaunchOptions(arguments: arguments), directory: folder, calendar: utc, now: now)
        }
        // Demo collections show earned progress: Apple Health and a sleep tracker.
        let rich = make(["-MapleDemoSpecies", "23"])
        #expect(rich.collection.context.permissions == [.appleHealth, .sleepTracker])
        #expect(rich.health.isConnected)
        #expect(sleepCategories.allSatisfy { rich.collection.availability(of: $0) == .available })
        #expect(make(["-MapleDemoSpecies", "23", "-MapleDemoPermissions", "none"]).collection.context.permissions.isEmpty)
        #expect(!make(["-MapleDemoSpecies", "23", "-MapleDemoPermissions", "none"]).health.isConnected)
        #expect(make(["-MapleDemoFresh", "YES"]).collection.context.permissions.isEmpty)
        // A copy of the member's own collection gets their own Apple Health record.
        #expect(make(["-MapleDemoPhase", "evening"]).collection.context.permissions.isEmpty)
        JSONStorage<HealthConnection>(.file(folder.appendingPathComponent(HealthPermission.file)))
            .save(HealthConnection(promptCompletedAt: now))
        let own = make(["-MapleDemoPhase", "evening"])
        #expect(own.collection.context.permissions == [.appleHealth])
        #expect(own.health.isConnected)

        let before = files(in: folder)
        _ = make(["-MapleDemoSpecies", "40", "-MapleDemoPermissions", "all"])
        #expect(files(in: folder) == before)
    }
}
