import SwiftUI
import MapleCore
import MapleDesign
import MapleServices

/// The unlock celebration (spec §5.8), presented as a full-screen cover from Home's CTA, the waiting bud, a waiting
/// Herbarium tile or the focus summary. It opens what may be opened now (`CollectionStore.revealable(at:)`),
/// oldest first, or `startingWith` first.
///
/// - Tap to open, no hold. The full ritual for the first 3 reveals ever and always for uncommon, rare and legendary
///   leaves; the short one otherwise; a 0.6 s crossfade under Reduce Motion. One soft haptic per opening.
/// - Queues: "Next leaf", or "Open all {n}".
/// - "Place on your maple" marks the opened leaves revealed in the collection, so Home grafts them onto the tree,
///   then the cover fades out. The first morning reveal ends with the rarity consent sheet (D5).
/// - Nothing opens in wind-down or at night (except First steps); the cover then says "Opens in the morning".
///
/// The cover is transparent and fades itself in and out over `gentle`; present it without the slide:
///
/// ```swift
/// .fullScreenCover(isPresented: $revealing) { RevealFlow(startingWith: tappedID) }
/// // open it with: var t = Transaction(); t.disablesAnimations = true; withTransaction(t) { revealing = true }
/// ```
struct RevealFlow: View {
    /// Open this waiting leaf first; nil opens the queue in unlock order.
    var startingWith: String? = nil

    var body: some View {
        RevealFlowScreen(startingWith: requested)
            #if DEBUG
            .revealDemoMotion()
            #endif
            .presentationBackground(.clear)
    }

    private var requested: String? {
        #if DEBUG
        if startingWith == nil, let leaf = RevealDemoOptions.leaf { return leaf }
        #endif
        return startingWith
    }
}

/// Presents the reveal's transparent cover without the system slide (its content fades itself in over `gentle`):
/// `presentingRevealWithoutSlide { reveal = request }`.
@MainActor
func presentingRevealWithoutSlide(_ change: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, change)
}

private struct RevealFlowScreen: View {
    let startingWith: String?

    @Environment(CollectionStore.self) private var collection
    @Environment(LeafShareStore.self) private var shares
    @Environment(\.mapleClock) private var clock
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme
    @Environment(\.season) private var season
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var session: RevealSession?
    @State private var heldCount = 0
    @State private var isShown = false
    @State private var openings = 0
    @State private var asksConsent = false
    @State private var shareImages: [String: Image] = [:]
    @State private var placed: [LeafUnlock] = []
    /// DEBUG still frames: seconds after the tap, or into "Open all".
    @State private var stillTime: TimeInterval?
    @State private var stillOpenAllTime: TimeInterval?

    var body: some View {
        ZStack {
            if let session {
                if session.isOpeningAll {
                    openAll(session)
                        .transition(.opacity)
                } else if let item = session.current, let leaf = leaf(item.speciesID) {
                    RevealView(
                        leaf: leaf,
                        position: session.position,
                        ritual: session.ritual(at: session.index, reduceMotion: reduceMotion),
                        moment: moment(session),
                        footer: session.footer,
                        shareImage: shareImages[item.speciesID],
                        actions: RevealView.Actions(
                            open: open,
                            close: close,
                            next: next,
                            openAll: openAll,
                            place: place
                        )
                    )
                    .id(item.speciesID)
                    .transition(.opacity)
                }
            } else if heldCount > 0 {
                RevealHeldView(count: heldCount, onClose: close)
            }
        }
        .opacity(isShown ? 1 : 0)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: openings)
        .sheet(isPresented: $asksConsent, onDismiss: consentAnswered) {
            RarityConsentView(
                species: placed.last.flatMap { LeafCatalog.shared.species(id: $0.speciesID) },
                colourway: placed.last?.colourway ?? .summer,
                onInclude: { answerConsent(true) },
                onNotNow: { answerConsent(false) }
            )
            // .medium (D5); at accessibility text sizes the question and its buttons need the full height.
            .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium])
            .presentationBackground(theme.colors.surface2)
        }
        .task { start() }
    }

    // MARK: Pieces

    private func leaf(_ speciesID: String) -> RevealLeaf? {
        guard let unlock = collection.unlock(for: speciesID) else { return nil }
        return RevealLeaf(unlock: unlock, share: shares.share(for: speciesID))
    }

    private func moment(_ session: RevealSession) -> RevealMoment {
        if let stillTime, session.index == 0 { return .still(stillTime) }
        if let opened = session.currentOpenedAt { return .opened(at: opened) }
        return .closed
    }

    @ViewBuilder
    private func openAll(_ session: RevealSession) -> some View {
        let opening = session.openAllRange.map { range in range.compactMap { leaf(session.items[$0].speciesID) } } ?? []
        let opened = session.opened.compactMap(leaf)
        let moment: RevealMoment = if let stillOpenAllTime { .still(stillOpenAllTime) }
            else if let date = session.openAllAt { .opened(at: date) } else { .closed }
        RevealOpenAllView(opening: opening, opened: opened, moment: moment, onPlace: place)
    }

    // MARK: Flow

    private func start() {
        guard session == nil, heldCount == 0 else { return }
        let now = clock.now()
        let queue = collection.revealable(at: now)
        if queue.isEmpty {
            heldCount = collection.waiting.count
            if heldCount == 0 {
                dismissNow()
                return
            }
        } else {
            session = RevealSession(queue: queue, startingWith: startingWith, revealsBefore: collection.revealsOpened)
        }
        withAnimation(theme.motion.gentle) { isShown = true }
        #if DEBUG
        applyDemo()
        #endif
    }

    private func open() {
        guard var current = session, let item = current.current, current.open(at: Date()) else { return }
        session = current
        openings += 1
        prepareShareImage(item.speciesID, after: current.ritual(at: current.index, reduceMotion: reduceMotion).footerStart / 2)
    }

    private func next() {
        guard var current = session else { return }
        current.advance()
        withAnimation(theme.motion.gentle) { session = current }
    }

    private func openAll() {
        guard var current = session, current.openAll(at: Date()) else { return }
        withAnimation(theme.motion.gentle) { session = current }
        openings += 1
    }

    /// "Place on your maple": the opened leaves go onto the tree, then the cover fades (or the consent sheet
    /// follows the first morning reveal).
    private func place() {
        guard let session, !session.opened.isEmpty else { return finish() }
        let now = clock.now()
        placed = collection.openReveals(session.opened, at: now)
        announce(placed)
        if !placed.isEmpty, collection.phase(at: now) == .morning, collection.rarityConsent == .notAsked {
            asksConsent = true
        } else {
            finish()
        }
    }

    /// The close circle on a closed bud: anything already opened is placed; the rest keeps waiting.
    private func close() {
        if let session, !session.opened.isEmpty {
            place()
        } else {
            finish()
        }
    }

    private func answerConsent(_ included: Bool) {
        collection.setRarityConsent(included)
        asksConsent = false
    }

    private func consentAnswered() {
        // Asked once: closing the sheet without an answer counts as "Not now".
        if collection.rarityConsent == .notAsked { collection.setRarityConsent(false) }
        finish()
    }

    private func finish() {
        withAnimation(theme.motion.gentle) {
            isShown = false
        } completion: {
            dismissNow()
        }
    }

    private func dismissNow() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { dismiss() }
    }

    private func announce(_ leaves: [LeafUnlock]) {
        let names = leaves.compactMap { LeafCatalog.shared.species(id: $0.speciesID)?.displayName }
        guard !names.isEmpty else { return }
        AccessibilityNotification.Announcement("\(names.formatted(.list(type: .and))) placed on your maple.").post()
    }

    /// Renders the share card off the critical first frames of the ritual.
    private func prepareShareImage(_ speciesID: String, after delay: TimeInterval) {
        Task {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard shareImages[speciesID] == nil, let leaf = leaf(speciesID),
                  let date = collection.unlock(for: speciesID)?.date else { return }
            shareImages[speciesID] = RevealShareCard.image(leaf: leaf, pressedOn: date, season: season, theme: theme)
        }
    }

    #if DEBUG
    /// `-MapleDemoRevealAt`, `-MapleDemoRevealOpenAll` and `-MapleDemoRevealConsent`.
    private func applyDemo() {
        guard var current = session, let item = current.current else { return }
        let openAllAt = RevealDemoOptions.openAllAt
        let showsConsent = RevealDemoOptions.showsConsent
        guard let openAt = RevealDemoOptions.openAt ?? (openAllAt != nil || showsConsent ? 10 : nil) else { return }
        current.open(at: Date())
        stillTime = openAt
        prepareShareImage(item.speciesID, after: 0)
        if let openAllAt, current.openAll(at: Date()) {
            stillOpenAllTime = openAllAt
        }
        session = current
        if showsConsent {
            placed = current.opened.compactMap { collection.unlock(for: $0) }
            asksConsent = true
        }
    }
    #endif
}
