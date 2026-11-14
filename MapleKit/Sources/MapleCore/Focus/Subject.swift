import Foundation

/// One of the member's subjects (F2 Study record): a name, and nothing else. A session carries its subject's id; the
/// name lives only in `subjects.json`, never in the ledger (F1-19).
public struct Subject: Codable, Sendable, Hashable, Identifiable {
    /// The most subjects offered at once. Removed ones don't count.
    public static let maximumCount = 8
    public static let nameLimit = 24

    public var id: UUID
    public var name: String
    /// Removed by the member: no longer offered at the start, but its past sessions keep its name in History.
    public var isRemoved: Bool

    public init(id: UUID = UUID(), name: String, isRemoved: Bool = false) {
        self.id = id
        self.name = name
        self.isRemoved = isRemoved
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, isRemoved
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        isRemoved = (try? c.decodeIfPresent(Bool.self, forKey: .isRemoved)) ?? false
    }

    /// A name as it is kept: on one line, single-spaced, trimmed, at most 24 characters; nil when nothing is left.
    public static func normalizedName(_ text: String) -> String? {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let joined = String(words.joined(separator: " ").prefix(nameLimit)).trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? nil : joined
    }

    /// Two names are the same subject whatever their capitals or accents' case.
    static func matches(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame
    }
}

/// The member's subjects and the subject each preset was last used with (`subjects.json`). Pure: `SubjectStore` saves
/// it.
///
/// - Up to 8 subjects are offered, in the member's order. Removed ones are kept, out of sight, so History can still
///   name their sessions; adding a removed subject's name again brings it back under its id.
/// - Decoding is tolerant: a damaged subject is skipped, and a last-used entry that can't be read is dropped.
public struct SubjectList: Codable, Sendable, Equatable {
    public enum AddOutcome: Sendable, Equatable {
        case added(Subject)
        /// A subject with this name is already offered.
        case existing(Subject)
        /// 8 subjects are offered already.
        case full
        case blank
    }

    /// Every subject: the offered ones in the member's order, removed ones among them where they were.
    public private(set) var subjects: [Subject] = []
    /// The subject each preset was last started with, by the preset's lowercased id. No entry: no subject.
    public private(set) var lastUsed: [String: UUID] = [:]
    /// Decoding skipped a damaged subject, or the list itself was unreadable. Not saved, and not part of equality.
    public private(set) var decodedWithLosses = false

    public init() {}

    /// The subjects offered at the start, in the member's order.
    public var active: [Subject] { subjects.filter { !$0.isRemoved } }
    public var canAdd: Bool { active.count < Subject.maximumCount }
    /// Any session ever had a subject to pick: History shows "By subject" from then on.
    public var isEmpty: Bool { subjects.isEmpty }

    /// A subject by id, removed or not.
    public func subject(id: UUID) -> Subject? {
        subjects.first { $0.id == id }
    }

    /// The name History and the session screens show for `id`; nil for no subject, or one the list doesn't hold.
    public func name(for id: UUID?) -> String? {
        id.flatMap(subject(id:))?.name
    }

    /// Adds a subject at the end. A name already offered gives that subject back; a removed subject's name brings it
    /// back, with the capitals now typed.
    public mutating func add(_ name: String) -> AddOutcome {
        guard let name = Subject.normalizedName(name) else { return .blank }
        if let existing = active.first(where: { Subject.matches($0.name, name) }) { return .existing(existing) }
        guard canAdd else { return .full }
        if let index = subjects.firstIndex(where: { $0.isRemoved && Subject.matches($0.name, name) }) {
            var restored = subjects.remove(at: index)
            restored.name = name
            restored.isRemoved = false
            subjects.append(restored)
            return .added(restored)
        }
        let subject = Subject(name: name)
        subjects.append(subject)
        return .added(subject)
    }

    /// - Returns: False for a blank name, another offered subject's name, or a subject the list doesn't offer.
    public mutating func rename(_ id: UUID, to name: String) -> Bool {
        guard let name = Subject.normalizedName(name),
              let index = subjects.firstIndex(where: { $0.id == id && !$0.isRemoved }),
              !active.contains(where: { $0.id != id && Subject.matches($0.name, name) })
        else { return false }
        subjects[index].name = name
        return true
    }

    /// Stops offering the subject. Its sessions keep it, and no preset remembers it any more.
    public mutating func remove(_ id: UUID) {
        guard let index = subjects.firstIndex(where: { $0.id == id && !$0.isRemoved }) else { return }
        subjects[index].isRemoved = true
        lastUsed = lastUsed.filter { $0.value != id }
    }

    /// Reorders the offered subjects, as a list's `onMove` gives it.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var offered = active
        let moving = source.filter { offered.indices.contains($0) }.map { offered[$0] }
        guard !moving.isEmpty else { return }
        let before = source.filter { $0 < destination }.count
        for index in source.sorted(by: >) where offered.indices.contains(index) { offered.remove(at: index) }
        offered.insert(contentsOf: moving, at: min(max(0, destination - before), offered.count))
        subjects = offered + subjects.filter(\.isRemoved)
    }

    /// The subject `preset` was last started with, while it is still offered.
    public func lastUsed(with preset: UUID) -> UUID? {
        guard let id = lastUsed[preset.uuidString.lowercased()], subject(id: id)?.isRemoved == false else { return nil }
        return id
    }

    /// Remembers the subject a session with `preset` started with; nil remembers "No subject". A subject the list
    /// doesn't offer changes nothing.
    public mutating func markUsed(_ subject: UUID?, with preset: UUID) {
        let key = preset.uuidString.lowercased()
        guard let subject else {
            lastUsed[key] = nil
            return
        }
        guard self.subject(id: subject)?.isRemoved == false else { return }
        lastUsed[key] = subject
    }

    /// Forgets presets that no longer exist.
    public mutating func keepLastUsed(for presets: [UUID]) {
        let keys = Set(presets.map { $0.uuidString.lowercased() })
        lastUsed = lastUsed.filter { keys.contains($0.key) }
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case subjects, lastUsed
    }

    private struct Lossy: Decodable {
        let subject: Subject?

        init(from decoder: any Decoder) throws {
            subject = try? Subject(from: decoder)
        }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try? c.decodeIfPresent([Lossy].self, forKey: .subjects)
        var seen = Set<UUID>()
        subjects = (entries ?? []).compactMap(\.subject).filter { seen.insert($0.id).inserted }
        decodedWithLosses = (c.contains(.subjects) && entries == nil) || subjects.count < (entries?.count ?? 0)
        let used = (try? c.decodeIfPresent([String: String].self, forKey: .lastUsed)) ?? [:]
        lastUsed = used.reduce(into: [:]) { result, entry in
            if let id = UUID(uuidString: entry.value) { result[entry.key.lowercased()] = id }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(subjects, forKey: .subjects)
        try c.encode(lastUsed.mapValues(\.uuidString), forKey: .lastUsed)
    }

    public static func == (lhs: SubjectList, rhs: SubjectList) -> Bool {
        lhs.subjects == rhs.subjects && lhs.lastUsed == rhs.lastUsed
    }
}
