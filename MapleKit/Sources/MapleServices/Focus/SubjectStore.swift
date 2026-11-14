import Foundation
import MapleCore
import Observation

/// The member's subjects (`subjects.json`, F2 Study record): up to 8 offered at the start, each preset's last-used one,
/// and the removed ones History still names. The rules are `SubjectList`'s; this saves it.
///
/// While the file exists but can't be read yet nothing is offered and nothing is saved, so a later save never writes
/// over the member's real subjects. Every change reads again first.
@Observable
public final class SubjectStore {
    nonisolated public static let file = "subjects.json"

    public private(set) var list: SubjectList
    public private(set) var isAvailable: Bool

    @ObservationIgnored private let storage: JSONStorage<SubjectList>

    public init(storage: JSONStorage<SubjectList>) {
        self.storage = storage
        let loaded = Self.contents(of: storage.read(), in: storage)
        list = loaded ?? SubjectList()
        isAvailable = loaded != nil
    }

    /// Reads the subjects again if they couldn't be read at launch.
    /// - Returns: Whether the store now holds the member's real subjects (or knows there are none).
    @discardableResult
    public func reloadIfUnavailable() -> Bool {
        guard !isAvailable else { return false }
        guard let loaded = Self.contents(of: storage.read(), in: storage) else { return false }
        list = loaded
        isAvailable = true
        return true
    }

    /// The subjects offered at the start, in the member's order.
    public var active: [Subject] { list.active }
    public var canAdd: Bool { list.canAdd }

    /// A subject's name, removed or not; nil for no subject.
    public func name(for id: UUID?) -> String? { list.name(for: id) }

    /// The subject `preset` was last started with, while it is still offered.
    public func lastUsed(with preset: UUID) -> UUID? { list.lastUsed(with: preset) }

    /// - Returns: Nil while the saved subjects still can't be read (nothing changes then).
    @discardableResult
    public func add(_ name: String) -> SubjectList.AddOutcome? {
        guard isAvailable || reloadIfUnavailable() else { return nil }
        return change { $0.add(name) }
    }

    /// - Returns: False for a blank or taken name, or while the saved subjects still can't be read.
    @discardableResult
    public func rename(_ id: UUID, to name: String) -> Bool {
        guard isAvailable || reloadIfUnavailable() else { return false }
        return change { $0.rename(id, to: name) }
    }

    /// Stops offering the subject; its sessions keep its name.
    public func remove(_ id: UUID) {
        guard isAvailable || reloadIfUnavailable() else { return }
        change { $0.remove(id) }
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard isAvailable || reloadIfUnavailable() else { return }
        change { $0.move(fromOffsets: source, toOffset: destination) }
    }

    /// Remembers the subject a session with `preset` started with; nil remembers "No subject".
    public func markUsed(_ subject: UUID?, with preset: UUID) {
        guard isAvailable || reloadIfUnavailable() else { return }
        change { $0.markUsed(subject, with: preset) }
    }

    // MARK: Private

    /// What a read means for the store: the saved subjects (a file that read with losses is copied aside first, so a
    /// later save never destroys the original), or none; nil while the file can't be read.
    private static func contents(of read: StorageRead<SubjectList>, in storage: JSONStorage<SubjectList>) -> SubjectList? {
        switch read {
        case .value(let saved):
            if saved.decodedWithLosses { storage.copyAside() }
            return saved
        case .absent:
            return SubjectList()
        case .unavailable:
            return nil
        }
    }

    @discardableResult
    private func change<Result>(_ edit: (inout SubjectList) -> Result) -> Result {
        var copy = list
        let result = edit(&copy)
        if copy != list {
            list = copy
            storage.save(copy)
        }
        return result
    }
}
