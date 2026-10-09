import SwiftUI
import MapleDesign

@main
struct MapleApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.theme, .maple)
                .preferredColorScheme(.dark)
        }
    }
}
