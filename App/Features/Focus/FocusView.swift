import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The Focus tab (F1 design §5): the one screen the session store's state calls for (`FocusRoute`). It is read
/// again whenever the store changes, and when a break or the session runs out with nothing else changing.
///
/// - Before the store's first replay, and in the moment between a session's planned end and the refresh that ends
///   it, nothing is drawn. So a session that ended while Maple was closed opens straight on its receipt.
/// - A running session shows its screen (its break while one runs), or the start screen's running state once
///   minimised.
/// - Otherwise an unseen receipt (`ReceiptPicker.pending`, P5) comes first, then Needs Screen Time while blocking
///   isn't available (until the member picks the plain timer), then the start screen.
///
/// Cross-tab requests arrive through `AppRouter.focusRequest` and are applied once. The tab's own choices live in
/// `FocusTabState`, which every Focus screen reads from the environment, and its one sheet is `FocusTabState.sheet`.
///
/// Until Tasks 9–15 build them, each destination and each sheet is a `FocusPlaceholder`.
struct FocusView: View {
    @Environment(\.theme) private var theme
    @Environment(FocusSessionStore.self) private var sessions
    @Environment(PresetStore.self) private var presets
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @State private var tab = FocusTabState()
    /// Bumped when the route can change with time alone (a break running out), so the route is read again.
    @State private var tick = 0

    var body: some View {
        @Bindable var tab = tab
        let now = sessions.now
        let pending = ReceiptPicker.pending(sessions.sessions, seen: settings.lastReceiptSeen, now: now)
        let route = FocusRoute.resolve(
            isLoaded: sessions.isLedgerReadable, running: sessions.running, receipt: tab.shownReceipt ?? pending?.id,
            isMinimised: tab.isMinimised, canBlock: canBlock, usesPlainTimer: tab.plainTimer != nil, now: now
        )
        // Read, so a tick reads the route again.
        let _ = tick
        destination(route, now: now)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.colors.background)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .sheet(item: $tab.sheet) { sheet in
                // Tasks 14 and 15 replace these with the sheets themselves.
                FocusPlaceholder(sheet.title)
                    .presentationDetents([.medium])
                    .presentationBackground(theme.colors.surface2)
            }
            .onChange(of: pending?.id, initial: true) { _, id in holdReceipt(id) }
            .onChange(of: sessions.running?.id) { old, new in sessionChanged(from: old, to: new) }
            .onChange(of: router.focusRequest, initial: true) { _, request in apply(request) }
            // Once Screen Time allows Maple, a plain timer chosen on Needs Screen Time gives way to blocking again.
            .onChange(of: canBlock) { _, allowed in
                if allowed, tab.plainTimer == .chosen { tab.plainTimer = nil }
            }
            .task(id: FocusRoute.nextChange(running: sessions.running, now: now)) { await waitForChange() }
            // §5.1, Locking: a soft haptic as the block is confirmed and the session's screen settles.
            .sensoryFeedback(.impact(flexibility: .soft), trigger: tab.lastStarted)
            #if DEBUG
            .task { FocusDemoPresenter.apply(to: tab, presets: presets) }
            #endif
            // Outermost, so the sheets see it too.
            .environment(tab)
    }

    /// Blocking is available: the build can block, and Screen Time allows Maple.
    private var canBlock: Bool {
        sessions.blocking.capability.canBlock && sessions.probe.isAllowed
    }

    @ViewBuilder
    private func destination(_ route: FocusRoute, now: Date) -> some View {
        switch route {
        case .settling:
            Color.clear
        case .start:
            FocusStartView()
        case .minimised(let id):
            FocusStartView(minimised: id)
        case .needsScreenTime:
            NeedsScreenTimeView()
        case .running(let id), .breakTime(let id):
            // One view for both, so the screen keeps its state as a break starts and runs out (§5.5).
            RunningSessionView(sessionID: id)
                .id(id)
        case .receipt(let id):
            ReceiptView(sessionID: id)
                .id(id)
        }
    }

    private func session(_ id: UUID) -> SessionRecord? {
        sessions.sessions.first { $0.id == id }
    }

    /// Keeps a receipt on screen once it shows, so marking it seen (Task 13) doesn't take it away mid-read.
    private func holdReceipt(_ id: UUID?) {
        guard let id, tab.shownReceipt == nil, sessions.running == nil else { return }
        tab.shownReceipt = id
    }

    /// A session starting clears the last receipt and the plain-timer choice; one ending or being replaced leaves
    /// nothing minimised. (At launch the first replay finds the running session: a minimised state set for a DEBUG
    /// launch survives that.)
    private func sessionChanged(from old: UUID?, to new: UUID?) {
        if old != nil {
            tab.isMinimised = false
            tab.releasesAll = false
        }
        if new != nil {
            tab.shownReceipt = nil
            tab.plainTimer = nil
        }
    }

    private func apply(_ request: FocusRequest?) {
        guard let request else { return }
        router.focusRequest = nil
        switch request {
        case .selectPreset(let id):
            tab.selectedPresetID = id
            tab.minutes = nil
        case .needsScreenTime:
            tab.plainTimer = nil
        case .receipt(let id):
            tab.shownReceipt = id
        case .returnToSession:
            tab.isMinimised = false
        case .releaseAll:
            if sessions.running != nil {
                tab.isMinimised = false
                tab.releasesAll = true
            } else {
                // The session ended on the way here: nothing to go through.
                Task { await sessions.releaseAll() }
            }
        }
    }

    /// Sleeps until the route's next change by time alone, then reads the route again.
    private func waitForChange() async {
        guard let next = FocusRoute.nextChange(running: sessions.running, now: sessions.now) else { return }
        try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSince(sessions.now))))
        guard !Task.isCancelled else { return }
        tick += 1
    }
}

/// What the Focus tab remembers between its screens for this launch. Nothing in it is saved.
@Observable
final class FocusTabState {
    /// The chip the member picked, or the one Home's Start asked for; nil uses the last-used preset (Quick for the
    /// first session, P4).
    var selectedPresetID: UUID?
    /// This session's length from turning the dial; nil uses the preset's.
    var minutes: Int?
    /// "What's this for?", saved with the session when it starts.
    var intention: String?
    /// The dial has been turned once this launch: its caption shows the preset name instead of the hint (§4.5).
    var hasTurnedDial = false
    /// ⌄ on the running session: the start screen shows the session's running state (§5.1).
    var isMinimised = false
    /// The member is starting a plain timer instead of a blocking session, and why; nil for a blocking session.
    var plainTimer: PlainTimerReason?
    /// The receipt on screen, kept until Done even once it is marked seen.
    var shownReceipt: UUID?
    /// The sheet over the tab.
    var sheet: FocusTabSheet?
    /// The last session this tab started, for the soft haptic as its block is confirmed (§5.1).
    var lastStarted: UUID?
    /// Settings' "Release all apps" arrived during a session: the session screen opens its way out and clears this.
    var releasesAll = false
}

/// Why the start screen starts a plain timer (§5.1, §5.3).
enum PlainTimerReason: Hashable {
    /// "Use a plain timer · it won't count" on Needs Screen Time.
    case chosen
    /// The block couldn't be applied: "Couldn't lock your apps · Start as a plain timer?"
    case lockFailed
}

/// The sheets the Focus tab presents. A screen asks for one by setting `FocusTabState.sheet`.
enum FocusTabSheet: Identifiable, Hashable {
    /// "Blocking 6 apps ›" (§5.14).
    case blocking
    /// Holding a chip edits its preset; "+" (nil) makes a new one (§5.13).
    case preset(UUID?)
    /// "What's this for?" (§5.16).
    case intention
    /// Tapping the receipt's numeral (§5.9).
    case saved
    /// The streak sheet (§5.15).
    case streak

    var id: String {
        switch self {
        case .blocking: "blocking"
        case .preset(let id): "preset.\(id?.uuidString ?? "new")"
        case .intention: "intention"
        case .saved: "saved"
        case .streak: "streak"
        }
    }

    /// The sheet's name, for its placeholder until Tasks 14 and 15 build it.
    var title: String {
        switch self {
        case .blocking: "Blocking"
        case .preset: "Preset"
        case .intention: "What's this for?"
        case .saved: "Saved today"
        case .streak: "Focus streak"
        }
    }
}

/// A Focus screen still to be built: its name and one line of what the store says. Tasks 9–15 replace every use.
struct FocusPlaceholder: View {
    @Environment(\.theme) private var theme
    private let name: String
    private let detail: String?

    init(_ name: String, detail: String? = nil) {
        self.name = name
        self.detail = detail
    }

    var body: some View {
        VStack(spacing: theme.spacing.xs) {
            Text(name)
                .font(MapleFont.sectionTitle)
                .foregroundStyle(theme.colors.textPrimary)
            if let detail {
                Text(detail)
                    .font(MapleFont.callout)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(theme.spacing.homeMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

extension EnvironmentValues {
    /// This launch's Focus stores, for the commands that span them (`FocusStores.start(_:intention:settings:)`).
    /// Set at the root (`MapleApp`); nil only in a view built outside it.
    @Entry var focusStores: FocusStores? = nil
}
