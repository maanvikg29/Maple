import Foundation
import MapleCore
import Observation

/// A saved sleep schedule and when it was last saved.
///
/// The file keeps its shape from before weekend schedules: `schedule` holds the weekday schedule's own fields, plus
/// a `weekend` schedule when weekend nights differ (`WeeklySleepSchedule`'s coding). So a file saved by an earlier
/// build reads as the same schedule every night, losslessly, and needs no migration step.
nonisolated public struct SavedSchedule: Codable, Sendable, Equatable {
    public var schedule: WeeklySleepSchedule
    public var savedAt: Date

    public init(schedule: WeeklySleepSchedule, savedAt: Date) {
        self.schedule = schedule
        self.savedAt = savedAt
    }
}

/// The member's sleep schedule: weekday nights and, optionally, weekend nights (wake, bedtime, wind-down length).
/// Screens read it with `@Environment(ScheduleStore.self)` and change it with one call, `save(_:at:)`.
///
/// ```swift
/// schedule.weekly                                              // WeeklySleepSchedule: weekday + optional weekend
/// schedule.tonight(at: now)                                    // the SleepSchedule tonight is planned with
/// schedule.weekly.upcoming(from: now, days: 7, calendar: cal)  // [NightTimes] for reminders
/// schedule.save(WeeklySleepSchedule(weekday: …, weekend: …), at: clock.now())
/// ```
///
/// Until the member saves one, `weekly` is `WeeklySleepSchedule.standard` and `hasSavedSchedule` is false. Saving the
/// first schedule records the first leaf and unlocks the Sugar maple ("Plant your maple"), the leaf revealed
/// at the end of onboarding (D12).
@Observable
public final class ScheduleStore {
    /// The member's weekday and weekend schedules.
    public private(set) var weekly: WeeklySleepSchedule
    /// When the schedule was last saved; nil until the member saves one.
    public private(set) var savedAt: Date?
    /// False while the schedule file exists but can't be read yet (before the first unlock after a restart): the
    /// store then shows the standard schedule, never saves over the file, and `reloadIfUnavailable()` reads it.
    public private(set) var isAvailable: Bool
    /// "Now" for `schedule`: live, or the DEBUG demo clock (`MapleStores` sets it).
    @ObservationIgnored public var clock: MapleClock = .live

    @ObservationIgnored private let storage: JSONStorage<SavedSchedule>
    @ObservationIgnored private let collection: CollectionStore

    public init(storage: JSONStorage<SavedSchedule>, collection: CollectionStore) {
        self.storage = storage
        self.collection = collection
        let read = storage.read()
        let saved: SavedSchedule? = if case .value(let value) = read { value } else { nil }
        if case .unavailable = read { isAvailable = false } else { isAvailable = true }
        weekly = saved?.schedule ?? .standard
        savedAt = saved?.savedAt
        collection.schedule = weekly
    }

    /// Tonight's schedule now (on `clock`), the one Home and Rest show: the weekend schedule from a weekend night's
    /// evening until the next morning. Inside a timeline prefer `tonight(at:)` with the timeline's date.
    public var schedule: SleepSchedule { tonight(at: clock.now()) }

    /// Tonight's schedule at `date`: the night named by today's evening, until the next morning's start
    /// (`WeeklySleepSchedule.tonight(at:calendar:)`), in the collection's calendar.
    public func tonight(at date: Date) -> SleepSchedule {
        weekly.tonight(at: date, calendar: collection.context.calendar)
    }

    /// Reads the schedule again if it couldn't be read at launch.
    /// - Returns: Whether the store now holds the member's real schedule (or knows there is none).
    @discardableResult
    public func reloadIfUnavailable() -> Bool {
        guard !isAvailable else { return false }
        let saved: SavedSchedule?
        switch storage.read() {
        case .value(let value): saved = value
        case .absent: saved = nil
        case .unavailable: return false
        }
        isAvailable = true
        weekly = saved?.schedule ?? .standard
        savedAt = saved?.savedAt
        collection.schedule = weekly
        return true
    }

    public var hasSavedSchedule: Bool { savedAt != nil }

    /// Where the first run starts or picks up (spec §8.8): the schedule, the sprout with the waiting Sugar maple,
    /// or nothing (the tabs). Read it at launch to decide whether onboarding shows.
    public var firstRun: FirstRunStep {
        FirstRunStep.resume(hasSavedSchedule: hasSavedSchedule, firstLeaf: collection.firstLeaf)
    }

    /// Resumes a first run the app was stopped in. If the schedule was saved but the first leaf never made
    /// it into the collection (the app stopped between the two saves), this records it now; the award is
    /// idempotent, so the Sugar maple is never earned twice.
    /// - Returns: The step to show: `.schedule`, `.sprout` or `.finished` (never `.recordFirstLeaf`).
    @discardableResult
    public func resumeFirstRun(at date: Date) -> FirstRunStep {
        let step = firstRun
        guard step == .recordFirstLeaf else { return step }
        collection.raise(.firstLeaf, to: 1, at: date)
        let resumed = firstRun
        // Should the award still be missing, ask for the schedule again rather than stopping on an empty sprout.
        return resumed == .recordFirstLeaf ? .schedule : resumed
    }

    /// Saves the weekly schedule and applies it everywhere (phases, held reveals). Nights already under way are still
    /// judged by the schedule they began with (the 18:00 cut-off), so an edit applies from the next night. The first
    /// save plants the maple.
    /// - Returns: Leaves unlocked by this save: the Sugar maple the first time, otherwise nothing.
    @discardableResult
    public func save(_ schedule: WeeklySleepSchedule, at date: Date) -> [LeafUnlock] {
        if !isAvailable { reloadIfUnavailable() }
        let replaced = hasSavedSchedule ? weekly : nil
        weekly = schedule
        savedAt = date
        storage.save(SavedSchedule(schedule: schedule, savedAt: date))
        collection.scheduleSaved(schedule, replacing: replaced, at: date)
        return collection.raise(.firstLeaf, to: 1, at: date)
    }
}
