import MapleCore
import MapleDesign
import MapleServices
import SwiftUI

/// The van's scene: home, with everything done from it (syrup van design §5). The picture's pot cooks a leaf, its
/// button opens the clock, and the round buttons open the study record and the machines.
struct VanSceneView: View {
    let now: Date
    let streak: Int
    /// The reveal or wind-down, when the tree home's one button would have offered it now (`NowState.Action.showsOnVan`).
    let prompt: VanHomeView.Prompt?
    /// Time saved today (`FocusStatus.savedTodaySeconds`), 0 when nothing counts.
    let savedTodaySeconds: Int
    let onProfile: () -> Void
    let onStreak: () -> Void
    /// Opens Saved today, from the line under the time.
    let onSavedToday: () -> Void

    @Environment(AppRouter.self) private var router
    @Environment(CollectionStore.self) private var collection
    @Environment(FocusSessionStore.self) private var sessions
    @Environment(WorkshopStore.self) private var workshop
    @State private var showsHistory = false
    @State private var showsMachines = false
    @State private var cooked = 0
    @State private var cheers = 0
    /// The last finished session whose walk back from the maple was shown (`FocusView`), and the last one Pip danced
    /// for here: when they differ, he has just come home.
    @AppStorage("van.walkedBack") private var walkedBack = ""
    @AppStorage("van.dancedFor") private var dancedFor = ""

    var body: some View {
        let running = sessions.running
        let minutesLeft = running.map { max(0, Int(($0.plannedEnd.timeIntervalSince(now) / 60).rounded(.up))) }
        let model = VanHomeModel(
            phase: collection.phase(at: now), hour: collection.context.calendar.component(.hour, from: now),
            leaves: workshop.leaves, syrupTenths: workshop.syrupTenths, isAvailable: workshop.isAvailable, minutesLeft: minutesLeft,
            savedTodaySeconds: savedTodaySeconds
        )
        VanHomeView(
            model: model, now: now, streak: streak, prompt: prompt, cooked: cooked, cheers: cheers, isSessionRunning: running != nil,
            onEnter: openTimer,
            onCook: { if workshop.cook() > 0 { cooked += 1 } },
            onMachines: { showsMachines = true }, onHistory: { showsHistory = true },
            onProfile: onProfile, onStreak: onStreak,
            onSavedToday: onSavedToday
        )
        .sheet(isPresented: $showsHistory) {
            NavigationStack { HistoryView() }
        }
        .sheet(isPresented: $showsMachines) {
            VanUpgradesView()
                .presentationDetents([.large])
        }
        .onAppear {
            if !walkedBack.isEmpty, walkedBack != dancedFor {
                dancedFor = walkedBack
                cheers += 1
            }
        }
        .task {
            // The van's leaves come from the whole ledger; a second look at the same ledger adds nothing.
            await sessions.loadHistory()
            workshop.collect(from: sessions.history)
        }
        .onChange(of: sessions.running?.id) { _, _ in
            Task {
                await sessions.loadHistory()
                workshop.collect(from: sessions.history)
            }
        }
    }

    /// The timer's button: the clock that sets the length, or the running session.
    private func openTimer() {
        if sessions.running != nil {
            router.showFocus(.returnToSession)
        } else if sessions.isLoaded, sessions.isLedgerReadable {
            router.selectedTab = .focus
        }
        // Until the sessions have been read there is no clock to show (`FocusRoute.settling`): the tap does nothing.
    }
}
