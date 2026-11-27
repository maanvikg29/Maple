import MapleCore
import MapleDesign
import MapleServices
import SwiftUI

/// The van's scene: home outside, the workshop inside, and the entrance between them (syrup van design §5).
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
    @Environment(PresetStore.self) private var presets
    @Environment(WorkshopStore.self) private var workshop
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("van.lastFullEntrance") private var lastFullEntrance = 0.0
    /// The length last set on the clock, which the gauge shows (`ClockTimerView` writes it).
    @AppStorage("van.minutes") private var savedMinutes = 0
    @State private var isInside = VanSceneView.startsInside
    @State private var pushIn = 0.0

    var body: some View {
        let running = sessions.running
        let minutesLeft = running.map { max(0, Int(($0.plannedEnd.timeIntervalSince(now) / 60).rounded(.up))) }
        let model = VanHomeModel(
            phase: collection.phase(at: now), hour: collection.context.calendar.component(.hour, from: now),
            leaves: workshop.leaves, syrupTenths: workshop.syrupTenths, isAvailable: workshop.isAvailable, minutesLeft: minutesLeft
        )
        let preset = presets.presets.first { $0.id == presets.lastUsedID } ?? presets.presets.first
        let length = VanTimer.length(saved: savedMinutes, preset: preset?.minutes)
        ZStack {
            if isInside {
                VanWorkshopView(
                    model: model,
                    gaugeText: minutesLeft.map { FocusTimeText.length(minutes: $0) } ?? VanHomeModel.gaugeText(minutes: length),
                    onGauge: openTimer, onBack: { move(inside: false) }
                )
                .transition(.opacity)
            } else {
                VanHomeView(
                    model: model, now: now, streak: streak, prompt: prompt,
                    onEnter: { running == nil ? move(inside: true) : openTimer() },
                    onHerbarium: { router.showHerbarium() }, onProfile: onProfile, onTree: onTree, onStreak: onStreak
                )
                // The camera pushes in toward the van before the cut.
                // Toward the open side of the van, where the picture has it.
                .scaleEffect(1 + pushIn * 0.9, anchor: UnitPoint(x: 0.47, y: 0.36))
                .transition(.opacity)
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

    /// The gauge: the clock that sets the length, or the running session.
    private func openTimer() {
        if sessions.running != nil {
            router.showFocus(.returnToSession)
        } else if sessions.isLoaded, sessions.isLedgerReadable {
            router.selectedTab = .focus
        }
        // Until the sessions have been read there is no clock to show (`FocusRoute.settling`): the tap does nothing.
    }

    private func move(inside: Bool) {
        guard inside else {
            withAnimation(.easeInOut(duration: VanEntrance.short.seconds)) { isInside = false }
            return
        }
        let lastFull = lastFullEntrance > 0 ? Date(timeIntervalSince1970: lastFullEntrance) : nil
        let style = VanEntrance.style(lastFull: lastFull, now: now, calendar: .current, reduceMotion: reduceMotion)
        if style == .full { lastFullEntrance = now.timeIntervalSince1970 }
        guard style != .crossFade else {
            withAnimation(.easeInOut(duration: style.seconds)) { isInside = true }
            return
        }
        withAnimation(.easeIn(duration: style.seconds * 0.6)) { pushIn = 1 }
        Task {
            try? await Task.sleep(for: .seconds(style.seconds * 0.55))
            withAnimation(.easeOut(duration: style.seconds * 0.45)) { isInside = true }
            try? await Task.sleep(for: .seconds(style.seconds * 0.45))
            pushIn = 0
        }
    }

    /// DEBUG: `-MapleDemoPresent van:workshop` opens inside the van.
    private static var startsInside: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "MapleDemoPresent") == "van:workshop"
        #else
        false
        #endif
    }
}
