import Foundation
import MapleFocusCore

/// What a selection holds, in words (F1 design §5.1, §5.4, §5.14).
public enum SelectionText {
    /// The start screen's Blocking line (§5.1, §5.2): what is blocked, the strictness, then "›". Locked draws
    /// `lock.fill` before its name; `printed` leaves the symbol out.
    public struct BlockingLine: Sendable, Hashable {
        /// "Blocking 6 apps", "Choose apps to block", "Allowing 24 apps · 20 or fewer count".
        public let text: String
        /// Nil when a prompt or a warning takes the line.
        public let strictness: Strictness?
        /// The selection can't count as it is: no apps, one that doesn't qualify, or apps to choose again.
        public let needsAttention: Bool

        public var showsLock: Bool { strictness == .locked }
        public var strictnessName: String? { strictness.map { FocusCopy.strictnessName($0) } }

        /// As printed, without the lock symbol: "Blocking 6 apps · Locked ›".
        public var printed: String {
            strictnessName.map { "\(text) · \($0) ›" } ?? "\(text) ›"
        }

        /// For VoiceOver: "Blocking 6 apps, Locked".
        public var spoken: String {
            strictnessName.map { "\(text), \($0)" } ?? text
        }
    }

    /// The Blocking sheet's counter (§5.14).
    public struct Counter: Sendable, Hashable {
        /// "6 apps · 1 site".
        public let text: String
        /// "Up to 50 apps can rest at once", near the limit.
        public let limitNote: String?
    }

    /// From this many tokens across every set (`AppSetStore.totalTokens`), the counter names the 50-app limit.
    public static let nearLimit = 40

    /// Checked in `StartReadiness`'s order: no apps, a selection that can't count (R3), expired tokens.
    public static func blockingLine(_ selection: SelectionSummary?, strictness: Strictness, expired: Bool) -> BlockingLine {
        guard let selection, !selection.isEmpty else {
            return BlockingLine(text: "Choose apps to block", strictness: nil, needsAttention: true)
        }
        if !selection.qualifies {
            return BlockingLine(text: notQualifying(selection), strictness: nil, needsAttention: true)
        }
        if expired {
            return BlockingLine(text: "Some apps need choosing again", strictness: nil, needsAttention: true)
        }
        return BlockingLine(text: "\(verb(selection.mode)) \(list(selection))", strictness: strictness, needsAttention: false)
    }

    /// The running header's line under the title (§5.4): "6 apps resting"; an allow list or categories read "Apps
    /// resting"; a plain timer reads "Plain timer · apps aren't locked".
    public static func restingLine(_ selection: SelectionSummary?, isPlainTimer: Bool) -> String {
        guard !isPlainTimer, let selection else { return "Plain timer · apps aren't locked" }
        guard countsByName(selection) else { return "Apps resting" }
        return "\(list(selection)) resting"
    }

    /// The capsule after Start, until the read-back confirms the block (§5.1): "Locking 6 apps…".
    public static func locking(_ selection: SelectionSummary?) -> String {
        guard let selection, countsByName(selection) else { return "Locking apps…" }
        return "Locking \(list(selection))…"
    }

    public static func counter(_ selection: SelectionSummary, totalTokens: Int) -> Counter {
        let items = parts(selection)
        return Counter(
            text: items.isEmpty ? "No apps chosen yet" : items.joined(separator: " · "),
            limitNote: totalTokens >= nearLimit ? "Up to \(SelectionSummary.tokenLimit) apps can rest at once" : nil
        )
    }

    // MARK: Private

    /// A block list of apps and sites, without categories, names its count; anything else reads "apps".
    private static func countsByName(_ selection: SelectionSummary) -> Bool {
        selection.mode == .blockThese && selection.categories == 0 && !selection.isEmpty
    }

    private static func notQualifying(_ selection: SelectionSummary) -> String {
        let held = "\(verb(selection.mode)) \(list(selection))"
        if selection.mode == .onlyThese {
            if selection.categories > 0 { return "\(held) · allow apps, not categories" }
            if selection.apps + selection.sites > SelectionSummary.onlyTheseLimit {
                return "\(held) · \(SelectionSummary.onlyTheseLimit) or fewer count"
            }
        }
        return "\(held) · \(SelectionSummary.tokenLimit) or fewer count"
    }

    private static func verb(_ mode: SelectionSummary.Mode) -> String {
        switch mode {
        case .blockThese: "Blocking"
        case .onlyThese: "Allowing"
        }
    }

    /// "1 category", "6 apps", "1 site", in that order, for what the selection holds.
    private static func parts(_ selection: SelectionSummary) -> [String] {
        var found: [String] = []
        if selection.categories > 0 { found.append(count(selection.categories, "category", "categories")) }
        if selection.apps > 0 { found.append(count(selection.apps, "app", "apps")) }
        if selection.sites > 0 { found.append(count(selection.sites, "site", "sites")) }
        return found
    }

    /// "6 apps", "1 category and 2 apps", "1 category, 2 apps and 1 site".
    private static func list(_ selection: SelectionSummary) -> String {
        let items = parts(selection)
        guard let last = items.last else { return count(0, "app", "apps") }
        return items.count == 1 ? last : items.dropLast().joined(separator: ", ") + " and " + last
    }

    private static func count(_ value: Int, _ one: String, _ many: String) -> String {
        "\(value) \(value == 1 ? one : many)"
    }
}
