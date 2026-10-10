import Foundation
import MapleCore
import SwiftUI

/// What the rarity explainer sheet says (spec §5.7, override 1), in every `MemberShare` state. Pure.
///
/// The sheet leads with one figure: the members counted ("12,400 members shared their leaves in the week of
/// 29 Sep"), or, while there are fewer than 1,000, the progress toward that ("640 of 1,000"). Then how to read a
/// share, what is ever sent, and whether the member's own leaves are counted.
nonisolated public struct RarityExplainer: Sendable, Equatable {
    public enum Figure: Sendable, Equatable {
        /// "12,400": members counted.
        case members(String)
        /// "640" of "1,000", and the fraction for a progress hairline.
        case progress(soFar: String, threshold: String, fraction: Double)
    }

    public static let title = "Members who have this leaf"

    public let figure: Figure?
    /// The line under the figure, or the lead sentence when there is no figure.
    public let lead: String
    /// "Last updated 3 Oct" for a cached value older than 48 hours.
    public let updated: String?
    public let paragraphs: [String]
    public let consent: String

    /// - Parameters:
    ///   - memberCount: Members counted, rounded down to 100 (`LeafShareStore.memberCount`); nil below 1,000.
    ///   - weekStart: The week the counts describe.
    ///   - included: The member's own leaves are counted (`rarityConsent == .included`).
    public init(
        share: MemberShare, memberCount: Int?, weekStart: Date?, included: Bool,
        locale: Locale = .current, timeZone: TimeZone = .current
    ) {
        let number = IntegerFormatStyle<Int>.number.locale(locale)
        let threshold = MemberShareCopy.memberThreshold
        var day = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, timeZone: timeZone)
        day = day.day().month(.abbreviated)

        var updated: String?
        switch share {
        case .value, .stale:
            if let memberCount {
                figure = .members(memberCount.formatted(number))
                lead = weekStart.map { "members shared their leaves in the week of \($0.formatted(day))" }
                    ?? "members share their leaves"
            } else {
                figure = nil
                lead = "Counted from the members who share their leaves."
            }
            if case .stale(_, let asOf) = share { updated = "Last updated \(asOf.formatted(day))" }
        case .notEnoughMembers(let soFar):
            if let soFar, soFar > 0 {
                figure = .progress(soFar: soFar.formatted(number), threshold: threshold.formatted(number),
                                   fraction: min(1, Double(soFar) / Double(threshold)))
                lead = "Rarity appears once \(threshold.formatted(number)) members share their leaves."
            } else {
                figure = nil
                lead = "Rarity appears once \(threshold.formatted(number)) members share their leaves."
            }
        case .neverFetched:
            figure = nil
            lead = "Rarity shows when you're online."
        case .loading:
            figure = nil
            lead = "Maple is counting who has this leaf."
        case .newSpecies:
            figure = nil
            lead = "This leaf is new to Maple. Its rarity appears next week."
        case .notEarnableYet:
            figure = nil
            lead = "This leaf can't be earned in Maple yet."
        }
        self.updated = updated
        paragraphs = [
            "Rarity is the share of members who hold a leaf. When Maple can't be sure, it shows a bound like “Under 1%”.",
            "Only which leaves you hold is ever shared, never sleep, health or screen data.",
        ]
        consent = included ? "Your leaves are counted." : "Your leaves aren't counted. Rarity looks the same either way."
    }
}

/// The explainer's content, drawn on the sheet's `surface2` (spec §5.7). The sheet adds the "Privacy settings"
/// link below it.
public struct RarityExplainerView: View {
    @Environment(\.theme) private var theme
    private let explainer: RarityExplainer

    public init(_ explainer: RarityExplainer) {
        self.explainer = explainer
    }

    public var body: some View {
        let colors = theme.colors
        VStack(alignment: .leading, spacing: 0) {
            Text(RarityExplainer.title)
                .font(MapleFont.sectionTitle)
                .foregroundStyle(colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            switch explainer.figure {
            case .members(let count):
                VStack(alignment: .leading, spacing: 4) {
                    StatNumber(count, size: .stat, accessibilityText: "\(count) \(explainer.lead)")
                    Text(explainer.lead)
                        .font(MapleFont.callout)
                        .foregroundStyle(colors.textSecondary)
                        .accessibilityHidden(true)
                }
                .padding(.top, 24)
            case .progress(let soFar, let threshold, let fraction):
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        StatNumber(soFar, size: .stat)
                        Text("of \(threshold)")
                            .font(.system(.body, design: .rounded, weight: .medium))
                            .foregroundStyle(colors.textSecondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(soFar) of \(threshold) members so far")
                    ProgressHairline(fraction: fraction, height: 3)
                    Text(explainer.lead)
                        .font(MapleFont.callout)
                        .foregroundStyle(colors.textSecondary)
                }
                .padding(.top, 24)
            case nil:
                Text(explainer.lead)
                    .font(MapleFont.body)
                    .foregroundStyle(colors.textPrimary)
                    .padding(.top, 16)
            }

            if let updated = explainer.updated {
                Text(updated)
                    .font(MapleFont.footnote)
                    .foregroundStyle(colors.textSecondary)
                    .padding(.top, 4)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(explainer.paragraphs, id: \.self) { paragraph in
                    Text(paragraph)
                        .font(MapleFont.callout)
                        .foregroundStyle(colors.textSecondary)
                }
                Text(explainer.consent)
                    .font(MapleFont.callout)
                    .foregroundStyle(colors.textPrimary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
