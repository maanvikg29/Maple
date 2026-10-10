import Foundation
import MapleCore
import SwiftUI

/// The Streak sheet's last 14 nights (spec §8.6): which belong to the current bedtime run, which were missed but
/// forgiven inside it, and which came before it.
nonisolated public enum BedtimeRunNights {
    public enum Mark: Sendable, Hashable {
        /// An on-time night of the current run: a filled amber circle.
        case inRun
        /// A missed night the run forgave: a hollow amber ring.
        case forgiven
        /// Any other night: a faint ring.
        case other
    }

    public static let nightCount = 14

    /// The last `count` nights, oldest first, ending with last night.
    ///
    /// Walking back from last night, the run takes on-time nights until it has `currentRun` of them; a night
    /// recorded as missed inside that stretch was forgiven (the run counter says the run went on past it). A night
    /// with no record inside the run counts as one of its nights. Everything earlier is outside the run.
    ///
    /// - Parameters:
    ///   - nights: Recent night records (any order; only `onTime` is read).
    ///   - currentRun: The current bedtime run, in on-time nights.
    ///   - lastNight: The local day last night began on.
    public static func marks(
        nights: [NightRecord], currentRun: Int, lastNight: LocalDay, calendar: Calendar = .current, count: Int = nightCount
    ) -> [Mark] {
        let byDay = Dictionary(nights.map { ($0.day, $0) }, uniquingKeysWith: { _, newer in newer })
        var remaining = max(0, currentRun)
        var marks: [Mark] = []
        for back in 0..<max(0, count) {
            let day = lastNight.adding(days: -back, calendar: calendar)
            guard remaining > 0 else {
                marks.append(.other)
                continue
            }
            if byDay[day]?.onTime == false {
                // A miss only counts as forgiven while the run continues past it.
                marks.append(.forgiven)
            } else {
                marks.append(.inRun)
                remaining -= 1
            }
        }
        return marks.reversed()
    }
}

/// A row of the last 14 nights as 20pt circles (spec §8.6): the current run filled in `reward` amber, forgiven
/// misses as hollow amber rings, other nights as faint rings. One VoiceOver element.
public struct BedtimeRunRow: View {
    @Environment(\.theme) private var theme
    private let marks: [BedtimeRunNights.Mark]

    public init(marks: [BedtimeRunNights.Mark]) {
        self.marks = marks
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                circle(mark)
                    .frame(width: 20, height: 20)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HomeSpeech.runNights(marks))
    }

    @ViewBuilder
    private func circle(_ mark: BedtimeRunNights.Mark) -> some View {
        switch mark {
        case .inRun:
            Circle().fill(theme.colors.reward)
        case .forgiven:
            Circle().strokeBorder(theme.colors.reward, lineWidth: 1.5)
        case .other:
            Circle().strokeBorder(theme.colors.track, lineWidth: 1)
        }
    }
}
