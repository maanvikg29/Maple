import MapleCore
import MapleDesign
import SwiftUI

/// One short moment at the maple, between a session and its receipt (syrup van design §6.6, §6.7): Pip tumbling out
/// of the tree when a session ends early, or hopping down and walking off toward the van when it finishes.
///
/// It plays once and calls `onDone`. A tap skips the walk. With Reduce Motion it is one still frame, held a moment.
struct VanTreeMomentView: View {
    enum Kind {
        /// Ended early: the tumble, and the pail's leaves scattering. The session's leaves are lost.
        case tumble
        /// Finished: the walk back with the pail.
        case walkBack

        var seconds: Double {
            switch self {
            case .tumble: PipFall.seconds
            case .walkBack: PipWalk.seconds
            }
        }
    }

    let kind: Kind
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var finished = false
    /// DEBUG `-MapleDemoMomentAt <seconds>`: the moment held at that time, for a screenshot.
    private let heldAt: Double? = {
        #if DEBUG
        UserDefaults.standard.string(forKey: "MapleDemoMomentAt").flatMap(Double.init)
        #else
        nil
        #endif
    }()

    private static let leaves = ["VanLeafOrange", "VanLeafYellow", "VanLeafRed"]

    var body: some View {
        ZStack {
            VanPalette.sky.ignoresSafeArea()
            TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion || finished || heldAt != nil)) { timeline in
                // Still: the tumble's last frame (Pip sitting up on the grass), the walk's first steps on the grass.
                let time = heldAt ?? (reduceMotion ? (kind == .tumble ? kind.seconds : 1.2) : timeline.date.timeIntervalSince(start))
                GeometryReader { proxy in
                    let canvas = VanCanvas.tree
                    let scale = canvas.scale(width: proxy.size.width, height: proxy.size.height)
                    let pose = kind == .tumble ? PipFall.pose(at: time) : PipWalk.pose(at: time)
                    let place = { (x: Double, y: Double) in canvas.point(VanTreePip.centreX + x, VanTreePip.centreY + y, in: proxy.size) }
                    ZStack {
                        Image("VanTreeScene")
                            .resizable()
                            .frame(width: canvas.width * scale, height: canvas.height * scale)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        if kind == .tumble {
                            // Dust where he and the pail land (drawn by Maple, in the grass's colour made pale).
                            ForEach(Array(PipFall.dust(at: time).enumerated()), id: \.offset) { _, puff in
                                Circle()
                                    .fill(VanPalette.dust)
                                    .frame(width: 2 * puff.radius * scale, height: 2 * puff.radius * scale)
                                    .opacity(puff.opacity)
                                    .position(place(puff.x, puff.y))
                            }
                            // The pail, out of his paw: it turns about its own middle.
                            let pail = PipFall.pail(at: time)
                            Image("VanTreePail")
                                .resizable()
                                .frame(width: VanTreePip.width * scale, height: VanTreePip.height * scale)
                                .rotationEffect(.radians(pail.turn), anchor: VanTreePip.pailMiddle)
                                .position(place(pail.x, pail.y))
                        }
                        Image(kind == .tumble ? "VanTreePipAlone" : "VanTreePip")
                            .resizable()
                            .frame(width: VanTreePip.width * scale, height: VanTreePip.height * scale)
                            // He squashes onto his feet, and turns about his middle.
                            .scaleEffect(x: 1 + (1 - pose.squash) * 0.5, y: pose.squash, anchor: .bottom)
                            .rotationEffect(.radians(pose.turn))
                            .position(place(pose.x, pose.y))
                        if kind == .tumble {
                            // The pail's leaves, out of its mouth and fluttering down over everything.
                            ForEach(Array(PipFall.spill(at: time).enumerated()), id: \.offset) { _, leaf in
                                Image(Self.leaves[leaf.colour])
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 92 * leaf.size * scale)
                                    .rotationEffect(.radians(leaf.turn))
                                    .opacity(leaf.opacity)
                                    .position(place(leaf.x, leaf.y))
                            }
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                }
                .ignoresSafeArea()
            }
            // The system's clock and battery are white: a soft shade keeps them readable on the canopy.
            LinearGradient(colors: [VanPalette.outline.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 110)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // The walk can be skipped; the tumble is short and the session is already ending behind it.
            if kind == .walkBack { finish() }
        }
        .accessibilityElement()
        .accessibilityLabel(kind == .tumble ? "Pip tumbles out of the tree onto the grass" : "Pip walks back to the van with his pail of leaves")
        .accessibilityAddTraits(kind == .walkBack ? .isButton : [])
        .task {
            start = Date()
            guard heldAt == nil else { return }
            try? await Task.sleep(for: .seconds(reduceMotion ? 1.0 : kind.seconds + 0.25))
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onDone()
    }
}

/// Pip's picture on the tree's canvas: his feet in the fork of the trunk (`PIP_FEET`, `PIP_SCALE` and `PIP_BOX` in
/// `Scripts/art/concept/build_concept_art.py`).
enum VanTreePip {
    static let width = 610 * 0.61
    static let height = 580 * 0.61
    static let centreX = 440 + (305 - 310) * 0.61
    static let centreY = 668 + (290 - 555) * 0.61
    /// The pail's middle in his square (`PAIL_MIDDLE`), which it turns about once it flies.
    static let pailMiddle = UnitPoint(x: 494.0 / 610, y: 476.0 / 580)
}
