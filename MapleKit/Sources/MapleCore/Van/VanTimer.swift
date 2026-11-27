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

    /// The line under the block mode switch, when blocking is either available and allowed or not available at all.
    public static func blockingLine(canBlock: Bool, wantsBlock: Bool, hasApps: Bool) -> String {
        VanBlocking(buildCanBlock: canBlock, isAllowed: canBlock, wantsBlock: wantsBlock, hasApps: hasApps).line
    }

    /// The length the clock opens on and the gauge shows: the one last set on the clock, else the last preset's, else
    /// 50 minutes; always a length the clock allows.
    /// - Parameter saved: The length last set (`van.minutes`); 0 or less when none has been.
    public static func length(saved: Int, preset: Int?) -> Int {
        ClockSetting(minutes: saved > 0 ? saved : preset ?? 50).minutes
    }
}

/// What block mode will do at the next start (syrup van design §6.3, §6.4). Pure.
public enum VanBlocking: Sendable, Equatable {
    /// A free-tier build without Apple's Family Controls permission: every session is a plain timer.
    case unavailable
    /// The build can block, but Screen Time hasn't been turned on for Maple.
    case needsScreenTime
    /// The member switched block mode off.
    case off
    /// On, with nothing in the app list: choosing comes before the start.
    case chooseApps
    case on

    /// - Parameters:
    ///   - buildCanBlock: `BlockingCapability.canBlock`.
    ///   - isAllowed: Screen Time allows Maple (`BlockingProbe.isAllowed`).
    ///   - hasApps: The app list has something in it (`SelectionSummary.isEmpty` is false).
    public init(buildCanBlock: Bool, isAllowed: Bool, wantsBlock: Bool, hasApps: Bool) {
        if !buildCanBlock {
            self = .unavailable
        } else if !isAllowed {
            self = .needsScreenTime
        } else if !wantsBlock {
            self = .off
        } else {
            self = hasApps ? .on : .chooseApps
        }
    }

    public var line: String {
        switch self {
        case .unavailable: "Plain timer · apps aren't locked"
        case .needsScreenTime: "Screen Time is off · apps aren't locked"
        case .off: "Block mode is off · apps aren't locked"
        case .chooseApps: "Choose apps to block"
        case .on: "Blocking your chosen apps"
        }
    }

    /// A start made now locks nothing.
    public var startsPlainTimer: Bool {
        switch self {
        case .unavailable, .needsScreenTime, .off: true
        case .chooseApps, .on: false
        }
    }

    /// The switch can be turned: blocking is there to turn on or off.
    public var canSwitch: Bool {
        switch self {
        case .unavailable, .needsScreenTime: false
        case .off, .chooseApps, .on: true
        }
    }

    /// The word at the end of the line's row, when the row does something.
    public var rowAction: String? {
        switch self {
        case .unavailable, .off: nil
        case .needsScreenTime: "Turn on"
        case .chooseApps: "Choose"
        case .on: "Change"
        }
    }
}
