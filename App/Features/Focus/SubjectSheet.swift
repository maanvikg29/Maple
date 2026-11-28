import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The subject sheet (F2 Study record), from the start screen's subject line, the receipt's, and a session's detail in
/// History.
///
/// - **Choosing:** "New subject" at the top takes a name (24 characters at most); adding it chooses it. At 8 subjects
///   the row reads "8 of 8 subjects". Under it are "No subject", then the member's subjects in their order, the current
///   one ticked. A tap chooses and closes the sheet.
/// - **Edit:** each name becomes a field (Return renames; a blank or taken name is put back), with a handle to reorder
///   and "Remove". A removed subject keeps its sessions in History and is no longer offered.
///
/// The sheet never ends or changes a session by itself: `onPick` gets the choice.
struct SubjectSheet: View {
    /// The subject ticked as the sheet opens; nil for "No subject".
    let selected: UUID?
    /// A subject, or nil for "No subject". The sheet closes itself afterwards.
    let onPick: (UUID?) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(SubjectStore.self) private var subjects

    @State private var isEditing = false
    /// The list's own edit mode, which shows the reorder handles; it follows `isEditing`.
    @State private var editMode = EditMode.inactive
    @State private var isAdding = false
    @State private var newName = ""
    /// Names being typed in Edit, by subject.
    @State private var drafts: [UUID: String] = [:]
    @State private var notice: String?
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case new
        case rename(UUID)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !isEditing {
                // Above the list, so the field is never under the keyboard however many subjects there are.
                newRow
                    .padding(.horizontal, theme.spacing.listMargin)
                divider
            }
            List {
                if isEditing {
                    ForEach(subjects.active) { subject in editRow(subject) }
                        .onMove { subjects.move(fromOffsets: $0, toOffset: $1) }
                    footnote(SubjectCopy.removedNote)
                } else {
                    if let notice { footnote(notice) }
                    if subjects.active.isEmpty {
                        footnote(SubjectCopy.hint)
                    } else {
                        pickRow(SubjectCopy.noSubject, isSelected: selected == nil) { pick(nil) }
                        ForEach(subjects.active) { subject in
                            pickRow(subject.name, isSelected: selected == subject.id) { pick(subject.id) }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, $editMode)
            .scrollDismissesKeyboard(.interactively)
            // The sheet already rises over the keyboard; the list mustn't make room for it a second time.
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // The Focus tab's own dark, a little see-through, as the end sheet's (F1-35).
        .presentationBackground {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                theme.colors.background.opacity(0.78)
            }
        }
        .onAppear {
            // With no subjects yet the sheet is for making the first one.
            if subjects.active.isEmpty { startAdding() }
        }
    }

    private var header: some View {
        HStack {
            Text(SubjectCopy.title)
                .font(MapleFont.sectionTitle)
                .foregroundStyle(theme.colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if !subjects.active.isEmpty {
                TextLink(isEditing ? SubjectCopy.done : SubjectCopy.edit, chevron: false) { toggleEditing() }
            }
        }
        .padding(.horizontal, theme.spacing.listMargin)
        .padding(.top, theme.spacing.xl)
        .padding(.bottom, theme.spacing.xs)
    }

    // MARK: Choosing

    private func pickRow(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(MapleFont.body)
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: theme.spacing.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .row(theme)
    }

    @ViewBuilder
    private var newRow: some View {
        if isAdding {
            HStack(spacing: theme.spacing.sm) {
                TextField(SubjectCopy.namePrompt, text: $newName)
                    .font(MapleFont.body)
                    .foregroundStyle(theme.colors.textPrimary)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($focus, equals: .new)
                    .onChange(of: newName) { _, typed in
                        if typed.count > Subject.nameLimit { newName = String(typed.prefix(Subject.nameLimit)) }
                    }
                    .onSubmit(addNew)
                if Subject.normalizedName(newName) != nil {
                    TextLink(SubjectCopy.addButton, chevron: false, action: addNew)
                }
            }
            .frame(minHeight: theme.spacing.minimumHitTarget)
        } else if subjects.canAdd {
            Button(action: startAdding) {
                HStack(spacing: theme.spacing.xs) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(SubjectCopy.new)
                        .font(MapleFont.body)
                }
                .foregroundStyle(theme.colors.textSecondary)
                .frame(maxWidth: .infinity, minHeight: theme.spacing.minimumHitTarget, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Text(SubjectCopy.full)
                .font(MapleFont.footnote)
                .foregroundStyle(theme.colors.textSecondary)
                .frame(maxWidth: .infinity, minHeight: theme.spacing.minimumHitTarget, alignment: .leading)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.colors.divider)
            .frame(height: theme.elevation.hairlineWidth)
            .padding(.horizontal, theme.spacing.listMargin)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(MapleFont.footnote)
            .foregroundStyle(theme.colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: theme.spacing.minimumHitTarget, alignment: .leading)
            .row(theme, separator: false)
    }

    // MARK: Edit

    private func editRow(_ subject: Subject) -> some View {
        HStack(spacing: theme.spacing.sm) {
            TextField(SubjectCopy.namePrompt, text: draft(for: subject))
                .font(MapleFont.body)
                .foregroundStyle(theme.colors.textPrimary)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($focus, equals: .rename(subject.id))
                .onSubmit { rename(subject) }
            Button(SubjectCopy.remove) { remove(subject) }
                .buttonStyle(.textLink(chevron: false))
                .accessibilityLabel("\(SubjectCopy.remove) \(subject.name)")
        }
        .frame(minHeight: theme.spacing.minimumHitTarget)
        .row(theme)
    }

    private func draft(for subject: Subject) -> Binding<String> {
        Binding(
            get: { drafts[subject.id] ?? subject.name },
            set: { drafts[subject.id] = String($0.prefix(Subject.nameLimit)) }
        )
    }

    // MARK: Actions

    private func pick(_ subject: UUID?) {
        onPick(subject)
        dismiss()
    }

    private func startAdding() {
        isAdding = true
        notice = nil
        focus = .new
    }

    private func addNew() {
        guard Subject.normalizedName(newName) != nil else {
            isAdding = !subjects.active.isEmpty ? false : isAdding
            focus = nil
            return
        }
        switch subjects.add(newName) {
        case .added(let subject), .existing(let subject):
            pick(subject.id)
        case .full:
            notice = SubjectCopy.full
            isAdding = false
        case .blank:
            break
        case nil:
            notice = SubjectCopy.unavailable
        }
    }

    private func toggleEditing() {
        if isEditing { commitDrafts() }
        isEditing.toggle()
        withAnimation(theme.motion.press) { editMode = isEditing ? .active : .inactive }
        isAdding = false
        notice = nil
        focus = nil
    }

    /// Return on a name: kept when it is a real, free name; put back otherwise.
    private func rename(_ subject: Subject) {
        if let typed = drafts[subject.id] { subjects.rename(subject.id, to: typed) }
        drafts[subject.id] = nil
        focus = nil
    }

    /// Done: every name still being typed is kept as Return would keep it.
    private func commitDrafts() {
        for (id, typed) in drafts { subjects.rename(id, to: typed) }
        drafts = [:]
    }

    private func remove(_ subject: Subject) {
        drafts[subject.id] = nil
        subjects.remove(subject.id)
        if subjects.active.isEmpty {
            isEditing = false
            editMode = .inactive
            startAdding()
        }
    }
}

private extension View {
    /// A row of the sheet's list: clear, on the sheet's own background, with the theme's divider.
    func row(_ theme: Theme, separator: Bool = true) -> some View {
        alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: theme.spacing.listMargin, bottom: 0, trailing: theme.spacing.listMargin))
            .listRowSeparatorTint(theme.colors.divider)
            .listRowSeparator(separator ? .visible : .hidden)
    }
}
