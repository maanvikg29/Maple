import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The Blocking sheet (F1 design §5.14), from the start screen's Blocking line and its "Choose apps" capsule: which list
/// this preset blocks (Distractions, Study apps or Bedtime), "Block these" or "Only these", the picker, the counter and
/// the footer. An empty selection is never saved over a full one, and no more than 50 apps rest across every list
/// (`BlockingSheetModel`, `AppSetStore.save`). Choosing another list also makes it the preset's on Save. Save is off
/// while it would change nothing, and an unchanged list is never saved again, so an expired one keeps "Some apps need
/// choosing again" until something is chosen.
///
/// F1 has no real picker: launches on the DEBUG preview blocker show `FakeAppPicker`; every other build says it can't
/// lock apps, where F1-paid puts Apple's picker. `.large`, with the counter and Save pinned at the bottom. The line
/// under the counter keeps its room whether or not it shows, so a tick that brings it moves nothing (§4.6), except at
/// accessibility sizes (`note(_:)`).
struct BlockingSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.mapleClock) private var clock
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(CollectionStore.self) private var collection
    @Environment(FocusSessionStore.self) private var sessions
    @Environment(PresetStore.self) private var presets
    @Environment(AppSetStore.self) private var appSets

    private let preset: FocusPreset
    @State private var setID: UUID
    @State private var mode: SelectionSummary.Mode
    #if DEBUG
    @State private var choice: PickerChoice
    #endif
    @State private var failure: String?

    /// - Parameters:
    ///   - preset: The preset whose list this edits.
    ///   - sets: The lists as saved, to open on the preset's own.
    init(preset: FocusPreset, sets: [AppSet]) {
        self.preset = preset
        let set = sets.first { $0.id == preset.appSetID } ?? sets.first { $0.id == AppSet.distractionsID } ?? sets.first
        _setID = State(initialValue: set?.id ?? AppSet.distractionsID)
        _mode = State(initialValue: set?.summary.mode ?? .blockThese)
        #if DEBUG
        _choice = State(initialValue: set.map { PickerChoice(data: $0.selection, summary: $0.summary) } ?? PickerChoice())
        #endif
    }

    var body: some View {
        let model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                lists
                    .padding(.top, theme.spacing.md)
                SegmentedCapsule(selection: $mode, options: [.blockThese, .onlyThese], size: .regular, fillsWidth: true) {
                    FocusSheetCopy.modeTitle($0)
                }
                .accessibilityLabel(Text(FocusSheetCopy.modeLabel))
                .padding(.top, theme.spacing.sm)
                if saved?.tokensExpired == true {
                    Text(SelectionText.needsChoosingAgain)
                        .font(MapleFont.footnote)
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(.top, theme.spacing.xs)
                }
                picker
                    .padding(.top, theme.spacing.lg)
                Text(FocusSheetCopy.footer)
                    .font(MapleFont.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, theme.spacing.md)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, theme.spacing.listMargin)
            .padding(.top, theme.spacing.lg)
            .padding(.bottom, theme.spacing.lg)
            // Selected chips and the segment thumb sit on `surface2`, the sheet's own fill: lifted, they show.
            .environment(\.theme, theme.onSheet)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom) {
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                // A cross-fade if a change is ever animated: the numeric roll animates a blur, and Focus motion is
                // transform and opacity only (§4.6).
                Text(model.counter.text)
                    .font(MapleFont.headline)
                    .foregroundStyle(theme.colors.textPrimary)
                    .contentTransition(.opacity)
                note(failure ?? model.note)
                Button(FocusSheetCopy.save, action: save)
                    .buttonStyle(.moonlight(dimmed: isQuietHours))
                    .disabled(!model.canSave)
                    .padding(.top, theme.spacing.xs)
            }
            .padding(.horizontal, theme.spacing.listMargin)
            .padding(.vertical, theme.spacing.xs)
        }
        .presentationDetents([.large])
        .presentationBackground(theme.colors.surface2)
        .onChange(of: mode) { failure = nil }
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .center, spacing: theme.spacing.sm) {
            Text(FocusCopy.chooseApps)
                .font(MapleFont.sectionTitle)
                .foregroundStyle(theme.colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button(FocusSheetCopy.close, systemImage: "xmark") { dismiss() }
                .buttonStyle(.iconCircle)
        }
        .padding(.trailing, -4)
    }

    /// Distractions · Study apps · Bedtime.
    private var lists: some View {
        ChipFlow(spacing: theme.spacing.xs, lineSpacing: 0) {
            ForEach(appSets.sets) { set in
                Chip(set.name, isSelected: set.id == setID) { select(set) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(FocusSheetCopy.listsLabel))
    }

    @ViewBuilder
    private var picker: some View {
        #if DEBUG
        if usesFakePicker {
            FakeAppPicker(choice: $choice)
        } else {
            unavailable
        }
        #else
        unavailable
        #endif
    }

    /// F1-paid: Apple's picker takes this place when the blocker is `.screenTime`.
    private var unavailable: some View {
        Text(FocusSheetCopy.pickerUnavailable)
            .font(MapleFont.body)
            .foregroundStyle(theme.colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The problem's line, a failed save, or the counter's limit note.
    ///
    /// Hidden copies of every line it can hold keep its room, so neither the counter above it nor the rows behind the
    /// bar move when one comes or goes, and the words cross-fade by opacity alone (§4.6). At accessibility sizes that
    /// room would be a quarter of the screen, taken from the list for a line that seldom shows, so there the line
    /// takes room only while it shows, at once: Save, at the bar's foot, stays where it is.
    @ViewBuilder
    private func note(_ line: String?) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            if let line { noteText(line) }
        } else {
            ZStack(alignment: .topLeading) {
                ForEach(Self.notes, id: \.self) { reserved in
                    noteText(reserved)
                        .hidden()
                        .accessibilityHidden(true)
                }
                FadingLine(line) { line in
                    if let line { noteText(line) }
                }
            }
        }
    }

    /// Every line the bar can show under the counter.
    private static let notes = [
        FocusSheetCopy.keepOneChosen, FocusSheetCopy.overLimit, FocusSheetCopy.onlyTheseNote, FocusSheetCopy.couldNotSave,
    ]

    private func noteText(_ line: String) -> some View {
        Text(line)
            .font(MapleFont.footnote)
            .foregroundStyle(theme.colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: The draft

    private var saved: AppSet? { appSets.set(id: setID) }

    /// The DEBUG preview blocker comes with the fake picker; nothing else in F1 can pick apps.
    private var usesFakePicker: Bool {
        #if DEBUG
        return sessions.blocking.capability == .preview
        #else
        return false
        #endif
    }

    /// What Save would store: the picker's choice in the chosen mode, or, with no picker, the list as saved in it.
    private var draft: SelectionSummary {
        #if DEBUG
        if usesFakePicker { return choice.summary(mode: mode) }
        #endif
        let summary = saved?.summary ?? SelectionSummary(mode: mode, apps: 0, sites: 0, categories: 0)
        return SelectionSummary(mode: mode, apps: summary.apps, sites: summary.sites, categories: summary.categories)
    }

    private var draftData: Data {
        #if DEBUG
        if usesFakePicker { return choice.data }
        #endif
        return saved?.selection ?? Data()
    }

    /// Whether Save would change the list itself. The fake picker compares its choice with the list's
    /// (`PickerChoice.isUnchanged`), because a list it didn't write (a seeded one) is stored in other bytes than the same
    /// choice would be; so an untouched expired list keeps "Some apps need choosing again".
    private var selectionChanged: Bool {
        guard let saved else { return true }
        #if DEBUG
        if usesFakePicker {
            return !choice.isUnchanged(from: saved.selection, summary: saved.summary, mode: mode)
        }
        #endif
        return draft != saved.summary || draftData != saved.selection
    }

    /// Another list for the preset is a change too.
    private var listChanged: Bool { setID != preset.appSetID }

    private var model: BlockingSheetModel {
        BlockingSheetModel(
            draft: draft, saved: saved?.summary ?? SelectionSummary(mode: .blockThese, apps: 0, sites: 0, categories: 0),
            others: appSets.sets.filter { $0.id != setID }.map(\.summary), isChange: listChanged || selectionChanged
        )
    }

    /// The primary capsule's dimmed variant from the evening on (D11).
    private var isQuietHours: Bool {
        switch collection.phase(at: clock.now()) {
        case .evening, .windDown, .night: true
        case .morning, .day: false
        }
    }

    // MARK: Actions

    /// Shows another list as it is saved, its id, mode and choice in one change, so the sheet never judges one list's
    /// choice against another (a false "Choose at least one app…" for a frame). Changes to the list before are dropped.
    private func select(_ set: AppSet) {
        guard set.id != setID else { return }
        failure = nil
        setID = set.id
        mode = set.summary.mode
        #if DEBUG
        choice = PickerChoice(data: set.selection, summary: set.summary)
        #endif
    }

    private func save() {
        if selectionChanged {
            switch appSets.save(selection: draftData, summary: draft, to: setID) {
            case .saved:
                break
            case .wouldEmpty:
                failure = FocusSheetCopy.keepOneChosen
                return
            case .overTokenLimit:
                failure = FocusSheetCopy.overLimit
                return
            case .unknownSet, .unavailable:
                failure = FocusSheetCopy.couldNotSave
                return
            }
        }
        if listChanged, var updated = presets.preset(id: preset.id) {
            updated.appSetID = setID
            presets.update(updated)
        }
        dismiss()
    }
}
