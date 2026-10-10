import SwiftUI
import MapleCore
import MapleDesign

/// About Maple: what it is in one paragraph, the version, where the species list comes from, and the privacy line.
struct AboutView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ProfilePage("About") {
            VStack(alignment: .leading, spacing: 0) {
                Text("Maple grows a tree from your sleep. Keep a steady bedtime and wake on time, and you earn leaves: \(LeafCatalog.shared.species.count) real maple species, each one a milestone you keep. Every leaf grows on your maple, pressed in the season you earned it.")
                    .font(MapleFont.body)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                ProfileListGroup {
                    ProfileFactRow("Version", value: Self.version)
                    ProfileFactRow("Species", value: "\(LeafCatalog.shared.species.count) maples")
                }
                .padding(.top, theme.spacing.xl)

                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    Text("Your sleep, focus and screen data never leave your iPhone.")
                    Text("Species list: Plants of the World Online, Royal Botanic Gardens, Kew.")
                }
                .font(MapleFont.footnote)
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, theme.spacing.listMargin)
                .padding(.top, theme.spacing.sm)
            }
        }
    }

    /// "1.0 (1)" from the bundle.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty else { return short }
        return "\(short) (\(build))"
    }
}
