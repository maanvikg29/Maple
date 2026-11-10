import Foundation
import MapleCore
import Testing
@testable import MapleDesign

/// One sitting of the reveal (docs/design/spec.md §5.8): queue order, opening, "Next leaf", "Open all", what gets
/// placed, the ritual per leaf, and the words the reveal and consent sheet use.
@Suite("Reveal session")
struct RevealSessionTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func unlock(_ id: String, minutesAgo: Double = 60) -> LeafUnlock {
        LeafUnlock(speciesID: id, date: Self.now.addingTimeInterval(-minutesAgo * 60), season: .autumn, colourway: .autumn)
    }

    private var threeCommons: [LeafUnlock] {
        [unlock("davidii", minutesAgo: 90), unlock("triflorum", minutesAgo: 60), unlock("truncatum", minutesAgo: 30)]
    }

    // MARK: Queue

    @Test("The requested leaf opens first; the rest keep their order")
    func startingWith() {
        #expect(RevealSession.ordered(["a", "b", "c"], startingWith: "c") == ["c", "a", "b"])
        #expect(RevealSession.ordered(["a", "b", "c"], startingWith: "a") == ["a", "b", "c"])
        #expect(RevealSession.ordered(["a", "b", "c"], startingWith: "zz") == ["a", "b", "c"])
        #expect(RevealSession.ordered(["a", "b", "c"], startingWith: nil) == ["a", "b", "c"])
        let session = RevealSession(queue: threeCommons, startingWith: "triflorum", revealsBefore: 20)
        #expect(session.items.map(\.speciesID) == ["triflorum", "davidii", "truncatum"])
    }

    @Test("Tiers come from the reward table")
    func tiers() {
        let session = RevealSession(queue: [unlock("saccharum"), unlock("pentaphyllum")], revealsBefore: 0)
        #expect(session.items.map(\.tier) == [.firstSteps, .legendary])
    }

    @Test("An empty queue has nothing to open")
    func empty() {
        var session = RevealSession(queue: [], revealsBefore: 4)
        #expect(session.isEmpty)
        #expect(session.current == nil)
        let opened = session.open(at: Self.now)
        #expect(opened == false)
        #expect(session.opened.isEmpty)
    }

    // MARK: Opening

    @Test("Once Wind-down begins mid-sitting, closed buds stay closed; what was opened is still placed")
    func phaseBoundary() {
        var session = RevealSession(queue: threeCommons, revealsBefore: 20)
        let evening: Set<String> = ["davidii", "triflorum", "truncatum"]
        #expect(session.mayOpen(openable: evening))
        #expect(!session.mayOpen(openable: []))
        session.open(at: Self.now)
        // The bud on screen is open, so a tap opens nothing more; "Open all" would open the other two.
        #expect(session.mayOpen(openable: []))
        #expect(session.mayOpen(all: true, openable: evening))
        #expect(!session.mayOpen(all: true, openable: []))
        session.advance()
        #expect(!session.mayOpen(openable: []))
        #expect(session.unopened.map(\.speciesID) == ["triflorum", "truncatum"])
        #expect(session.opened == ["davidii"])
    }

    @Test("A tap opens the current leaf once; the haptic plays once")
    func openOnce() {
        var session = RevealSession(queue: threeCommons, revealsBefore: 20)
        #expect(!session.isCurrentOpen)
        let first = session.open(at: Self.now)
        #expect(first)
        #expect(session.isCurrentOpen)
        #expect(session.currentOpenedAt == Self.now)
        let second = session.open(at: Self.now.addingTimeInterval(1))
        #expect(second == false)
        #expect(session.currentOpenedAt == Self.now)
        #expect(session.opened == ["davidii"])
    }

    @Test("While more wait the footer is Next leaf and Open all 3; the last one places")
    func footerAndNext() {
        var session = RevealSession(queue: threeCommons, revealsBefore: 20)
        #expect(session.position?.index == 1)
        #expect(session.position?.count == 3)
        #expect(session.footer == .next(total: 3))
        session.advance()
        #expect(session.index == 0, "Next leaf needs the current one open")
        session.open(at: Self.now)
        session.advance()
        #expect(session.index == 1)
        #expect(session.position?.index == 2)
        #expect(!session.isCurrentOpen)
        session.open(at: Self.now)
        session.advance()
        session.open(at: Self.now)
        #expect(session.index == 2)
        #expect(session.footer == .place)
        session.advance()
        #expect(session.index == 2)
        #expect(session.opened == ["davidii", "triflorum", "truncatum"])
    }

    @Test("A single leaf has no position and places straight away")
    func single() {
        let session = RevealSession(queue: [unlock("rubrum")], revealsBefore: 2)
        #expect(session.position == nil)
        #expect(session.footer == .place)
    }

    @Test("Open all opens every remaining bud at once and leaves Place on your maple")
    func openAll() {
        var session = RevealSession(queue: threeCommons, revealsBefore: 20)
        let early = session.openAll(at: Self.now)
        #expect(early == false, "the first leaf opens by tap")
        session.open(at: Self.now)
        #expect(session.remaining.map(\.speciesID) == ["triflorum", "truncatum"])
        let all = session.openAll(at: Self.now.addingTimeInterval(4))
        #expect(all)
        #expect(session.isOpeningAll)
        #expect(session.openAllRange == 1..<3)
        #expect(session.openAllAt == Self.now.addingTimeInterval(4))
        #expect(session.opened == ["davidii", "triflorum", "truncatum"])
        #expect(session.footer == .place)
        let again = session.openAll(at: Self.now)
        #expect(again == false, "only once")
        session.advance()
        #expect(session.index == 0, "Next leaf does nothing once everything is open")
    }

    @Test("Placing after Next leaf and Open all places only what was opened, in queue order")
    func placesOpenedOnly() {
        var session = RevealSession(queue: threeCommons, revealsBefore: 20)
        session.open(at: Self.now)
        session.advance()
        #expect(session.opened == ["davidii"], "the close circle on the second bud places only the first")
    }

    /// Review finding "share-card-render-after-moving-on".
    @Test("A share card is worth rendering only while its leaf is on screen, open, outside Open all")
    func shareCardMoment() {
        var session = RevealSession(queue: threeCommons, revealsBefore: 20)
        #expect(!session.isShowingOpened("davidii"), "still a closed bud")
        session.open(at: Self.now)
        #expect(session.isShowingOpened("davidii"))
        session.advance()
        #expect(!session.isShowingOpened("davidii"), "the member moved on to the next leaf")
        #expect(!session.isShowingOpened("triflorum"), "the next bud is still closed")
        session.open(at: Self.now)
        #expect(session.isShowingOpened("triflorum"))
        session.openAll(at: Self.now)
        #expect(!session.isShowingOpened("triflorum"), "Open all shows the row, not the card")
    }

    // MARK: Rituals

    @Test("The full ritual covers the first 3 reveals ever, counting this sitting")
    func ritualCountsSitting() {
        let session = RevealSession(queue: threeCommons, revealsBefore: 1)
        #expect(session.ritual(at: 0, reduceMotion: false) == .full)
        #expect(session.ritual(at: 1, reduceMotion: false) == .full)
        #expect(session.ritual(at: 2, reduceMotion: false) == .short)
        #expect(session.ritual(at: 2, reduceMotion: true) == .crossfade)
    }

    @Test("A legendary leaf gets the full ritual however many came before")
    func legendaryFull() {
        let session = RevealSession(queue: [unlock("davidii"), unlock("pentaphyllum")], revealsBefore: 90)
        #expect(session.ritual(at: 0, reduceMotion: false) == .short)
        #expect(session.ritual(at: 1, reduceMotion: false) == .full)
    }

    // MARK: Words

    @Test("The Sugar maple's reveal says what it was earned for, from the reward table")
    func sugarMapleWords() throws {
        let leaf = try #require(RevealLeaf(unlock: unlock("saccharum"), share: .notEnoughMembers(soFar: nil)))
        #expect(leaf.species.common == "Sugar maple")
        #expect(leaf.tier == .firstSteps)
        #expect(leaf.categoryName == "First leaf")
        #expect(leaf.earnedLine == "For planting your maple")
        #expect(RevealLeaf(unlock: unlock("not-a-maple"), share: .loading) == nil)
    }

    @Test("Unnamed species show their series under the scientific name")
    func seriesLine() {
        #expect(RevealText.series("Macrantha") == "Series Macrantha")
        #expect(RevealText.series("Unplaced") == "Not placed in a series")
        #expect(RevealText.series("") == "Not placed in a series")
    }

    @Test("Scientific names are spoken as Latin")
    func latin() {
        let name = RevealText.latin("Acer saccharum")
        #expect(name.runs.allSatisfy { $0.languageIdentifier == "la" })
    }

    @Test("The consent sheet asks the spec's question, with no exclamation and no blame")
    func consentCopy() {
        #expect(RarityConsentView.title == "Help show how rare each leaf is?")
        #expect(RarityConsentView.message.hasSuffix("No account, no device ID, no health data."))
        #expect(!RarityConsentView.message.contains("!"))
    }

    @Test("The Apple Health primer says what Maple reads and that it stays on the iPhone, in two sentences")
    func healthPrimerCopy() {
        let message = HealthPrimerView.message
        #expect(message.split(separator: ".").count == 2)
        #expect(message.contains("Apple Health") && message.contains("sleep"))
        #expect(message.hasSuffix("It stays on your iPhone."))
        #expect(!message.contains("!") && !HealthPrimerView.title.contains("!"))
        #expect(HealthPrimerView.continueTitle == "Continue")
        #expect(HealthPrimerView.notNowTitle == "Not now")
    }
}
