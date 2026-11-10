import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The preset editor (F1 design §5.13), from holding a chip or from "+": the name (up to 24 characters), the start
/// button's words, the length (the dial's 20 minutes to 3 hours, in 5-minute steps), the break, the app list and the
/// strictness, each level with its honest line. A tighter level applies now and a looser one from the next day,
/// with the line "Steady starts tomorrow" (`PresetDraft`). Delete is the last row, and the last preset has none.
/// `.large`, with Close at the top and Save pinned at the bottom, as `ScheduleEditor` is.
///
/// Delete and its confirmation are never red (spec §1, principle 8), and "Steady starts tomorrow" keeps its room
/// whether or not it shows, so choosing a level moves nothing (§4.6); at accessibility sizes the sheet grows below the
/// rows instead (`pendingLine`), and the start button's words are radio rows (`ChoiceRow`), as the break is from
/// xxLarge text, where its capsule can't hold its words.
struct PresetEditor: View {
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.mapleClock) private var clock
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(CollectionStore.self) private var collection
    @Environment(PresetStore.self) private var presets
    @Environment(AppSetStore.self) private var appSets

    @State private var draft: PresetDraft
    /// What the name field shows: written back as the draft keeps it, so a 25th character never appears.
    @State private var nameText: String
    @State private var asksToDelete = false
    @State private var failure: String?
    @FocusState private var nameIsFocused: Bool
    private let onSaved: (UUID) -> Void
    private let onDeleted: (UUID) -> Void

    /// - Parameters:
    ///   - onSaved: The preset saved or added, for the start screen to select.
    ///   - onDeleted: The preset deleted, for the start screen to stop selecting.
    init(draft: PresetDraft, onSaved: @escaping (UUID) -> Void, onDeleted: @escaping (UUID) -> Void) {
        _draft = State(initialValue: draft)
        _nameText = State(initialValue: draft.name)
        self.onSaved = onSaved
        self.onDeleted = onDeleted
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                fields
                    .padding(.top, theme.spacing.md)
                strictness
                    .padding(.top, theme.spacing.lg)
                if draft.canDelete {
                    deleteRow
                        .padding(.top, theme.spacing.md)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, theme.spacing.listMargin)
            .padding(.top, theme.spacing.lg)
            .padding(.bottom, theme.spacing.lg)
            // Selected chips and segments sit on `surface2`, the sheet's own fill: lifted, they show.
            .environment(\.theme, theme.onSheet)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: theme.spacing.xs) {
                if let failure {
                    Text(failure)
                        .font(MapleFont.footnote)
                        .foregroundStyle(theme.colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(FocusSheetCopy.save, action: save)
                    .buttonStyle(.moonlight(dimmed: isQuietHours))
                    .disabled(!draft.canSave)
            }
            .padding(.horizontal, theme.spacing.listMargin)
            .padding(.vertical, theme.spacing.xs)
        }
        .presentationDetents([.large])
        .presentationBackground(theme.colors.surface2)
        // No destructive role: it would paint the button red, and the question already says what it does.
        .confirmationDialog(FocusSheetCopy.deleteQuestion, isPresented: $asksToDelete, titleVisibility: .visible) {
            Button(FocusSheetCopy.deletePreset, action: delete)
            Button(FocusSheetCopy.cancel, role: .cancel) {}
        } message: {
            Text(FocusSheetCopy.deleteNote)
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .center, spacing: theme.spacing.sm) {
            Text(draft.title)
                .font(MapleFont.sectionTitle)
                .foregroundStyle(theme.colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button(FocusSheetCopy.close, systemImage: "xmark") { dismiss() }
                .buttonStyle(.iconCircle)
        }
        // The close circle's 44pt hit area overhangs the margin, so the glyph lines up with the content edge.
        .padding(.trailing, -4)
    }

    private var fields: some View {
        ProfileListGroup {
            ProfileSettingRow(FocusSheetCopy.nameTitle, stacked: true) {
                // One line, which wraps at accessibility sizes so the name never scrolls out of sight (§5.17), as the
                // intention's field does; there Return arrives as a newline, which `PresetDraft` drops and treats as Return.
                TextField(
                    FocusSheetCopy.nameTitle, text: $nameText, axis: dynamicTypeSize.isAccessibilitySize ? .vertical : .horizontal
                )
                    .font(MapleFont.body)
                    .foregroundStyle(theme.colors.textPrimary)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .focused($nameIsFocused)
                    .onChange(of: nameText) { _, typed in
                        let pressedReturn = draft.typeName(typed)
                        // The field's own text changes back, which SwiftUI always shows; a clamp left in the binding
                        // alone may not reach the field.
                        if draft.name != typed { nameText = draft.name }
                        if pressedReturn { nameIsFocused = false }
                    }
            }
            ProfileSettingRow(FocusSheetCopy.verbTitle, stacked: true, controlIsLabelled: false) {
                verbChoice
            }
            ProfileSettingRow(FocusSheetCopy.lengthTitle) {
                lengthStepper
            }
            ProfileSettingRow(
                FocusSheetCopy.breakTitle, detail: draft.hasBreak ? Text(FocusSheetCopy.breakNote) : nil, stacked: true,
                controlIsLabelled: false
            ) {
                breakChoice
            }
            ProfileSettingRow(FocusSheetCopy.appsTitle, detail: Text(appsLine), stacked: true, controlIsLabelled: false) {
                ChipFlow(spacing: theme.spacing.xs, lineSpacing: 0) {
                    ForEach(appSets.sets) { set in
                        Chip(set.name, isSelected: chosenSetID == set.id) { draft.appSetID = set.id }
                    }
                }
            }
        }
    }

    /// Minus and plus around the length ("50m"), in 5-minute steps; one adjustable element for VoiceOver, whose value
    /// is read in words ("50 minutes"), never "m". The value keeps the room of the widest length at every text size, so
    /// neither button moves as the length changes.
    private var lengthStepper: some View {
        HStack(spacing: 0) {
            Button(FocusSheetCopy.shorter, systemImage: "minus") { draft.shorten() }
                .buttonStyle(.iconCircle)
                .disabled(!draft.canShorten)
            ZStack {
                Text(PresetDraft.widestLengthText)
                    .hidden()
                // A cross-fade: the numeric roll would animate a blur, and Focus motion is transform and opacity only (§4.6).
                Text(draft.lengthText)
                    .foregroundStyle(theme.colors.textPrimary)
                    .contentTransition(.opacity)
                    .mapleAnimation(theme.motion.gentle, value: draft.minutes)
            }
            .font(MapleFont.headline.monospacedDigit())
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, theme.spacing.xs)
            Button(FocusSheetCopy.longer, systemImage: "plus") { draft.lengthen() }
                .buttonStyle(.iconCircle)
                .disabled(!draft.canLengthen)
        }
        .sensoryFeedback(.selection, trigger: draft.minutes)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(FocusSheetCopy.lengthTitle))
        .accessibilityValue(Text(draft.spokenLength(locale: locale)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: draft.lengthen()
            case .decrement: draft.shorten()
            @unknown default: break
            }
        }
    }

    /// The start button's words, as chips; at accessibility sizes, where a chip can't hold "Start a quick session" on
    /// its one line, as rows with a drawn radio whose words wrap in full.
    @ViewBuilder
    private var verbChoice: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(FocusVerb.allCases, id: \.self) { verb in
                    ChoiceRow(title: verb.startTitle, isChosen: draft.verb == verb) { draft.verb = verb }
                }
            }
            .sensoryFeedback(.selection, trigger: draft.verb)
        } else {
            ChipFlow(spacing: theme.spacing.xs, lineSpacing: 0) {
                ForEach(FocusVerb.allCases, id: \.self) { verb in
                    Chip(verb.startTitle, isSelected: draft.verb == verb) { draft.verb = verb }
                }
            }
        }
    }

    /// No break · One 5-minute break: a capsule; from xxLarge text, where its segments can no longer hold "One 5-minute
    /// break" even scaled down, rows with a drawn radio, as the start button's are at accessibility sizes.
    @ViewBuilder
    private var breakChoice: some View {
        if dynamicTypeSize >= .xxLarge {
            VStack(alignment: .leading, spacing: 0) {
                ForEach([false, true], id: \.self) { option in
                    ChoiceRow(title: FocusSheetCopy.breakOption(option), isChosen: draft.hasBreak == option) {
                        draft.hasBreak = option
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: draft.hasBreak)
        } else {
            SegmentedCapsule(selection: $draft.hasBreak, options: [false, true], size: .regular, fillsWidth: true) {
                FocusSheetCopy.breakOption($0)
            }
        }
    }

    /// Gentle, Steady and Locked, each with its honest line; "Steady starts tomorrow" under them while a looser
    /// level waits.
    private var strictness: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(FocusSheetCopy.strictnessTitle)
                .font(MapleFont.headline)
                .foregroundStyle(theme.colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ProfileListGroup {
                ForEach(Strictness.allCases, id: \.self) { level in
                    StrictnessRow(level: level, isChosen: draft.chosenStrictness == level) {
                        draft.choose(level, calendar: collection.context.calendar)
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: draft.chosenStrictness)
            pendingLine
        }
    }

    /// The line's room is held by hidden copies of every line it can show (only Gentle and Steady can wait), so it
    /// appearing or going moves nothing under the rows; the words cross-fade by opacity alone (§4.6). At accessibility
    /// sizes that room would be a blank screenful above Delete, so there the line takes room only while it shows, at
    /// once, and the sheet grows below the rows.
    @ViewBuilder
    private var pendingLine: some View {
        if dynamicTypeSize.isAccessibilitySize {
            if let line = draft.pendingLine { pendingText(line) }
        } else {
            ZStack(alignment: .topLeading) {
                ForEach([Strictness.gentle, .steady], id: \.self) { level in
                    pendingText(FocusCopy.pendingLine(level))
                        .hidden()
                        .accessibilityHidden(true)
                }
                FadingLine(draft.pendingLine) { line in
                    if let line { pendingText(line) }
                }
            }
        }
    }

    private func pendingText(_ line: String) -> some View {
        Text(line)
            .font(MapleFont.footnote)
            .foregroundStyle(theme.colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var deleteRow: some View {
        ProfileListGroup {
            Button {
                asksToDelete = true
            } label: {
                // Never red (spec §1, principle 8): the dialog says what it does.
                Text(FocusSheetCopy.deletePreset)
                    .font(MapleFont.body)
                    .foregroundStyle(theme.colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, theme.spacing.listMargin)
                    .padding(.vertical, theme.spacing.sm)
                    .frame(minHeight: theme.spacing.row)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.profileRow)
        }
    }

    /// The list the preset blocks; nil for a preset without one, which the start screen reads as "Choose apps to block".
    private var chosenSetID: UUID? { draft.appSetID }

    /// That list's counter ("6 apps · 1 site", "No apps chosen yet"), or "Some apps need choosing again".
    private var appsLine: String {
        let none = SelectionSummary(mode: .blockThese, apps: 0, sites: 0, categories: 0)
        guard let set = chosenSetID.flatMap({ appSets.set(id: $0) }) else {
            return SelectionText.counter(none, totalTokens: appSets.totalTokens).text
        }
        if set.tokensExpired { return SelectionText.needsChoosingAgain }
        return SelectionText.counter(set.summary, totalTokens: appSets.totalTokens).text
    }

    /// The primary capsule's dimmed variant from the evening on (D11).
    private var isQuietHours: Bool {
        switch collection.phase(at: clock.now()) {
        case .evening, .windDown, .night: true
        case .morning, .day: false
        }
    }

    // MARK: Actions

    private func save() {
        guard presets.isAvailable || presets.reloadIfUnavailable() else {
            failure = FocusSheetCopy.couldNotSave
            return
        }
        if draft.isNew {
            guard presets.add(draft.preset) else {
                failure = FocusSheetCopy.couldNotSave
                return
            }
        } else {
            // A reload can replace the defaults shown before the first unlock with the member's own presets.
            guard presets.preset(id: draft.preset.id) != nil else {
                failure = FocusSheetCopy.couldNotSave
                return
            }
            presets.update(draft.preset)
        }
        onSaved(draft.preset.id)
        dismiss()
    }

    private func delete() {
        let id = draft.preset.id
        guard presets.delete(id: id) else {
            failure = FocusSheetCopy.couldNotSave
            return
        }
        onDeleted(id)
        dismiss()
    }
}

/// One strictness level: a drawn radio, the name (Locked with its lock), and its honest line. Selecting it is one tap.
private struct StrictnessRow: View {
    @Environment(\.theme) private var theme
    let level: Strictness
    let isChosen: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(alignment: .top, spacing: theme.spacing.sm) {
                SelectionMark(isOn: isChosen)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                    HStack(spacing: theme.spacing.xxs) {
                        Text(FocusCopy.strictnessName(level))
                            .font(MapleFont.body)
                            .foregroundStyle(theme.colors.textPrimary)
                        if level == .locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.colors.textSecondary)
                                .accessibilityHidden(true)
                        }
                    }
                    Text(FocusCopy.strictnessLine(level))
                        .font(MapleFont.footnote)
                        .foregroundStyle(theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, theme.spacing.listMargin)
            .padding(.vertical, theme.spacing.sm)
            .frame(minHeight: theme.spacing.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.profileRow)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}

/// One of a few choices at accessibility sizes, where a chip's one line can't hold the words: a drawn radio and the
/// words, wrapping in full. Selecting it is one tap.
private struct ChoiceRow: View {
    @Environment(\.theme) private var theme
    let title: String
    let isChosen: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(alignment: .top, spacing: theme.spacing.sm) {
                SelectionMark(isOn: isChosen)
                    .padding(.top, theme.spacing.xxs)
                Text(title)
                    .font(MapleFont.body)
                    .foregroundStyle(isChosen ? theme.colors.textPrimary : theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, theme.spacing.xxs)
            .frame(minHeight: theme.spacing.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}

/// A drawn radio or checkbox. Spec §6.8 allows no checkmark symbol, so a choice is a filled shape inside its ring.
struct SelectionMark: View {
    enum Kind {
        case circle, square
    }

    @Environment(\.theme) private var theme
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 20
    let isOn: Bool
    var kind: Kind = .circle

    var body: some View {
        let side = min(size, 28)
        let stroke = isOn ? theme.colors.textPrimary : theme.colors.textSecondary
        Group {
            switch kind {
            case .circle:
                ZStack {
                    Circle().strokeBorder(stroke, lineWidth: 1.5)
                    if isOn { Circle().fill(theme.colors.textPrimary).padding(side * 0.25) }
                }
            case .square:
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(stroke, lineWidth: 1.5)
                    if isOn {
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(theme.colors.textPrimary)
                            .padding(side * 0.25)
                    }
                }
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Holding a preset chip opens its editor (F1 design §4.5, §5.13): a half-second press with a soft haptic, and the
    /// same as a VoiceOver action, "Edit preset".
    ///
    /// The press runs beside the chip's own tap, never instead of it: a tap shorter than half a second only selects.
    /// It ends without opening anything once the finger travels more than 10 points, so a drag that scrolls the chips
    /// (or the start screen at accessibility sizes) never opens the editor; the scroll view taking the touch cancels
    /// it too. The lift that ends a completed hold can still reach the chip as a tap, so `edit` is told the editor was
    /// opened by a hold, and the chip swallows that tap (`ChipHoldGate`).
    ///
    /// ```swift
    /// Chip(preset.name, isSelected: isSelected) { if gate.tap(preset.id) { select(preset) } }
    ///     .editsPresetOnHold { byHold in
    ///         if byHold { gate.held(preset.id) }
    ///         tab.sheet = .preset(preset.id)
    ///     }
    /// ```
    /// - Parameter edit: Opens the editor; `byHold` is true for a held finger, false for VoiceOver's action.
    func editsPresetOnHold(_ edit: @escaping (_ byHold: Bool) -> Void) -> some View {
        modifier(PresetChipHold(edit: edit))
    }
}

private struct PresetChipHold: ViewModifier {
    /// How long the press lasts, and how far the finger may travel during it before it stops being a hold.
    private static let seconds = 0.5
    private static let travel: CGFloat = 10

    @State private var holds = 0
    let edit: (_ byHold: Bool) -> Void

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                LongPressGesture(minimumDuration: Self.seconds, maximumDistance: Self.travel).onEnded { _ in
                    holds += 1
                    edit(true)
                }
            )
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: holds)
            .accessibilityAction(named: Text(FocusSheetCopy.editPreset)) { edit(false) }
    }
}

#if DEBUG
extension PresetEditor {
    /// DEBUG only: `-MapleDemoPresent preset -MapleDemoStrictness <level>` opens the editor as it looks just after
    /// choosing `<level>` on a Locked copy of the preset, unsaved, so a looser level shows "Steady starts tomorrow".
    /// Nothing is written to the store. Nil for any other launch.
    static func demoDraft(for preset: FocusPreset, presetCount: Int, today: LocalDay, calendar: Calendar) -> PresetDraft? {
        let options = DemoLaunchOptions.current
        guard options.focusSheet == .preset, let level = options.strictness else { return nil }
        var locked = preset
        locked.strictness = .locked
        locked.pendingStrictness = nil
        locked.pendingFrom = nil
        var draft = PresetDraft(editing: locked, presetCount: presetCount, today: today)
        draft.choose(level, calendar: calendar)
        return draft
    }
}
#endif
