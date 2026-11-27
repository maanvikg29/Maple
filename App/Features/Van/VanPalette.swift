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

/// A number with its picture, on a plate: the leaves, the syrup, the streak.
struct VanCounter: View {
    let value: String
    let image: String
    /// What the number counts, for VoiceOver: "leaves".
    let label: String
    /// A tighter plate, for a row that has more on it than fits at full size.
    var compact = false

    var body: some View {
        Label(value, systemImage: image)
            .font(.system(compact ? .footnote : .subheadline, design: .rounded).weight(.heavy))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(VanPalette.outline)
            .lineLimit(1)
            .fixedSize()
            .modifier(VanPlate(horizontal: compact ? 9 : 12))
            .accessibilityLabel("\(value) \(label)")
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
