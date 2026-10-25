import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// Locked's emergency release (F1 design §5.7, F1-1): a full screen, with the tab bar tucked away.
///
/// - **Holding:** "Emergency release" over "Study · Locked". The dial is in the hold state, its marks filling
///   clockwise as "Hold to release" is held for 10 seconds, with "10s" over "hold to release" in the centre
///   ("keep holding" while pressed). Letting go early drains it, and leaving the foreground cancels it
///   (`HoldButton`). "Keep going" goes back to the session. There is no limit and no allowance.
/// - **Released:** the release happens when the hold completes, so the breath can't trap anyone. Then "Breathe in"
///   for 4 seconds and "and out" for 4, while the cool bloom swells and settles (a transform and an opacity), then
///   the ended state: "18m", "saved · they stay yours", "Session ended. It won't count as finished." and "Done".
///
/// The session screen shows the hold. Once the store has ended the session, the receipt route shows the released
/// stage from the session's end, so the breath carries on across the change and a later look opens on the ended
/// state.
struct EmergencyReleaseView: View {
    enum Stage: Hashable {
        /// The session runs: the 10-second hold.
        case holding
        /// Released at `endedAt` (trusted time): the breath, then the ended state.
        case released(endedAt: Date)
    }

    let session: SessionRecord
    let stage: Stage
    /// The receipt, once the session has ended: the ended dial's marks and its VoiceOver reading.
    let receipt: ReceiptModel?
    /// DEBUG still frames: this many seconds into the breath, frozen.
    let frozenSeconds: Double?
    let onKeepGoing: () -> Void
    let onRelease: () -> Void
    let onDone: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(FocusSessionStore.self) private var sessions

    @State private var holdProgress = 0.0
    /// The breath and the ended state's fade are over: the timeline stops.
    @State private var isSettled = false
    @State private var announcedEnd = false

    /// The breath, then the ended state's fade.
    private static var settledAfter: TimeInterval { EmergencyReleaseModel.breathSeconds + EmergencyReleaseModel.endedFade }

    init(
        session: SessionRecord, stage: Stage, receipt: ReceiptModel? = nil, frozenSeconds: Double? = nil,
        onKeepGoing: @escaping () -> Void = {}, onRelease: @escaping () -> Void = {}, onDone: @escaping () -> Void = {}
    ) {
        self.session = session
        self.stage = stage
        self.receipt = receipt
        self.frozenSeconds = frozenSeconds
        self.onKeepGoing = onKeepGoing
        self.onRelease = onRelease
        self.onDone = onDone
    }

    var body: some View {
        Group {
            switch stage {
            case .holding:
                screen(model(.hold(progress: holdProgress)))
            case .released(let endedAt):
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isSettled || frozenSeconds != nil)) { _ in
                    let seconds = frozenSeconds ?? sessions.now.timeIntervalSince(endedAt)
                    screen(model(.released(seconds: seconds)))
                }
            }
        }
        .toolbarVisibility(.hidden, for: .tabBar)
        .task(id: stage) { await settle() }
    }

    private func screen(_ model: EmergencyReleaseModel) -> some View {
        SessionScreen(title: model.title, subtitle: model.subtitle) { diameter in
            dial(model, diameter: diameter)
        } lines: {
            if let body = model.body {
                Text(body)
                    .font(MapleFont.callout)
                    .foregroundStyle(theme.colors.textPrimary)
                    .opacity(model.isEnded ? model.endedOpacity : 1)
            }
        } controls: {
            if let hold = model.holdTitle {
                HoldButton(
                    title: hold, duration: FocusCopy.Emergency.holdSeconds, accessibilityName: hold,
                    progress: $holdProgress, frozenProgress: frozenHold, onComplete: onRelease
                )
            }
            if let keepGoing = model.keepGoingTitle {
                TextLink(keepGoing, chevron: false, action: onKeepGoing)
            }
            if case .released = stage {
                // Done holds its place through the breath, so nothing moves when it fades in.
                Button(FocusCopy.done, action: onDone)
                    .buttonStyle(.moonlight)
                    .opacity(model.endedOpacity)
                    .allowsHitTesting(model.isEnded)
                    .accessibilityHidden(!model.isEnded)
            }
        }
        .onChange(of: model.isEnded) { _, ended in
            guard ended, !announcedEnd else { return }
            announcedEnd = true
            // The session ending is a milestone (§4.9).
            AccessibilityNotification.Announcement(FocusCopy.Emergency.endedLine).post()
        }
    }

    /// The hold's dial, the breath's (every mark held, the bloom swelling), and the ended state's (the receipt's
    /// marks), cross-fading as the ended state comes in. VoiceOver reads it as one element.
    private func dial(_ model: EmergencyReleaseModel, diameter: CGFloat) -> some View {
        let side = diameter * MinuteDialMetrics.bloomScale
        let held = model.holdTitle != nil ? holdProgress : 1
        return ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [theme.dial.restBloom, theme.dial.restBloom.opacity(0)], center: .center,
                    startRadius: 0, endRadius: side / 2
                ))
                .frame(width: side, height: side)
                .scaleEffect(model.bloomScale)
                .opacity(model.bloomOpacity)
                .allowsHitTesting(false)
            if model.endedOpacity < 1 {
                MinuteDial(frame: holdFrame(progress: held), diameter: diameter, theme: theme) {
                    centre(model, diameter: diameter)
                }
                .opacity(1 - model.endedOpacity)
            }
            if case .ended(let numeral, let caption) = model.centre {
                MinuteDial(frame: endedFrame, diameter: diameter, theme: theme) {
                    DialCentre(leaf: nil, numeral: DialCentre.numeralParts(numeral), caption: caption, diameter: diameter)
                }
                .opacity(model.endedOpacity)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(model.spoken ?? receipt?.dialLabel ?? endedReading(model)))
    }

    /// The hold dial's centre: the hold's countdown, then the breath's words. "Breathe in" cross-fades into "and out"
    /// by opacity alone (§4.6); the hold's seconds and its caption change at once. While the ended state fades in over
    /// it, the breath's last words stay.
    private func centre(_ model: EmergencyReleaseModel, diameter: CGFloat) -> some View {
        let words: CentreWords = switch model.centre {
        case .countdown(let numeral, let caption): CentreWords(numeral: numeral, caption: caption, breath: nil)
        case .breath(let breath): CentreWords(numeral: breath, caption: nil, breath: breath)
        case .ended: CentreWords(numeral: FocusCopy.Emergency.breatheOut, caption: nil, breath: FocusCopy.Emergency.breatheOut)
        }
        return FadingLine(words, key: words.breath) { words in
            DialCentre(leaf: nil, numeral: DialCentre.numeralParts(words.numeral), caption: words.caption, diameter: diameter)
        }
    }

    /// The hold's marks, filling clockwise; the bloom is drawn here instead, so the breath can swell it.
    private func holdFrame(progress: Double) -> DialFrame {
        var frame = DialFrame.hold(progress: progress)
        frame.bloom = .hidden
        return frame
    }

    /// The marks as the session counted them: the receipt's, or worked out from the credit while the receipt isn't
    /// there yet (the hold's last moment, and DEBUG still frames).
    private var endedFrame: DialFrame {
        let marks = receipt?.marks ?? ReceiptMarks.marks(
            layout: DialLayout(plannedMinutes: session.plan.plannedMinutes), countdownStart: session.countdownStart,
            stretches: sessions.credit(for: session.id)?.stretches ?? []
        )
        var frame = DialFrame.receipt(marks: marks, isGold: false, fill: DialFill())
        frame.bloom = .hidden
        return frame
    }

    private func endedReading(_ model: EmergencyReleaseModel) -> String {
        guard case .ended(let numeral, let caption) = model.centre else { return model.title }
        return "\(numeral), \(caption)"
    }

    private func model(_ stage: EmergencyReleaseModel.Stage) -> EmergencyReleaseModel {
        let end = session.endedAt ?? sessions.now
        return EmergencyReleaseModel(
            presetName: session.plan.presetName, countedSeconds: sessions.countedSoFar(session.id),
            focusedSeconds: Int(max(0, end.timeIntervalSince(session.countdownStart))), canCount: session.plan.canCount,
            stage: stage, reduceMotion: reduceMotion
        )
    }

    /// Stops the timeline once the breath and the fade are over.
    private func settle() async {
        guard case .released(let endedAt) = stage, frozenSeconds == nil else { return }
        isSettled = false
        let left = Self.settledAfter - sessions.now.timeIntervalSince(endedAt)
        if left > 0 { try? await Task.sleep(for: .seconds(left)) }
        guard !Task.isCancelled else { return }
        isSettled = true
    }

    /// `-MapleDemoHoldAt 0…1`: "Hold to release" frozen at that fill, and the dial with it.
    private var frozenHold: Double? {
        #if DEBUG
        return DemoLaunchOptions.current.holdAt
        #else
        return nil
        #endif
    }
}

/// The hold dial's centre words, and the breath's words that key their cross-fade (nil during the hold).
nonisolated private struct CentreWords: Equatable, Sendable {
    let numeral: String
    let caption: String?
    let breath: String?
}
