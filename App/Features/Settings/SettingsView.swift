import SwiftUI
import MapleDesign

struct SettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Privacy") {
                    Label("Your data stays on this iPhone", systemImage: "lock.shield")
                    Label("Export and delete arrive in M7", systemImage: "square.and.arrow.up")
                        .foregroundStyle(theme.colors.textSecondary)
                }
                .listRowBackground(theme.colors.surface)

                Section("Developer") {
                    NavigationLink("Design system") {
                        DesignSystemView()
                    }
                }
                .listRowBackground(theme.colors.surface)

                Section {
                    LabeledContent("Version", value: appVersion)
                }
                .listRowBackground(theme.colors.surface)
            }
            .mapleBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .preferredColorScheme(.dark)
}
