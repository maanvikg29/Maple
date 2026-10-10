import MapleCore
import SwiftUI

/// A Herbarium section's pinned header (spec §5.3): the name in `sectionTitle`, "6 of 15" on the right, the
/// definition in `footnote`, and for a category missing a permission, "Needs Apple Health" with a 32pt "Turn on".
/// Pinned, it sits on the background at 92% over `ultraThinMaterial` with a white 6% hairline below.
///
/// ```swift
/// HerbariumSectionHeader(section) { requestPermission(section.permission) }
/// ```
public struct HerbariumSectionHeader: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let title: String
    private let count: String
    private let spokenCount: String
    private let definition: String?
    private let dot: LeafColor?
    private let permission: LeafAvailability?
    private let turnOn: (() -> Void)?

    /// - Parameter turnOn: Asks for the missing permission; nil hides the capsule.
    public init(_ section: HerbariumSection, turnOn: (() -> Void)? = nil) {
        self.init(title: section.title, count: section.count, spokenCount: section.spokenCount,
                  definition: section.definition, dot: section.dot, permission: section.permission, turnOn: turnOn)
    }

    public init(
        title: String, count: String, spokenCount: String? = nil, definition: String? = nil, dot: LeafColor? = nil,
        permission: LeafAvailability? = nil, turnOn: (() -> Void)? = nil
    ) {
        self.title = title
        self.count = count
        self.spokenCount = spokenCount ?? count
        self.definition = definition
        self.dot = dot
        self.permission = permission
        self.turnOn = turnOn
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let dot {
                    Circle()
                        .fill(Color(dot))
                        .frame(width: 10, height: 10)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 7 }
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(MapleFont.sectionTitle)
                    .foregroundStyle(theme.colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                Text(count)
                    .font(MapleFont.callout.monospacedDigit())
                    .foregroundStyle(theme.colors.textSecondary)
                    .accessibilityLabel(spokenCount)
            }
            if let definition {
                Text(definition)
                    .font(MapleFont.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let permission, let line = HerbariumCopy.permissionLine(permission) {
                HStack(spacing: 12) {
                    Text(line)
                        .font(MapleFont.footnote)
                        .foregroundStyle(theme.colors.textSecondary)
                    Spacer(minLength: 8)
                    if let turnOn, HerbariumCopy.turnOnTitle(permission) != nil {
                        Button("Turn on", action: turnOn)
                            .buttonStyle(.glassCapsule(.compact))
                            .accessibilityHint(HerbariumCopy.turnOnTitle(permission) ?? "")
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                if reduceTransparency {
                    theme.colors.background
                } else {
                    Rectangle().fill(.ultraThinMaterial)
                    theme.colors.background.opacity(0.92)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.colors.divider).frame(height: 0.5)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
