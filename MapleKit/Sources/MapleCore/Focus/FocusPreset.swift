import Foundation
import MapleFocusCore

/// A Focus preset (F1 design §5.13): a named length, verb, optional locked break, app set and strictness.
public struct FocusPreset: Codable, Sendable, Equatable, Identifiable {
    public static let nameLimit = 24
    public static let maximumCount = 6
    /// One 5-minute locked break inside the planned length (§5.5).
    public static let breakSeconds = 5 * 60

    public var id: UUID
    public var name: String
    public var verb: FocusVerb
    public var minutes: Int
    public var hasBreak: Bool
    public var appSetID: UUID?
    public var strictness: Strictness
    /// A looser strictness waiting for the next day ("Steady starts tomorrow").
    public var pendingStrictness: Strictness?
    public var pendingFrom: LocalDay?

    public init(
        id: UUID = UUID(), name: String, verb: FocusVerb, minutes: Int, hasBreak: Bool, appSetID: UUID?,
        strictness: Strictness = .steady, pendingStrictness: Strictness? = nil, pendingFrom: LocalDay? = nil
    ) {
        self.id = id
        self.name = name
        self.verb = verb
        self.minutes = minutes
        self.hasBreak = hasBreak
        self.appSetID = appSetID
        self.strictness = strictness
        self.pendingStrictness = pendingStrictness
        self.pendingFrom = pendingFrom
    }

    /// Study 50m and Deep 90m with a break, Quick 25m and Read 30m without.
    public static func defaults(appSetID: UUID?) -> [FocusPreset] {
        [
            FocusPreset(name: "Study", verb: .study, minutes: 50, hasBreak: true, appSetID: appSetID),
            FocusPreset(name: "Quick", verb: .quick, minutes: 25, hasBreak: false, appSetID: appSetID),
            FocusPreset(name: "Deep", verb: .deep, minutes: 90, hasBreak: true, appSetID: appSetID),
            FocusPreset(name: "Read", verb: .reading, minutes: 30, hasBreak: false, appSetID: appSetID),
        ]
    }

    /// The strictness a session started on `day` uses.
    public func strictness(on day: LocalDay) -> Strictness {
        if let pendingStrictness, let pendingFrom, day >= pendingFrom { return pendingStrictness }
        return strictness
    }

    /// A tighter level applies at once; a looser one from the next day.
    public mutating func changeStrictness(to new: Strictness, on day: LocalDay, calendar: Calendar) {
        let current = strictness(on: day)
        strictness = current
        if new >= current {
            strictness = new
            pendingStrictness = nil
            pendingFrom = nil
        } else {
            pendingStrictness = new
            pendingFrom = day.adding(days: 1, calendar: calendar)
        }
    }

    /// Trimmed and kept to 24 characters; nil when empty.
    public static func normalizedName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(nameLimit))
    }

    // MARK: Codable (a length outside the range is brought into it)

    private enum CodingKeys: String, CodingKey {
        case id, name, verb, minutes, hasBreak, appSetID, strictness, pendingStrictness, pendingFrom
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        verb = (try? c.decode(FocusVerb.self, forKey: .verb)) ?? .focus
        let minutes = (try? c.decode(Int.self, forKey: .minutes)) ?? 50
        self.minutes = min(DialLayout.maximumMinutes, max(DialLayout.minimumMinutes, minutes))
        hasBreak = (try? c.decode(Bool.self, forKey: .hasBreak)) ?? false
        appSetID = try? c.decodeIfPresent(UUID.self, forKey: .appSetID)
        strictness = (try? c.decode(Strictness.self, forKey: .strictness)) ?? .steady
        pendingStrictness = try? c.decodeIfPresent(Strictness.self, forKey: .pendingStrictness)
        pendingFrom = try? c.decodeIfPresent(LocalDay.self, forKey: .pendingFrom)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(verb, forKey: .verb)
        try c.encode(minutes, forKey: .minutes)
        try c.encode(hasBreak, forKey: .hasBreak)
        try c.encodeIfPresent(appSetID, forKey: .appSetID)
        try c.encode(strictness, forKey: .strictness)
        try c.encodeIfPresent(pendingStrictness, forKey: .pendingStrictness)
        try c.encodeIfPresent(pendingFrom, forKey: .pendingFrom)
    }
}
