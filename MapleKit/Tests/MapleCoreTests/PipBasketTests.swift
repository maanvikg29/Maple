import Foundation
import Testing
@testable import MapleCore

@Suite("Pip collects leaves in his basket while a session runs")
struct PipBasketTests {
    private let times = stride(from: 0.0, through: 60, by: 1.0 / 30).map { $0 }

    @Test("The basket fills as the session goes on: a leaf or two at the start, heaped at the end, never more than it holds")
    func heapGrows() {
        #expect(PipBasket.heap(fraction: 0) == 1)
        #expect(PipBasket.heap(fraction: 1) == PipBasket.heapSlots)
        #expect(PipBasket.heap(fraction: 2) == PipBasket.heapSlots)
        #expect(PipBasket.heap(fraction: -1) == 1)
        #expect(PipBasket.heap(fraction: .nan) == 1)
        let counts = stride(from: 0.0, through: 1, by: 0.01).map { PipBasket.heap(fraction: $0) }
        // Only ever more, one leaf at a time.
        for (a, b) in zip(counts, counts.dropFirst()) {
            #expect(b == a || b == a + 1)
        }
    }

    @Test("Every few seconds a leaf comes down into the basket: it starts up in the canopy and ends in the basket's mouth")
    func catches() {
        // The owner, 28 Nov 2026: "where is the animation of pip collecting the leafs".
        var arrivals = 0
        var wasVisible = false
        for time in times {
            let now = PipBasket.catching(at: time)
            if let leaf = now.leaf {
                #expect(leaf.opacity >= 0 && leaf.opacity <= 1)
                #expect(leaf.y <= PipBasket.mouth.y + 1)
                wasVisible = true
            } else if wasVisible {
                arrivals += 1
                wasVisible = false
            }
        }
        #expect(arrivals >= 8)
        let starts = times.compactMap { PipBasket.catching(at: $0).leaf }.filter { $0.progress < 0.02 }
        let ends = times.compactMap { PipBasket.catching(at: $0).leaf }.filter { $0.progress > 0.98 }
        #expect(!starts.isEmpty && starts.allSatisfy { $0.y < PipBasket.mouth.y - 300 })
        #expect(!ends.isEmpty && ends.allSatisfy { abs($0.x - PipBasket.mouth.x) < 12 && abs($0.y - PipBasket.mouth.y) < 12 })
    }

    @Test("Pip leans toward the leaf as it comes, and the basket dips when it lands; both small, and both settle back")
    func leansAndDips() {
        let all = times.map { PipBasket.catching(at: $0) }
        #expect(all.allSatisfy { $0.lean >= 0 && $0.lean <= 0.1 && $0.dip >= 0 && $0.dip <= 10 })
        #expect(all.map(\.lean).max()! > 0.04)
        #expect(all.map(\.dip).max()! > 4)
        #expect(all.contains { $0.lean == 0 && $0.dip == 0 })
        // Smooth: never a jump between frames.
        for (a, b) in zip(all, all.dropFirst()) {
            #expect(abs(a.lean - b.lean) < 0.02 && abs(a.dip - b.dip) < 2.5)
        }
        #expect(PipBasket.catching(at: .nan) == PipBasket.catching(at: 0))
    }
}
