import Foundation
import MapleCore

/// What Home and the Focus start screen read from the Focus stores (F1 design §5.1, §5.10, F1-20): the start
/// screen's model, Home's `FocusStatus` built from that same model, the next hours leaf, and whether Maple can block.
/// Compose them at trusted time (`FocusSessionStore.now`), so Home and the Focus tab always agree.
///
/// ```swift
/// let status = focusStores.status(at: focusStores.sessions.now, collection: collection, settings: settings)   // Home
/// let model = focusStores.startScreen(preset: preset, minutes: tab.minutes ?? preset.minutes, at: sessions.now,
///                                     collection: collection, settings: settings)                             // the start screen
/// ```
extension FocusStores {
    /// Whether Maple can block now: the build can (`BlockingCapability.canBlock`), and the last refresh's probe found
    /// Screen Time allowing Maple.
    public var blockingStatus: FocusStatus.Blocking {
        guard sessions.blocking.capability.canBlock else { return .notInThisBuild }
        return sessions.probe.isAllowed ? .ready : .needsPermission
    }

    /// The next hours-saved leaf: the lowest locked rung, as the counters have it. It is the dial's centre leaf and
    /// the counts line's leaf.
    public func nextHoursLeaf(at date: Date, collection: CollectionStore) -> LeafProgress? {
        collection.progress(at: date)
            .filter { $0.category == .hoursSaved && $0.state == .locked }
            .min { $0.threshold < $1.threshold }
    }

    /// The start screen for `preset` at `minutes` (the dial's length, or the preset's own) at `now`. The Maple day and
    /// awake window are the ones a start now would freeze, so the strictness is the one `start(_:)` will use.
    public func startScreen(
        preset: FocusPreset, minutes: Int, at now: Date, collection: CollectionStore, settings: AppSettings,
        stage: StartScreenModel.Stage = .choosing, hasTurned: Bool = false, locale: Locale = .current
    ) -> StartScreenModel {
        let frozen = collection.snapshot.focusWindow(at: now, context: collection.context)
        let appSet = preset.appSetID.flatMap { appSets.set(id: $0) }
        return StartScreenModel(
            preset: preset, minutes: minutes, selection: appSet?.summary, expiredTokens: appSet?.tokensExpired ?? false,
            blocking: blockingStatus, isFirstSession: !settings.hasStartedFocus, phase: collection.phase(at: now),
            day: frozen.day, window: frozen.window, now: now, progress: nextHoursLeaf(at: now, collection: collection),
            displayToday: sessions.displayCredit(at: now).today, stage: stage, hasTurned: hasTurned, locale: locale,
            calendar: collection.context.calendar
        )
    }

    /// Today's focus for Home (§5.10): display credit, a running session's time left (`plannedEnd − now`, so it stays
    /// above 0 through a locked break and until the session ends), and Start for the last-used preset at its own
    /// length, built from the start screen's model so its readiness is the start screen's.
    public func status(at now: Date, collection: CollectionStore, settings: AppSettings) -> FocusStatus {
        let credit = sessions.displayCredit(at: now)
        let start = presets.lastUsed.map { preset in
            FocusStart(model: startScreen(preset: preset, minutes: preset.minutes, at: now, collection: collection, settings: settings))
        }
        return FocusStatus(
            savedTodaySeconds: credit.today, savedYesterdaySeconds: credit.yesterday, savedTotalSeconds: credit.total,
            remaining: sessions.running.map { max(0, $0.plannedEnd.timeIntervalSince(now)) }, start: start,
            blocking: blockingStatus
        )
    }
}
