import ActivityKit
import MapleActivity
import SwiftUI
import WidgetKit

/// The running session's Live Activity (F1 design §5.11). This first version only proves the extension is wired: the
/// system timer text on the Lock Screen and in the Dynamic Island. Step 27 replaces it with the real layouts.
struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            Text(timerInterval: context.state.start...context.state.end, countsDown: true)
                .monospacedDigit()
                .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text(timerInterval: context.state.start...context.state.end, countsDown: true)
                        .monospacedDigit()
                }
            } compactLeading: {
                EmptyView()
            } compactTrailing: {
                Text(timerInterval: context.state.start...context.state.end, countsDown: true)
                    .monospacedDigit()
                    .frame(width: 52)
            } minimal: {
                EmptyView()
            }
        }
    }
}
