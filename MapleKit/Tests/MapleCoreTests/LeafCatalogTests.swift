import Foundation
import Testing
@testable import MapleCore

@Suite("Leaf catalogue")
struct LeafCatalogTests {
    private let catalog = LeafCatalog.shared

    @Test("All 155 species load with unique ids")
    func loadsEverySpecies() {
        #expect(catalog.species.count == 155)
        #expect(Set(catalog.species.map(\.id)).count == 155)
    }

    @Test("Field values decode into typed enums")
    func decodesJapaneseMaple() throws {
        let palmatum = try #require(catalog.species(id: "palmatum"))
        #expect(palmatum.name == "Acer palmatum")
        #expect(palmatum.common == "Japanese maple")
        #expect(palmatum.displayName == "Japanese maple")
        #expect(palmatum.form == .palmate)
        #expect(palmatum.lobes == 7)
        #expect(palmatum.depth == 0.75)
        #expect(palmatum.margin == .doubleToothed)
        #expect(palmatum.regions == [.eastAsia])
        #expect(palmatum.confidence == .documented)
        #expect(!palmatum.evergreen)
    }

    @Test("Species without an English name fall back to the scientific name")
    func displayNameFallback() throws {
        let acuminatum = try #require(catalog.species(id: "acuminatum"))
        #expect(acuminatum.common.isEmpty)
        #expect(acuminatum.displayName == "Acer acuminatum")
    }

    @Test("Catalogue composition matches the supplied handoff")
    func composition() {
        let forms = Dictionary(grouping: catalog.species, by: \.form).mapValues(\.count)
        #expect(forms == [.palmate: 117, .unlobed: 29, .trifoliate: 7, .pinnate: 1, .palmcompound: 1])
        #expect(catalog.species.filter(\.evergreen).count == 24)
        let confidence = Dictionary(grouping: catalog.species, by: \.confidence).mapValues(\.count)
        #expect(confidence == [.documented: 89, .inferred: 55, .placeholder: 11])
        #expect(catalog.species.filter { $0.confidence.isApproximate }.count == 66)
    }

    @Test("Autumn colour codes map to the handoff's hex values")
    func autumnColours() {
        #expect(LeafSpecies.AutumnColor.crimson.color == LeafColor(0xB3312B))
        #expect(LeafSpecies.AutumnColor.scarlet.color == LeafColor(0xD2462A))
        #expect(LeafSpecies.AutumnColor.orange.color == LeafColor(0xD9782B))
        #expect(LeafSpecies.AutumnColor.gold.color == LeafColor(0xD1A020))
        #expect(LeafSpecies.AutumnColor.staysGreen.color == LeafColor(0x3F6D3B))
    }

    // Expected values read from the supplied SVG exports (Catalog/svg).
    @Test("Summer green matches the original generator", arguments: [
        ("rubrum", 0x3A8F3E), ("palmatum", 0x508235), ("saccharum", 0x347730),
        ("negundo", 0x477630), ("griseum", 0x2D6E2D),
    ] as [(String, UInt32)])
    func summerGreen(id: String, expected: UInt32) throws {
        let species = try #require(catalog.species(id: id))
        let actual = species.summerColor
        #expect(actual.isClose(to: LeafColor(expected), tolerance: 1), "\(id): got \(String(actual.rgb, radix: 16))")
    }

    @Test("Each leaf's resting tilt matches the original generator", arguments: [
        ("rubrum", 5.6), ("palmatum", 0.5), ("saccharum", -1.7), ("negundo", -4.3), ("griseum", -7.3),
    ])
    func restingTilt(id: String, degrees: Double) throws {
        let species = try #require(catalog.species(id: id))
        #expect(abs(species.restingTiltDegrees - degrees) < 0.051)
    }

    @Test("Vein colour is the fill at 55% brightness")
    func veinColour() {
        #expect(LeafColor(0xD2462A).veinColor == LeafColor(0x732617))
        #expect(LeafColor(0xD9782B).veinColor == LeafColor(0x774217))
    }
}
