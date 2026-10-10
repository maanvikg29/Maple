import CoreGraphics
import Testing
@testable import MapleDesign

/// `HeroFit`: how a screen's hero yields height so the first screen stays above the floating tab bar (spec §3.1, §9).
@Suite("Hero fit")
struct HeroFitTests {
    @Test("The hero keeps its preferred height while everything fits")
    func roomy() {
        let fit = HeroFit(preferred: 280, minimum: 160, visible: 700, content: 200, action: 84)
        #expect(fit == HeroFit(heroHeight: 280, pinsAction: false))
    }

    @Test("It yields just enough, rounded down, leaving the minimum gap above the tab bar")
    func yields() {
        let fit = HeroFit(preferred: 280, minimum: 160, visible: 600, content: 300.5, action: 84)
        #expect(!fit.pinsAction)
        #expect(fit.heroHeight == (600 - 300.5 - 84 - HeroFit.minimumBottomGap).rounded(.down))
        #expect(fit.heroHeight + 300.5 + 84 + HeroFit.minimumBottomGap <= 600)
    }

    @Test("Below its minimum the hero stops yielding and the action is pinned; without one nothing is")
    func pins() {
        #expect(HeroFit(preferred: 280, minimum: 160, visible: 500, content: 300, action: 84)
            == HeroFit(heroHeight: 160, pinsAction: true))
        #expect(HeroFit(preferred: 280, minimum: 160, visible: 500, content: 400, action: 0)
            == HeroFit(heroHeight: 160, pinsAction: false))
        // Exactly the minimum still fits in the flow.
        let exact = 160 + 300 + 84 + HeroFit.minimumBottomGap
        #expect(HeroFit(preferred: 280, minimum: 160, visible: exact, content: 300, action: 84)
            == HeroFit(heroHeight: 160, pinsAction: false))
    }

    @Test("Unmeasured content, or no visible height yet, keeps the preferred height")
    func unmeasured() {
        #expect(HeroFit(preferred: 280, minimum: 160, visible: 400, content: nil, action: 84)
            == HeroFit(heroHeight: 280, pinsAction: false))
        #expect(HeroFit(preferred: 280, minimum: 160, visible: 0, content: 300, action: 84)
            == HeroFit(heroHeight: 280, pinsAction: false))
        // A minimum above the preferred height never grows the hero.
        #expect(HeroFit(preferred: 120, minimum: 160, visible: 300, content: 250, action: 84).heroHeight == 120)
    }

    /// Review finding "rest-pinned-layout-wastes-space".
    @Test("A page fills the first screen while it fits, and keeps its natural height once the action is pinned")
    func pageHeight() {
        let fits = HeroFit(preferred: 280, minimum: 160, visible: 700, content: 200, action: 84)
        #expect(fits.pageMinHeight(visible: 700) == 700)
        let pinned = HeroFit(preferred: 280, minimum: 160, visible: 500, content: 300, action: 84)
        #expect(pinned.pinsAction)
        #expect(pinned.pageMinHeight(visible: 500) == nil)
    }
}
