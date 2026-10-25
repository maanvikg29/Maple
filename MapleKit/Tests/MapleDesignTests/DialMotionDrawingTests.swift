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

    /// The top mark's pixel with the finish at `finish` (or none), on black at 400pt.
    private func top(_ frame: DialFrame, _ finish: FinishFrame?) throws -> (r: Int, g: Int, b: Int) {
        let view = MinuteDial(frame: frame, diameter: 400, theme: .maple).finishing(finish).background(Color.black)
        return rgb(try pixels(of: view, size: CGSize(width: 400, height: 400)), x: 200, y: 28, width: 400)
    }

    @Test("At its peak the sweep draws a counted mark gold; a session that counted nothing sweeps it white")
    func sweepColours() throws {
        let peak = FinishTimeline.sweepDuration * FinishTimeline.sweepPeak
        let gold = try top(lit, FinishTimeline.frame(at: peak, counted: lit.gold, leafOpened: false, reduceMotion: false))
        #expect(gold.r > gold.b + 80 && gold.g > gold.b + 50, "gold #F0C24A: \(gold)")
        let plain = DialFrame.receipt(marks: Array(repeating: .lit, count: 50), isGold: false, fill: DialFill())
        let white = try top(plain, FinishTimeline.frame(at: peak, counted: plain.gold, leafOpened: false, reduceMotion: false))
        #expect(white.r > 200 && abs(white.r - white.b) < 20, "white: \(white)")
        let none = try top(lit, nil)
        #expect(abs(none.r - none.b) < 20, "the lit mark alone: \(none)")
    }

    @Test("Once the sweep has passed, and under Reduce Motion, the marks are the receipt's own")
    func settlesToTheReceipt() throws {
        let none = try top(lit, nil)
        let settled = try top(lit, FinishTimeline.frame(at: 3, counted: lit.gold, leafOpened: false, reduceMotion: false))
        let still = try top(lit, FinishTimeline.frame(at: 0.2, counted: lit.gold, leafOpened: false, reduceMotion: true))
        for value in [settled, still] {
            #expect(abs(value.r - none.r) <= 3 && abs(value.b - none.b) <= 3, "\(value) against \(none)")
        }
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
