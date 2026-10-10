import Observation

/// Navigation requests that cross tabs, such as the Tree view's "See all leaves" (spec §8.4).
@Observable
final class AppRouter {
    var selectedTab: AppTab
    /// One-shot request for the Herbarium to show only earned leaves. The Herbarium clears it once applied.
    var herbariumEarnedOnlyRequest = false

    init(selectedTab: AppTab = .home) {
        self.selectedTab = selectedTab
    }

    func showEarnedLeaves() {
        herbariumEarnedOnlyRequest = true
        selectedTab = .herbarium
    }
}
