#if DEBUG
import Testing
@testable import MapleCore
@testable import MapleServices

@Suite("The van in demo launches")
struct VanDemoOptionsTests {
    @Test("-MapleDemoShip f1 opens the app as it was before the van, and van opens it with the van")
    func ship() {
        #expect(DemoLaunchOptions(arguments: ["-MapleDemoShip", "f1"]).ship == ShippedFeatures(releases: [.m1, .f1]))
        #expect(DemoLaunchOptions(arguments: ["-MapleDemoShip", "van"]).ship == ShippedFeatures(releases: [.m1, .f1], syrupVan: true))
        #expect(DemoLaunchOptions(arguments: []).ship == nil)
    }
}
#endif
