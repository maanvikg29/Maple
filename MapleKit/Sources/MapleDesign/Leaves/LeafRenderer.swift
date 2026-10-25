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

/// How a locked leaf's progress fills its blades, rising from the stalk (F1 design §4.3).
///
/// ```swift
/// LeafView(species, style: .skeleton(stroke: tint.opacity(0.6), vein: .white.opacity(0.15)),
///          progress: .twoTone(before: 0.4, session: 0.2, edge: true),
///          palette: LeafFill.Palette(before: theme.dial.goldSoft, session: theme.dial.gold, edge: theme.dial.goldEdge))
/// ```
nonisolated public enum LeafFill: Sendable, Equatable {
    /// One even coat up to `fraction` (0...1) of the leaf's length, in the palette's `session` colour: what
    /// `LeafView.progressFill(fraction:colour:opacity:)` draws.
    case single(Double)
    /// Two coats: `before` (the part saved before this session) in the palette's `before` colour, then `session`
    /// more on top of it in `session`, with a light line in `edge` along the top of the fill when `edge` is true.
    /// Both are fractions of the leaf's length; together they stop at the tip.
    case twoTone(before: Double, session: Double, edge: Bool)

    /// The colours a fill is drawn in.
    public struct Palette: Sendable, Equatable {
        public var before: Color
        public var session: Color
        public var edge: Color

        public init(before: Color, session: Color, edge: Color) {
            self.before = before
            self.session = session
            self.edge = edge
        }
    }

    /// Where the `session` coat starts, 0...1: the top of the `before` coat, or 0 for one coat.
    public var split: Double {
        switch self {
        case .single: 0
        case .twoTone(let before, _, _): Self.unit(before)
        }
    }

    /// The top of the whole fill, 0...1.
    public var top: Double {
        switch self {
        case .single(let fraction): Self.unit(fraction)
        case .twoTone(_, let session, _): min(1, split + Self.unit(session))
        }
    }

    /// Whether the edge is drawn: asked for, and the fill line is inside the leaf (not at the stalk or the tip).
    public var showsEdge: Bool {
        guard case .twoTone(_, _, true) = self else { return false }
        return top > 0 && top < 1
    }

    /// `value` clamped to 0...1, with anything not finite as nothing (as `drawProgressFill` always treated it).
    static func unit(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
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
        drawProgressFill(
            geometry, in: context, transform: transform, fill: .single(fraction),
            palette: LeafFill.Palette(before: .clear, session: color, edge: .clear)
        )
    }

    /// Fills the blades as `fill` says, rising from their bottom along the leaf's own axis, then draws its edge:
    /// the dial's two-tone leaf (F1 design §4.3). Drawn before the skeleton; `transform` is the one
    /// `draw(_:in:transform:style:)` takes.
    public static func drawProgressFill(
        _ geometry: LeafGeometry, in context: GraphicsContext, transform: CGAffineTransform,
        fill: LeafFill, palette: LeafFill.Palette
    ) {
        let top = fill.top
        let split = fill.split
        guard top > 0 else { return }
        if split > 0 {
            drawBand(geometry, in: context, transform: transform, from: 0, to: split, color: palette.before)
        }
        if top > split {
            drawBand(geometry, in: context, transform: transform, from: split, to: top, color: palette.session)
        }
        if fill.showsEdge {
            // A 1-point line across the leaf at the fill line, inside the silhouette.
            var context = context
            context.clip(to: geometry.silhouettePath.applying(transform))
            let level = level(of: top, in: geometry)
            var line = Path()
            line.move(to: CGPoint(x: -200, y: level))
            line.addLine(to: CGPoint(x: 200, y: level))
            context.stroke(
                line.applying(geometry.placement.concatenating(transform)),
                with: .color(palette.edge), lineWidth: 1
            )
        }
    }

    /// The silhouette between `lower` and `upper` (fractions of the blades' length up from the stalk end), in `color`.
    private static func drawBand(
        _ geometry: LeafGeometry, in context: GraphicsContext, transform: CGAffineTransform,
        from lower: Double, to upper: Double, color: Color
    ) {
        let top = level(of: upper, in: geometry)
        // The first band reaches past the -100...100 box below, exactly as one coat always did.
        let bottom = lower > 0 ? level(of: lower, in: geometry) : top + 400
        let band = Path(CGRect(x: -200, y: top, width: 400, height: bottom - top))
            .applying(geometry.placement.concatenating(transform))
        var context = context
        context.clip(to: band)
        context.fill(geometry.silhouettePath.applying(transform), with: .color(color))
    }

    /// The leaf-space y of `fraction` of the blades' length, up from the stalk end (y points down).
    private static func level(of fraction: Double, in geometry: LeafGeometry) -> CGFloat {
        let extent = geometry.bladeExtent
        return extent.upperBound - CGFloat(fraction) * (extent.upperBound - extent.lowerBound)
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
