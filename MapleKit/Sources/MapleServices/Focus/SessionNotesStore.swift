import Foundation
import MapleCore
import Observation

/// One session's intention. Free text never goes into the ledger (F1-19).
nonisolated public struct SessionNote: Codable, Sendable, Equatable {
    public var text: String
    public var at: Date

    public init(text: String, at: Date) {
        self.text = text
        self.at = at
    }
}

nonisolated public struct SessionNotesFile: Codable, Sendable, Equatable {
    /// Keyed by the lowercased session id.
    public var notes: [String: SessionNote]

    public init(notes: [String: SessionNote] = [:]) {
        self.notes = notes
    }
}

/// Intentions by session (`session-notes.json`, F1 design §5.16): the member can edit and erase them, and only the
/// newest 200 are kept.
@Observable
public final class SessionNotesStore {
    nonisolated public static let file = "session-notes.json"
    nonisolated public static let kept = 200

    public private(set) var notes: [String: SessionNote]
    public private(set) var isAvailable: Bool

    @ObservationIgnored private let storage: JSONStorage<SessionNotesFile>

    public init(storage: JSONStorage<SessionNotesFile>) {
        self.storage = storage
        let loaded = Self.contents(of: storage.read())
        notes = loaded ?? [:]
        isAvailable = loaded != nil
    }

    /// Reads the notes again if they couldn't be read at launch. Every change does this first, so it lands on the
    /// member's real notes, and erasing them erases the file's.
    /// - Returns: Whether the store now holds the member's real notes (or knows there are none).
    @discardableResult
    public func reloadIfUnavailable() -> Bool {
        guard !isAvailable else { return false }
        guard let loaded = Self.contents(of: storage.read()) else { return false }
        notes = loaded
        isAvailable = true
        return true
    }

    public func intention(for session: UUID) -> String? {
        notes[session.uuidString.lowercased()]?.text
    }

    /// Sets a session's intention (trimmed, at most 60 characters); an empty one removes it. Does nothing while the
    /// saved notes still can't be read.
    public func setIntention(_ text: String?, for session: UUID, at date: Date) {
        guard isAvailable || reloadIfUnavailable() else { return }
        let key = session.uuidString.lowercased()
        if let text = text.flatMap(RecentIntentions.normalized) {
            notes[key] = SessionNote(text: text, at: notes[key]?.at ?? date)
        } else {
            notes[key] = nil
        }
        if notes.count > Self.kept {
            let oldest = notes.sorted { $0.value.at < $1.value.at }.prefix(notes.count - Self.kept).map(\.key)
            for key in oldest { notes[key] = nil }
        }
        persist()
    }

    /// - Returns: False while the saved notes still can't be read: nothing is erased then, in memory or on disk.
    @discardableResult
    public func eraseAll() -> Bool {
        guard isAvailable || reloadIfUnavailable() else { return false }
        notes = [:]
        persist()
        return true
    }

    /// Every intention with the session's reflection, for `RecentIntentions.chips`.
    public func entries(reflections: [UUID: Reflection]) -> [RecentIntentions.Entry] {
        let byKey = Dictionary(uniqueKeysWithValues: reflections.map { ($0.key.uuidString.lowercased(), $0.value) })
        return notes.map { RecentIntentions.Entry(text: $0.value.text, reflection: byKey[$0.key], at: $0.value.at) }
            .sorted { $0.at < $1.at }
    }

    /// The saved notes, or none for a first run; nil while the file can't be read.
    private static func contents(of read: StorageRead<SessionNotesFile>) -> [String: SessionNote]? {
        switch read {
        case .value(let saved): saved.notes
        case .absent: [:]
        case .unavailable: nil
        }
    }

    private func persist() {
        guard isAvailable else { return }
        storage.save(SessionNotesFile(notes: notes))
    }
}
