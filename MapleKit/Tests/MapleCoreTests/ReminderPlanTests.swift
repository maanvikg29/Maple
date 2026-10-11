import Foundation
import Testing
@testable import MapleCore

@Suite("Reminder plan")
struct ReminderPlanTests {
    @Test("Wind-down fires at the wind-down start with the bedtime in its words")
    func windDown() {
        let reminder = ReminderPlan.windDownReminder(for: .standard, locale: enGB)
        #expect(reminder.kind == .windDown)
        #expect(reminder.time == ClockTime(hour: 22, minute: 15))
        #expect(reminder.title == "Time to wind down")
        #expect(reminder.body == "Bed at 23:00. Let the evening slow down.")
        #expect(!reminder.isQuiet)
    }

    @Test("Times follow the locale's clock")
    func twelveHour() {
        let reminder = ReminderPlan.windDownReminder(for: .standard, locale: enUS)
        #expect(reminder.body == "Bed at 11:00 PM. Let the evening slow down.")
    }

    @Test("A wind-down that starts before midnight for a bedtime after it wraps")
    func windDownWraps() {
        let late = SleepSchedule(bedtime: ClockTime(hour: 0, minute: 30), wake: ClockTime(hour: 8), windDownMinutes: 45)
        #expect(ReminderPlan.windDownReminder(for: late, locale: enGB).time == ClockTime(hour: 23, minute: 45))
    }

    @Test("The morning check-in is quiet and comes 30 minutes after wake")
    func morning() {
        let reminder = ReminderPlan.morningReminder(for: .standard)
        #expect(reminder.kind == .morning)
        #expect(reminder.time == ClockTime(hour: 7, minute: 30))
        #expect(reminder.isQuiet)

        let lateWake = SleepSchedule(bedtime: ClockTime(hour: 15), wake: ClockTime(hour: 23, minute: 45), windDownMinutes: 30)
        #expect(ReminderPlan.morningTime(for: lateWake) == ClockTime(hour: 0, minute: 15))
    }

    @Test("Only the wanted reminders are planned, wind-down first")
    func wanted() {
        let both = ReminderPlan.reminders(for: .standard, windDown: true, morning: true, locale: enGB)
        #expect(both.map(\.kind) == [.windDown, .morning])
        #expect(ReminderPlan.reminders(for: .standard, windDown: true, morning: false, locale: enGB).map(\.kind) == [.windDown])
        #expect(ReminderPlan.reminders(for: .standard, windDown: false, morning: true, locale: enGB).map(\.kind) == [.morning])
        #expect(ReminderPlan.reminders(for: .standard, windDown: false, morning: false, locale: enGB).isEmpty)
    }

    @Test("Reminders never mention leaves or progress (rewards.md)")
    func noLeaves() {
        let words = ReminderPlan.reminders(for: .standard, windDown: true, morning: true, locale: enGB)
            .flatMap { [$0.title, $0.body] }
            .joined(separator: " ")
            .lowercased()
        for word in ["leaf", "leaves", "streak", "progress", "earn"] {
            #expect(!words.contains(word))
        }
    }

    @Test("Each kind has its own stable identifier")
    func identifiers() {
        let identifiers = ReminderKind.allCases.map(\.identifier)
        #expect(Set(identifiers).count == ReminderKind.allCases.count)
        #expect(ReminderKind.windDown.identifier == "com.maanvikgupta.maple.reminder.windDown")
    }
}
