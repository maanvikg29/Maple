import Foundation
import Testing
@testable import MapleDesign

/// The no-sleep hint's copy (spec §1 rules 7 and 8: Home lines are one line of 7 words or fewer, never blame).
@Suite("No sleep from Apple Health hint")
struct NoSleepHintTests {
    private func words(_ line: String) -> Int {
        line.split(separator: " ").count
    }

    @Test("Home's two lines fit Home's copy rules; Privacy carries the whole sentence")
    func copy() {
        #expect(words(NoSleepHintCopy.title) <= 7)
        #expect(words(NoSleepHintCopy.advice) <= 7)
        #expect(NoSleepHintCopy.full == "No sleep from Apple Health yet. Wear your Apple Watch to bed, or turn on Sleep in the Health app.")
        #expect(NoSleepHintCopy.full.hasPrefix(NoSleepHintCopy.title))
        for line in [NoSleepHintCopy.title, NoSleepHintCopy.advice, NoSleepHintCopy.full] {
            #expect(!line.contains("!"))
            #expect(!line.lowercased().contains("missed"))
        }
    }
}
