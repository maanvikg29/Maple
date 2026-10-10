import Foundation
import os

/// Where Maple keeps its files: the App Group container (shared with future extensions and widgets), or
/// Application Support when the group isn't available.
nonisolated public enum MapleContainer {
    /// The app's `MapleAppGroup` Info.plist key, filled from the `MAPLE_APP_GROUP` build setting so each developer's
    /// Signing.local.xcconfig can use their own group; Maple's own group where the key is missing (tests, previews).
    public static let appGroupIdentifier: String = {
        let configured = Bundle.main.object(forInfoDictionaryKey: "MapleAppGroup") as? String
        if let configured, !configured.isEmpty, !configured.hasPrefix("$(") { return configured }
        return "group.com.maanvikgupta.maple"
    }()

    public static func directory(fileManager: FileManager = .default) -> URL {
        if let group = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return group.appending(path: "Maple", directoryHint: .isDirectory)
        }
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return support.appending(path: "Maple", directoryHint: .isDirectory)
    }
}

/// Where a store's value lives.
nonisolated public enum StorageLocation: Sendable, Equatable {
    /// A JSON file, written atomically and protected until first unlock (extensions read it while locked).
    case file(URL)
    /// Memory only: DEBUG demos and tests. Nothing touches the disk.
    case memory
}

/// What reading a store's file found.
public enum StorageRead<Value> {
    case value(Value)
    /// There is no file: a first run. A store may create and save its default.
    case absent
    /// The file is there but can't be read now: before the first unlock after a restart (the app can be prewarmed
    /// then), or any other I/O error. Nothing may be saved over it; read again later.
    case unavailable
}

/// Loads and saves one Codable value as JSON. Small values, written synchronously on every change.
///
/// - A file that reads but can't be decoded is moved aside as `<name>.damaged-<time>.json` and never overwritten,
///   so a bug can't silently erase a member's collection.
/// - A file that can't be *read* (protected data unavailable, a permission error) is left exactly where it is, and
///   every save is refused until a read succeeds again, so a launch before the first unlock can't replace it.
/// - When the file is missing but an earlier launch set aside a copy that decodes cleanly, the newest such copy is
///   moved back (installs that met the old read-error path still have their real collection beside it). When a newer
///   copy can't be read yet, the read is `.unavailable`, never `.absent`, so no empty file is created in its place.
public final class JSONStorage<Value: Codable> {
    public let location: StorageLocation
    private var memory: Value?
    /// The last read found the file unreadable; saves are refused until a read works.
    public private(set) var isUnavailable = false
    private static var logger: Logger { Logger(subsystem: "com.maanvikgupta.maple", category: "storage") }

    /// - Parameter initial: The value a memory location starts with (ignored for files).
    public init(_ location: StorageLocation, initial: Value? = nil) {
        self.location = location
        memory = initial
    }

    /// Reads the value, telling a missing file apart from one that can't be read now.
    public func read() -> StorageRead<Value> {
        guard case .file(let url) = location else { return memory.map { .value($0) } ?? .absent }
        guard FileManager.default.fileExists(atPath: url.path) else {
            switch restoreSetAside(url) {
            case .restored(let value):
                isUnavailable = false
                return .value(value)
            case .unreadable:
                // A set-aside copy may be the member's real file: nothing is created in its place until it reads.
                isUnavailable = true
                return .unavailable
            case .none:
                isUnavailable = false
                return .absent
            }
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            isUnavailable = true
            Self.logger.error("Couldn't read \(url.lastPathComponent, privacy: .public) yet: \(String(describing: error), privacy: .public)")
            return .unavailable
        }
        isUnavailable = false
        do {
            return .value(try JSONDecoder().decode(Value.self, from: data))
        } catch {
            Self.logger.error("Couldn't decode \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            setAside(url)
            return .absent
        }
    }

    /// The saved value; nil when there is none or it can't be read now (`read()` tells them apart).
    public func load() -> Value? {
        if case .value(let value) = read() { return value }
        return nil
    }

    public func save(_ value: Value) {
        guard case .file(let url) = location else {
            memory = value
            return
        }
        guard !isUnavailable else {
            Self.logger.error("Not saving \(url.lastPathComponent, privacy: .public): the file couldn't be read")
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(value)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: url, options: [.atomic])
            #endif
        } catch {
            Self.logger.error("Couldn't save \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func setAside(_ url: URL) {
        let stamp = Int(Date().timeIntervalSince1970)
        let name = url.deletingPathExtension().lastPathComponent + ".damaged-\(stamp)." + url.pathExtension
        try? FileManager.default.moveItem(at: url, to: url.deletingLastPathComponent().appending(path: name))
    }

    /// What looking for a set-aside copy found.
    private enum Restore {
        case restored(Value)
        /// No copy decodes, or there is none: a first run.
        case none
        /// A copy newer than any that decodes can't be read yet (protected data before the first unlock, or a
        /// permission error), so it may be the member's real file.
        case unreadable
    }

    /// The newest `<name>.damaged-<time>.<ext>` beside `url` that decodes cleanly, moved back to `url`. A newer copy
    /// that can't be read yet stops the search (`.unreadable`), so a launch before the first unlock never takes the
    /// missing file for a first run; copies that read but don't decode, or fail to read any other way, are skipped.
    private func restoreSetAside(_ url: URL) -> Restore {
        let folder = url.deletingLastPathComponent()
        let prefix = url.deletingPathExtension().lastPathComponent + ".damaged-"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return .none }
        let candidates = names
            .filter { $0.hasPrefix(prefix) && $0.hasSuffix("." + url.pathExtension) }
            .compactMap { name -> (stamp: Int, name: String)? in
                let stamp = name.dropFirst(prefix.count).prefix { $0.isNumber }
                return Int(stamp).map { ($0, name) }
            }
            .sorted { $0.stamp > $1.stamp }
        for candidate in candidates {
            let copy = folder.appending(path: candidate.name)
            let data: Data
            do {
                data = try Data(contentsOf: copy)
            } catch {
                guard Self.isLockedOut(error) else { continue }
                Self.logger.error("Couldn't read \(candidate.name, privacy: .public) yet: \(String(describing: error), privacy: .public)")
                return .unreadable
            }
            guard let value = try? JSONDecoder().decode(Value.self, from: data) else { continue }
            do {
                try FileManager.default.moveItem(at: copy, to: url)
                Self.logger.notice("Restored \(url.lastPathComponent, privacy: .public) from \(candidate.name, privacy: .public)")
            } catch {
                Self.logger.error("Couldn't restore \(candidate.name, privacy: .public): \(String(describing: error), privacy: .public)")
            }
            return .restored(value)
        }
        return .none
    }

    /// A read refused for protection or permissions (`NSFileReadNoPermissionError`, POSIX `EPERM` or `EACCES`): the
    /// file is there but can't be read now. Any other error means the copy is unusable.
    static func isLockedOut(_ error: any Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoPermissionError { return true }
        if error.domain == NSPOSIXErrorDomain, error.code == Int(EPERM) || error.code == Int(EACCES) { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { return isLockedOut(underlying) }
        return false
    }
}
