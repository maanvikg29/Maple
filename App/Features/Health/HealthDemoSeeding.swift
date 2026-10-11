#if DEBUG
import Foundation
import os
import MapleCore
import MapleServices

/// DEBUG only: `-MapleDemoSeedHealth <nights>` (and `-MapleDemoSeedSource watch|iphone|otherApp`) on the first
/// foreground of a launch writes synthetic sleep for the last N nights into the simulator's Apple Health
/// (`HealthSleepSeeder`), then connects Apple Health and imports, as the real flow would
/// (docs/debug-launch-arguments.md). It needs a planted maple: nights are varied around the saved schedule and none
/// starts before the maple was planted.
///
/// The seeder's own authorization request (write and read sleep) is Apple's prompt, which needs a tap; once it has
/// been answered, `HealthPermission.requestAccess` has nothing left to ask and records the connection without a
/// second sheet. Automated runs use `-MapleDemoSeedStore memory` on a demo launch instead, which needs no sheet.
@MainActor
enum HealthDemoSeeding {
    private static var hasRun = false
    private static var logger: Logger { Logger(subsystem: "com.maanvikgupta.maple", category: "health") }

    static func runIfRequested(
        collection: CollectionStore, health: HealthPermission, sleep: HealthSleepImporter, clock: MapleClock
    ) async {
        // `-MapleDemoSeedStore memory` was seeded before the first frame (`HealthSleepImporter.launch`).
        guard !hasRun, let options = HealthSleepSeeder.Options.current, options.store == .health else { return }
        hasRun = true
        guard let planted = collection.firstLeaf?.date else {
            logger.error("-MapleDemoSeedHealth needs a planted maple: run the first run first")
            return
        }
        do {
            try await HealthSleepSeeder.seed(
                options, schedule: collection.schedule, now: clock.now(), calendar: collection.context.calendar,
                notBefore: planted
            )
        } catch {
            logger.error("Couldn't seed Apple Health: \(String(describing: error), privacy: .public)")
        }
        await health.requestAccess(at: clock.now())
        health.apply(to: collection)
        sleep.startObserving(clock: clock)
        await sleep.importNow(at: clock.now())
    }
}
#endif
