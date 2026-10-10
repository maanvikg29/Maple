import Foundation

/// The first run's screens, in order (spec §8.8). Four questions, one per screen; "Your sleep schedule", which opens
/// with a schedule proposed from the answers and whose save earns the First-steps leaf (the Sugar maple); the Apple
/// Health primer; the notifications primer; then the sprout, the reveal and "Place on your maple".
public enum OnboardingStep: String, Codable, Sendable, CaseIterable {
    /// "When do you need to be up on weekdays?"
    case weekdayWake
    /// "And on weekends?": the same time, or later.
    case weekendWake
    /// "How much sleep feels best?"
    case sleepNeed
    /// "How long do you like to wind down?"
    case windDown
    /// "Your sleep schedule": the proposal, adjustable; "Save schedule" earns the Sugar maple.
    case schedule
    /// The Apple Health primer ("Not now" allowed).
    case health
    /// The notifications primer.
    case notifications
    /// The sprout with its bud, the Sugar maple's reveal and "Place on your maple".
    case sprout

    /// The steps before the sprout, each with its place on the progress hairline.
    public static let setup: [OnboardingStep] = [.weekdayWake, .weekendWake, .sleepNeed, .windDown, .schedule, .health, .notifications]

    public var isQuestion: Bool {
        switch self {
        case .weekdayWake, .weekendWake, .sleepNeed, .windDown: true
        case .schedule, .health, .notifications, .sprout: false
        }
    }

    /// How far along the progress hairline this step is (1 / 7 on the first question); nil for the sprout, which has
    /// no hairline.
    public var progress: Double? {
        Self.setup.firstIndex(of: self).map { Double($0 + 1) / Double(Self.setup.count) }
    }

    /// The step the back circle returns to: questions and the schedule only. Once the schedule is saved there is no
    /// way back to it, so it is never asked twice.
    public var previous: OnboardingStep? {
        switch self {
        case .weekdayWake, .health, .notifications, .sprout: nil
        case .weekendWake: .weekdayWake
        case .sleepNeed: .weekendWake
        case .windDown: .sleepNeed
        case .schedule: .windDown
        }
    }

    /// The step after this one.
    public var next: OnboardingStep {
        switch self {
        case .weekdayWake: .weekendWake
        case .weekendWake: .sleepNeed
        case .sleepNeed: .windDown
        case .windDown: .schedule
        case .schedule: .health
        case .health: .notifications
        case .notifications, .sprout: .sprout
        }
    }
}

/// The member's answers to the onboarding questions, and the schedule they propose.
public struct OnboardingAnswers: Codable, Sendable, Hashable {
    /// "When do you need to be up on weekdays?"
    public var weekdayWake: ClockTime
    /// "And on weekends?": nil for "Same time".
    public var weekendWake: ClockTime?
    /// "How much sleep feels best?": the sleep need behind Full nights (Settings › Sleep goal).
    public var sleepNeedMinutes: Int
    /// "How long do you like to wind down?"
    public var windDownMinutes: Int

    /// 7h, 7h 30m, 8h, 8h 30m, 9h (rewards.json `full_nights`: "adjustable 7–9 h").
    public static let sleepNeedChoices = [420, 450, 480, 510, 540]
    /// 7h 30m (rewards.json `full_nights`: "default 7 h 30 min").
    public static let defaultSleepNeedMinutes = 450
    /// 30m, 45m, 1h: the schedule editor's wind-down lengths.
    public static let windDownChoices = [30, 45, 60]
    /// Time to fall asleep, left between bedtime and the start of the sleep need.
    public static let fallAsleepMinutes = 15

    public init(
        weekdayWake: ClockTime = SleepSchedule.standard.wake, weekendWake: ClockTime? = nil,
        sleepNeedMinutes: Int = OnboardingAnswers.defaultSleepNeedMinutes,
        windDownMinutes: Int = SleepSchedule.standard.windDownMinutes
    ) {
        self.weekdayWake = weekdayWake
        self.weekendWake = weekendWake
        self.sleepNeedMinutes = sleepNeedMinutes
        self.windDownMinutes = windDownMinutes
    }

    /// The weekend wake the "Later" wheel starts on: an hour after the weekday wake.
    public var suggestedWeekendWake: ClockTime {
        Self.clock(weekdayWake.minutesSinceMidnight + 60)
    }

    /// The schedule the answers propose, per variant: bedtime = wake − sleep need − 15 minutes to fall asleep, with
    /// the chosen wind-down. A weekend wake equal to the weekday one proposes the same schedule every night.
    public var proposedSchedule: WeeklySleepSchedule {
        WeeklySleepSchedule(weekday: proposal(waking: weekdayWake), weekend: weekendWake.map(proposal(waking:)))
    }

    /// One night's proposal for a wake time.
    public func proposal(waking wake: ClockTime) -> SleepSchedule {
        let bedtime = Self.clock(wake.minutesSinceMidnight - sleepNeedMinutes - Self.fallAsleepMinutes)
        return SleepSchedule(bedtime: bedtime, wake: wake, windDownMinutes: windDownMinutes)
    }

    private static func clock(_ minutes: Int) -> ClockTime {
        let wrapped = ((minutes % (24 * 60)) + 24 * 60) % (24 * 60)
        return ClockTime(hour: wrapped / 60, minute: wrapped % 60)
    }

    // MARK: Codable (tolerant: missing or unreadable values take their defaults)

    private enum CodingKeys: String, CodingKey {
        case weekdayWake, weekendWake, sleepNeedMinutes, windDownMinutes
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = OnboardingAnswers()
        weekdayWake = (try? c.decodeIfPresent(ClockTime.self, forKey: .weekdayWake)) ?? defaults.weekdayWake
        weekendWake = (try? c.decodeIfPresent(ClockTime.self, forKey: .weekendWake)) ?? nil
        let need = (try? c.decodeIfPresent(Int.self, forKey: .sleepNeedMinutes)) ?? defaults.sleepNeedMinutes
        sleepNeedMinutes = Self.sleepNeedChoices.contains(need) ? need : defaults.sleepNeedMinutes
        let windDown = (try? c.decodeIfPresent(Int.self, forKey: .windDownMinutes)) ?? defaults.windDownMinutes
        windDownMinutes = Self.windDownChoices.contains(windDown) ? windDown : defaults.windDownMinutes
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(weekdayWake, forKey: .weekdayWake)
        try c.encodeIfPresent(weekendWake, forKey: .weekendWake)
        try c.encode(sleepNeedMinutes, forKey: .sleepNeedMinutes)
        try c.encode(windDownMinutes, forKey: .windDownMinutes)
    }
}

/// How far the member is through the first run, saved after every step so a relaunch resumes where they were: the
/// screen, the answers, the schedule draft on "Your sleep schedule", and which primers they have been through.
///
/// What the other files say wins: once a schedule is saved (or the Sugar maple earned) the questions and the schedule
/// are never shown again, and once the Sugar maple is on the tree the first run is over (`FirstRunStep`).
public struct OnboardingProgress: Codable, Sendable, Hashable {
    /// The screen the member was on.
    public var step: OnboardingStep
    public var answers: OnboardingAnswers
    /// "Your sleep schedule" as the member left it, when they changed the proposal; nil shows the proposal.
    public var scheduleDraft: WeeklySleepSchedule?
    /// The member answered the Apple Health primer (Continue or "Not now").
    public var healthAnswered: Bool
    /// The member answered the notifications primer.
    public var notificationsAnswered: Bool

    public init(
        step: OnboardingStep = .weekdayWake, answers: OnboardingAnswers = OnboardingAnswers(),
        scheduleDraft: WeeklySleepSchedule? = nil, healthAnswered: Bool = false, notificationsAnswered: Bool = false
    ) {
        self.step = step
        self.answers = answers
        self.scheduleDraft = scheduleDraft
        self.healthAnswered = healthAnswered
        self.notificationsAnswered = notificationsAnswered
    }

    /// The step to show, given what the other files say.
    /// - Parameters:
    ///   - hasSavedSchedule: The member has saved a sleep schedule.
    ///   - firstLeaf: The First-steps unlock (the Sugar maple), opened or not.
    /// - Returns: Nil once the Sugar maple is on the tree (the first run is over). With a schedule saved: the first
    ///   primer not yet answered, else the sprout. Otherwise the saved question or the schedule (a saved step past
    ///   the schedule without a schedule on file asks for the schedule, which the Sugar maple needs).
    public func resume(hasSavedSchedule: Bool, firstLeaf: LeafUnlock?) -> OnboardingStep? {
        if firstLeaf?.revealed == true { return nil }
        if hasSavedSchedule || firstLeaf != nil {
            if !healthAnswered { return .health }
            if !notificationsAnswered { return .notifications }
            return .sprout
        }
        return step.isQuestion ? step : .schedule
    }

    /// The schedule "Your sleep schedule" opens with: the member's own draft, else the answers' proposal.
    public var scheduleShown: WeeklySleepSchedule {
        scheduleDraft ?? answers.proposedSchedule
    }

    /// The draft differs from the proposal ("Proposed from your answers" then no longer applies).
    public var isProposal: Bool {
        scheduleDraft == nil || scheduleDraft == answers.proposedSchedule
    }

    // MARK: Codable (tolerant: missing or unknown values take their defaults)

    private enum CodingKeys: String, CodingKey {
        case step, answers, scheduleDraft, healthAnswered, notificationsAnswered
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        step = (try? c.decodeIfPresent(String.self, forKey: .step)).flatMap(OnboardingStep.init(rawValue:)) ?? .weekdayWake
        answers = (try? c.decodeIfPresent(OnboardingAnswers.self, forKey: .answers)) ?? OnboardingAnswers()
        scheduleDraft = (try? c.decodeIfPresent(WeeklySleepSchedule.self, forKey: .scheduleDraft)) ?? nil
        healthAnswered = (try? c.decodeIfPresent(Bool.self, forKey: .healthAnswered)) ?? false
        notificationsAnswered = (try? c.decodeIfPresent(Bool.self, forKey: .notificationsAnswered)) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(step, forKey: .step)
        try c.encode(answers, forKey: .answers)
        try c.encodeIfPresent(scheduleDraft, forKey: .scheduleDraft)
        try c.encode(healthAnswered, forKey: .healthAnswered)
        try c.encode(notificationsAnswered, forKey: .notificationsAnswered)
    }
}
