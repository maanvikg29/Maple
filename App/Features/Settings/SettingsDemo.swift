#if DEBUG
import Foundation
import MapleCore
import MapleServices

/// DEBUG only: Settings' Focus rows for simulator screenshots (docs/debug-launch-arguments.md). Pair it with
/// `-MapleDemoPresent profile -MapleDemoProfile settings`, and `-MapleDemoShip f1` for the Focus rows.
///
/// - `-MapleDemoSettingsOpen end` opens Settings scrolled to its end. `studyTime` also opens the daily study
///   reminder's time sheet, and `releaseAll` the "Release all apps?" confirmation, a second after the page appears.
/// - `-MapleDemoStudyReminder HH:MM` shows the study reminder saved at that time. It works on demo launches only, whose
///   settings live in memory.
@MainActor
enum SettingsDemo {
    enum Opening: String {
        case end
        case studyTime = "studytime"
        case releaseAll = "releaseall"
    }

    static var opening: Opening? {
        UserDefaults.standard.string(forKey: "MapleDemoSettingsOpen").flatMap { Opening(rawValue: $0.lowercased()) }
    }

    /// The Focus rows sit at the page's end.
    static var scrollsToEnd: Bool { opening != nil }

    static var studyReminder: ClockTime? {
        guard DemoLaunchOptions.current.isActive,
              let text = UserDefaults.standard.string(forKey: "MapleDemoStudyReminder")
        else { return nil }
        let fields = text.split(separator: ":").compactMap { Int($0) }
        guard fields.count == 2, (0..<24).contains(fields[0]), (0..<60).contains(fields[1]) else { return nil }
        return ClockTime(hour: fields[0], minute: fields[1])
    }
}
#endif
