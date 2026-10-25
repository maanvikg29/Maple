// The Focus dial (F1 design §4): every mark state; the dial through a session (start, running, the last minute, the
// leaf opening, dimmed, a plain timer, the break, Locked's hold, the emergency release, Needs Screen Time and the
// receipt); the lengths; the centre leaf's two tones and edge; Increase Contrast; the seasons; the smallest size;
// Dynamic Type for the centre; the finish's frames; and the hold buttons. All on the real #05070D background.
//
//   Scripts/snapshot.sh Scripts/snapshot/FocusScenes.swift [output-dir]       (macOS: Mac type sizes)
//   SIMULATOR="iPhone 17" Scripts/snapshot-ios.sh Scripts/snapshot/FocusScenes.swift [output-dir] [filter]
//
// macOS has no Dynamic Type, so judge focus-dial-centre-type with snapshot-ios.sh. The Live Activity is checked in the
// simulator (P9), and the Focus screens themselves with the launch arguments in docs/debug-launch-arguments.md.
// Compiled together with MapleCore + MapleDesign; not part of the app.
import Foundation
import SwiftUI

@MainActor
func snapshotScenes() -> [SnapshotScene] {
    dialScenes() + leafScenes() + motionScenes()
}

// MARK: - The dial

@MainActor
private func dialScenes() -> [SnapshotScene] {
    let fifty = DialLayout(plannedMinutes: 50)
    let saved = DialFill(before: 0.42)
    let counting = DialFill(before: 0.42, session: 0.3)
    let opened = DialFill(before: 0.42, session: 0.58, opened: 1)
    let gaps: [MarkState] = (0..<50).map { (22..<27).contains($0) ? .gap : .lit }
    let running = DialFrame.running(layout: fifty, elapsed: 18.4 * 60, leafMinute: 35, fill: counting)
    let receiptGaps = DialFrame.receipt(marks: gaps, isGold: true, fill: DialFill(before: 0.42, session: 0.38))
    return [
        SnapshotScene("focus-dial-mark-states", size: CGSize(width: 402, height: 560)) { MarkStateSheet() },
        SnapshotScene("focus-dial-mark-states-contrast", size: CGSize(width: 402, height: 560)) {
            MarkStateSheet().environment(\.theme, .mapleIncreasedContrast)
        },
        SnapshotScene("focus-dial-start") {
            DialPage(title: "Start · Study 50m", frame: .preview(layout: fifty, leafMinute: 35, fill: saved),
                     numeral: "50m", caption: "turn to set the length")
        },
        SnapshotScene("focus-dial-lengths", size: CGSize(width: 402, height: 520)) { LengthsSheet() },
        SnapshotScene("focus-dial-running") {
            DialPage(title: "Running · minute 18 of 50", frame: running, numeral: "32m", caption: "left of 50m")
        },
        SnapshotScene("focus-dial-running-last-minute") {
            DialPage(title: "The last minute",
                     frame: .running(layout: fifty, elapsed: 49.5 * 60, leafMinute: 35, fill: DialFill(before: 0.42, session: 0.55)),
                     numeral: "0:30", caption: "left of 50m")
        },
        SnapshotScene("focus-dial-running-opened") {
            DialPage(title: "The leaf has opened · minute 36",
                     frame: .running(layout: fifty, elapsed: 36 * 60, leafMinute: 35, fill: opened),
                     numeral: "14m", caption: "left of 50m")
        },
        SnapshotScene("focus-dial-running-dimmed") {
            DialPage(title: "Dimmed after 30 seconds", frame: running.dimmed(true), numeral: "32m", caption: "left of 50m")
        },
        SnapshotScene("focus-dial-plain-timer") {
            DialPage(title: "Plain timer",
                     frame: .running(layout: fifty, elapsed: 18.4 * 60, leafMinute: nil, fill: DialFill()),
                     showsLeaf: false, numeral: "32m", caption: "left of 50m")
        },
        SnapshotScene("focus-dial-break") {
            DialPage(title: "Break", frame: .breakTime(BreakDialLayout(breakSeconds: 300), left: 190),
                     showsLeaf: false, numeral: "4m", caption: "left of your break")
        },
        SnapshotScene("focus-dial-hold-start") {
            DialPage(title: "Locked · holding to start",
                     frame: .hold(progress: 0.5, base: .preview(layout: fifty, leafMinute: 35, fill: saved)),
                     numeral: "50m", caption: "Study")
        },
        SnapshotScene("focus-dial-emergency") {
            DialPage(title: "Emergency release", frame: .hold(progress: 0.6), showsLeaf: false,
                     numeral: "4s", caption: "keep holding")
        },
        SnapshotScene("focus-dial-off") {
            DialPage(title: "Needs Screen Time", frame: .off(layout: fifty), numeral: "50m", caption: nil)
        },
        SnapshotScene("focus-dial-receipt") {
            DialPage(title: "Receipt · a leaf opened",
                     frame: .receipt(marks: Array(repeating: .lit, count: 50), isGold: true, fill: opened),
                     numeral: "50m", caption: "saved · 2h 10m today", grow: 1)
        },
        SnapshotScene("focus-dial-receipt-gaps") {
            DialPage(title: "Receipt · 5m unlocked", frame: receiptGaps, numeral: "45m", caption: "saved · 2h 10m today")
        },
        SnapshotScene("focus-dial-running-contrast") {
            DialPage(title: "Running · Increase Contrast", frame: running, numeral: "32m", caption: "left of 50m")
                .environment(\.theme, .mapleIncreasedContrast)
        },
        SnapshotScene("focus-dial-receipt-gaps-contrast") {
            DialPage(title: "Receipt · Increase Contrast", frame: receiptGaps, numeral: "45m", caption: "saved · 2h 10m today")
                .environment(\.theme, .mapleIncreasedContrast)
        },
        SnapshotScene("focus-dial-seasons", size: CGSize(width: 402, height: 480)) { SeasonsSheet(frame: running) },
        SnapshotScene("focus-dial-smallest") {
            DialPage(title: "Smallest · 220pt", frame: running, numeral: "32m", caption: "left of 50m",
                     diameter: MinuteDialMetrics.minimumDiameter)
        },
        SnapshotScene("focus-dial-centre-type", size: CGSize(width: 402, height: 1080)) { CentreTypeSheet() },
    ]
}

// MARK: - The centre leaf

@MainActor
private func leafScenes() -> [SnapshotScene] {
    [
        SnapshotScene("focus-leaf-tones", size: CGSize(width: 402, height: 420)) { LeafTonesSheet() },
        SnapshotScene("focus-leaf-tones-large", size: CGSize(width: 402, height: 300)) { LargeLeafSheet() },
    ]
}

// MARK: - Pages

/// The dial with its centre, as the Focus screens compose it, with the Field maple as the next leaf.
private struct SceneDial: View {
    @Environment(\.theme) private var theme
    let frame: DialFrame
    var showsLeaf = true
    let numeral: String
    let caption: String?
    var grow: Double = 0
    var diameter: CGFloat = 300

    var body: some View {
        let leaf = showsLeaf ? LeafCatalog.shared.species(id: "campestre").map { DialLeaf(species: $0, fill: frame.fill) } : nil
        MinuteDial(frame: frame, diameter: diameter, theme: theme) {
            DialCentre(leaf: leaf, numeral: DialCentre.numeralParts(numeral), caption: caption, diameter: diameter)
                .grown(grow)
        }
    }
}

/// One dial on the black page, labelled above.
private struct DialPage: View {
    @Environment(\.theme) private var theme
    let title: String
    let frame: DialFrame
    var showsLeaf = true
    let numeral: String
    let caption: String?
    var grow: Double = 0
    var diameter: CGFloat = 300

    var body: some View {
        VStack(spacing: 48) {
            Text(title)
                .font(MapleFont.headline)
                .foregroundStyle(theme.colors.textSecondary)
            SceneDial(frame: frame, showsLeaf: showsLeaf, numeral: numeral, caption: caption, grow: grow, diameter: diameter)
        }
        .padding(.top, 140)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.colors.background)
    }
}

/// Every mark state on its own dial (§4.2).
private struct MarkStateSheet: View {
    @Environment(\.theme) private var theme

    private var tiles: [(name: String, frame: DialFrame)] {
        func uniform(_ state: MarkState, brightness: Double = 1) -> DialFrame {
            DialFrame(marks: Array(repeating: state, count: 50), currentBrightness: brightness)
        }
        return [
            ("plan", uniform(.plan)), ("ahead", uniform(.ahead)), ("lit", uniform(.lit)),
            ("current at 55%", uniform(.current, brightness: 0.55)), ("current at 100%", uniform(.current)),
            ("rest", uniform(.rest)), ("gap", uniform(.gap)), ("hold", uniform(.hold)), ("off", uniform(.off)),
        ]
    }

    var body: some View {
        let tiles = self.tiles
        Grid(horizontalSpacing: 16, verticalSpacing: 24) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        let tile = tiles[row * 3 + column]
                        VStack(spacing: 8) {
                            MinuteDial(frame: tile.frame, diameter: 108, theme: theme)
                            Text(tile.name)
                                .font(MapleFont.footnote)
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                    }
                }
            }
        }
        .padding(.top, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.colors.background)
    }
}

/// 20 minutes (one mark a minute, no dot: the leaf is out of reach), 1h 30m (45 marks of 2 minutes), 2h 5m (42 of
/// 3 minutes) and 3h (60).
private struct LengthsSheet: View {
    @Environment(\.theme) private var theme

    var body: some View {
        let lengths = [20, 90, 125, 180]
        Grid(horizontalSpacing: 24, verticalSpacing: 32) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(0..<2, id: \.self) { column in
                        let minutes = lengths[row * 2 + column]
                        let layout = DialLayout(plannedMinutes: minutes)
                        SceneDial(frame: .preview(layout: layout, leafMinute: 35, fill: DialFill(before: 0.42)),
                                  numeral: FocusTimeText.length(minutes: minutes), caption: "\(layout.markCount) marks",
                                  diameter: 160)
                    }
                }
            }
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.colors.background)
    }
}

/// The running dial in each season's tint: the current mark, the dot and the bloom.
private struct SeasonsSheet: View {
    @Environment(\.theme) private var theme
    let frame: DialFrame

    var body: some View {
        Grid(horizontalSpacing: 24, verticalSpacing: 24) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(0..<2, id: \.self) { column in
                        let season = Season.allCases[row * 2 + column]
                        VStack(spacing: 8) {
                            SceneDial(frame: frame, numeral: "32m", caption: "left of 50m", diameter: 160)
                            Text(season.rawValue)
                                .font(MapleFont.footnote)
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                        .environment(\.season, season)
                    }
                }
            }
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.colors.background)
    }
}

/// The centre at Large, at xxLarge, and at AX5, which is capped at xxLarge (§5.17), with the widest numeral.
private struct CentreTypeSheet: View {
    @Environment(\.theme) private var theme

    var body: some View {
        let rows: [(String, DynamicTypeSize)] = [
            ("Large", .large), ("xxLarge", .xxLarge), ("AX5 · capped at xxLarge", .accessibility5),
        ]
        let frame = DialFrame.running(
            layout: DialLayout(plannedMinutes: 120), elapsed: 30 * 60, leafMinute: 100, fill: DialFill(before: 0.3, session: 0.1)
        )
        VStack(spacing: 12) {
            ForEach(0..<rows.count, id: \.self) { index in
                VStack(spacing: 4) {
                    Text(rows[index].0)
                        .font(MapleFont.footnote)
                        .foregroundStyle(theme.colors.textSecondary)
                    SceneDial(frame: frame, numeral: "1h 30m", caption: "left of 2h", diameter: 300)
                        .environment(\.dynamicTypeSize, rows[index].1)
                }
            }
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.colors.background)
    }
}

/// The centre leaf's tones for four species: saved before only, saved plus this session, this session only,
/// nearly full (with the edge), and opened.
private struct LeafTonesSheet: View {
    @Environment(\.theme) private var theme
    private let fills: [(String, DialFill)] = [
        ("saved", DialFill(before: 0.4)),
        ("+ session", DialFill(before: 0.4, session: 0.3)),
        ("session", DialFill(session: 0.5)),
        ("nearly", DialFill(before: 0.5, session: 0.45)),
        ("opened", DialFill(before: 0.5, session: 0.5, opened: 1)),
    ]
    private let leaves = ["campestre", "palmatum", "rubrum", "saccharum"].compactMap { LeafCatalog.shared.species(id: $0) }

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 16) {
            GridRow {
                ForEach(0..<fills.count, id: \.self) { column in
                    Text(fills[column].0)
                        .font(MapleFont.micro)
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
            ForEach(leaves) { leaf in
                GridRow {
                    ForEach(0..<fills.count, id: \.self) { column in
                        DialLeaf(species: leaf, fill: fills[column].1)
                            .frame(width: 64, height: 64)
                    }
                }
            }
        }
        .padding(.top, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.colors.background)
    }
}

/// The Field maple at 170pt: two tones with the edge, and opened with its dark veins and glow.
private struct LargeLeafSheet: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 24) {
            if let field = LeafCatalog.shared.species(id: "campestre") {
                DialLeaf(species: field, fill: DialFill(before: 0.42, session: 0.3))
                    .frame(width: 170, height: 170)
                DialLeaf(species: field, fill: DialFill(before: 0.42, session: 0.58, opened: 1))
                    .frame(width: 170, height: 170)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.background)
    }
}

// MARK: - Motion: the finish and the holds

/// The finish frozen at 0.3 s, 0.9 s and 1.6 s with a leaf opened, then with gaps, in white, and under Reduce Motion,
/// and the hold buttons frozen as `-MapleDemoHoldAt` freezes them.
@MainActor
private func motionScenes() -> [SnapshotScene] {
    let lit = Array(repeating: MarkState.lit, count: 50)
    let gaps: [MarkState] = (0..<50).map { (22..<27).contains($0) ? .gap : .lit }
    let opened = DialFill(before: 0.42, session: 0.58, opened: 1)
    var scenes: [SnapshotScene] = []
    for time in [0.3, 0.9, 1.6] {
        scenes.append(SnapshotScene("focus-finish-\(time)s") {
            FinishPage(marks: lit, isGold: true, fill: opened, time: time, reduceMotion: false, numeral: "50m")
        })
    }
    scenes += [
        SnapshotScene("focus-finish-gaps-0.9s") {
            FinishPage(marks: gaps, isGold: true, fill: DialFill(before: 0.42, session: 0.38), time: 0.9,
                       reduceMotion: false, numeral: "45m")
        },
        SnapshotScene("focus-finish-white-0.6s") {
            FinishPage(marks: lit, isGold: false, fill: DialFill(before: 0.42), time: 0.6, reduceMotion: false,
                       numeral: "50m")
        },
        SnapshotScene("focus-finish-reduce-motion-0.5s") {
            FinishPage(marks: lit, isGold: true, fill: opened, time: 0.5, reduceMotion: true, numeral: "50m")
        },
        SnapshotScene("focus-hold-buttons", size: CGSize(width: 402, height: 700)) { HoldSheet() },
    ]
    return scenes
}

/// The receipt's dial, centre, leaf line and buttons at one moment of the finish.
private struct FinishPage: View {
    @Environment(\.theme) private var theme
    let marks: [MarkState]
    let isGold: Bool
    let fill: DialFill
    let time: Double
    let reduceMotion: Bool
    let numeral: String

    var body: some View {
        let dial = DialFrame.receipt(marks: marks, isGold: isGold, fill: fill)
        let finish = FinishTimeline.frame(at: time, counted: dial.gold, leafOpened: fill.opened > 0, reduceMotion: reduceMotion)
        let leaf = LeafCatalog.shared.species(id: "campestre").map { DialLeaf(species: $0, fill: fill) }
        VStack(spacing: 28) {
            Text("Finish at \(String(format: "%.1f", time)) s\(reduceMotion ? " · Reduce Motion" : "")")
                .font(MapleFont.headline)
                .foregroundStyle(theme.colors.textSecondary)
            MinuteDial(frame: dial, diameter: 300, theme: theme) {
                DialCentre(leaf: leaf, numeral: DialCentre.numeralParts(numeral), caption: "saved · 2h 10m today",
                           diameter: 300)
                    .finishing(finish)
            }
            .finishing(finish)
            Text(fill.opened > 0 ? "Field maple is yours · it opens after this session" : "Field maple · 1h 10m to go")
                .font(MapleFont.callout)
                .foregroundStyle(theme.colors.textPrimary)
                .opacity(finish.lineOpacity)
                .offset(y: finish.lineRise)
            VStack(spacing: 12) {
                Button("Done") {}
                    .buttonStyle(.moonlight)
                TextLink("Again · 50m", chevron: false) {}
            }
            .padding(.horizontal, 24)
            .opacity(finish.actionsOpacity)
            .offset(y: finish.actionsRise)
        }
        .padding(.top, 100)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.colors.background)
    }
}

/// Locked's start dial filling as the hold does, and the hold buttons frozen empty, at 40%, full, and the
/// emergency release at 60%.
private struct HoldSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        let fifty = DialLayout(plannedMinutes: 50)
        VStack(spacing: 24) {
            MinuteDial(frame: .hold(progress: 0.4, base: .preview(layout: fifty, leafMinute: 35)), diameter: 220, theme: theme)
            ForEach([0.0, 0.4, 1.0], id: \.self) { progress in
                HoldButton(
                    title: FocusCopy.holdToStart(minutes: 50), duration: FocusCopy.holdToStartSeconds,
                    accessibilityName: FocusCopy.holdToStartName(minutes: 50, locale: locale),
                    progress: .constant(progress), frozenProgress: progress
                ) {}
            }
            HoldButton(
                title: FocusCopy.Emergency.holdToRelease, duration: FocusCopy.Emergency.holdSeconds,
                accessibilityName: FocusCopy.Emergency.holdToRelease,
                progress: .constant(0.6), frozenProgress: 0.6
            ) {}
        }
        .padding(.horizontal, 24)
        .padding(.top, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.colors.background)
    }
}
