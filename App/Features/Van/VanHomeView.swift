import MapleCore
import MapleDesign
import SwiftUI

/// Home: the van under the maple (the concept picture itself), a welcome, the time, what is waiting, and one way in
/// (syrup van design §5.1).
struct VanHomeView: View {
    let model: VanHomeModel
    let now: Date
    let streak: Int
    let prompt: Prompt?
    let onEnter: () -> Void
    let onHerbarium: () -> Void
    let onProfile: () -> Void
    let onTree: () -> Void
    let onStreak: () -> Void

    /// One more thing to do from home, above the van's own button: a waiting leaf's reveal, or wind-down.
    struct Prompt {
        let title: String
        let action: () -> Void
    }

    var body: some View {
        ZStack {
            // The picture is the concept art itself, untouched: its full width at the top of the screen, and its own
            // sky colour carrying on below it, where the words are.
            GeometryReader { proxy in
                let canvas = VanCanvas.home
                let scale = canvas.scale(width: proxy.size.width, height: proxy.size.height)
                let length = { (value: Double) in value * scale }
                ZStack {
                    VanPalette.sky
                    Image("VanHomePicture")
                        .resizable()
                        .frame(width: length(canvas.width), height: length(VanCanvas.homePictureHeight))
                        .position(canvas.point(canvas.width / 2, VanCanvas.homePictureHeight / 2, in: proxy.size))
                        .accessibilityHidden(true)
                    // The maple opens the tree and its leaves, as the old home's tree did: its canopy and trunk, in
                    // the picture's own pixels.
                    VanHotspot(width: length(1000), height: length(900), action: onTree)
                        .position(canvas.point(500, 560, in: proxy.size))
                        .accessibilityLabel("Your maple")
                    // The van is the way in, like the button below.
                    VanHotspot(width: length(1400), height: length(1000), action: onEnter)
                        .position(canvas.point(880, 1560, in: proxy.size))
                        .accessibilityHidden(true)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
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
                    welcome
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
        Button(action: onEnter) {
            Text(model.enterTitle)
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(VanPalette.outline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: 260)
                .modifier(VanPlate(fill: VanPalette.goldLight))
        }
        .buttonStyle(.plain)
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
