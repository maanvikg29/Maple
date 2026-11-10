import CoreGraphics
import Foundation
import MapleCore
import SwiftUI
import Testing
@testable import MapleDesign

/// The MapleDesign components of docs/design/spec.md §7.3: their pure logic, and the few visual rules a
/// pixel can prove (containers never cast shadows; amber appears only where something was earned).
@Suite("Components")
@MainActor
struct ComponentTests {
    // MARK: ProgressHairline

    @Test("ProgressHairline clamps its fraction to 0...1, treating NaN as no progress")
    func hairlineClamping() {
        #expect(ProgressHairline.clamped(-0.5) == 0)
        #expect(ProgressHairline.clamped(0) == 0)
        #expect(ProgressHairline.clamped(0.35) == 0.35)
        #expect(ProgressHairline.clamped(1) == 1)
        #expect(ProgressHairline.clamped(3) == 1)
        #expect(ProgressHairline.clamped(.nan) == 0)
        #expect(ProgressHairline.clamped(.infinity) == 1)
        #expect(ProgressHairline.clamped(-.infinity) == 0)
    }

    @Test("The fill is proportional, never shorter than a dot once there is progress, never past the track")
    func hairlineFillWidth() {
        #expect(ProgressHairline.fillWidth(fraction: 0, totalWidth: 300, height: 2) == 0)
        #expect(ProgressHairline.fillWidth(fraction: .nan, totalWidth: 300, height: 2) == 0)
        // 1 of 540 nights on a 300pt track would be 0.56pt: it shows as a 2pt dot instead.
        #expect(ProgressHairline.fillWidth(fraction: 1.0 / 540, totalWidth: 300, height: 2) == 2)
        #expect(ProgressHairline.fillWidth(fraction: 0.5, totalWidth: 300, height: 2) == 150)
        #expect(ProgressHairline.fillWidth(fraction: 1, totalWidth: 300, height: 4) == 300)
        #expect(ProgressHairline.fillWidth(fraction: 2, totalWidth: 300, height: 4) == 300)
        #expect(ProgressHairline.fillWidth(fraction: 0.5, totalWidth: 0, height: 2) == 0)
        // A dot never overflows a track shorter than itself.
        #expect(ProgressHairline.fillWidth(fraction: 0.01, totalWidth: 1, height: 3) == 1)
    }

    // MARK: Buds

    @Test("A growing bud swells from 0.4 to full size with progress, and never shrinks")
    func budScale() {
        #expect(BudGlyph.scale(forProgress: 0) == 0.4)
        #expect(abs(BudGlyph.scale(forProgress: 0.5) - 0.7) < 1e-12)
        #expect(BudGlyph.scale(forProgress: 1) == 1)
        #expect(BudGlyph.scale(forProgress: -1) == 0.4)
        #expect(BudGlyph.scale(forProgress: 4) == 1)
        #expect(BudGlyph.scale(forProgress: .nan) == 0.4)
        let steps = stride(from: 0.0, through: 1.0, by: 0.05).map { BudGlyph.scale(forProgress: $0) }
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test("The waiting bud's core glow is 60% when small and 35% at reveal size, never above the cap")
    func budCoreGlow() {
        #expect(BudGlyph.coreOpacity(side: 32) == 0.6)
        #expect(BudGlyph.coreOpacity(side: 48) == 0.6)
        #expect(abs(BudGlyph.coreOpacity(side: 96) - 0.35) < 1e-12)
        #expect(abs(BudGlyph.coreOpacity(side: 200) - 0.35) < 1e-12)
        let cap = Theme.maple.elevation.waitingBudCoreCap
        for side in stride(from: 8.0, through: 240, by: 8) {
            #expect(BudGlyph.coreOpacity(side: side, cap: cap) <= cap)
        }
        #expect(BudGlyph.coreOpacity(side: 32, cap: 0.5) == 0.5)
    }

    @Test("BudShape draws two distinct scales inside its rectangle, the inner one's tip highest")
    func budShapeScales() {
        let rect = CGRect(x: 0, y: 0, width: 64, height: 100)
        let back = BudShape(.back).path(in: rect).boundingRect
        let front = BudShape(.front).path(in: rect).boundingRect
        let whole = BudShape(.whole).path(in: rect).boundingRect
        #expect(rect.insetBy(dx: -0.5, dy: -0.5).contains(whole))
        #expect(back != front)
        #expect(back.minX < front.minX)
        #expect(back.minY < front.minY)
        let union = back.union(front)
        #expect(abs(whole.minX - union.minX) < 0.01 && abs(whole.maxX - union.maxX) < 0.01)
        #expect(abs(whole.minY - union.minY) < 0.01 && abs(whole.maxY - union.maxY) < 0.01)
        // Each scale turns about its own base, at the bottom of the bud.
        #expect(BudShape.pivot(of: .front, in: rect).y == rect.maxY)
        #expect(BudShape.pivot(of: .back, in: rect).x < BudShape.pivot(of: .front, in: rect).x)
    }

    // MARK: Member share copy (spec §5.7)

    private let copy = MemberShareCopy(locale: Locale(identifier: "en_GB"), timeZone: TimeZone(identifier: "UTC")!)

    private func date(_ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!
    }

    /// Every `MemberShare` case. The switch fails to compile when a case is added, so the copy tests keep up.
    private var everyShare: [MemberShare] {
        let shares: [MemberShare] = [
            .loading, .value(display: "22%", asOf: date(3)), .stale(display: "22%", asOf: date(3)),
            .notEnoughMembers(soFar: nil), .notEnoughMembers(soFar: 640), .neverFetched, .newSpecies, .notEarnableYet,
        ]
        for share in shares {
            switch share {
            case .loading, .value, .stale, .notEnoughMembers, .neverFetched, .newSpecies, .notEarnableYet: break
            }
        }
        return shares
    }

    @Test("Detail copy for every state")
    func detailCopy() {
        let caption = "of members have this leaf"
        #expect(copy.detail(.loading) == .placeholder)
        #expect(copy.detail(.value(display: "22%", asOf: date(3))) == .value("22%", caption: caption, asOf: nil))
        #expect(copy.detail(.value(display: "Under 1%", asOf: date(3))) == .value("Under 1%", caption: caption, asOf: nil))
        #expect(copy.detail(.stale(display: "22%", asOf: date(3))) == .value("22%", caption: caption, asOf: "As of 3 Oct"))
        #expect(copy.detail(.notEnoughMembers(soFar: nil)) == .message("Rarity appears once 1,000 members take part"))
        #expect(copy.detail(.notEnoughMembers(soFar: 640))
            == .message("Rarity appears once 1,000 members take part · 640 so far"))
        #expect(copy.detail(.neverFetched) == .message("Rarity shows when you're online"))
        #expect(copy.detail(.newSpecies) == .message("New · rarity next week"))
        #expect(copy.detail(.notEarnableYet) == .message("Not earnable yet"))
    }

    @Test("Tile meta shows the share, else the pressed date, never a placeholder")
    func tileCopy() {
        let pressed = date(4)
        #expect(copy.tile(.value(display: "22%", asOf: date(3)), pressedOn: pressed) == "22% have it")
        // Stale: the value, without its date.
        #expect(copy.tile(.stale(display: "22%", asOf: date(3)), pressedOn: pressed) == "22% have it")
        for share: MemberShare in [.loading, .notEnoughMembers(soFar: nil), .notEnoughMembers(soFar: 640), .neverFetched, .newSpecies] {
            #expect(copy.tile(share, pressedOn: pressed) == "4 Oct")
            #expect(copy.tile(share, pressedOn: nil) == "No rarity yet")
        }
        #expect(copy.tile(.notEarnableYet, pressedOn: pressed) == "Not earnable yet")
    }

    @Test("Inline (reveal) copy for every state")
    func inlineCopy() {
        #expect(copy.inline(.loading) == .placeholder)
        #expect(copy.inline(.value(display: "22%", asOf: date(3))) == .value("22%", rest: " of members have this"))
        #expect(copy.inline(.stale(display: "22%", asOf: date(3))) == .value("22%", rest: " of members have this · as of 3 Oct"))
        for share: MemberShare in [.notEnoughMembers(soFar: 640), .neverFetched, .newSpecies, .notEarnableYet] {
            guard case .message(let detail) = copy.detail(share) else {
                Issue.record("\(share) should be a message in detail")
                continue
            }
            #expect(copy.inline(share) == .message(detail))
        }
    }

    @Test("The share card's line appears only for a fresh value")
    func shareCardCopy() {
        #expect(MemberShareCopy.shareCard(.value(display: "22%", asOf: date(3))) == "22% of Maple members have it")
        for share in everyShare {
            if case .value = share { continue }
            #expect(MemberShareCopy.shareCard(share) == nil)
        }
    }

    @Test("VoiceOver reads every state in words; loading says so")
    func accessibilityCopy() {
        let pressed = date(4)
        #expect(copy.accessibilityLabel(.loading, layout: .detail, pressedOn: nil) == "Loading rarity")
        #expect(copy.accessibilityLabel(.loading, layout: .inline, pressedOn: nil) == "Loading rarity")
        #expect(copy.accessibilityLabel(.loading, layout: .tile, pressedOn: pressed) == "4 Oct")
        #expect(copy.accessibilityLabel(.value(display: "22%", asOf: date(3)), layout: .detail, pressedOn: nil)
            == "22% of members have this leaf")
        #expect(copy.accessibilityLabel(.stale(display: "22%", asOf: date(3)), layout: .detail, pressedOn: nil)
            == "22% of members have this leaf. As of 3 Oct")
        #expect(copy.accessibilityLabel(.value(display: "22%", asOf: date(3)), layout: .inline, pressedOn: nil)
            == "22% of members have this")
        for share in everyShare {
            for layout in [MemberShareLabel.Layout.detail, .tile, .inline] {
                let label = copy.accessibilityLabel(share, layout: layout, pressedOn: pressed)
                #expect(!label.isEmpty)
            }
        }
    }

    @Test("No state ever shows 0%, 100%, a dash or tracked capitals")
    func honestCopy() {
        var lines: [String] = []
        for share in everyShare {
            lines.append(copy.tile(share, pressedOn: date(4)))
            lines.append(copy.tile(share, pressedOn: nil))
            switch copy.detail(share) {
            case .placeholder: break
            case .value(let value, let caption, let asOf): lines += [value, caption, asOf].compactMap(\.self)
            case .message(let message): lines.append(message)
            }
            if case .value(let value, let rest) = copy.inline(share) { lines.append(value + rest) }
            if let card = MemberShareCopy.shareCard(share) { lines.append(card) }
        }
        for line in lines {
            #expect(!line.isEmpty)
            #expect(!line.hasPrefix("0%") && !line.contains(" 0%"), "\(line)")
            #expect(!line.contains("100%"), "\(line)")
            #expect(line != "—" && line != "-" && line != "0")
            #expect(line != line.uppercased() || !line.contains { $0.isLetter }, "No capitals-only copy: \(line)")
            #expect(!line.contains("!"), "No exclamation marks: \(line)")
        }
    }

    // MARK: Approximate labelling (spec §5.2)

    @Test("Approximate drawings carry the ≈ chip, spoken label and accuracy note; documented ones carry none")
    func approximateLabels() {
        #expect(LeafSpecies.Confidence.documented.approximateChipTitle == nil)
        #expect(LeafSpecies.Confidence.inferred.approximateChipTitle == "≈ Approximate drawing")
        #expect(LeafSpecies.Confidence.placeholder.approximateChipTitle == "≈ Uncharted")
        #expect(LeafSpecies.Confidence.documented.approximateSpokenLabel == nil)
        #expect(LeafSpecies.Confidence.inferred.approximateSpokenLabel == "Approximate drawing.")
        #expect(LeafSpecies.Confidence.placeholder.approximateSpokenLabel == "Uncharted, placeholder drawing.")
        #expect(LeafSpecies.Confidence.documented.accuracyNote == nil)
        #expect(LeafSpecies.Confidence.inferred.accuracyNote?.hasPrefix("Approximate.") == true)
        #expect(LeafSpecies.Confidence.placeholder.accuracyNote?.hasPrefix("Uncharted.") == true)
        #expect(SmallChip(approximate: .documented) == nil)
        #expect(SmallChip(approximate: .inferred) != nil)
    }

    // MARK: Layout maths

    @Test("StatNumber puts a word space before a value that follows a unit: 1h 20m")
    func statNumberGrouping() {
        let parts: [StatNumber.Part] = [.value("1"), .unit("h"), .value("20"), .unit("m")]
        #expect((0..<parts.count).map { StatNumber.startsNewGroup(parts, at: $0) } == [false, false, true, false])
        #expect(!StatNumber.startsNewGroup([.value("07:00")], at: 0))
        #expect(!StatNumber.startsNewGroup(parts, at: 9))
    }

    @Test("The segmented thumb covers exactly one segment inside the track's inset")
    func segmentedThumb() {
        let width = SegmentedCapsuleMetrics.thumbWidth(total: 304, count: 3)
        #expect(width == 100)
        #expect(SegmentedCapsuleMetrics.thumbOffset(index: 0, thumbWidth: width) == 2)
        #expect(SegmentedCapsuleMetrics.thumbOffset(index: 2, thumbWidth: width) == 202)
        #expect(SegmentedCapsuleMetrics.thumbOffset(index: 2, thumbWidth: width) + width == CGFloat(302))
        #expect(SegmentedCapsuleMetrics.thumbWidth(total: 304, count: 0) == 0)
    }

    @Test("ChipFlow wraps chips into rows, and gives a chip wider than a row the whole row")
    func chipFlowRows() {
        let chip = CGSize(width: 100, height: 22)
        let rows = ChipFlowRows(sizes: [chip, chip, chip, chip], maxWidth: 320, spacing: 8, lineSpacing: 8)
        #expect(rows.rows.map(\.items.count) == [3, 1])
        #expect(rows.rows[0].items.map(\.x) == [0, 108, 216])
        #expect(rows.rows[1].y == 30)
        #expect(rows.size == CGSize(width: 316, height: 52))

        let wide = ChipFlowRows(sizes: [CGSize(width: 500, height: 22), chip], maxWidth: 320, spacing: 8, lineSpacing: 8)
        #expect(wide.rows.map(\.items.count) == [1, 1])
        #expect(wide.rows[0].items[0].size.width == 320)
        #expect(ChipFlowRows(sizes: [], maxWidth: 320, spacing: 8, lineSpacing: 8).size == .zero)
    }

    @Test("Specimen bloom and contact shadow scale between the spec's tile and detail values")
    func specimenMetrics() {
        let tile = SpecimenMetrics(size: 64)
        #expect(abs(tile.bloomRadius - 70) < 1)
        #expect(abs(tile.shadowSize.width - 40) < 1)
        #expect(abs(tile.shadowSize.height - 5) < 0.5)
        #expect(tile.shadowOpacity == 0.5)

        let detail = SpecimenMetrics(size: 200)
        #expect(abs(detail.bloomRadius - 180) < 1)
        #expect(abs(detail.shadowSize.width - 120) < 1)
        #expect(abs(detail.shadowSize.height - 10) < 0.5)
        #expect(detail.shadowOpacity == 0.45)
        // Contact shadows stay within the spec's blur range of 6–10 at every size.
        for size in stride(from: 16.0, through: 320, by: 8) {
            #expect((6...10).contains(SpecimenMetrics(size: size).shadowBlur))
        }
        #expect(abs(tile.shadowBlur - 6) < 0.05)
        #expect(abs(detail.shadowBlur - 10) < 0.05)
    }

    @Test("Selected and approximate hairlines rise with Increase Contrast")
    func contrastHairlines() {
        #expect(abs(Theme.maple.selectedHairline.opacityValue - 0.14) < 0.005)
        #expect(abs(Theme.mapleIncreasedContrast.selectedHairline.opacityValue - 0.30) < 0.005)
    }

    // MARK: Pixels

    /// RGBA rows of a view rendered at `size` points, scale 1.
    private func pixels(of view: some View, size: CGSize) throws -> [UInt8] {
        let width = Int(size.width), height = Int(size.height)
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        try #require(drawn)
        return pixels
    }

    /// Alpha of every pixel outside `inner` (a rectangle in points, top-left origin).
    private func alphaOutside(_ inner: CGRect, in pixels: [UInt8], size: CGSize) -> [UInt8] {
        var result: [UInt8] = []
        for y in 0..<Int(size.height) {
            for x in 0..<Int(size.width) where !inner.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) {
                result.append(pixels[(y * Int(size.width) + x) * 4 + 3])
            }
        }
        return result
    }

    @Test("Level 1 draws nothing outside its shape: no glow, no shadow. Level 2 alone glows")
    func surfacesCastNoShadow() throws {
        let canvas = CGSize(width: 160, height: 160)
        let inner = CGRect(x: 40, y: 40, width: 80, height: 80)
        func tile(_ level: SurfaceLevel) -> some View {
            Color.clear.frame(width: 80, height: 80).surface(level, radius: 20).frame(width: 160, height: 160)
        }
        let level1 = try pixels(of: tile(.level1), size: canvas)
        #expect(alphaOutside(inner, in: level1, size: canvas).allSatisfy { $0 == 0 })
        // Level 0 changes nothing at all.
        let square = Color.red.frame(width: 80, height: 80).frame(width: 160, height: 160)
        let plain = try pixels(of: square, size: canvas)
        let level0 = try pixels(of: Color.red.frame(width: 80, height: 80).surface(.level0, radius: 20)
            .frame(width: 160, height: 160), size: canvas)
        #expect(plain == level0)
        let level2 = try pixels(of: tile(.level2), size: canvas)
        #expect(alphaOutside(inner, in: level2, size: canvas).contains { $0 > 0 })
    }

    /// Whether any pixel is close to the reward amber's hue (about 31°) with real saturation.
    private func containsAmber(_ pixels: [UInt8]) -> Bool {
        stride(from: 0, to: pixels.count, by: 4).contains { index in
            let alpha = Double(pixels[index + 3])
            guard alpha > 40 else { return false }
            let r = Double(pixels[index]) / alpha, g = Double(pixels[index + 1]) / alpha, b = Double(pixels[index + 2]) / alpha
            let maxC = max(r, g, b), minC = min(r, g, b)
            guard maxC == r, maxC - minC > 0.25 else { return false }
            let hue = 60 * ((g - b) / (maxC - minC))
            return (24...38).contains(hue)
        }
    }

    @Test("Amber appears on a specimen only while its leaf is waiting (spec §1.3)")
    func amberOnlyWhenWaiting() throws {
        // Red maple turns crimson, far from amber, so any amber here would come from the component.
        let rubrum = try #require(LeafCatalog.shared.species(id: "rubrum"))
        let size = CGSize(width: 96, height: 108)
        let states: [SpecimenState] = [.earned, .next(progress: 0.6), .locked, .needsPermission, .dormant]
        for state in states {
            let view = SpecimenView(species: rubrum, colourway: .autumn, size: 96, state: state)
            #expect(!containsAmber(try pixels(of: view, size: size)), "\(state)")
        }
        let waiting = SpecimenView(species: rubrum, colourway: .autumn, size: 96, state: .waiting)
        #expect(containsAmber(try pixels(of: waiting, size: size)))
        // Nothing is earned yet in the needs-permission row or the Apple Health primer.
        let needs = LeafProgress(speciesID: "rubrum", category: .restedNights, threshold: 1, tier: .common, current: 0,
                                 availability: .needsAppleHealth, state: .locked, estimatedDays: nil)
        let row = NextLeafRow(.needsPermission(needs), action: {}, turnOn: {}).frame(width: 354).background(Color.black)
        #expect(!containsAmber(try pixels(of: row, size: CGSize(width: 354, height: 64))))
        let primer = HealthPrimerView(species: rubrum, colourway: .autumn, onContinue: {}, onNotNow: {})
            .frame(width: 402, height: 420).background(Color.black)
        #expect(!containsAmber(try pixels(of: primer, size: CGSize(width: 402, height: 420))))
        let resting = BudGlyph(waiting: false).frame(width: 96, height: 96)
        #expect(!containsAmber(try pixels(of: resting, size: CGSize(width: 96, height: 96))))
    }

    @Test("Every component renders in every state without failing")
    func componentsRender() throws {
        let rubrum = try #require(LeafCatalog.shared.species(id: "rubrum"))
        let views: [AnyView] = [
            AnyView(Button("Start wind-down") {}.buttonStyle(.moonlight)),
            AnyView(Button("Start wind-down") {}.buttonStyle(.moonlight(dimmed: true))),
            AnyView(Button("Start focus") {}.buttonStyle(.moonlight).disabled(true)),
            AnyView(Button("Sleep sounds") {}.buttonStyle(.glassCapsule).environment(\.drawsGlassAsSolid, true)),
            AnyView(Button("Turn on") {}.buttonStyle(.glassCapsule(.compact)).environment(\.drawsGlassAsSolid, true)),
            AnyView(Button("Filter", systemImage: "line.3.horizontal.decrease") {}
                .buttonStyle(.iconCircle(badge: 2)).environment(\.drawsGlassAsSolid, true)),
            AnyView(TextLink("All insights") {}),
            AnyView(Chip("Earned", count: 23, isSelected: true) {}),
            AnyView(SmallChip(tier: .rare)),
            AnyView(SegmentedCapsule(selection: .constant(1), options: [0, 1, 2]) { "\($0)" }),
            AnyView(ProgressHairline(fraction: 0.4)),
            AnyView(BudGlyph(waiting: true)),
            AnyView(MemberShareLabel(share: .loading, layout: .detail)),
            AnyView(MemberShareLabel(share: .value(display: "22%", asOf: .now), layout: .inline)),
            AnyView(StatNumber([.value("1"), .unit("h"), .value("20"), .unit("m")])),
        ] + [SpecimenState.earned, .next(progress: 0.3), .locked, .waiting, .needsPermission, .dormant].map {
            AnyView(SpecimenView(species: rubrum, colourway: .autumn, size: 64, state: $0))
        }
        for view in views {
            let rendered = try pixels(of: view.background(Color.black), size: CGSize(width: 200, height: 120))
            #expect(rendered.count == 200 * 120 * 4)
        }
    }
}
