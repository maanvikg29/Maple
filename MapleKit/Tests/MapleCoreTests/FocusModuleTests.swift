import Testing
@testable import MapleCore

@Suite("Focus module")
struct FocusModuleTests {
    @Test("MapleCore re-exports MapleFocusCore")
    func reexport() {
        #expect(FocusRules.schemaVersion == 1)
        #expect(FocusRules.version == 1)
    }
}
