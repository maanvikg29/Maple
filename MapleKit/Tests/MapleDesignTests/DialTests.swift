import CoreGraphics
import Foundation
import MapleCore
import SwiftUI
import Testing
@testable import MapleDesign

private let fifty = DialLayout(plannedMinutes: 50)
private let gapMarks: [MarkState] = (0..<50).map { (22..<27).contains($0) ? .gap : .lit }

// MARK: - Tokens

/// The dial's colours (F1 design §4.2), gold (F1-18) and the bloom, in both themes.
@Suite("Dial tokens")
@MainActor
struct DialTokenTests {
    private func rgb(_ colour: Color) -> (r: Int, g: Int, b: Int) {
        let resolved = colour.resolve(in: EnvironmentValues())
        return (Int((resolved.red * 255).rounded()), Int((resolved.green * 255).rounded()), Int((resolved.blue * 255).rounded()))
    }

    private func matches(_ colour: Color, _ hex: UInt32) -> Bool {
        let value = rgb(colour)
        return abs(value.r - Int((hex >> 16) & 0xFF)) <= 1 && abs(value.g - Int((hex >> 8) & 0xFF)) <= 1
            && abs(value.b - Int(hex & 0xFF)) <= 1
    }

    @Test("Marks are textPrimary at the §4.2 opacities (rest is #C9D3E3), raised under Increase Contrast only where the table raises them")
    func markColours() {
        let normal = Theme.maple.dial, raised = Theme.mapleIncreasedContrast.dial
        let rows: [(String, (Theme.Dial) -> Color, Double, Double, UInt32)] = [
            ("plan", { $0.plan }, 0.42, 0.60, 0xF2F5FA),
            ("ahead", { $0.ahead }, 0.16, 0.30, 0xF2F5FA),
            ("lit", { $0.lit }, 0.88, 1, 0xF2F5FA),
            ("rest", { $0.rest }, 0.78, 1, 0xC9D3E3),
            ("gap", { $0.gap }, 0.09, 0.22, 0xF2F5FA),
            ("hold", { $0.hold }, 1, 1, 0xF2F5FA),
            ("off", { $0.off }, 0.10, 0.22, 0xF2F5FA),
        ]
        for (name, token, opacity, contrast, hex) in rows {
            #expect(abs(token(normal).opacityValue - opacity) < 0.005, "\(name)")
            #expect(abs(token(raised).opacityValue - contrast) < 0.005, "\(name) under Increase Contrast")
            #expect(matches(token(normal), hex) && matches(token(raised), hex), "\(name)'s colour")
        }
        #expect(normal.currentLow == 0.55 && normal.currentHigh == 1)
        #expect(raised.currentLow == 1 && raised.currentHigh == 1)
    }

    @Test("Gold, its softer and edge tones, the vein and the blooms, the same in both themes")
    func goldTones() {
        let dial = Theme.maple.dial
        #expect(matches(dial.gold, 0xF0C24A) && abs(dial.gold.opacityValue - 1) < 0.005)
        #expect(matches(dial.goldSoft, 0xC99A2C) && abs(dial.goldSoft.opacityValue - 0.62) < 0.005)
        #expect(matches(dial.goldEdge, 0xFFE8A8) && abs(dial.goldEdge.opacityValue - 0.85) < 0.005)
        #expect(matches(dial.goldVein, 0x725811) && abs(dial.goldVein.opacityValue - 1) < 0.005)
        #expect(dial.bloom == 0.14)
        #expect(matches(dial.goldBloom, 0xF0C24A) && abs(dial.goldBloom.opacityValue - 0.18) < 0.005)
        #expect(matches(dial.restBloom, 0xC9D3E3) && abs(dial.restBloom.opacityValue - 0.12) < 0.005)
        // §4.2 gives these no Increase Contrast value.
        let raised = Theme.mapleIncreasedContrast.dial
        #expect(matches(raised.gold, 0xF0C24A) && matches(raised.goldSoft, 0xC99A2C) && raised.bloom == dial.bloom)
    }

    @Test("Gold is its own colour: outside the reward amber's hue, and never the reward token (F1-18)")
    func goldIsNotAmber() {
        // Red is the largest channel and blue the smallest for each of these.
        func hue(_ colour: Color) -> Double {
            let value = rgb(colour)
            return 60 * Double(value.g - value.b) / Double(value.r - value.b)
        }
        for colour in [Theme.maple.dial.gold, Theme.maple.dial.goldSoft, Theme.maple.dial.goldEdge] {
            #expect(hue(colour) > 38 && hue(colour) < 50)
        }
        #expect(hue(Theme.maple.colors.reward) < 38)
        #expect(!matches(Theme.maple.dial.gold, 0xE8A35C))
    }

    @Test("Both themes carry every dial field, and the Increase Contrast theme carries its own values")
    func bothThemes() {
        let names = Mirror(reflecting: Theme.maple.dial).children.compactMap(\.label)
        #expect(names == [
            "plan", "ahead", "lit", "currentLow", "currentHigh", "rest", "gap", "hold", "off",
            "gold", "goldSoft", "goldEdge", "goldVein", "bloom", "goldBloom", "restBloom",
        ])
        #expect(Mirror(reflecting: Theme.mapleIncreasedContrast.dial).children.compactMap(\.label) == names)
        #expect(abs(Theme.mapleIncreasedContrast.dial.ahead.opacityValue - 0.30) < 0.005)
        #expect(abs(Theme(colors: .maple).dial.ahead.opacityValue - 0.16) < 0.005)
        // The rest of the Increase Contrast theme is as it was.
        #expect(abs(Theme.mapleIncreasedContrast.colors.track.opacityValue - 0.16) < 0.005)
    }

    @Test("A mark's colour is its token, or for the current mark the season tint at its brightness")
    func colourForState() {
        let tint = Color(hex: 0xE3A49E)
        let dial = Theme.maple.dial
        #expect(dial.colour(for: .plan, tint: tint, brightness: 0.6) == dial.plan)
        #expect(dial.colour(for: .gap, tint: tint, brightness: 0.6) == dial.gap)
        #expect(dial.colour(for: .rest, tint: tint, brightness: 0.6) == dial.rest)
        #expect(abs(dial.colour(for: .current, tint: tint, brightness: 0.55).opacityValue - 0.55) < 0.005)
        #expect(abs(dial.colour(for: .current, tint: tint, brightness: 0.775).opacityValue - 0.775) < 0.005)
        #expect(abs(dial.colour(for: .current, tint: tint, brightness: 1).opacityValue - 1) < 0.005)
        #expect(abs(dial.currentOpacity(brightness: 0.1) - 0.55) < 1e-9)
        #expect(abs(dial.currentOpacity(brightness: .nan) - 1) < 1e-9)
        #expect(matches(dial.colour(for: .current, tint: tint, brightness: 1), 0xE3A49E))
        #expect(abs(Theme.mapleIncreasedContrast.dial.colour(for: .current, tint: tint, brightness: 0.55).opacityValue - 1) < 0.005)
    }
}

// MARK: - Frames

/// `DialFrame`, the dial as plain values (F1 design §4.8), and its builders for every screen.
@Suite("Dial frames")
struct DialFrameTests {
    @Test("Preview: plan marks, the leaf dot in season tint at its minute, the saved fill and a soft bloom")
    func preview() throws {
        let frame = DialFrame.preview(layout: fifty, leafMinute: 35, fill: DialFill(before: 0.4))
        #expect(frame.marks == Array(repeating: .plan, count: 50))
        let dot = try #require(frame.dot)
        #expect(abs(dot.angle - fifty.angle(atMinute: 35)) < 1e-12 && !dot.reached)
        #expect(frame.fill == DialFill(before: 0.4))
        #expect(frame.bloom == DialBloom(tint: 0.4))
        #expect(DialFrame.preview(layout: fifty).dot == nil)
        #expect(DialFrame.preview(layout: fifty, leafMinute: 51).dot == nil)
        #expect(DialFrame.preview(layout: fifty, leafMinute: 0).dot == nil)
        #expect(DialFrame.preview(layout: DialLayout(plannedMinutes: 90)).marks.count == 45)
    }

    @Test("Running: passed minutes lit, the current one brightening from 55% to 100%, the rest still to come")
    func running() {
        let frame = DialFrame.running(layout: fifty, elapsed: 18.4 * 60, leafMinute: 35, fill: DialFill(before: 0.4, session: 0.2))
        #expect(frame.marks[..<18].allSatisfy { $0 == .lit })
        #expect(frame.marks[18] == .current)
        #expect(frame.marks[19...].allSatisfy { $0 == .ahead })
        #expect(abs(frame.currentBrightness - (0.55 + 0.45 * 0.4)) < 1e-6)
        let atMinute = DialFrame.running(layout: fifty, elapsed: 18 * 60, leafMinute: nil, fill: DialFill())
        #expect(abs(atMinute.currentBrightness - 0.55) < 1e-9)
        let endOfMinute = DialFrame.running(layout: fifty, elapsed: 18 * 60 + 59.9, leafMinute: nil, fill: DialFill())
        #expect(endOfMinute.currentBrightness > 0.99)
        // Two minutes a mark past an hour: minute 37 is halfway through mark 18.
        let ninety = DialFrame.running(layout: DialLayout(plannedMinutes: 90), elapsed: 37 * 60, leafMinute: nil, fill: DialFill())
        #expect(ninety.marks[18] == .current && abs(ninety.currentBrightness - 0.775) < 1e-9)
        // At the planned end every mark is lit; before the start the first mark is current.
        let ended = DialFrame.running(layout: fifty, elapsed: 50 * 60, leafMinute: 35, fill: DialFill())
        #expect(ended.marks == Array(repeating: .lit, count: 50) && ended.currentBrightness == 1)
        #expect(DialFrame.running(layout: fifty, elapsed: -5, leafMinute: nil, fill: DialFill()).marks[0] == .current)
        #expect(DialFrame.running(layout: fifty, elapsed: .nan, leafMinute: nil, fill: DialFill()).marks[0] == .current)
        #expect(DialFrame.running(layout: fifty, elapsed: .infinity, leafMinute: nil, fill: DialFill()).marks.allSatisfy { $0 == .lit })
    }

    @Test("When the leaf opens the dot turns amber and the bloom turns gold")
    func opening() throws {
        let waiting = DialFrame.running(layout: fifty, elapsed: 36 * 60, leafMinute: 35, fill: DialFill(before: 0.5, session: 0.5))
        #expect(try #require(waiting.dot).reached == false)
        #expect(waiting.bloom == DialBloom(tint: 0.55))
        let opened = DialFrame.running(layout: fifty, elapsed: 36 * 60, leafMinute: 35, fill: DialFill(before: 0.5, session: 0.5, opened: 1))
        #expect(try #require(opened.dot).reached)
        #expect(abs(opened.bloom.tint - 0.25) < 1e-9 && abs(opened.bloom.gold - 0.6) < 1e-9 && opened.bloom.cool == 0)
    }

    @Test("Receipt: the marks as they counted, gold over the counted ones when the finish is gold, and no dot")
    func receipt() {
        let gold = DialFrame.receipt(marks: gapMarks, isGold: true, fill: DialFill(before: 0.4, session: 0.6, opened: 1))
        #expect(gold.marks == gapMarks && gold.dot == nil)
        #expect(gold.gold == gapMarks.map { $0 == .lit })
        #expect(gold.bloom == DialBloom(tint: 0.25, gold: 1))
        let early = DialFrame.receipt(marks: gapMarks, isGold: false, fill: DialFill(before: 0.4, session: 0.1))
        #expect(early.gold == Array(repeating: false, count: 50))
        #expect(early.bloom == DialBloom(tint: 0.55))
    }

    @Test("Holds fill the marks clockwise: over marks still to come, or over another frame")
    func hold() {
        let emergency = DialFrame.hold(progress: 0.5)
        #expect(emergency.marks.count == 60)
        #expect(emergency.marks[..<30].allSatisfy { $0 == .hold } && emergency.marks[30...].allSatisfy { $0 == .ahead })
        #expect(emergency.bloom == DialBloom(cool: 1) && emergency.dot == nil)
        #expect(DialFrame.hold(progress: 0).marks.allSatisfy { $0 == .ahead })
        #expect(DialFrame.hold(progress: 1).marks.allSatisfy { $0 == .hold })
        #expect(DialFrame.hold(progress: .nan).marks.allSatisfy { $0 == .ahead })
        #expect(DialFrame.hold(progress: 7).marks.allSatisfy { $0 == .hold })
        let start = DialFrame.preview(layout: fifty, leafMinute: 35)
        let locked = DialFrame.hold(progress: 0.5, base: start)
        #expect(locked.marks[..<25].allSatisfy { $0 == .hold } && locked.marks[25...].allSatisfy { $0 == .plan })
        #expect(locked.dot == start.dot && locked.bloom == start.bloom)
    }

    @Test("Needs Screen Time turns every mark off; a break draws its rest marks with the cool bloom")
    func offAndBreak() {
        let off = DialFrame.off(layout: fifty)
        #expect(off.marks == Array(repeating: .off, count: 50) && off.dot == nil && off.bloom == DialBloom.hidden)
        let layout = BreakDialLayout(breakSeconds: 300)
        let rest = DialFrame.breakTime(layout, left: 190)
        #expect(rest.marks == layout.marks(left: 190) && rest.marks.contains(.rest))
        #expect(rest.bloom == DialBloom(cool: 1) && rest.dot == nil)
    }

    @Test("Between them the builders draw every mark state in §4.2")
    func everyState() {
        let frames: [DialFrame] = [
            .preview(layout: fifty),
            .running(layout: fifty, elapsed: 18.4 * 60, leafMinute: 35, fill: DialFill()),
            .receipt(marks: gapMarks, isGold: true, fill: DialFill()),
            .hold(progress: 0.5),
            .off(layout: fifty),
            .breakTime(BreakDialLayout(breakSeconds: 300), left: 190),
        ]
        let seen = Set(frames.flatMap(\.marks))
        #expect(seen == [.plan, .ahead, .lit, .current, .rest, .gap, .hold, .off])
    }

    @Test("Dimming halves the marks and the bloom, and undims")
    func dimming() {
        let frame = DialFrame.running(layout: fifty, elapsed: 600, leafMinute: 35, fill: DialFill())
        #expect(frame.markOpacity == 1)
        #expect(frame.dimmed(true).markOpacity == 0.5)
        #expect(frame.dimmed(true).dimmed(false) == frame)
    }

    @Test("The fill clamps, and splits a rung into the part saved before and this session's share")
    func fill() {
        let over = DialFill(before: 0.7, session: 0.6)
        #expect(over.before == 0.7 && abs(over.session - 0.3) < 1e-9)
        #expect(DialFill(before: -1, session: .nan, opened: 3) == DialFill(before: 0, session: 0, opened: 1))
        let rung = LeafProgress(
            speciesID: "campestre", category: .hoursSaved, threshold: 3, tier: .common, current: 2,
            availability: .available, state: .locked, estimatedDays: nil, floor: 1
        )
        let split = DialFill(rung: rung, sessionHours: 0.25)
        #expect(abs(split.before - 0.375) < 1e-9 && abs(split.session - 0.125) < 1e-9 && split.opened == 0)
        // More than the rung's progress so far: all of it is this session's.
        let all = DialFill(rung: rung, sessionHours: 5)
        #expect(all.before == 0 && abs(all.session - 0.5) < 1e-9)
        #expect(DialFill(rung: rung, sessionHours: .nan).session == 0)
        #expect(DialFill(before: 0.4, session: 0.2).leafFill == .twoTone(before: 0.4, session: 0.2, edge: true))
        #expect(DialFill(before: 0.4, session: 0.6, opened: 1).leafFill == .twoTone(before: 0.4, session: 0.6, edge: false))
    }

    @Test("The newest lit mark is the one the current mark has just left")
    func newestLit() {
        #expect(DialFrame.running(layout: fifty, elapsed: 18.4 * 60, leafMinute: nil, fill: DialFill()).newestLit == 17)
        #expect(DialFrame.running(layout: fifty, elapsed: 30, leafMinute: nil, fill: DialFill()).newestLit == nil)
        #expect(DialFrame.preview(layout: fifty).newestLit == nil)
    }
}

// MARK: - Geometry

@Suite("Dial geometry")
struct DialGeometryTests {
    private func distance(_ point: CGPoint, from centre: CGFloat) -> Double {
        Double(hypot(point.x - centre, point.y - centre))
    }

    @Test("Marks run clockwise from 12 o'clock on the 200-unit box: long from 80, short from 84, gaps from 86, out to 92")
    func marks() {
        let geometry = MinuteDialGeometry(diameter: 400)
        #expect(geometry.scale == 2)
        let top = geometry.segment(index: 0, count: 50, state: .lit)
        #expect(abs(top.outer.x - 200) < 1e-9 && abs(top.outer.y - 16) < 1e-9)
        #expect(abs(top.inner.x - 200) < 1e-9 && abs(top.inner.y - 40) < 1e-9)
        #expect(abs(distance(geometry.segment(index: 1, count: 50, state: .lit).inner, from: 200) - 168) < 1e-6)
        #expect(abs(distance(geometry.segment(index: 5, count: 50, state: .ahead).inner, from: 200) - 160) < 1e-6)
        #expect(abs(geometry.segment(index: 0, count: 50, state: .gap).inner.y - 28) < 1e-9)
        let quarter = geometry.segment(index: 25, count: 100, state: .lit)
        #expect(abs(quarter.outer.x - 384) < 1e-9 && abs(quarter.outer.y - 200) < 1e-9)
    }

    @Test("Strokes are 1.6, and 2.2 for the current mark, with round caps; the dot sits at 99 with radius 2.6")
    func strokesAndDot() {
        let geometry = MinuteDialGeometry(diameter: 300)
        #expect(abs(geometry.strokeStyle(for: .lit).lineWidth - 2.4) < 1e-9)
        #expect(abs(geometry.strokeStyle(for: .gap).lineWidth - 2.4) < 1e-9)
        #expect(abs(geometry.strokeStyle(for: .current).lineWidth - 3.3) < 1e-9)
        #expect(geometry.strokeStyle(for: .hold).lineCap == .round)
        #expect(abs(geometry.dotRadius - 3.9) < 1e-9)
        let dot = geometry.dotCentre(angle: .pi / 2)
        #expect(abs(dot.x - 298.5) < 1e-9 && abs(dot.y - 150) < 1e-9)
        // 99 + 2.6 units reaches past the 100-unit edge, so the dot is drawn outside the canvas and never clipped.
        #expect(dot.x + geometry.dotRadius > 300)
    }

    @Test("The dial is about 75% of the screen width, never below 220pt, with its bloom 1.61 times as wide")
    func metrics() {
        #expect(MinuteDialMetrics.preferredDiameter(forWidth: 393) == 295)
        #expect(MinuteDialMetrics.minimumDiameter == 220)
        #expect(MinuteDialMetrics.bloomScale == 1.61)
    }
}

// MARK: - Centre

@Suite("Dial centre")
struct DialCentreTests {
    @Test("Time text splits into digits and smaller units; words stay whole")
    func numeralParts() {
        #expect(DialCentre.numeralParts("32m") == [.value("32"), .unit("m")])
        #expect(DialCentre.numeralParts("1h 30m") == [.value("1"), .unit("h"), .value("30"), .unit("m")])
        #expect(DialCentre.numeralParts("0:59") == [.value("0:59")])
        #expect(DialCentre.numeralParts("10s") == [.value("10"), .unit("s")])
        #expect(DialCentre.numeralParts("Breathe in") == [.value("Breathe in")])
    }

    @Test("At the mockup's 236pt the leaf, numeral and caption sit where the mockup put them")
    func restingLayout() {
        let layout = DialCentreLayout(diameter: 236, numeralBase: 48, captionBase: 12, hasLeaf: true, grow: 0)
        #expect(abs(layout.leafY - -44) < 1)
        #expect(abs(layout.numeralY - 4) < 0.01)
        #expect(abs(layout.captionY - 40) < 2)
        #expect(abs(layout.leafScale - 0.41) < 0.001 && layout.numeralScale == 1)
        #expect(abs(layout.glowStrength - 0.55) < 1e-9)
        let bare = DialCentreLayout(diameter: 236, numeralBase: 48, captionBase: 12, hasLeaf: false, grow: 1)
        #expect(abs(bare.numeralY - -8) < 0.01 && abs(bare.captionY - 28) < 1 && bare.numeralScale == 1)
    }

    @Test("Grown on the receipt: the leaf fills the centre and the numeral shrinks to 72% beneath it")
    func grownLayout() {
        let layout = DialCentreLayout(diameter: 236, numeralBase: 48, captionBase: 12, hasLeaf: true, grow: 1)
        #expect(abs(layout.leafY - -34) < 0.01 && layout.leafScale == 1)
        #expect(abs(layout.numeralScale - 0.72) < 1e-9)
        #expect(abs(layout.numeralY - 33) < 1)
        #expect(abs(layout.captionY - 57) < 2.5)
        #expect(abs(layout.glowStrength - 1) < 1e-9)
    }

    @Test("Everything scales with the dial")
    func scales() {
        let small = DialCentreLayout(diameter: 236, numeralBase: 48, captionBase: 12, hasLeaf: true, grow: 0)
        let large = DialCentreLayout(diameter: 300, numeralBase: 48, captionBase: 12, hasLeaf: true, grow: 0)
        let ratio = 300.0 / 236
        #expect(abs(Double(large.numeralSize) - 48 * ratio) < 1e-9)
        #expect(abs(Double(large.leafY / small.leafY) - ratio) < 1e-9)
        #expect(abs(Double(large.captionY / small.captionY) - ratio) < 1e-9)
    }

    @Test("A larger numeral pushes the leaf up and the caption down, so nothing overlaps", arguments: [48.0, 60, 72])
    func noOverlap(base: Double) {
        for grow in [0.0, 0.5, 1.0] {
            let layout = DialCentreLayout(diameter: 300, numeralBase: CGFloat(base), captionBase: 15, hasLeaf: true, grow: grow)
            let half = layout.numeralSize * layout.numeralScale / 2
            #expect(layout.leafY + layout.leafSide * layout.leafScale / 2 <= layout.numeralY - half + 0.5, "\(base) at \(grow)")
            #expect(layout.captionY - layout.captionSize * 0.6 >= layout.numeralY + half - 0.5, "\(base) at \(grow)")
        }
    }
}

// MARK: - Drawing

/// What reaches the pixels: the colours and their order, Increase Contrast, the shorter gaps, the season tint, Reduce
/// Motion, dimming, the dot and the no-amber rule. The colour checks compare pixels with each other rather than
/// exact values, so the renderer's blending can't break them.
@Suite("Minute dial drawing")
@MainActor
struct MinuteDialDrawingTests {
    private func pixels(of view: some View, side: Int = 400) throws -> [UInt8] {
        let renderer = ImageRenderer(content: view.frame(width: CGFloat(side), height: CGFloat(side)))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        try #require(drawn)
        return pixels
    }

    private func rgb(_ pixels: [UInt8], x: Int, y: Int, side: Int = 400) -> (r: Int, g: Int, b: Int) {
        let index = (y * side + x) * 4
        return (Int(pixels[index]), Int(pixels[index + 1]), Int(pixels[index + 2]))
    }

    private func uniform(_ state: MarkState, brightness: Double = 1) -> DialFrame {
        DialFrame(marks: Array(repeating: state, count: 50), currentBrightness: brightness)
    }

    /// The dial at 400pt (2 points a unit) on black, with no centre.
    private func draw(_ frame: DialFrame, theme: Theme = .maple) -> some View {
        MinuteDial(frame: frame, diameter: 400, theme: theme).background(Color.black)
    }

    /// The top mark, halfway along a long mark (radius 86 units, y = 200 − 172).
    private func top(_ frame: DialFrame, theme: Theme = .maple) throws -> (r: Int, g: Int, b: Int) {
        rgb(try pixels(of: draw(frame, theme: theme)), x: 200, y: 28)
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

    /// How many pixels are close to the dial's gold (about 43°) with real saturation.
    private func goldPixels(_ pixels: [UInt8]) -> Int {
        stride(from: 0, to: pixels.count, by: 4).filter { index in
            let alpha = Double(pixels[index + 3])
            guard alpha > 40 else { return false }
            let r = Double(pixels[index]) / alpha, g = Double(pixels[index + 1]) / alpha, b = Double(pixels[index + 2]) / alpha
            let maxC = max(r, g, b), minC = min(r, g, b)
            guard maxC == r, maxC - minC > 0.25 else { return false }
            return (38...50).contains(60 * ((g - b) / (maxC - minC)))
        }.count
    }

    @Test("Brighter states draw brighter: hold, lit, plan, ahead, then off")
    func brightnessOrder() throws {
        let hold = try top(uniform(.hold)).r, lit = try top(uniform(.lit)).r, plan = try top(uniform(.plan)).r
        let ahead = try top(uniform(.ahead)).r, off = try top(uniform(.off)).r
        #expect(hold >= lit && lit > plan + 40 && plan > ahead + 25 && ahead > off && off > 5, "\([hold, lit, plan, ahead, off])")
        // Between the marks the dial is black.
        #expect(rgb(try pixels(of: draw(uniform(.lit))), x: 200, y: 200).r < 6)
    }

    @Test("Increase Contrast raises every mark the table raises, and leaves hold as it was")
    func contrast() throws {
        for state in [MarkState.plan, .ahead, .lit, .off] {
            #expect(try top(uniform(state), theme: .mapleIncreasedContrast).r > top(uniform(state)).r + 10, "\(state)")
        }
        let hold = try top(uniform(.hold)).r, raisedHold = try top(uniform(.hold), theme: .mapleIncreasedContrast).r
        #expect(abs(raisedHold - hold) <= 3)
        // A gap mark is short, so it is sampled nearer the rim.
        let gap = rgb(try pixels(of: draw(uniform(.gap))), x: 200, y: 22).r
        let raisedGap = rgb(try pixels(of: draw(uniform(.gap), theme: .mapleIncreasedContrast)), x: 200, y: 22).r
        #expect(raisedGap > gap + 10 && gap > 3)
    }

    @Test("Gap marks are shorter: nothing is drawn where a long mark's inner end would be")
    func gapsAreShorter() throws {
        #expect(rgb(try pixels(of: draw(uniform(.gap))), x: 200, y: 36).r < 12)
        #expect(rgb(try pixels(of: draw(uniform(.lit))), x: 200, y: 36).r > 100)
    }

    @Test("Rest marks are the cool blue-grey; the current mark is the season tint and brightens through its minute")
    func tints() throws {
        let rest = try top(uniform(.rest))
        #expect(rest.b > rest.r + 10)
        let dim = try top(uniform(.current, brightness: 0.55)), bright = try top(uniform(.current, brightness: 1))
        #expect(bright.r > dim.r + 40, "it brightens")
        #expect(bright.r > bright.g + 30, "autumn's #E3A49E")
        let winter = rgb(try pixels(of: draw(uniform(.current)).environment(\.season, .winter)), x: 200, y: 28)
        #expect(winter.b > winter.r, "winter's #C9DDEE")
    }

    @Test("Under Reduce Motion the current mark is steady at its full tint")
    func reduceMotion() throws {
        let still = rgb(
            try pixels(of: draw(uniform(.current, brightness: 0.55)).environment(\._accessibilityReduceMotion, true)),
            x: 200, y: 28
        )
        let bright = try top(uniform(.current, brightness: 1))
        #expect(abs(still.r - bright.r) <= 3)
    }

    @Test("Dimming halves the marks")
    func dimming() throws {
        let lit = try top(uniform(.lit)).r, dimmed = try top(uniform(.lit).dimmed(true)).r
        #expect(dimmed < lit - 40 && dimmed > 40)
    }

    @Test("The leaf dot is season tint, and amber once the leaf has opened")
    func dot() throws {
        let point = MinuteDialGeometry(diameter: 400).dotCentre(angle: fifty.angle(atMinute: 35))
        let x = Int(point.x), y = Int(point.y)
        let waiting = rgb(try pixels(of: draw(.preview(layout: fifty, leafMinute: 35))), x: x, y: y)
        let opened = rgb(try pixels(of: draw(.running(
            layout: fifty, elapsed: 40 * 60, leafMinute: 35, fill: DialFill(before: 0.5, session: 0.5, opened: 1)
        ))), x: x, y: y)
        #expect(waiting.r > 150 && waiting.b > 120, "season tint #E3A49E: \(waiting)")
        #expect(opened.r > 180 && opened.b < 120, "amber #E8A35C: \(opened)")
    }

    @Test("No amber anywhere on the dial except the dot of a leaf that has opened (spec §1.3, F1-18)")
    func noAmber() throws {
        let frames: [DialFrame] = [
            .preview(layout: fifty, leafMinute: 35, fill: DialFill(before: 0.4)),
            .running(layout: fifty, elapsed: 18 * 60, leafMinute: 35, fill: DialFill(before: 0.4, session: 0.2)),
            .running(layout: fifty, elapsed: 18 * 60, leafMinute: 35, fill: DialFill(before: 0.4, session: 0.2)).dimmed(true),
            .receipt(marks: gapMarks, isGold: true, fill: DialFill(before: 0.4, session: 0.6, opened: 1)),
            .hold(progress: 0.5),
            .off(layout: fifty),
            .breakTime(BreakDialLayout(breakSeconds: 300), left: 190),
        ]
        for frame in frames {
            #expect(!containsAmber(try pixels(of: draw(frame))))
        }
        let opened = DialFrame.running(layout: fifty, elapsed: 40 * 60, leafMinute: 35, fill: DialFill(before: 0.5, session: 0.5, opened: 1))
        #expect(containsAmber(try pixels(of: draw(opened))))
    }

    @Test("The centre leaf fills with gold from the stalk, turns fully gold when it opens, and never reads as amber")
    func centreLeaf() throws {
        let field = try #require(LeafCatalog.shared.species(id: "campestre"))
        // Spring's green tint keeps the skeleton's lines far from gold, so only the fill can count.
        func leaf(_ fill: DialFill) throws -> [UInt8] {
            try pixels(of: DialLeaf(species: field, fill: fill).environment(\.season, .spring).background(Color.black), side: 160)
        }
        let empty = try leaf(DialFill()), filling = try leaf(DialFill(before: 0.4, session: 0.3))
        let opened = try leaf(DialFill(before: 0.4, session: 0.6, opened: 1))
        #expect(goldPixels(empty) == 0)
        #expect(goldPixels(filling) > 100)
        #expect(goldPixels(opened) > goldPixels(filling))
        for image in [empty, filling, opened] {
            #expect(!containsAmber(image))
        }
    }
}
