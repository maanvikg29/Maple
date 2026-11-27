import MapleCore
import MapleDesign
import SwiftUI

/// Home: the van under the maple, a welcome, the time, what is waiting, and one way in (syrup van design §5.1).
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var breathes = false

    var body: some View {
        ZStack {
            VanPalette.sky.ignoresSafeArea()
            VanLayers(canvas: .home, names: ["VanHomeScene", "VanHomeSmoke", "VanHomePip", "VanHomeLeaves"]) { name, image in
                switch name {
                case "VanHomePip": image.offset(y: breathes ? -2 : 0)
                case "VanHomeSmoke": image.offset(x: breathes ? 3 : -1, y: breathes ? -5 : 0).opacity(breathes ? 0.82 : 1)
                case "VanHomeLeaves": image.offset(y: breathes ? 6 : -4)
                default: image
                }
            }
            .ignoresSafeArea()
            // The maple opens the tree and its leaves, as the old home's tree did.
            GeometryReader { proxy in
                // The canopy and the trunk, in the drawing's own units: left of the van's roof, above its door.
                let canvas = VanCanvas.home
                VanHotspot(
                    width: canvas.length(700, width: proxy.size.width, height: proxy.size.height),
                    height: canvas.length(1000, width: proxy.size.width, height: proxy.size.height), action: onTree
                )
                .position(canvas.point(350, 400, in: proxy.size))
                    .accessibilityLabel("Your maple")
            }
            .ignoresSafeArea()
            // The system's clock and battery are white: a soft shade keeps them readable on the pale sky.
            LinearGradient(colors: [VanPalette.outline.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 110)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            words
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathes = true }
        }
    }

    private var words: some View {
        VStack(spacing: 0) {
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
            VStack(spacing: 2) {
                Text(model.greeting)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text(now, format: .dateTime.hour().minute())
                    .font(.system(size: 60, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if !model.status.isEmpty {
                    Text(model.status)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(VanPalette.outline)
            // At the accessibility sizes the words reach the canopy, so they sit on a plate there.
            .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 14 : 0)
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
            .background {
                if dynamicTypeSize.isAccessibilitySize {
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(VanPalette.cream.opacity(0.92))
                }
            }
            .padding(.top, 10)
            .padding(.horizontal, 24)
            Spacer(minLength: 0)
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
        .vanChrome()
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
