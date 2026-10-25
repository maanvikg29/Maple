#if DEBUG
import Foundation

/// DEBUG only: the sleep pieces' launch arguments (docs/debug-launch-arguments.md), so the schedule editor and
/// wind-down mode can be screenshotted in the simulator without tapping. Release builds never read them.
enum SleepDemo {
    /// What the schedule editor opens with: a time's wheel, and the nights segment.
    struct EditorRequest: Equatable {
        var field: ScheduleEditor.Field?
        var nights: ScheduleEditor.Nights?
    }

    private static var editorTaken = false

    /// `-MapleDemoPresent schedule` (the editor at `.medium`, on Every day or tonight's nights), `schedule:bedtime` and
    /// `schedule:wake` (at `.large` with that time's wheel open), `schedule:everyday`, `schedule:weekdays` and
    /// `schedule:weekends` (on that segment). `App/DemoPresenter.swift` opens Settings in the Profile sheet for them;
    /// Settings takes the request here, once per launch.
    static func takeScheduleEditor() -> EditorRequest? {
        guard !editorTaken, opensScheduleEditor else { return nil }
        editorTaken = true
        return EditorRequest(field: openField, nights: openNights)
    }

    /// `-MapleDemoGoodnight YES`: wind-down mode opens as if Goodnight had just been tapped, so it dims to black
    /// 10 seconds after launch.
    static var saysGoodnight: Bool {
        UserDefaults.standard.bool(forKey: "MapleDemoGoodnight")
    }

    private static var opensScheduleEditor: Bool {
        presentation == "schedule" || openField != nil || openNights != nil
    }

    private static var openField: ScheduleEditor.Field? {
        switch presentation {
        case "schedule:bedtime": .bedtime
        case "schedule:wake": .wake
        default: nil
        }
    }

    private static var openNights: ScheduleEditor.Nights? {
        switch presentation {
        case "schedule:everyday": .everyNight
        case "schedule:weekdays": .weekdays
        case "schedule:weekends": .weekends
        default: nil
        }
    }

    private static var presentation: String? {
        UserDefaults.standard.string(forKey: "MapleDemoPresent")
    }
}
#endif
