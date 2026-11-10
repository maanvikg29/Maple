import Foundation
import Observation
import SwiftUI

/// What another tab asks the Focus tab to show (F1-20, §5.3, §5.10, §6). `FocusView` applies it once and clears it.
enum FocusRequest: Hashable {
    /// Home's Start when the start screen has something to say: that preset, selected.
    case selectPreset(UUID)
    /// Home's "Turn on blocking", and every "Turn on Screen Time" (Home's next-leaf row, the Herbarium): Needs Screen
    /// Time.
    case needsScreenTime
    /// A session-end notification's tap: that session's receipt.
    case receipt(UUID)
    /// Home's "Return to session": the running session, no longer minimised.
    case returnToSession
    /// Settings' "Release all apps" during a session (§5.12): the session's own way out, End early or the emergency
    /// release (`FocusReleaseRouter`).
    case releaseAll
}

/// Navigation requests that cross tabs, such as the Tree view's "See all leaves" (spec §8.4).
@Observable
final class AppRouter {
    var selectedTab: AppTab
    /// One-shot request for the Herbarium to show only earned leaves. The Herbarium clears it once applied.
    var herbariumEarnedOnlyRequest = false

    init(selectedTab: AppTab = .home) {
        self.selectedTab = selectedTab
    }

    /// Bumped by Home's tree caption: the Herbarium scrolls back to its top (spec §3.2).
    var herbariumTopRequest = 0

    func showHerbarium() {
        herbariumTopRequest += 1
        selectedTab = .herbarium
    }

    func showEarnedLeaves() {
        herbariumEarnedOnlyRequest = true
        selectedTab = .herbarium
    }

    /// One-shot request from leaf detail's "Show on my maple" (spec §5.6): Home opens the Tree view centred on this
    /// leaf's rosette and pulses its halo, then clears it. A detail inside a presentation of its own goes through
    /// `\.showOnMaple` instead (see `ShowOnMapleAction`).
    var treeLeafRequest: String?

    func showOnMaple(_ speciesID: String) {
        treeLeafRequest = speciesID
        selectedTab = .home
    }

    /// One-shot request for the Focus tab; `FocusView` applies it and clears it. Home closes its own sheet or cover
    /// when one arrives, so a request made from inside one shows the tab.
    var focusRequest: FocusRequest?

    /// Shows the Focus tab, with what it should show.
    func showFocus(_ request: FocusRequest) {
        focusRequest = request
        selectedTab = .focus
    }
}

/// What leaf detail's "Show on my maple" does when the detail sits inside a presentation that has to handle it
/// itself: the Tree view pops back and re-centres its own maple, and the Herbarium's Search sheet closes before
/// Home opens the Tree view. Elsewhere the link goes through `AppRouter.showOnMaple(_:)`.
struct ShowOnMapleAction {
    let perform: (String) -> Void

    func callAsFunction(_ speciesID: String) {
        perform(speciesID)
    }
}

extension EnvironmentValues {
    @Entry var showOnMaple: ShowOnMapleAction? = nil
}
