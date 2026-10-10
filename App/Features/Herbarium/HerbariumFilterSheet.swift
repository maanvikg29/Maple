import SwiftUI
import MapleCore
import MapleDesign

/// The Filter sheet (spec §5.4, `.medium`): region chips, autumn-colour dots, leaf-form chips, three toggles and
/// "Reset". Changes apply at once; the filter circle's badge counts them.
struct HerbariumFilterSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var filters: HerbariumFilters

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Filter")
                        .font(MapleFont.sectionTitle)
                        .foregroundStyle(theme.colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    TextLink("Reset", chevron: false) {
                        withAnimation(reduceMotion ? nil : theme.motion.gentle) { filters = HerbariumFilters() }
                    }
                    .disabled(!filters.isActive)
                    .opacity(filters.isActive ? 1 : 0.5)
                }

                group("Region") {
                    ForEach(LeafSpecies.Region.allCases, id: \.self) { region in
                        FilterChip(region.displayName, isSelected: filters.regions.contains(region)) {
                            filters.regions.formSymmetricDifference([region])
                        }
                    }
                }
                group("Autumn colour") {
                    ForEach(LeafSpecies.AutumnColor.allCases, id: \.self) { colour in
                        FilterChip(colour.displayName, dot: colour.color, isSelected: filters.autumnColours.contains(colour)) {
                            filters.autumnColours.formSymmetricDifference([colour])
                        }
                    }
                }
                group("Leaf form") {
                    ForEach(LeafSpecies.Form.allCases, id: \.self) { form in
                        FilterChip(form.displayName, isSelected: filters.forms.contains(form)) {
                            filters.forms.formSymmetricDifference([form])
                        }
                    }
                }

                VStack(spacing: 0) {
                    toggle("Evergreen only", isOn: $filters.evergreenOnly)
                    divider
                    toggle("Approximate drawings only", isOn: $filters.approximateOnly)
                    divider
                    toggle("Earnable now only", isOn: $filters.earnableNowOnly)
                }
                .padding(.top, theme.spacing.lg)
            }
            .padding(.horizontal, theme.spacing.listMargin)
            .padding(.top, theme.spacing.xl)
            .padding(.bottom, theme.spacing.lg)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.colors.surface2)
        .presentationDragIndicator(.visible)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxs) {
            Text(title)
                .font(MapleFont.contextEmphasis)
                .foregroundStyle(theme.colors.textSecondary)
                .accessibilityAddTraits(.isHeader)
            ChipFlow(spacing: 8, lineSpacing: 0) { content() }
        }
        .padding(.top, theme.spacing.lg)
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(MapleFont.body)
                .foregroundStyle(theme.colors.textPrimary)
        }
        .tint(theme.colors.primaryFillBottom)
        .frame(minHeight: theme.spacing.row)
        .sensoryFeedback(.selection, trigger: isOn.wrappedValue)
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.colors.divider)
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }
}
