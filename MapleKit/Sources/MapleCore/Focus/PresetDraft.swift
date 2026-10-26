import Foundation
import MapleFocusCore

/// The preset editor's working copy (F1 design §5.13): what Save stores, and the rules the editor shows.
///
/// - An existing preset's strictness changes through `FocusPreset.changeStrictness`, run each time on the preset as
///   saved: a tighter level applies now, and a looser one from the next day ("Steady starts tomorrow"), however many
///   levels were tried before saving.
/// - A new preset takes any level at once: there is nothing looser to wait for.
/// - At most 6 presets, a name to save, and the last preset can't be deleted.
public struct PresetDraft: Sendable, Equatable {
    public private(set) var preset: FocusPreset
    public let isNew: Bool
    /// The Maple day the editor is open on, from which a looser level waits a day.
    public let today: LocalDay
    private let saved: FocusPreset?
    private let presetCount: Int

    /// Editing a saved preset; `presetCount` is how many presets the member has.
    public init(editing preset: FocusPreset, presetCount: Int, today: LocalDay) {
        self.preset = preset
        isNew = false
        self.today = today
        saved = preset
        self.presetCount = presetCount
    }

    /// A new preset, from "+": unnamed, "Start focus", 50 minutes, no break, Steady, on `appSetID`.
    public init(newOn appSetID: UUID?, presetCount: Int, today: LocalDay) {
        preset = FocusPreset(name: "", verb: .focus, minutes: 50, hasBreak: false, appSetID: appSetID)
        isNew = true
        self.today = today
        saved = nil
        self.presetCount = presetCount
    }

    public var title: String {
        isNew ? FocusCopy.newPreset : FocusSheetCopy.editPresetTitle
    }

    /// The name as typed, kept to 24 characters.
    public var name: String {
        get { preset.name }
        set { preset.name = String(newValue.prefix(FocusPreset.nameLimit)) }
    }

    public var verb: FocusVerb {
        get { preset.verb }
        set { preset.verb = newValue }
    }

    public var minutes: Int { preset.minutes }

    /// "50m", "1h 30m".
    public var lengthText: String { FocusTimeText.length(minutes: preset.minutes) }

    /// The longest length the stepper can show ("1h 10m"), whose room its value keeps so the minus never moves.
    public static let widestLengthText: String = {
        let lengths = stride(from: DialLayout.minimumMinutes, through: DialLayout.maximumMinutes, by: DialLayout.stepMinutes)
            .map { FocusTimeText.length(minutes: $0) }
        return lengths.max { $0.count < $1.count } ?? FocusTimeText.length(minutes: DialLayout.maximumMinutes)
    }()

    /// The Length stepper's VoiceOver value, in words (§4.9): "50 minutes", "1 hour, 30 minutes".
    public func spokenLength(locale: Locale) -> String {
        FocusTimeText.spokenLength(minutes: preset.minutes, locale: locale)
    }

    public var canShorten: Bool { preset.minutes > DialLayout.minimumMinutes }

    public var canLengthen: Bool { preset.minutes < DialLayout.maximumMinutes }

    /// 5 minutes shorter, never under 20.
    public mutating func shorten() {
        preset.minutes = DialLayout.stepped(preset.minutes, by: -1)
    }

    /// 5 minutes longer, never over 3 hours.
    public mutating func lengthen() {
        preset.minutes = DialLayout.stepped(preset.minutes, by: 1)
    }

    public var hasBreak: Bool {
        get { preset.hasBreak }
        set { preset.hasBreak = newValue }
    }

    public var appSetID: UUID? {
        get { preset.appSetID }
        set { preset.appSetID = newValue }
    }

    /// The level the member picked: today's, or the looser one waiting for tomorrow.
    public var chosenStrictness: Strictness {
        preset.pendingStrictness ?? preset.strictness
    }

    public mutating func choose(_ strictness: Strictness, calendar: Calendar) {
        guard let saved else {
            preset.strictness = strictness
            preset.pendingStrictness = nil
            preset.pendingFrom = nil
            return
        }
        var changed = saved
        changed.changeStrictness(to: strictness, on: today, calendar: calendar)
        preset.strictness = changed.strictness
        preset.pendingStrictness = changed.pendingStrictness
        preset.pendingFrom = changed.pendingFrom
    }

    /// "Steady starts tomorrow" while a looser level waits for the next day; nil otherwise.
    public var pendingLine: String? {
        guard let pending = preset.pendingStrictness, let from = preset.pendingFrom, from > today else { return nil }
        return FocusCopy.pendingLine(pending)
    }

    /// A saved preset, and never the last one.
    public var canDelete: Bool { !isNew && presetCount > 1 }

    /// A name; for a new preset, room for it (at most 6); for a saved one, something changed.
    public var canSave: Bool {
        guard FocusPreset.normalizedName(preset.name) != nil else { return false }
        return isNew ? presetCount < FocusPreset.maximumCount : preset != saved
    }
}
