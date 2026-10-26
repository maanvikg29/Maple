import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The running session on the Herbarium (F1 design §5.10): "Study · 32m left", or "Break · back at 14:28", one tap
/// from the session's screen. Only the Herbarium has it, because Home already shows the session. Its time ticks
/// every second on the store's trusted time, so it agrees with the dial; with no session it draws nothing.
struct FocusMiniBar: View {
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.focusStores) private var focusStores
    @Environment(AppRouter.self) private var router
    @Environment(CollectionStore.self) private var collection
    /// The ticks run from here, so the schedule stays the same across redraws.
    @State private var ticksFrom = Date()

    var body: some View {
        if let sessions = focusStores?.sessions, let running = sessions.running {
            TimelineView(.periodic(from: ticksFrom, by: 1)) { _ in
                let bar = SessionMiniBar(session: running, now: sessions.now, calendar: collection.context.calendar, locale: locale)
                Button {
                    router.showFocus(.returnToSession)
                } label: {
                    HStack(spacing: theme.spacing.sm) {
                        Text(bar.title)
                            .monospacedDigit()
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.up")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.colors.textSecondary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.glassCapsule)
                .accessibilityLabel(bar.spoken)
            }
            .padding(.horizontal, theme.spacing.gridMargin)
            .padding(.bottom, theme.spacing.xs)
            .transition(.opacity)
        }
    }
}
