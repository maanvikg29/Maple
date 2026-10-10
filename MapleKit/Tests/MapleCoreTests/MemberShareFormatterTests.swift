import Foundation
import Testing
@testable import MapleCore

@Suite("Member share formatter")
struct MemberShareFormatterTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let p: Double
        let lo: Double
        let hi: Double
        let expected: String
        var testDescription: String { "p \(p) [\(lo), \(hi)] → \(expected)" }
    }

    private static let en = Locale(identifier: "en_US")

    private func format(_ p: Double, _ lo: Double, _ hi: Double) -> String {
        MemberShareFormatter.format(percent: p, lower: lo, upper: hi, locale: Self.en)
    }

    // §5.7 item 6: every listed p, each with narrow and wide bounds.
    @Test("Spec edge values with narrow and wide bounds", arguments: [
        Case(p: 0.09, lo: 0.085, hi: 0.095, expected: "Under 0.1%"),
        Case(p: 0.09, lo: 0.08, hi: 0.10, expected: "Under 0.1%"),
        Case(p: 0.09, lo: 0.01, hi: 0.5, expected: "Under 0.5%"),
        Case(p: 0.1, lo: 0.09, hi: 0.11, expected: "0.1%"),
        Case(p: 0.1, lo: 0.02, hi: 0.4, expected: "Under 0.5%"),
        Case(p: 0.99, lo: 0.95, hi: 1.03, expected: "1.0%"),
        Case(p: 0.99, lo: 0.3, hi: 1.8, expected: "Under 2%"),
        Case(p: 1.0, lo: 0.9, hi: 1.1, expected: "1.0%"),
        Case(p: 1.0, lo: 0.2, hi: 2.5, expected: "Under 3%"),
        Case(p: 1.99, lo: 1.9, hi: 2.08, expected: "2.0%"),
        Case(p: 1.99, lo: 0.8, hi: 3.6, expected: "Under 5%"),
        Case(p: 2.0, lo: 1.9, hi: 2.1, expected: "2%"),
        Case(p: 2.0, lo: 0.9, hi: 4.0, expected: "Under 5%"),
        Case(p: 9.95, lo: 9.5, hi: 10.4, expected: "10%"),
        Case(p: 9.95, lo: 4, hi: 18, expected: "Under 20%"),
        Case(p: 49.9, lo: 48.5, hi: 51.3, expected: "50%"),
        Case(p: 49.9, lo: 5, hi: 95, expected: "Under 95%"),
        Case(p: 50, lo: 48.6, hi: 51.4, expected: "50%"),
        Case(p: 50, lo: 5, hi: 95, expected: "Over 5%"),
        Case(p: 99.4, lo: 98.9, hi: 99.8, expected: "99%"),
        Case(p: 99.4, lo: 99.1, hi: 99.7, expected: "Over 99%"),
        Case(p: 99.4, lo: 15, hi: 99.95, expected: "Over 15%"),
        Case(p: 99.6, lo: 99.3, hi: 99.9, expected: "Over 99%"),
        Case(p: 99.6, lo: 98.9, hi: 99.95, expected: "99%"),
        Case(p: 99.6, lo: 10, hi: 99.99, expected: "Over 10%"),
    ])
    func edges(_ c: Case) {
        #expect(format(c.p, c.lo, c.hi) == c.expected)
    }

    @Test("Steps round the bound outward to the next clean value")
    func steps() {
        #expect(MemberShareFormatter.steps == [0.1, 0.2, 0.5, 1, 2, 3, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 95, 99])
        #expect(MemberShareFormatter.stepUp(0.15) == 0.2)
        #expect(MemberShareFormatter.stepUp(3) == 3)
        #expect(MemberShareFormatter.stepUp(99.5) == 99)
        #expect(MemberShareFormatter.stepDown(14.9) == 10)
        #expect(MemberShareFormatter.stepDown(0.05) == 0.1)
    }

    @Test("Never shows 0% or 100%, whatever the counts")
    func neverZeroOrHundred() throws {
        for members in [1, 7, 100, 999, 1_000, 4_321, 12_400, 250_000] {
            for count in Set([0, 1, 2, 5, members / 1000, members / 100, members / 10, members / 2, members - 1, members]) where count >= 0 && count <= members {
                let estimate = try #require(ShareEstimate.wilson(count: count, members: members))
                let text = MemberShareFormatter.format(estimate, locale: Self.en)
                #expect(text != "0%" && text != "100%" && text != "0.0%", "\(count)/\(members) → \(text)")
                #expect(!text.hasPrefix("0%") && !text.contains("100"), "\(count)/\(members) → \(text)")
                #expect(text.hasSuffix("%"))
            }
        }
        #expect(format(0, 0, 0) == "Under 0.1%")
        #expect(format(100, 100, 100) == "Over 99%")
    }

    @Test("Wilson interval matches the textbook values")
    func wilson() throws {
        let tenOfHundred = try #require(ShareEstimate.wilson(count: 10, members: 100))
        #expect(abs(tenOfHundred.percent - 10) < 1e-9)
        #expect(abs(tenOfHundred.lower - 5.52) < 0.01)
        #expect(abs(tenOfHundred.upper - 17.44) < 0.01)

        let none = try #require(ShareEstimate.wilson(count: 0, members: 1_000))
        #expect(none.percent == 0)
        #expect(none.lower == 0)
        #expect(abs(none.upper - 0.383) < 0.001)
        #expect(MemberShareFormatter.format(none, locale: Self.en) == "Under 0.5%")

        let everyone = try #require(ShareEstimate.wilson(count: 1_000, members: 1_000))
        #expect(MemberShareFormatter.format(everyone, locale: Self.en) == "Over 99%")

        let typical = try #require(ShareEstimate.wilson(count: 2_728, members: 12_400))
        #expect(MemberShareFormatter.format(typical, locale: Self.en) == "22%")

        #expect(ShareEstimate.wilson(count: 3, members: 0) == nil)
        let clamped = try #require(ShareEstimate.wilson(count: 20, members: 10))
        #expect(clamped.percent == 100)
    }
}
