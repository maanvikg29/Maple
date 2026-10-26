import Foundation
import MapleFocusCore

/// The Blocking sheet's rules for one app list (F1 design §5.14, §3.6 R3): the counter, what's wrong with the draft,
/// and whether Save may store it. An empty selection never replaces a full one, and no more than 50 app or 50 web
/// tokens rest across every list (above that iOS silently blocks nothing).
public struct BlockingSheetModel: Sendable, Equatable {
    public enum Problem: Sendable, Equatable {
        /// Empty, over a list that holds something: Save is off.
        case wouldEmpty
        /// More than 50 apps, or 50 sites, across every list: Save is off.
        case overLimit
        /// "Only these" with a category, or with more than 20 apps and sites: it saves, but won't count.
        case onlyTheseWontCount
    }

    public let draft: SelectionSummary
    /// The larger of apps and sites across every list, with this draft in place of the list as saved.
    public let totalTokens: Int
    public let problem: Problem?
    /// Save would change something: another list for the preset, or this list's choice or mode.
    public let isChange: Bool

    /// - Parameters:
    ///   - saved: This list as saved.
    ///   - others: Every other list, as saved.
    ///   - isChange: Whether Save would change anything; while it wouldn't, Save is off, as the editor's is.
    public init(draft: SelectionSummary, saved: SelectionSummary, others: [SelectionSummary], isChange: Bool = true) {
        self.draft = draft
        self.isChange = isChange
        let apps = others.reduce(draft.apps) { $0 + $1.apps }
        let sites = others.reduce(draft.sites) { $0 + $1.sites }
        totalTokens = max(apps, sites)
        if draft.isEmpty, !saved.isEmpty {
            problem = .wouldEmpty
        } else if apps > SelectionSummary.tokenLimit || sites > SelectionSummary.tokenLimit {
            problem = .overLimit
        } else if draft.mode == .onlyThese, !draft.qualifies {
            problem = .onlyTheseWontCount
        } else {
            problem = nil
        }
    }

    /// Task 4's counter for the draft: "6 apps · 1 site" or "No apps chosen yet", with "Up to 50 apps can rest at
    /// once" near the limit.
    public var counter: SelectionText.Counter {
        SelectionText.counter(draft, totalTokens: totalTokens)
    }

    public var problemLine: String? {
        switch problem {
        case .wouldEmpty: FocusSheetCopy.keepOneChosen
        case .overLimit: FocusSheetCopy.overLimit
        case .onlyTheseWontCount: FocusSheetCopy.onlyTheseNote
        case nil: nil
        }
    }

    /// The line under the counter: the problem's, which also covers the limit when over it, else the counter's own
    /// limit note.
    public var note: String? { problemLine ?? counter.limitNote }

    public var canSave: Bool { isChange && problem != .wouldEmpty && problem != .overLimit }
}
