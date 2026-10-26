import CoreGraphics
import Foundation
import MapleCore
import SwiftUI
import Testing
@testable import MapleDesign

/// RGBA rows of a view rendered at `size` points, scale 1, on whatever background the view brings.
@MainActor
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

private func rgb(_ pixels: [UInt8], x: Int, y: Int, width: Int) -> (r: Int, g: Int, b: Int) {
    let index = (y * width + x) * 4
    return (Int(pixels[index]), Int(pixels[index + 1]), Int(pixels[index + 2]))
}

/// The finish drawn over the dial (F1 design §4.6).
@Suite("Finish drawing")
@MainActor
struct FinishDrawingTests {
    private let lit = DialFrame.receipt(marks: Array(repeating: .lit, count: 50), isGold: true, fill: DialFill())

    /// The marks that counted: the receipt's lit ones.
    private func counted(_ frame: DialFrame) -> [Bool] {
        frame.marks.map { $0 == .lit }
    }

    /// The top mark's pixel with the finish at `finish` (or none), on black at 400pt. A gap mark is shorter, so its
    /// pixel is nearer the edge (`y: 22`).
    private func top(_ frame: DialFrame, _ finish: FinishFrame?, y: Int = 28) throws -> (r: Int, g: Int, b: Int) {
        let view = MinuteDial(frame: frame, diameter: 400, theme: .maple).finishing(finish).background(Color.black)
        return rgb(try pixels(of: view, size: CGSize(width: 400, height: 400)), x: 200, y: y, width: 400)
    }

    private func reduceMotion(_ frame: DialFrame, at t: Double) -> FinishFrame {
        FinishTimeline.frame(at: t, counted: counted(frame), gold: true, leafOpened: false, reduceMotion: true)
    }

    @Test("At its peak the sweep draws a counted mark gold; a session that counted nothing sweeps it white")
    func sweepColours() throws {
        let peak = FinishTimeline.sweepDuration * FinishTimeline.sweepPeak
        let gold = try top(lit, FinishTimeline.frame(at: peak, counted: counted(lit), gold: true, leafOpened: false, reduceMotion: false))
        #expect(gold.r > gold.b + 80 && gold.g > gold.b + 50, "gold #F0C24A: \(gold)")
        let plain = DialFrame.receipt(marks: Array(repeating: .lit, count: 50), isGold: false, fill: DialFill())
        let white = try top(plain, FinishTimeline.frame(at: peak, counted: counted(plain), gold: false, leafOpened: false, reduceMotion: false))
        #expect(white.r > 200 && abs(white.r - white.b) < 20, "white: \(white)")
        let none = try top(lit, nil)
        #expect(abs(none.r - none.b) < 20, "the lit mark alone: \(none)")
    }

    @Test("Once the sweep has passed, and once Reduce Motion's gold has faded, the marks are the receipt's own")
    func settlesToTheReceipt() throws {
        let none = try top(lit, nil)
        let settled = try top(lit, FinishTimeline.frame(at: 3, counted: counted(lit), gold: true, leafOpened: false, reduceMotion: false))
        let still = try top(lit, reduceMotion(lit, at: FinishTimeline.settledTime(markCount: 50, reduceMotion: true)))
        for value in [settled, still] {
            #expect(abs(value.r - none.r) <= 3 && abs(value.b - none.b) <= 3, "\(value) against \(none)")
        }
        // A gap stays a gap: Reduce Motion's gold never draws over it, at full strength or settled.
        var marks = Array(repeating: MarkState.lit, count: 50)
        marks[0] = .gap
        let gapped = DialFrame.receipt(marks: marks, isGold: true, fill: DialFill())
        let gap = try top(gapped, nil, y: 22)
        for t in [0.9, 1.8] {
            let value = try top(gapped, reduceMotion(gapped, at: t), y: 22)
            #expect(abs(value.r - gap.r) <= 3 && abs(value.b - gap.b) <= 3, "\(value) against \(gap) at \(t) s")
        }
    }

    @Test("Under Reduce Motion the counted marks are gold at full strength (0.6–1.2 s), part-way while fading in")
    func reduceMotionGold() throws {
        let none = try top(lit, nil)
        let full = try top(lit, reduceMotion(lit, at: 0.9))
        #expect(full.r > full.b + 80 && full.g > full.b + 50, "gold #F0C24A: \(full)")
        let fading = try top(lit, reduceMotion(lit, at: 0.3))
        #expect(fading.b < none.b - 10 && fading.b > full.b + 10, "part-way: \(fading) between \(none) and \(full)")
    }
}

/// The hold button's look (F1 design §4.7): the light fill rising from the leading edge.
@Suite("Hold button drawing")
@MainActor
struct HoldButtonDrawingTests {
    private let size = CGSize(width: 300, height: 60)

    private func button(_ progress: Double) throws -> [UInt8] {
        let view = HoldButton(
            title: FocusCopy.holdToStart(minutes: 50), duration: FocusCopy.holdToStartSeconds,
            accessibilityName: FocusCopy.holdToStartName(minutes: 50, locale: Locale(identifier: "en_US")),
            progress: .constant(0), frozenProgress: progress
        ) {}
        .frame(width: 300)
        .background(Color.black)
        return try pixels(of: view, size: size)
    }

    @Test("A frozen hold fills the button from its leading edge, light over the dark glass")
    func frozenFill() throws {
        let half = try button(0.5)
        #expect(rgb(half, x: 30, y: 30, width: 300).r > 150)
        #expect(rgb(half, x: 270, y: 30, width: 300).r < 60)
        #expect(rgb(try button(0), x: 30, y: 30, width: 300).r < 60)
        #expect(rgb(try button(1), x: 270, y: 30, width: 300).r > 150)
    }
}
