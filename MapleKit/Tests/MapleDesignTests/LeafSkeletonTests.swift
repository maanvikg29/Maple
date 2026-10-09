import CoreGraphics
import Foundation
import MapleCore
import SwiftUI
import Testing
@testable import MapleDesign

private let allIDs = LeafCatalog.shared.species.map(\.id)

/// Locked leaves: `LeafStyle.skeleton` and `LeafView.progressFill` (docs/design/spec.md, "One specimen grammar").
@Suite("Leaf skeletons and progress fill")
@MainActor
struct LeafSkeletonTests {
    private func species(_ id: String) throws -> LeafSpecies {
        try #require(LeafCatalog.shared.species(id: id))
    }

    /// A view rendered at `side` × `side` points, scale 1, as straight RGBA rows (top row first).
    private func pixels(of view: some View, side: Int) throws -> [UInt8] {
        let renderer = ImageRenderer(content: view.frame(width: CGFloat(side), height: CGFloat(side)))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        try #require(drawn)
        return pixels
    }

    private func alpha(of view: some View, side: Int) throws -> [UInt8] {
        let pixels = try pixels(of: view, side: side)
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }

    private func mask(of view: some View, side: Int, threshold: UInt8 = 127) throws -> [Bool] {
        let pixels = try pixels(of: view, side: side)
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] > threshold }
    }

    /// Only the progress fill: a skeleton whose lines are clear.
    private func fillOnly(_ species: LeafSpecies, fraction: Double) -> LeafView {
        LeafView(species, style: .skeleton(stroke: .clear, vein: .clear))
            .progressFill(fraction: fraction, colour: .red, opacity: 1)
    }

    private func rows(_ mask: [Bool], side: Int) -> ClosedRange<Int>? {
        let filled = (0..<side).filter { row in (0..<side).contains { mask[row * side + $0] } }
        guard let first = filled.first, let last = filled.last else { return nil }
        return first...last
    }

    // MARK: Skeleton

    @Test("skeleton(stroke:vein:) strokes outline and stalk in `stroke`, veins in `vein`, with no fill")
    func skeletonStyle() {
        let style = LeafStyle.skeleton(stroke: .gray, vein: .white)
        #expect(style.outline == .gray && style.vein == .white && style.fill == .clear)
        #expect(style.detail == .skeleton(outlineWidth: 1, veinWidth: 0.75))
        #expect(LeafStyle.skeleton(stroke: .gray, vein: .white, outlineWidth: 1.25, veinWidth: 0.5).detail
            == .skeleton(outlineWidth: 1.25, veinWidth: 0.5))
    }

    @Test("A skeleton is lines only: a small fraction of the filled leaf's area", arguments: [
        "palmatum", "rubrum", "negundo", "cissifolium", "pentaphyllum", "albopurpurascens",
    ])
    func skeletonHasNoFill(id: String) throws {
        let species = try species(id)
        let side = 160
        let filled = try mask(of: LeafView(species, detail: .fillOnly), side: side).filter { $0 }.count
        let lines = try mask(of: LeafView(species, style: .skeleton(stroke: .black, vein: .black)), side: side, threshold: 60)
            .filter { $0 }.count
        #expect(lines > 0, "\(id): the skeleton is drawn")
        #expect(Double(lines) < Double(filled) * 0.6, "\(id): \(lines) line pixels vs \(filled) filled")
    }

    @Test("Skeleton lines keep their width in points: ink grows with the leaf's size, not its area")
    func skeletonWidthIsInPoints() throws {
        let rubrum = try species("rubrum")
        let view = LeafView(rubrum, style: .skeleton(stroke: .black, vein: .black))
        let small = try alpha(of: view, side: 60).map(Int.init).reduce(0, +)
        let large = try alpha(of: view, side: 240).map(Int.init).reduce(0, +)
        let ratio = Double(large) / Double(small)
        // 4× the size: about 4× the ink for constant-width lines (16× if the widths scaled with the leaf).
        #expect(ratio > 3 && ratio < 6, "ink ratio \(ratio)")
    }

    @Test("Translucent skeleton lines are even where they meet", arguments: ["palmatum", "negundo"])
    func translucentSkeletonIsEven(id: String) throws {
        // Palmatum: the stalk starts inside the blade and seven veins meet at the base. Negundo: five leaflets.
        let species = try species(id)
        let translucent = Color.black.opacity(0.4)
        let outlines = LeafStyle.skeleton(stroke: translucent, vein: .clear, outlineWidth: 3, veinWidth: 3)
        let veins = LeafStyle.skeleton(stroke: .clear, vein: translucent, outlineWidth: 3, veinWidth: 3)
        for (name, style) in [("outline and stalk", outlines), ("veins", veins)] {
            let maximum = try #require(try alpha(of: LeafView(species, style: style), side: 160).max())
            #expect(abs(Int(maximum) - 102) <= 3, "\(id) \(name): maximum alpha \(maximum), expected 0.4 × 255")
        }
    }

    // MARK: Progress fill

    @Test("No progress draws nothing; full progress fills the whole blade", arguments: ["palmatum", "negundo", "davidii"])
    func progressExtremes(id: String) throws {
        let species = try species(id)
        let side = 120
        for fraction in [0, -0.5, .nan] as [Double] {
            #expect(try mask(of: fillOnly(species, fraction: fraction), side: side).allSatisfy { !$0 }, "\(id) at \(fraction)")
        }
        let full = try mask(of: fillOnly(species, fraction: 1), side: side)
        let blades = try mask(of: LeafView(species, style: LeafStyle(fill: .red, vein: .clear, detail: .fillOnly)), side: side)
        let both = zip(full, blades).filter { $0 && $1 }.count
        let either = zip(full, blades).filter { $0 || $1 }.count
        #expect(either > 0 && Double(both) / Double(either) > 0.98, "\(id): IoU with the blades \(Double(both) / Double(max(either, 1)))")
        #expect(try mask(of: fillOnly(species, fraction: 7), side: side) == full, "\(id): clamped to 1")
    }

    @Test("Progress rises from the stalk end towards the tip", arguments: ["palmatum", "rubrum", "negundo", "davidii", "griseum"])
    func progressRisesFromTheStalk(id: String) throws {
        let species = try species(id)
        let side = 160
        let fractions = [0.2, 0.5, 0.8, 1.0]
        let masks = try fractions.map { try mask(of: fillOnly(species, fraction: $0), side: side) }
        let extents = try masks.map { try #require(rows($0, side: side), "\(id) has some fill") }
        for (lower, higher) in zip(masks.indices, masks.indices.dropFirst()) {
            // Nested: more progress only ever adds fill.
            #expect(zip(masks[lower], masks[higher]).allSatisfy { !$0 || $1 }, "\(id): \(fractions[lower]) ⊂ \(fractions[higher])")
            // Anchored at the bottom (the stalk end), growing upwards.
            #expect(abs(extents[lower].upperBound - extents[higher].upperBound) <= 2, "\(id): same bottom row")
            #expect(extents[higher].lowerBound < extents[lower].lowerBound, "\(id): the top rises")
        }
        let areas = masks.map { $0.filter { $0 }.count }
        #expect(areas[1] > areas[3] / 10 && areas[1] < areas[3] * 9 / 10, "\(id): half progress, part of the blade (\(areas))")
    }

    @Test("Blade extent spans the outlines along the leaf's axis", arguments: allIDs)
    func bladeExtent(id: String) throws {
        let geometry = LeafGeometry.of(try species(id))
        let ys = geometry.outlines.joined().map(\.y)
        #expect(geometry.bladeExtent.lowerBound == ys.min() && geometry.bladeExtent.upperBound == ys.max())
        #expect(geometry.bladeExtent.upperBound - geometry.bladeExtent.lowerBound > 25)
    }
}
