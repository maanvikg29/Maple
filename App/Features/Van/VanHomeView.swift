import MapleCore
import MapleDesign
import SwiftUI

/// Home: the van under the maple (the concept picture itself), a welcome, the time, what is waiting, and the timer's
/// button (syrup van design §5.1). Everything is done from here: the pot on the stove cooks a leaf, and the round
/// buttons beside the timer's open the study record and the machines.
///
/// Pip is alive in the picture (`PipStage`): he breathes and his tail swishes, a tap makes him hop, cooking and a
/// finished session make him dance, and now and then he does something of his own. While a session runs, and with
/// Reduce Motion, he keeps to his place.
struct VanHomeView: View {
    let model: VanHomeModel
    let now: Date
    let streak: Int
    let prompt: Prompt?
    /// How many leaves have been cooked from here: each one is a light tap in the hand, and a dance from Pip.
    let cooked: Int
    /// How many finished sessions Pip has come home from while this view has been up: each one is a dance.
    let cheers: Int
    /// A session is running: Pip is at the maple with his pail, so here he only stands and breathes.
    let isSessionRunning: Bool
    let onEnter: () -> Void
    let onCook: () -> Void
    let onMachines: () -> Void
    let onHistory: () -> Void
    let onHerbarium: () -> Void
    let onProfile: () -> Void
    let onTree: () -> Void
    let onStreak: () -> Void
    /// Today's saved time, under the clock, opens Saved today (focus spec §5.9).
    let onSavedToday: () -> Void

    /// One more thing to do from home, above the van's own button: a waiting leaf's reveal, or wind-down.
    struct Prompt {
        let title: String
        let action: () -> Void
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    /// How the picture is being looked at: pinched in, dragged about.
    @State private var view = VanView.fit
    /// Where it was when the fingers came down.
    @State private var held: VanView?
    /// What Pip is doing.
    @State private var pip = PipStage()
    /// DEBUG `-MapleDemoPip <act>:<seconds>`: one frame of him, held.
    @State private var heldPip: PipScene?
    /// DEBUG `-MapleDemoAmbience <seconds>`: the picture's movement held at that moment.
    @State private var heldAmbience: Double?
    /// When home came up: the picture's movement counts from here.
    @State private var appeared = Date()

    /// How the counters and buttons sit over the picture (`VanHud`).
    private let hud = VanHud.current

    /// He does things of his own, and can be tapped.
    private var pipPlays: Bool { !reduceMotion && !isSessionRunning && heldPip == nil }

    private static func moment() -> Double { Date().timeIntervalSinceReferenceDate }

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
                    // The picture, alive: its smoke, flags, fire, lights and cat, Pip, and the maple's leaves coming
                    // down over everything. With Reduce Motion the picture is as it is, and Pip with it.
                    TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion || heldPip != nil)) { timeline in
                        let alive = timeline.date.timeIntervalSince(appeared)
                        ZStack {
                            if !reduceMotion {
                                VanAmbientLayer(part: .behind, time: heldAmbience ?? alive, canvas: canvas, size: proxy.size)
                            }
                            VanPipLayer(
                                scene: heldPip ?? pip.scene(at: timeline.date.timeIntervalSinceReferenceDate, still: reduceMotion),
                                canvas: canvas, size: proxy.size
                            )
                            if !reduceMotion {
                                VanAmbientLayer(part: .front, time: heldAmbience ?? alive, canvas: canvas, size: proxy.size)
                            }
                        }
                    }
                    // For VoiceOver, which can't tap a place in a picture: the maple, the pot and Pip. (The timer and
                    // the machines have their own buttons below.)
                    spoken("Pip's maple", hint: "Opens your leaves", width: length(1000), height: length(900), action: onTree)
                        .position(canvas.point(500, 560, in: proxy.size))
                    spoken(
                        "Cooking pot", hint: model.potHint == nil ? "No leaves to cook" : "Cooks one leaf into syrup",
                        width: length(210), height: length(180), action: onCook
                    )
                    .position(canvas.point(764, 1220, in: proxy.size))
                    if pipPlays {
                        spoken("Pip", hint: "Makes him hop", width: length(220), height: length(260)) { pip.tapped(at: Self.moment()) }
                            .position(canvas.point(PipHome.standX - 25, PipHome.standY - 125, in: proxy.size))
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                // A tap is a place in the picture, wherever the picture has been moved to.
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { tap in
                    let at = canvas.source(x: tap.location.x, y: tap.location.y, width: proxy.size.width, height: proxy.size.height)
                    // Pip first, wherever he has got to: he stands inside the van, whose tap is the timer.
                    let moment = Self.moment()
                    if pipPlays, pip.scene(at: moment).pose.contains(x: at.x, y: at.y) {
                        pip.tapped(at: moment)
                        return
                    }
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
            VanStatusShade()
            words
        }
        // Syrup cooked, or home from a finished session: a happy dance, unless he is in the middle of something.
        .onChange(of: cooked) { _, _ in
            if pipPlays { pip.play(.dance, at: Self.moment() + 0.15) }
        }
        .onChange(of: cheers) { _, _ in
            if pipPlays { pip.play(.dance, at: Self.moment() + 0.7) }
        }
        // Now and then, something of his own.
        .task(id: pipPlays) {
            guard pipPlays else { return }
            var last: PipAct?
            while !Task.isCancelled {
                let next = PipDirector.next(after: last, roll: UInt64.random(in: .min ... .max))
                try? await Task.sleep(for: .seconds(next.wait))
                guard !Task.isCancelled else { return }
                let moment = Self.moment()
                guard !pip.isBusy(at: moment) else { continue }
                pip.play(next.act, at: moment)
                last = next.act
                try? await Task.sleep(for: .seconds(next.act.seconds))
            }
        }
        #if DEBUG
        .onAppear(perform: showDemoPip)
        #endif
    }

    #if DEBUG
    /// `-MapleDemoPip <act>` plays that act a second after home opens; `<act>:<seconds>` holds its frame that far in.
    /// `idle:<seconds>` holds a frame of him just standing.
    private func showDemoPip() {
        heldAmbience = UserDefaults.standard.string(forKey: "MapleDemoAmbience").flatMap(Double.init)
        guard let value = UserDefaults.standard.string(forKey: "MapleDemoPip") else { return }
        let parts = value.split(separator: ":").map(String.init)
        let seconds = parts.count > 1 ? Double(parts[1]) : nil
        if parts.first == "idle" {
            heldPip = PipScene(pose: PipIdle.pose(at: seconds ?? 0))
        } else if let act = parts.first.flatMap(PipAct.init(rawValue:)) {
            if let seconds {
                heldPip = act.scene(at: seconds)
            } else {
                pip.play(act, at: Self.moment() + 1, cuttingIn: true)
            }
        }
    }
    #endif

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
            .padding(.horizontal, hud == .board ? 12 : 0)
            .padding(.vertical, hud == .board ? 6 : 0)
            .background { if hud == .board { VanBoard() } }
            .padding(.horizontal, hud == .board ? 10 : 16)
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
            if let saved = model.savedToday, let minutes = model.savedTodayMinutes {
                Button(action: onSavedToday) {
                    HStack(spacing: 4) {
                        Text(saved)
                        Image(systemName: "chevron.right")
                            .font(.system(.caption, design: .rounded).weight(.heavy))
                            .opacity(0.6)
                    }
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .padding(.bottom, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(FocusTimeText.spokenLength(minutes: minutes, locale: locale)) saved today")
                .accessibilityHint(FocusSheetCopy.savedTodayHint)
            }
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
            roundButton("VanIconGauge", label: "Study record", action: onHistory)
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
            roundButton("VanIconTools", label: "Machines", action: onMachines)
        }
        .padding(.horizontal, hud == .board ? 10 : 0)
        .padding(.vertical, hud == .board ? 8 : 0)
        .background { if hud == .board { VanBoard() } }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private func counters(compact: Bool) -> some View {
        if let leaves = model.leavesText { VanCounter(value: leaves, icon: "VanIconBasket", label: "leaves", compact: compact, hud: hud) }
        if let syrup = model.syrupText { VanCounter(value: syrup, icon: "VanIconJug", label: "bottles of syrup", compact: compact, hud: hud) }
    }

    @ViewBuilder
    private func buttons(compact: Bool) -> some View {
        if streak >= 2 {
            Button(action: onStreak) { VanCounter(value: "\(streak)", icon: "VanIconFire", label: "day streak", compact: compact, hud: hud) }
                .buttonStyle(.plain)
        }
        roundButton("VanIconLeaf", label: "Herbarium", action: onHerbarium)
        roundButton("VanIconPip", label: "Profile and settings", action: onProfile)
    }

    /// A round window onto the picture, as a button.
    private func roundButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VanMedallion(name: icon, size: hud == .floating ? 46 : 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
