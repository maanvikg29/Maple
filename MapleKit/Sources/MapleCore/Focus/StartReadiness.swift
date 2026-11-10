import Foundation
import MapleFocusCore

/// Whether a start from Home or the receipt's Again can go straight ahead, or must open the start screen to say
/// something first (F1 design §5.1, F1-20).
public enum StartReadiness: Sendable, Hashable {
    /// One tap starts it; Locked needs a hold, everywhere.
    case ready(needsHold: Bool)
    case needsStartScreen(Reason)

    /// What the start screen would show, in the order it is checked.
    public enum Reason: Sendable, Hashable {
        case blockingUnavailable, noAppSet, notQualifying, expiredTokens, firstSession, windDown
        case afterBedtime, capReached, crossesBedtime
    }

    public static func check(
        strictness: Strictness, blockingAllowed: Bool, selection: SelectionSummary?, expiredTokens: Bool,
        isFirstSession: Bool, phase: NowPhase, countsLine: SessionForecast.CountsLine
    ) -> StartReadiness {
        guard blockingAllowed else { return .needsStartScreen(.blockingUnavailable) }
        guard let selection, !selection.isEmpty else { return .needsStartScreen(.noAppSet) }
        guard selection.qualifies else { return .needsStartScreen(.notQualifying) }
        if expiredTokens { return .needsStartScreen(.expiredTokens) }
        if isFirstSession { return .needsStartScreen(.firstSession) }
        if phase == .windDown || phase == .night { return .needsStartScreen(.windDown) }
        switch countsLine {
        case .afterBedtime: return .needsStartScreen(.afterBedtime)
        case .capReached: return .needsStartScreen(.capReached)
        case .untilBed: return .needsStartScreen(.crossesBedtime)
        case .hidden, .definition, .reaches, .toward: return .ready(needsHold: strictness == .locked)
        }
    }
}
