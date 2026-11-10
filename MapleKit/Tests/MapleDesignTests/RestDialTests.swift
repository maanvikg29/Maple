import CoreGraphics
import Foundation
import MapleCore
import SwiftUI
import Testing
@testable import MapleDesign

/// Rest › Sleep's dial and copy (docs/design/spec.md §8.1): where times sit on the 24-hour ring, the arcs between
/// them, the words around the dial, and the few visual rules a pixel can prove.
@Suite("Rest dial")
@MainActor
struct RestDialTests {
    private let h24 = Locale(identifier: "en_GB")
    private let h12 = Locale(identifier: "en_US")
    private let late = SleepSchedule(bedtime: ClockTime(hour: 0, minute: 30), wake: ClockTime(hour: 8, minute: 30), windDownMinutes: 60)

    // MARK: Geometry

    @Test("Midnight sits at the top and the day runs clockwise")
    func fractions() {
        #expect(SleepDialGeometry.fraction(of: ClockTime(hour: 0)) == 0)
        #expect(SleepDialGeometry.fraction(of: ClockTime(hour: 6)) == 0.25)
        #expect(SleepDialGeometry.fraction(of: ClockTime(hour: 12)) == 0.5)
        #expect(SleepDialGeometry.fraction(of: ClockTime(hour: 23, minute: 59)) < 1)

        let dial = SleepDialGeometry(side: SleepDial.diameter)
        #expect(dial.ringRadius == 128)
        let top = dial.point(at: 0, radius: dial.ringRadius)
        #expect(abs(top.x - 140) < 1e-9 && abs(top.y - 12) < 1e-9)
        let six = dial.point(at: 0.25, radius: dial.ringRadius)
        #expect(abs(six.x - 268) < 1e-9 && abs(six.y - 140) < 1e-9)
        let eighteen = dial.point(at: 0.75, radius: dial.ringRadius)
        #expect(abs(eighteen.x - 12) < 1e-9 && abs(eighteen.y - 140) < 1e-9)
    }

    @Test("Arcs run clockwise and wrap midnight; equal times give no arc")
    func arcs() {
        let night = SleepDialGeometry.arc(from: ClockTime(hour: 23), to: ClockTime(hour: 7))
        #expect(abs(night.start - 23.0 / 24) < 1e-12)
        #expect(abs(night.length - 8.0 / 24) < 1e-12)

        let windDown = SleepDialGeometry.arc(from: SleepSchedule.standard.windDownStart, to: SleepSchedule.standard.bedtime)
        #expect(abs(windDown.length - 45.0 / 1440) < 1e-12)

        let afterMidnight = SleepDialGeometry.arc(from: late.windDownStart, to: late.bedtime)
        #expect(abs(afterMidnight.start - 23.5 / 24) < 1e-12)
        #expect(abs(afterMidnight.length - 1.0 / 24) < 1e-12)

        #expect(SleepDialGeometry.arc(from: ClockTime(hour: 7), to: ClockTime(hour: 7)).length == 0)
    }

    @Test("The quarter labels sit inside the ticks, and the moon's cut-out inside the dial")
    func clearances() {
        let dial = SleepDialGeometry(side: SleepDial.diameter)
        #expect(dial.labelInset > dial.ringInset + 9 + 7)
        #expect(dial.ringInset >= (SleepDialGeometry.moonDiameter + 6) / 2)
    }

    // MARK: Copy

    @Test("Time in bed reads like Home's durations")
    func inBed() {
        #expect(RestCopy.inBed(.standard) == "8h in bed")
        let short = SleepSchedule(bedtime: ClockTime(hour: 23, minute: 30), wake: ClockTime(hour: 7), windDownMinutes: 30)
        #expect(RestCopy.inBed(short) == "7h 30m in bed")
        #expect(RestCopy.windDownOption(minutes: 30) == "30m")
        #expect(RestCopy.windDownOption(minutes: 60) == "1h")
    }

    @Test("Dial labels follow the locale's clock")
    func dialLabels() {
        #expect([0, 6, 12, 18].map { RestCopy.dialLabel(hour: $0, locale: h24) } == ["00", "06", "12", "18"])
        #expect([0, 6, 12, 18].map { RestCopy.dialLabel(hour: $0, locale: h12) } == ["12 AM", "6 AM", "12 PM", "6 PM"])
    }

    @Test("VoiceOver hears the whole schedule as one sentence set, with full units")
    func spoken() {
        let text = RestCopy.dialDescription(.standard, now: ClockTime(hour: 21, minute: 40), locale: h24)
        #expect(text == "Wind-down from 22:15. Bed at 23:00, wake-up at 07:00. 8 hours in bed. Now 21:40.")
        let withoutNow = RestCopy.dialDescription(late, now: nil, locale: h12)
        #expect(withoutNow == "Wind-down from 11:30 PM. Bed at 12:30 AM, wake-up at 8:30 AM. 8 hours in bed.")
        #expect(RestCopy.spokenSchedule(.standard, locale: h24) == "Bed at 23:00, wake-up at 07:00")
        #expect(RestCopy.editorSummary(late, locale: h24) == "Wind-down from 23:30 · 8h in bed")
    }

    @Test("The bedside line counts down to bed, then names the wake-up once the night starts")
    func bedsideLine() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        func at(_ hour: Int, _ minute: Int) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: hour, minute: minute)))
        }
        let windDown = RestCopy.bedsideLine(at: try at(22, 22), schedule: .standard, calendar: calendar, locale: h24)
        #expect(windDown.text == "38m until bed")
        #expect(windDown.spoken == "38 minutes until bed.")
        let evening = RestCopy.bedsideLine(at: try at(20, 55), schedule: .standard, calendar: calendar, locale: h24)
        #expect(evening.text == "2h 5m until bed")
        let night = RestCopy.bedsideLine(at: try at(1, 30), schedule: .standard, calendar: calendar, locale: h24)
        #expect(night.text == "Wake-up at 07:00")
        // After midnight, before a 00:30 bedtime, it still counts down.
        let beforeLateBed = RestCopy.bedsideLine(at: try at(0, 10), schedule: .everyNight(late), calendar: calendar, locale: h24)
        #expect(beforeLateBed.text == "20m until bed")
        #expect(RestCopy.phoneDown(at: ClockTime(hour: 23, minute: 4), locale: h12) == "Phone down at 11:04 PM")
    }

    // MARK: Pixels

    @Test("The dial draws the season tint, never amber, in every season (spec §1.3)")
    func noAmber() throws {
        for season in Season.allCases {
            let dial = SleepDial(schedule: .standard, now: ClockTime(hour: 22, minute: 30))
                .environment(\.season, season)
                .background(Theme.maple.colors.background)
            let rendered = try pixels(of: dial, size: CGSize(width: 280, height: 280))
            #expect(!containsAmber(rendered), "\(season)")
        }
    }

    @Test("The in-bed arc is drawn in the tint, the rest of the ring is a quiet track, and the moon marks now")
    func arcAndMoon() throws {
        let size = CGSize(width: 280, height: 280)
        let dial = SleepDialGeometry(side: 280)
        func view(now: ClockTime?) -> some View {
            SleepDial(schedule: .standard, now: now)
                .environment(\.season, .winter)
                .background(Color.black)
        }
        let rendered = try pixels(of: view(now: ClockTime(hour: 15)), size: size)
        func pixel(at fraction: Double) -> (r: Int, g: Int, b: Int) {
            let point = dial.point(at: fraction, radius: dial.ringRadius)
            let index = (Int(point.y) * 280 + Int(point.x)) * 4
            return (Int(rendered[index]), Int(rendered[index + 1]), Int(rendered[index + 2]))
        }
        // 03:00 is inside 23:00 → 07:00: bright, winter's pale blue (#C9DDEE).
        let inBed = pixel(at: 3.0 / 24)
        #expect(inBed.r > 120 && inBed.b > inBed.r)
        // 10:00 is outside every arc: only the white 8% track.
        let track = pixel(at: 10.0 / 24)
        #expect(max(track.r, track.g, track.b) < 40)
        // 15:00 carries the moon. Its lit limb is toward the lower left of the marker's centre.
        let noMoon = try pixels(of: view(now: nil), size: size)
        let centre = dial.point(at: 15.0 / 24, radius: dial.ringRadius)
        let index = (Int(centre.y + 2) * 280 + Int(centre.x - 3)) * 4
        func brightness(_ pixels: [UInt8]) -> Int { Int(pixels[index]) + Int(pixels[index + 1]) + Int(pixels[index + 2]) }
        #expect(brightness(rendered) > 450)
        #expect(brightness(noMoon) < 120)
    }

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
}
