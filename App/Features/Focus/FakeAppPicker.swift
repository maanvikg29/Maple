#if DEBUG
import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// DEBUG only: F1's stand-in for Apple's app picker (F1 design §5.14). Sample apps, sites and categories with
/// checkboxes, one row worth 45 apps to try the 50-app limit, and, for a seeded list longer than the samples, one row
/// for the rest. It edits a `PickerChoice`, whose JSON the Blocking sheet stores as the list's opaque selection.
struct FakeAppPicker: View {
    @Environment(\.theme) private var theme
    @Binding var choice: PickerChoice

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.lg) {
            ForEach(PickerChoice.Kind.allCases, id: \.self) { kind in
                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    Text(kind.title)
                        .font(MapleFont.headline)
                        .foregroundStyle(theme.colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    ProfileListGroup {
                        ForEach(PickerChoice.samples.filter { $0.kind == kind }) { sample in
                            row(sample.name, isOn: choice.picked.contains(sample.id)) { choice.toggle(sample.id) }
                        }
                        if kind == .app {
                            row(PickerChoice.bulkTitle, isOn: choice.bulk) { choice.bulk.toggle() }
                            if choice.otherApps > 0 {
                                row(PickerChoice.othersTitle(choice.otherApps), isOn: true) { choice.otherApps = 0 }
                            }
                        }
                    }
                }
            }
        }
    }

    private func row(_ title: String, isOn: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: theme.spacing.sm) {
                SelectionMark(isOn: isOn, kind: .square)
                Text(title)
                    .font(MapleFont.body)
                    .foregroundStyle(theme.colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, theme.spacing.listMargin)
            .padding(.vertical, theme.spacing.sm)
            .frame(minHeight: theme.spacing.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.profileRow)
        // A toggle with its name, on or off (§5.14): "Battle game, toggle, on".
        .accessibilityAddTraits(isOn ? [.isToggle, .isSelected] : .isToggle)
    }
}
#endif
