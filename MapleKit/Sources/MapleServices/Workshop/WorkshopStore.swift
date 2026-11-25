import Foundation
import MapleCore
import Observation

/// The syrup van's leaves, syrup and machines (`workshop.json`, syrup van design §2). The rules are `WorkshopBank`'s;
/// this saves it.
///
/// While the file exists but can't be read yet, the van shows empty and nothing is saved, so a later save never writes
/// over the member's real van. Every change reads again first.
@Observable
public final class WorkshopStore {
    nonisolated public static let file = "workshop.json"

    public private(set) var bank: WorkshopBank
    public private(set) var isAvailable: Bool
    /// The economy's numbers for this launch.
    public let tuning: WorkshopTuning

    @ObservationIgnored private let storage: JSONStorage<WorkshopBank>

    public init(storage: JSONStorage<WorkshopBank>, tuning: WorkshopTuning = .starting) {
        self.storage = storage
        self.tuning = tuning
        let loaded = Self.contents(of: storage.read(), in: storage)
        bank = loaded ?? WorkshopBank()
        isAvailable = loaded != nil
    }

    /// Reads the van again if it couldn't be read at launch.
    /// - Returns: Whether the store now holds the member's real van (or knows there is none yet).
    @discardableResult
    public func reloadIfUnavailable() -> Bool {
        guard !isAvailable else { return false }
        guard let loaded = Self.contents(of: storage.read(), in: storage) else { return false }
        bank = loaded
        isAvailable = true
        return true
    }

    /// Leaves in the van now.
    public var leaves: Int { bank.leaves }
    /// Syrup in the van now, in tenths of a bottle.
    public var syrupTenths: Int { bank.syrupTenths }
    /// Tenths of a bottle a leaf cooks into now.
    public var tenthsPerLeaf: Int { bank.tenthsPerLeaf(tuning: tuning) }

    public func level(of machine: WorkshopMachine) -> Int { bank.level(of: machine, tuning: tuning) }
    /// Leaves for the machine's next level; nil at the top.
    public func price(of machine: WorkshopMachine) -> Int? { bank.price(of: machine, tuning: tuning) }

    /// Tells the van the ledger's total (`LeafEarnings.total`), counted at this launch's pace.
    /// - Returns: The leaves newly in the van; 0 while the saved van still can't be read.
    @discardableResult
    public func noteEarned(_ total: Int) -> Int {
        guard isAvailable || reloadIfUnavailable() else { return 0 }
        return change { $0.noteEarned(total, tuning: tuning) }
    }

    /// Cooks up to `count` leaves: one tap of the pot.
    /// - Returns: The leaves cooked; 0 while the saved van still can't be read.
    @discardableResult
    public func cook(_ count: Int = 1) -> Int {
        guard isAvailable || reloadIfUnavailable() else { return 0 }
        return change { $0.cook(count, tuning: tuning) }
    }

    /// - Returns: Nil while the saved van still can't be read (nothing changes then).
    @discardableResult
    public func upgrade(_ machine: WorkshopMachine) -> WorkshopBank.UpgradeOutcome? {
        guard isAvailable || reloadIfUnavailable() else { return nil }
        return change { $0.upgrade(machine, tuning: tuning) }
    }

    // MARK: Private

    /// What a read means for the store: the saved van (a file that read with losses is copied aside first, so a later
    /// save never destroys the original), or a new one; nil while the file can't be read.
    private static func contents(of read: StorageRead<WorkshopBank>, in storage: JSONStorage<WorkshopBank>) -> WorkshopBank? {
        switch read {
        case .value(let saved):
            if saved.decodedWithLosses { storage.copyAside() }
            return saved
        case .absent:
            return WorkshopBank()
        case .unavailable:
            return nil
        }
    }

    @discardableResult
    private func change<Result>(_ edit: (inout WorkshopBank) -> Result) -> Result {
        var copy = bank
        let result = edit(&copy)
        if copy != bank {
            bank = copy
            storage.save(copy)
        }
        return result
    }
}
