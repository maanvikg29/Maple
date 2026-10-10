import SwiftUI

extension View {
    /// Maple's glass: Liquid Glass tinted `glassTint` inside `shape`, with a 1pt `borderHighlight` → `borderSoft`
    /// edge and no glow (spec §7.3). Under Reduce Transparency it becomes solid `surface2` with the same edge.
    ///
    /// `GlassCapsuleStyle` and `IconCircleStyle` use it; use it directly for glass that is not a button,
    /// such as a `Menu` label or the focus stepper's value capsule.
    public func glassSurface<S: InsettableShape>(in shape: S) -> some View {
        modifier(GlassSurface(shape: shape))
    }
}

extension EnvironmentValues {
    /// Draws glass as its solid Reduce Transparency fallback. `ImageRenderer` cannot draw Liquid Glass (glass
    /// views render empty), so snapshot rendering sets this; the app never does.
    @Entry var drawsGlassAsSolid = false
}

private struct GlassSurface<S: InsettableShape>: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.drawsGlassAsSolid) private var drawsGlassAsSolid
    let shape: S

    func body(content: Content) -> some View {
        Group {
            if reduceTransparency || drawsGlassAsSolid {
                content.background { shape.fill(theme.colors.surface2) }
            } else {
                content.glassEffect(.regular.tint(theme.colors.glassTint), in: shape)
            }
        }
        .overlay {
            shape.strokeBorder(theme.edgeGradient, lineWidth: theme.elevation.hairlineWidth)
                .allowsHitTesting(false)
        }
    }
}

/// Secondary actions: a glass capsule with a 15pt SF Rounded semibold label (spec §7.3).
///
/// ```swift
/// Button("Sleep sounds") { … }.buttonStyle(.glassCapsule)
/// Button("Turn on") { … }.buttonStyle(.glassCapsule(.compact))   // 32pt, in section headers
/// ```
///
/// Both sizes keep a 44pt hit area. Pressing dims the label over `press`; there is no glow and no bounce.
public struct GlassCapsuleStyle: ButtonStyle {
    nonisolated public enum Size: Sendable, Hashable {
        /// 44pt: the standard secondary action.
        case regular
        /// 32pt, for actions inside headers and rows; the hit area stays 44pt.
        case compact

        var height: CGFloat {
            switch self {
            case .regular: 44
            case .compact: 32
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .regular: 20
            case .compact: 14
            }
        }
    }

    public var size: Size

    public init(_ size: Size = .regular) {
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        GlassCapsuleButton(configuration: configuration, size: size)
    }
}

private struct GlassCapsuleButton: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    let configuration: ButtonStyleConfiguration
    let size: GlassCapsuleStyle.Size

    var body: some View {
        configuration.label
            .font(MapleFont.contextEmphasis)
            .foregroundStyle(isEnabled ? theme.colors.textPrimary : theme.colors.textSecondary)
            // A capsule stays one line; at large sizes it shrinks a little, and containers stack capsules.
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, 6)
            .frame(minHeight: size.height)
            .glassSurface(in: Capsule(style: .continuous))
            .padding(.vertical, (44 - size.height) / 2)
            .contentShape(Rectangle())
            .mapleAnimation(theme.motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassCapsuleStyle {
    /// A 44pt glass capsule for secondary actions.
    public static var glassCapsule: GlassCapsuleStyle { GlassCapsuleStyle() }

    public static func glassCapsule(_ size: GlassCapsuleStyle.Size) -> GlassCapsuleStyle {
        GlassCapsuleStyle(size)
    }
}

/// Back, close, share, search, filter, info, plus, minus and play: a 36pt glass circle holding one SF Symbol
/// at 15pt semibold and 90% opacity, inside a 44pt hit area (spec §7.3).
///
/// Give the button a title so VoiceOver can name it; only the symbol is drawn:
///
/// ```swift
/// Button("Filter", systemImage: "line.3.horizontal.decrease") { … }
///     .buttonStyle(.iconCircle(badge: activeFilters))
/// ```
public struct IconCircleStyle: ButtonStyle {
    /// A count shown on a 16pt `surface2` badge, e.g. active filters. Hidden when nil or 0.
    public var badge: Int?

    public init(badge: Int? = nil) {
        self.badge = badge
    }

    public func makeBody(configuration: Configuration) -> some View {
        IconCircleButton(configuration: configuration, badge: badge)
    }
}

private struct IconCircleButton: View {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    let configuration: ButtonStyleConfiguration
    let badge: Int?

    var body: some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 15, weight: .semibold))
            .imageScale(.medium)
            .foregroundStyle((isEnabled ? theme.colors.textPrimary : theme.colors.textSecondary).opacity(0.9))
            .opacity(configuration.isPressed ? 0.55 : 1)
            .frame(width: 36, height: 36)
            .glassSurface(in: Circle())
            .overlay(alignment: .topTrailing) {
                if let badge, badge > 0 {
                    Text(badge, format: .number)
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(theme.colors.textPrimary)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 16, minHeight: 16)
                        .background {
                            Capsule(style: .continuous)
                                .fill(theme.colors.surface2)
                                .stroke(theme.colors.background, lineWidth: 2)
                        }
                        .offset(x: 5, y: -5)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            // The symbol stays 15pt at every text size, so offer the large content viewer instead.
            .accessibilityShowsLargeContentViewer()
            .accessibilityValue(badge.map { $0 > 0 ? Text($0, format: .number) : Text("") } ?? Text(""))
            .mapleAnimation(theme.motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == IconCircleStyle {
    /// A 36pt glass circle with a 44pt hit area.
    public static var iconCircle: IconCircleStyle { IconCircleStyle() }

    public static func iconCircle(badge: Int?) -> IconCircleStyle {
        IconCircleStyle(badge: badge)
    }
}
