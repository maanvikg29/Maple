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

    @ObservationIgnored private let storage: JSONStorage<SavedSchedule>
    @ObservationIgnored private let collection: CollectionStore

    public init(storage: JSONStorage<SavedSchedule>, collection: CollectionStore) {
        self.storage = storage
        self.collection = collection
        let saved = storage.load()
        schedule = saved?.schedule ?? .standard
        savedAt = saved?.savedAt
        collection.schedule = schedule
    }

    public var hasSavedSchedule: Bool { savedAt != nil }

    /// Saves the schedule and applies it everywhere (phases, held reveals). The first save plants the maple.
    /// - Returns: Leaves unlocked by this save: the Sugar maple the first time, otherwise nothing.
    @discardableResult
    public func save(_ schedule: SleepSchedule, at date: Date) -> [LeafUnlock] {
        self.schedule = schedule
        savedAt = date
        storage.save(SavedSchedule(schedule: schedule, savedAt: date))
        collection.schedule = schedule
        return collection.raise(.firstSteps, to: 1, at: date)
    }
}
