import Testing
@testable import MapleCore

@Suite("Placing the van's art on a screen")
struct VanCanvasTests {
    @Test("The art fills the screen: it is scaled by whichever side needs more, and centred")
    func fills() {
        let canvas = VanCanvas(width: 1600, height: 3460, originX: 0, originY: -1000)
        // A screen of the same shape: scale is exact and nothing is cut.
        #expect(canvas.scale(width: 400, height: 865) == 0.25)
        let origin = canvas.point(x: 0, y: -1000, width: 400, height: 865)
        #expect(origin.x == 0 && origin.y == 0)
        // A wider screen: the width decides, and the art is centred top to bottom.
        #expect(canvas.scale(width: 800, height: 865) == 0.5)
        let middle = canvas.point(x: 800, y: 730, width: 800, height: 865)
        #expect(middle.x == 400 && middle.y == 432.5)
        #expect(canvas.length(104, width: 400, height: 865) == 26)
    }

    @Test("A canvas that doesn't start at zero places its own corner at the screen's")
    func corner() {
        let canvas = VanCanvas(width: 1140, height: 2470, originX: 150, originY: -80)
        let corner = canvas.point(x: 150, y: -80, width: 285, height: 617.5)
        #expect(corner.x == 0 && corner.y == 0)
        let inside = canvas.point(x: 921, y: 985, width: 285, height: 617.5)
        #expect(inside.x == 192.75 && inside.y == 266.25)
    }

    @Test("The pot on home's stove lands where the picture has it")
    func homePot() {
        let pot = VanCanvas.home.point(x: 764, y: 1220, width: 464, height: 1009)
        #expect(pot.x == 191 && pot.y == 305)
    }

    @Test("Home is the concept picture at the top of a tall page: its full width, its corner at the screen's")
    func homePicture() {
        let canvas = VanCanvas.home
        #expect(canvas.width == 1856 && VanCanvas.homePictureHeight == 2304)
        // A phone's shape: the picture's width is the screen's, and the sky's colour carries on below it.
        let scale = canvas.scale(width: 464, height: 1009)
        #expect(scale == 0.25)
        let corner = canvas.point(x: 0, y: 0, width: 464, height: 1009)
        #expect(corner.x == 0 && corner.y == 0)
        #expect(VanCanvas.homePictureHeight * scale < 1009 * 0.6)
    }

    @Test("A screen with no size places everything at the origin instead of dividing by nothing")
    func empty() {
        let canvas = VanCanvas.home
        #expect(canvas.scale(width: 0, height: 0) == 0)
        let point = canvas.point(x: 720, y: 881, width: 0, height: 0)
        #expect(point.x == 0 && point.y == 0)
    }
}
