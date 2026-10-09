import CoreGraphics
import Foundation
import MapleCore
import SwiftUI
import Testing
@testable import MapleDesign

private let allIDs = LeafCatalog.shared.species.map(\.id)

@Suite("Leaf geometry")
struct LeafGeometryTests {
    private static let catalog = LeafCatalog.shared

    private func species(_ id: String) throws -> LeafSpecies {
        try #require(Self.catalog.species(id: id))
    }

    @Test("Every species has non-empty, finite outlines, veins and paths", arguments: allIDs)
    func finiteAndNonEmpty(id: String) throws {
        let geometry = LeafGeometry.of(try species(id))
        #expect(!geometry.outlines.isEmpty)
        for outline in geometry.outlines {
            #expect(outline.count >= 50, "a blade samples at least 53 points")
            #expect(outline.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        }
        #expect(!geometry.veins.isEmpty)
        #expect(geometry.veins.allSatisfy { [$0.start, $0.end].allSatisfy { $0.x.isFinite && $0.y.isFinite } })
        #expect(geometry.bladePaths.count == geometry.outlines.count)
        #expect(geometry.veinPaths.count == geometry.veins.count)
        #expect(geometry.bladePaths.allSatisfy { !$0.isEmpty })
        #expect(geometry.veinPaths.allSatisfy { !$0.isEmpty })
        #expect(!geometry.petiolePath.isEmpty && !geometry.silhouettePath.isEmpty)
        for rect in [geometry.bounds, geometry.frame] {
            #expect(rect.minX.isFinite && rect.minY.isFinite && rect.width > 25 && rect.height > 25, "\(rect)")
        }
    }

    @Test("Everything stays inside the generator's -100...100 box", arguments: allIDs)
    func staysInLeafBox(id: String) throws {
        let geometry = LeafGeometry.of(try species(id))
        let box = CGRect(x: -100, y: -100, width: 200, height: 200)
        let raw = geometry.outlines.flatMap { $0 } + geometry.veins.flatMap { [$0.start, $0.end] }
            + [geometry.petiole.start, geometry.petiole.end]
        #expect(raw.allSatisfy { box.contains($0) })
        // Placed (offset and tilted) and stroked, too.
        #expect(box.contains(geometry.bounds), "\(geometry.bounds)")
        // The fitted square holds the whole drawing.
        #expect(geometry.frame.insetBy(dx: -0.01, dy: -0.01).contains(geometry.bounds))
        #expect(abs(geometry.frame.width - geometry.frame.height) < 1e-9)
    }

    @Test("Palmate leaves have one lobe (tip and vein) per catalogue lobe", arguments: allIDs)
    func palmateLobes(id: String) throws {
        let species = try species(id)
        guard species.form == .palmate else { return }
        let geometry = LeafGeometry.of(species)
        #expect(geometry.outlines.count == 1)
        #expect(geometry.veins.count == species.lobes)
        let outline = geometry.outlines[0]
        let tips = geometry.veins.map(\.end)
        #expect(geometry.veins.allSatisfy { $0.start == .zero }, "veins radiate from the leaf base")
        for tip in tips {
            // Each vein ends exactly on an outline vertex: the lobe tip, well clear of the base.
            #expect(outline.contains { hypot($0.x - tip.x, $0.y - tip.y) < 1e-9 })
            #expect(hypot(tip.x, tip.y) > 40)
        }
        // Lobes fan out symmetrically, left to right.
        let angles = tips.map { atan2($0.x, -$0.y) }
        #expect(zip(angles, angles.dropFirst()).allSatisfy { $0 < $1 })
        #expect(abs(angles.first! + angles.last!) < 1e-9)
    }

    @Test("Compound and simple leaves have the generator's blade counts", arguments: allIDs)
    func bladeCounts(id: String) throws {
        let species = try species(id)
        let geometry = LeafGeometry.of(species)
        switch species.form {
        case .palmate:
            #expect(geometry.outlines.count == 1)
        case .unlobed:
            #expect(geometry.outlines.count == 1)
            #expect(geometry.veins.count == 11, "midrib and five pairs of side veins")
        case .trifoliate, .palmcompound, .pinnate:
            // The catalogue's `lobes` is the leaflet count for compound leaves.
            #expect(geometry.outlines.count == species.lobes)
            #expect(geometry.veins.count == species.lobes + (species.form == .pinnate ? 1 : 0))
        }
    }

    @Test("Toothed margins add teeth; smooth margins have none")
    func margins() throws {
        let palmatum = try species("palmatum") // double-toothed
        let smooth = LeafGeometry(
            id: palmatum.id, form: palmatum.form, lobes: palmatum.lobes, depth: palmatum.depth,
            margin: .smooth, evergreen: palmatum.evergreen
        )
        let toothed = LeafGeometry.of(palmatum)
        #expect(smooth.outlines[0].count == toothed.outlines[0].count, "teeth move points, never add them")
        let moved = zip(smooth.outlines[0], toothed.outlines[0]).filter { $0 != $1 }.count
        #expect(moved > 7 * 8, "several teeth per lobe")
        #expect(smooth.veins == toothed.veins)
    }

    @Test("Geometry is deterministic and cached per species")
    func determinismAndCache() throws {
        for id in ["palmatum", "negundo", "rubrum", "cissifolium", "pentaphyllum", "albopurpurascens"] {
            let species = try species(id)
            let first = LeafGeometry(species: species)
            let second = LeafGeometry(species: species)
            #expect(first.outlines == second.outlines)
            #expect(first.veins == second.veins)
            #expect(first.frame == second.frame && first.bounds == second.bounds)
            let cached = LeafGeometry.of(species)
            #expect(cached.outlines == first.outlines)
            #expect(LeafGeometry.of(species).speciesID == id)
        }
    }

    @Test("The cache serves many concurrent callers off the main actor")
    func concurrentCache() async {
        let species = Self.catalog.species
        let results = await withTaskGroup(of: (String, Int, CGRect).self) { group in
            for _ in 0..<4 {
                for item in species {
                    group.addTask { (item.id, LeafGeometry.of(item).outlines[0].count, LeafGeometry.of(item).frame) }
                }
            }
            var results: [(String, Int, CGRect)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        #expect(results.count == species.count * 4)
        let byID = Dictionary(grouping: results, by: \.0)
        #expect(byID.values.allSatisfy { runs in runs.allSatisfy { $0.1 == runs[0].1 && $0.2 == runs[0].2 } })
    }

    @Test("The cache is keyed by the traits the drawing depends on")
    func cacheKeyedByTraits() throws {
        let palmatum = try species("palmatum")
        let fiveLobed = try decodeSpecies(editing: "palmatum") { $0["lobes"] = 5 }
        #expect(LeafGeometry.of(palmatum).veins.count == 7)
        #expect(LeafGeometry.of(fiveLobed).veins.count == 5)
        #expect(LeafGeometry.of(palmatum).veins.count == 7)
    }

    @Test("A single-lobed palmate leaf is drawn as an unlobed leaf instead of dividing by zero")
    func singleLobedPalmate() throws {
        let oneLobe = try decodeSpecies(editing: "palmatum") { $0["lobes"] = 1 }
        let geometry = LeafGeometry.of(oneLobe)
        #expect(geometry.outlines.count == 1)
        #expect(geometry.outlines[0].allSatisfy { $0.x.isFinite && $0.y.isFinite })
        #expect(geometry.bounds.width > 40 && geometry.bounds.height > 100)
    }

    @Test("Simple leaves vary per species through the generator's hash")
    func hashJitter() throws {
        // Deciduous unlobed leaves are 34 + 6 × hash(id) units wide at the widest; evergreens are 24.
        let unlobed = Self.catalog.species.filter { $0.form == .unlobed }
        let widths = Set(unlobed.filter { !$0.evergreen }.map { LeafGeometry.of($0).outlines[0].map(\.x).max()! })
        #expect(widths.count > 3)
        #expect(LeafGenerator.hash("") == 2_166_136_261.0 / 4_294_967_295.0, "FNV-1a offset basis")
        #expect(LeafGenerator.hash("palmatum") == LeafGenerator.hash("palmatum"))
        #expect(LeafGenerator.hash("palmatum") != LeafGenerator.hash("rubrum"))
    }

    @Test("Tilt is the catalogue's resting tilt, rounded to 0.1° as the exports drew it", arguments: allIDs)
    func tilt(id: String) throws {
        let species = try species(id)
        let geometry = LeafGeometry.of(species)
        #expect(abs(geometry.tiltDegrees - species.restingTiltDegrees) <= 0.05 + 1e-9)
        #expect(abs(geometry.tiltDegrees * 10 - (geometry.tiltDegrees * 10).rounded()) < 1e-9)
        #expect(abs(geometry.tiltDegrees) <= 8)
    }

    // MARK: Pinned to the catalogue exports

    @Test("Outline, veins, stalk, offset, tilt, colours and framing match the catalogue export", arguments: allIDs)
    func matchesExport(id: String) throws {
        let species = try species(id)
        let geometry = LeafGeometry.of(species)
        let export = try CatalogExport(id: id)

        // The exports print coordinates with toFixed(1), so every point must be within half a decimal.
        let tolerance = 0.05 + 1e-6
        func close(_ a: CGPoint, _ b: CGPoint) -> Bool {
            abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
        }
        try #require(geometry.outlines.count == export.blades.count)
        for (outline, exported) in zip(geometry.outlines, export.blades) {
            try #require(outline.count == exported.count)
            let mismatches = zip(outline, exported).filter { !close($0, $1) }
            #expect(mismatches.isEmpty, "\(id): \(mismatches.prefix(3))")
        }
        try #require(geometry.veins.count == export.veins.count)
        for (vein, exported) in zip(geometry.veins, export.veins) {
            #expect(close(vein.start, exported.start) && close(LeafGeometry.veinDrawnEnd(vein), exported.end), "\(id) vein")
        }
        let control = LeafGeometry.petioleControl(geometry.petiole)
        let petiole: [Double] = [
            geometry.petiole.start.x, geometry.petiole.start.y, control.x, control.y,
            geometry.petiole.end.x, geometry.petiole.end.y,
        ].map { Double($0) }
        #expect(export.petiole == petiole)
        #expect(Double(geometry.verticalOffset) == export.verticalOffset)
        #expect(abs(geometry.tiltDegrees - export.tiltDegrees) < 1e-9)
        #expect(export.fill == species.autumnColor.rgb)
        #expect(export.stroke == species.autumnColor.veinColor.rgb)
        // The export measured its viewBox from those rounded coordinates and printed it rounded too.
        let frame = geometry.frame
        let frameTolerance = 0.15
        #expect(abs(frame.minX - export.viewBox.minX) < frameTolerance, "\(id): \(frame) vs \(export.viewBox)")
        #expect(abs(frame.minY - export.viewBox.minY) < frameTolerance, "\(id): \(frame) vs \(export.viewBox)")
        #expect(abs(frame.width - export.viewBox.width) < frameTolerance, "\(id): \(frame) vs \(export.viewBox)")
    }

    @Test("Spot values copied from the exports")
    func spotValues() throws {
        let palmatum = LeafGeometry.of(try species("palmatum"))
        // "M0.0 2.4" … "L0.0 -70.6" (the middle lobe's tip) in acer-palmatum.svg.
        #expect(abs(palmatum.outlines[0][0].x) < 0.05 && abs(palmatum.outlines[0][0].y - 2.4) < 0.05)
        #expect(palmatum.veins.count == 7)
        #expect(abs(palmatum.veins[3].end.y - -70.6) < 0.05)
        #expect(abs(LeafGeometry.veinDrawnEnd(palmatum.veins[0]).x - -29.6) < 0.05)
        #expect(abs(LeafGeometry.veinDrawnEnd(palmatum.veins[0]).y - 26.5) < 0.05)
        #expect(palmatum.tiltDegrees == 0.5 && Double(palmatum.verticalOffset) == -10)

        let negundo = LeafGeometry.of(try species("negundo"))
        #expect(negundo.outlines.count == 5)
        #expect(negundo.petiole == .init(start: CGPoint(x: 0, y: 42), end: CGPoint(x: 2, y: 80)))
        #expect(negundo.tiltDegrees == -4.3 && Double(negundo.verticalOffset) == -4)
    }
}

// MARK: - Helpers

/// Decodes a catalogue species with some fields edited (`LeafSpecies` has no public memberwise initialiser).
private func decodeSpecies(editing id: String, _ edit: (inout [String: Any]) -> Void) throws -> LeafSpecies {
    let encoded = try JSONEncoder().encode(try #require(LeafCatalog.shared.species(id: id)))
    var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    edit(&object)
    return try JSONDecoder().decode(LeafSpecies.self, from: JSONSerialization.data(withJSONObject: object))
}

/// The parts of a catalogue export (`Catalog/svg/autumn/acer-<id>.svg`) that the port must reproduce.
private struct CatalogExport {
    var viewBox: CGRect
    var tiltDegrees: Double
    var verticalOffset: Double
    /// `M x0 y0 Q cx cy x1 y1`
    var petiole: [Double]
    var blades: [[CGPoint]]
    var veins: [LeafGeometry.Segment]
    var fill: UInt32
    var stroke: UInt32

    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // MapleDesignTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // MapleKit
        .deletingLastPathComponent() // repo
        .appendingPathComponent("Catalog/svg/autumn")

    init(id: String) throws {
        let url = Self.directory.appendingPathComponent("acer-\(id).svg")
        let svg = try String(contentsOf: url, encoding: .utf8)
        let box = Self.numbers(try #require(Self.attribute("viewBox", in: Substring(svg))))
        try #require(box.count == 4)
        viewBox = CGRect(x: box[0], y: box[1], width: box[2], height: box[3])
        // <g transform="rotate(r) translate(0 y)">
        let transform = Self.numbers(try #require(Self.attribute("transform", in: Substring(svg), containing: "rotate(")))
        try #require(transform.count == 3)
        tiltDegrees = transform[0]
        verticalOffset = transform[2]

        var petiole: [Double] = [], blades: [[CGPoint]] = [], veins: [LeafGeometry.Segment] = []
        var fill: UInt32 = 0, stroke: UInt32 = 0
        for element in svg.components(separatedBy: "<path ").dropFirst() {
            let tag = Substring(" " + element.prefix { $0 != ">" })
            let values = Self.numbers(try #require(Self.attribute("d", in: tag)))
            if tag.contains("stroke-linecap=\"round\"") {
                petiole = values
            } else if tag.contains("opacity=\".55\"") {
                try #require(values.count == 4)
                veins.append(.init(start: CGPoint(x: values[0], y: values[1]), end: CGPoint(x: values[2], y: values[3])))
            } else {
                blades.append(stride(from: 0, to: values.count - 1, by: 2).map { CGPoint(x: values[$0], y: values[$0 + 1]) })
                fill = UInt32(Self.attribute("fill", in: tag)?.dropFirst() ?? "", radix: 16) ?? 0
                stroke = UInt32(Self.attribute("stroke", in: tag)?.dropFirst() ?? "", radix: 16) ?? 0
            }
        }
        self.petiole = petiole
        self.blades = blades
        self.veins = veins
        self.fill = fill
        self.stroke = stroke
    }

    /// The value of the first `name="..."` attribute in `text` (optionally one whose value contains `marker`).
    private static func attribute(_ name: String, in text: Substring, containing marker: String = "") -> Substring? {
        var rest = text[...]
        while let range = rest.range(of: " \(name)=\"") {
            let value = rest[range.upperBound...].prefix { $0 != "\"" }
            if marker.isEmpty || value.contains(marker) { return value }
            rest = rest[range.upperBound...]
        }
        return nil
    }

    /// Every number in an SVG attribute such as a path's `d` ("M0.0 2.4L-1.1 5.4…Z").
    private static func numbers(_ text: Substring) -> [Double] {
        text.split { !($0.isNumber || $0 == "-" || $0 == ".") }.compactMap { Double($0) }
    }
}
