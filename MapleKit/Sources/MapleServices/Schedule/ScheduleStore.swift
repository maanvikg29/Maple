import Foundation
import MapleCore
import Observation

/// A saved sleep schedule and when it was last saved.
nonisolated public struct SavedSchedule: Codable, Sendable, Equatable {
    public var schedule: SleepSchedule
    public var savedAt: Date

    public init(schedule: SleepSchedule, savedAt: Date) {
        self.schedule = schedule
        self.savedAt = savedAt
    }
}

/// The member's sleep schedule (wake, bedtime, wind-down length). Screens read it with
/// `@Environment(ScheduleStore.self)` and change it with one call, `save(_:at:)`.
///
/// Until the member saves one, `schedule` is `SleepSchedule.standard` and `hasSavedSchedule` is false. Saving the
/// first schedule records First steps and unlocks the Sugar maple ("Set your sleep schedule"), the leaf revealed
/// at the end of onboarding (D12).
@Observable
public final class ScheduleStore {
    public private(set) var schedule: SleepSchedule
    /// When the schedule was last saved; nil until the member saves one.
    public private(set) var savedAt: Date?
    /// False while the schedule file exists but can't be read yet (before the first unlock after a restart): the
    /// store then shows the standard schedule, never saves over the file, and `reloadIfUnavailable()` reads it.
    public private(set) var isAvailable: Bool

    @ObservationIgnored private let storage: JSONStorage<SavedSchedule>
    @ObservationIgnored private let collection: CollectionStore

    public init(storage: JSONStorage<SavedSchedule>, collection: CollectionStore) {
        self.storage = storage
        self.collection = collection
        let read = storage.read()
        let saved: SavedSchedule? = if case .value(let value) = read { value } else { nil }
        if case .unavailable = read { isAvailable = false } else { isAvailable = true }
        schedule = saved?.schedule ?? .standard
        savedAt = saved?.savedAt
        collection.schedule = schedule
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
        schedule = saved?.schedule ?? .standard
        savedAt = saved?.savedAt
        collection.schedule = schedule
        return true
    }

    public var hasSavedSchedule: Bool { savedAt != nil }

    /// Where the first run starts or picks up (spec §8.8): the schedule, the sprout with the waiting Sugar maple,
    /// or nothing (the tabs). Read it at launch to decide whether onboarding shows.
    public var firstRun: FirstRunStep {
        FirstRunStep.resume(hasSavedSchedule: hasSavedSchedule, firstLeaf: collection.firstLeaf)
    }

    /// Resumes a first run the app was stopped in. If the schedule was saved but the First-steps leaf never made
    /// it into the collection (the app stopped between the two saves), this records it now; the award is
    /// idempotent, so the Sugar maple is never earned twice.
    /// - Returns: The step to show: `.schedule`, `.sprout` or `.finished` (never `.recordFirstLeaf`).
    @discardableResult
    public func resumeFirstRun(at date: Date) -> FirstRunStep {
        let step = firstRun
        guard step == .recordFirstLeaf else { return step }
        collection.raise(.firstSteps, to: 1, at: date)
        let resumed = firstRun
        // Should the award still be missing, ask for the schedule again rather than stopping on an empty sprout.
        return resumed == .recordFirstLeaf ? .schedule : resumed
    }

    /// Saves the schedule and applies it everywhere (phases, held reveals). Nights already under way are still judged
    /// by the schedule they began with. The first save plants the maple.
    /// - Returns: Leaves unlocked by this save: the Sugar maple the first time, otherwise nothing.
    @discardableResult
    public func save(_ schedule: SleepSchedule, at date: Date) -> [LeafUnlock] {
        if !isAvailable { reloadIfUnavailable() }
        let replaced = hasSavedSchedule ? self.schedule : nil
        self.schedule = schedule
        savedAt = date
        storage.save(SavedSchedule(schedule: schedule, savedAt: date))
        collection.scheduleSaved(schedule, replacing: replaced, at: date)
        return collection.raise(.firstSteps, to: 1, at: date)
    }
}
