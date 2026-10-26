import Foundation

/// "What's this for?" as it is typed (F1 design §5.16): at most 60 characters, Return saves it trimmed, and a cleared
/// field removes the intention.
public struct IntentionDraft: Sendable, Equatable {
    public private(set) var text: String

    public init(_ intention: String?) {
        text = String((intention ?? "").prefix(RecentIntentions.maximumLength))
    }

    /// The field after typing: its first 60 characters.
    public mutating func type(_ typed: String) {
        text = String(typed.prefix(RecentIntentions.maximumLength))
    }

    /// What Return saves: trimmed, or nil (no intention) for a blank field.
    public var saved: String? { RecentIntentions.normalized(text) }

    public var isCleared: Bool { saved == nil }
}
