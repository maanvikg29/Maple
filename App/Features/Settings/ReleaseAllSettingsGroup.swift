import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// Settings › "Release all apps" (F1 design §5.12), for an app that stays locked by mistake. It asks first ("Release
/// all apps? Every app Maple is resting opens again now.").
/// - With no session running, every store is cleared at once (on F1 builds, the preview stores), and the row says so.
/// - During a session it goes through that strictness level's own end path on the Focus tab, so in Locked it is the
///   emergency release (`FocusReleaseRouter`, Task 12). Home closes the Profile sheet when the request arrives.
///
/// `SettingsView` shows it once Focus ships, in a build that can block.
struct ReleaseAllSettingsGroup: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppRouter.self) private var router
    @Environment(FocusSessionStore.self) private var sessions
    @State private var asks = false
    @State private var isReleasing = false
    /// Every app was released from here, so the row's line says so.
    @State private var released = false

    var body: some View {
        ProfileListGroup {
            Button {
                asks = true
            } label: {
                row
            }
            .buttonStyle(.profileRow)
            .disabled(isReleasing)
            // No destructive role: nothing is lost, and the words stay calm.
            .confirmationDialog(FocusCopy.ReleaseAll.question, isPresented: $asks, titleVisibility: .visible) {
                Button(FocusCopy.ReleaseAll.title) { release() }
                Button(FocusCopy.ReleaseAll.cancel, role: .cancel) {}
            } message: {
                Text(FocusCopy.ReleaseAll.body)
            }
        }
        // Groups sit 32pt apart, as the reminders do.
        .padding(.top, theme.spacing.xs)
        #if DEBUG
        .task {
            // `-MapleDemoSettingsOpen releaseAll` (SettingsDemo): the confirmation, once the page has settled.
            guard SettingsDemo.opening == .releaseAll else { return }
            try? await Task.sleep(for: .seconds(1))
            asks = true
        }
        #endif
    }

    /// The title, with what it is for (or that every app is open again) under it.
    private var row: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(FocusCopy.ReleaseAll.title)
                .font(MapleFont.body)
                .foregroundStyle(theme.colors.textPrimary)
            // Both lines hold their place, so the row keeps its height and the swap is a cross-fade (§4.6: nothing
            // animates layout).
            ZStack(alignment: .topLeading) {
                line(FocusSettingsCopy.releaseAllDetail, shows: !released)
                line(FocusSettingsCopy.releaseAllDone, shows: released)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.spacing.listMargin)
        .padding(.vertical, theme.spacing.md)
        .frame(minHeight: theme.spacing.row)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func line(_ text: String, shows: Bool) -> some View {
        Text(text)
            .font(MapleFont.footnote)
            .foregroundStyle(theme.colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(shows ? 1 : 0)
            .accessibilityHidden(!shows)
    }

    private func release() {
        guard !isReleasing else { return }
        isReleasing = true
        Task {
            let releasedNow = await FocusReleaseRouter(router: router).releaseAll(from: sessions)
            isReleasing = false
            // False: a session was running, and the Focus tab took over with its own way out.
            guard releasedNow else { return }
            withAnimation(reduceMotion ? nil : theme.motion.gentle) { released = true }
            AccessibilityNotification.Announcement(FocusSettingsCopy.releaseAllDone).post()
        }
    }
}
