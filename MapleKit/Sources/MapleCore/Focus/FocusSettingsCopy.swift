import Foundation

/// Settings' Focus rows (F1 design §5.12, §6): the session-end switch, the daily study reminder and its time sheet, and
/// "Release all apps". The release's own title and its confirmation are `FocusCopy.ReleaseAll`.
public enum FocusSettingsCopy {
    public static let sessionEndTitle = "Session end"
    public static let sessionEndDetail = "When a session ends, with its length."

    public static let studyTitle = "Daily study reminder"
    /// Under the switch while it is off.
    public static let studyOff = "Once a day, at a time you choose."

    /// "At 16:00, unless a session has already started that day."
    public static func studyOn(_ time: ClockTime, locale: Locale) -> String {
        "At \(HomeFormat.clock(time, locale: locale)), unless a session has already started that day."
    }

    /// A saved time that a schedule change has put outside the Day phase: "21:00 is outside your day now. Choose a time
    /// from 10:00 to 20:14."
    public static func studyOutsideDay(_ time: ClockTime, window: StudyReminderWindow, locale: Locale) -> String {
        "\(HomeFormat.clock(time, locale: locale)) is outside your day now. "
            + "Choose a time from \(HomeFormat.clock(window.earliest, locale: locale)) to \(HomeFormat.clock(window.latest, locale: locale))."
    }

    /// The schedule leaves no time in the Day phase every day.
    public static let studyNoDaytime = "Your sleep schedule leaves no daytime for it."

    /// The line under the study reminder's switch, which never says more than the switch shows:
    /// - no daytime in the schedule: `studyNoDaytime`;
    /// - a saved time while notifications are allowed: `studyOn`, or `studyOutsideDay` once it has left the Day phase;
    /// - otherwise (nothing saved, or iOS not asked or turned off, so the switch rests off): `studyOff`.
    public static func studyDetail(_ time: ClockTime?, window: StudyReminderWindow?, isAllowed: Bool, locale: Locale) -> String {
        guard let window else { return studyNoDaytime }
        guard isAllowed, let time else { return studyOff }
        return window.contains(time) ? studyOn(time, locale: locale) : studyOutsideDay(time, window: window, locale: locale)
    }
    public static let studyChangeTime = "Change time"

    /// The time sheet's line: "Any time from 10:00 to 20:14."
    public static func studyRange(_ window: StudyReminderWindow, locale: Locale) -> String {
        "Any time from \(HomeFormat.clock(window.earliest, locale: locale)) to \(HomeFormat.clock(window.latest, locale: locale))."
    }

    public static let save = "Save"
    public static let close = "Close"

    /// Under "Release all apps".
    public static let releaseAllDetail = "If an app stays locked after a session ends, this opens it."
    /// The same line once every app has been released from Settings, also announced to VoiceOver.
    public static let releaseAllDone = "Every app is open again."
}
