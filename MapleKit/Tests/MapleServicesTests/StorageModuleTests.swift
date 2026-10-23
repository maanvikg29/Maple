import Foundation
import Testing
@testable import MapleServices

@Suite("Storage module")
struct StorageModuleTests {
    @Test("MapleServices re-exports MapleStorage's container")
    func container() {
        #expect(MapleContainer.directory().lastPathComponent == "Maple")
        #expect(!MapleContainer.appGroupIdentifier.isEmpty)
    }
}
