import MapleCore
import MapleDesign
import SwiftUI

/// Home: the van under the maple (the concept picture itself), a welcome, the time, what is waiting, and the timer's
/// button (syrup van design §5.1). Everything is done from here: the pot on the stove cooks a leaf, and the round
/// buttons beside the timer's open the study record and the machines.
struct VanHomeView: View {
    let model: VanHomeModel
    let now: Date
    let streak: Int
    let prompt: Prompt?
    /// How many leaves have been cooked from here: each one is a light tap in the hand.
    let cooked: Int
    let onEnter: () -> Void
    let onCook: () -> Void
    let onMachines: () -> Void
    let onHistory: () -> Void
    let onHerbarium: () -> Void
    let onProfile: () -> Void
    let onTree: () -> Void
    let onStreak: () -> Void

    /// One more thing to do from home, above the van's own button: a waiting leaf's reveal, or wind-down.
    struct Prompt {
        let title: String
        let action: () -> Void
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How the picture is being looked at: pinched in, dragged about.
    @State private var view = VanView.fit
    /// Where it was when the fingers came down.
    @State private var held: VanView?

    var body: some View {
        ZStack {
            // The picture is the concept art itself, untouched: its full width at the top of the screen, and its own
            // sky colour carrying on below it, where the words are. It can be pinched closer and dragged about.
            GeometryReader { proxy in
                let canvas = VanCanvas.home
                let scale = canvas.scale(width: proxy.size.width, height: proxy.size.height)
                let length = { (value: Double) in value * scale }
                let shown = view.shown(width: proxy.size.width, height: proxy.size.height)
                ZStack {
                    VanPalette.sky
                    Image("VanHomePicture")
                        .resizable()
                        .frame(width: length(canvas.width), height: length(VanCanvas.homePictureHeight))
                        .position(canvas.point(canvas.width / 2, VanCanvas.homePictureHeight / 2, in: proxy.size))
                        .accessibilityHidden(true)
                    // For VoiceOver, which can't tap a place in a picture: the maple and the pot. (The timer and the
                    // machines have their own buttons below.)
                    spoken("Your maple", hint: "Opens the tree and its leaves", width: length(1000), height: length(900), action: onTree)
                        .position(canvas.point(500, 560, in: proxy.size))
                    spoken(
                        "Cooking pot", hint: model.potHint == nil ? "No leaves to cook" : "Cooks one leaf into syrup",
                        width: length(210), height: length(180), action: onCook
                    )
                    .position(canvas.point(764, 1220, in: proxy.size))
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                // A tap is a place in the picture, wherever the picture has been moved to.
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { tap in
                    let at = canvas.source(x: tap.location.x, y: tap.location.y, width: proxy.size.width, height: proxy.size.height)
                    switch VanHomeTarget.at(x: at.x, y: at.y) {
                    case .pot: onCook()
                    case .machines: onMachines()
                    case .timer: onEnter()
                    case .maple: onTree()
                    case nil: break
                    }
                })
                .scaleEffect(shown.zoom)
                .offset(x: shown.x, y: shown.y)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .contentShape(Rectangle())
                .gesture(looking(in: proxy.size))
                .sensoryFeedback(.impact(weight: .light), trigger: cooked)
            }
            .ignoresSafeArea()
            // The system's clock and battery are white: a soft shade keeps them readable on the canopy.
            LinearGradient(colors: [VanPalette.outline.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 110)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            words
        }
    }

    /// Pinch to zoom about the fingers, drag to move; letting go settles the picture back inside its limits.
    private func looking(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .simultaneously(with: DragGesture(minimumDistance: 8))
            .onChanged { value in
                let from = held ?? view
                held = from
                var next = from
                if let pinch = value.first {
                    next = next.zoomed(
                        by: pinch.magnification, aroundX: pinch.startLocation.x, y: pinch.startLocation.y,
                        width: size.width, height: size.height
                    )
                }
                if let drag = value.second {
                    next = next.moved(byX: drag.translation.width, y: drag.translation.height)
                }
                view = next
            }
            .onEnded { _ in
                held = nil
                let rest = view.settled(width: size.width, height: size.height)
                if reduceMotion {
                    view = rest
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { view = rest }
                }
            }
    }

    /// A place in the picture that VoiceOver can find and press. Touches go to the picture's own tap, not to this.
    private func spoken(_ label: String, hint: String, width: CGFloat, height: CGFloat, action: @escaping () -> Void) -> some View {
        Color.clear
            .frame(width: max(44, width), height: max(44, height))
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityHint(hint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }

    private var words: some View {
        ZStack {
            // One row when it fits, tighter when the numbers are long; at large text sizes the counters go above the
            // buttons.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    counters(compact: false)
                    Spacer(minLength: 0)
                    buttons(compact: false)
                }
                HStack(spacing: 6) {
                    counters(compact: true)
                    Spacer(minLength: 0)
                    buttons(compact: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) { counters(compact: false) }
                    HStack(spacing: 8) { buttons(compact: false) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxHeight: .infinity, alignment: .top)
            GeometryReader { proxy in
                // Where the picture's grass ends, below this view's top: the welcome sits in the middle of the sky
                // colour between there and the button.
                let insets = proxy.safeAreaInsets
                let scale = VanCanvas.home.scale(width: proxy.size.width, height: proxy.size.height + insets.top + insets.bottom)
                let grassEnds = max(0, VanHomeView.grassEnds * scale - insets.top)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    // Zoomed in, the picture is under these words: they step aside until it is back.
                    welcome
                        .opacity(view.isFit ? 1 : 0)
                        .animation(.easeInOut(duration: 0.2), value: view.isFit)
                        .accessibilityHidden(!view.isFit)
                    Spacer(minLength: 0)
                    enter
                }
                .padding(.top, grassEnds)
                .frame(maxWidth: .infinity)
            }
        }
        .vanChrome()
    }

    /// The bottom of the grass in the picture, in its own pixels.
    private static let grassEnds = 2150.0

    private var welcome: some View {
        VStack(spacing: 0) {
            Text(model.greeting)
                .font(.system(.title3, design: .rounded).weight(.bold))
            Text(now, format: .dateTime.hour().minute())
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if !model.status.isEmpty {
                Text(model.status)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            if let hint = model.potHint {
                Text(hint)
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .opacity(0.7)
                    .padding(.top, 2)
            }
        }
        .foregroundStyle(VanPalette.outline)
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var enter: some View {
        if let prompt {
            Button(action: prompt.action) {
                Text(prompt.title)
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(VanPalette.outline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .modifier(VanPlate())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 10)
        }
        HStack(spacing: 12) {
            roundButton("clock.arrow.circlepath", label: "Study record", action: onHistory)
            Button(action: onEnter) {
                Text(model.enterTitle)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(VanPalette.outline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 220)
                    .modifier(VanPlate(fill: VanPalette.goldLight))
            }
            .buttonStyle(.plain)
            .accessibilityHint(model.enterHint)
            roundButton("wrench.and.screwdriver.fill", label: "Machines", action: onMachines)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private func counters(compact: Bool) -> some View {
        if let leaves = model.leavesText { VanCounter(value: leaves, image: "leaf.fill", label: "leaves", compact: compact) }
        if let syrup = model.syrupText { VanCounter(value: syrup, image: "drop.fill", label: "bottles of syrup", compact: compact) }
    }

    @ViewBuilder
    private func buttons(compact: Bool) -> some View {
        if streak >= 2 {
            Button(action: onStreak) { VanCounter(value: "\(streak)", image: "flame.fill", label: "day streak", compact: compact) }
                .buttonStyle(.plain)
        }
        roundButton("book.closed.fill", label: "Herbarium", action: onHerbarium)
        roundButton("person.fill", label: "Profile and settings", action: onProfile)
    }

    private func roundButton(_ image: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(VanPalette.outline)
                .frame(width: 44, height: 44)
                .background(VanPalette.cream, in: Circle())
                .overlay(Circle().strokeBorder(VanPalette.outline, lineWidth: 2.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
