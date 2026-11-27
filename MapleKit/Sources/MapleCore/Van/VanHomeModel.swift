import Foundation

/// The words on the van's home view (syrup van design §5.1). Pure.
public struct VanHomeModel: Sendable, Equatable {
    public let greeting: String
    /// One line about what is waiting; empty while the van can't be read.
    public let status: String
    /// The counters; nil while the van's file can't be read, so nothing is shown rather than a zero that isn't true.
    public let leavesText: String?
    public let syrupText: String?
    /// The one button: into the van, or back to the session while one runs.
    public let enterTitle: String
    /// The workshop's one line: what the gauge does now, with the time left while a session runs.
    public let workshopHint: String
    /// What a tap on the gauge does, for VoiceOver.
    public let gaugeHint: String

    /// - Parameters:
    ///   - hour: The hour on the clock, 0 to 23. Before the evening the greeting follows it: the schedule's "day"
    ///     starts three hours after waking, which for an early riser is still the morning.
    ///   - leaves: `WorkshopStore.leaves`.
    ///   - syrupTenths: `WorkshopStore.syrupTenths`.
    ///   - isAvailable: `WorkshopStore.isAvailable`.
    ///   - minutesLeft: The running session's minutes left; nil when none runs.
    public init(phase: NowPhase, hour: Int, leaves: Int, syrupTenths: Int, isAvailable: Bool, minutesLeft: Int?) {
        greeting = switch phase {
        case .morning, .day: hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        case .evening: "Good evening"
        case .windDown: "Winding down"
        case .night: "Good night"
        }
        if let minutesLeft {
            workshopHint = "Session running · \(FocusTimeText.length(minutes: max(0, minutesLeft))) left. Tap the gauge to go back to it"
            gaugeHint = "Returns to your session"
        } else {
            workshopHint = isAvailable && leaves > 0
                ? "Tap the gauge to set the timer, or the pot to cook a leaf" : "Tap the gauge to set the timer"
            gaugeHint = "Opens the clock"
        }
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
        enterTitle = minutesLeft == nil ? "Open the van" : "Return to session"
        leavesText = isAvailable ? "\(max(0, leaves))" : nil
        let tenths = max(0, syrupTenths)
        syrupText = isAvailable ? "\(tenths / 10).\(tenths % 10)" : nil
    }

    /// The gauge's face in the workshop: the length that would start now.
    public static func gaugeText(minutes: Int) -> String {
        FocusTimeText.length(minutes: minutes)
    }
}

extension NowState.Action {
    /// The van's home offers this beside its own button: the waiting leaves' reveal and wind-down, which were the tree
    /// home's one button at those moments. The focus actions are the van's own button and gauge.
    public var showsOnVan: Bool {
        switch self {
        case .openReveals, .startWindDown, .returnToWindDown: true
        case .startFocus, .returnToSession, .turnOnBlocking: false
        }
    }
}
