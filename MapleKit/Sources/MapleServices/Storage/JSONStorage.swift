import Foundation
import os

/// Where Maple keeps its files: the App Group container (shared with future extensions and widgets), or
/// Application Support when the group isn't available.
nonisolated public enum MapleContainer {
    public static let appGroupIdentifier = "group.com.maanvikgupta.maple"

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
///   moved back (installs that met the old read-error path still have their real collection beside it).
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
            isUnavailable = false
            if let restored = restoreSetAside(url) { return .value(restored) }
            return .absent
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

    /// The newest `<name>.damaged-<time>.<ext>` beside `url` that decodes cleanly, moved back to `url`.
    private func restoreSetAside(_ url: URL) -> Value? {
        let folder = url.deletingLastPathComponent()
        let prefix = url.deletingPathExtension().lastPathComponent + ".damaged-"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        let candidates = names
            .filter { $0.hasPrefix(prefix) && $0.hasSuffix("." + url.pathExtension) }
            .compactMap { name -> (stamp: Int, name: String)? in
                let stamp = name.dropFirst(prefix.count).prefix { $0.isNumber }
                return Int(stamp).map { ($0, name) }
            }
            .sorted { $0.stamp > $1.stamp }
        for candidate in candidates {
            let copy = folder.appending(path: candidate.name)
            guard let data = try? Data(contentsOf: copy), let value = try? JSONDecoder().decode(Value.self, from: data) else {
                continue
            }
            do {
                try FileManager.default.moveItem(at: copy, to: url)
                Self.logger.notice("Restored \(url.lastPathComponent, privacy: .public) from \(candidate.name, privacy: .public)")
            } catch {
                Self.logger.error("Couldn't restore \(candidate.name, privacy: .public): \(String(describing: error), privacy: .public)")
            }
            return value
        }
        return nil
    }
}
