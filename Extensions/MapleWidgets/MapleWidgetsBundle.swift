import SwiftUI
import WidgetKit

/// Maple's widget extension. In F1 it holds only the running session's Live Activity (F1 design §5.11).
@main
struct MapleWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FocusLiveActivity()
    }
}
