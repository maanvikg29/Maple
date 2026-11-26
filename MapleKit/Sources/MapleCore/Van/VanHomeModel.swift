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

    /// - Parameters:
    ///   - leaves: `WorkshopStore.leaves`.
    ///   - syrupTenths: `WorkshopStore.syrupTenths`.
    ///   - isAvailable: `WorkshopStore.isAvailable`.
    ///   - minutesLeft: The running session's minutes left; nil when none runs.
    public init(phase: NowPhase, leaves: Int, syrupTenths: Int, isAvailable: Bool, minutesLeft: Int?) {
        greeting = switch phase {
        case .morning: "Good morning"
        case .day: "Good afternoon"
        case .evening: "Good evening"
        case .windDown: "Winding down"
        case .night: "Good night"
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
