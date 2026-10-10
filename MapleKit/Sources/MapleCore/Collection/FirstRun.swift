import Foundation

/// Where the first run (spec §8.8, D12) starts or picks up after the app was stopped part-way through it.
///
/// The first run is: save the sleep schedule (which earns the First-steps leaf, the Sugar maple), open it from the
/// sprout's bud, then "Place on your maple". Each step is saved as it happens, so a relaunch resumes from what the
/// files say, never asks for the schedule twice and never awards the Sugar maple twice.
public enum FirstRunStep: Sendable, Equatable {
    /// Nothing saved yet: "Your sleep schedule".
    case schedule
    /// The schedule was saved, but the app stopped before the First-steps leaf was recorded (the two are separate
    /// files). Record it (idempotent: `ScheduleStore.resumeFirstRun(at:)`), then show the sprout.
    case recordFirstLeaf
    /// The Sugar maple is earned and still waiting: the sprout with its bud, then the reveal and "Place on your maple".
    case sprout
    /// The Sugar maple is on the tree: the first run is over and the tabs show.
    case finished

    /// Whether the app opens on the end of onboarding instead of the tabs.
    public var needsOnboarding: Bool { self != .finished }

    /// The pure gate decision.
    /// - Parameters:
    ///   - hasSavedSchedule: The member has saved a sleep schedule.
    ///   - firstLeaf: The First-steps unlock (the Sugar maple), opened or not; nil when it hasn't been earned.
    public static func resume(hasSavedSchedule: Bool, firstLeaf: LeafUnlock?) -> FirstRunStep {
        if let firstLeaf {
            // Earning the leaf is what saving the schedule does, so an unlock means the schedule step is done even if
            // its own file is missing.
            return firstLeaf.revealed ? .finished : .sprout
        }
        return hasSavedSchedule ? .recordFirstLeaf : .schedule
    }

    /// The First-steps leaf's species: the Sugar maple.
    public static var firstLeafID: String {
        RewardCatalog.shared.rungs(in: .firstSteps).first?.speciesID ?? "saccharum"
    }
}

extension CollectionSnapshot {
    /// The First-steps unlock (the Sugar maple), opened or not.
    public var firstLeaf: LeafUnlock? {
        unlocks.first { RevealSchedule.isFirstSteps($0.speciesID) }
    }

    /// The Sugar maple is opened and on the tree: the first run is over. `hasPlantedMaple` turns true earlier, when
    /// saving the schedule earns the leaf.
    public var hasPlacedFirstLeaf: Bool {
        firstLeaf?.revealed == true
    }
}
