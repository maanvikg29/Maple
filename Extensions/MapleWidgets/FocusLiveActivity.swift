import ActivityKit
import MapleActivity
import SwiftUI
import WidgetKit

/// The running session's Live Activity (F1 design §5.11, §4.7): display only, with no buttons.
///
/// - Lock Screen: the next hours leaf as a skeleton in season tint (never gold), the system timer text over
///   "until 14:52 · Study", and the ring. A break reads "Break · back at 14:28"; a plain timer has no leaf.
/// - Compact: the leaf (the ring for a plain timer) and the timer text. Minimal: the ring.
/// - Expanded: the leaf, the timer text over "Study · Chemistry ch. 4" (the only place the intention shows), the ring.
///   Its line may take two lines, so a 40-character intention shows whole; the Lock Screen's stays on one.
/// - Once the stale date (the planned end) passes: "Session complete" and a full ring.
///
/// Every word arrives in the activity's content, already worded by MapleCore (`FocusActivityState.lines`).
struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            LockScreenActivity(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .activityBackgroundTint(ActivityPalette.card)
                .activitySystemActionForegroundColor(ActivityPalette.text)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LeadingMark(attributes: context.attributes, state: context.state, isStale: context.isStale, size: 34)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SessionRing(state: context.state, isStale: context.isStale)
                        .frame(width: 40, height: 40)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    TimeAndLine(state: context.state, isStale: context.isStale, line: context.state.expandedLine, timeFont: .title3,
                                lineLimit: 2)
                }
            } compactLeading: {
                LeadingMark(attributes: context.attributes, state: context.state, isStale: context.isStale, size: 20)
            } compactTrailing: {
                if context.isStale {
                    SessionRing(state: context.state, isStale: true)
                        .frame(width: 18, height: 18)
                } else {
                    Text(timerInterval: context.state.start...context.state.end, countsDown: true)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
                        .foregroundStyle(ActivityPalette.text)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 52)
                }
            } minimal: {
                // One element of its own: the ring hides itself, so a label on it alone would never be read.
                SessionRing(state: context.state, isStale: context.isStale)
                    .frame(width: 18, height: 18)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(context.isStale ? context.state.completeLine : context.state.lockLine))
            }
            .keylineTint(Color(attributes: context.attributes))
        }
    }
}

/// The Lock Screen banner: leaf, time and line, ring.
private struct LockScreenActivity: View {
    let attributes: FocusActivityAttributes
    let state: FocusActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        HStack(spacing: 12) {
            if let leaf = attributes.leaf {
                LeafMark(sketch: leaf, tint: Color(attributes: attributes))
                    .frame(width: 30, height: 30)
            }
            TimeAndLine(state: state, isStale: isStale, line: state.lockLine, timeFont: .title2)
            SessionRing(state: state, isStale: isStale)
                .frame(width: 36, height: 36)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// The system timer text (or "Session complete") over a line in secondary: one line, or up to `lineLimit` (the
/// expanded island's two, which a 40-character intention needs).
private struct TimeAndLine: View {
    let state: FocusActivityAttributes.ContentState
    let isStale: Bool
    let line: String
    let timeFont: Font.TextStyle
    var lineLimit = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Group {
                if isStale {
                    Text(state.completeLine)
                } else {
                    Text(timerInterval: state.start...state.end, countsDown: true)
                }
            }
            .font(.system(timeFont, design: .rounded, weight: .semibold).monospacedDigit())
            .foregroundStyle(ActivityPalette.text)
            .lineLimit(1)
            Text(isStale ? state.title : line)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(ActivityPalette.secondary)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The leaf, or the ring when there is no leaf (a plain timer).
private struct LeadingMark: View {
    let attributes: FocusActivityAttributes
    let state: FocusActivityAttributes.ContentState
    let isStale: Bool
    let size: CGFloat

    var body: some View {
        if let leaf = attributes.leaf {
            LeafMark(sketch: leaf, tint: Color(attributes: attributes))
                .frame(width: size, height: size)
        } else {
            SessionRing(state: state, isStale: isStale)
                .frame(width: size * 0.9, height: size * 0.9)
        }
    }
}

/// The session's progress as the system ring, filling as time passes like the dial's marks; full once stale.
private struct SessionRing: View {
    let state: FocusActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        Group {
            if isStale {
                Circle().strokeBorder(ActivityPalette.text, lineWidth: 3)
            } else {
                ProgressView(timerInterval: state.start...state.end, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .tint(ActivityPalette.text)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The leaf's skeleton: outline in the tint, veins and stalk fainter, as `LeafView`'s skeleton style draws it.
private struct LeafMark: View {
    let sketch: LeafSketch
    let tint: Color

    var body: some View {
        ZStack {
            SketchShape(sketch: sketch, part: .stalk)
                .stroke(tint.opacity(0.6), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            SketchShape(sketch: sketch, part: .veins)
                .stroke(tint.opacity(0.4), style: StrokeStyle(lineWidth: 0.75, lineCap: .butt))
            SketchShape(sketch: sketch, part: .outline)
                .stroke(tint, style: StrokeStyle(lineWidth: 1, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// One part of a `LeafSketch` as a path in the shape's frame.
nonisolated private struct SketchShape: Shape {
    enum Part { case outline, veins, stalk }

    let sketch: LeafSketch
    let part: Part

    func path(in rect: CGRect) -> Path {
        Path { path in
            switch part {
            case .outline:
                for outline in sketch.outlines(in: rect) where outline.count > 2 {
                    path.addLines(outline)
                    path.closeSubpath()
                }
            case .veins:
                for vein in sketch.veins(in: rect) where vein.count > 1 {
                    path.addLines(vein)
                }
            case .stalk:
                let stalk = sketch.stalk(in: rect)
                if stalk.count > 1 { path.addLines(stalk) }
            }
        }
    }
}

/// The few colours the extension draws with. It can't read `Theme`, so these copy its values: text primary
/// `#F2F5FA`, the Lock Screen card from the mockup (`docs/design/mockups/f1-focus-screens.html`, `.lockcard`), and its
/// secondary line `#A7ADBA`.
private enum ActivityPalette {
    static let text = Color(red: 0xF2 / 255, green: 0xF5 / 255, blue: 0xFA / 255)
    static let secondary = Color(red: 0xA7 / 255, green: 0xAD / 255, blue: 0xBA / 255)
    static let card = Color(red: 40 / 255, green: 42 / 255, blue: 48 / 255).opacity(0.86)
}

extension Color {
    /// The activity's leaf tint (sRGB).
    fileprivate init(attributes: FocusActivityAttributes) {
        let tint = attributes.tint
        self.init(red: tint.red, green: tint.green, blue: tint.blue)
    }
}
