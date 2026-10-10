import MapleCore
import SwiftUI

/// The sky behind Home's tree (spec §4.4): the phase's gradient, dawn wash and light pools, 48 stars, the crescent
/// moon and its moonlight, dissolving into the background from y 460 to 540. Lay it out at the scene's size
/// (402 × 560 on an iPhone 17); it scales to fit any size.
///
/// ```swift
/// ScrollView { … }
///     .background(alignment: .top) {
///         SkyBackdrop(phase: .evening, season: .autumn, vitality: 1).frame(height: 560).ignoresSafeArea(edges: .top)
///     }
/// ```
///
/// Stars twinkle on 6–12 s periods in the evening and at night (vitality ≥ 0.6). Under Reduce Motion, in Low Power
/// Mode or with `time` set, the sky is one still frame.
public struct SkyBackdrop: View {
    private let phase: NowPhase
    private let season: Season
    private let vitality: Double
    private let time: Date?

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(phase: NowPhase, season: Season, vitality: Double = 1, time: Date? = nil) {
        self.phase = phase
        self.season = season
        self.vitality = vitality
        self.time = time
    }

    public var body: some View {
        let palette = theme.colors.scene.sky(for: phase)
        let background = theme.colors.background
        let twinkles = palette.twinklingStars > 0 && vitality >= 0.6 && !reduceMotion && time == nil
        Group {
            if twinkles {
                TimelineView(.animation(minimumInterval: 1 / 15)) { timeline in
                    canvas(palette, background: background, time: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                canvas(palette, background: background, time: reduceMotion ? nil : time?.timeIntervalSinceReferenceDate)
            }
        }
        .accessibilityHidden(true)
    }

    private func canvas(_ palette: SkyPalette, background: Color, time: Double?) -> some View {
        let vitality = vitality
        return Canvas { context, size in
            let frame = TreeSceneFrame(size: size)
            TreeSkyPainter.draw(palette, frame: frame, time: time, vitality: vitality, crown: CGPoint(x: 201, y: 300), background: background, in: context)
            TreePainter.drawDissolve(frame: frame, color: background, in: context)
        }
    }
}
