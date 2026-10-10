import Foundation
import MapleCore

/// One sitting of the reveal: the queue of waiting leaves captured when the cover opened, which of them have
/// been opened, and what the footer offers (spec §5.8). Pure, so the flow's rules are unit-tested; the app's
/// `RevealFlow` drives it and tells the collection what was placed.
///
/// ```swift
/// var session = RevealSession(queue: collection.revealable(at: now), startingWith: "rubrum",
///                             revealsBefore: collection.revealsOpened)
/// session.open(at: now)            // the tap: the current bud opens
/// session.footer                   // .next(total: 3) while more wait, then .place
/// session.advance()                // "Next leaf"
/// session.openAll(at: now)         // "Open all 3"
/// collection.openReveals(session.opened, at: now)   // "Place on your maple"
/// ```
nonisolated public struct RevealSession: Sendable, Equatable {
    /// One waiting leaf in the queue.
    public struct Item: Sendable, Equatable, Identifiable {
        public var id: String { speciesID }
        public let speciesID: String
        public let tier: RewardTier

        public init(speciesID: String, tier: RewardTier) {
            self.speciesID = speciesID
            self.tier = tier
        }
    }

    /// What the footer offers once the current leaf has opened.
    public enum Footer: Sendable, Equatable {
        /// More leaves wait: primary "Next leaf", and the text link "Open all {total}".
        case next(total: Int)
        /// The last one: primary "Place on your maple".
        case place
    }

    /// The leaves to open, in order: the requested one first, then the rest oldest first.
    public let items: [Item]
    /// Reveals opened before this sitting; the first 3 ever get the full ritual.
    public let revealsBefore: Int
    /// The leaf on screen.
    public private(set) var index = 0
    /// When each leaf was tapped open, by position in `items`.
    public private(set) var openedAt: [Date?]
    /// When "Open all" was tapped.
    public private(set) var openAllAt: Date?
    /// The leaves "Open all" opened, after the one that was on screen.
    public private(set) var openAllRange: Range<Int>?

    /// - Parameters:
    ///   - queue: `CollectionStore.revealable(at:)`: what may be opened now, oldest first.
    ///   - startingWith: A waiting leaf to open first (a tapped tile or bud); ignored when it isn't in the queue.
    ///   - revealsBefore: `CollectionStore.revealsOpened`.
    public init(queue: [LeafUnlock], startingWith: String? = nil, revealsBefore: Int, catalog: RewardCatalog = .shared) {
        let ordered = Self.ordered(queue.map(\.speciesID), startingWith: startingWith)
        self.init(
            items: ordered.map { Item(speciesID: $0, tier: catalog.reward(forSpecies: $0)?.tier ?? .common) },
            revealsBefore: revealsBefore
        )
    }

    public init(items: [Item], revealsBefore: Int) {
        self.items = items
        self.revealsBefore = max(0, revealsBefore)
        openedAt = Array(repeating: nil, count: items.count)
    }

    /// `ids` with `first` moved to the front when it is among them; otherwise unchanged.
    public static func ordered(_ ids: [String], startingWith first: String?) -> [String] {
        guard let first, let position = ids.firstIndex(of: first) else { return ids }
        var ordered = ids
        ordered.remove(at: position)
        ordered.insert(first, at: 0)
        return ordered
    }

    // MARK: State

    public var isEmpty: Bool { items.isEmpty }
    public var current: Item? { items.indices.contains(index) ? items[index] : nil }
    /// The current leaf has been tapped open.
    public var isCurrentOpen: Bool { openedAt.indices.contains(index) && openedAt[index] != nil }
    public var currentOpenedAt: Date? { openedAt.indices.contains(index) ? openedAt[index] : nil }
    public var isOpeningAll: Bool { openAllAt != nil }
    /// `speciesID` is the leaf on screen, opened, outside "Open all": the only time its share card is worth rendering.
    public func isShowingOpened(_ speciesID: String) -> Bool {
        !isOpeningAll && isCurrentOpen && current?.speciesID == speciesID
    }

    /// "1 of 3" for the header while more than one leaf waits; nil for a single leaf.
    public var position: (index: Int, count: Int)? {
        items.count > 1 ? (index + 1, items.count) : nil
    }

    /// The footer for the current leaf.
    public var footer: Footer {
        index < items.count - 1 && !isOpeningAll ? .next(total: items.count) : .place
    }

    /// Every leaf opened so far, in queue order: what "Place on your maple" places.
    public var opened: [String] {
        items.indices.filter { openedAt[$0] != nil }.map { items[$0].speciesID }
    }

    /// Leaves still closed, after the one on screen.
    public var remaining: [Item] {
        guard index + 1 < items.count else { return [] }
        return Array(items[(index + 1)...])
    }

    /// Every leaf not opened yet in this sitting, the one on screen included while it is closed.
    public var unopened: [Item] {
        items.indices.filter { openedAt[$0] == nil }.map { items[$0] }
    }

    /// Whether the next tap may still open what it would open: the closed bud on screen, or with "Open all" every
    /// leaf after it. `openable` is what may be opened now (`CollectionStore.revealable(at:)`); once Evening has
    /// turned into Wind-down mid-sitting it no longer holds them, and the rest waits for the morning (D8).
    public func mayOpen(all: Bool = false, openable: Set<String>) -> Bool {
        let leaves = all ? remaining : (isCurrentOpen ? [] : current.map { [$0] } ?? [])
        return leaves.allSatisfy { openable.contains($0.speciesID) }
    }

    /// The ritual for the leaf at `position`: the full one for the first 3 reveals ever and for uncommon, rare and
    /// legendary leaves (D8), the crossfade under Reduce Motion.
    public func ritual(at position: Int, reduceMotion: Bool) -> RevealRitual {
        guard items.indices.contains(position) else { return reduceMotion ? .crossfade : .short }
        return RevealRitual(tier: items[position].tier, revealsBefore: revealsBefore + position, reduceMotion: reduceMotion)
    }

    // MARK: Changes

    /// The tap: opens the current leaf.
    /// - Returns: Whether it opened (false when it was already open): play the reveal haptic.
    @discardableResult
    public mutating func open(at date: Date) -> Bool {
        guard openedAt.indices.contains(index), openedAt[index] == nil else { return false }
        openedAt[index] = date
        return true
    }

    /// "Next leaf": the next closed bud.
    public mutating func advance() {
        guard isCurrentOpen, index + 1 < items.count, !isOpeningAll else { return }
        index += 1
    }

    /// "Open all": every remaining bud opens at once (in a staggered row).
    /// - Returns: Whether anything opened: play the reveal haptic.
    @discardableResult
    public mutating func openAll(at date: Date) -> Bool {
        guard isCurrentOpen, !isOpeningAll, index + 1 < items.count else { return false }
        openAllAt = date
        openAllRange = (index + 1)..<items.count
        for position in (index + 1)..<items.count {
            openedAt[position] = date
        }
        return true
    }
}
