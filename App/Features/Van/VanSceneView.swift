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
    let onProfile: () -> Void
    let onTree: () -> Void
    let onStreak: () -> Void

    @Environment(AppRouter.self) private var router
    @Environment(CollectionStore.self) private var collection
    @Environment(FocusSessionStore.self) private var sessions
    @Environment(WorkshopStore.self) private var workshop
    @State private var showsHistory = false
    @State private var showsMachines = false
    @State private var cooked = 0

    var body: some View {
        let running = sessions.running
        let minutesLeft = running.map { max(0, Int(($0.plannedEnd.timeIntervalSince(now) / 60).rounded(.up))) }
        let model = VanHomeModel(
            phase: collection.phase(at: now), hour: collection.context.calendar.component(.hour, from: now),
            leaves: workshop.leaves, syrupTenths: workshop.syrupTenths, isAvailable: workshop.isAvailable, minutesLeft: minutesLeft
        )
        VanHomeView(
            model: model, now: now, streak: streak, prompt: prompt, cooked: cooked,
            onEnter: openTimer,
            onCook: { if workshop.cook() > 0 { cooked += 1 } },
            onMachines: { showsMachines = true }, onHistory: { showsHistory = true },
            onHerbarium: { router.showHerbarium() }, onProfile: onProfile, onTree: onTree, onStreak: onStreak
        )
        .sheet(isPresented: $showsHistory) {
            NavigationStack { HistoryView() }
        }
        .sheet(isPresented: $showsMachines) {
            VanUpgradesView()
                .presentationDetents([.large])
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
