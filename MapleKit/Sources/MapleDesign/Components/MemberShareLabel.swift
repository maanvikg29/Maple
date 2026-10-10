import MapleCore
import SwiftUI

/// How many members hold a leaf, in every `MemberShare` state, with the copy from spec §5.7.
///
/// ```swift
/// MemberShareLabel(share: store.share(for: id), layout: .detail)
/// MemberShareLabel(share: share, layout: .tile, pressedOn: unlock.date)   // tile meta
/// MemberShareLabel(share: share, layout: .inline)                       // the reveal
/// ```
///
/// While loading, a small placeholder capsule pulses 0.35 ↔ 0.6 over `loadingPulsePeriod` (static at 0.45 under
/// Reduce Motion); tiles show the pressed date instead. The share card's line is `MemberShareCopy.shareCard(_:)`.
public struct MemberShareLabel: View {
    nonisolated public enum Layout: Sendable, Hashable {
        /// Leaf detail: "22%" at 22pt over "of members have this leaf", centred.
        case detail
        /// Tile meta: "22% have it", or the pressed date.
        case tile
        /// The reveal: one line, "22% of members have this".
        case inline
    }

    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @ScaledMetric(relativeTo: .title2) private var valueSize: CGFloat = 22

    private let share: MemberShare
    private let layout: Layout
    private let pressedOn: Date?

    /// - Parameter pressedOn: The date the leaf was pressed. Tiles show it whenever there is no share to show;
    ///   without it they read "No rarity yet".
    public init(share: MemberShare, layout: Layout, pressedOn: Date? = nil) {
        self.share = share
        self.layout = layout
        self.pressedOn = pressedOn
    }

    public var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(copy.accessibilityLabel(share, layout: layout, pressedOn: pressedOn))
    }

    private var copy: MemberShareCopy {
        MemberShareCopy(locale: locale, timeZone: timeZone)
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .detail: detail
        case .tile: tile
        case .inline: inline
        }
    }

    // MARK: Layouts

    @ViewBuilder
    private var detail: some View {
        let colors = theme.colors
        switch copy.detail(share) {
        case .placeholder:
            // The value's line, with the caption's space kept so nothing jumps when it arrives.
            VStack(spacing: 4) {
                LoadingCapsule()
                    .frame(height: valueLineHeight)
                Text(verbatim: MemberShareCopy.detailCaption)
                    .font(MapleFont.callout)
                    .hidden()
            }
        case .value(let value, let caption, let asOf):
            VStack(spacing: 4) {
                Text(value)
                    .font(MapleFont.numeral(size: valueSize))
                    .foregroundStyle(asOf == nil ? colors.textPrimary : colors.textSecondary)
                Text(caption)
                    .font(MapleFont.callout)
                    .foregroundStyle(colors.textSecondary)
                if let asOf {
                    Text(asOf)
                        .font(MapleFont.footnote)
                        .foregroundStyle(colors.textSecondary)
                }
            }
            .multilineTextAlignment(.center)
        case .message(let message):
            MessageText(message)
        }
    }

    private var tile: some View {
        Text(copy.tile(share, pressedOn: pressedOn))
            .font(MapleFont.tileMeta)
            .foregroundStyle(theme.colors.textSecondary)
            .lineLimit(1)
    }

    @ViewBuilder
    private var inline: some View {
        let colors = theme.colors
        switch copy.inline(share) {
        case .placeholder:
            LoadingCapsule()
                .frame(height: inlineLineHeight)
        case .value(let value, let rest):
            Text("\(Text(value).foregroundStyle(colors.textPrimary).fontWeight(.semibold))\(Text(rest).foregroundStyle(colors.textSecondary))")
                .font(MapleFont.callout)
                .multilineTextAlignment(.center)
        case .message(let message):
            MessageText(message)
        }
    }

    @ScaledMetric(relativeTo: .title2) private var valueLineHeight: CGFloat = 27
    @ScaledMetric(relativeTo: .subheadline) private var inlineLineHeight: CGFloat = 20
}

/// A rarity message in 15pt secondary, centred. One line when it fits; otherwise it breaks at its last " · "
/// ("…take part" / "640 so far") rather than leaving a word alone on the second line.
private struct MessageText: View {
    @Environment(\.theme) private var theme
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        let separator = " · "
        let parts = message.components(separatedBy: separator)
        ViewThatFits(in: .horizontal) {
            Text(message).lineLimit(1)
            if parts.count > 1 {
                VStack(spacing: 2) {
                    Text(parts.dropLast().joined(separator: separator))
                    Text(parts[parts.count - 1])
                }
            }
            Text(message)
        }
        .font(MapleFont.callout)
        .foregroundStyle(theme.colors.textSecondary)
        .multilineTextAlignment(.center)
    }
}

/// The 44 × 12 loading placeholder: a white 8% capsule pulsing 0.35 ↔ 0.6 (never a shimmer).
private struct LoadingCapsule: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let capsule = Capsule(style: .continuous)
            .fill(theme.colors.track)
            .frame(width: 44, height: 12)
        if reduceMotion {
            capsule.opacity(MemberShareCopy.loadingStillOpacity)
        } else {
            capsule.phaseAnimator(MemberShareCopy.loadingPulse) { content, opacity in
                content.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: theme.motion.loadingPulsePeriod / 2)
            }
        }
    }
}

/// The words for every `MemberShare` state and layout (spec §5.7). Pure, so every state's copy is tested.
nonisolated public struct MemberShareCopy: Sendable {
    /// What a detail or inline layout shows.
    public enum Content: Sendable, Equatable {
        /// The pulsing loading capsule.
        case placeholder
        /// Detail: the value ("22%"), its caption, and "As of 3 Oct" when stale.
        case value(String, caption: String, asOf: String?)
        /// A sentence in place of a value.
        case message(String)
    }

    /// What the inline (reveal) layout shows.
    public enum Inline: Sendable, Equatable {
        case placeholder
        /// "22%" and the rest of the line (" of members have this", plus " · as of 3 Oct" when stale).
        case value(String, rest: String)
        case message(String)
    }

    /// The reports a week needs before any share is published (D4).
    public static let memberThreshold = 1_000
    static let detailCaption = "of members have this leaf"
    /// The loading pulse's two opacities, and its still opacity under Reduce Motion.
    static let loadingPulse: [Double] = [0.35, 0.6]
    static let loadingStillOpacity = 0.45

    public var locale: Locale
    public var timeZone: TimeZone

    public init(locale: Locale = .current, timeZone: TimeZone = .current) {
        self.locale = locale
        self.timeZone = timeZone
    }

    // MARK: Layouts

    public func detail(_ share: MemberShare) -> Content {
        switch share {
        case .loading: .placeholder
        case .value(let display, _): .value(display, caption: Self.detailCaption, asOf: nil)
        case .stale(let display, let asOf): .value(display, caption: Self.detailCaption, asOf: "As of \(day(asOf))")
        case .notEnoughMembers, .neverFetched, .newSpecies, .notEarnableYet: .message(message(for: share))
        }
    }

    /// Tile meta: the share when there is a current or cached value, otherwise the pressed date
    /// ("No rarity yet" without one), and "Not earnable yet" for unshipped categories.
    public func tile(_ share: MemberShare, pressedOn: Date?) -> String {
        switch share {
        case .value(let display, _), .stale(let display, _): "\(display) have it"
        case .notEarnableYet: "Not earnable yet"
        case .loading, .notEnoughMembers, .neverFetched, .newSpecies: pressedOn.map(day) ?? "No rarity yet"
        }
    }

    public func inline(_ share: MemberShare) -> Inline {
        switch share {
        case .loading: .placeholder
        case .value(let display, _): .value(display, rest: " of members have this")
        case .stale(let display, let asOf): .value(display, rest: " of members have this · as of \(day(asOf))")
        case .notEnoughMembers, .neverFetched, .newSpecies, .notEarnableYet: .message(message(for: share))
        }
    }

    /// The share card's line, which appears only for a fresh value.
    public static func shareCard(_ share: MemberShare) -> String? {
        if case .value(let display, _) = share { "\(display) of Maple members have it" } else { nil }
    }

    /// What VoiceOver reads for a layout: the visible words as one sentence.
    public func accessibilityLabel(_ share: MemberShare, layout: MemberShareLabel.Layout, pressedOn: Date?) -> String {
        if share == .loading, layout != .tile { return "Loading rarity" }
        switch layout {
        case .tile:
            return tile(share, pressedOn: pressedOn)
        case .detail:
            switch detail(share) {
            case .placeholder: return "Loading rarity"
            case .value(let value, let caption, let asOf): return ["\(value) \(caption)", asOf].compactMap(\.self).joined(separator: ". ")
            case .message(let message): return message
            }
        case .inline:
            switch inline(share) {
            case .placeholder: return "Loading rarity"
            case .value(let value, let rest): return value + rest
            case .message(let message): return message
            }
        }
    }

    // MARK: Pieces

    private func message(for share: MemberShare) -> String {
        switch share {
        case .notEnoughMembers(let soFar):
            let threshold = Self.memberThreshold.formatted(.number.locale(locale))
            let base = "Rarity appears once \(threshold) members take part"
            guard let soFar else { return base }
            return "\(base) · \(soFar.formatted(.number.locale(locale))) so far"
        case .neverFetched: return "Rarity shows when you're online"
        case .newSpecies: return "New · rarity next week"
        case .notEarnableYet: return "Not earnable yet"
        case .loading, .value, .stale: return ""
        }
    }

    /// "3 Oct" (day and short month, in the locale's order).
    private func day(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, timeZone: timeZone)
        style = style.day().month(.abbreviated)
        return date.formatted(style)
    }
}
