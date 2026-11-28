import MapleCore
import MapleDesign
import SwiftUI

/// A running session with the van: Pip up in the maple with his pail, leaves coming down, and the time left under
/// the tree (syrup van design §6.5).
///
/// The maple, Pip and the leaves are cut from the concept picture, pixel for pixel
/// (`Scripts/art/concept/build_concept_art.py`). The leaves in the air are an animation only: the screen never shows
/// how many leaves the session has earned, or how fast.
struct VanTreeSessionView: View {
    let title: String
    let subtitle: String?
    /// "24:10".
    let time: String
    /// "left of 50m".
    let caption: String
    /// What VoiceOver reads for the time.
    let spoken: String
    let endTitle: String
    let breakTitle: String?
    /// After 30 seconds without a touch the scene goes dim.
    let dimmed: Bool
    let onMinimise: () -> Void
    let onEnd: () -> Void
    let onBreak: () -> Void
    var controlsFocused: AccessibilityFocusState<Bool>.Binding

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        ZStack {
            VanPalette.sky.ignoresSafeArea()
            GeometryReader { proxy in
                let canvas = VanCanvas.tree
                let scale = canvas.scale(width: proxy.size.width, height: proxy.size.height)
                ZStack {
                    Image("VanTreeScene")
                        .resizable()
                        .frame(width: canvas.width * scale, height: canvas.height * scale)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    // Pip breathes and blinks, and the string lights twinkle; dimmed, all of it rests.
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: dimmed || reduceMotion)) { timeline in
                        let time = reduceMotion ? 0 : timeline.date.timeIntervalSince(start)
                        let idle = PipIdle.pose(at: time)
                        ZStack {
                            VanTreeLights(time: time, canvas: canvas)
                            // The leaves come down behind Pip, so none lands on his face.
                            VanFallingLeaves(canvas: canvas, time: time, count: 13)
                            ZStack {
                                Image("VanTreePip")
                                    .resizable()
                                if idle.asleep {
                                    Image("VanTreePipLids")
                                        .resizable()
                                }
                            }
                            .frame(width: VanTreePip.width * scale, height: VanTreePip.height * scale)
                            .scaleEffect(x: idle.stretchX, y: idle.stretchY, anchor: VanTreePip.feet)
                            .position(canvas.point(VanTreePip.centreX, VanTreePip.centreY, in: proxy.size))
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
            // The system's clock and battery are white: a soft shade keeps them readable on the canopy.
            LinearGradient(colors: [VanPalette.outline.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 110)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            if dimmed {
                VanPalette.outline.opacity(0.45).ignoresSafeArea().allowsHitTesting(false)
            }
            words
        }
        .animation(.easeInOut(duration: 0.6), value: dimmed)
    }

    private var words: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: onMinimise) {
                    Image(systemName: "chevron.down")
                        .font(.system(.body, design: .rounded).weight(.heavy))
                        .foregroundStyle(VanPalette.outline)
                        .frame(width: 44, height: 44)
                        .background(VanPalette.cream, in: Circle())
                        .overlay(Circle().strokeBorder(VanPalette.outline, lineWidth: 2.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Minimise")
                // One line, so the plate stays clear of Pip's ears.
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .lineLimit(1)
                    .foregroundStyle(VanPalette.outline)
                    .modifier(VanPlate(horizontal: 14))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer(minLength: 0)
            VStack(spacing: -2) {
                Text(time)
                    .font(.system(size: 60, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(caption)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .opacity(0.7)
                        .padding(.top, 6)
                }
            }
            .foregroundStyle(VanPalette.outline)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text([spoken, subtitle].compactMap { $0 }.joined(separator: " ")))
            .padding(.bottom, 14)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { buttons }
                VStack(spacing: 8) { buttons }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .vanChrome()
    }

    @ViewBuilder
    private var buttons: some View {
        if let breakTitle {
            plateButton(breakTitle, fill: VanPalette.cream, action: onBreak)
        }
        plateButton(endTitle, fill: VanPalette.cream, action: onEnd)
            .accessibilityFocused(controlsFocused)
    }

    private func plateButton(_ title: String, fill: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(VanPalette.outline)
                .lineLimit(1)
                .fixedSize()
                .modifier(VanPlate(fill: fill, horizontal: 22))
        }
        .buttonStyle(.plain)
    }
}

/// Leaves coming down from the canopy to the grass: the concept's own three leaves, placed by `FallingLeaves`, swinging
/// as they fall and carried by its gusts. With Reduce Motion they hang still.
struct VanFallingLeaves: View {
    let canvas: VanCanvas
    /// Seconds since the scene appeared.
    let time: Double
    var count = FallingLeaves.defaultCount

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let names = ["VanLeafOrange", "VanLeafYellow", "VanLeafRed"]
    /// In the canvas's own units: out of the canopy, down to the grass; a leaf is about this wide.
    private static let top = 620.0
    private static let bottom = 1720.0
    private static let leafWidth = 104.0

    var body: some View {
        let seconds = reduceMotion ? 4 : time
        Canvas { context, size in
            let scale = canvas.scale(width: size.width, height: size.height)
            let left = (size.width - canvas.width * scale) / 2
            let topEdge = (size.height - canvas.height * scale) / 2
            for leaf in FallingLeaves.leaves(at: seconds, count: count) {
                let image = context.resolve(Image(Self.names[leaf.colour]))
                let width = Self.leafWidth * leaf.size * scale
                let height = width * image.size.height / max(1, image.size.width)
                var drawing = context
                drawing.opacity = leaf.opacity
                drawing.translateBy(
                    x: left + leaf.x * canvas.width * scale,
                    y: topEdge + (Self.top + (Self.bottom - Self.top) * leaf.fall) * scale
                )
                drawing.rotate(by: .radians(leaf.turn))
                drawing.draw(image, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
            }
        }
        .allowsHitTesting(false)
    }
}

/// The string lights round the maple's trunk, twinkling: a soft glow over each bulb, drawn by Maple in the bulbs' own
/// colour (`VanAmbience.bulb`).
struct VanTreeLights: View {
    let time: Double
    let canvas: VanCanvas

    /// The bulbs in the tree picture.
    private static let bulbs: [(x: Double, y: Double)] = [(238, 875), (295, 917), (370, 937), (442, 933)]

    var body: some View {
        Canvas { context, size in
            let scale = canvas.scale(width: size.width, height: size.height)
            var glow = context
            glow.blendMode = .screen
            for (index, bulb) in Self.bulbs.enumerated() {
                let middle = canvas.point(bulb.x, bulb.y, in: size)
                let radius = 48 * scale
                var drawing = glow
                drawing.opacity = 0.15 + 0.6 * VanAmbience.bulb(index, at: time)
                let colour = Color(red: 1, green: 0.93, blue: 0.62)
                drawing.fill(
                    Path(ellipseIn: CGRect(x: middle.x - radius, y: middle.y - radius, width: 2 * radius, height: 2 * radius)),
                    with: .radialGradient(
                        Gradient(colors: [colour, colour.opacity(0.5), colour.opacity(0)]), center: middle, startRadius: 0,
                        endRadius: radius
                    )
                )
            }
        }
        .allowsHitTesting(false)
    }
}
