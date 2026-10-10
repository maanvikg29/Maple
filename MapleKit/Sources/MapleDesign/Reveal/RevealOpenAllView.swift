import MapleCore
import SwiftUI

/// "Open all" (spec §5.8): the remaining buds appear in a centred row (56 pt each, up to 6 a row) and open one
/// after another every 0.35 s with the short ritual; then a list of every leaf opened in this sitting follows,
/// with "Place on your maple". Under Reduce Motion it goes straight to the list.
///
/// ```swift
/// RevealOpenAllView(opening: rest, opened: all, moment: .opened(at: tapped), onPlace: place)
/// ```
public struct RevealOpenAllView: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var focusesList: Bool
    @State private var settledAt: Date?

    private let opening: [RevealLeaf]
    private let opened: [RevealLeaf]
    private let moment: RevealMoment
    private let onPlace: () -> Void

    /// - Parameters:
    ///   - opening: The leaves that open in the row, in order.
    ///   - opened: Every leaf opened in this sitting, for the list.
    ///   - moment: When "Open all" was tapped, or a fixed time after it (`.closed` shows the closed row).
    public init(opening: [RevealLeaf], opened: [RevealLeaf], moment: RevealMoment, onPlace: @escaping () -> Void) {
        self.opening = opening
        self.opened = opened
        self.moment = moment
        self.onPlace = onPlace
    }

    private var schedule: RevealOpenAllSchedule {
        RevealOpenAllSchedule(count: opening.count, reduceMotion: reduceMotion)
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !isRunning)) { context in
            content(time: time(at: context.date))
        }
        .task(id: moment) { await settle() }
    }

    // MARK: Time

    private var isRunning: Bool {
        if case .opened(let date) = moment { return settledAt != date }
        return false
    }

    private func time(at date: Date) -> TimeInterval {
        switch moment {
        case .closed: return 0
        case .still(let time): return time
        case .opened(let opened):
            return settledAt == opened ? schedule.settledTime : max(0, date.timeIntervalSince(opened))
        }
    }

    private func settle() async {
        guard case .opened(let opened) = moment else {
            if case .still(let time) = moment, time >= schedule.listStart { focusesList = true }
            return
        }
        let untilList = schedule.listStart - Date().timeIntervalSince(opened)
        if untilList > 0 { try? await Task.sleep(for: .seconds(untilList)) }
        guard !Task.isCancelled else { return }
        focusesList = true
        let untilRest = schedule.settledTime - Date().timeIntervalSince(opened)
        if untilRest > 0 { try? await Task.sleep(for: .seconds(untilRest)) }
        guard !Task.isCancelled else { return }
        settledAt = opened
    }

    // MARK: Layout

    private func content(time: TimeInterval) -> some View {
        let listOpacity = moment == .closed ? 0 : schedule.listOpacity(at: time)
        let rowOpacity = moment == .closed ? 1 : schedule.rowOpacity(at: time)
        return GeometryReader { proxy in
            let layout = RevealLayout(size: proxy.size, safeArea: proxy.safeAreaInsets)
            ZStack(alignment: .top) {
                RevealBackdrop(centreY: layout.budCentreScreenY)

                if rowOpacity > 0 {
                    row(time: time, width: proxy.size.width)
                        .position(x: proxy.size.width / 2, y: layout.budCentreY)
                        .opacity(rowOpacity)
                        .accessibilityHidden(true)
                }

                if listOpacity > 0 {
                    list(height: proxy.size.height)
                        .opacity(listOpacity)
                        .accessibilityHidden(listOpacity < 0.5)
                }

                RevealHeader(headerTitle)
                    .padding(.horizontal, theme.spacing.homeMargin + theme.spacing.minimumHitTarget)
                    .padding(.top, RevealLayout.headerInset)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button("Place on your maple", action: onPlace)
                    .buttonStyle(.moonlight)
                    .padding(.horizontal, theme.spacing.homeMargin)
                    .padding(.top, theme.spacing.sm)
                    .padding(.bottom, theme.spacing.md)
                    .opacity(listOpacity)
                    .allowsHitTesting(listOpacity > 0.5)
                    .accessibilityHidden(listOpacity < 0.5)
                    .footerFade(theme.colors.background)
            }
        }
    }

    private var headerTitle: String {
        let count = max(opened.count, opening.count)
        return count == 1 ? "A new leaf" : "\(count) new leaves"
    }

    /// The buds in a centred row, wrapping after 6, each opening on its own schedule.
    private func row(time: TimeInterval, width: CGFloat) -> some View {
        let cell = RevealOpenAllMetrics.cell
        let rows = RevealOpenAllMetrics.rows(count: opening.count)
        let gap = RevealOpenAllMetrics.gap(perRow: rows.first?.count ?? 1, width: width - 2 * theme.spacing.homeMargin)
        return VStack(spacing: RevealOpenAllMetrics.rowGap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, indices in
                HStack(spacing: gap) {
                    ForEach(indices, id: \.self) { index in
                        let leaf = opening[index]
                        let frame: RevealFrame? = moment == .closed ? nil : schedule.frame(of: index, at: time)
                        RevealStage(species: leaf.species, colourway: leaf.colourway, frame: frame, leafSize: cell, budSize: cell)
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
    }

    /// Every opened leaf: its 64 pt specimen, name and earned line, centred between the header and the footer.
    private func list(height: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                ForEach(opened) { leaf in
                    RevealListRow(leaf: leaf)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityFocused($focusesList)
            .padding(.horizontal, theme.spacing.homeMargin)
            .padding(.top, RevealOpenAllMetrics.listTop)
            .padding(.bottom, RevealOpenAllMetrics.listInset)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .center)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// One opened leaf in the "Open all" list.
struct RevealListRow: View {
    @Environment(\.theme) private var theme
    let leaf: RevealLeaf

    var body: some View {
        let species = leaf.species
        HStack(spacing: theme.spacing.md) {
            SpecimenView(species: species, colourway: leaf.colourway, size: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                name(species)
                Text(leaf.earnedLine)
                    .font(MapleFont.callout)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    private func name(_ species: LeafSpecies) -> some View {
        let colors = theme.colors
        let title = species.common.isEmpty
            ? Text(RevealText.latin(species.name)).font(MapleFont.scientific(.headline, weight: .semibold))
            : Text(species.common).font(MapleFont.headline)
        let mark = species.confidence.isApproximate
            ? Text(" ≈").font(MapleFont.footnote).foregroundStyle(colors.textSecondary) : Text("")
        return Text("\(title.foregroundStyle(colors.textPrimary))\(mark)")
    }

    private var spokenLabel: String {
        var parts = [leaf.species.displayName, leaf.earnedLine]
        if let approximate = leaf.species.confidence.approximateSpokenLabel {
            parts.append(approximate)
        }
        return parts.joined(separator: ". ")
    }
}

/// Sizes for the "Open all" row and list, kept pure for testing.
nonisolated enum RevealOpenAllMetrics {
    /// Each bud, and each leaf it opens into.
    static let cell: CGFloat = 56
    static let perRow = 6
    static let rowGap: CGFloat = 24
    static let maxGap: CGFloat = 16
    /// Below the list: more than above, so a short list sits a little above the middle, near the reveal's hero line.
    static let listInset: CGFloat = 128
    /// Clears the header (24 pt down, about 40 pt tall) by a group gap.
    static let listTop: CGFloat = 96

    /// Positions in the row, split into lines of at most 6, the remainder on the last line.
    static func rows(count: Int) -> [[Int]] {
        guard count > 0 else { return [] }
        return stride(from: 0, to: count, by: perRow).map { start in Array(start..<min(count, start + perRow)) }
    }

    /// The gap between cells: up to 16 pt, tighter when a full row must fit in `width`.
    static func gap(perRow count: Int, width: CGFloat) -> CGFloat {
        guard count > 1 else { return 0 }
        let room = (width - CGFloat(count) * cell) / CGFloat(count - 1)
        return max(0, min(maxGap, room))
    }
}
