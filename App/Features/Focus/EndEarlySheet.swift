import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// End early, for Gentle and Steady (F1 design §5.6): a sheet over the running session.
///
/// - "End this session?", the minutes saved so far (counted seconds, with this session's provisional time), and the
///   primary "Keep going", which cancels at every stage, as swiping the sheet away does.
/// - Steady: "Hold to end" for 3 seconds, then a quiet 15-second countdown, "Ending in 15s". "Take a 5-minute break
///   instead" is offered while the preset's break is unused and apps are locked; it is cut short at the planned end.
/// - Gentle: "End session" starts a 5-second breathing ring (a transform and an opacity only).
/// - Leaving the foreground cancels the hold (`HoldButton`) and the countdown alike.
///
/// The sheet only decides. `onEnd` runs when the countdown reaches zero; the session screen ends the session once
/// the sheet has gone, so the receipt never appears under a sheet.
struct EndEarlySheet: View {
    let session: SessionRecord
    /// `.gentle` or `.steady`.
    let path: SessionEndPath
    let onKeepGoing: () -> Void
    let onBreakInstead: () -> Void
    let onEnd: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(FocusSessionStore.self) private var sessions

    /// When the countdown ends, on the store's trusted time; nil while asking.
    @State private var endsAt: Date?
    @State private var holdProgress = 0.0

    init(
        session: SessionRecord, path: SessionEndPath, onKeepGoing: @escaping () -> Void,
        onBreakInstead: @escaping () -> Void, onEnd: @escaping () -> Void
    ) {
        self.session = session
        self.path = path
        self.onKeepGoing = onKeepGoing
        self.onBreakInstead = onBreakInstead
        self.onEnd = onEnd
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: path == .gentle ? 1.0 / 30 : 0.25, paused: endsAt == nil)) { _ in
            let now = sessions.now
            content(model(at: now), ring: ring(at: now))
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.colors.surface2)
        .onChange(of: scenePhase) { _, phase in
            // Holds and countdowns cancel when Maple leaves the foreground (§5.7).
            if phase != .active { cancelCountdown() }
        }
        .task(id: endsAt) {
            guard let endsAt, frozenCountdown == nil else { return }
            try? await Task.sleep(for: .seconds(max(0, endsAt.timeIntervalSince(sessions.now))))
            guard !Task.isCancelled, self.endsAt == endsAt else { return }
            onEnd()
        }
    }

    private func content(_ model: EndEarlyModel, ring: Double?) -> some View {
        ScrollView {
            VStack(spacing: theme.spacing.md) {
                // The question cross-fades into the countdown once (§4.6); the countdown's seconds then change at once,
                // so the title stays quiet.
                FadingLine(model.title, key: model.stage == .asking) { title in
                    Text(title)
                        .font(MapleFont.sectionTitle)
                        .foregroundStyle(theme.colors.textPrimary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(model.spokenTitle))
                .accessibilityAddTraits(.isHeader)
                Text(model.body)
                    .font(MapleFont.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                VStack(spacing: theme.spacing.sm) {
                    Button(model.keepGoingTitle, action: keepGoing)
                        .buttonStyle(.moonlight)
                    if let hold = model.holdTitle {
                        HoldButton(
                            title: hold, duration: FocusCopy.EndEarly.holdSeconds, accessibilityName: hold,
                            progress: $holdProgress, frozenProgress: frozenHold, onComplete: startCountdown
                        )
                    }
                    if let end = model.endTitle {
                        Button(end, action: startCountdown)
                            .buttonStyle(.glassCapsule)
                    }
                    if let ring {
                        // In End session's place, under "Keep going": the button that cancels never moves during the
                        // 5 seconds, and the sheet only grows below it.
                        breathingRing(ring)
                    }
                    if let instead = model.breakInsteadTitle {
                        TextLink(instead, chevron: false, action: onBreakInstead)
                    }
                }
                .padding(.top, theme.spacing.xs)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, theme.spacing.homeMargin)
            .padding(.top, theme.spacing.xl)
            .padding(.bottom, theme.spacing.md)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// Gentle's ring: one slow swell over its 5 seconds.
    private func breathingRing(_ progress: Double) -> some View {
        Circle()
            .stroke(theme.dial.rest, lineWidth: 2)
            .frame(width: 88, height: 88)
            .scaleEffect(EndEarlyModel.ringScale(progress: progress, reduceMotion: reduceMotion))
            .opacity(0.55 + 0.45 * sin(.pi * min(1, max(0, progress))))
            .padding(theme.spacing.xs)
            .accessibilityHidden(true)
    }

    // MARK: State

    private func model(at now: Date) -> EndEarlyModel {
        let stage: EndEarlyModel.Stage
        if let frozen = frozenCountdown {
            stage = .ending(secondsLeft: frozen)
        } else if let endsAt {
            stage = .ending(secondsLeft: EndEarlyModel.secondsLeft(until: endsAt, now: now))
        } else {
            stage = .asking
        }
        // The running screen's own rule: no break for a plain timer or a lost block.
        let breakAvailable = RunningSessionModel.breakAvailable(session, at: now)
        return EndEarlyModel(path: path, countedSeconds: sessions.countedSoFar(session.id), breakAvailable: breakAvailable,
                             stage: stage)
    }

    /// Gentle's ring, 0…1 through its 5 seconds, smoothly; nil for Steady and while asking.
    private func ring(at now: Date) -> Double? {
        guard path == .gentle else { return nil }
        if let frozen = frozenCountdown {
            return EndEarlyModel(path: .gentle, countedSeconds: 0, breakAvailable: false, stage: .ending(secondsLeft: frozen))
                .ringProgress
        }
        guard let endsAt else { return nil }
        let length = Double(EndEarlyModel.countdown(for: .gentle))
        return 1 - min(1, max(0, endsAt.timeIntervalSince(now) / length))
    }

    // MARK: Actions

    private func startCountdown() {
        guard endsAt == nil else { return }
        let seconds = EndEarlyModel.countdown(for: path)
        endsAt = sessions.now.addingTimeInterval(TimeInterval(seconds))
    }

    private func cancelCountdown() {
        endsAt = nil
        holdProgress = 0
    }

    private func keepGoing() {
        cancelCountdown()
        onKeepGoing()
    }

    // MARK: DEBUG still frames

    /// `-MapleDemoEndCountdown <s>`: the countdown frozen at that many seconds; it never ends the session.
    private var frozenCountdown: Int? {
        #if DEBUG
        return DemoLaunchOptions.current.endCountdown
        #else
        return nil
        #endif
    }

    /// `-MapleDemoHoldAt 0…1`: "Hold to end" frozen at that fill.
    private var frozenHold: Double? {
        #if DEBUG
        return DemoLaunchOptions.current.holdAt
        #else
        return nil
        #endif
    }
}
