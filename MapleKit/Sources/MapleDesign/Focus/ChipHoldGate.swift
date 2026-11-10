import Foundation

/// Whether a tap on a preset chip selects it (F1 design §4.5, §5.13). Holding a chip opens its editor, and the lift
/// that ends the hold can arrive as an ordinary tap; it must not also select the chip, which would reset a turned dial.
/// `PresetChips` keeps one in its state. VoiceOver's "Edit preset" action is not a hold, so it never sets one.
nonisolated public struct ChipHoldGate: Sendable, Equatable {
    /// The chip a held finger opened the editor from, until its lift has come.
    private var heldChip: UUID?

    public init() {}

    /// A held finger opened the editor for this chip.
    public mutating func held(_ id: UUID) {
        heldChip = id
    }

    /// A tap on a chip. False for the lift that ends that chip's hold, which is swallowed once; true otherwise.
    public mutating func tap(_ id: UUID) -> Bool {
        defer { heldChip = nil }
        return heldChip != id
    }

    /// The editor has closed: any lift has come by now, so the next tap selects, whatever happened to the last.
    public mutating func editorClosed() {
        heldChip = nil
    }
}
