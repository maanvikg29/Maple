import Foundation

/// Where the reveal's leaves go, in words. On the night look they are placed on the member's maple; with the van
/// (syrup van design) home is the van and there is no maple to place them on, so they go into the herbarium, where
/// every earned leaf is kept.
nonisolated public enum RevealCopy {
    /// The reveal's last button.
    public static func place(_ look: Theme.Look) -> String {
        switch look {
        case .night: "Place on your maple"
        case .van: "Add to your herbarium"
        }
    }

    /// VoiceOver's line once the button is tapped: "Sugar maple and Vine maple added to your herbarium."
    public static func placed(_ names: [String], _ look: Theme.Look) -> String {
        let list = names.formatted(.list(type: .and))
        switch look {
        case .night: return "\(list) placed on your maple."
        case .van: return "\(list) added to your herbarium."
        }
    }
}
