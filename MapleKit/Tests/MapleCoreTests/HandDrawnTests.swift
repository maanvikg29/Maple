import Foundation
import Testing
@testable import MapleCore

@Suite("Hand-drawn outlines: a little wobble and ink that thickens and thins, so the van's buttons look drawn")
struct HandDrawnTests {
    private func distance(_ a: HandDrawn.Point, _ b: HandDrawn.Point) -> Double { hypot(a.x - b.x, a.y - b.y) }

    @Test("A rounded box's outline goes all the way round it, evenly spaced, inside its frame")
    func roundedBox() {
        let points = HandDrawn.roundedRect(width: 200, height: 60, radius: 22, step: 4)
        #expect(points.count > 100)
        #expect(points.allSatisfy { $0.x >= -0.001 && $0.x <= 200.001 && $0.y >= -0.001 && $0.y <= 60.001 })
        let gaps = zip(points, points.dropFirst() + [points[0]]).map { distance($0, $1) }
        #expect(gaps.allSatisfy { $0 > 1 && $0 < 6 })
        // It reaches every side.
        #expect(points.contains { $0.y < 0.01 } && points.contains { $0.y > 59.99 })
        #expect(points.contains { $0.x < 0.01 } && points.contains { $0.x > 199.99 })
        // A radius bigger than the box allows is a capsule, not a mistake.
        let capsule = HandDrawn.roundedRect(width: 100, height: 40, radius: 90, step: 4)
        #expect(capsule.allSatisfy { $0.y >= -0.001 && $0.y <= 40.001 })
    }

    @Test("An ellipse's outline goes round it")
    func ellipse() {
        let points = HandDrawn.ellipse(width: 44, height: 44, step: 3)
        #expect(points.count >= 40)
        #expect(points.allSatisfy { abs(distance($0, .init(x: 22, y: 22)) - 22) < 0.01 })
    }

    @Test("The wobble is small, smooth, closes on itself and is the same every time for the same seed")
    func wobble() {
        let points = HandDrawn.roundedRect(width: 240, height: 64, radius: 22, step: 3)
        let wobbled = HandDrawn.wobbled(points, seed: 7, wobble: 1.2)
        #expect(wobbled.count == points.count)
        let pushed = zip(points, wobbled).map { distance($0, $1) }
        #expect(pushed.allSatisfy { $0 <= 1.2 + 1e-9 })
        // Not perfect: it really moves.
        #expect(pushed.max()! > 0.6)
        // Smooth: neighbours move together; and where it ends it meets where it began.
        let moves = zip(points, wobbled).map { HandDrawn.Point(x: $1.x - $0.x, y: $1.y - $0.y) }
        for (a, b) in zip(moves, moves.dropFirst() + [moves[0]]) {
            #expect(hypot(a.x - b.x, a.y - b.y) < 0.6)
        }
        #expect(HandDrawn.wobbled(points, seed: 7, wobble: 1.2) == wobbled)
        #expect(HandDrawn.wobbled(points, seed: 8, wobble: 1.2) != wobbled)
        #expect(HandDrawn.wobbled(points, seed: 7, wobble: 0) == points)
    }

    @Test("The ink is a ribbon round the line: about as wide as asked, thicker and thinner along the way, never gone")
    func ink() {
        let line = HandDrawn.wobbled(HandDrawn.ellipse(width: 60, height: 60, step: 2), seed: 3, wobble: 0.8)
        let ink = HandDrawn.ink(line, seed: 3, width: 2.6, variation: 0.3)
        #expect(ink.outer.count == line.count && ink.inner.count == line.count)
        let widths = zip(ink.outer, ink.inner).map { distance($0, $1) }
        #expect(widths.allSatisfy { $0 >= 2.6 * 0.7 - 1e-6 && $0 <= 2.6 * 1.3 + 1e-6 })
        #expect(widths.max()! - widths.min()! > 0.5)
        let mean = widths.reduce(0, +) / Double(widths.count)
        #expect(abs(mean - 2.6) < 0.35)
        // The line runs down the middle of the ribbon.
        for (index, point) in line.enumerated() {
            let middle = HandDrawn.Point(x: (ink.outer[index].x + ink.inner[index].x) / 2, y: (ink.outer[index].y + ink.inner[index].y) / 2)
            #expect(distance(point, middle) < 1e-6)
        }
    }

    @Test("Nothing to draw, or sizes that aren't numbers, give nothing rather than a crash")
    func edges() {
        #expect(HandDrawn.roundedRect(width: 0, height: 40, radius: 8, step: 4).isEmpty)
        #expect(HandDrawn.roundedRect(width: .nan, height: 40, radius: 8, step: 4).isEmpty)
        #expect(HandDrawn.ellipse(width: 30, height: 30, step: 0).isEmpty)
        #expect(HandDrawn.wobbled([], seed: 1, wobble: 1).isEmpty)
        #expect(HandDrawn.ink([], seed: 1, width: 2, variation: 0.3).outer.isEmpty)
    }
}
