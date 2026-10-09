// Compares the native leaf port with the catalogue exports, for Scripts/leaf-fidelity.sh.
//
//   leaf-fidelity-compare <reference-dir> <port-dir> <out-dir> <species.json> <svg-dir> [gate=value ...]
//
// <reference-dir> holds QuickLook rasters of the exports (acer-<id>.svg.png); <port-dir> holds the port's
// renders (acer-<id>.png), both 512 × 512; <svg-dir> holds the exports themselves, which give each species'
// fill and line colours. Both images are flattened onto white, then compared four ways:
//
// - silhouette: IoU of the "ink" masks (darkest channel below 150). Every fill passes that test, so this
//   checks the outer shape (lobes, teeth, tilt, stalk) and nothing inside it.
// - lines: IoU of the "line" masks. A pixel is a line pixel when its colour, projected onto the segment from
//   the export's fill colour F to its line colour V, sits more than `lineThreshold` of the way towards V:
//   t = (C − F)·(V − F) / |V − F|² > 0.35, and it is not near-white. Veins (V at 55 % over F, t ≈ 0.55),
//   their crossings, the outline and the stalk pass; plain fill (t ≈ 0) and the white page (t < 0) do not.
//   This checks where the veins and outlines are, and how wide and dark they are.
// - colour: mean of the per-pixel colour difference (largest channel, 0...255) over the union of both leaves
//   (darkest channel below 200), which catches a wrong fill, line colour or opacity anywhere on the leaf.
// - line colour: the same difference averaged over the union of both line masks only, so a wrong vein
//   colour or opacity cannot hide in the much larger fill area.
// - off-edge: mismatched pixels (in either mask) with no edge of either mask in their 3 × 3 neighbourhood.
//   Anti-aliasing only moves edges, so any such pixel is a real shape difference.
//
// Prints a table worst first (ranked by headroom: how close the species is to its nearest gate), writes
// <out-dir>/fidelity.tsv and a contact sheet of the worst 12 (reference | port | mask difference | colour
// difference). Exits 1 when any gate fails; gates (defaults below) can be overridden as name=value arguments.
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let side = 512
let inkThreshold: UInt8 = 150
let leafThreshold: UInt8 = 200
let lineThreshold = 0.35

// MARK: Gates

struct Gates {
    // Defaults sit between the port (mean / worst species, 2026-10-10) and the nearest deliberately broken
    // render (see Scripts/leaf-fidelity.sh): silhouette 0.9980 / 0.9941, lines 0.9444 / 0.9147,
    // colour 0.74 / 1.70, line colour 3.31 / 4.54, off-edge 0 / 0.

    /// Silhouette IoU: mean over all species, and every species.
    var silhouetteMean = 0.995
    var silhouetteMin = 0.99
    /// Line-mask IoU.
    var lineMean = 0.93
    var lineMin = 0.90
    /// Mean colour difference over the leaf, 0...255.
    var colourMean = 1.25
    var colourMax = 2.5
    /// Mean colour difference over the line pixels, 0...255.
    var lineColourMean = 5.0
    var lineColourMax = 7.0
    /// Mismatched pixels away from every edge of both masks (silhouette or lines), per species. Anti-aliasing
    /// cannot produce one: it takes a 3 × 3 block where one drawing has ink or a line and the other does not.
    var offEdgeMax = 0.0

    mutating func apply(_ argument: String) -> Bool {
        let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2, let value = Double(parts[1]) else { return false }
        switch parts[0] {
        case "silhouette-mean": silhouetteMean = value
        case "silhouette-min": silhouetteMin = value
        case "line-mean": lineMean = value
        case "line-min": lineMin = value
        case "colour-mean": colourMean = value
        case "colour-max": colourMax = value
        case "line-colour-mean": lineColourMean = value
        case "line-colour-max": lineColourMax = value
        case "off-edge-max": offEdgeMax = value
        default: return false
        }
        return true
    }
}

// MARK: Images

struct RGB {
    var r: Double, g: Double, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { (self.r, self.g, self.b) = (r, g, b) }
    init(hex: String) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        self.init(Double((value >> 16) & 0xFF), Double((value >> 8) & 0xFF), Double(value & 0xFF))
    }
    static func - (a: RGB, b: RGB) -> RGB { RGB(a.r - b.r, a.g - b.g, a.b - b.b) }
    func dot(_ other: RGB) -> Double { r * other.r + g * other.g + b * other.b }
}

/// An image flattened onto white, as straight 8-bit RGBA.
struct Raster {
    var pixels: [UInt8]
    var image: CGImage

    func darkest(_ index: Int) -> UInt8 { min(pixels[index * 4], pixels[index * 4 + 1], pixels[index * 4 + 2]) }
    func colour(_ index: Int) -> RGB {
        RGB(Double(pixels[index * 4]), Double(pixels[index * 4 + 1]), Double(pixels[index * 4 + 2]))
    }
}

func loadRaster(_ url: URL) -> Raster? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    var pixels = [UInt8](repeating: 255, count: side * side * 4)
    let drawn: CGImage? = pixels.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(
            data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }
    guard let flattened = drawn else { return nil }
    return Raster(pixels: pixels, image: flattened)
}

func makeImage(_ pixels: inout [UInt8]) -> CGImage? {
    pixels.withUnsafeMutableBytes { buffer in
        CGContext(
            data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage()
    }
}

/// The export's fill and line colours (each export uses exactly one of each).
func exportColours(_ url: URL) -> (fill: RGB, line: RGB)? {
    guard let svg = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    func first(_ attribute: String) -> RGB? {
        guard let regex = try? NSRegularExpression(pattern: attribute + #"="(#[0-9a-fA-F]{6})""#),
              let match = regex.firstMatch(in: svg, range: NSRange(svg.startIndex..., in: svg)),
              let range = Range(match.range(at: 1), in: svg) else { return nil }
        return RGB(hex: String(svg[range]))
    }
    guard let fill = first("fill"), let line = first("stroke") else { return nil }
    return (fill, line)
}

// MARK: Masks

struct Masks {
    var silhouette: [Bool]
    var line: [Bool]
    var leaf: [Bool]
}

func masks(_ raster: Raster, fill: RGB, line: RGB) -> Masks {
    let axis = line - fill
    let length = axis.dot(axis)
    var result = Masks(
        silhouette: [Bool](repeating: false, count: side * side),
        line: [Bool](repeating: false, count: side * side),
        leaf: [Bool](repeating: false, count: side * side)
    )
    for index in 0..<(side * side) {
        let darkest = raster.darkest(index)
        result.silhouette[index] = darkest < inkThreshold
        result.leaf[index] = darkest < leafThreshold
        if darkest < leafThreshold {
            let t = (raster.colour(index) - fill).dot(axis) / length
            result.line[index] = t > lineThreshold
        }
    }
    return result
}

/// Whether the mask changes value within the 3 × 3 neighbourhood of `index` (the pixel sits on an edge).
func onEdge(_ mask: [Bool], _ index: Int) -> Bool {
    let x = index % side, y = index / side
    let value = mask[index]
    for dy in -1...1 {
        for dx in -1...1 {
            let nx = x + dx, ny = y + dy
            guard nx >= 0, ny >= 0, nx < side, ny < side else { continue }
            if mask[ny * side + nx] != value { return true }
        }
    }
    return false
}

struct Overlap {
    var iou: Double
    var referencePixels = 0
    var portPixels = 0
    var mismatched = 0
    /// Mismatched pixels with no edge of either mask in their 3 × 3 neighbourhood: real shape differences,
    /// as opposed to anti-aliasing along an edge both drawings share.
    var offEdge = 0
}

func overlap(_ a: [Bool], _ b: [Bool]) -> Overlap {
    var intersection = 0, union = 0
    var result = Overlap(iou: 1)
    for index in 0..<(side * side) {
        let x = a[index], y = b[index]
        if x { result.referencePixels += 1 }
        if y { result.portPixels += 1 }
        if x && y { intersection += 1 }
        if x || y { union += 1 }
        if x != y {
            result.mismatched += 1
            if !onEdge(a, index) && !onEdge(b, index) { result.offEdge += 1 }
        }
    }
    result.iou = union == 0 ? 1 : Double(intersection) / Double(union)
    return result
}

// MARK: Per species

struct Result {
    let id: String
    let form: String
    let silhouette: Overlap
    let line: Overlap
    /// Mean colour difference (largest channel, 0...255) over both leaves, and over both line masks.
    let colour: Double
    let lineColour: Double
    let reference: Raster
    let port: Raster
    let referenceMasks: Masks
    let portMasks: Masks

    var offEdge: Int { silhouette.offEdge + line.offEdge }

    /// How far the species is from failing, per gate, as a fraction of the gate's range (1 = perfect, 0 = at
    /// the gate, negative = failing). The smallest one ranks the table.
    func headroom(_ gates: Gates) -> (value: Double, limit: String) {
        let candidates: [(Double, String)] = [
            ((silhouette.iou - gates.silhouetteMin) / (1 - gates.silhouetteMin), "silhouette"),
            ((line.iou - gates.lineMin) / (1 - gates.lineMin), "lines"),
            ((gates.colourMax - colour) / gates.colourMax, "colour"),
            ((gates.lineColourMax - lineColour) / gates.lineColourMax, "line colour"),
            (Double(offEdge) <= gates.offEdgeMax ? 1 : -1, "off-edge"),
        ]
        let worst = candidates.min { $0.0 < $1.0 }!
        return (worst.0, worst.1)
    }
}

func padded(_ string: String, _ width: Int) -> String {
    string.count >= width ? string : string + String(repeating: " ", count: width - string.count)
}

let arguments = CommandLine.arguments
guard arguments.count >= 6 else {
    FileHandle.standardError.write(Data(
        "usage: leaf-fidelity-compare <reference-dir> <port-dir> <out-dir> <species.json> <svg-dir> [gate=value ...]\n".utf8
    ))
    exit(2)
}
let referenceDirectory = URL(fileURLWithPath: arguments[1])
let portDirectory = URL(fileURLWithPath: arguments[2])
let outDirectory = URL(fileURLWithPath: arguments[3])
let svgDirectory = URL(fileURLWithPath: arguments[5])
var gates = Gates()
for argument in arguments.dropFirst(6) where !gates.apply(argument) {
    FileHandle.standardError.write(Data("unknown gate \(argument)\n".utf8))
    exit(2)
}

struct SpeciesInfo: Decodable {
    let id: String
    let form: String
    let lobes: Int
    let margin: Int
}
let speciesData = try Data(contentsOf: URL(fileURLWithPath: arguments[4]))
let species = try JSONDecoder().decode([SpeciesInfo].self, from: speciesData)

var results: [Result] = []
var missing: [String] = []
for info in species {
    let referenceURL = referenceDirectory.appendingPathComponent("acer-\(info.id).svg.png")
    let portURL = portDirectory.appendingPathComponent("acer-\(info.id).png")
    let svgURL = svgDirectory.appendingPathComponent("acer-\(info.id).svg")
    guard let reference = loadRaster(referenceURL), let port = loadRaster(portURL),
          let colours = exportColours(svgURL) else {
        missing.append(info.id)
        continue
    }
    let referenceMasks = masks(reference, fill: colours.fill, line: colours.line)
    let portMasks = masks(port, fill: colours.fill, line: colours.line)
    var colourSum = 0.0, colourCount = 0, lineSum = 0.0, lineCount = 0
    for index in 0..<(side * side) {
        let inLeaf = referenceMasks.leaf[index] || portMasks.leaf[index]
        let inLine = referenceMasks.line[index] || portMasks.line[index]
        guard inLeaf || inLine else { continue }
        let difference = Double(max(
            abs(Int(reference.pixels[index * 4]) - Int(port.pixels[index * 4])),
            abs(Int(reference.pixels[index * 4 + 1]) - Int(port.pixels[index * 4 + 1])),
            abs(Int(reference.pixels[index * 4 + 2]) - Int(port.pixels[index * 4 + 2]))
        ))
        if inLeaf { colourSum += difference; colourCount += 1 }
        if inLine { lineSum += difference; lineCount += 1 }
    }
    let form = info.form == "palmate" ? "palmate-\(info.lobes)" : info.form
    results.append(Result(
        id: info.id, form: "\(form) m\(info.margin)",
        silhouette: overlap(referenceMasks.silhouette, portMasks.silhouette),
        line: overlap(referenceMasks.line, portMasks.line),
        colour: colourCount == 0 ? 0 : colourSum / Double(colourCount),
        lineColour: lineCount == 0 ? 0 : lineSum / Double(lineCount),
        reference: reference, port: port, referenceMasks: referenceMasks, portMasks: portMasks
    ))
}
results.sort { $0.headroom(gates).value < $1.headroom(gates).value }

// MARK: Report

func mean(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }

try? FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)
var table = "rank\tspecies\tform\tsilhouette_iou\tline_iou\tcolour_delta\tline_colour_delta\theadroom\tlimit\t"
    + "silhouette_mismatch_px\tsilhouette_off_edge_px\tline_ref_px\tline_port_px\tline_mismatch_px\tline_off_edge_px\n"
print("rank  species               form              silhouette  lines   colour  line col  headroom  limit")
for (rank, result) in results.enumerated() {
    let headroom = result.headroom(gates)
    print(String(format: "%4d  ", rank + 1) + padded(result.id, 22) + padded(result.form, 16)
        + String(format: "%9.4f %8.4f %7.2f %8.2f %9.2f  ", result.silhouette.iou, result.line.iou,
                 result.colour, result.lineColour, headroom.value)
        + headroom.limit)
    table += "\(rank + 1)\t\(result.id)\t\(result.form)\t"
        + String(format: "%.5f\t%.5f\t%.3f\t%.3f\t%.3f\t", result.silhouette.iou, result.line.iou,
                 result.colour, result.lineColour, headroom.value)
        + "\(headroom.limit)\t\(result.silhouette.mismatched)\t\(result.silhouette.offEdge)\t"
        + "\(result.line.referencePixels)\t\(result.line.portPixels)\t\(result.line.mismatched)\t\(result.line.offEdge)\n"
}
try table.write(to: outDirectory.appendingPathComponent("fidelity.tsv"), atomically: true, encoding: .utf8)

struct Summary {
    let name: String
    let values: [Double]
    let ids: [String]
    let higherIsBetter: Bool
    let meanGate: Double
    let worstGate: Double

    var mean: Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }
    var worst: Double { (higherIsBetter ? values.min() : values.max()) ?? 0 }
    var worstID: String {
        guard Set(values).count > 1, let index = values.firstIndex(of: worst) else { return "all" }
        return ids[index]
    }
    var passed: Bool {
        higherIsBetter ? mean >= meanGate && worst >= worstGate : mean <= meanGate && worst <= worstGate
    }
    var line: String {
        let relation = higherIsBetter ? ">=" : "<="
        return padded(name, 24) + String(
            format: "mean %8.4f (%@ %.4g)   worst %8.4f (%@ %.4g, %@)   %@",
            mean, relation, meanGate, worst, relation, worstGate, worstID as NSString, passed ? "ok" : "FAIL"
        )
    }
}
let summaries = [
    Summary(name: "silhouette IoU", values: results.map(\.silhouette.iou), ids: results.map(\.id), higherIsBetter: true,
            meanGate: gates.silhouetteMean, worstGate: gates.silhouetteMin),
    Summary(name: "line IoU", values: results.map(\.line.iou), ids: results.map(\.id), higherIsBetter: true,
            meanGate: gates.lineMean, worstGate: gates.lineMin),
    Summary(name: "colour delta /255", values: results.map(\.colour), ids: results.map(\.id), higherIsBetter: false,
            meanGate: gates.colourMean, worstGate: gates.colourMax),
    Summary(name: "line colour delta /255", values: results.map(\.lineColour), ids: results.map(\.id), higherIsBetter: false,
            meanGate: gates.lineColourMean, worstGate: gates.lineColourMax),
    Summary(name: "off-edge mismatch px", values: results.map { Double($0.offEdge) }, ids: results.map(\.id),
            higherIsBetter: false, meanGate: gates.offEdgeMax, worstGate: gates.offEdgeMax),
]
print("\ncompared \(results.count) species")
for summary in summaries { print(summary.line) }
let silhouetteMismatched = results.map(\.silhouette.mismatched).reduce(0, +)
let silhouetteOffEdge = results.map(\.silhouette.offEdge).reduce(0, +)
let lineMismatched = results.map(\.line.mismatched).reduce(0, +)
let lineOffEdge = results.map(\.line.offEdge).reduce(0, +)
print(String(
    format: "mismatched pixels away from any edge of either mask: silhouette %d of %d (%.2f%%), lines %d of %d (%.2f%%)",
    silhouetteOffEdge, silhouetteMismatched,
    silhouetteMismatched == 0 ? 0 : 100 * Double(silhouetteOffEdge) / Double(silhouetteMismatched),
    lineOffEdge, lineMismatched, lineMismatched == 0 ? 0 : 100 * Double(lineOffEdge) / Double(lineMismatched)
))
if !missing.isEmpty {
    print("MISSING renders, rasters or exports for: \(missing.joined(separator: ", "))")
}

// MARK: Contact sheet of the worst 12: reference | port | mask difference | colour difference

/// Lines: dark grey in both, red only in the reference, blue only in the port. Silhouette: light grey in both,
/// pale red / pale blue in one only.
func maskDifference(_ result: Result) -> CGImage? {
    var pixels = [UInt8](repeating: 255, count: side * side * 4)
    let reference = result.referenceMasks, port = result.portMasks
    for index in 0..<(side * side) {
        let (r, g, b): (UInt8, UInt8, UInt8) = switch (reference.line[index], port.line[index]) {
        case (true, true): (110, 110, 110)
        case (true, false): (215, 25, 25)
        case (false, true): (25, 70, 225)
        case (false, false):
            switch (reference.silhouette[index], port.silhouette[index]) {
            case (true, true): (215, 215, 215)
            case (true, false): (245, 150, 150)
            case (false, true): (150, 175, 245)
            case (false, false): (255, 255, 255)
            }
        }
        pixels[index * 4] = r
        pixels[index * 4 + 1] = g
        pixels[index * 4 + 2] = b
        pixels[index * 4 + 3] = 255
    }
    return makeImage(&pixels)
}

/// The colour difference, darker where larger (black at 64/255 or more).
func colourDifference(_ result: Result) -> CGImage? {
    var pixels = [UInt8](repeating: 255, count: side * side * 4)
    for index in 0..<(side * side) {
        var difference = 0
        for channel in 0..<3 {
            difference = max(difference, abs(Int(result.reference.pixels[index * 4 + channel])
                - Int(result.port.pixels[index * 4 + channel])))
        }
        let value = UInt8(255 - min(255, difference * 4))
        pixels[index * 4] = value
        pixels[index * 4 + 1] = value
        pixels[index * 4 + 2] = value
        pixels[index * 4 + 3] = 255
    }
    return makeImage(&pixels)
}

let worst = Array(results.prefix(12))
let tile = 256, gutter = 16, label = 30, columns = 2, panels = 4
let rows = (worst.count + columns - 1) / columns
let header = 64
let sheetWidth = columns * (panels * tile) + (columns + 1) * gutter
let sheetHeight = header + rows * (tile + label + gutter) + gutter
if !worst.isEmpty, let sheet = CGContext(
    data: nil, width: sheetWidth, height: sheetHeight, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) {
    sheet.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.95, alpha: 1))
    sheet.fill(CGRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight))
    sheet.interpolationQuality = .high

    func text(_ string: String, x: Int, top: Int, size: CGFloat, bold: Bool = false) {
        let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
        let attributed = NSAttributedString(string: string, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.1, alpha: 1),
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        sheet.textPosition = CGPoint(x: CGFloat(x), y: CGFloat(sheetHeight - top) - size)
        CTLineDraw(line, sheet)
    }

    text(
        String(format: "Worst 12 of %d by headroom   reference | port | masks (lines dark grey, silhouette light grey; red = reference only, blue = port only) | colour difference (black = 64/255+)",
               results.count),
        x: gutter, top: 12, size: 15, bold: true
    )
    text(
        String(format: "silhouette IoU mean %.4f min %.4f   line IoU mean %.4f min %.4f   colour delta mean %.2f max %.2f   line colour delta mean %.2f max %.2f",
               summaries[0].mean, summaries[0].worst, summaries[1].mean, summaries[1].worst,
               summaries[2].mean, summaries[2].worst, summaries[3].mean, summaries[3].worst),
        x: gutter, top: 36, size: 15
    )
    for (index, result) in worst.enumerated() {
        let column = index % columns, row = index / columns
        let left = gutter + column * (panels * tile + gutter)
        let top = header + row * (tile + label + gutter)
        text(String(format: "%d. %@  (%@)  silhouette %.4f  lines %.4f  colour %.2f  line colour %.2f",
                    index + 1, result.id as NSString, result.form as NSString, result.silhouette.iou,
                    result.line.iou, result.colour, result.lineColour),
             x: left, top: top + 6, size: 14)
        let images = [result.reference.image, result.port.image, maskDifference(result), colourDifference(result)]
        for (slot, image) in images.enumerated() {
            guard let image else { continue }
            let frame = CGRect(x: left + slot * tile, y: sheetHeight - (top + label + tile), width: tile, height: tile)
            sheet.draw(image, in: frame)
            sheet.setStrokeColor(CGColor(gray: 0.75, alpha: 1))
            sheet.setLineWidth(1)
            sheet.stroke(frame.insetBy(dx: 0.5, dy: 0.5))
        }
    }
    if let image = sheet.makeImage() {
        let url = outDirectory.appendingPathComponent("contact-sheet.png")
        if let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
            print("contact sheet: \(url.path)")
        }
    }
}
print("table: \(outDirectory.appendingPathComponent("fidelity.tsv").path)")

let passed = missing.isEmpty && !results.isEmpty && summaries.allSatisfy(\.passed)
print(passed ? "PASS (every gate)" : "FAIL (see the gates above; every species must also be rendered)")
exit(passed ? 0 : 1)
