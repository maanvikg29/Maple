// Home's presentational pieces (MapleDesign/Home) as snapshots, rendered without the app:
//
//   SIMULATOR="iPhone 17e" Scripts/snapshot-ios.sh Scripts/snapshot/HomeScenes.swift [output-dir] [name-filter]
//   Scripts/snapshot.sh Scripts/snapshot/HomeScenes.swift [output-dir]
//
// The header (with and without a streak), the tree caption, the NowBlock in every §3.4 row, the next-leaf row
// (with progress, "Tonight", approximate, waiting), the Streak sheet's run row, the Tree view at 1× and 2×, and a
// still of the whole first screen composed the way HomeView lays it out. The real screens are verified in the app
// (docs/debug-launch-arguments.md); these are for fast review of the pieces. Not part of the app.
import Foundation
import SwiftUI

private let instant = Date(timeIntervalSinceReferenceDate: 812_000_013)
private let schedule = SleepSchedule.standard

/// Species in a plausible unlock order (each rung's day at its category's design pace).
@MainActor
private let unlockOrder: [String] = RewardCatalog.shared.assignments
    .sorted { a, b in
        let da = a.threshold / RewardCategoryInfo(a.categoryID).designPace
        let db = b.threshold / RewardCategoryInfo(b.categoryID).designPace
        return da != db ? da < db : RewardCategoryInfo(a.categoryID).order < RewardCategoryInfo(b.categoryID).order
    }
    .map(\.speciesID)

@MainActor
private func species(_ id: String) -> LeafSpecies { LeafCatalog.shared.species(id: id)! }

/// A locked leaf of `category`, `current` of the way to its first rung above it.
@MainActor
private func progress(_ category: RewardCategoryID, current: Double) -> LeafProgress {
    let rung = RewardCatalog.shared.rungs(in: category).first { $0.threshold > current }!
    return LeafProgress(speciesID: rung.speciesID, category: category, threshold: rung.threshold, tier: rung.tier,
                        current: current, availability: .available, state: .locked, estimatedDays: 4)
}

/// An approximate (confidence i or u) locked leaf.
@MainActor
private func approximateProgress() -> LeafProgress {
    let rung = RewardCatalog.shared.assignments.first { species($0.speciesID).confidence.isApproximate }!
    return LeafProgress(speciesID: rung.speciesID, category: rung.categoryID, threshold: rung.threshold, tier: rung.tier,
                        current: rung.threshold / 2, availability: .available, state: .locked, estimatedDays: 30)
}

@MainActor
private func tree(species count: Int, growth: Double, phase: NowPhase, waiting: Int = 0, vitality: Double = 1) -> TreeSceneModel {
    TreeSceneModel(
        seed: 0x00C0_FFEE_0A1E_5EED, growth: growth,
        species: unlockOrder.prefix(count).map { .init(speciesID: $0, pressed: .autumn) },
        buds: unlockOrder.dropFirst(count + waiting).prefix(3).enumerated().map { .init(speciesID: $1, progress: [0.7, 0.4, 0.15][$0]) },
        waiting: Array(unlockOrder.dropFirst(count).prefix(waiting)),
        featured: count > 3 ? unlockOrder[2] : nil, season: .autumn, seasonDay: 40, phase: phase, vitality: vitality,
        time: instant
    )
}

@MainActor
private func state(_ phase: NowPhase, pending: Int = 0) -> NowState {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/London")!
    let date = PhaseWindows(schedule: schedule).sampleDate(in: phase, onDayOf: instant, calendar: calendar)
    return NowState.resolve(date: date, schedule: schedule, calendar: calendar, locale: Locale(identifier: "en_GB"), pending: pending)
}

/// Pieces sit on the background with Home's 24pt margins.
@MainActor
private func piece<V: View>(_ name: String, height: CGFloat = 120, @ViewBuilder _ view: () -> V) -> SnapshotScene {
    SnapshotScene(name, size: CGSize(width: 402, height: height)) {
        view()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.maple.colors.background)
            .environment(\.season, .autumn)
    }
}

/// The first screen as HomeView composes it (header, stage with caption, NowBlock, row, capsule).
@MainActor
private func homeStill(
    _ name: String, species count: Int, growth: Double, phase: NowPhase, waiting: Int = 0, row: NextLeafRow.Content?,
    streak: Int = 12, vitality: Double = 1
) -> SnapshotScene {
    let now = state(phase, pending: waiting)
    let model = tree(species: count, growth: growth, phase: phase, waiting: waiting, vitality: vitality)
    let scale: CGFloat = 1
    return SnapshotScene(name) {
        VStack(spacing: 0) {
            HomeHeader(season: .autumn, date: instant, streak: streak,
                       avatar: .init(species: species(unlockOrder[max(0, count - 1)]), colourway: .autumn),
                       onStreak: {}, onAvatar: {})
                .padding(.top, 62)
            ZStack(alignment: .top) {
                MapleTreeScene(model: model, includesBackdrop: false)
                    .frame(width: 402, height: 560)
                    .offset(y: HomeLayout.sceneOffset(scale: scale))
                    .frame(width: 402, height: 410, alignment: .top)
                TreeCaption(stage: TreeStage(speciesCount: count), leaves: count, action: {})
                    .position(x: 201, y: HomeLayout.captionCentre(scale: scale))
            }
            .frame(height: 410)
            NowBlock(numeral: now.numeral.parts, caption: now.caption, spoken: now.spoken)
                .padding(.top, HomeLayout.numeralGap)
                .opacity(now.contentOpacity)
            if let row = now.waitingCount > 0 ? .waiting(count: now.waitingCount) : row {
                NextLeafRow(row, action: {})
                    .padding(.horizontal, 24)
                    .padding(.top, HomeLayout.rowGap)
                    .opacity(now.contentOpacity)
            }
            if let action = now.action {
                Button(action.title) {}
                    .buttonStyle(.moonlight(dimmed: now.actionIsDimmed))
                    .padding(.horizontal, 24)
                    .padding(.top, HomeLayout.actionGap)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 402, height: 874, alignment: .top)
        .background(alignment: .top) {
            SkyBackdrop(phase: phase, season: .autumn, vitality: vitality, time: instant).frame(width: 402, height: 560)
        }
        .background(Theme.maple.colors.background)
        .environment(\.season, .autumn)
    }
}

@MainActor
func snapshotScenes() -> [SnapshotScene] {
    let next = progress(.onTimeBedtimes, current: 9)
    let firstRung = progress(.nightsTracked, current: 0)
    var scenes: [SnapshotScene] = []

    // Whole first screen, composed.
    scenes.append(homeStill("01-home-evening-23", species: 23, growth: 0.21, phase: .evening,
                            row: .leaf(next, remainder: LeafRemainder(next, phase: .evening))))
    scenes.append(homeStill("02-home-night-23", species: 23, growth: 0.21, phase: .night,
                            row: .leaf(next, remainder: LeafRemainder(next, phase: .night))))
    scenes.append(homeStill("03-home-morning-waiting-3", species: 20, growth: 0.21, phase: .morning, waiting: 3, row: nil))
    scenes.append(homeStill("04-home-new-user-evening", species: 1, growth: 0, phase: .evening,
                            row: .leaf(firstRung, remainder: LeafRemainder(firstRung, phase: .evening)), streak: 0))
    scenes.append(homeStill("05-home-quiet", species: 23, growth: 0.21, phase: .evening,
                            row: .leaf(next, remainder: LeafRemainder(next, phase: .evening)), vitality: 0.45))

    // Header.
    scenes.append(piece("10-header-streak", height: 64) {
        HomeHeader(season: .autumn, date: instant, streak: 12, avatar: .init(species: species("rubrum"), colourway: .autumn),
                   onStreak: {}, onAvatar: {})
    })
    scenes.append(piece("11-header-new-user", height: 64) {
        HomeHeader(season: .spring, date: instant, streak: 1, avatar: .init(species: species(unlockOrder[0]), colourway: .spring),
                   onStreak: {}, onAvatar: {})
    })
    scenes.append(piece("12-tree-caption", height: 64) {
        TreeCaption(stage: .youngMaple, leaves: 23, action: {})
    })

    // NowBlock, every phase.
    for (index, phase) in NowPhase.allCases.enumerated() {
        let now = state(phase)
        scenes.append(piece(String(format: "%02d-now-%@", 20 + index, phase.rawValue), height: 140) {
            NowBlock(numeral: now.numeral.parts, caption: now.caption, spoken: now.spoken).opacity(now.contentOpacity)
        })
    }

    // Next-leaf row variants.
    let approximate = approximateProgress()
    let rows: [(String, NextLeafRow.Content)] = [
        ("30-row-progress", .leaf(next, remainder: LeafRemainder(next, phase: .evening))),
        ("31-row-tonight", .leaf(firstRung, remainder: LeafRemainder(firstRung, phase: .evening))),
        ("32-row-approximate", .leaf(approximate, remainder: LeafRemainder(approximate, phase: .day))),
        ("33-row-waiting-1", .waiting(count: 1)),
        ("34-row-waiting-2", .waiting(count: 2)),
    ]
    for (name, content) in rows {
        scenes.append(piece(name, height: 80) {
            NextLeafRow(content, action: {}).padding(.horizontal, 24)
        })
    }

    // The Streak sheet's 14 nights: a 9-night run with one forgiven miss.
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let lastNight = LocalDay(year: 2026, month: 10, day: 9)
    let onTime: [Bool] = [true, false, true, true, true, true, false, true, true, true, true, true]
    let nights = onTime.enumerated().map { index, value in
        NightRecord(day: lastNight.adding(days: index - onTime.count + 1, calendar: calendar), onTime: value, fullNight: nil, scrollFree: nil)
    }
    scenes.append(piece("40-run-row", height: 60) {
        BedtimeRunRow(marks: BedtimeRunNights.marks(nights: nights, currentRun: 9, lastNight: lastNight, calendar: calendar))
            .padding(.horizontal, 20)
    })

    // Tree view at 1× and 2×.
    let model = tree(species: 23, growth: 0.21, phase: .evening, waiting: 1)
    let viewport = CGSize(width: 402, height: 874)
    let geometry = TreeCloseUpGeometry(model: model, viewport: viewport, insets: EdgeInsets(top: 138, leading: 0, bottom: 110, trailing: 0))
    scenes.append(SnapshotScene("50-tree-view-1x") {
        TreeCloseUp(model: model, geometry: geometry, zoom: 1, pan: .zero)
    })
    scenes.append(SnapshotScene("51-tree-view-2x") {
        TreeCloseUp(model: model, geometry: geometry, zoom: 2, pan: geometry.clampedPan(CGSize(width: 60, height: 80), zoom: 2))
    })
    return scenes
}
