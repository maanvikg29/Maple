import MapleCore
import SwiftUI

/// A slice of the face, from 12 clockwise.
nonisolated struct ClockSector: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        guard fraction > 0 else { return path }
        path.move(to: centre)
        path.addArc(center: centre, radius: min(rect.width, rect.height) / 2, startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * min(1, fraction)), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// The clock that sets a session's length: a thick rim, a face set back inside it, hands that cast a shadow, and the
/// length as digits in the hub the hands start from (syrup van design §6.2).
struct ClockFace: View {
    @Binding var setting: ClockSetting

    @Environment(\.locale) private var locale

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                // The rim: an outline, the brass, a bright edge, and the shadow the rim throws on the face. The
                // outlines are drawn by hand (`VanInked`), so they thicken and thin round the brass.
                VanInked(outline: .ellipse, part: .fill, lineWidth: 0, wobble: side * 0.0028).fill(VanPalette.outline)
                Circle().fill(LinearGradient(colors: [VanPalette.goldLight, VanPalette.gold, VanPalette.copper],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(side * 0.014)
                Circle().strokeBorder(VanPalette.face.opacity(0.55), lineWidth: side * 0.012).padding(side * 0.03)
                VanInked(outline: .ellipse, part: .fill, lineWidth: 0, wobble: side * 0.0022).fill(VanPalette.outline)
                    .padding(side * 0.085)
                Circle().fill(VanPalette.face).padding(side * 0.098)
                // Syrup colour, from the top to the long hand.
                ClockSector(fraction: setting.faceFill)
                    .fill(VanPalette.syrupLight.opacity(0.55))
                    .padding(side * 0.098)
                Circle()
                    .strokeBorder(
                        LinearGradient(colors: [VanPalette.outline.opacity(0.34), .clear], startPoint: .top, endPoint: .center),
                        lineWidth: side * 0.05
                    )
                    .padding(side * 0.098)
                ticks(side: side)
                drops(side: side)
                hand(length: side * 0.2, width: side * 0.042, angle: setting.hourAngle, side: side)
                hand(length: side * 0.32, width: side * 0.03, angle: setting.minuteTurn, side: side)
                // The hub, with the length in it.
                VanInked(outline: .ellipse, part: .fill, lineWidth: 0, wobble: side * 0.0022).fill(VanPalette.outline)
                    .frame(width: side * 0.3, height: side * 0.3)
                Circle().fill(VanPalette.cream).frame(width: side * 0.272, height: side * 0.272)
                Text(setting.hubText)
                    .font(.system(size: side * 0.1, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(VanPalette.outline)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .frame(width: side * 0.24)
            }
            .frame(width: side, height: side)
            .position(centre)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dx = value.location.x - centre.x, dy = value.location.y - centre.y
                        // A touch on the hub itself has no direction worth following.
                        guard (dx * dx + dy * dy).squareRoot() > side * 0.16 else { return }
                        setting.turn(toAngle: ClockSetting.angle(dx: dx, dy: dy))
                    }
                    .onEnded { _ in setting.settle() }
            )
            .animation(.snappy(duration: 0.18), value: setting.minutes)
            .sensoryFeedback(.selection, trigger: setting.minutes)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Session length")
        .accessibilityValue(FocusTimeText.spokenLength(minutes: setting.minutes, locale: locale))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setting.nudge(1)
            case .decrement: setting.nudge(-1)
            @unknown default: break
            }
        }
    }

    private func ticks(side: Double) -> some View {
        ForEach(0 ..< 60, id: \.self) { index in
            let major = index % 5 == 0
            Capsule()
                .fill(VanPalette.outline.opacity(major ? 1 : 0.45))
                .frame(width: side * (major ? 0.014 : 0.006), height: side * (major ? 0.05 : 0.024))
                .offset(y: -side * (major ? 0.355 : 0.368))
                .rotationEffect(.degrees(Double(index) * 6))
        }
    }

    /// Three drops under 12: one fills for each whole hour, so the length reads without the digits.
    private func drops(side: Double) -> some View {
        HStack(spacing: side * 0.022) {
            ForEach(1 ... 3, id: \.self) { hour in
                Image(systemName: setting.wholeHours >= hour ? "drop.fill" : "drop")
                    .font(.system(size: side * 0.05, weight: .bold))
                    .foregroundStyle(setting.wholeHours >= hour ? VanPalette.syrup : VanPalette.outline.opacity(0.4))
            }
        }
        .offset(y: -side * 0.24)
        .accessibilityHidden(true)
    }

    private func hand(length: Double, width: Double, angle: Double, side: Double) -> some View {
        Capsule()
            .fill(VanPalette.outline)
            .frame(width: width, height: length)
            .offset(y: -length / 2 - side * 0.1)
            .rotationEffect(.degrees(angle))
            .shadow(color: VanPalette.outline.opacity(0.28), radius: side * 0.012, x: side * 0.012, y: side * 0.018)
    }
}
