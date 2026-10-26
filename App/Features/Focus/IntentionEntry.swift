import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// Intention entry (F1 design §5.16), from the start screen's "What's this for?": one line above the keyboard (at most
/// 60 characters), with the last 3 distinct intentions as chips above it, those carried forward from "Partly" or
/// "Not yet" first (§5.8). Return saves it, a chip saves itself, and clearing the field removes the intention at once.
/// It stays the Focus tab's (`FocusTabState.intention`) until a session starts, which saves it to `session-notes.json`
/// (F1-19). A short sheet that fits what it holds, focused as it opens so it sits on the keyboard.
struct IntentionEntry: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(SessionNotesStore.self) private var notes
    @Environment(FocusSessionStore.self) private var sessions
    @Binding private var intention: String?
    @State private var draft: IntentionDraft
    /// The content's measured height, which the sheet's detent follows.
    @State private var height: CGFloat = 132
    @FocusState private var isFocused: Bool

    init(intention: Binding<String?>) {
        _intention = intention
        _draft = State(initialValue: IntentionDraft(intention.wrappedValue))
    }

    var body: some View {
        let chips = RecentIntentions.chips(notes.entries(reflections: sessions.reflections))
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            if !chips.isEmpty {
                ChipFlow(spacing: theme.spacing.xs, lineSpacing: 0) {
                    ForEach(chips, id: \.self) { chip in
                        Chip(chip, isSelected: draft.saved == chip) { choose(chip) }
                    }
                }
            }
            field
        }
        .padding(.horizontal, theme.spacing.listMargin)
        .padding(.top, theme.spacing.lg)
        .padding(.bottom, theme.spacing.sm)
        .environment(\.theme, theme.onSheet)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height + theme.spacing.xs)])
        .presentationBackground(theme.colors.surface2)
        .onAppear { isFocused = true }
    }

    /// One line, which wraps at accessibility sizes so the words never scroll out of sight; there Return arrives as a
    /// newline, which `IntentionDraft` drops and treats as Return.
    private var field: some View {
        HStack(spacing: 0) {
            TextField(FocusCopy.intentionPrompt, text: Binding {
                draft.text
            } set: { typed in
                let pressedReturn = draft.type(typed)
                if draft.isCleared { intention = nil }
                if pressedReturn { save() }
            }, axis: dynamicTypeSize.isAccessibilitySize ? .vertical : .horizontal)
            .font(MapleFont.body)
            .foregroundStyle(theme.colors.textPrimary)
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .focused($isFocused)
            .onSubmit(save)
            if !draft.text.isEmpty {
                Button(FocusSheetCopy.clearIntention, systemImage: "xmark") {
                    draft.type("")
                    intention = nil
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.colors.textSecondary)
                .frame(minWidth: theme.spacing.minimumHitTarget, minHeight: theme.spacing.minimumHitTarget)
                .contentShape(Rectangle())
            }
        }
        .padding(.leading, theme.spacing.md)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? theme.spacing.xs : 0)
        .frame(minHeight: theme.spacing.minimumHitTarget + theme.spacing.xs)
        .background {
            RoundedRectangle(cornerRadius: theme.radius.tile, style: .continuous)
                .fill(theme.colors.chipFill)
                .overlay {
                    RoundedRectangle(cornerRadius: theme.radius.tile, style: .continuous)
                        .strokeBorder(theme.colors.divider, lineWidth: 1)
                }
        }
    }

    /// Return: the trimmed text, or no intention for a blank field.
    private func save() {
        intention = draft.saved
        dismiss()
    }

    private func choose(_ chip: String) {
        draft.type(chip)
        save()
    }
}
