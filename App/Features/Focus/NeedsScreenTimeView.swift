import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// Needs Screen Time (F1 design §5.3, F1-17): the Focus tab whenever blocking isn't available, with the plain timer
/// offered instead.
///
/// - The dial with its marks off, with the selected preset's length and name in its centre, and the next leaf unless
///   this build can't block.
/// - A card with the state's title and line (`FocusCopy.card`), and "Turn on Screen Time" where Maple can ask. Under
///   them, "Use a plain timer · it won't count" opens the start screen as a plain timer (`PlainTimerReason.chosen`).
///   A build that can never block remembers that choice (`AppSettings.choosePlainTimer(capability:)`), so after the
///   first time its Focus tab goes straight to the plain timer's start screen; a build that can block asks again
///   after each start.
///
/// "Turn on Screen Time" asks once (`FocusSessionStore.requestAuthorization()`). When Screen Time allows Maple, the
/// store's probe changes and `FocusView` shows the start screen. Every "Turn on Screen Time" elsewhere in the app
/// (Home's needs-permission row, the Herbarium, leaf detail) comes here through `router.showFocus(.needsScreenTime)`.
/// A session that loses its block mid-session never comes here: it carries on as a plain timer on its own screen.
struct NeedsScreenTimeView: View {
    @Environment(\.theme) private var theme
    @Environment(\.focusStores) private var focusStores
    @Environment(FocusTabState.self) private var tab
    @Environment(FocusSessionStore.self) private var sessions
    @Environment(PresetStore.self) private var presets
    @Environment(CollectionStore.self) private var collection
    @Environment(AppSettings.self) private var settings

    /// "Turn on Screen Time" is waiting for iOS's answer.
    @State private var isAsking = false

    var body: some View {
        if let preset, let model = NeedsScreenTimeModel(probe: sessions.probe, capability: sessions.blocking.capability, preset: preset) {
            FocusHeroPage(hasPrimary: false) { diameter in
                dial(model, preset: preset, diameter: diameter)
            } below: {
                card(model)
                    .padding(.top, theme.spacing.md)
            } primary: {
                EmptyView()
            }
        }
    }

    /// The preset the start screen would show.
    private var preset: FocusPreset? {
        FocusStartLines.preset(selected: tab.selectedPresetID, presets: presets.presets, lastUsedID: presets.lastUsedID,
                               isFirstSession: !settings.hasStartedFocus)
    }

    /// The dial with its marks off (§4.2 `off`): no dot and no bloom. The card says everything, so VoiceOver skips it.
    private func dial(_ model: NeedsScreenTimeModel, preset: FocusPreset, diameter: CGFloat) -> some View {
        let leaf = model.showsLeaf ? focusStores?.nextHoursLeaf(at: sessions.now, collection: collection) : nil
        let species = leaf.flatMap { LeafCatalog.shared.species(id: $0.speciesID) }
        let fill = leaf.map { DialFill(rung: $0, sessionHours: 0) } ?? DialFill()
        return MinuteDial(frame: .off(layout: DialLayout(plannedMinutes: preset.minutes)), diameter: diameter, theme: theme) {
            DialCentre(leaf: species.map { DialLeaf(species: $0, fill: fill) }, numeral: DialCentre.numeralParts(model.lengthText),
                       caption: model.caption, diameter: diameter)
        }
        .accessibilityHidden(true)
    }

    private func card(_ model: NeedsScreenTimeModel) -> some View {
        VStack(spacing: theme.spacing.xs) {
            Text(model.card.title)
                .font(MapleFont.headline)
                .foregroundStyle(theme.colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let line = model.card.body {
                Text(line)
                    .font(MapleFont.callout)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            if let primary = model.card.primary {
                Button { turnOn() } label: {
                    // The capsule sits inside the card, so at accessibility sizes "Turn on Screen Time" needs a third line
                    // that the capsule's own two-line limit would cut off. A limit set on the label itself wins over it.
                    Text(primary).lineLimit(nil)
                }
                .buttonStyle(.moonlight)
                .disabled(isAsking)
                .padding(.top, theme.spacing.xs)
            }
            TextLink(model.plainTimerLink, chevron: false) {
                tab.plainTimer = .chosen
                // A build that can never block remembers it, so its card doesn't come before every session.
                settings.choosePlainTimer(capability: sessions.blocking.capability)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(theme.spacing.md)
        .surface(.level1, radius: theme.radius.tile)
    }

    private func turnOn() {
        guard !isAsking else { return }
        isAsking = true
        Task {
            _ = await sessions.requestAuthorization()
            isAsking = false
        }
    }
}
