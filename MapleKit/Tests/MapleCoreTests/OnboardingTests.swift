import Foundation
import Testing
@testable import MapleCore

@Suite("Onboarding: questions, proposal and resuming")
struct OnboardingTests {
    @Test("The steps run questions, schedule, Apple Health, notifications, sprout; back only before the schedule is saved")
    func steps() {
        #expect(OnboardingStep.setup == [.weekdayWake, .weekendWake, .sleepNeed, .windDown, .schedule, .health, .notifications])
        var step = OnboardingStep.weekdayWake
        var order = [step]
        while step != .sprout {
            step = step.next
            order.append(step)
        }
        #expect(order == OnboardingStep.allCases)
        #expect(OnboardingStep.weekdayWake.previous == nil)
        #expect(OnboardingStep.weekendWake.previous == .weekdayWake)
        #expect(OnboardingStep.schedule.previous == .windDown)
        #expect(OnboardingStep.health.previous == nil)
        #expect(OnboardingStep.notifications.previous == nil)
        #expect(OnboardingStep.weekdayWake.progress == 1.0 / 7)
        #expect(OnboardingStep.notifications.progress == 1)
        #expect(OnboardingStep.sprout.progress == nil)
        #expect(OnboardingStep.allCases.filter(\.isQuestion) == [.weekdayWake, .weekendWake, .sleepNeed, .windDown])
    }

    @Test("Bedtime is the wake time less the sleep need and 15 minutes to fall asleep, per variant")
    func proposal() {
        var answers = OnboardingAnswers()
        #expect(answers.weekdayWake == ClockTime(hour: 7))
        #expect(answers.sleepNeedMinutes == 450)
        #expect(answers.windDownMinutes == 45)
        #expect(answers.proposedSchedule == .everyNight(SleepSchedule(bedtime: ClockTime(hour: 23, minute: 15), wake: ClockTime(hour: 7), windDownMinutes: 45)))
        #expect(answers.suggestedWeekendWake == ClockTime(hour: 8))

        answers.weekendWake = ClockTime(hour: 9)
        answers.sleepNeedMinutes = 480
        answers.windDownMinutes = 60
        let week = answers.proposedSchedule
        #expect(week.weekday == SleepSchedule(bedtime: ClockTime(hour: 22, minute: 45), wake: ClockTime(hour: 7), windDownMinutes: 60))
        // The weekend bedtime wraps past midnight.
        #expect(week.weekend == SleepSchedule(bedtime: ClockTime(hour: 0, minute: 45), wake: ClockTime(hour: 9), windDownMinutes: 60))

        // An early riser with a long need goes to bed in the evening; a weekend "later" equal to weekdays is no split.
        answers = OnboardingAnswers(weekdayWake: ClockTime(hour: 5, minute: 30), weekendWake: ClockTime(hour: 5, minute: 30), sleepNeedMinutes: 540, windDownMinutes: 30)
        #expect(answers.proposedSchedule == .everyNight(SleepSchedule(bedtime: ClockTime(hour: 20, minute: 15), wake: ClockTime(hour: 5, minute: 30), windDownMinutes: 30)))
        #expect(OnboardingAnswers(weekdayWake: ClockTime(hour: 23, minute: 30)).suggestedWeekendWake == ClockTime(hour: 0, minute: 30))
        #expect(OnboardingAnswers.sleepNeedChoices.map { HomeFormat.duration(minutes: $0) } == ["7h", "7h 30m", "8h", "8h 30m", "9h"])
    }

    @Test("A relaunch resumes on the same question; once the schedule is saved it is never asked again")
    func resume() {
        let sugarMaple = LeafUnlock(speciesID: "saccharum", date: at(2026, 10, 1, 22), season: .autumn, colourway: .autumn)
        var placed = sugarMaple
        placed.revealed = true

        var progress = OnboardingProgress()
        #expect(progress.resume(hasSavedSchedule: false, firstLeaf: nil) == .weekdayWake)
        progress.step = .sleepNeed
        #expect(progress.resume(hasSavedSchedule: false, firstLeaf: nil) == .sleepNeed)
        progress.step = .schedule
        #expect(progress.resume(hasSavedSchedule: false, firstLeaf: nil) == .schedule)
        // A step past the schedule with no schedule on file asks for the schedule (the Sugar maple needs it).
        progress.step = .notifications
        #expect(progress.resume(hasSavedSchedule: false, firstLeaf: nil) == .schedule)

        // Saved: the questions and the schedule are done, whatever step the file names.
        progress.step = .windDown
        #expect(progress.resume(hasSavedSchedule: true, firstLeaf: sugarMaple) == .health)
        #expect(progress.resume(hasSavedSchedule: true, firstLeaf: nil) == .health)
        #expect(progress.resume(hasSavedSchedule: false, firstLeaf: sugarMaple) == .health)
        progress.healthAnswered = true
        #expect(progress.resume(hasSavedSchedule: true, firstLeaf: sugarMaple) == .notifications)
        progress.notificationsAnswered = true
        #expect(progress.resume(hasSavedSchedule: true, firstLeaf: sugarMaple) == .sprout)
        // The Sugar maple on the tree: the first run is over.
        #expect(progress.resume(hasSavedSchedule: true, firstLeaf: placed) == nil)
        #expect(OnboardingProgress().resume(hasSavedSchedule: true, firstLeaf: placed) == nil)
    }

    @Test("The schedule step opens on the member's draft, else the proposal")
    func draft() {
        var progress = OnboardingProgress()
        #expect(progress.scheduleShown == progress.answers.proposedSchedule)
        #expect(progress.isProposal)
        let mine = WeeklySleepSchedule.everyNight(SleepSchedule(bedtime: ClockTime(hour: 22), wake: ClockTime(hour: 6), windDownMinutes: 30))
        progress.scheduleDraft = mine
        #expect(progress.scheduleShown == mine)
        #expect(!progress.isProposal)
    }

    @Test("Progress survives a save; missing or unknown values take their defaults")
    func coding() throws {
        let progress = OnboardingProgress(
            step: .sleepNeed,
            answers: OnboardingAnswers(weekdayWake: ClockTime(hour: 6, minute: 45), weekendWake: ClockTime(hour: 8, minute: 30), sleepNeedMinutes: 510, windDownMinutes: 60),
            scheduleDraft: .standard, healthAnswered: true
        )
        let data = try JSONEncoder().encode(progress)
        #expect(try JSONDecoder().decode(OnboardingProgress.self, from: data) == progress)

        let odd = Data(#"{"step":"tour","answers":{"sleepNeedMinutes":200,"windDownMinutes":90}}"#.utf8)
        let decoded = try JSONDecoder().decode(OnboardingProgress.self, from: odd)
        #expect(decoded == OnboardingProgress())
        #expect(try JSONDecoder().decode(OnboardingProgress.self, from: Data("{}".utf8)) == OnboardingProgress())
    }
}
