import Foundation
import Testing
@testable import MapleCore

@Suite("Focus plans")
struct FocusPlanTests {
    @Test("Block these: any app, site or category qualifies; an empty list doesn't (R3, F1-14)")
    func blockThese() {
        #expect(SelectionSummary(mode: .blockThese, apps: 1, sites: 0, categories: 0).qualifies)
        #expect(SelectionSummary(mode: .blockThese, apps: 0, sites: 1, categories: 0).qualifies)
        #expect(SelectionSummary(mode: .blockThese, apps: 0, sites: 0, categories: 1).qualifies)
        #expect(!SelectionSummary(mode: .blockThese, apps: 0, sites: 0, categories: 0).qualifies)
        #expect(SelectionSummary(mode: .blockThese, apps: 0, sites: 0, categories: 0).isEmpty)
    }

    @Test("Only these: no allowed categories and at most 20 apps or sites")
    func onlyThese() {
        #expect(SelectionSummary(mode: .onlyThese, apps: 20, sites: 0, categories: 0).qualifies)
        #expect(SelectionSummary(mode: .onlyThese, apps: 12, sites: 8, categories: 0).qualifies)
        #expect(!SelectionSummary(mode: .onlyThese, apps: 21, sites: 0, categories: 0).qualifies)
        #expect(!SelectionSummary(mode: .onlyThese, apps: 3, sites: 0, categories: 1).qualifies)
    }

    @Test("More than 50 app or web tokens never qualifies, because iOS would block nothing")
    func tokenLimit() {
        #expect(SelectionSummary(mode: .blockThese, apps: 50, sites: 50, categories: 0).qualifies)
        #expect(!SelectionSummary(mode: .blockThese, apps: 51, sites: 0, categories: 0).qualifies)
        #expect(!SelectionSummary(mode: .blockThese, apps: 0, sites: 51, categories: 0).withinTokenLimit)
    }

    @Test("A plan counts only when it blocks a qualifying selection")
    func canCount() {
        #expect(FocusFixtures.plan().canCount)
        #expect(!FocusFixtures.plan(kind: .plainTimer).canCount)
        #expect(!FocusFixtures.plan(selection: nil).canCount)
        #expect(!FocusFixtures.plan(selection: SelectionSummary(mode: .blockThese, apps: 0, sites: 0, categories: 0)).canCount)
    }

    @Test("Plans round-trip through JSON")
    func codable() throws {
        let plan = FocusFixtures.plan(minutes: 90, breakMinutes: 5, strictness: .locked)
        let decoded = try JSONDecoder().decode(FocusPlan.self, from: try JSONEncoder().encode(plan))
        #expect(decoded == plan)
        #expect(decoded.plannedMinutes == 90)
    }

    @Test("Strictness orders gentle, steady, locked")
    func strictnessOrder() {
        #expect(Strictness.gentle < .steady)
        #expect(Strictness.steady < .locked)
    }

    @Test("The awake window holds its start and not its end")
    func window() {
        let window = FocusFixtures.window()
        #expect(window.contains(at(2026, 10, 23, 6)))
        #expect(window.contains(at(2026, 10, 23, 22, 59)))
        #expect(!window.contains(at(2026, 10, 23, 23)))
        #expect(window.interval.duration == 17 * 3600)
    }

    @Test("Each verb's capsule title")
    func verbs() {
        #expect(FocusVerb.study.startTitle == "Start study")
        #expect(FocusVerb.quick.startTitle == "Start a quick session")
        #expect(FocusVerb.deep.startTitle == "Start a deep session")
        #expect(FocusVerb.reading.startTitle == "Start reading")
        #expect(FocusVerb.focus.startTitle == "Start focus")
    }
}
