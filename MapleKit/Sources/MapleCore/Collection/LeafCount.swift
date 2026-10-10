import Foundation

/// The collection's one count rule (spec §5.2): "N of 155" counts **opened** leaves, the ones placed on the tree.
///
/// Every surface that shows N reads it from here: Home's tree caption, the Tree view, the Herbarium's count, owned
/// bar, "Earned" chip and section counts, the Profile line, the onboarding seedling and VoiceOver. A waiting leaf
/// (earned but not opened yet) is drawn as a bud and may be mentioned on its own ("1 waiting"), but it never adds
/// to N, so a count can't rise before the reveal shows the leaf.
///
/// ```swift
/// let count = collection.leafCount       // the whole collection
/// Text(count.text)                       // "23 of 155"
/// if let waiting = count.waitingText { Text(waiting) }   // "1 waiting"
/// LeafCount(section.map(\.progress)).text                // one Herbarium section: "6 of 15"
/// ```
public struct LeafCount: Sendable, Equatable {
    /// Opened leaves: N.
    public let opened: Int
    /// Earned leaves not opened yet (held or pending). Never part of N.
    public let waiting: Int
    /// Every leaf counted against: 155 for the collection, a section's size for a section.
    public let total: Int

    public init(opened: Int, waiting: Int = 0, total: Int) {
        self.opened = max(0, opened)
        self.waiting = max(0, waiting)
        self.total = max(0, total)
    }

    /// Counts a group of leaves (the whole collection, or one Herbarium section) by their state.
    public init<Leaves: Sequence>(_ leaves: Leaves) where Leaves.Element == LeafProgress {
        var opened = 0, waiting = 0, total = 0
        for leaf in leaves {
            total += 1
            if leaf.state.isOpened { opened += 1 } else if leaf.state.isWaiting { waiting += 1 }
        }
        self.init(opened: opened, waiting: waiting, total: total)
    }

    /// Counts the member's unlocks against the whole catalogue.
    public init(unlocks: [LeafUnlock], total: Int = LeafCatalog.shared.species.count) {
        let opened = unlocks.filter(\.revealed).count
        self.init(opened: opened, waiting: unlocks.count - opened, total: total)
    }

    /// Opened leaves as a share of the total, 0…1 (the Herbarium's owned bar).
    public var fraction: Double {
        total > 0 ? min(1, Double(opened) / Double(total)) : 0
    }

    /// "23 of 155".
    public var text: String {
        "\(opened) of \(total)"
    }

    /// "23 of 155 leaves", for VoiceOver.
    public var spoken: String {
        "\(opened) of \(total) leaves"
    }

    /// "1 waiting" or "2 waiting"; nil when nothing waits.
    public var waitingText: String? {
        waiting > 0 ? "\(waiting) waiting" : nil
    }

    /// "1 leaf waiting to open" or "2 leaves waiting to open", for VoiceOver; nil when nothing waits.
    public var spokenWaiting: String? {
        guard waiting > 0 else { return nil }
        return waiting == 1 ? "1 leaf waiting to open" : "\(waiting) leaves waiting to open"
    }
}

extension LeafState {
    /// Earned and opened: the leaf is on the tree and counts toward "N of 155" (`LeafCount`).
    public var isOpened: Bool {
        if case .earned = self { true } else { false }
    }

    /// Earned but not opened yet: a bud, never counted in "N of 155".
    public var isWaiting: Bool {
        if case .waiting = self { true } else { false }
    }
}

extension LeafProgress {
    /// Earned and opened: counts toward "N of 155" (`LeafCount`).
    public var isOpened: Bool { state.isOpened }
}
