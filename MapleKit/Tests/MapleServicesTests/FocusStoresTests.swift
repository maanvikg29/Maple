import Foundation
import Testing
@testable import MapleCore
@testable import MapleServices

@Suite("Focus stores")
@MainActor
struct FocusStoresTests {
    private func url(_ name: String) throws -> URL {
        try temporaryDirectory().appendingPathComponent(name)
    }

    @Test("Presets start with the four defaults on Distractions, and changes are saved")
    func presets() throws {
        let file = try url(PresetStore.file)
        let store = PresetStore(storage: JSONStorage(.file(file)), defaultAppSetID: AppSet.distractionsID)
        #expect(store.presets.map(\.name) == ["Study", "Quick", "Deep", "Read"])
        #expect(store.presets.allSatisfy { $0.appSetID == AppSet.distractionsID })
        #expect(store.lastUsed?.name == "Study")
        let deep = try #require(store.presets.first { $0.name == "Deep" })
        store.markUsed(deep.id)
        var renamed = deep
        renamed.name = "   Deep work, the long kind of session   "
        renamed.minutes = 999
        store.update(renamed)
        let reloaded = PresetStore(storage: JSONStorage(.file(file)), defaultAppSetID: nil)
        #expect(reloaded.lastUsed?.id == deep.id)
        #expect(reloaded.lastUsed?.name == "Deep work, the long kind")
        #expect(reloaded.lastUsed?.minutes == 180)
    }

    @Test("At most 6 presets, and the last one can't be deleted")
    func presetLimits() {
        let store = PresetStore(storage: JSONStorage(.memory), defaultAppSetID: nil)
        #expect(store.add(FocusPreset(name: "Essay", verb: .focus, minutes: 40, hasBreak: false, appSetID: nil)))
        #expect(store.add(FocusPreset(name: "Revision", verb: .study, minutes: 60, hasBreak: true, appSetID: nil)))
        #expect(!store.canAdd)
        #expect(!store.add(FocusPreset(name: "Seventh", verb: .focus, minutes: 30, hasBreak: false, appSetID: nil)))
        for preset in store.presets.dropLast() { #expect(store.delete(id: preset.id)) }
        #expect(store.presets.count == 1)
        #expect(!store.delete(id: store.presets[0].id))
        #expect(store.lastUsed?.id == store.presets[0].id)
    }

    @Test("A damaged preset is skipped; an unreadable file is never written over")
    func presetFiles() throws {
        let file = try url(PresetStore.file)
        let good = FocusPreset(name: "Read", verb: .reading, minutes: 30, hasBreak: false, appSetID: nil)
        let json = #"{"presets":[{"name":"broken"},"# + String(decoding: try JSONEncoder().encode(good), as: UTF8.self) + "]}"
        try Data(json.utf8).write(to: file)
        #expect(PresetStore(storage: JSONStorage(.file(file)), defaultAppSetID: nil).presets.map(\.name) == ["Read"])

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
        let locked = PresetStore(storage: JSONStorage(.file(file)), defaultAppSetID: nil)
        #expect(!locked.isAvailable)
        locked.markUsed(locked.presets[0].id)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        #expect(try String(contentsOf: file, encoding: .utf8) == json)
    }

    @Test("A preset file that read with losses is copied aside before a save replaces it; a clean one is not")
    func presetsKeepOriginal() throws {
        func copies(of json: String) throws -> (kept: [String], directory: URL) {
            let directory = try temporaryDirectory()
            let file = directory.appendingPathComponent(PresetStore.file)
            try Data(json.utf8).write(to: file)
            let store = PresetStore(storage: JSONStorage(.file(file)), defaultAppSetID: nil)
            store.markUsed(store.presets[0].id)
            return (files(in: directory).filter { $0.hasPrefix("presets.damaged-") }, directory)
        }
        func preset(_ name: String) throws -> String {
            let preset = FocusPreset(name: name, verb: .focus, minutes: 30, hasBreak: false, appSetID: nil)
            return String(decoding: try JSONEncoder().encode(preset), as: UTF8.self)
        }
        func list(_ items: [String]) -> String {
            #"{"presets":["# + items.joined(separator: ",") + "]}"
        }

        let damaged = list([#"{"name":"broken"}"#, try preset("Read")])
        let (kept, directory) = try copies(of: damaged)
        #expect(kept.count == 1)
        let copy = try #require(kept.first)
        #expect(try String(contentsOf: directory.appendingPathComponent(copy), encoding: .utf8) == damaged)
        #expect(try String(contentsOf: directory.appendingPathComponent(PresetStore.file), encoding: .utf8) != damaged)

        let notAList = try copies(of: #"{"presets":"gone"}"#)
        #expect(notAList.kept.count == 1)

        let seven = try copies(of: list(try ["A", "B", "C", "D", "E", "F", "G"].map(preset)))
        #expect(seven.kept.count == 1)

        #expect(try copies(of: list(try ["A", "B", "C", "D", "E", "F"].map(preset))).kept.isEmpty)
        #expect(try copies(of: #"{"presets":[]}"#).kept.isEmpty)
    }

    @Test("App sets: three starters; an empty selection never replaces a full one; 50 tokens across every set")
    func appSets() throws {
        let store = AppSetStore(storage: JSONStorage(.memory))
        #expect(store.sets.map(\.name) == ["Distractions", "Study apps", "Bedtime"])
        #expect(store.set(id: AppSet.distractionsID)?.summary.isEmpty == true)
        let six = SelectionSummary(mode: .blockThese, apps: 6, sites: 1, categories: 0)
        #expect(store.save(selection: Data("six".utf8), summary: six, to: AppSet.distractionsID) == .saved)
        #expect(store.set(id: AppSet.distractionsID)?.summary == six)
        let empty = SelectionSummary(mode: .blockThese, apps: 0, sites: 0, categories: 0)
        #expect(store.save(selection: Data(), summary: empty, to: AppSet.distractionsID) == .wouldEmpty)
        #expect(store.set(id: AppSet.distractionsID)?.summary == six)
        let study = try #require(store.sets.first { $0.name == "Study apps" })
        let big = SelectionSummary(mode: .blockThese, apps: 45, sites: 0, categories: 0)
        #expect(store.save(selection: Data("big".utf8), summary: big, to: study.id) == .overTokenLimit)
        #expect(store.totalTokens == 6)                                         // 6 apps; 1 site counts separately
        #expect(store.save(selection: Data("x".utf8), summary: six, to: UUID()) == .unknownSet)
        store.markExpired(AppSet.distractionsID, true)
        #expect(store.set(id: AppSet.distractionsID)?.tokensExpired == true)
        #expect(store.save(selection: Data("six".utf8), summary: six, to: AppSet.distractionsID) == .saved)
        #expect(store.set(id: AppSet.distractionsID)?.tokensExpired == false)
    }

    @Test("Session notes: one intention per session, cleared by an empty field, erased on request, newest 200 kept")
    func notes() throws {
        let file = try url(SessionNotesStore.file)
        let store = SessionNotesStore(storage: JSONStorage(.file(file)))
        let a = UUID(), b = UUID()
        store.setIntention("  Chemistry ch. 4 ", for: a, at: at(2026, 10, 23, 14))
        store.setIntention("Essay", for: b, at: at(2026, 10, 23, 16))
        #expect(SessionNotesStore(storage: JSONStorage(.file(file))).intention(for: a) == "Chemistry ch. 4")
        store.setIntention("   ", for: b, at: at(2026, 10, 23, 16, 5))
        #expect(store.intention(for: b) == nil)
        #expect(store.entries(reflections: [a: .partly]) == [RecentIntentions.Entry(text: "Chemistry ch. 4", reflection: .partly, at: at(2026, 10, 23, 14))])
        for index in 0..<210 { store.setIntention("Note \(index)", for: UUID(), at: at(2026, 10, 1).addingTimeInterval(Double(index))) }
        #expect(store.entries(reflections: [:]).count == SessionNotesStore.kept)
        #expect(store.intention(for: a) == "Chemistry ch. 4")
        store.eraseAll()
        #expect(SessionNotesStore(storage: JSONStorage(.file(file))).entries(reflections: [:]).isEmpty)
    }
}
