import Foundation
import Testing
@testable import MapleCore
@testable import MapleServices

@Suite("Launch modes")
@MainActor
struct LaunchModeTests {
    #if DEBUG
    @Test("Each mode credits its own sources and blocks with the right service")
    func modes() {
        #expect(LaunchMode.live.credited == [.live])
        #expect(LaunchMode.demo.credited == [.live, .preview])
        #expect(LaunchMode.sandbox.credited == [.live, .preview])
        #expect(!LaunchMode.live.usesPreview && LaunchMode.demo.usesPreview && LaunchMode.sandbox.usesPreview)
    }

    @Test("Sandbox arguments are demo arguments")
    func arguments() {
        let options = DemoLaunchOptions(arguments: ["Maple", "-MapleDemoSandbox", "YES", "-MapleDemoSessionSeconds", "90"])
        #expect(options.sandbox)
        #expect(options.sessionSeconds == 90)
        #expect(options.isActive)
        #expect(!DemoLaunchOptions(arguments: ["Maple"]).sandbox)
    }
    #endif

    @Test("A live launch keeps its ledger in the container and can't block on a free build")
    func live() throws {
        let folder = try temporaryDirectory()
        let stores = MapleStores.live(directory: folder, calendar: utc, now: at(2026, 10, 23, 9), healthAuthorizer: FakeHealthAuthorizer())
        #expect(stores.focus.mode == .live)
        #expect(stores.focus.sessions.blocking.capability == .unavailableInBuild)
        #expect(files(in: folder).contains(DeviceIdentity.file))
    }

    @Test("The foreground reload reads the Focus files a locked launch couldn't")
    func reloadsFocusStores() throws {
        let folder = try temporaryDirectory()
        let essay = FocusPreset(name: "Essay", verb: .focus, minutes: 40, hasBreak: false, appSetID: nil)
        let summary = SelectionSummary(mode: .blockThese, apps: 6, sites: 0, categories: 0)
        let session = UUID()
        let presets = folder.appending(path: PresetStore.file)
        let appSets = folder.appending(path: AppSetStore.file)
        let notes = folder.appending(path: SessionNotesStore.file)
        JSONStorage(.file(presets)).save(PresetsFile(presets: [essay], lastUsedID: essay.id))
        JSONStorage(.file(appSets)).save(AppSetsFile(sets: [AppSet(id: AppSet.distractionsID, name: "Distractions", summary: summary)]))
        JSONStorage(.file(notes)).save(SessionNotesFile(notes: [session.uuidString.lowercased(): SessionNote(text: "Chemistry", at: at(2026, 10, 22, 9))]))
        let files = [presets, appSets, notes]
        func setPermissions(_ mode: Int) throws {
            for file in files { try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: file.path) }
        }

        try setPermissions(0o000)
        defer { try? setPermissions(0o644) }
        let stores = MapleStores.live(directory: folder, calendar: utc, now: at(2026, 10, 23, 9), healthAuthorizer: FakeHealthAuthorizer())
        #expect(!stores.focus.presets.isAvailable && !stores.focus.appSets.isAvailable && !stores.focus.notes.isAvailable)
        #expect(!stores.reloadIfUnavailable(), "still locked: nothing to report")

        try setPermissions(0o644)
        #expect(stores.reloadIfUnavailable())
        #expect(stores.focus.presets.isAvailable && stores.focus.appSets.isAvailable && stores.focus.notes.isAvailable)
        #expect(stores.focus.presets.presets.map(\.name) == ["Essay"])
        #expect(stores.focus.presets.lastUsedID == essay.id)
        #expect(stores.focus.appSets.set(id: AppSet.distractionsID)?.summary == summary)
        #expect(stores.focus.notes.intention(for: session) == "Chemistry")
        #expect(!stores.reloadIfUnavailable(), "everything is read: nothing more to report")
    }

    #if DEBUG
    @Test("A demo launch runs a session in memory and writes nothing to the live files")
    func demo() async throws {
        let folder = try temporaryDirectory()
        let stores = MapleStores.make(DemoLaunchOptions(arguments: ["-MapleDemoSpecies", "10"]), directory: folder, calendar: utc,
                                      now: at(2026, 10, 23, 9))
        #expect(stores.focus.mode == .demo)
        #expect(stores.focus.sessions.blocking.capability == .preview)
        let preset = try #require(stores.focus.presets.lastUsed)
        let outcome = await stores.focus.sessions.start(.init(preset: preset, minutes: 25,
                                                              appSet: stores.focus.appSets.set(id: AppSet.distractionsID), from: .focusTab))
        #expect(stores.focus.sessions.running != nil, "\(outcome)")
        #expect(files(in: folder).isEmpty)
    }

    @Test("The sandbox is a complete parallel container, with short sessions when asked")
    func sandbox() async throws {
        let folder = try temporaryDirectory()
        let stores = MapleStores.live(directory: folder.appending(path: MapleStores.sandboxFolder), calendar: utc, now: at(2026, 10, 23, 9),
                                      healthAuthorizer: FakeHealthAuthorizer(), focusMode: .sandbox, sessionSeconds: 90)
        #expect(stores.focus.mode == .sandbox)
        #expect(stores.focus.sessions.blocking.capability == .preview)
        let preset = try #require(stores.focus.presets.lastUsed)
        _ = await stores.focus.sessions.start(.init(preset: preset, minutes: 50, appSet: stores.focus.appSets.set(id: AppSet.distractionsID),
                                                    from: .focusTab))
        #expect(stores.focus.sessions.running?.plan.plannedSeconds == 90)
        #expect(files(in: folder) == [MapleStores.sandboxFolder])
        #expect(files(in: folder.appending(path: MapleStores.sandboxFolder)).contains(FocusStores.ledgerFolder))
    }
    #endif
}
