import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// After End early's sheet (F1-32): a full screen in the session's place, with the tab bar tucked away.
///
/// - **The breath:** "Breathe in" for 4 seconds and "and out" for 4, once for Gentle and twice for Steady, inside the
///   session's own dial. A soft disc fills the dial as the breath comes in and empties as it goes out, and the cool
///   bloom swells with it (a transform and an opacity; under Reduce Motion only the opacity). Under the dial: "One
///   slow breath before you decide."
/// - **The second question:** the dial shows the minutes saved so far, and under it "Still want to end?" with the line
///   that says they stay. "End session" fades in where it has been waiting, so nothing moves.
/// - "Keep going" is there from the first moment and goes back to the session. The session ends only on "End
///   session". Leaving the foreground goes back to the session too (`RunningSessionView`).
struct EndBreathView: View {
    let session: SessionRecord
    /// `.gentle` or `.steady`.
    let path: SessionEndPath
    /// The session screen's own second header line ("6 apps resting"), so the dial stays where it was.
    let subtitle: String?
    /// When the breath began, on trusted time.
    let startedAt: Date
    /// DEBUG still frames: the breath frozen with this many seconds left (0 is the second question).
    let frozenSecondsLeft: Double?
    /// "End session" was tapped: the store is ending the session.
    let isEnding: Bool
    let onKeepGoing: () -> Void
    let onEnd: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(FocusSessionStore.self) private var sessions
    @Environment(SessionNotesStore.self) private var notes

    /// The breath and the question's fade are over: the timeline stops.
    @State private var isSettled = false
    @State private var announcedQuestion = false

    private var settledAfter: TimeInterval { EndBreathModel.breathSeconds(for: path) + EndBreathModel.askFade }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isSettled || frozenSecondsLeft != nil)) { _ in
            let now = sessions.now
            screen(model(at: now), now: now)
        }
        .toolbarVisibility(.hidden, for: .tabBar)
        .task(id: startedAt) { await settle() }
    }

    private func screen(_ model: EndBreathModel, now: Date) -> some View {
        SessionScreen(title: title, subtitle: subtitle) { diameter in
            dial(model, now: now, diameter: diameter)
        } lines: {
            if dynamicTypeSize.isAccessibilitySize, let time = model.timeLine {
                // The dial's centre stops growing at xxLarge, so its minutes are repeated where they can grow (§5.17).
                Text(time)
                    .font(MapleFont.headline)
                    .foregroundStyle(theme.colors.textPrimary)
                    .accessibilityHidden(true)
                    .opacity(model.askOpacity)
            }
            if let line = model.line {
                Text(line)
                    .font(MapleFont.callout)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            if let question = model.title {
                Text(question)
                    .font(MapleFont.sectionTitle)
                    .foregroundStyle(theme.colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .opacity(model.askOpacity)
            }
            if let body = model.body {
                Text(body)
                    .font(MapleFont.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                    .opacity(model.askOpacity)
            }
        } controls: {
            Button(model.keepGoingTitle, action: onKeepGoing)
                .buttonStyle(.moonlight)
                .disabled(isEnding)
            // End session holds its place through the breath, so nothing moves when it fades in.
            Button(model.endTitle, action: onEnd)
                .buttonStyle(.glassCapsule)
                .opacity(model.askOpacity)
                .allowsHitTesting(model.isAsking)
                .accessibilityHidden(!model.isAsking)
                .disabled(isEnding)
        }
        .onChange(of: model.isAsking, initial: true) { _, asking in
            guard asking, !announcedQuestion else { return }
            announcedQuestion = true
            // The breath is over and a choice is waiting (§4.9).
            AccessibilityNotification.Announcement(FocusCopy.EndEarly.askAgain).post()
        }
    }

    /// The session's own marks, held dim through the breath, with the disc and the bloom breathing inside them; then
    /// the marks back at full strength around the minutes saved. VoiceOver reads it as one element.
    private func dial(_ model: EndBreathModel, now: Date, diameter: CGFloat) -> some View {
        let bloomSide = diameter * MinuteDialMetrics.bloomScale
        let discSide = diameter * 0.74
        return ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [theme.dial.restBloom, theme.dial.restBloom.opacity(0)], center: .center,
                    startRadius: 0, endRadius: bloomSide / 2
                ))
                .frame(width: bloomSide, height: bloomSide)
                .scaleEffect(model.bloomScale)
                .opacity(model.bloomOpacity)
                .allowsHitTesting(false)
            // The breath itself: it fills the dial on the way in and empties on the way out.
            ZStack {
                Circle().fill(RadialGradient(
                    colors: [theme.dial.rest.opacity(0.26), theme.dial.rest.opacity(0.10)], center: .center,
                    startRadius: 0, endRadius: discSide / 2
                ))
                Circle().strokeBorder(theme.dial.rest.opacity(0.55), lineWidth: 1.5)
            }
            .frame(width: discSide, height: discSide)
            .scaleEffect(model.discScale)
            .opacity(model.discOpacity)
            .allowsHitTesting(false)
            if model.askOpacity < 1 {
                MinuteDial(frame: marks(at: now).dimmed(true), diameter: diameter, theme: theme) {
                    breathWords(model, diameter: diameter)
                }
                .opacity(1 - model.askOpacity)
            }
            if case .asking(let numeral, let caption) = model.centre {
                MinuteDial(frame: marks(at: now), diameter: diameter, theme: theme) {
                    DialCentre(leaf: nil, numeral: DialCentre.numeralParts(numeral), caption: caption, diameter: diameter)
                }
                .opacity(model.askOpacity)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(model.spoken))
    }

    /// "Breathe in" cross-fading into "and out" by opacity alone (§4.6). While the question fades in over it, the
    /// breath's last words stay.
    private func breathWords(_ model: EndBreathModel, diameter: CGFloat) -> some View {
        let words: String = if case .breath(let words) = model.centre { words } else { FocusCopy.EndEarly.breatheOut }
        return FadingLine(words) { words in
            // Smaller than the dial's numeral, so the words sit inside the disc; like the numeral, they stop growing at
            // xxLarge (§5.17).
            Text(words)
                .font(MapleFont.screenTitle)
                .foregroundStyle(theme.colors.textPrimary)
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: diameter * 0.6)
        }
    }

    /// The running session's marks as they stand; the bloom is drawn here instead, so the breath can swell it.
    private func marks(at now: Date) -> DialFrame {
        let shown = FocusRoute.frameTime(session, now: now)
        var frame = DialFrame.running(
            layout: DialLayout(plannedMinutes: session.plan.plannedMinutes),
            elapsed: shown.timeIntervalSince(session.countdownStart), leafMinute: nil, fill: DialFill()
        )
        frame.bloom = .hidden
        return frame
    }

    /// "Study · Chemistry ch. 4", as the session's own header reads.
    private var title: String {
        FocusCopy.sessionTitle(presetName: session.plan.presetName, intention: notes.intention(for: session.id))
    }

    private func model(at now: Date) -> EndBreathModel {
        let total = EndBreathModel.breathSeconds(for: path)
        let seconds = frozenSecondsLeft.map { $0 <= 0 ? total + EndBreathModel.askFade : total - $0 }
            ?? now.timeIntervalSince(startedAt)
        return EndBreathModel(
            path: path, countedSeconds: sessions.countedSoFar(session.id),
            focusedSeconds: Int(max(0, now.timeIntervalSince(session.countdownStart))), canCount: session.plan.canCount,
            seconds: seconds, reduceMotion: reduceMotion, locale: locale
        )
    }

    /// Stops the timeline once the breath and the question's fade are over.
    private func settle() async {
        guard frozenSecondsLeft == nil else { return }
        isSettled = false
        let left = settledAfter - sessions.now.timeIntervalSince(startedAt)
        if left > 0 { try? await Task.sleep(for: .seconds(left)) }
        guard !Task.isCancelled else { return }
        isSettled = true
    }
}
