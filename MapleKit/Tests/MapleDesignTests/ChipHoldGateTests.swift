import Foundation
import Testing
@testable import MapleDesign

/// Holding a preset chip opens its editor; the lift that ends the hold must not also select the chip (F1 design §4.5,
/// §5.13), or opening and closing the editor would reset a turned dial.
@Suite("Preset chip hold")
struct ChipHoldGateTests {
    private let study = UUID()
    private let quick = UUID()

    @Test("A plain tap selects, every time")
    func tap() {
        var gate = ChipHoldGate()
        let first = gate.tap(study)
        let second = gate.tap(study)
        #expect(first && second)
    }

    @Test("The lift that ends a hold doesn't select; the next tap does")
    func liftAfterHold() {
        var gate = ChipHoldGate()
        gate.held(study)
        let lift = gate.tap(study)
        let next = gate.tap(study)
        #expect(!lift)
        #expect(next)
    }

    @Test("A lift that never arrived as a tap swallows nothing once the editor has closed")
    func editorClosed() {
        var gate = ChipHoldGate()
        gate.held(study)
        gate.editorClosed()
        let tap = gate.tap(study)
        #expect(tap)
    }

    @Test("Only the held chip's lift is swallowed")
    func otherChip() {
        var gate = ChipHoldGate()
        gate.held(study)
        let other = gate.tap(quick)
        let held = gate.tap(study)
        #expect(other && held)
    }
}
