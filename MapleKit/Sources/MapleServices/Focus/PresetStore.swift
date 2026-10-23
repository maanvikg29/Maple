import Foundation
import MapleCore
import Observation

/// What `presets.json` holds. Decoding is tolerant: a damaged preset is skipped.
nonisolated public struct PresetsFile: Codable, Sendable, Equatable {
    public var presets: [FocusPreset]
    public var lastUsedID: UUID?
    /// Decoding skipped a damaged preset, or the list itself was unreadable. Not saved, and not part of equality.
    public private(set) var decodedWithLosses = false

    public init(presets: [FocusPreset], lastUsedID: UUID? = nil) {
        self.presets = presets
        self.lastUsedID = lastUsedID
    }

    private enum CodingKeys: String, CodingKey {
        case presets, lastUsedID
    }

    private struct Lossy: Decodable {
        let preset: FocusPreset?

        init(from decoder: any Decoder) throws {
            preset = try? FocusPreset(from: decoder)
        }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try? c.decodeIfPresent([Lossy].self, forKey: .presets)
        presets = (entries ?? []).compactMap(\.preset)
        decodedWithLosses = (c.contains(.presets) && entries == nil) || presets.count < (entries?.count ?? 0)
        lastUsedID = try? c.decodeIfPresent(UUID.self, forKey: .lastUsedID)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(presets, forKey: .presets)
        try c.encodeIfPresent(lastUsedID, forKey: .lastUsedID)
    }

    public static func == (lhs: PresetsFile, rhs: PresetsFile) -> Bool {
        lhs.presets == rhs.presets && lhs.lastUsedID == rhs.lastUsedID
    }
}

/// The member's Focus presets (F1 design §5.13): up to 6, never none. Home's Start uses the last-used one.
@Observable
public final class PresetStore {
    nonisolated public static let file = "presets.json"

    public private(set) var presets: [FocusPreset]
    public private(set) var lastUsedID: UUID?
    /// False while the file exists but can't be read yet: the defaults are shown and nothing is saved.
    public private(set) var isAvailable: Bool

    @ObservationIgnored private let storage: JSONStorage<PresetsFile>
    @ObservationIgnored private let defaultAppSetID: UUID?

    /// - Parameter defaultAppSetID: The app set new and default presets block (Distractions).
    public init(storage: JSONStorage<PresetsFile>, defaultAppSetID: UUID?) {
        self.storage = storage
        self.defaultAppSetID = defaultAppSetID
        let loaded = Self.contents(of: storage.read(), in: storage, defaultAppSetID: defaultAppSetID)
        presets = loaded?.presets ?? FocusPreset.defaults(appSetID: defaultAppSetID)
        lastUsedID = loaded?.lastUsedID
        isAvailable = loaded != nil
    }

    /// Reads the presets again if they couldn't be read at launch. Every edit does this first, so it lands on the
    /// member's real presets, never on the defaults shown meanwhile.
    /// - Returns: Whether the store now holds the member's real presets (or knows there are none).
    @discardableResult
    public func reloadIfUnavailable() -> Bool {
        guard !isAvailable else { return false }
        guard let loaded = Self.contents(of: storage.read(), in: storage, defaultAppSetID: defaultAppSetID) else {
            return false
        }
        presets = loaded.presets
        lastUsedID = loaded.lastUsedID
        isAvailable = true
        return true
    }

    /// The preset Start begins: the last used, else the first.
    public var lastUsed: FocusPreset? {
        lastUsedID.flatMap(preset(id:)) ?? presets.first
    }

    public var canAdd: Bool { presets.count < FocusPreset.maximumCount }

    public func preset(id: UUID) -> FocusPreset? {
        presets.first { $0.id == id }
    }

    /// - Returns: False at 6 presets, or while the saved presets still can't be read (nothing changes then).
    @discardableResult
    public func add(_ preset: FocusPreset) -> Bool {
        guard isAvailable || reloadIfUnavailable(), canAdd else { return false }
        change { $0.append(Self.cleaned(preset)) }
        return true
    }

    /// Replaces the preset with the same id; the name is trimmed to 24 characters and the length kept in range.
    public func update(_ preset: FocusPreset) {
        guard isAvailable || reloadIfUnavailable(),
              let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        change { $0[index] = Self.cleaned(preset) }
    }

    /// - Returns: False for the last preset, which can't be deleted, or while the saved presets still can't be read.
    @discardableResult
    public func delete(id: UUID) -> Bool {
        guard isAvailable || reloadIfUnavailable(), presets.count > 1,
              let index = presets.firstIndex(where: { $0.id == id }) else { return false }
        change { $0.remove(at: index) }
        if lastUsedID == id { setLastUsed(nil) }
        return true
    }

    public func markUsed(_ id: UUID) {
        guard isAvailable || reloadIfUnavailable(), preset(id: id) != nil else { return }
        setLastUsed(id)
    }

    // MARK: Private

    /// What a read means for the store: the saved presets (a file that read with losses is copied aside first, so a
    /// later save never destroys the original) or the defaults; nil while the file can't be read.
    private static func contents(
        of read: StorageRead<PresetsFile>, in storage: JSONStorage<PresetsFile>, defaultAppSetID: UUID?
    ) -> (presets: [FocusPreset], lastUsedID: UUID?)? {
        if case .value(let saved) = read, saved.decodedWithLosses || saved.presets.count > FocusPreset.maximumCount {
            storage.copyAside()
        }
        switch read {
        case .value(let saved) where !saved.presets.isEmpty:
            return (Array(saved.presets.prefix(FocusPreset.maximumCount)), saved.lastUsedID)
        case .value, .absent:
            return (FocusPreset.defaults(appSetID: defaultAppSetID), nil)
        case .unavailable:
            return nil
        }
    }

    private static func cleaned(_ preset: FocusPreset) -> FocusPreset {
        var copy = preset
        copy.name = FocusPreset.normalizedName(preset.name) ?? preset.verb.rawValue.capitalized
        copy.minutes = DialLayout.stepped(preset.minutes, by: 0)
        return copy
    }

    private func change(_ edit: (inout [FocusPreset]) -> Void) {
        var copy = presets
        edit(&copy)
        guard copy != presets else { return }
        presets = copy
        save()
    }

    private func setLastUsed(_ id: UUID?) {
        guard id != lastUsedID else { return }
        lastUsedID = id
        save()
    }

    private func save() {
        guard isAvailable else { return }
        storage.save(PresetsFile(presets: presets, lastUsedID: lastUsedID))
    }
}
