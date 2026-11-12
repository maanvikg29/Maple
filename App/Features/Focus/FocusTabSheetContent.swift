import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The Focus tab's sheets (`FocusTabState.sheet`, F1 design §5.9, §5.13–§5.16), shown by `FocusView`. Each sheet sets
/// its own detents and `surface2` background (spec §2.3). They read the tab's state, which `FocusView` puts in the
/// environment outermost so its sheets see it:
/// - `.blocking`: the selected preset's app list;
/// - `.preset(id)`: that preset's editor, or a new preset's for nil. A saved preset becomes the selected one, and a
///   deleted one stops being it; either way the turned length goes, so the start screen shows the preset's own;
/// - `.intention`: the tab's "What's this for?";
/// - `.saved`: as from Home, on the receipt's day when it gives one; `.streak`: as from Home.
struct FocusTabSheetContent: View {
    @Environment(CollectionStore.self) private var collection
    @Environment(FocusSessionStore.self) private var sessions
    @Environment(PresetStore.self) private var presets
    @Environment(AppSetStore.self) private var appSets
    @Environment(FocusTabState.self) private var tab
    @Environment(AppSettings.self) private var settings
    let sheet: FocusTabSheet

    var body: some View {
        @Bindable var tab = tab
        switch sheet {
        case .saved(let day, let earlier):
            SavedTodaySheet(day: day, isEarlierDay: earlier)
        case .streak:
            StreakSheet()
        case .blocking:
            if let preset = selectedPreset {
                BlockingSheet(preset: preset, sets: appSets.sets)
            }
        case .preset(let id):
            PresetEditorHost(draft: draft(for: id), onSaved: saved, onDeleted: deleted)
        case .intention:
            IntentionEntry(intention: $tab.intention)
        }
    }

    /// The start screen's own preset (Task 9's `FocusStartLines.preset`): Quick for the first session (P4).
    private var selectedPreset: FocusPreset? {
        FocusStartLines.preset(selected: tab.selectedPresetID, presets: presets.presets, lastUsedID: presets.lastUsedID,
                               isFirstSession: !settings.hasStartedFocus)
    }

    /// The Maple day of the store's trusted now: the day a looser strictness waits from.
    private var today: LocalDay {
        collection.snapshot.focusWindow(at: sessions.now, context: collection.context).day
    }

    private func draft(for id: UUID?) -> PresetDraft? {
        let count = presets.presets.count
        guard let id else { return PresetDraft(newOn: AppSet.distractionsID, presetCount: count, today: today) }
        guard let preset = presets.preset(id: id) else { return nil }
        #if DEBUG
        if let frame = PresetEditor.demoDraft(for: preset, presetCount: count, today: today, calendar: collection.context.calendar) {
            return frame
        }
        #endif
        return PresetDraft(editing: preset, presetCount: count, today: today)
    }

    private func saved(_ id: UUID) {
        tab.selectedPresetID = id
        tab.minutes = nil
    }

    private func deleted(_ id: UUID) {
        if tab.selectedPresetID == id { tab.selectedPresetID = nil }
        tab.minutes = nil
    }
}

/// Holds the editor's opening draft for as long as its sheet shows. Delete removes the preset from the store before the
/// sheet has slid away, and `draft(for:)` then finds nothing; the draft held here keeps the editor, and its background,
/// on screen until it has gone.
private struct PresetEditorHost: View {
    @State private var draft: PresetDraft?
    private let onSaved: (UUID) -> Void
    private let onDeleted: (UUID) -> Void

    /// - Parameter draft: The draft to open on. Only the first one counts; later ones (nil once deleted) are ignored.
    init(draft: PresetDraft?, onSaved: @escaping (UUID) -> Void, onDeleted: @escaping (UUID) -> Void) {
        _draft = State(initialValue: draft)
        self.onSaved = onSaved
        self.onDeleted = onDeleted
    }

    var body: some View {
        if let draft {
            PresetEditor(draft: draft, onSaved: onSaved, onDeleted: onDeleted)
        }
    }
}

extension Theme {
    /// Segment thumbs and selected chips on a sheet: their `surface2` is the sheet's own fill, so on it they would
    /// vanish. They lift with white instead, as `ScheduleEditor`'s segments do.
    var onSheet: Theme {
        var sheet = self
        sheet.colors.surface2 = .white.opacity(0.12)
        return sheet
    }
}
