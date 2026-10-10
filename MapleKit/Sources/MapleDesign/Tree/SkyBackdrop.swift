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
/// Stars twinkle on 6–12 s periods in the evening and at night (vitality ≥ 0.6). Under Reduce Motion, or with `time`
/// set, the sky is one still frame. The twinkle pauses on its last frame, as the maple does (spec §4.9): when `paused`,
/// under a full-screen cover (`\.treeScenesPaused`), after the night's idle minute (`nightIdleFreeze(phase:)`), in Low
/// Power Mode, while the app is inactive and off screen.
public struct SkyBackdrop: View {
    private let phase: NowPhase
    private let season: Season
    private let vitality: Double
    private let time: Date?
    private let paused: Bool

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.treeScenesPaused) private var isCovered
    @Environment(\.nightIdleFrozen) private var nightFrozen
    @State private var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var isOnScreen = true

    /// - Parameter paused: Hold the twinkle's current frame (the caller's own reasons; the system ones are built in).
    public init(phase: NowPhase, season: Season, vitality: Double = 1, time: Date? = nil, paused: Bool = false) {
        self.phase = phase
        self.season = season
        self.vitality = vitality
        self.time = time
        self.paused = paused
    }

    public var body: some View {
        let palette = theme.colors.scene.sky(for: phase)
        let background = theme.colors.background
        let twinkles = palette.twinklingStars > 0 && vitality >= 0.6 && !reduceMotion && time == nil
        Group {
            if twinkles {
                TimelineView(.animation(minimumInterval: 1 / 15, paused: isPaused)) { timeline in
                    canvas(palette, background: background, time: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                canvas(palette, background: background, time: reduceMotion ? nil : time?.timeIntervalSinceReferenceDate)
            }
        }
        .onScrollVisibilityChange(threshold: 0.05) { isOnScreen = $0 }
        .onLowPowerModeChange { isLowPower = $0 }
        .accessibilityHidden(true)
    }

    /// The twinkle holds its last frame.
    private var isPaused: Bool {
        paused || isCovered || nightFrozen == true || isLowPower || scenePhase != .active || !isOnScreen
    }

    private func canvas(_ palette: SkyPalette, background: Color, time: Double?) -> some View {
        let vitality = vitality
        return Canvas { context, size in
            let frame = TreeSceneFrame(size: size)
            TreeSkyPainter.draw(palette, frame: frame, time: time, vitality: vitality, crown: Self.crown, background: background, in: context)
            TreePainter.drawDissolve(frame: frame, color: background, in: context)
        }
    }

    /// Where the moonlight reaches toward (reference frame).
    static let crown = CGPoint(x: 201, y: 300)
}

/// The sky above a `SkyBackdrop`, continuing it upward: the gradient's top colour with the morning and day light
/// pools and the moonlight carried across, so no seam shows where the two meet. Home lays one directly above its
/// backdrop; it shows when the scroll is pulled down, and under the header when the stage is shrunk for
/// accessibility text sizes (which brings the backdrop's top edge into view). Always one still frame: the stars
/// and the moon lie below it.
///
/// ```swift
/// VStack(spacing: 0) {
///     SkyBackdropExtension(phase: .morning, backdropSize: size).frame(width: size.width, height: 600)
///     SkyBackdrop(phase: .morning, season: .autumn).frame(width: size.width, height: size.height)
/// }
/// ```
public struct SkyBackdropExtension: View {
    private let phase: NowPhase
    private let backdropSize: CGSize

    @Environment(\.theme) private var theme

    /// - Parameter backdropSize: The size the `SkyBackdrop` below is laid out at.
    public init(phase: NowPhase, backdropSize: CGSize) {
        self.phase = phase
        self.backdropSize = backdropSize
    }

    public var body: some View {
        let palette = theme.colors.scene.sky(for: phase)
        let background = theme.colors.background
        let backdropSize = backdropSize
        Canvas { context, size in
            let frame = Self.frame(backdropSize: backdropSize, size: size)
            TreeSkyPainter.draw(palette, frame: frame, time: nil, vitality: 1, crown: SkyBackdrop.crown, background: background, in: context)
        }
        .accessibilityHidden(true)
    }

    /// The backdrop's scene frame seen from the extension: the same scale, with the scene starting at the
    /// extension's bottom edge, so everything the backdrop draws past its top edge lands here.
    static func frame(backdropSize: CGSize, size: CGSize) -> TreeSceneFrame {
        var frame = TreeSceneFrame(size: backdropSize)
        frame.origin.y += size.height
        frame.size = size
        return frame
    }
}
