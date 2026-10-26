#if DEBUG
import Foundation
import Testing
@testable import MapleCore
@testable import MapleServices

@Suite("Fake app picker")
struct PickerChoiceTests {
    @Test("Ticked samples make the summary, and the choice reads back from the list's selection as it was")
    func roundTrip() {
        var choice = PickerChoice()
        choice.toggle("app.shorts")
        choice.toggle("app.photos")
        choice.toggle("site.video")
        let summary = choice.summary(mode: .blockThese)
        #expect(summary == SelectionSummary(mode: .blockThese, apps: 2, sites: 1, categories: 0))
        #expect(PickerChoice(data: choice.data, summary: summary) == choice)
        choice.toggle("app.shorts")
        choice.toggle("category.games")
        #expect(choice.summary(mode: .onlyThese) == SelectionSummary(mode: .onlyThese, apps: 1, sites: 1, categories: 1))
    }

    @Test("The bulk row counts 45 apps, to reach the 50-app limit")
    func bulk() {
        var choice = PickerChoice()
        for sample in PickerChoice.samples.filter({ $0.kind == .app }).prefix(6) {
            choice.toggle(sample.id)
        }
        choice.bulk = true
        #expect(choice.summary(mode: .blockThese).apps == 51)
    }

    @Test("A list the picker didn't write shows its summary's counts as the first samples")
    func seeded() {
        let six = SelectionSummary(mode: .blockThese, apps: 6, sites: 1, categories: 0)
        let choice = PickerChoice(data: Data("seeded".utf8), summary: six)
        #expect(choice.summary(mode: .blockThese) == six)
        #expect(choice.picked.contains("app.shorts") && choice.picked.contains("site.video"))
        #expect(choice.otherApps == 0)
        let wide = PickerChoice(data: Data(), summary: SelectionSummary(mode: .onlyThese, apps: 24, sites: 0, categories: 0))
        #expect(wide.otherApps == 12)
        #expect(wide.summary(mode: .onlyThese).apps == 24)
        let none = SelectionSummary(mode: .blockThese, apps: 0, sites: 0, categories: 0)
        #expect(PickerChoice(data: Data(), summary: none) == PickerChoice())
    }

    @Test("The same choice is the same bytes, whatever order it was ticked in")
    func stableData() {
        var first = PickerChoice()
        first.toggle("app.shorts")
        first.toggle("app.news")
        var second = PickerChoice()
        second.toggle("app.news")
        second.toggle("app.shorts")
        #expect(first.data == second.data)
    }

    @Test("12 apps, 3 sites and 3 categories, each id once")
    func samples() {
        let samples = PickerChoice.samples
        #expect(samples.filter { $0.kind == .app }.count == 12)
        #expect(samples.filter { $0.kind == .site }.count == 3)
        #expect(samples.filter { $0.kind == .category }.count == 3)
        #expect(Set(samples.map(\.id)).count == samples.count)
    }
}
#endif
