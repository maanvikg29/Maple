import MapleCore
import MapleServices
import SwiftUI

/// How each of the van's places arrives on screen (syrup van design §5.3). With the van the tab bar is gone and the
/// places are switched in code, which on its own is a cut; instead each place comes in as it is shown, from the
/// van's sky colour behind every screen. With Reduce Motion it is only a short fade.
enum VanArrivalStyle {
    /// Home: the camera pulls back out of the van, and the picture settles from a little closer.
    case home
    /// The clock (and whatever the timer is showing): the boiler's gauge comes up close.
    case clock
    /// A place reached from the van, such as the Herbarium: it rises into view.
    case rise

    fileprivate var scale: Double {
        switch self {
        case .home: 1.1
        case .clock: 0.86
        case .rise: 0.98
        }
    }

    fileprivate var offset: Double {
        self == .rise ? 36 : 0
    }

    /// Where it grows from: the van's door at home, the gauge on the clock.
    fileprivate var anchor: UnitPoint {
        switch self {
        case .home: UnitPoint(x: 0.5, y: 0.3)
        case .clock: UnitPoint(x: 0.5, y: 0.3)
        case .rise: .center
        }
    }

    fileprivate var animation: Animation {
        switch self {
        case .home: .spring(response: 0.6, dampingFraction: 0.92)
        case .clock: .spring(response: 0.5, dampingFraction: 0.82)
        case .rise: .spring(response: 0.5, dampingFraction: 0.9)
        }
    }
}

extension View {
    /// This tab's arrival with the van; nothing without it.
    func vanArrival(_ tab: AppTab, _ style: VanArrivalStyle) -> some View {
        modifier(VanArrival(tab: tab, style: style))
    }
}

private struct VanArrival: ViewModifier {
    let tab: AppTab
    let style: VanArrivalStyle

    @Environment(AppRouter.self) private var router
    @Environment(CollectionStore.self) private var collection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Off while the place is away, so it is ready to come in again the moment it is shown.
    @State private var arrived = false

    func body(content: Content) -> some View {
        if collection.context.features.syrupVan {
            let moving = !arrived && !reduceMotion
            ZStack {
                // The sky stays put while the place comes in over it: without it the window's own white shows
                // through the fade, and round the edges while the place is still small.
                VanPalette.sky.ignoresSafeArea()
                content
                    .scaleEffect(moving ? style.scale : 1, anchor: style.anchor)
                    .offset(y: moving ? style.offset : 0)
                    .opacity(arrived ? 1 : 0)
            }
            .onAppear(perform: arrive)
            .onChange(of: router.selectedTab) { old, new in
                if old == tab, new != tab { leave() }
                if new == tab, old != tab { arrive() }
            }
        } else {
            content
        }
    }

    private func arrive() {
        guard !arrived else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : style.animation) { arrived = true }
    }

    /// Unseen: the tab has already gone.
    private func leave() {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { arrived = false }
    }
}
