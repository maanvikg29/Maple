import MapleCore
import MapleDesign
import MapleServices
import SwiftUI

/// The workshop: the van's cut-away room, seen from the front (syrup van design §5.2). The gauge is the Focus button, the pot
/// cooks a leaf, and the logbook opens History.
struct VanWorkshopView: View {
    let model: VanHomeModel
    /// The gauge's face: the length that would start, or the time left while a session runs.
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
            VanLayers(canvas: .workshop, names: ["VanWorkshopRoom", "VanWorkshopSteam", "VanWorkshopSmoke", "VanWorkshopPip"]) { name, image in
                switch name {
                case "VanWorkshopPip": image.offset(y: breathes ? -3 : 0)
                case "VanWorkshopSteam": image.offset(y: breathes ? -6 : 0).opacity(breathes ? 0.7 : 1)
                case "VanWorkshopSmoke": image.offset(x: breathes ? 4 : -1, y: breathes ? -6 : 0).opacity(breathes ? 0.82 : 1)
                default: image
                }
            }
            .ignoresSafeArea()
            GeometryReader { proxy in
                let canvas = VanCanvas.workshop
                let radius = canvas.length(44, width: proxy.size.width, height: proxy.size.height)
                Button(action: onGauge) {
                    // The face is small on a phone, so it carries the length alone; the line under the room names it.
                    Text(gaugeText)
                        .font(.system(size: max(11, radius * 0.5), weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(VanPalette.outline)
                        .frame(width: radius * 1.4, height: radius * 1.4)
                        .background(VanPalette.face, in: Circle())
                        // The whole drawn gauge takes the tap, and never less than 44 points.
                        .frame(width: max(44, radius * 2), height: max(44, radius * 2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .position(canvas.point(720, 881, in: proxy.size))
                .accessibilityLabel("Focus timer, \(gaugeText)")
                .accessibilityHint(model.gaugeHint)

                VanHotspot(
                    width: canvas.length(120, width: proxy.size.width, height: proxy.size.height),
                    height: canvas.length(90, width: proxy.size.width, height: proxy.size.height), action: cook
                )
                .position(canvas.point(361, 904, in: proxy.size))
                    .accessibilityLabel("Cooking pot")
                    .accessibilityHint(workshop.leaves > 0 ? "Cooks one leaf into syrup" : "No leaves to cook")
                    .sensoryFeedback(.impact(weight: .light), trigger: cooked)

                // The boiler's dome, above its gauge: the machines.
                VanHotspot(
                    width: canvas.length(130, width: proxy.size.width, height: proxy.size.height),
                    height: canvas.length(110, width: proxy.size.width, height: proxy.size.height)
                ) { showsMachines = true }
                .position(canvas.point(748, 770, in: proxy.size))
                .accessibilityLabel("Machines")
                .accessibilityHint("Opens the upgrades")

                VanHotspot(
                    width: canvas.length(70, width: proxy.size.width, height: proxy.size.height),
                    height: canvas.length(60, width: proxy.size.width, height: proxy.size.height)
                ) { showsHistory = true }
                .position(canvas.point(764, 958, in: proxy.size))
                    .accessibilityLabel("Logbook")
                    .accessibilityHint("Opens your study record")
            }
            .ignoresSafeArea()
            VStack {
                // One row when it fits; at large text sizes the counters go under the way out.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        VanBackButton(title: "Outside", action: onBack)
                        Spacer(minLength: 0)
                        counters
                        machinesButton
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        VanBackButton(title: "Outside", action: onBack)
                        HStack(spacing: 8) {
                            counters
                            machinesButton
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

    /// The machines, as a button that can be seen: the boiler's dome opens them too.
    private var machinesButton: some View {
        Button { showsMachines = true } label: {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(VanPalette.outline)
                .frame(width: 44, height: 44)
                .background(VanPalette.cream, in: Circle())
                .overlay(Circle().strokeBorder(VanPalette.outline, lineWidth: 2.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Machines")
        .accessibilityHint("Opens the upgrades")
    }

    @ViewBuilder private var counters: some View {
        if let leaves = model.leavesText { VanCounter(value: leaves, image: "leaf.fill", label: "leaves") }
        if let syrup = model.syrupText { VanCounter(value: syrup, image: "drop.fill", label: "bottles of syrup") }
    }
}
