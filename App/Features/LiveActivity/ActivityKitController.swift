import ActivityKit
import Foundation
import MapleActivity
import MapleCore
import MapleDesign
import MapleServices
import os

/// The running session's Live Activity on ActivityKit (F1 design §5.11): display only, with no buttons and no push.
///
/// `FocusSessionStore` calls `reconcile(running:)` after every change, and through `refresh()` on launch, on every
/// return to the foreground and every 15 seconds while a session runs. So this is also where Maple reconnects to the
/// activity a killed app left running, and ends any activity it doesn't recognise (`LiveActivityPlan`). The
/// activity's stale date is the planned end, after which the widget reads "Session complete"; an activity never ends
/// a session itself.
///
/// - A session's activity is never asked for every refresh (`LiveActivityAsks`): one that showed, was found again and
///   kept, or was dismissed isn't asked for again in this launch. One ActivityKit refused is asked for once more after
///   Maple next becomes active (`mapleBecameActive()`, on each return to the foreground). "Live Activities are off" is
///   logged once per launch.
/// - Logs carry session ids and counts, never content.
final class ActivityKitController: LiveActivityController {
    private var collection: CollectionStore?
    private var notes: SessionNotesStore?
    /// What was last sent to each session's activity, so a refresh with nothing new sends nothing.
    private var sent: [UUID: FocusActivityAttributes.ContentState] = [:]
    /// Which sessions this launch may still ask ActivityKit for.
    private var asks = LiveActivityAsks()
    private let log = Logger(subsystem: "com.maanvikgupta.maple", category: "LiveActivity")

    /// Gives the controller what the store's state doesn't carry: intentions (`session-notes.json`), the season and
    /// the next hours leaf. `MapleApp` calls it once the stores exist.
    func attach(collection: CollectionStore, notes: SessionNotesStore) {
        self.collection = collection
        self.notes = notes
    }

    func reconcile(running state: FocusActivityState?) async {
        await show(state.map(described))
    }

    func mapleBecameActive() {
        asks.mapleBecameActive()
    }

    /// Shows exactly `state` (already described), or ends every Maple activity when it is nil.
    func show(_ state: FocusActivityState?) async {
        let wanted = state.map { state in
            LiveActivities.Wanted(attributes: attributes(for: state), content: Self.content(for: state), staleDate: state.plannedEnd)
        }
        let id = state?.sessionID
        let outcome = await LiveActivities.sync(
            wanted, lastSent: id.flatMap { sent[$0] }, mayRequest: id.map { asks.mayRequest($0) } ?? false
        )
        if outcome.ended > 0 { log.info("Ended \(outcome.ended, privacy: .public) Live Activities Maple didn't recognise") }
        guard let id, let wanted else {
            sent = [:]
            return
        }
        switch outcome.result {
        case .updated, .requested:
            asks.record(.shown, for: id)
            sent[id] = wanted.content
        case .unchanged:
            asks.record(.shown, for: id)
        case .dismissed:
            asks.record(.dismissed, for: id)
        case .refused(let reason):
            asks.record(.refused, for: id)
            log.error("No Live Activity for session \(id, privacy: .public): \(reason, privacy: .public)")
        case .disabled:
            if asks.record(.disabled, for: id) {
                log.info("Live Activities are off; session \(id, privacy: .public) shows none")
            }
        case .notAsked, .cleared:
            break
        }
    }

    /// The store's state with the intention, the season's tint and the next hours leaf (none for a plain timer).
    private func described(_ state: FocusActivityState) -> FocusActivityState {
        guard let collection else { return state }
        let leaf = collection.progress(at: state.start).first { $0.category == .hoursSaved && $0.state == .locked }
        return state.described(
            intention: notes?.intention(for: state.sessionID),
            tint: Theme.SeasonTints.leafColor(for: collection.season(at: state.start)),
            leafID: leaf?.speciesID
        )
    }

    private func attributes(for state: FocusActivityState) -> FocusActivityAttributes {
        let sketch = state.leafID.flatMap { LeafCatalog.shared.species(id: $0) }.map { species in
            let skeleton = LeafGeometry.of(species).placedSkeleton
            return LeafSketch(outlines: skeleton.outlines, veins: skeleton.veins, stalk: skeleton.stalk, frame: skeleton.frame)
        }
        return FocusActivityAttributes(
            sessionID: state.sessionID, tintRGB: state.tint?.rgb ?? FocusActivityAttributes.neutralTint, leaf: sketch
        )
    }

    private static func content(for state: FocusActivityState) -> FocusActivityAttributes.ContentState {
        let lines = state.lines(locale: .autoupdatingCurrent, calendar: .autoupdatingCurrent)
        return FocusActivityAttributes.ContentState(
            start: state.start, end: state.plannedEnd, title: lines.title, lockLine: lines.lockLine,
            expandedLine: lines.expandedLine, completeLine: lines.complete, breakSpoken: lines.breakSpoken
        )
    }

    #if DEBUG
    /// DEBUG screenshots only (`-MapleDemoLiveActivityExpand`): sends the running activity's content again with an
    /// alert, so the Dynamic Island shows its expanded presentation for a few seconds.
    func expandForDemo() async {
        await LiveActivities.alertForDemo()
    }
    #endif
}

/// ActivityKit's side, off the main actor. `Activity` isn't `Sendable`, so it never crosses into the controller:
/// only attributes, content and outcomes do.
nonisolated enum LiveActivities {
    struct Wanted: Sendable {
        var attributes: FocusActivityAttributes
        var content: FocusActivityAttributes.ContentState
        var staleDate: Date
    }

    struct Outcome: Sendable {
        enum Result: Sendable {
            /// Nothing is wanted; every Maple activity has ended.
            case cleared
            /// The session's activity already shows this content.
            case unchanged
            case updated
            case requested
            /// The session's activity was dismissed (by the member, or ended by the system): it isn't asked for again.
            case dismissed
            /// Already asked for this launch, and not showing.
            case notAsked
            /// Live Activities are off for Maple in Settings.
            case disabled
            /// ActivityKit refused the request; the reason is the error's type, never its message.
            case refused(String)
        }

        var ended: Int
        var result: Result
    }

    /// Applies `LiveActivityPlan`: ends what it lists, then updates or requests the wanted session's activity.
    @concurrent
    static func sync(
        _ wanted: Wanted?, lastSent: FocusActivityAttributes.ContentState?, mayRequest: Bool
    ) async -> Outcome {
        let activities = Activity<FocusActivityAttributes>.activities
        let plan = LiveActivityPlan.make(
            activities: activities.map { activity in
                LiveActivityPlan.Listed(
                    session: activity.attributes.sessionID,
                    isShown: activity.activityState != .ended && activity.activityState != .dismissed
                )
            },
            wanted: wanted?.attributes.sessionID, contentChanged: lastSent != wanted?.content, mayRequest: mayRequest
        )
        for index in plan.end {
            await activities[index].end(nil, dismissalPolicy: .immediate)
        }
        let ended = plan.end.count
        guard let wanted else { return Outcome(ended: ended, result: .cleared) }
        switch plan.next {
        case .clear:
            return Outcome(ended: ended, result: .cleared)
        case .unchanged:
            return Outcome(ended: ended, result: .unchanged)
        case .update(let index):
            await activities[index].update(ActivityContent(state: wanted.content, staleDate: wanted.staleDate))
            return Outcome(ended: ended, result: .updated)
        case .dismissed:
            return Outcome(ended: ended, result: .dismissed)
        case .notAsked:
            return Outcome(ended: ended, result: .notAsked)
        case .request:
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return Outcome(ended: ended, result: .disabled) }
            do {
                _ = try Activity.request(
                    attributes: wanted.attributes,
                    content: ActivityContent(state: wanted.content, staleDate: wanted.staleDate),
                    pushType: nil
                )
                return Outcome(ended: ended, result: .requested)
            } catch {
                return Outcome(ended: ended, result: .refused(String(describing: type(of: error))))
            }
        }
    }

    #if DEBUG
    /// Re-sends each active activity's content with an alert (DEBUG screenshots of the expanded presentation).
    @concurrent
    static func alertForDemo() async {
        for activity in Activity<FocusActivityAttributes>.activities where activity.activityState == .active {
            let state = activity.content.state
            let alert = AlertConfiguration(
                title: LocalizedStringResource(String.LocalizationValue(state.title)),
                body: LocalizedStringResource(String.LocalizationValue(state.lockLine)),
                sound: .default
            )
            await activity.update(activity.content, alertConfiguration: alert)
        }
    }
    #endif
}
