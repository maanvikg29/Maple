import Foundation

/// How lively the tree looks after the last seven nights (spec §4.8): 0.4…1. A rough week only makes the tree
/// dimmer and stiller; nothing is ever removed.
///
/// `score = 0.5·onTimeShare + 0.25·fullNightShare + 0.25·scrollFreeShare`, `v = 0.4 + 0.6·score`.
/// Each share counts only nights that have that data; a share with no data hands its weight to the others in
/// proportion, and with no data at all the tree is at full vitality.
public struct Vitality: Sendable, Equatable {
    /// Below this the tree is quiet (VoiceOver adds "Resting.").
    public static let quietThreshold = 0.55
    public static let minimum = 0.4

    public let value: Double

    public init(value: Double) {
        self.value = min(1, max(Self.minimum, value))
    }

    /// Days a night stays in the window: the 7 nights before today, plus tonight once it is recorded.
    public static let window = 7

    /// The tree's vitality on `today` (spec §4.8, "computed once a day from the last 7 nights"): only nights that
    /// began in the week up to today count, so nights from before a gap never dim the tree. With none, it is 1.
    public init(nights: [NightRecord], today: LocalDay, calendar: Calendar) {
        let earliest = today.adding(days: -Self.window, calendar: calendar)
        self.init(last7Nights: nights.filter { $0.day >= earliest && $0.day <= today })
    }

    /// Scores the last 7 of `nights`, whatever their dates; `init(nights:today:calendar:)` picks the window first.
    public init(last7Nights nights: [NightRecord]) {
        let recent = nights.sorted { $0.day < $1.day }.suffix(7)
        func share(_ field: KeyPath<NightRecord, Bool?>) -> Double? {
            let known = recent.compactMap { $0[keyPath: field] }
            return known.isEmpty ? nil : Double(known.filter { $0 }.count) / Double(known.count)
        }
        let weighted = [(0.5, share(\.onTime)), (0.25, share(\.fullNight)), (0.25, share(\.scrollFree))]
            .compactMap { weight, share in share.map { (weight, $0) } }
        let totalWeight = weighted.reduce(0) { $0 + $1.0 }
        guard totalWeight > 0 else {
            self.init(value: 1)
            return
        }
        let score = weighted.reduce(0) { $0 + $1.0 * $1.1 } / totalWeight
        self.init(value: Self.minimum + (1 - Self.minimum) * score)
    }

    public var isQuiet: Bool { value < Self.quietThreshold }
}
