import Foundation
import MapleFocusCore

/// The intention chips above the "What's this for?" field (F1 design §5.16, §5.8): the last 3 distinct intentions,
/// with ones the member said were "Partly" or "Not yet" done first. "All done" drops an intention.
public enum RecentIntentions {
    public static let limit = 3
    public static let maximumLength = 60

    public struct Entry: Sendable, Equatable {
        public var text: String
        public var reflection: Reflection?
        public var at: Date

        public init(text: String, reflection: Reflection?, at: Date) {
            self.text = text
            self.reflection = reflection
            self.at = at
        }
    }

    public static func chips(_ entries: [Entry]) -> [String] {
        var seen = Set<String>()
        var carried: [String] = []
        var others: [String] = []
        for entry in entries.sorted(by: { $0.at > $1.at }) {
            guard let text = normalized(entry.text), seen.insert(text.lowercased()).inserted else { continue }
            switch entry.reflection {
            case .allDone: continue
            case .partly, .notYet: carried.append(text)
            case nil: others.append(text)
            }
        }
        return Array((carried + others).prefix(limit))
    }

    /// Trimmed and kept to 60 characters; nil when empty.
    public static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maximumLength))
    }
}
