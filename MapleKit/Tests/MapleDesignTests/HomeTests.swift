import CoreGraphics
import Foundation
import MapleCore
import SwiftUI
import Testing
@testable import MapleDesign

/// Home's presentational logic (spec §3, §4.11, §8.4, §8.6): the vertical rhythm, what VoiceOver says, the Streak
/// sheet's nights and the Tree view's zoom, pan and hit testing.
@Suite("Home")
@MainActor
struct HomeTests {
    // MARK: Layout

    @Test("The stage is 47% of the screen, between 320 and 410, and 320 at accessibility sizes")
    func stageHeight() {
        #expect(HomeLayout.stageHeight(screenHeight: 874, accessibilitySize: false) == 410)
        #expect(HomeLayout.stageHeight(screenHeight: 956, accessibilitySize: false) == 410)
        #expect(HomeLayout.stageHeight(screenHeight: 844, accessibilitySize: false) == 396)
        #expect(HomeLayout.stageHeight(screenHeight: 600, accessibilitySize: false) == 320)
        #expect(HomeLayout.stageHeight(screenHeight: 874, accessibilitySize: true) == 320)
    }

    @Test("The scene's stage band fills the stage: at 410 the wireframe's own coordinates")
    func sceneScale() {
        #expect(HomeLayout.sceneScale(stageHeight: 410, width: 402) == 1)
        // A wide screen never stretches the scene past its stage.
        #expect(HomeLayout.sceneScale(stageHeight: 410, width: 440) == 1)
        let compact = HomeLayout.sceneScale(stageHeight: 396, width: 390)
        #expect(abs(compact - 396.0 / 410.0) < 1e-9)
        // A narrow screen is limited by its width.
        #expect(abs(HomeLayout.sceneScale(stageHeight: 410, width: 360) - 360.0 / 402.0) < 1e-9)
        // The scene starts 106pt above the stage (behind the header) and the caption sits on the ground at 494.
        #expect(HomeLayout.sceneOffset(scale: 1) == -106)
        #expect(HomeLayout.captionCentre(scale: 1) == 388)
        // Stage 106–516 + 8 + numeral 72 + 4 + caption 20 + 16 + row 56 + 12 + capsule 52 ends at 756 (§3.1).
        let end = 106 + 410 + HomeLayout.numeralGap + 72 + HomeLayout.captionGap + 20 + HomeLayout.rowGap + 56
            + HomeLayout.actionGap + 52
        #expect(end == 756)
    }

    @Test("The first screen keeps the stage while there is room, as on the wireframe")
    func firstScreenAtDefaultSize() {
        // iPhone 17e at Large: 714pt between the status bar and the tab bar, a 44pt header, and the numeral,
        // caption and row taking 179pt under the stage.
        let fit = HomeLayout.firstScreen(stageHeight: 396, visibleHeight: 714 - 44, belowStage: 179, action: 52, hasAction: true)
        #expect(fit == HeroFit(heroHeight: 396, pinsAction: false))
        // The wireframe (iPhone 17, §3.1): stage 410, numeral to row 176, capsule 52 ending 30pt above the tab bar.
        let wireframe = HomeLayout.firstScreen(stageHeight: 410, visibleHeight: 786 - 106, belowStage: 176, action: 52,
                                               hasAction: true)
        #expect(wireframe == HeroFit(heroHeight: 410, pinsAction: false))
        // Not measured yet: the preferred height.
        let unmeasured = HomeLayout.firstScreen(stageHeight: 396, visibleHeight: 670, belowStage: nil, action: nil, hasAction: true)
        #expect(unmeasured == HeroFit(heroHeight: 396, pinsAction: false))
    }

    @Test("At large text sizes the stage yields so the capsule sits fully above the tab bar")
    func firstScreenYields() {
        // iPhone 17e at accessibility-extra-large: an 86pt header and a two-line capsule.
        let visible: CGFloat = 714 - 86
        let fit = HomeLayout.firstScreen(stageHeight: 320, visibleHeight: visible, belowStage: 300, action: 92, hasAction: true)
        #expect(!fit.pinsAction)
        #expect(fit.heroHeight == visible - 300 - HomeLayout.actionGap - 92 - HeroFit.minimumBottomGap)
        #expect(fit.heroHeight >= HomeLayout.minimumFittedStageHeight)
        // Everything ends at least the minimum gap above the tab bar.
        #expect(fit.heroHeight + 300 + HomeLayout.actionGap + 92 + HeroFit.minimumBottomGap <= visible)
        // Without a row the capsule sits a row gap under the caption.
        let rowless = HomeLayout.firstScreen(stageHeight: 320, visibleHeight: visible, belowStage: 200, action: 92, hasAction: true,
                                             hasRow: false)
        #expect(rowless.heroHeight == visible - 200 - HomeLayout.rowGap - 92 - HeroFit.minimumBottomGap)
        // An unmeasured capsule counts as its 52pt minimum.
        let estimated = HomeLayout.firstScreen(stageHeight: 320, visibleHeight: visible, belowStage: 300, action: nil, hasAction: true)
        #expect(estimated.heroHeight == visible - 300 - HomeLayout.actionGap - 52 - HeroFit.minimumBottomGap)
    }

    @Test("When even the smallest stage leaves no room, the capsule is pinned above the tab bar")
    func firstScreenPins() {
        let fit = HomeLayout.firstScreen(stageHeight: 320, visibleHeight: 608, belowStage: 440, action: 140, hasAction: true)
        #expect(fit == HeroFit(heroHeight: HomeLayout.minimumFittedStageHeight, pinsAction: true))
        // With no action there is nothing to pin; the stage stays small and Home scrolls.
        let night = HomeLayout.firstScreen(stageHeight: 320, visibleHeight: 608, belowStage: 500, action: 140, hasAction: false)
        #expect(night == HeroFit(heroHeight: HomeLayout.minimumFittedStageHeight, pinsAction: false))
    }

    @Test("A small stage draws a smaller scene, so the caption's text stays inside the stage")
    func captionInsideStage() {
        // At the default size the caption's line never limits the scene.
        #expect(HomeLayout.sceneScale(stageHeight: 410, width: 402, captionTextHeight: 18) == 1)
        let compact = HomeLayout.sceneScale(stageHeight: 396, width: 390, captionTextHeight: 18)
        #expect(abs(compact - 396.0 / 410.0) < 1e-9)
        // A 170pt stage with a 46pt caption line: the caption's centre plus half its line ends at the stage's foot.
        let scale = HomeLayout.sceneScale(stageHeight: 170, width: 390, captionTextHeight: 46)
        #expect(scale < 170.0 / 410.0)
        #expect(abs(HomeLayout.captionCentre(scale: scale) + 23 - 170) < 1e-9)
    }

    @Test("A tap opens the Tree view on the stage band, but not on the waiting bud, the sky or the ground")
    func stageTaps() throws {
        let bud = CGPoint(x: 200, y: 300)
        #expect(HomeLayout.tapOpensTree(at: CGPoint(x: 100, y: 300), scale: 1, waitingBud: bud))
        #expect(!HomeLayout.tapOpensTree(at: CGPoint(x: 210, y: 312), scale: 1, waitingBud: bud))
        // Behind the header, and under the numeral.
        #expect(!HomeLayout.tapOpensTree(at: CGPoint(x: 100, y: 80), scale: 1, waitingBud: nil))
        #expect(!HomeLayout.tapOpensTree(at: CGPoint(x: 100, y: 530), scale: 1, waitingBud: nil))
        #expect(HomeLayout.tapOpensTree(at: CGPoint(x: 100, y: 500), scale: 1, waitingBud: nil))
        // At a smaller scale the band shrinks with the scene.
        #expect(!HomeLayout.tapOpensTree(at: CGPoint(x: 100, y: 500), scale: 0.78, waitingBud: nil))

        let size = CGSize(width: 402, height: 560)
        let point = try #require(HomeLayout.waitingBudPoint(model: treeModel(), sceneSize: size))
        #expect(CGRect(origin: .zero, size: size).contains(point))
        #expect(!HomeLayout.tapOpensTree(at: point, scale: 1, waitingBud: point))
        #expect(HomeLayout.waitingBudPoint(model: treeModel(waiting: false), sceneSize: size) == nil)
    }

    @Test("The sky drifts at 40% of the scroll, and not at all under Reduce Motion")
    func parallax() {
        #expect(HomeLayout.skyCounterOffset(scrollOffset: 100, reduceMotion: false) == 60)
        #expect(HomeLayout.skyCounterOffset(scrollOffset: -40, reduceMotion: false) == 0)
        #expect(HomeLayout.skyCounterOffset(scrollOffset: 100, reduceMotion: true) == 0)
    }

    // MARK: VoiceOver

    @Test("The tree reads its stage, count and growth as one sentence (§4.11)")
    func treeLabel() {
        #expect(HomeSpeech.treeLabel(stage: .youngMaple, leaves: 23, total: 155, tendedDays: 41)
            == "Your maple. Young maple, 23 of 155 leaves, grown over 41 days.")
        #expect(HomeSpeech.treeLabel(stage: .seedling, leaves: 1, total: 155, tendedDays: 1)
            == "Your maple. Seedling, 1 of 155 leaves, grown over 1 day.")
        #expect(HomeSpeech.treeLabel(stage: .seedling, leaves: 1, total: 155, tendedDays: 0)
            == "Your maple. Seedling, 1 of 155 leaves.")
        #expect(HomeSpeech.caption(stage: .youngMaple, leaves: 23, total: 155) == "23 of 155 leaves, young maple")
        #expect(HomeSpeech.streak(nights: 12) == "12-night bedtime run")
    }

    @Test("The tree's value names the newest and next leaf, then what applies")
    func treeValue() throws {
        let next = try progress(.restedNights, current: 9)
        let name = try #require(LeafCatalog.shared.species(id: next.speciesID)).displayName
        let threshold = Int(next.threshold)
        #expect(HomeSpeech.treeValue(newest: "Red maple", next: next, waiting: 0, grewToday: false, resting: false)
            == "Newest: Red maple. Next leaf: \(name), 9 of \(threshold) rested nights.")
        #expect(HomeSpeech.treeValue(newest: nil, next: nil, waiting: 1, grewToday: true, resting: true)
            == "A new leaf is waiting. Grew today. Resting.")
        #expect(HomeSpeech.treeValue(newest: nil, next: nil, waiting: 3, grewToday: false, resting: false)
            == "3 new leaves are waiting.")
    }

    @Test("The next-leaf row reads the leaf, its progress in its own words and what is left")
    func nextLeaf() throws {
        let next = try progress(.restedNights, current: 2)
        let species = try #require(LeafCatalog.shared.species(id: next.speciesID))
        let threshold = Int(next.threshold)
        var expected = "Next leaf: \(species.displayName). 2 of \(threshold) rested nights, \(threshold - 2) to go."
        if let approximate = species.confidence.approximateSpokenLabel {
            expected += " " + approximate
        }
        #expect(HomeSpeech.nextLeaf(next) == expected)

        let streak = try progress(.focusStreak, current: 2)
        #expect(HomeSpeech.amount(streak) == "2 of \(Int(streak.threshold)) days in a row")
        let hours = try progress(.hoursSaved, current: 0)
        #expect(HomeSpeech.amount(hours) == "0 of \(Int(hours.threshold)) hours saved")
        let firstHour = LeafProgress(speciesID: "rubrum", category: .hoursSaved, threshold: 1, tier: .firstSteps, current: 0,
                                     availability: .available, state: .locked, estimatedDays: 1)
        #expect(HomeSpeech.amount(firstHour) == "0 of 1 hour saved")
        #expect(HomeSpeech.waiting(1) == "A new leaf is waiting")
        #expect(HomeSpeech.waiting(2) == "2 new leaves are waiting")
    }

    @Test("Without Apple Health the row names the leaf and what it needs, with Turn on Apple Health")
    func needsPermission() {
        let rubrum = LeafProgress(speciesID: "saccharinum", category: .restedNights, threshold: 3, tier: .firstSteps, current: 0,
                                  availability: .needsAppleHealth, state: .locked, estimatedDays: nil)
        #expect(HomeSpeech.needsPermission(rubrum) == "Next leaf: Silver maple. Needs Apple Health.")
        #expect(HerbariumCopy.turnOnTitle(rubrum.availability) == "Turn on Apple Health")
        // Home's copy rule: one line of 7 words or fewer.
        #expect((HerbariumCopy.turnOnTitle(rubrum.availability) ?? "").split(separator: " ").count <= 7)
        #expect(NextLeafRow.Content.needsPermission(rubrum) != .waiting(count: 1))
    }

    @Test("Dates follow the locale: 'Sat 10 Oct' and 'Saturday 10 October' in en-GB")
    func dates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 21))!
        let british = Locale(identifier: "en_GB")
        #expect(HomeDateText.short(date, locale: british, calendar: calendar) == "Sat 10 Oct")
        #expect(HomeDateText.long(date, locale: british, calendar: calendar) == "Saturday 10 October")
        #expect(HomeSpeech.header(season: .autumn, date: date, locale: british, calendar: calendar)
            == "Autumn, Saturday 10 October")
        #expect(HomeSpeech.rosette(name: "Red maple", pressed: date, locale: british, calendar: calendar)
            == "Red maple, pressed 10 October")
        #expect(HomeSpeech.rosette(name: "Red maple", pressed: nil) == "Red maple")

        // Formatters are reused, but never across time zones or locales.
        var tokyo = calendar
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        #expect(HomeDateText.dayMonth(date, locale: british, calendar: tokyo) == "11 October")
        #expect(HomeDateText.dayMonth(date, locale: british, calendar: calendar) == "10 October")
        #expect(HomeDateText.dayMonth(date, locale: Locale(identifier: "en_US"), calendar: calendar) == "October 10")
    }

    // MARK: Streak nights

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let lastNight = LocalDay(year: 2026, month: 10, day: 9)

    private func nights(_ onTime: [Bool?]) -> [NightRecord] {
        // Oldest first, ending last night.
        onTime.enumerated().map { index, value in
            NightRecord(day: lastNight.adding(days: index - onTime.count + 1, calendar: calendar), onTime: value, fullNight: nil, scrollFree: nil)
        }
    }

    // MARK: Tree view

    private func treeModel(species count: Int = 23, growth: Double = 0.21, waiting: Bool = true) -> TreeSceneModel {
        let ids = RewardCatalog.shared.assignments.map(\.speciesID)
        return TreeSceneModel(
            seed: 0xC0FFEE, growth: growth,
            species: ids.prefix(count).map { .init(speciesID: $0, pressed: .autumn) },
            buds: ids.dropFirst(count + 1).prefix(3).map { .init(speciesID: $0, progress: 0.5) },
            waiting: waiting && count < ids.count ? [ids[count]] : [],
            season: .autumn, phase: .evening
        )
    }

    private let viewport = CGSize(width: 390, height: 844)
    private let insets = EdgeInsets(top: 123, leading: 0, bottom: 102, trailing: 0)

    @Test("The tree is fitted to the width minus 32 and stays inside the space between the bars")
    func treeFit() {
        for (count, growth) in [(1, 0.0), (23, 0.21), (155, 1.0)] {
            let geometry = TreeCloseUpGeometry(model: treeModel(species: count, growth: growth), viewport: viewport, insets: insets)
            let rect = geometry.restTreeRect
            #expect(rect.width <= viewport.width - 32 + 0.5)
            #expect(rect.minY >= CGFloat(insets.top) - 0.5)
            #expect(geometry.restBase.y <= viewport.height - CGFloat(insets.bottom) + 0.5)
            #expect(geometry.fitScale <= TreeCloseUpGeometry.maximumFit)
            #expect(abs(rect.midX - viewport.width / 2) < 0.5)
            // Every placed species has its own primary rosette to tap.
            #expect(Set(geometry.targets.filter(\.isPrimary).map(\.speciesID)).count == count)
        }
    }

    @Test("Zoom keeps the pinch anchor still; pan is clamped, and nothing pans at 1×")
    func zoomAndPan() {
        let geometry = TreeCloseUpGeometry(model: treeModel(), viewport: viewport, insets: insets)
        let point = CGPoint(x: 120, y: 300)
        #expect(geometry.screenPoint(point, zoom: 1, pan: .zero) == point)
        let anchor = CGPoint(x: 250, y: 400)
        let pan = geometry.pan(keeping: anchor, from: 1, to: 2.5, startingPan: .zero)
        // The rest point under the anchor before the pinch is still under it after.
        let restUnderAnchor = anchor
        let moved = geometry.screenPoint(restUnderAnchor, zoom: 2.5, pan: pan)
        #expect(abs(moved.x - anchor.x) < 1e-6 && abs(moved.y - anchor.y) < 1e-6)
        #expect(geometry.clampedPan(CGSize(width: 80, height: -60), zoom: 1) == .zero)
        let far = geometry.clampedPan(CGSize(width: 10_000, height: -10_000), zoom: 3)
        #expect(far.width > 0 && far.width < 10_000)
        #expect(far.height < 0 && far.height > -10_000)
    }

    @Test("A tap hits the waiting bud first, then the nearest rosette within 22pt")
    func hits() throws {
        let geometry = TreeCloseUpGeometry(model: treeModel(), viewport: viewport, insets: insets)
        let bud = try #require(geometry.restWaitingBud)
        #expect(geometry.hit(at: bud.point, zoom: 1, pan: .zero) == .waitingBud(speciesID: bud.speciesID))

        let target = try #require(geometry.targets.first { hypot($0.restPoint.x - bud.point.x, $0.restPoint.y - bud.point.y) > 50 })
        #expect(geometry.hit(at: target.restPoint, zoom: 1, pan: .zero) == .rosette(speciesID: target.speciesID))
        // Zoomed and panned, the same rosette is found where it is drawn.
        let pan = CGSize(width: 30, height: -20)
        let zoomed = geometry.screenPoint(target.restPoint, zoom: 2, pan: pan)
        #expect(geometry.hit(at: zoomed, zoom: 2, pan: pan) == .rosette(speciesID: target.speciesID))
        // Far from the tree, nothing.
        #expect(geometry.hit(at: CGPoint(x: 5, y: 5), zoom: 1, pan: .zero) == nil)
    }

    @Test("VoiceOver meets each species once, top to bottom and left to right")
    func readingOrder() {
        let geometry = TreeCloseUpGeometry(model: treeModel(), viewport: viewport, insets: insets)
        let order = geometry.readingOrder()
        #expect(order.count == 23)
        #expect(Set(order.map(\.speciesID)).count == 23)
        for (a, b) in zip(order, order.dropFirst()) {
            let rowA = (a.restPoint.y / 36).rounded(.down), rowB = (b.restPoint.y / 36).rounded(.down)
            #expect(rowA < rowB || (rowA == rowB && a.restPoint.x <= b.restPoint.x))
        }
    }

    // MARK: Helpers

    /// A locked leaf of `category` with `current` progress: the lowest rung above `current`.
    private func progress(_ category: RewardCategoryID, current: Double) throws -> LeafProgress {
        let rung = try #require(RewardCatalog.shared.rungs(in: category).first { $0.threshold > current + 1 })
        return LeafProgress(
            speciesID: rung.speciesID, category: category, threshold: rung.threshold, tier: rung.tier, current: current,
            availability: .available, state: .locked, estimatedDays: 3
        )
    }
}
