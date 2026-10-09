import MapleCore
import SwiftUI

/// Colours and level of detail for drawing a leaf.
nonisolated public struct LeafStyle: Sendable, Equatable {
    public enum Detail: Sendable, Hashable {
        /// Blades, outline, veins and stalk, as in the catalogue drawings.
        case full
        /// Blades and stalk only. Outline and veins would be sub-pixel at small sizes.
        case fillOnly
        /// Outline, stalk and veins only, with no fill: the skeleton of a leaf that is not earned yet.
        /// Line widths are in points, so the skeleton reads the same at any size. See `LeafStyle.skeleton`.
        case skeleton(outlineWidth: CGFloat, veinWidth: CGFloat)
    }

    /// The blades. Unused by `.skeleton`.
    public var fill: Color
    /// Veins, and also the outline and stalk unless `outline` is set. In `.full` detail veins are drawn at
    /// `LeafGeometry.Stroke.veinOpacity` on top of this.
    public var vein: Color
    /// Outline and stalk, when they differ from `vein` (skeletons).
    public var outline: Color?
    public var detail: Detail

    public init(fill: Color, vein: Color, outline: Color? = nil, detail: Detail = .full) {
        self.fill = fill
        self.vein = vein
        self.outline = outline
        self.detail = detail
    }

    /// A locked leaf's skeleton: outline and stalk in `stroke`, veins in `vein`, no fill. Lines keep their
    /// width in points at any leaf size; translucent colours stay even where lines meet.
    ///
    /// ```swift
    /// LeafView(species, style: .skeleton(stroke: Color(hex: 0x8A96AD, opacity: 0.35), vein: .white.opacity(0.1)))
    /// ```
    public static func skeleton(stroke: Color, vein: Color, outlineWidth: CGFloat = 1, veinWidth: CGFloat = 0.75) -> LeafStyle {
        LeafStyle(fill: .clear, vein: vein, outline: stroke, detail: .skeleton(outlineWidth: outlineWidth, veinWidth: veinWidth))
    }
}

extension LeafStyle {
    /// A style whose outline, veins and stalk use the fill's `LeafColor.veinColor`, as in the original drawings.
    public init(fill: LeafColor, detail: Detail = .full) {
        self.init(fill: Color(hex: fill.rgb), vein: Color(hex: fill.veinColor.rgb), detail: detail)
    }
}

/// Draws leaves into a `GraphicsContext`. Callable from any `Canvas` (including off the main actor),
/// so a scene such as the home tree can draw hundreds of cached leaves per frame:
///
/// ```swift
/// Canvas { context, size in
///     for leaf in leaves {
///         LeafRenderer.draw(LeafGeometry.of(leaf.species), in: context, fitting: leaf.rect, style: leaf.style)
///     }
/// }
/// ```
nonisolated public enum LeafRenderer {
    /// Draws the leaf with its `frame` (the export's fitted square) aspect-fitted and centred in `rect`.
    public static func draw(_ geometry: LeafGeometry, in context: GraphicsContext, fitting rect: CGRect, style: LeafStyle) {
        draw(geometry, in: context, transform: transform(fitting: geometry.frame, into: rect), style: style)
    }

    /// Draws the leaf through `transform`, which maps placed leaf space (see `LeafGeometry.placement`)
    /// into the context. Stroke widths scale with it, like the SVG exports, except in `.skeleton` detail,
    /// whose lines are a fixed number of points wide.
    public static func draw(_ geometry: LeafGeometry, in context: GraphicsContext, transform: CGAffineTransform, style: LeafStyle) {
        if case .skeleton(let outlineWidth, let veinWidth) = style.detail {
            drawSkeleton(geometry, in: context, transform: transform, style: style,
                         outlineWidth: outlineWidth, veinWidth: veinWidth)
            return
        }
        var context = context
        context.concatenate(transform)
        let lineShading = GraphicsContext.Shading.color(style.outline ?? style.vein)
        context.stroke(
            geometry.petiolePath,
            with: lineShading,
            style: StrokeStyle(lineWidth: LeafGeometry.Stroke.petiole, lineCap: .round)
        )
        switch style.detail {
        case .fillOnly, .skeleton:
            context.fill(geometry.silhouettePath, with: .color(style.fill))
        case .full:
            let outline = StrokeStyle(lineWidth: LeafGeometry.Stroke.outline, lineJoin: .round)
            for blade in geometry.bladePaths {
                context.fill(blade, with: .color(style.fill))
                context.stroke(blade, with: lineShading, style: outline)
            }
            // Each vein is its own translucent stroke, so crossings darken as they did in the SVGs.
            let veinColor = GraphicsContext.Shading.color(style.vein.opacity(LeafGeometry.Stroke.veinOpacity))
            for vein in geometry.veinPaths {
                context.stroke(vein, with: veinColor, lineWidth: LeafGeometry.Stroke.vein)
            }
        }
    }

    /// Fills the blades from their bottom (where the stalk joins) up to `fraction` (0...1) of their length,
    /// measured along the leaf's own axis, in one even coat of `color`: progress towards a locked leaf, drawn
    /// before its skeleton. `transform` is the same one `draw(_:in:transform:style:)` takes.
    public static func drawProgressFill(
        _ geometry: LeafGeometry, in context: GraphicsContext, transform: CGAffineTransform,
        fraction: Double, color: Color
    ) {
        let fraction = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        guard fraction > 0 else { return }
        let extent = geometry.bladeExtent
        let level = extent.upperBound - CGFloat(fraction) * (extent.upperBound - extent.lowerBound)
        // Everything below `level` in leaf space (y points down), with a margin past the -100...100 box.
        let below = Path(CGRect(x: -200, y: level, width: 400, height: 400))
            .applying(geometry.placement.concatenating(transform))
        var context = context
        context.clip(to: below)
        context.fill(geometry.silhouettePath.applying(transform), with: .color(color))
    }

    /// Outline, stalk and veins stroked in device space, so their widths are in points. Each colour is drawn
    /// opaque into its own layer, which then takes the colour's opacity once, so translucent lines don't
    /// darken where they meet.
    private static func drawSkeleton(
        _ geometry: LeafGeometry, in context: GraphicsContext, transform: CGAffineTransform, style: LeafStyle,
        outlineWidth: CGFloat, veinWidth: CGFloat
    ) {
        let lines = StrokeStyle(lineWidth: outlineWidth, lineCap: .round, lineJoin: .round)
        let outlines = geometry.bladePaths.map { $0.applying(transform) } + [geometry.petiolePath.applying(transform)]
        strokeEvenly(outlines, color: style.outline ?? style.vein, style: lines, in: context)
        let veins = geometry.veinPaths.map { $0.applying(transform) }
        strokeEvenly(veins, color: style.vein, style: StrokeStyle(lineWidth: veinWidth, lineCap: .round), in: context)
    }

    private static func strokeEvenly(_ paths: [Path], color: Color, style: StrokeStyle, in context: GraphicsContext) {
        var resolved = color.resolve(in: context.environment)
        let opacity = Double(resolved.opacity)
        guard opacity > 0 else { return }
        resolved.opacity = 1
        var context = context
        context.opacity *= opacity
        context.drawLayer { layer in
            for path in paths {
                layer.stroke(path, with: .color(Color(resolved)), style: style)
            }
        }
    }

    /// The transform that aspect-fits the leaf-space rectangle `region` into `rect`, centred.
    public static func transform(fitting region: CGRect, into rect: CGRect) -> CGAffineTransform {
        guard region.width > 0, region.height > 0 else { return .identity }
        let scale = min(rect.width / region.width, rect.height / region.height)
        return CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -region.midX, y: -region.midY)
    }
}
