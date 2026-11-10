#if DEBUG
import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// DEBUG only: Settings › Ledger inspector (F1 design §7.7). Every ledger event, newest first, by kind, session,
/// writer and sequence number, source and wall time, and no content: no preset name, intention or length
/// (`LedgerInspection`). It reads the whole ledger when it opens, and again on "Read again".
struct LedgerInspector: View {
    @Environment(\.theme) private var theme
    @Environment(FocusSessionStore.self) private var sessions
    @State private var page: LedgerInspection.Page?
    @State private var hasRead = false

    var body: some View {
        ProfilePage("Ledger inspector") {
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                Text(summary)
                    .font(MapleFont.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                TextLink("Read again", chevron: false) { read() }
            }
            if let page, !page.rows.isEmpty {
                ProfileListGroup {
                    ForEach(page.rows) { row in
                        LedgerEventRow(row: row)
                    }
                }
            }
        }
        .onAppear {
            if !hasRead { read() }
        }
    }

    private var summary: String {
        guard hasRead else { return "Reading the ledger…" }
        return page?.summary ?? "The ledger can't be read until the iPhone is unlocked."
    }

    private func read() {
        page = sessions.ledgerInspection(calendar: .autoupdatingCurrent)
        hasRead = true
    }
}

/// One event: its kind and wall time, then its session, writer and sequence number, and source.
private struct LedgerEventRow: View {
    @Environment(\.theme) private var theme
    let row: LedgerInspection.Row

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing.sm) {
                Text(row.kind)
                    .font(MapleFont.body)
                    .foregroundStyle(theme.colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(row.time)
                    .font(MapleFont.tileMeta)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            Text(row.detail)
                .font(MapleFont.footnote)
                .monospacedDigit()
                .foregroundStyle(theme.colors.textSecondary)
        }
        .padding(.horizontal, theme.spacing.listMargin)
        .padding(.vertical, theme.spacing.sm)
        .frame(minHeight: theme.spacing.row, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
#endif
