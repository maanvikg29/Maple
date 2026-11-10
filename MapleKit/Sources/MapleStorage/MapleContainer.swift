import Foundation

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
