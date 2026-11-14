import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// End early, for Gentle and Steady (F1 design §5.6), and for every plain timer, which is Gentle whatever its preset: a
/// small sheet over the running session, no taller than what it says.
///
/// - "End this session?", the minutes saved so far (counted seconds, with this session's provisional time), and the
///   primary "Keep going", which cancels, as swiping the sheet away does.
/// - Gentle: "End session". Steady: "Hold to end" for 3 seconds, and "Take a 5-minute break instead" while the preset's
///   break is unused and apps are locked; it is cut short at the planned end.
/// - Leaving the foreground cancels the hold (`HoldButton`).
///
/// The sheet only asks. Its way out calls `onContinue`, and the session screen then shows the breath and the second
/// question once the sheet has gone (`EndBreathView`, F1-32): nothing here ends the session.
struct EndEarlySheet: View {
    let session: SessionRecord
    /// `.gentle` or `.steady`.
    let path: SessionEndPath
    let onKeepGoing: () -> Void
    let onBreakInstead: () -> Void
    let onContinue: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(FocusSessionStore.self) private var sessions

    @State private var holdProgress = 0.0
    /// The content's own height: the sheet is exactly that tall.
    @State private var contentHeight: CGFloat = 260

    init(
        session: SessionRecord, path: SessionEndPath, onKeepGoing: @escaping () -> Void,
        onBreakInstead: @escaping () -> Void, onContinue: @escaping () -> Void
    ) {
        self.session = session
        self.path = path
        self.onKeepGoing = onKeepGoing
        self.onBreakInstead = onBreakInstead
        self.onContinue = onContinue
    }

    var body: some View {
        // Once a minute, so the minutes saved keep up while the sheet is open.
        TimelineView(.everyMinute) { _ in
            content(model(at: sessions.now))
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(contentHeight)])
        .presentationDragIndicator(.visible)
        // The session screen's own dark, a little see-through, so the sheet belongs to the screen under it.
        .presentationBackground {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                theme.colors.background.opacity(0.78)
            }
        }
    }

    private func content(_ model: EndEarlyModel) -> some View {
        ScrollView {
            VStack(spacing: theme.spacing.sm) {
                Text(model.title)
                    .font(MapleFont.sectionTitle)
                    .foregroundStyle(theme.colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(model.body)
                    .font(MapleFont.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: theme.spacing.sm) {
                    Button(model.keepGoingTitle, action: onKeepGoing)
                        .buttonStyle(.moonlight)
                    if let hold = model.holdTitle {
                        HoldButton(
                            title: hold, duration: FocusCopy.EndEarly.holdSeconds, accessibilityName: hold,
                            progress: $holdProgress, frozenProgress: frozenHold, onComplete: onContinue
                        )
                    }
                    if let end = model.endTitle {
                        Button(end, action: onContinue)
                            .buttonStyle(.glassCapsule)
                    }
                    if let instead = model.breakInsteadTitle {
                        TextLink(instead, chevron: false, action: onBreakInstead)
                    }
                }
                .padding(.top, theme.spacing.sm)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, theme.spacing.homeMargin)
            .padding(.top, theme.spacing.xl)
            .padding(.bottom, theme.spacing.xs)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                contentHeight = height
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func model(at now: Date) -> EndEarlyModel {
        // The running screen's own rule: no break for a plain timer or a lost block.
        EndEarlyModel(
            path: path, countedSeconds: sessions.countedSoFar(session.id),
            breakAvailable: RunningSessionModel.breakAvailable(session, at: now)
        )
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
