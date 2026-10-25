#if DEBUG
import Foundation
import MapleCore
import MapleServices

/// DEBUG only: the Focus tab's launch arguments that set the tab's own state (docs/debug-launch-arguments.md). The
/// stores' state comes from `FocusStores.demo(collection:clock:options:)` instead. They are applied once per launch,
/// and only when the app opens on the Focus tab (`-MapleDemoTab focus`):
/// - `-MapleDemoFocus minimised`: the running session tucked away, on the start screen;
/// - `-MapleDemoPreset study|quick|deep|read`: that chip selected;
/// - `-MapleDemoIntention <text>`: "What's this for?" filled in;
/// - `-MapleDemoScreenTime failStart`: the start screen as just after a lock that failed, offering the plain timer;
/// - `-MapleDemoScreenTime plain`: the plain timer chosen (with `-MapleDemoFocus idle`, the start screen as a plain timer);
/// - `-MapleDemoPresent blocking|preset|saved|streak|intention`: that sheet over the tab.
enum FocusDemoPresenter {
    private static var applied = false

    static func apply(
        to tab: FocusTabState, presets: PresetStore, options: DemoLaunchOptions = .current, defaults: UserDefaults = .standard
    ) {
        guard !applied, defaults.string(forKey: "MapleDemoTab") == AppTab.focus.rawValue else { return }
        applied = true
        if options.focus == .minimised { tab.isMinimised = true }
        if let verb = options.preset { tab.selectedPresetID = presets.presets.first { $0.verb == verb }?.id }
        if let intention = options.intention { tab.intention = intention }
        if options.screenTime == .failStart { tab.plainTimer = .lockFailed }
        if options.screenTime == .plain { tab.plainTimer = .chosen }
        if let sheet = options.focusSheet { tab.sheet = Self.sheet(sheet, tab: tab, presets: presets) }
    }

    private static func sheet(_ sheet: FocusDemo.Sheet, tab: FocusTabState, presets: PresetStore) -> FocusTabSheet {
        switch sheet {
        case .blocking: .blocking
        case .preset: .preset(tab.selectedPresetID ?? presets.lastUsed?.id)
        case .saved: .saved
        case .streak: .streak
        case .intention: .intention
        }
    }
}
#endif
