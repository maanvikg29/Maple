import Foundation
@testable import MapleCore

/// Shared builders for focus tests. Later suites add to it in their own files.
enum FocusFixtures {
    static let device = UUID(uuidString: "00000000-0000-4000-8000-0000000000D1")!
    static let session = UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!

    static func window(_ day: Int = 23, month: Int = 10) -> AwakeWindow {
        AwakeWindow(start: at(2026, month, day, 6), end: at(2026, month, day, 23), windDown: at(2026, month, day, 22, 15))
    }

    static let blockSix = SelectionSummary(mode: .blockThese, apps: 6, sites: 0, categories: 0)

    static func plan(
        minutes: Int = 50, breakMinutes: Int = 0, strictness: Strictness = .steady, kind: SessionKind = .blocking,
        selection: SelectionSummary? = FocusFixtures.blockSix, day: String = "2026-10-23",
        window: AwakeWindow = FocusFixtures.window()
    ) -> FocusPlan {
        FocusPlan(
            presetID: UUID(uuidString: "00000000-0000-4000-8000-00000000F001")!, presetName: "Study", verb: .study,
            plannedSeconds: minutes * 60, breakSeconds: breakMinutes * 60, strictness: strictness, kind: kind,
            appSetID: nil, selection: selection, startedFrom: .focusTab, mapleDay: day, window: window, zone: "UTC",
            appBuild: "1", rulesVersion: FocusRules.version
        )
    }
}
