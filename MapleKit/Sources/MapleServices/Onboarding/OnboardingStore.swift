import Foundation
import MapleCore
import Observation

/// The first run's progress (`OnboardingProgress`): the screen the member is on, their answers, the schedule draft and
/// which primers they have answered, saved as `onboarding.json` after every change so a relaunch resumes on the same
/// screen. One instance for the app, injected with `.environment(_:)`; onboarding reads it with
/// `@Environment(OnboardingStore.self)`.
///
/// ```swift
/// onboarding.step(schedule: schedule, collection: collection)   // the screen to show now (nil: the tabs)
/// onboarding.answers.sleepNeedMinutes = 480                     // saves at once
/// onboarding.go(to: .sleepNeed)
/// onboarding.answered(.health)                                  // "Not now" or Apple's sheet closed
/// ```
///
/// The schedule and the Sugar maple live in their own stores; once a schedule is saved the questions and the
/// schedule never show again, whatever this file says.
@Observable
public final class OnboardingStore {
    nonisolated public static let file = "onboarding.json"

    public private(set) var progress: OnboardingProgress
    /// False while the file exists but can't be read yet (before the first unlock after a restart).
    public private(set) var isAvailable: Bool

    @ObservationIgnored private let storage: JSONStorage<OnboardingProgress>

    public init(storage: JSONStorage<OnboardingProgress>) {
        self.storage = storage
        switch storage.read() {
        case .value(let saved):
            progress = saved
            isAvailable = true
        case .absent:
            progress = OnboardingProgress()
            isAvailable = true
        case .unavailable:
            progress = OnboardingProgress()
            isAvailable = false
        }
    }

    /// Reads the file again if it couldn't be read at launch.
    /// - Returns: Whether the store now holds the member's real progress (or knows there is none).
    @discardableResult
    public func reloadIfUnavailable() -> Bool {
        guard !isAvailable else { return false }
        switch storage.read() {
        case .value(let saved): progress = saved
        case .absent: progress = OnboardingProgress()
        case .unavailable: return false
        }
        isAvailable = true
        return true
    }

    // MARK: Reading

    /// The screen to show, from this file and what the schedule and collection say (`OnboardingProgress.resume`):
    /// nil once the Sugar maple is on the tree.
    public func step(schedule: ScheduleStore, collection: CollectionStore) -> OnboardingStep? {
        progress.resume(hasSavedSchedule: schedule.hasSavedSchedule, firstLeaf: collection.firstLeaf)
    }

    /// The answers so far. Setting them saves at once (`setAnswers(_:)`).
    public var answers: OnboardingAnswers {
        get { progress.answers }
        set { setAnswers(newValue) }
    }

    /// The schedule "Your sleep schedule" shows: the member's draft, else the answers' proposal.
    public var scheduleShown: WeeklySleepSchedule { progress.scheduleShown }

    // MARK: Changes

    /// The member moved to `step` (Continue or the back circle).
    public func go(to step: OnboardingStep) {
        change { $0.step = step }
    }

    /// Keeps "Your sleep schedule" as the member left it; the proposal itself is never stored as a draft, so changing
    /// an answer afterwards proposes again.
    public func setScheduleDraft(_ draft: WeeklySleepSchedule) {
        change { $0.scheduleDraft = draft == $0.answers.proposedSchedule ? nil : draft }
    }

    /// Changing an answer proposes a new schedule, so a draft made from the old answers is dropped.
    public func setAnswers(_ answers: OnboardingAnswers) {
        change { progress in
            guard progress.answers != answers else { return }
            progress.answers = answers
            progress.scheduleDraft = nil
        }
    }

    /// The member answered a primer: Apple Health or notifications.
    public func answered(_ step: OnboardingStep) {
        change { progress in
            switch step {
            case .health: progress.healthAnswered = true
            case .notifications: progress.notificationsAnswered = true
            default: break
            }
            progress.step = step.next
        }
    }

    // MARK: Launch

    /// The member's progress file in `directory`.
    public static func live(directory: URL = MapleContainer.directory()) -> OnboardingStore {
        OnboardingStore(storage: JSONStorage(.file(directory.appending(path: file))))
    }

    /// What this launch should use. DEBUG demo launches get an in-memory copy (an empty one for `-MapleDemoFresh`),
    /// like every other store, so a demo never writes the real file.
    public static func launch(directory: URL = MapleContainer.directory()) -> OnboardingStore {
        #if DEBUG
        let options = DemoLaunchOptions.current
        if options.isActive {
            let saved = options.fresh ? nil : JSONStorage<OnboardingProgress>(.file(directory.appending(path: file))).load()
            return OnboardingStore(storage: JSONStorage(.memory, initial: saved))
        }
        #endif
        return live(directory: directory)
    }

    // MARK: Private

    private func change(_ edit: (inout OnboardingProgress) -> Void) {
        // A change lands on the member's real progress, never on launch defaults saved over an unreadable file.
        if !isAvailable { reloadIfUnavailable() }
        var copy = progress
        edit(&copy)
        guard copy != progress else { return }
        progress = copy
        storage.save(copy)
    }
}
