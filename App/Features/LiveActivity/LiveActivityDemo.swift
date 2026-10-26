#if DEBUG
import MapleCore
import MapleDesign
import MapleServices
import SwiftUI
import UIKit

extension View {
    /// DEBUG only, on a demo launch:
    /// - shows `-MapleDemoLiveActivity running|break|plain|ended` as a real Live Activity on real dates, straight
    ///   through `controller` (the demo store never shows one);
    /// - without it, ends any Maple activity an earlier launch left, so screenshots start clean;
    /// - with `-MapleDemoLiveActivityExpand <seconds>`, that long after Maple goes to the background, re-sends the
    ///   activity with an alert, so the Dynamic Island shows its expanded presentation for a screenshot.
    /// The sandbox's store drives the controller itself, so the sandbox is left alone.
    func liveActivityDemo(_ controller: ActivityKitController, collection: CollectionStore) -> some View {
        modifier(LiveActivityDemoRunner(controller: controller, collection: collection))
    }
}

private struct LiveActivityDemoRunner: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let controller: ActivityKitController
    let collection: CollectionStore
    @State private var hasShown = false

    func body(content: Content) -> some View {
        content.task(id: scenePhase) {
            let options = DemoLaunchOptions.current
            guard options.isActive, !options.sandbox else { return }
            switch scenePhase {
            case .active where !hasShown:
                hasShown = true
                await show(options)
            case .background:
                await expandLater(options)
            default:
                break
            }
        }
    }

    private func show(_ options: DemoLaunchOptions) async {
        guard let value = options.liveActivity else {
            await controller.show(nil)
            return
        }
        let now = Date.now
        let state = value.state(options: options, now: now)
        let leaf = collection.progress(at: now).first { $0.category == .hoursSaved && $0.state == .locked }
        await controller.show(state.described(
            intention: state.intention, tint: Theme.SeasonTints.leafColor(for: collection.season(at: now)), leafID: leaf?.speciesID
        ))
    }

    private func expandLater(_ options: DemoLaunchOptions) async {
        guard options.liveActivity != nil,
              let seconds = UserDefaults.standard.string(forKey: "MapleDemoLiveActivityExpand").flatMap(TimeInterval.init)
        else { return }
        let task = UIApplication.shared.beginBackgroundTask(withName: "LiveActivityDemoExpand", expirationHandler: nil)
        defer { UIApplication.shared.endBackgroundTask(task) }
        guard (try? await Task.sleep(for: .seconds(max(0, seconds)))) != nil else { return }
        await controller.expandForDemo()
    }
}
#endif
