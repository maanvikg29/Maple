import Foundation
import Synchronization

/// Where event stamps come from (F1 design §7.1). Injected, so tests and demos can move time.
public protocol FocusTimeSource: Sendable {
    func stamp() -> EventStamp
}

/// The real clocks: the wall clock, the continuous clock and this boot.
public struct LiveFocusTime: FocusTimeSource {
    /// This boot, hashed with the device id.
    public let boot: String

    /// - Parameter bootSession: `kern.bootsessionuuid`. When it can't be read, a random id stands in, so this launch's
    ///   credit can never be joined to another's.
    public init(deviceID: UUID, bootSession: String? = LiveFocusTime.bootSessionID()) {
        boot = Self.hashedBoot(bootSession ?? "unread-" + UUID().uuidString, deviceID: deviceID)
    }

    public func stamp() -> EventStamp {
        // CLOCK_MONOTONIC keeps counting while the phone sleeps (it is ContinuousClock's clock) and restarts at boot.
        EventStamp(wall: Date(), continuous: clock_gettime_nsec_np(CLOCK_MONOTONIC), boot: boot,
                   zone: TimeZone.current.identifier)
    }

    /// `kern.bootsessionuuid`, which changes at every restart; nil when it can't be read.
    public static func bootSessionID() -> String? {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let text = String(decoding: bytes, as: UTF8.self)
        return text.isEmpty ? nil : text
    }

    /// FNV-1a over the boot id and the device id: stable within a boot, never the same across installs.
    static func hashedBoot(_ boot: String, deviceID: UUID) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in (boot + "|" + deviceID.uuidString).utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

/// Clocks moved by hand, for tests and demo scenarios. The wall and continuous clocks advance together; `setWall`
/// changes only the wall clock, as the member can; `reboot` starts a new boot.
public final class ManualFocusTime: FocusTimeSource {
    private let state: Mutex<EventStamp>

    public init(wall: Date, zone: String = "UTC", boot: String = "b1", continuous: UInt64 = 1_000_000_000_000) {
        state = Mutex(EventStamp(wall: wall, continuous: continuous, boot: boot, zone: zone))
    }

    public func stamp() -> EventStamp {
        state.withLock { $0 }
    }

    public var now: Date { stamp().wall }

    public func advance(_ seconds: TimeInterval) {
        state.withLock { stamp in
            stamp.wall = stamp.wall.addingTimeInterval(seconds)
            stamp.continuous += UInt64((seconds * 1e9).rounded())
        }
    }

    public func setWall(_ date: Date) {
        state.withLock { $0.wall = date }
    }

    public func setZone(_ zone: String) {
        state.withLock { $0.zone = zone }
    }

    /// A restart: a new boot whose continuous clock starts small. The wall clock carries on unless `wall` is given.
    public func reboot(_ boot: String, wall: Date? = nil) {
        state.withLock { stamp in
            stamp.boot = boot
            stamp.continuous = 5_000_000_000
            if let wall { stamp.wall = wall }
        }
    }
}

/// The real clocks with the wall clock moved by `offset`: DEBUG demos that start inside a chosen phase and keep running.
public struct ShiftedFocusTime: FocusTimeSource {
    public let base: LiveFocusTime
    public let offset: TimeInterval

    public init(base: LiveFocusTime, offset: TimeInterval) {
        self.base = base
        self.offset = offset
    }

    public func stamp() -> EventStamp {
        var stamp = base.stamp()
        stamp.wall = stamp.wall.addingTimeInterval(offset)
        return stamp
    }
}
