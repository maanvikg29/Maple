import MapleCore
import MapleDesign
import MapleServices
import SwiftUI

/// The van's machines: spend leaves so every leaf cooks into more syrup (syrup van design §2, §7).
struct VanUpgradesView: View {
    @Environment(WorkshopStore.self) private var workshop
    @Environment(\.dismiss) private var dismiss
    /// Bumped by each upgrade, for the haptic.
    @State private var upgraded = 0

    var body: some View {
        let levels = Dictionary(uniqueKeysWithValues: WorkshopMachine.allCases.map { ($0, workshop.level(of: $0)) })
        let model = VanUpgradesModel(leaves: workshop.leaves, levels: levels, tuning: workshop.tuning)
        ZStack {
            VanPalette.sky.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Machines")
                            .font(.system(.title2, design: .rounded).weight(.heavy))
                        Spacer(minLength: 8)
                        Button("Done") { dismiss() }
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(VanPalette.outline)
                            .modifier(VanPlate())
                            .buttonStyle(.plain)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.yieldText)
                            .font(.system(.headline, design: .rounded).weight(.bold))
                        HStack(spacing: 6) {
                            VanMedallion(name: "VanIconBasket", size: 24)
                            Text(model.leavesText)
                        }
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    }
                    ForEach(model.rows) { row in
                        card(row)
                    }
                    Text("Leaves spent here aren't cooked into syrup.")
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .opacity(0.7)
                }
                .foregroundStyle(VanPalette.outline)
                .padding(20)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .sensoryFeedback(.success, trigger: upgraded)
    }

    private func card(_ row: VanUpgradesModel.Row) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.name)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                Spacer(minLength: 8)
                Text(row.levelText)
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .opacity(0.7)
            }
            Text(row.about)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .opacity(0.7)
            Text(row.nowText)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
            if let next = row.nextText {
                Text(next)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
            }
            if let title = row.buttonTitle {
                Button {
                    if case .upgraded = workshop.upgrade(row.machine) { upgraded += 1 }
                } label: {
                    Text(title)
                        .font(.system(.body, design: .rounded).weight(.heavy))
                        .foregroundStyle(VanPalette.outline)
                        .frame(maxWidth: .infinity)
                        .modifier(VanPlate(fill: row.canAfford ? VanPalette.goldLight : VanPalette.creamShade))
                }
                .buttonStyle(.plain)
                .disabled(!row.canAfford)
                .padding(.top, 4)
                .accessibilityHint(row.canAfford ? "Spends the leaves and raises this machine a level" : "Not enough leaves yet")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VanPalette.cream, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(VanPalette.outline, lineWidth: 2.5))
        .accessibilityElement(children: .contain)
    }
}
