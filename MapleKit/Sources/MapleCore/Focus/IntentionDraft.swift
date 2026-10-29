import Foundation

/// "What's this for?" as it is typed (F1 design §5.16): at most 60 characters, Return saves it trimmed, a cleared
/// field removes the intention, and closing the entry without Return saves what Return would.
public struct IntentionDraft: Sendable, Equatable {
    public private(set) var text: String

    public init(_ intention: String?) {
        text = String((intention ?? "").prefix(RecentIntentions.maximumLength))
    }

    /// The field after typing: its first 60 characters, on one line.
    /// - Returns: Whether the typing was Return. A field that wraps (at accessibility sizes) gets Return as a newline
    ///   rather than a submit; the newline isn't kept, and Return saves.
    @discardableResult
    public mutating func type(_ typed: String) -> Bool {
        let line = typed.replacingOccurrences(of: "\n", with: "")
        text = String(line.prefix(RecentIntentions.maximumLength))
        return line != typed
    }

    /// What Return saves: trimmed, or nil (no intention) for a blank field.
    public var saved: String? { RecentIntentions.normalized(text) }

    /// What closing the entry without Return saves (a swipe down, or a tap outside): exactly what Return saves, so
    /// typed words are never lost (owner, 2026-10-29: F1-28).
    public var savedOnDismiss: String? { saved }

    public var isCleared: Bool { saved == nil }
}
