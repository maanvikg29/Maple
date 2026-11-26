import Foundation

/// The session the van's clock starts (syrup van design §6.3, §6.4). Pure.
public enum VanTimer {
    /// The preset a start is made with. The van has no presets, breaks or strictness levels, but a start still needs a
    /// `FocusPreset`: this one is always Gentle with no break, and keeps the member's own app list and identity so the
    /// subject and the app list they chose carry on.
    public static func preset(from base: FocusPreset?) -> FocusPreset {
        var preset = base ?? FocusPreset(name: "Focus", verb: .focus, minutes: 50, hasBreak: false, appSetID: nil, strictness: .gentle)
        preset.name = "Focus"
        preset.verb = .focus
        preset.hasBreak = false
        preset.strictness = .gentle
        preset.pendingStrictness = nil
        preset.pendingFrom = nil
        return preset
    }

    /// "Start · 50m". Never a leaf count or a rate (§6.2).
    public static func startTitle(minutes: Int) -> String {
        "Start · \(FocusTimeText.length(minutes: minutes))"
    }

    /// The line under the block mode switch.
    public static func blockingLine(canBlock: Bool, wantsBlock: Bool, hasApps: Bool) -> String {
        if !canBlock { return "Plain timer · apps aren't locked" }
        if !wantsBlock { return "Block mode is off · apps aren't locked" }
        return hasApps ? "Blocking your chosen apps" : "Choose apps to block"
    }
}
