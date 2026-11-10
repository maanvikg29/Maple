import CoreGraphics
import Foundation
import MapleCore
import SwiftUI
import Testing
@testable import MapleDesign

/// The dial's centre leaf (F1 design §4.3): `LeafFill` drawn by `LeafRenderer` under a skeleton's lines. The part
/// saved before this session in one colour, this session's share above it in another, and a light edge at the fill
/// line.
@Suite("Leaf fill")
@MainActor
struct LeafFillTests {
    /// Pure sRGB primaries, so each coat and the edge is clearly one channel (system blue and green carry too much green).
    private let palette = LeafFill.Palette(
        before: Color(red: 1, green: 0, blue: 0), session: Color(red: 0, green: 0, blue: 1), edge: Color(red: 0, green: 1, blue: 0)
    )

    private func species(_ id: String) throws -> LeafSpecies {
        try #require(LeafCatalog.shared.species(id: id))
    }

    /// A view rendered at `side` × `side` points, scale 1, as premultiplied RGBA rows (top row first).
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

    /// The fill alone: a skeleton whose lines are clear.
    private func filled(_ species: LeafSpecies, _ fill: LeafFill) -> LeafView {
        LeafView(species, style: .skeleton(stroke: .clear, vein: .clear), progress: fill, palette: palette)
    }

    /// Pixels that are clearly `channel` (0 red, 1 green, 2 blue): one coat's colour, or the edge's.
    private func mask(_ pixels: [UInt8], channel: Int) -> [Bool] {
        stride(from: 0, to: pixels.count, by: 4).map { index in
            let value = Int(pixels[index + channel])
            let others = (0..<3).filter { $0 != channel }.map { Int(pixels[index + $0]) }
            return pixels[index + 3] > 60 && value > 2 * (others.max() ?? 0) + 20
        }
    }

    /// Pixels more than half covered by anything.
    private func covered(_ pixels: [UInt8]) -> [Bool] {
        stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] > 127 }
    }

    private func overlap(_ a: [Bool], _ b: [Bool]) -> Double {
        let both = zip(a, b).filter { $0 && $1 }.count
        let either = zip(a, b).filter { $0 || $1 }.count
        return Double(both) / Double(max(either, 1))
    }

    /// The mean row of the set pixels (rows grow downward, so a smaller value is higher up).
    private func meanRow(_ mask: [Bool], side: Int) -> Double {
        let rows = mask.indices.filter { mask[$0] }.map { Double($0 / side) }
        return rows.reduce(0, +) / Double(max(rows.count, 1))
    }

    @Test("Fractions clamp: two coats stop at the tip, and a negative, infinite or NaN coat is nothing")
    func clamping() {
        #expect(LeafFill.single(0.4).top == 0.4 && LeafFill.single(0.4).split == 0)
        #expect(LeafFill.single(.nan).top == 0 && LeafFill.single(-1).top == 0 && LeafFill.single(.infinity).top == 0)
        #expect(LeafFill.single(7).top == 1)
        let two = LeafFill.twoTone(before: 0.3, session: 0.4, edge: true)
        #expect(two.split == 0.3 && abs(two.top - 0.7) < 1e-9)
        #expect(LeafFill.twoTone(before: 0.8, session: 0.6, edge: true).top == 1)
        #expect(LeafFill.twoTone(before: -1, session: 0.5, edge: false).split == 0)
        #expect(LeafFill.twoTone(before: 1.4, session: 0.2, edge: false).split == 1)
        // The edge shows only when asked for, at a fill line inside the leaf.
        #expect(two.showsEdge)
        #expect(!LeafFill.twoTone(before: 0.3, session: 0.4, edge: false).showsEdge)
        #expect(!LeafFill.twoTone(before: 0.6, session: 0.6, edge: true).showsEdge)
        #expect(!LeafFill.twoTone(before: 0, session: 0, edge: true).showsEdge)
        #expect(!LeafFill.single(0.5).showsEdge)
    }

    @Test("One coat through the new initializer draws exactly what progressFill draws", arguments: ["palmatum", "negundo"])
    func singleCoat(id: String) throws {
        let leaf = try species(id)
        let old = LeafView(leaf, style: .skeleton(stroke: .clear, vein: .clear))
            .progressFill(fraction: 0.45, colour: palette.session, opacity: 1)
        #expect(try pixels(of: old, side: 120) == pixels(of: filled(leaf, .single(0.45)), side: 120))
    }

    @Test("The saved-before coat sits under this session's, and together they cover what one coat would",
          arguments: ["palmatum", "rubrum", "campestre"])
    func twoTones(id: String) throws {
        let leaf = try species(id)
        let side = 160
        let two = try pixels(of: filled(leaf, .twoTone(before: 0.3, session: 0.4, edge: false)), side: side)
        let lower = covered(try pixels(of: filled(leaf, .single(0.3)), side: side))
        let whole = covered(try pixels(of: filled(leaf, .single(0.7)), side: side))
        let red = mask(two, channel: 0), blue = mask(two, channel: 2)
        #expect(overlap(covered(two), whole) > 0.98, "\(id): the two coats cover one coat to 0.7")
        #expect(overlap(red, lower) > 0.85, "\(id): the saved-before coat is the bottom 0.3")
        #expect(red.contains(true) && blue.contains(true), "\(id): both coats are drawn")
        #expect(meanRow(blue, side: side) < meanRow(red, side: side), "\(id): this session's coat is above")
        #expect(!mask(two, channel: 1).contains(true), "\(id): no edge unless asked for")
    }

    @Test("The edge is a light line along the top of the fill, inside the leaf", arguments: ["palmatum", "campestre"])
    func edge(id: String) throws {
        let leaf = try species(id)
        let side = 160
        let green = mask(try pixels(of: filled(leaf, .twoTone(before: 0.3, session: 0.4, edge: true)), side: side), channel: 1)
        let upper = covered(try pixels(of: filled(leaf, .single(0.76)), side: side))
        let below = covered(try pixels(of: filled(leaf, .single(0.64)), side: side))
        let band = zip(upper, below).map { $0 && !$1 }
        let count = green.filter { $0 }.count
        #expect(count > 10, "\(id): the edge is drawn")
        let inBand = zip(green, band).filter { $0 && $1 }.count
        #expect(Double(inBand) / Double(max(count, 1)) > 0.9, "\(id): it runs along the fill line")
        // A full leaf has no fill line, so it has no edge.
        let full = mask(try pixels(of: filled(leaf, .twoTone(before: 0.5, session: 0.5, edge: true)), side: side), channel: 1)
        #expect(!full.contains(true), "\(id): no edge on a full leaf")
    }
}
