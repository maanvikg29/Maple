import Foundation
import MapleCore
import MapleDesign
import MapleServices
import Observation

/// The member's `WindDownSession`, kept as JSON next to the collection so wind-down and the phone-down time
/// survive a relaunch (spec §8.1). Wind-down mode writes it; Rest reads it for "Return to wind-down".
///
/// Home can read the same two facts for its state (§3.4):
/// `collection.nowState(at: now, goodnightAt: BedsideLog.shared.session.goodnight(forMorningOf: now),
/// windDownActive: BedsideLog.shared.session.isActive(at: now, schedule: …, calendar: …))`.
@Observable
final class BedsideLog {
    static let fileName = "bedside.json"

    /// The app's log. DEBUG demo launches keep it in memory, like every other store, so nothing is written.
    static let shared = BedsideLog(storage: launchStorage())

    private(set) var session: WindDownSession
    @ObservationIgnored private let storage: JSONStorage<WindDownSession>

    init(storage: JSONStorage<WindDownSession>) {
        self.storage = storage
        session = storage.load() ?? WindDownSession()
    }

    /// Wind-down mode opened (recorded only in the evening and wind-down phases).
    func startWindDown(at date: Date, schedule: WeeklySleepSchedule, calendar: Calendar) {
        update { session in session.start(at: date, schedule: schedule, calendar: calendar) }
    }

    /// Goodnight: the phone goes down now.
    func sayGoodnight(at date: Date) {
        update { $0.sayGoodnight(at: date) }
    }

    func isWindDownActive(at date: Date, schedule: WeeklySleepSchedule, calendar: Calendar) -> Bool {
        session.isActive(at: date, schedule: schedule, calendar: calendar)
    }

    private func update(_ change: (inout WindDownSession) -> Void) {
        var copy = session
        change(&copy)
        guard copy != session else { return }
        session = copy
        storage.save(copy)
    }

    private static func launchStorage() -> JSONStorage<WindDownSession> {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-MapleDemo") }) {
            return JSONStorage(.memory)
        }
        #endif
        return JSONStorage(.file(MapleContainer.directory().appending(path: fileName)))
    }
}

/// What Home's NowState reads from wind-down mode (spec §3.4): whether the mode is on ("Return to wind-down"),
/// and the Goodnight tap the morning shows when Apple Health has nothing.
struct BedsideState: Equatable {
    var windDownActive = false
    var goodnightAt: Date?
}

extension BedsideLog {
    func state(at date: Date, collection: CollectionStore) -> BedsideState {
        BedsideState(
            windDownActive: isWindDownActive(at: date, schedule: collection.schedule, calendar: collection.context.calendar),
            goodnightAt: session.goodnight(forMorningOf: date)
        )
    }
}
