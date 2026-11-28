import Foundation

/// The words on the van's home view (syrup van design §5.1). Pure.
public struct VanHomeModel: Sendable, Equatable {
    public let greeting: String
    /// One line about what is waiting; empty while the van can't be read.
    public let status: String
    /// The counters; nil while the van's file can't be read, so nothing is shown rather than a zero that isn't true.
    public let leavesText: String?
    public let syrupText: String?
    /// The one button: the clock that sets the timer, or back to the session while one runs.
    public let enterTitle: String
    /// What that button does, for VoiceOver.
    public let enterHint: String
    /// A second line under the status when the pot has something to cook; nil otherwise, and while a session runs.
    public let potHint: String?
    /// "1h 20m saved today", under the time; nil under a minute, and while a session runs (its own line says so).
    public let savedToday: String?
    /// The same, in whole minutes, for VoiceOver to read in words.
    public let savedTodayMinutes: Int?

    /// - Parameters:
    ///   - hour: The hour on the clock, 0 to 23. Before the evening the greeting follows it: the schedule's "day"
    ///     starts three hours after waking, which for an early riser is still the morning.
    ///   - leaves: `WorkshopStore.leaves`.
    ///   - syrupTenths: `WorkshopStore.syrupTenths`.
    ///   - isAvailable: `WorkshopStore.isAvailable`.
    ///   - minutesLeft: The running session's minutes left; nil when none runs.
    ///   - savedTodaySeconds: Time saved today (`FocusStatus.savedTodaySeconds`): 0 when nothing counts.
    public init(
        phase: NowPhase, hour: Int, leaves: Int, syrupTenths: Int, isAvailable: Bool, minutesLeft: Int?,
        savedTodaySeconds: Int = 0
    ) {
        greeting = switch phase {
        case .morning, .day: hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        case .evening: "Good evening"
        case .windDown: "Winding down"
        case .night: "Good night"
        }
        enterHint = minutesLeft == nil ? "Opens the clock" : "Returns to your session"
        potHint = minutesLeft == nil && isAvailable && leaves > 0 ? "Tap the pot to cook a leaf" : nil
        if let minutesLeft {
            // No leaf count while a session runs (§6.5).
            status = "Session running · \(FocusTimeText.length(minutes: max(0, minutesLeft))) left"
        } else if !isAvailable {
            status = ""
        } else {
            status = switch max(0, leaves) {
            case 0: "Pip is out of leaves"
            case 1: "1 leaf waiting to cook"
            default: "\(leaves) leaves waiting to cook"
            }
        }
        enterTitle = minutesLeft == nil ? "Set the timer" : "Return to session"
        let savedMinutes = max(0, savedTodaySeconds) / 60
        savedTodayMinutes = minutesLeft == nil && savedMinutes > 0 ? savedMinutes : nil
        savedToday = savedTodayMinutes.map { "\(FocusTimeText.length(minutes: $0)) saved today" }
        leavesText = isAvailable ? "\(max(0, leaves))" : nil
        let tenths = max(0, syrupTenths)
        syrupText = isAvailable ? "\(tenths / 10).\(tenths % 10)" : nil
    }
}

extension NowState.Action {
    /// The van's home offers this beside its own button: wind-down, which was the tree home's one button at those
    /// moments. Never a leaf to open: the van has no leaf types (the owner, 28 Nov 2026: "i dont want the herbarium or
    /// any diff type of leaf"). The focus actions are the van's own button.
    public var showsOnVan: Bool {
        switch self {
        case .startWindDown, .returnToWindDown: true
        case .openReveals, .startFocus, .returnToSession, .turnOnBlocking: false
        }
    }
}
