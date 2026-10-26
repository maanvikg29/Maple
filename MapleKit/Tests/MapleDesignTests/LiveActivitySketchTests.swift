import CoreGraphics
import Foundation
import MapleActivity
import MapleCore
import SwiftUI
import Testing
@testable import MapleDesign

@Suite("Live Activity leaf and tint")
struct LiveActivitySketchTests {
    private func sketch(_ id: String) throws -> LeafSketch {
        let skeleton = LeafGeometry.of(try #require(LeafCatalog.shared.species(id: id))).placedSkeleton
        return LeafSketch(outlines: skeleton.outlines, veins: skeleton.veins, stalk: skeleton.stalk, frame: skeleton.frame)
    }

    @Test("Every species' sketch fits the Live Activity's payload", arguments: LeafCatalog.shared.species.map(\.id))
    func fits(id: String) throws {
        let sketch = try sketch(id)
        #expect(sketch.outlinePointCount <= LeafSketch.maximumOutlinePoints)
        let attributes = FocusActivityAttributes(sessionID: UUID(), tintRGB: 0x9CC3A4, leaf: sketch)
        #expect(try JSONEncoder().encode(attributes).count < 2048)
        #expect(try JSONDecoder().decode(FocusActivityAttributes.self, from: JSONEncoder().encode(attributes)).leaf == sketch)
    }

    @Test("Every species' sketch keeps its leaf's shape: the same box, every vein and the stalk",
          arguments: LeafCatalog.shared.species.map(\.id))
    func keepsShape(id: String) throws {
        let geometry = LeafGeometry.of(try #require(LeafCatalog.shared.species(id: id)))
        let skeleton = geometry.placedSkeleton
        let sketch = try sketch(id)
        let box = CGRect(x: 0, y: 0, width: 255, height: 255)
        let drawn = Array(sketch.outlines(in: box).joined())
        let frame = skeleton.frame
        let original = skeleton.outlines.joined().map {
            CGPoint(x: ($0.x - frame.minX) / frame.width * 255, y: ($0.y - frame.minY) / frame.height * 255)
        }
        func extent(_ points: [CGPoint], _ edge: KeyPath<CGPoint, CGFloat>) throws -> ClosedRange<CGFloat> {
            let low = try #require(points.map { $0[keyPath: edge] }.min())
            let high = try #require(points.map { $0[keyPath: edge] }.max())
            return low...high
        }
        for edge in [\CGPoint.x, \CGPoint.y] {
            let kept = try extent(drawn, edge)
            let full = try extent(original, edge)
            let miss = max(abs(kept.lowerBound - full.lowerBound), abs(kept.upperBound - full.upperBound))
            #expect(miss <= 1, "\(id) misses its box by \(miss)")
        }
        #expect(sketch.veins(in: box).count == geometry.veins.count)
        #expect(sketch.stalk(in: box).count == 7)
        #expect(drawn.allSatisfy { box.insetBy(dx: -0.01, dy: -0.01).contains($0) })
    }

    @Test("The Lock Screen tint is the season tint token, for every season")
    @MainActor
    func tints() {
        let environment = EnvironmentValues()
        for season in Season.allCases {
            #expect(Color(Theme.SeasonTints.leafColor(for: season)).resolve(in: environment)
                == Theme.maple.colors.seasonTint(season).resolve(in: environment))
        }
    }
}
