import Foundation
import Testing
@testable import MapleCore

extension FocusFixtures {
    static func stamp(_ wall: Date, cont: UInt64 = 1_000_000_000_000, boot: String = "b1", zone: String = "UTC") -> EventStamp {
        EventStamp(wall: wall, continuous: cont, boot: boot, zone: zone)
    }

    static func event(
        _ kind: FocusEventKind, at stamp: EventStamp, seq: Int, session: UUID = FocusFixtures.session, writer: FocusWriter = .app,
        source: FocusSource = .live, id: String? = nil
    ) -> FocusEvent {
        FocusEvent(id: id ?? "e\(seq)-\(session.uuidString.prefix(4))", kind: kind, sessionID: session, deviceID: device,
                   writer: writer, seq: seq, source: source, stamp: stamp)
    }
}

@Suite("Focus events")
struct FocusEventTests {
    private func roundTrip(_ event: FocusEvent) throws -> FocusEvent {
        let data = try JSONEncoder().encode(event)
        return try JSONDecoder().decode(FocusEvent.self, from: data)
    }

    @Test("Every kind round-trips through JSON")
    func roundTrips() throws {
        let stamp = FocusFixtures.stamp(at(2026, 10, 23, 14))
        let kinds: [FocusEventKind] = [
            .shieldApplied, .shieldVerified, .shieldLost, .breakStarted(seconds: 300), .breakEnded,
            .overrideStarted(seconds: 60), .overrideEnded, .sessionEnded(.completed, verified: true),
            .sessionEnded(.emergencyRelease, verified: false), .shieldCleared(.releaseAll), .reflected(.partly),
            .sessionHidden,
        ]
        for (index, kind) in kinds.enumerated() {
            let event = FocusFixtures.event(kind, at: stamp, seq: index + 1)
            #expect(try roundTrip(event) == event)
        }
    }

    @Test("A kind this build doesn't know is kept as unknown, and keeps its credit flag")
    func unknownKind() throws {
        let line = """
        {"id":"x1","v":1,"type":"phoneBreakStarted","session":"00000000-0000-4000-8000-0000000000A1",\
        "device":"00000000-0000-4000-8000-0000000000D1","writer":"app","seq":7,"source":"live","credit":true,\
        "at":{"wall":1792764000,"cont":5,"boot":"b1","zone":"UTC"},"seconds":120}
        """
        let event = try JSONDecoder().decode(FocusEvent.self, from: Data(line.utf8))
        #expect(event.kind == .unknown("phoneBreakStarted"))
        #expect(event.affectsCredit)
        #expect(event.seq == 7)
        let again = try roundTrip(event)
        #expect(again.kind == .unknown("phoneBreakStarted"))
    }

    @Test("A known kind with a payload this build can't read becomes unknown instead of being lost")
    func unreadablePayload() throws {
        let line = """
        {"id":"x2","v":1,"type":"sessionEnded","session":"00000000-0000-4000-8000-0000000000A1",\
        "device":"00000000-0000-4000-8000-0000000000D1","writer":"monitor","seq":3,"source":"live",\
        "at":{"wall":1792764000,"cont":5,"boot":"b1","zone":"UTC"},"reason":"timedOut"}
        """
        let event = try JSONDecoder().decode(FocusEvent.self, from: Data(line.utf8))
        #expect(event.kind == .unknown("sessionEnded"))
        #expect(event.writer == .monitor)
        #expect(event.affectsCredit)
    }

    @Test("The stamp's wall time is seconds since 1970, and continuous time is in nanoseconds")
    func stampFormat() throws {
        let stamp = EventStamp(wall: Date(timeIntervalSince1970: 1_792_764_000), continuous: 42, boot: "b", zone: "Asia/Kolkata")
        let json = try #require(String(data: try JSONEncoder().encode(stamp), encoding: .utf8))
        #expect(json.contains("\"wall\":1792764000"))
        #expect(json.contains("\"cont\":42"))
        let later = EventStamp(wall: stamp.wall, continuous: 42 + 2_500_000_000, boot: "b", zone: "Asia/Kolkata")
        #expect(later.seconds(since: stamp) == 2.5)
        #expect(stamp.seconds(since: later) == -2.5)
    }

    @Test("Reflections and hiding never affect credit; everything else does")
    func creditFlags() {
        #expect(!FocusEventKind.reflected(.allDone).affectsCredit)
        #expect(!FocusEventKind.sessionHidden.affectsCredit)
        #expect(FocusEventKind.shieldVerified.affectsCredit)
        #expect(FocusEventKind.unknown("future").affectsCredit)
    }

    @Test("Checkpoints are the read-backs after the start; a verified end is one too")
    func checkpoints() {
        #expect(FocusEventKind.shieldVerified.isCheckpoint)
        #expect(FocusEventKind.breakStarted(seconds: 300).isCheckpoint)
        #expect(FocusEventKind.breakEnded.isCheckpoint)
        #expect(FocusEventKind.overrideEnded.isCheckpoint)
        #expect(FocusEventKind.shieldApplied.isCheckpoint)
        #expect(FocusEventKind.sessionEnded(.completed, verified: true).isCheckpoint)
        #expect(!FocusEventKind.sessionEnded(.completed, verified: false).isCheckpoint)
        #expect(!FocusEventKind.overrideStarted(seconds: 60).isCheckpoint)
        #expect(!FocusEventKind.shieldLost.isCheckpoint)
        #expect(FocusEventKind.sessionEnded(.endedEarly, verified: false).isTerminal)
    }

    @Test("Derived ids are the same for any process that derives them")
    func derivedIDs() {
        let a = FocusEvent.derivedID(session: FocusFixtures.session, kind: .sessionEnded(.completed, verified: true))
        let b = FocusEvent.derivedID(session: FocusFixtures.session, kind: .sessionEnded(.completed, verified: false))
        #expect(a == b)
        #expect(a == "00000000-0000-4000-8000-0000000000a1.sessionEnded")
    }

    @Test("Writers sort app, monitor, shield action")
    func writerOrder() {
        #expect(FocusWriter.allCases.sorted() == [.app, .monitor, .shieldAction])
    }
}
