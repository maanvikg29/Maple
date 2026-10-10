#if DEBUG
import Foundation

/// DEBUG only: the Rest-owned launch arguments from docs/debug-launch-arguments.md, so every Rest state can be
/// screenshotted in the simulator without tapping. Release builds never read them.
enum RestDemo {
    /// `-MapleDemoPresent schedule` opens the schedule editor on the Rest tab; `schedule:bedtime` and
    /// `schedule:wake` open it with that time's picker showing.
    static var opensScheduleEditor: Bool {
        presentation == "schedule" || openField != nil || openNights != nil
    }

    static var openField: ScheduleEditor.Field? {
        switch presentation {
        case "schedule:bedtime": .bedtime
        case "schedule:wake": .wake
        default: nil
        }
    }

    /// `schedule:everyday`, `schedule:weekdays` and `schedule:weekends` open the editor on that segment.
    static var openNights: ScheduleEditor.Nights? {
        switch presentation {
        case "schedule:everyday": .everyNight
        case "schedule:weekdays": .weekdays
        case "schedule:weekends": .weekends
        default: nil
        }
    }

    /// `-MapleDemoGoodnight YES`: wind-down mode opens as if Goodnight had just been tapped, so it dims to black
    /// 10 seconds after launch.
    static var saysGoodnight: Bool {
        UserDefaults.standard.bool(forKey: "MapleDemoGoodnight")
    }

    private static var presentation: String? {
        UserDefaults.standard.string(forKey: "MapleDemoPresent")
    }
}
#endif
