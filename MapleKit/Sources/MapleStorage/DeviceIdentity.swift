import Foundation

/// This install's device id: a random UUID made once and kept in the container (F1 design §7.8). It never leaves the
/// device in F1 and isn't derived from anything about the phone.
public enum DeviceIdentity {
    public static let file = "device-id.txt"

    /// The kept id, made and saved on first use. Nil when the file is there but can't be read yet.
    public static func load(in directory: URL) -> UUID? {
        let url = directory.appending(path: file)
        if FileManager.default.fileExists(atPath: url.path) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            if let id = UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines)) { return id }
        }
        let id = UUID()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            #if os(iOS)
            try Data(id.uuidString.utf8).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try Data(id.uuidString.utf8).write(to: url, options: [.atomic])
            #endif
        } catch {
            return nil
        }
        return id
    }
}
