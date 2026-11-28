import MapleCore
import SwiftUI

/// One time in the schedule editor: its name over the time in `statNumeral`, on a quiet tile that lifts when
/// it is the time being edited. A button: tapping it opens (or closes) that time's picker.
public struct ScheduleTimeField: View {
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale

    private let title: String
    private let time: ClockTime
    private let isSelected: Bool
    private let action: () -> Void

    public init(_ title: String, time: ClockTime, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.time = time
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text(title)
                    .font(MapleFont.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                StatNumber(StatNumber.Part.clockParts(HomeFormat.clockParts(time, locale: locale)), size: .stat)
            }
            .padding(.horizontal, theme.spacing.md)
            .padding(.vertical, theme.spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: theme.radius.tile, style: .continuous))
        }
        .buttonStyle(ScheduleTimeFieldStyle(isSelected: isSelected))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(HomeFormat.clock(time, locale: locale)))
        .accessibilityHint(Text(isSelected ? "Hides the time picker" : "Shows a time picker"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct ScheduleTimeFieldStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Tile(configuration: configuration, isSelected: isSelected)
    }

    private struct Tile: View {
        @Environment(\.theme) private var theme
        let configuration: Configuration
        let isSelected: Bool

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: theme.radius.tile, style: .continuous)
            configuration.label
                .background { shape.fill(fill) }
                .overlay { shape.strokeBorder(edge, lineWidth: theme.elevation.hairlineWidth) }
                .opacity(configuration.isPressed ? 0.7 : 1)
                .mapleAnimation(theme.motion.press, value: configuration.isPressed)
                .mapleAnimation(theme.motion.gentle, value: isSelected)
        }

        /// Sheets are `surface2`, so a tile lifts with white rather than a darker surface. On the van's cream white
        /// barely shows, so the chosen tile takes the gold of the one primary button and the other a faint brown.
        private var fill: AnyShapeStyle {
            if theme.look == .van {
                return AnyShapeStyle(isSelected ? theme.colors.primaryFillTop.opacity(0.6) : theme.colors.textPrimary.opacity(0.04))
            }
            return AnyShapeStyle(.white.opacity(isSelected ? 0.09 : 0.04))
        }

        /// With the van, the chosen tile has the picture's full outline and the other a faint line.
        private var edge: AnyShapeStyle {
            if theme.look == .van {
                return AnyShapeStyle(isSelected ? theme.colors.textPrimary : theme.colors.divider)
            }
            return AnyShapeStyle(theme.topLitHairline(isSelected ? theme.selectedHairline : theme.colors.hairlineTop))
        }
    }
}

/// Wind-down mode's bedside clock (spec §8.1): the time in `heroNumeral` at 70%, and one quiet line under it
/// ("38m until bed"). One VoiceOver element.
public struct BedsideClock: View {
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale

    private let time: ClockTime
    private let line: String
    private let spokenLine: String

    /// - Parameters:
    ///   - line: "38m until bed", or after Goodnight "Phone down at 23:04".
    ///   - spokenLine: The line with full units for VoiceOver.
    public init(time: ClockTime, line: String, spokenLine: String? = nil) {
        self.time = time
        self.line = line
        self.spokenLine = spokenLine ?? line
    }

    public var body: some View {
        VStack(spacing: theme.spacing.xxs) {
            StatNumber(StatNumber.Part.clockParts(HomeFormat.clockParts(time, locale: locale)), size: .hero)
                .opacity(0.7)
            Text(line)
                .font(MapleFont.callout)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
        }
        .mapleAnimation(theme.motion.gentle, value: line)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(HomeFormat.clock(time, locale: locale)). \(spokenLine)"))
    }
}

fileprivate extension StatNumber.Part {
    /// Core's numeral parts ("11:00 PM") as `StatNumber` parts.
    static func clockParts(_ numeral: [NumeralPart]) -> [StatNumber.Part] {
        numeral.map { $0.isUnit ? .unit($0.text) : .value($0.text) }
    }
}
