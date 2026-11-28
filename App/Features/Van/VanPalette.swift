import MapleDesign
import SwiftUI

/// The van's colours, sampled from the concept picture.
enum VanPalette {
    static let sky = Color(hex: 0xFFDDC2)
    static let outline = Color(hex: 0x3A1C0E)
    static let cream = Color(hex: 0xF8E1B7)
    static let creamShade = Color(hex: 0xECD09F)
    static let stripe = Color(hex: 0xC75438)
    static let wood = Color(hex: 0xD69761)
    static let gold = Color(hex: 0xEDA04F)
    static let goldLight = Color(hex: 0xF6C16A)
    static let syrup = Color(hex: 0xC9662A)
    static let syrupLight = Color(hex: 0xE59A45)
    static let face = Color(hex: 0xFFF4E2)
    static let grass = Color(hex: 0xA09F5F)
    static let copper = Color(hex: 0xC87445)
    /// Dust off the grass: its colour, paled toward the cream.
    static let dust = Color(hex: 0xD9D1A6)
}

/// A rounded plate with a hand-drawn outline (`VanInked`): the look of every button and label that sits over the
/// scene. A capsule round one line, a rounded box round several.
struct VanPlate: ViewModifier {
    var fill = VanPalette.cream
    var horizontal: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontal)
            .padding(.vertical, 10)
            .vanInked(.roundedRect(radius: 22), fill: fill)
    }
}

/// A number on its own drawn bar, with its picture over the bar's left end: the leaves, the syrup, the streak, along
/// the top of home (the owner, 28 Nov 2026, picked separate bars over the board: "the top bar looks too free").
struct VanCounter: View {
    let value: String
    /// A `VanIcon…` picture.
    let icon: String
    /// What the number counts, for VoiceOver: "leaves".
    let label: String
    /// Tighter, for a row that has more on it than fits at full size.
    var compact = false

    var body: some View {
        let iconSize: CGFloat = compact ? 40 : 46
        ZStack(alignment: .leading) {
            Text(value)
                .font(.system(compact ? .subheadline : .headline, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(VanPalette.outline)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: compact ? 34 : 52, alignment: .trailing)
                .padding(.leading, iconSize * 0.62)
                .padding(.trailing, compact ? 11 : 14)
                .padding(.vertical, 7)
                .vanInked(.roundedRect(radius: 18), fill: VanPalette.cream, lineWidth: 2.4)
                // The bar starts under the middle of its picture.
                .padding(.leading, iconSize * 0.42)
            VanIcon(name: icon, size: iconSize)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }
}

/// One of home's drawn icons (`Scripts/art/icons/build_van_icons.py`), on its own: the counters' pictures.
struct VanIcon: View {
    let name: String
    var size: CGFloat = 30

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A drawn icon on a cream disc with a hand-drawn outline: the round buttons.
struct VanMedallion: View {
    let name: String
    var size: CGFloat = 44
    var fill = VanPalette.cream

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .padding(size * 0.14)
            .frame(width: size, height: size)
            .vanInked(.ellipse, fill: fill, lineWidth: size >= 34 ? 2.6 : 2.1)
            .accessibilityHidden(true)
    }
}

/// A wooden board, drawn in the picture's wood with a hand-drawn outline, a few grain lines and a nail at each end:
/// what home's buttons sit on (the owner picked it from three looks, 28 Nov 2026).
struct VanBoard: View {
    var body: some View {
        let shape = VanInked(outline: .roundedRect(radius: 14), part: .fill)
        Color.clear
            .overlay {
                Canvas { context, size in
                    // Grain: three long, gently waving lines in the wood's darker tone.
                    for (index, height) in [0.3, 0.55, 0.8].enumerated() {
                        var line = Path()
                        let y = size.height * height
                        line.move(to: CGPoint(x: 14, y: y))
                        let wave = index.isMultiple(of: 2) ? 2.0 : -2.0
                        line.addCurve(
                            to: CGPoint(x: size.width - 14, y: y + wave), control1: CGPoint(x: size.width * 0.35, y: y - wave),
                            control2: CGPoint(x: size.width * 0.65, y: y + 2 * wave)
                        )
                        context.stroke(line, with: .color(VanPalette.copper.opacity(0.55)), lineWidth: 1.5)
                    }
                    // A nail at each end.
                    for x in [9.0, size.width - 9] {
                        let nail = CGRect(x: x - 2.5, y: size.height / 2 - 2.5, width: 5, height: 5)
                        context.fill(Path(ellipseIn: nail), with: .color(VanPalette.outline.opacity(0.8)))
                    }
                }
                .clipShape(shape)
            }
            .vanInked(.roundedRect(radius: 14), fill: VanPalette.wood)
            .accessibilityHidden(true)
    }
}

/// The top of a scene, under the system's clock and battery. With the van's light look those are dark, so a soft haze
/// of the sky lifts the canopy behind them (a darker canopy leaves them about 3.6 : 1, the haze about 6 : 1).
struct VanStatusShade: View {
    var body: some View {
        LinearGradient(colors: [VanPalette.sky.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
            .frame(height: 110)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// The words and buttons over the scene grow with the member's text size up to the second accessibility size;
    /// past that they would cover the picture they sit on.
    func vanChrome() -> some View {
        dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

/// The way back, top-left of any screen reached from the scene.
struct VanBackButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "chevron.backward")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(VanPalette.outline)
                .lineLimit(1)
                .fixedSize()
                .modifier(VanPlate())
        }
        .buttonStyle(.plain)
    }
}
