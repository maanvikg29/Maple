import MapleCore
import MapleDesign
import MapleServices
import SwiftUI

/// The workshop: the concept picture closer in, turned a little toward the front (syrup van design §5.2). The dial on
/// the boiler is the Focus button, the pot cooks a leaf, and the top row opens the machines and the study record.
///
/// The room is the concept picture's own pixels (`Scripts/art/concept/build_concept_art.py`); Pip is laid over it
/// upright and untouched. The points below are in that picture's units (`VanCanvas.workshop`), printed by the script.
struct VanWorkshopView: View {
    let model: VanHomeModel
    /// The dial's face: the length that would start, or the time left while a session runs.
    let gaugeText: String
    let onGauge: () -> Void
    let onBack: () -> Void

    @Environment(WorkshopStore.self) private var workshop
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathes = false
    @State private var showsHistory = false
    @State private var showsMachines = false
    @State private var cooked = 0

    var body: some View {
        ZStack {
            VanPalette.sky.ignoresSafeArea()
            GeometryReader { proxy in
                let canvas = VanCanvas.workshop
                let scale = canvas.scale(width: proxy.size.width, height: proxy.size.height)
                ZStack {
                    Image("VanWorkshopScene")
                        .resizable()
                        .frame(width: canvas.width * scale, height: canvas.height * scale)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        .accessibilityHidden(true)
                    Image("VanWorkshopPip")
                        .resizable()
                        .frame(width: 285 * scale, height: 285 * scale)
                        .offset(y: breathes ? -2 : 0)
                        .position(canvas.point(832.5, 1419.8, in: proxy.size))
                        .accessibilityHidden(true)

                    // The pot on the stove.
                    VanHotspot(width: 200 * scale, height: 170 * scale, action: cook)
                        .position(canvas.point(420, 1016, in: proxy.size))
                        .accessibilityLabel("Cooking pot")
                        .accessibilityHint(workshop.leaves > 0 ? "Cooks one leaf into syrup" : "No leaves to cook")
                        .sensoryFeedback(.impact(weight: .light), trigger: cooked)

                    // The boiler's dome, above its gauge: the machines.
                    VanHotspot(width: 170 * scale, height: 110 * scale) { showsMachines = true }
                        .position(canvas.point(645, 885, in: proxy.size))
                        .accessibilityHidden(true)

                    // The boiler's gauge is the timer: its face is drawn large enough to read and to tap.
                    Button(action: onGauge) {
                        Text(gaugeText)
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .foregroundStyle(VanPalette.outline)
                            .padding(.horizontal, 5)
                            .frame(width: 54, height: 54)
                            .background(VanPalette.face, in: Circle())
                            .overlay(Circle().strokeBorder(VanPalette.outline, lineWidth: 2.5))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .position(canvas.point(645, 1023, in: proxy.size))
                    .accessibilityLabel("Focus timer, \(gaugeText)")
                    .accessibilityHint(model.gaugeHint)
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
            VStack {
                // One row when it fits; at large text sizes the counters go under the way out.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        VanBackButton(title: "Outside", action: onBack)
                        Spacer(minLength: 0)
                        counters(compact: false)
                        roundButtons
                    }
                    HStack(spacing: 6) {
                        VanBackButton(title: "Outside", action: onBack)
                        Spacer(minLength: 0)
                        counters(compact: true)
                        roundButtons
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        VanBackButton(title: "Outside", action: onBack)
                        HStack(spacing: 8) {
                            counters(compact: false)
                            roundButtons
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer(minLength: 0)
                Text(model.workshopHint)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(VanPalette.outline)
                    .multilineTextAlignment(.center)
                    .modifier(VanPlate())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
            .vanChrome()
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { breathes = true }
        }
        .sheet(isPresented: $showsHistory) {
            NavigationStack { HistoryView() }
        }
        .sheet(isPresented: $showsMachines) {
            VanUpgradesView()
                .presentationDetents([.large])
        }
    }

    private func cook() {
        if workshop.cook() > 0 { cooked += 1 }
    }

    /// The study record and the machines, as buttons that can be seen.
    @ViewBuilder private var roundButtons: some View {
        roundButton("clock.arrow.circlepath", label: "Study record", hint: "Opens your past sessions") { showsHistory = true }
        roundButton("wrench.and.screwdriver.fill", label: "Machines", hint: "Opens the upgrades") { showsMachines = true }
    }

    private func roundButton(_ image: String, label: String, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(VanPalette.outline)
                .frame(width: 44, height: 44)
                .background(VanPalette.cream, in: Circle())
                .overlay(Circle().strokeBorder(VanPalette.outline, lineWidth: 2.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }

    @ViewBuilder
    private func counters(compact: Bool) -> some View {
        if let leaves = model.leavesText { VanCounter(value: leaves, image: "leaf.fill", label: "leaves", compact: compact) }
        if let syrup = model.syrupText { VanCounter(value: syrup, image: "drop.fill", label: "bottles of syrup", compact: compact) }
    }
}
