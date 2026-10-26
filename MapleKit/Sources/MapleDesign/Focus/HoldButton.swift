import MapleCore
import SwiftUI

/// A press-and-hold button (F1 design §4.7, §5.2, §5.6, §5.7; F1-22): Locked's "Hold to start · 50m", Steady's
/// "Hold to end" and the emergency release's "Hold to release". The moonlight fill rises from the leading edge
/// over the dark glass while it is held, and drains back at the same rate if it is let go early. `onComplete` runs
/// once, when it fills.
///
/// - **Interruptions cancel and drain, and never complete:** the app leaving the foreground (a call, the Lock
///   Screen), a second finger, a touch the system takes (a scroll, a sheet), or VoiceOver focus moving away from a
///   running countdown. After a scene change or a second finger, touches are ignored until every finger lifts. The
///   button leaving the screen (a tab switch, a cover) resets an unfinished hold to empty.
/// - **Accessibility (F1-22):** it reads as one button with `accessibilityName`. Its named action "Start countdown",
///   and VoiceOver's double-tap, fill it as a visible countdown of the same length ("Cancel · 8s", "8 seconds left").
///   The same action, a double-tap or a touch cancels it.
/// - `progress` mirrors the fill, so the screen can show it on the dial's marks (`DialFrame.hold(progress:base:)`).
///   Set it back to 0 to use a completed button again.
///
/// ```swift
/// #if DEBUG
/// let frozen = DemoLaunchOptions.current.holdAt   // -MapleDemoHoldAt
/// #else
/// let frozen: Double? = nil
/// #endif
/// HoldButton(title: model.capsuleTitle, duration: FocusCopy.holdToStartSeconds,
///            accessibilityName: FocusCopy.holdToStartName(minutes: 50, locale: locale),
///            progress: $holdProgress, frozenProgress: frozen, onTap: { showsHoldHint = true }) {
///     start()
/// }
/// ```
public struct HoldButton: View {
    /// A press released sooner than this is a plain tap (`onTap`).
    public static let tapLimit: TimeInterval = 0.3

    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @AccessibilityFocusState private var isFocused: Bool

    @Binding private var progress: Double
    @State private var hold: HoldProgress
    @State private var now = Date()
    @State private var touches: Set<SpatialEventCollection.Event.ID> = []
    /// The touches a gesture still held when its state reset, until a later main-actor turn shows whether its
    /// `onEnded` came (a lift) or never will (the system cancelled it). The hold can't complete meanwhile.
    @State private var endingTouches: Set<SpatialEventCollection.Event.ID>?
    @State private var ignoresTouches = false
    @State private var pressedAt: Date?
    @State private var ticker: Task<Void, Never>?
    @GestureState private var isTouching = false

    private let title: String
    private let duration: TimeInterval
    private let accessibilityName: String
    private let frozenProgress: Double?
    private let onTap: (() -> Void)?
    private let onComplete: () -> Void

    /// - Parameters:
    ///   - title: The label ("Hold to start · 50m").
    ///   - duration: Seconds to hold: 1.5, 3 or 10.
    ///   - accessibilityName: What VoiceOver reads (§4.9: "Hold to start, Locked 50 minutes").
    ///   - progress: The fill, 0…1, written as it changes.
    ///   - frozenProgress: A fixed fill that ignores touches: DEBUG still frames (`-MapleDemoHoldAt`), passed by the app.
    ///   - onTap: A press let go within `tapLimit` (Locked's hint, §5.2).
    ///   - onComplete: The hold filled.
    public init(
        title: String, duration: TimeInterval, accessibilityName: String, progress: Binding<Double>,
        frozenProgress: Double? = nil, onTap: (() -> Void)? = nil, onComplete: @escaping () -> Void
    ) {
        self.title = title
        self.duration = duration
        self.accessibilityName = accessibilityName
        self._progress = progress
        self.frozenProgress = frozenProgress
        self.onTap = onTap
        self.onComplete = onComplete
        self._hold = State(initialValue: HoldProgress(duration: duration))
    }

    public var body: some View {
        let shown = frozenProgress.map { min(1, max(0, $0)) } ?? hold.value(at: now)
        let counting = hold.isCountdown && hold.isFilling
        let label = counting ? FocusCopy.holdCountdownTitle(secondsLeft: hold.secondsLeft(at: now)) : title
        ZStack {
            Capsule(style: .continuous)
                .fill(theme.colors.surface2.opacity(0.72))
            labelText(label, colour: theme.colors.textPrimary)
            ZStack {
                Capsule(style: .continuous)
                    .fill(LinearGradient(
                        colors: [theme.colors.primaryFillTop, theme.colors.primaryFillBottom],
                        startPoint: .top, endPoint: .bottom
                    ))
                labelText(label, colour: theme.colors.primaryLabel)
            }
            .mask {
                Rectangle()
                    .scaleEffect(x: max(shown, 0.001), y: 1, anchor: .leading)
                    .opacity(shown > 0 ? 1 : 0)
            }
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(theme.colors.primaryBorderBottom, lineWidth: theme.elevation.hairlineWidth)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Capsule(style: .continuous))
        .gesture(touchGesture, including: frozenProgress == nil ? .all : .subviews)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { interrupt() }
        }
        .onChange(of: isTouching) { _, touching in
            // `isTouching` resets as the gesture ends, and SwiftUI can run this before the gesture's own `onEnded`,
            // which still has to see the lift (and a plain tap). So the touches still recorded are looked at again a
            // main-actor turn later, once the update that ended the gesture has run its actions: a lift's `onEnded`
            // has removed them by then. A gesture the system cancels (a scroll view or a sheet taking the touch)
            // never calls `onEnded`, so they are still there: that is an interruption, and the hold drains and never
            // completes.
            guard !touching, !touches.isEmpty else { return }
            let held = touches
            endingTouches = held
            Task {
                // One more turn, in case the gesture's actions were themselves queued behind this task.
                await Task.yield()
                endingTouches = nil
                guard !touches.isDisjoint(with: held) else { return }
                touches.subtract(held)
                interrupt()
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused, hold.isCountdown { interrupt() }
        }
        .onChange(of: progress) { _, value in
            if value == 0, hold.isComplete { hold.reset() }
        }
        .onChange(of: duration) { _, value in
            hold = HoldProgress(duration: value)
        }
        .onAppear {
            if let frozenProgress { progress = frozenProgress }
        }
        .onChange(of: frozenProgress) { _, value in
            if let value { progress = value }
        }
        .onDisappear {
            // Leaving the screen (a tab switch, a cover) ends the hold: nothing carries over, so the first tap back
            // can't lift a press that began before and complete it.
            touches.removeAll()
            endingTouches = nil
            ignoresTouches = false
            pressedAt = nil
            if !hold.isComplete {
                hold.reset()
                progress = 0
            }
            ticker?.cancel()
            ticker = nil
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityName))
        .accessibilityValue(Text(counting ? FocusTimeText.spokenRemaining(Double(hold.secondsLeft(at: now)), locale: locale) : ""))
        .accessibilityAddTraits(.isButton)
        .trackingAccessibilityFocus($isFocused, when: frozenProgress == nil)
        .accessibilityAction { toggleCountdown() }
        .accessibilityAction(named: Text(counting ? FocusCopy.holdCancelAction : FocusCopy.holdCountdownAction)) {
            toggleCountdown()
        }
    }

    /// One line, and as many as the words need at accessibility sizes, where "Hold to start as a plain timer" takes
    /// three (§5.17: no word is cut). The capsule grows to fit (`fixedSize`).
    private func labelText(_ text: String, colour: Color) -> some View {
        Text(text)
            .font(MapleFont.buttonLabel)
            .foregroundStyle(colour)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .multilineTextAlignment(.center)
            .padding(.horizontal, theme.spacing.lg)
            .padding(.vertical, theme.spacing.sm)
    }

    // MARK: Touches

    /// Every finger on the button, so a second one is noticed.
    private var touchGesture: some Gesture {
        SpatialEventGesture()
            .updating($isTouching) { _, touching, _ in touching = true }
            .onChanged { events in track(events) }
            .onEnded { events in
                track(events)
                touchesEnded()
            }
    }

    private func track(_ events: SpatialEventCollection) {
        var cancelled = false
        for event in events {
            if event.phase == .active {
                touches.insert(event.id)
            } else {
                touches.remove(event.id)
                if event.phase == .cancelled { cancelled = true }
            }
        }
        if cancelled {
            // A touch the system took (a scroll starting on the button, a sheet) is an interruption, not a lift: the
            // hold drains, never completes, and it is never a tap.
            interrupt()
        } else if touches.count > 1 {
            // A second finger lets go of the hold.
            interrupt()
        } else if touches.isEmpty {
            touchesEnded()
        } else if !ignoresTouches, hold.isCountdown, hold.isFilling {
            // A touch while the countdown runs cancels it.
            interrupt()
        } else if !ignoresTouches, !hold.isFilling {
            press()
        }
    }

    private func touchesEnded() {
        touches.removeAll()
        if ignoresTouches {
            ignoresTouches = false
            return
        }
        guard hold.isFilling, !hold.isCountdown else { return }
        let date = Date()
        if completeIfFilled(at: date) { return }
        let tapped = pressedAt.map { date.timeIntervalSince($0) < Self.tapLimit } ?? false
        hold.release(at: date)
        pressedAt = nil
        run()
        if tapped { onTap?() }
    }

    private func press() {
        guard frozenProgress == nil, !hold.isComplete else { return }
        let date = Date()
        hold.press(at: date)
        pressedAt = date
        run()
    }

    /// The hold or countdown is cut short: it drains and never completes, and touches still down are ignored until
    /// every finger lifts.
    private func interrupt() {
        ignoresTouches = !touches.isEmpty
        guard hold.isFilling else { return }
        hold.release(at: Date())
        pressedAt = nil
        run()
    }

    // MARK: Accessibility

    /// The named action and VoiceOver's double-tap: start the countdown, or cancel the one that is running.
    private func toggleCountdown() {
        guard frozenProgress == nil, !hold.isComplete else { return }
        if hold.isCountdown, hold.isFilling {
            interrupt()
        } else {
            hold.startCountdown(at: Date())
            pressedAt = nil
            run()
        }
    }

    // MARK: Time

    /// Completes the hold once, if it has filled by `date`.
    private func completeIfFilled(at date: Date) -> Bool {
        guard hold.isFilled(at: date) else { return false }
        hold.finish()
        now = date
        progress = 1
        ticker?.cancel()
        ticker = nil
        onComplete()
        return true
    }

    /// Samples the hold 30 times a second while it fills or drains, and stops once it is still.
    private func run() {
        now = Date()
        progress = hold.value(at: now)
        guard ticker == nil else { return }
        ticker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.0 / 30))
                let date = Date()
                // While a gesture's end is unresolved, only its lift (`touchesEnded`) may complete the hold: a
                // gesture the system cancelled must never complete.
                if endingTouches == nil, completeIfFilled(at: date) { return }
                now = date
                progress = hold.value(at: date)
                if hold.phase(at: date) == .idle {
                    ticker = nil
                    return
                }
            }
        }
    }
}

extension View {
    /// VoiceOver focus tracking for a live hold only. `ImageRenderer` draws nothing under `accessibilityFocused`, and a
    /// frozen still frame (`frozenProgress`) ignores touches and actions, so it has no countdown for focus to cancel.
    @ViewBuilder
    fileprivate func trackingAccessibilityFocus(_ focus: AccessibilityFocusState<Bool>.Binding, when tracks: Bool) -> some View {
        if tracks {
            accessibilityFocused(focus)
        } else {
            self
        }
    }
}
