import Foundation

/// What reading a JSON-lines file found.
public enum LinesRead<Value> {
    /// The lines that decoded, in file order, and how many didn't.
    case lines([Value], damaged: Int)
    /// The file is there but can't be read now (before the first unlock after a restart).
    case unavailable
}

/// One append-only file of JSON lines (F1 design §7.3). Appends never rewrite earlier lines, and reading skips lines
/// that don't decode (a torn tail after a crash) instead of setting the file aside.
public struct JSONLinesFile: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Appends `value` as one line, protected until first unlock. If the file doesn't end in a newline (a torn
    /// append), this line starts on a fresh one so it still decodes.
    public func append<Value: Encodable>(_ value: Value) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var line = try encoder.encode(value)
        line.append(0x0A)
        let manager = FileManager.default
        if !manager.fileExists(atPath: url.path) {
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            #if os(iOS)
            let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            #else
            let attributes: [FileAttributeKey: Any] = [:]
            #endif
            guard manager.createFile(atPath: url.path, contents: nil, attributes: attributes) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
            }
        }
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        if end > 0 {
            try handle.seek(toOffset: end - 1)
            if try handle.read(upToCount: 1) != Data([0x0A]) { line.insert(0x0A, at: line.startIndex) }
            try handle.seekToEnd()
        }
        try handle.write(contentsOf: line)
    }

    /// Every line that decodes as `Value`, in order. A missing file is empty.
    public func read<Value: Decodable>(_ type: Value.Type) -> LinesRead<Value> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .lines([], damaged: 0) }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .unavailable
        }
        let decoder = JSONDecoder()
        var values: [Value] = []
        var damaged = 0
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if let value = try? decoder.decode(Value.self, from: Data(line)) {
                values.append(value)
            } else {
                damaged += 1
            }
        }
        return .lines(values, damaged: damaged)
    }

    /// The last line that decodes, or nil.
    public func last<Value: Decodable>(_ type: Value.Type) -> Value? {
        guard case .lines(let values, _) = read(type) else { return nil }
        return values.last
    }
}
