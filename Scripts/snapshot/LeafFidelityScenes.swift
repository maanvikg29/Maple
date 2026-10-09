// Scenes for Scripts/leaf-fidelity.sh: every species drawn by the native port (LeafView) in its autumn colour,
// framed by exactly the `viewBox` of its catalogue export, at 256 × 256 pt (512 × 512 px) on white.
//
// With LEAF_FIDELITY_CONTROLS=1 (leaf-fidelity.sh --controls) it also draws every species once per
// `LeafFidelityControl`, named "<control>--acer-<id>": the same leaf with one deliberate defect, so the script
// can check that the comparer fails each of them (and passes the unchanged `replica`).
// Compiled by Scripts/snapshot.sh together with MapleCore + MapleDesign; not part of the app.
import Foundation
import SwiftUI

@MainActor
func snapshotScenes() -> [SnapshotScene] {
    let environment = ProcessInfo.processInfo.environment
    guard let svgDirectory = environment["MAPLE_CATALOG_SVG"] else {
        fatalError("Set MAPLE_CATALOG_SVG to Catalog/svg/autumn (Scripts/leaf-fidelity.sh does this).")
    }
    let controls = environment["LEAF_FIDELITY_CONTROLS"] == "1" ? LeafFidelityControl.allCases : []
    let size = CGSize(width: 256, height: 256)
    return LeafCatalog.shared.species.flatMap { species -> [SnapshotScene] in
        let url = URL(fileURLWithPath: svgDirectory).appendingPathComponent("acer-\(species.id).svg")
        guard let svg = try? String(contentsOf: url, encoding: .utf8),
              let viewBox = leafFidelityViewBox(in: svg) else {
            print("SKIPPED \(species.id): no export or no viewBox at \(url.path)")
            return []
        }
        let port = SnapshotScene("acer-\(species.id)", size: size) {
            ZStack {
                Color.white
                LeafView(species, fill: .autumn, detail: .full, framing: .leafSpace(viewBox))
            }
        }
        return [port] + controls.map { control in
            SnapshotScene("\(control.rawValue)--acer-\(species.id)", size: size) {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                    let transform = LeafRenderer.transform(fitting: viewBox, into: CGRect(origin: .zero, size: size))
                    control.draw(species, in: context, transform: transform)
                }
            }
        }
    }
}

/// The export's `viewBox="minX minY width height"`.
func leafFidelityViewBox(in svg: String) -> CGRect? {
    let number = #"(-?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?)"#
    let pattern = #"viewBox="\s*"# + [String](repeating: number, count: 4).joined(separator: #"[\s,]+"#) + #"\s*""#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: svg, range: NSRange(svg.startIndex..., in: svg)) else {
        return nil
    }
    let values = (1...4).compactMap { index -> Double? in
        guard let range = Range(match.range(at: index), in: svg) else { return nil }
        return Double(svg[range])
    }
    guard values.count == 4, values[2] > 0, values[3] > 0 else { return nil }
    return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
}

/// Negative controls for the comparer. `replica` redoes `LeafRenderer.draw` step by step and must pass; every
/// other case changes exactly one thing and must fail at least one gate. Together they cover each gate: outer
/// shape (`tilt`, `smooth`), lines (`noVeins`, `thinVeins`, `fullLengthVeins`, `outlineInFill`) and colour
/// (`strongVeins`, `fillShift`).
enum LeafFidelityControl: String, CaseIterable {
    case replica
    /// Fill, outline and stalk only.
    case noVeins = "no-veins"
    /// Veins 0.6 units wide instead of 0.9.
    case thinVeins = "thin-veins"
    /// Veins drawn to the lobe tips instead of 86 % of the way.
    case fullLengthVeins = "full-length-veins"
    /// Veins at 75 % opacity instead of 55 %.
    case strongVeins = "strong-veins"
    /// The outline stroked in the fill colour.
    case outlineInFill = "outline-in-fill"
    /// The fill 10/255 lighter in every channel.
    case fillShift = "fill-shift"
    /// One degree more tilt.
    case tilt
    /// No teeth (margin drawn smooth).
    case smooth

    func draw(_ species: LeafSpecies, in context: GraphicsContext, transform: CGAffineTransform) {
        var context = context
        context.concatenate(transform)
        if self == .tilt {
            context.concatenate(CGAffineTransform(rotationAngle: .pi / 180))
        }
        let geometry = self == .smooth
            ? LeafGeometry(id: species.id, form: species.form, lobes: species.lobes, depth: species.depth,
                           margin: .smooth, evergreen: species.evergreen)
            : LeafGeometry.of(species)
        let autumn = species.autumnColor
        let fillColour = self == .fillShift
            ? LeafColor(red: min(autumn.red + 10, 255), green: min(autumn.green + 10, 255), blue: min(autumn.blue + 10, 255))
            : autumn
        let fill = Color(hex: fillColour.rgb)
        let line = Color(hex: autumn.veinColor.rgb)

        context.stroke(
            geometry.petiolePath, with: .color(line),
            style: StrokeStyle(lineWidth: LeafGeometry.Stroke.petiole, lineCap: .round)
        )
        let outline = StrokeStyle(lineWidth: LeafGeometry.Stroke.outline, lineJoin: .round)
        for blade in geometry.bladePaths {
            context.fill(blade, with: .color(fill))
            context.stroke(blade, with: .color(self == .outlineInFill ? fill : line), style: outline)
        }
        guard self != .noVeins else { return }
        let veins = self == .fullLengthVeins
            ? geometry.veins.map { vein in
                Path { path in
                    path.move(to: vein.start)
                    path.addLine(to: vein.end)
                }
                .applying(geometry.placement)
            }
            : geometry.veinPaths
        let opacity = self == .strongVeins ? 0.75 : LeafGeometry.Stroke.veinOpacity
        let width = self == .thinVeins ? 0.6 : LeafGeometry.Stroke.vein
        for vein in veins {
            context.stroke(vein, with: .color(line.opacity(opacity)), lineWidth: width)
        }
    }
}
