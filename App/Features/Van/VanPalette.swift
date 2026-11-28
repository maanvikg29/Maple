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

/// A rounded, outlined plate: the look of every button and label that sits over the scene.
struct VanPlate: ViewModifier {
    var fill = VanPalette.cream
    var horizontal: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontal)
            .padding(.vertical, 10)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(VanPalette.outline, lineWidth: 2.5))
    }

    /// A capsule round one line, a rounded box round several.
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 22, style: .continuous) }
}

/// A number with its picture: the leaves, the syrup, the streak. The picture is a round window onto the concept
/// (`VanMedallion`); how the number sits over the scene is the HUD's look (`VanHud`).
struct VanCounter: View {
    let value: String
    /// A `VanIcon…` picture.
    let icon: String
    /// What the number counts, for VoiceOver: "leaves".
    let label: String
    /// Tighter, for a row that has more on it than fits at full size.
    var compact = false
    var hud = VanHud.current

    var body: some View {
        Group {
            switch hud {
            case .plates:
                HStack(spacing: 6) {
                    VanMedallion(name: icon, size: compact ? 24 : 28)
                    number
                }
                .padding(.leading, 5)
                .padding(.trailing, compact ? 10 : 12)
                .padding(.vertical, 5)
                .background(VanPalette.cream, in: Capsule())
                .overlay(Capsule().strokeBorder(VanPalette.outline, lineWidth: 2.5))
            case .board:
                HStack(spacing: 5) {
                    VanMedallion(name: icon, size: compact ? 26 : 30)
                    number
                }
            case .floating:
                HStack(spacing: 5) {
                    VanMedallion(name: icon, size: compact ? 32 : 38)
                    number
                        // A cream edge round the dark numerals, so they read on the canopy and the sky alike.
                        .shadow(color: VanPalette.cream, radius: 0.6)
                        .shadow(color: VanPalette.cream, radius: 1.4)
                        .shadow(color: VanPalette.cream, radius: 2.4)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }

    private var number: some View {
        Text(value)
            .font(.system(compact ? .footnote : .subheadline, design: .rounded).weight(.heavy))
            .monospacedDigit()
            .foregroundStyle(VanPalette.outline)
            .lineLimit(1)
            .fixedSize()
    }
}

/// A round window onto the concept picture, centred on one thing in it (`HUD_ICONS` in the art script), with the
/// picture's own outline round it: the buttons' and counters' pictures.
struct VanMedallion: View {
    let name: String
    var size: CGFloat = 44

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(VanPalette.outline, lineWidth: size >= 34 ? 2.5 : 2))
            .accessibilityHidden(true)
    }
}

/// How home's counters and buttons sit over the picture. Three looks, while the owner picks one (the owner, 28 Nov
/// 2026: "the hud at the top of screen give options to replace"); DEBUG `-MapleDemoHud plates|board|floating` shows
/// each.
enum VanHud: String, CaseIterable {
    /// Each number on its own small cream plate, the buttons round windows onto the picture.
    case plates
    /// Everything on one wooden board across the top, and one along the bottom.
    case board
    /// No plates at all: the pictures and numbers stand on the scene.
    case floating

    static var current: VanHud {
        #if DEBUG
        if let value = UserDefaults.standard.string(forKey: "MapleDemoHud"), let hud = VanHud(rawValue: value) { return hud }
        #endif
        return .plates
    }
}

/// A wooden board, drawn in the picture's wood with its outline, a few grain lines and a nail at each end: the
/// `board` HUD's backing.
struct VanBoard: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        shape
            .fill(VanPalette.wood)
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
            .overlay(shape.strokeBorder(VanPalette.outline, lineWidth: 2.5))
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
