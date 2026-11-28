import Testing
@testable import MapleCore

@Suite("The syrup van's switch")
struct VanFeatureTests {
    @Test("The app ships with the van; a set of releases alone leaves it off, so older screens can still be opened")
    func shipped() {
        #expect(ShippedFeatures.current.syrupVan)
        #expect(ShippedFeatures.all.syrupVan)
        #expect(!ShippedFeatures(releases: [.m1, .f1]).syrupVan)
        #expect(ShippedFeatures.current.releases == [.m1, .f1])
        #expect(ShippedFeatures.current != ShippedFeatures(releases: [.m1, .f1]))
    }
}
