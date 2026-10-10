import MapleCore
import SwiftUI

/// The next leaf to earn, as one quiet 56pt row on black (spec §3.2): a 32pt skeleton of the leaf filling from
/// its stalk with progress, the name, the remainder on the right ("3 nights", "Tonight"), and a 2pt season-tint
/// hairline under the text. Its waiting variant shows the amber bud and "A new leaf is waiting" instead.
///
/// When nothing can be earned because Apple Health isn't on (D9 keeps those leaves out of the next leaf), its
/// needs-permission variant shows the cheapest of them as the Herbarium draws a needs-permission tile: a neutral
/// skeleton at 50%, the name with "Needs Apple Health" on the right, and a "Turn on Apple Health" text link where
/// the hairline would be. The row opens the leaf; the link asks for the permission.
///
/// ```swift
/// NextLeafRow(.leaf(progress, remainder: LeafRemainder(progress, phase: state.phase)), action: { push(id) })
///     .zoomSource(id: progress.speciesID, in: namespace)
/// NextLeafRow(.waiting(count: 2), action: { reveal() })
/// NextLeafRow(.needsPermission(prompt), action: { push(id) }, turnOn: { showHealthPrimer() })
/// ```
public struct NextLeafRow: View {
    public enum Content: Equatable {
        /// A locked leaf and what is left to earn it.
        case leaf(LeafProgress, remainder: LeafRemainder)
        /// Earned leaves waiting to be opened.
        case waiting(count: Int)
        /// No leaf can be earned without a permission: the cheapest one turning it on would make earnable
        /// (`CollectionStore.permissionPrompt(at:)`).
        case needsPermission(LeafProgress)
    }

    @Environment(\.theme) private var theme
    @Environment(\.season) private var season
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let content: Content
    private let action: () -> Void
    private let turnOn: (() -> Void)?
    private var zoom: (id: String, namespace: Namespace.ID)?

    /// - Parameter turnOn: Asks for the missing permission (the needs-permission variant's text link).
    public init(_ content: Content, action: @escaping () -> Void, turnOn: (() -> Void)? = nil) {
        self.content = content
        self.action = action
        self.turnOn = turnOn
    }

    /// Makes the 32pt leaf the source of a zoom transition (`.navigationTransition(.zoom(sourceID:in:))`).
    public func zoomSource(id: String, in namespace: Namespace.ID) -> NextLeafRow {
        var row = self
        row.zoom = (id, namespace)
        return row
    }

    public var body: some View {
        if case .needsPermission(let progress) = content {
            needsPermissionRow(progress)
        } else {
            row
        }
    }

    private var row: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: theme.spacing.sm) {
                glyph
                    .frame(width: 32, height: 32)
                    .modifier(ZoomSource(zoom: zoom))
                text
            }
            .frame(maxWidth: .infinity, minHeight: theme.spacing.row, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    // MARK: Parts

    @ViewBuilder
    private var glyph: some View {
        switch content {
        case .leaf(let progress, _):
            if let species = LeafCatalog.shared.species(id: progress.speciesID) {
                let tint = theme.colors.seasonTint(season)
                LeafView(species, style: .skeleton(stroke: tint.opacity(0.6), vein: .white.opacity(0.15)))
                    .progressFill(
                        fraction: progress.fraction,
                        colour: Color(LeafColourway.pressed(in: season, evergreen: species.evergreen).color(for: species)),
                        opacity: 0.4
                    )
            }
        case .waiting:
            BudGlyph(waiting: true, glow: .still)
        case .needsPermission(let progress):
            // The Herbarium's needs-permission skeleton (spec §5.2): neutral, at 50%.
            if let species = LeafCatalog.shared.species(id: progress.speciesID) {
                LeafView(species, style: .skeleton(stroke: theme.colors.skeletonStroke, vein: theme.colors.skeletonVein))
                    .opacity(0.5)
            }
        }
    }

    @ViewBuilder
    private var text: some View {
        switch content {
        case .leaf(let progress, let remainder):
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                nameLine(progress, remainder: remainder)
                if remainder.showsBar {
                    ProgressHairline(fraction: progress.fraction)
                }
            }
        case .waiting(let count):
            Text(HomeSpeech.waiting(count))
                .font(MapleFont.contextEmphasis)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        case .needsPermission(let progress):
            nameLine(progress, trailing: HerbariumCopy.permissionLine(progress.availability) ?? "")
        }
    }

    /// The needs-permission variant: the leaf and its name open the leaf; the text link under the name asks for the
    /// permission. Two VoiceOver elements, so each can be reached on its own.
    private func needsPermissionRow(_ progress: LeafProgress) -> some View {
        HStack(alignment: .center, spacing: theme.spacing.sm) {
            glyph
                .frame(width: 32, height: 32)
                .modifier(ZoomSource(zoom: zoom))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                text
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityHint(accessibilityHint)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(.default, action)
                if let turnOn, let title = HerbariumCopy.turnOnTitle(progress.availability) {
                    // The link's 44pt target overlaps the row's padding, so the row stays 56pt.
                    TextLink(title, action: turnOn)
                        .padding(.top, -8)
                        .padding(.bottom, -12)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: theme.spacing.row, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func nameLine(_ progress: LeafProgress, remainder: LeafRemainder) -> some View {
        nameLine(progress, trailing: remainder.text)
    }

    /// The name, and on the right the remainder (or what the leaf needs), which never truncates.
    @ViewBuilder
    private func nameLine(_ progress: LeafProgress, trailing: String) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: theme.spacing.xs))
        layout {
            name(progress)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            // The remainder never truncates; the name gives way first.
            Text(trailing)
                .font(MapleFont.footnote.monospacedDigit())
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
        }
    }

    private func name(_ progress: LeafProgress) -> Text {
        guard let species = LeafCatalog.shared.species(id: progress.speciesID) else { return Text("") }
        let title = species.common.isEmpty
            ? Text(species.name).font(MapleFont.scientific(.subheadline))
            : Text(species.common).font(MapleFont.contextEmphasis)
        let styled = title.foregroundStyle(theme.colors.textPrimary)
        guard species.confidence.isApproximate else { return styled }
        let mark = Text(" ≈").font(MapleFont.footnote).foregroundStyle(theme.colors.textSecondary)
        return Text("\(styled)\(mark)")
    }

    // MARK: Accessibility

    private var accessibilityLabel: String {
        switch content {
        case .leaf(let progress, _): HomeSpeech.nextLeaf(progress)
        case .waiting(let count): HomeSpeech.waiting(count)
        case .needsPermission(let progress): HomeSpeech.needsPermission(progress)
        }
    }

    private var accessibilityHint: String {
        switch content {
        case .leaf, .needsPermission: "Shows how to earn it."
        case .waiting(let count): count == 1 ? "Opens your new leaf." : "Opens your new leaves."
        }
    }
}

private struct ZoomSource: ViewModifier {
    let zoom: (id: String, namespace: Namespace.ID)?

    func body(content: Content) -> some View {
        if let zoom {
            content.matchedTransitionSource(id: zoom.id, in: zoom.namespace)
        } else {
            content
        }
    }
}

/// Rows dim and settle slightly while pressed: scale 0.98 and 90% over `press` (no scale under Reduce Motion).
private struct RowPressStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .mapleAnimation(theme.motion.press, value: configuration.isPressed)
    }
}
