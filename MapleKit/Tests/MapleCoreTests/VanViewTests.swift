import Foundation
import Testing
@testable import MapleCore

@Suite("Moving the van's picture about: pinch to zoom, drag to pan")
struct VanViewTests {
    private let width = 400.0
    private let height = 800.0

    @Test("Pinching about the middle zooms in and leaves the middle where it was")
    func zoomAboutCentre() {
        let view = VanView.fit.zoomed(by: 2, aroundX: 200, y: 400, width: width, height: height)
        #expect(view == VanView(zoom: 2, x: 0, y: 0))
        #expect(!view.isFit && VanView.fit.isFit)
    }

    @Test("Pinching about a corner keeps that corner under the fingers")
    func zoomAboutCorner() {
        let view = VanView.fit.zoomed(by: 2, aroundX: 0, y: 0, width: width, height: height)
        #expect(view == VanView(zoom: 2, x: 200, y: 400))
        // Already at its limit, so letting go changes nothing.
        #expect(view.settled(width: width, height: height) == view)
    }

    @Test("Letting go brings the picture back inside its limits: never smaller than the screen, never more than three times")
    func settles() {
        let far = VanView.fit.zoomed(by: 10, aroundX: 200, y: 400, width: width, height: height)
        #expect(far.settled(width: width, height: height).zoom == VanView.maxZoom)
        let small = VanView.fit.zoomed(by: 0.2, aroundX: 200, y: 400, width: width, height: height)
        #expect(small.settled(width: width, height: height) == .fit)
        // Zoomed twice, the picture can move half a screen each way and no further.
        let dragged = VanView(zoom: 2, x: 0, y: 0).moved(byX: 900, y: -900).settled(width: width, height: height)
        #expect(dragged == VanView(zoom: 2, x: 200, y: -400))
        // Not zoomed, there is nowhere to go: it comes back.
        #expect(VanView.fit.moved(byX: 120, y: 40).settled(width: width, height: height) == .fit)
        // Barely zoomed counts as not zoomed.
        #expect(VanView(zoom: 1.03, x: 4, y: 2).settled(width: width, height: height) == .fit)
    }

    @Test("While the fingers are down the picture's edge never shows: it stops at the screen's edge and never gets smaller than the screen")
    func neverShowsItsEdge() {
        // The owner, 28 Nov 2026: "why is this tree ending it should be smooth and continued".
        let pulled = VanView.fit.moved(byX: 90, y: -30).shown(width: width, height: height)
        #expect(pulled == .fit)
        let pastTheSide = VanView(zoom: 2, x: 500, y: -900).shown(width: width, height: height)
        #expect(pastTheSide == VanView(zoom: 2, x: 200, y: -400))
        let inside = VanView(zoom: 2, x: 50, y: 0).shown(width: width, height: height)
        #expect(inside == VanView(zoom: 2, x: 50, y: 0))
        let pinchedOut = VanView(zoom: 0.4, x: 30, y: 0).shown(width: width, height: height)
        #expect(pinchedOut == .fit)
        // Past the closest zoom there is no edge to show, so it still gives a little there.
        let pinchedIn = VanView(zoom: 5, x: 0, y: 0).shown(width: width, height: height)
        #expect(pinchedIn.zoom > VanView.maxZoom && pinchedIn.zoom < 5)
    }

    @Test("Numbers that aren't numbers change nothing")
    func nonsense() {
        #expect(VanView.fit.zoomed(by: .nan, aroundX: 0, y: 0, width: width, height: height) == .fit)
        #expect(VanView.fit.zoomed(by: 0, aroundX: 0, y: 0, width: width, height: height) == .fit)
        #expect(VanView.fit.moved(byX: .infinity, y: 0) == .fit)
        #expect(VanView(zoom: 2, x: 10, y: 10).settled(width: 0, height: 0) == .fit)
    }

    @Test("A tap on the screen is a place in the picture")
    func source() {
        let canvas = VanCanvas.home
        let at = canvas.source(x: 191, y: 305, width: 464, height: 1009)
        #expect(at.x == 764 && at.y == 1220)
        let none = canvas.source(x: 10, y: 10, width: 0, height: 0)
        #expect(none.x == 0 && none.y == 0)
    }

    @Test("What a tap on home's picture does: the pot cooks, the boiler is the machines, the van is the timer, the maple is the tree")
    func targets() {
        #expect(VanHomeTarget.at(x: 764, y: 1220) == .pot)
        #expect(VanHomeTarget.at(x: 990, y: 1100) == .machines)
        #expect(VanHomeTarget.at(x: 1500, y: 1700) == .timer)
        #expect(VanHomeTarget.at(x: 300, y: 400) == .maple)
        #expect(VanHomeTarget.at(x: 1700, y: 300) == nil)
        #expect(VanHomeTarget.at(x: 900, y: 2250) == nil)
        #expect(VanHomeTarget.at(x: .nan, y: 0) == nil)
    }
}
