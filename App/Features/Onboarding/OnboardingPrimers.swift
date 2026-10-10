import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The Apple Health step, after "Save schedule" and before the sprout (spec §8.8, D9): the same calm primer every
/// "Turn on Apple Health" shows (`HealthPrimerView`), full screen under the progress hairline. "Continue" shows
/// Apple's Health sheet through `HealthPermission`; once it closes, Apple Health counts as connected. "Not now" is
/// fine: the sleep leaves wait with their "Needs Apple Health" states. Either answer moves on, and is saved, so a
/// relaunch never asks again. There is no back circle: the schedule is saved and is never asked for twice.
struct OnboardingHealthStep: View {
    /// The member answered (or Apple Health was already connected).
    var onDone: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.season) private var season
    @Environment(\.mapleClock) private var clock
    @Environment(HealthPermission.self) private var health
    @Environment(CollectionStore.self) private var collection
    @State private var answered = false

    var body: some View {
        let species = RewardCatalog.shared.rungs(in: .nightsTracked).first.flatMap { LeafCatalog.shared.species(id: $0.speciesID) }
        VStack(spacing: 0) {
            OnboardingTopBar(progress: OnboardingStep.health.progress ?? 1)
            HealthPrimerView(
                species: species, colourway: LeafColourway.pressed(in: season, evergreen: species?.evergreen ?? false),
                isAsking: health.isRequesting, page: theme.colors.background, onContinue: connect, onNotNow: finish
            )
        }
        .task {
            // Already connected (a reinstall Apple remembers, or a DEBUG demo): nothing to ask.
            if health.isConnected { finish() }
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "MapleDemoHealthContinue") {
                try? await Task.sleep(for: .seconds(1))
                connect()
            }
            #endif
        }
    }

    /// Apple's sheet over the primer; once the member closes it the sleep leaves follow and onboarding moves on.
    private func connect() {
        guard !health.isRequesting, !answered else { return }
        Task {
            await health.requestAccess(at: clock.now())
            health.apply(to: collection)
            finish()
        }
    }

    private func finish() {
        guard !answered else { return }
        answered = true
        onDone()
    }
}

/// The notifications step's place in the flow, between Apple Health and the sprout.
///
/// TODO(integrator): replace this with the notifications primer (the notifications engineer's view). It should call
/// `onDone` once the member has answered it, exactly as `OnboardingHealthStep` does; `OnboardingStore` then saves
/// the answer and the flow moves on to the sprout. Until then the step draws nothing and continues at once, so no
/// placeholder screen ever shows.
struct OnboardingNotificationsStep: View {
    var onDone: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        theme.colors.background
            .ignoresSafeArea()
            .accessibilityHidden(true)
            .task { onDone() }
    }
}
