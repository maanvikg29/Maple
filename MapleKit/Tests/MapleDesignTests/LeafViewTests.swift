import CoreGraphics
import Foundation
import MapleCore
import SwiftUI
import Testing
@testable import MapleDesign

@Suite("Leaf view and renderer")
struct LeafViewTests {
    private func species(_ id: String) throws -> LeafSpecies {
        try #require(LeafCatalog.shared.species(id: id))
    }

    @Test("Fill options resolve to the species' summer and autumn colours")
    @MainActor
    func fills() throws {
        let rubrum = try species("rubrum")
        #expect(LeafView.Fill.summer.color(for: rubrum) == rubrum.summerColor)
        #expect(LeafView.Fill.autumn.color(for: rubrum) == rubrum.autumnColor)
        #expect(LeafView.Fill.color(LeafColor(0x123456)).color(for: rubrum) == LeafColor(0x123456))
    }

    @Test("Automatic detail drops outline and veins only for tiny leaves")
    func automaticDetail() {
        let threshold = LeafView.Detail.minimumFullScale
        #expect(LeafView.Detail.automatic.resolved(atScale: threshold) == .full)
        #expect(LeafView.Detail.automatic.resolved(atScale: threshold * 0.99) == .fillOnly)
        #expect(LeafView.Detail.full.resolved(atScale: 0.01) == .full)
        #expect(LeafView.Detail.fillOnly.resolved(atScale: 10) == .fillOnly)
        // A 40 pt leaf (the fitted frame is about 110...190 units across) gets the full drawing at the median size.
        let frames = LeafCatalog.shared.species.map { LeafGeometry.of($0).frame.width }.sorted()
        #expect(LeafView.Detail.automatic.resolved(atScale: 44 / frames[frames.count / 2]) == .full)
        #expect(LeafView.Detail.automatic.resolved(atScale: 24 / frames[0]) == .fillOnly)
    }

    @Test("Fitting maps the leaf's frame onto the centre of the target, aspect-fitted")
    func fitting() throws {
        let frame = LeafGeometry.of(try species("palmatum")).frame
        let target = CGRect(x: 10, y: 20, width: 300, height: 100)
        let transform = LeafRenderer.transform(fitting: frame, into: target)
        let centre = CGPoint(x: frame.midX, y: frame.midY).applying(transform)
        #expect(abs(centre.x - target.midX) < 1e-9 && abs(centre.y - target.midY) < 1e-9)
        let fitted = frame.applying(transform)
        #expect(abs(fitted.height - 100) < 1e-9 && abs(fitted.width - 100) < 1e-9)
        #expect(LeafRenderer.transform(fitting: .zero, into: target) == .identity)
    }

    @Test("LeafStyle takes outline and veins from LeafColor.veinColor")
    @MainActor
    func style() {
        let fill = LeafColor(0xD2462A)
        let style = LeafStyle(fill: fill)
        #expect(style == LeafStyle(fill: Color(hex: 0xD2462A), vein: Color(hex: fill.veinColor.rgb)))
        #expect(LeafStyle(fill: fill, detail: .fillOnly).detail == .fillOnly)
    }

    @Test("LeafView renders every form as a leaf-coloured shape that fills its frame", arguments: [
        "palmatum", "rubrum", "negundo", "cissifolium", "pentaphyllum", "albopurpurascens",
    ])
    @MainActor
    func renders(id: String) throws {
        let species = try species(id)
        let side = 96
        let renderer = ImageRenderer(content: LeafView(species, fill: .autumn).frame(width: CGFloat(side), height: CGFloat(side)))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        #expect(image.width == side && image.height == side)

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
        var opaque = 0, minX = side, maxX = 0, minY = side, maxY = 0
        var fillLike = 0
        let fill = species.autumnColor
        for y in 0..<side {
            for x in 0..<side {
                let index = (y * side + x) * 4
                guard pixels[index + 3] > 200 else { continue }
                opaque += 1
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                let colour = LeafColor(red: Int(pixels[index]), green: Int(pixels[index + 1]), blue: Int(pixels[index + 2]))
                if colour.isClose(to: fill, tolerance: 12) { fillLike += 1 }
            }
        }
        let area = Double(side * side)
        #expect(Double(opaque) > area * 0.06 && Double(opaque) < area * 0.8, "\(id): \(opaque) opaque pixels")
        #expect(Double(fillLike) > Double(opaque) * 0.5, "\(id): mostly the autumn fill")
        // Fitted like the catalogue exports: the leaf's longer side spans 1 / 1.12 of the frame.
        let span = Double(max(maxX - minX, maxY - minY) + 1)
        #expect(span > Double(side) * 0.8 && span < Double(side) * 0.95, "\(id): spans \(span) of \(side)")
    }
}
