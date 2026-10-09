import Foundation

/// Every collectible maple species, loaded once from the bundled `species.json`.
public final class LeafCatalog: Sendable {
    public static let shared = LeafCatalog()

    /// All species in catalogue order (alphabetical by scientific name).
    public let species: [LeafSpecies]
    private let byID: [String: LeafSpecies]

    public init(species: [LeafSpecies]) {
        self.species = species
        self.byID = Dictionary(uniqueKeysWithValues: species.map { ($0.id, $0) })
    }

    private convenience init() {
        guard let url = Bundle.module.url(forResource: "species", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let species = try? JSONDecoder().decode([LeafSpecies].self, from: data) else {
            preconditionFailure("species.json is missing or malformed; it ships inside MapleCore.")
        }
        self.init(species: species)
    }

    public func species(id: String) -> LeafSpecies? {
        byID[id]
    }
}
