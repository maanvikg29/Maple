#if DEBUG
import SwiftUI

/// DEBUG only: the Herbarium's `-MapleDemoPresent` values (docs/debug-launch-arguments.md), read once per launch
/// and only when the app opens on the Herbarium tab (`-MapleDemoTab herbarium`).
enum HerbariumDemo: Equatable {
    case leaf(String)
    case share(String)
    case rarity
    case filter
    case search(String)

    private static var taken = false

    /// The requested presentation, the first time it is asked for.
    static func take(defaults: UserDefaults = .standard) -> HerbariumDemo? {
        guard !taken, defaults.string(forKey: "MapleDemoTab") == "herbarium",
              let value = defaults.string(forKey: "MapleDemoPresent") else { return nil }
        taken = true
        return HerbariumDemo(value)
    }

    /// `-MapleDemoScroll <section id>` (a category id such as `steady_mornings`, or `dormant`): scrolls the grid so
    /// that section's header is pinned at the top, for screenshots of the lower sections.
    @MainActor
    static func scroll(_ proxy: ScrollViewProxy, defaults: UserDefaults = .standard) async {
        guard defaults.string(forKey: "MapleDemoTab") == "herbarium",
              let section = defaults.string(forKey: "MapleDemoScroll") else { return }
        try? await Task.sleep(for: .milliseconds(600))
        proxy.scrollTo(section, anchor: .top)
    }

    init?(_ value: String) {
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        let argument = parts.count > 1 ? parts[1] : ""
        switch parts.first {
        case "leaf" where !argument.isEmpty: self = .leaf(argument)
        case "share" where !argument.isEmpty: self = .share(argument)
        case "rarity": self = .rarity
        case "filter": self = .filter
        case "search": self = .search(argument)
        default: return nil
        }
    }
}
#endif
