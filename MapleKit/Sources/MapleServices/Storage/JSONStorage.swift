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

/// Loads and saves one Codable value as JSON. Small values, written synchronously on every change.
///
/// A file that can't be decoded is moved aside as `<name>.damaged-<time>.json` and never overwritten, so a bug
/// can't silently erase a member's collection.
public final class JSONStorage<Value: Codable> {
    public let location: StorageLocation
    private var memory: Value?
    private static var logger: Logger { Logger(subsystem: "com.maanvikgupta.maple", category: "storage") }

    /// - Parameter initial: The value a memory location starts with (ignored for files).
    public init(_ location: StorageLocation, initial: Value? = nil) {
        self.location = location
        memory = initial
    }

    public func load() -> Value? {
        guard case .file(let url) = location else { return memory }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            Self.logger.error("Couldn't read \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            setAside(url)
            return nil
        }
    }

    public func save(_ value: Value) {
        guard case .file(let url) = location else {
            memory = value
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
}
