import CoreGraphics
import Foundation
import MapleCore
import SwiftUI
import Testing
@testable import MapleDesign

/// The unlock ritual's timeline (docs/design/spec.md §5.8, D8, §6.5, §6.6): which ritual a leaf gets, the full
/// ritual's table row by row, the short ritual, the Reduce Motion crossfade, "Open all", and the glow caps.
@Suite("Reveal timeline")
struct RevealTimelineTests {
    private static let samples = stride(from: -0.5, through: 4.0, by: 0.01).map { $0 }

    // MARK: Which ritual

    @Test("The first 3 reveals ever get the full ritual whatever their tier")
    func firstThreeAreFull() {
        for before in 0..<3 {
            #expect(RevealRitual(tier: .common, revealsBefore: before, reduceMotion: false) == .full)
            #expect(RevealRitual(tier: .firstSteps, revealsBefore: before, reduceMotion: false) == .full)
        }
        #expect(RevealRitual(tier: .common, revealsBefore: 3, reduceMotion: false) == .short)
        #expect(RevealRitual(tier: .firstSteps, revealsBefore: 40, reduceMotion: false) == .short)
    }

    @Test("Uncommon, rare and legendary leaves always get the full ritual")
    func rarerTiersAreFull() {
        for tier in [RewardTier.uncommon, .rare, .legendary] {
            #expect(RevealRitual(tier: tier, revealsBefore: 120, reduceMotion: false) == .full)
        }
    }

    @Test("Reduce Motion is always the crossfade")
    func reduceMotionCrossfades() {
        for tier in RewardTier.allCases {
            #expect(RevealRitual(tier: tier, revealsBefore: 0, reduceMotion: true) == .crossfade)
            #expect(RevealRitual(tier: tier, revealsBefore: 50, reduceMotion: true) == .crossfade)
        }
    }

    // MARK: Ends

    @Test("Before the tap every ritual shows the closed bud; after it settles, the opened leaf")
    func ends() {
        for ritual in RevealRitual.allCases {
            #expect(RevealFrame.at(0, ritual: ritual) == .closed)
            #expect(RevealFrame.at(-1, ritual: ritual) == .closed)
            let rest = RevealFrame.at(ritual.settledTime, ritual: ritual)
            #expect(rest.budOpacity == 0)
            #expect(rest.leafScale == 1)
            #expect(rest.leafTurn == 0)
            #expect(rest.unfurl == 1)
            #expect(rest.veins == 1)
            #expect(rest.fill == 1)
            #expect(rest.leafOpacity == 1)
            #expect(rest.drop == RevealFrame.restingDrop)
            #expect(rest.amberBloom == 0)
            #expect(abs(rest.leafBloom - RevealFrame.leafBloomCap) < 1e-9)
            #expect(rest.textOpacity == 1)
            #expect(rest.textRise == 0)
            #expect(rest.footerOpacity == 1)
            #expect(rest.promptOpacity == 0)
            #expect(RevealFrame.at(ritual.settledTime + 10, ritual: ritual) == rest)
        }
        #expect(RevealFrame.at(.infinity, ritual: .full) == .opened)
        #expect(RevealFrame.at(.nan, ritual: .full) == .closed)
    }

    @Test("Every ritual settles where the others do, so a leaf never jumps between them")
    func sameRestingPlace() {
        let full = RevealFrame.at(10, ritual: .full)
        for ritual in RevealRitual.allCases {
            let rest = RevealFrame.at(10, ritual: ritual)
            #expect(rest.leafScale == full.leafScale)
            #expect(rest.drop == full.drop)
            #expect(rest.leafTurn == full.leafTurn)
        }
    }

    // MARK: The full ritual's table

    @Test("0–0.6 s: the bud's scales turn ±35° apart and fade")
    func budOpens() {
        #expect(RevealFrame.at(0.6, ritual: .full).budOpacity == 0)
        #expect(RevealFrame.at(0.6, ritual: .full).budSpread == 35)
        let mid = RevealFrame.at(0.3, ritual: .full)
        #expect(mid.budSpread > 17.5, "easeOut is past halfway at half time")
        #expect(mid.budOpacity > 0 && mid.budOpacity < 0.5)
    }

    @Test("0.2–1.6 s: the leaf scales 0.2 → 1 and turns from −25° to its resting tilt as it unfurls")
    func leafUnfurls() {
        let start = RevealFrame.at(0.2, ritual: .full)
        #expect(start.leafScale == 0.2)
        #expect(start.leafTurn == -25)
        #expect(start.unfurl == 0)
        let end = RevealFrame.at(1.6, ritual: .full)
        #expect(end.leafScale == 1)
        #expect(end.leafTurn == 0)
        #expect(end.unfurl == 1)
    }

    @Test("0.4–1.6 s veins draw in; 1.0–1.8 s the fill fades in")
    func veinsAndFill() {
        #expect(RevealFrame.at(0.4, ritual: .full).veins == 0)
        #expect(RevealFrame.at(1.6, ritual: .full).veins == 1)
        #expect(RevealFrame.at(1.0, ritual: .full).fill == 0)
        #expect(abs(RevealFrame.at(1.4, ritual: .full).fill - 0.5) < 1e-6, "easeInOut is symmetric")
        #expect(RevealFrame.at(1.8, ritual: .full).fill == 1)
    }

    @Test("The amber bloom peaks at 30% at 1.6 s, then turns into the leaf's colour at 22% by 2.4 s")
    func bloomTurns() {
        let peak = RevealFrame.at(1.6, ritual: .full)
        #expect(abs(peak.amberBloom - 0.30) < 1e-9)
        #expect(peak.amberReach == 1)
        #expect(peak.leafBloom == 0)
        let turned = RevealFrame.at(2.4, ritual: .full)
        #expect(turned.amberBloom == 0)
        #expect(abs(turned.leafBloom - 0.22) < 1e-9)
    }

    @Test("1.8–2.8 s the leaf drifts 12 pt down; 2.0–2.6 s the text rises 8 pt in; the footer from 2.6 s")
    func settleTextFooter() {
        #expect(RevealFrame.at(1.8, ritual: .full).drop == 0)
        #expect(RevealFrame.at(2.8, ritual: .full).drop == 12)
        #expect(RevealFrame.at(2.0, ritual: .full).textOpacity == 0)
        #expect(RevealFrame.at(2.0, ritual: .full).textRise == 8)
        #expect(RevealFrame.at(2.6, ritual: .full).textOpacity == 1)
        #expect(RevealFrame.at(2.6, ritual: .full).textRise == 0)
        #expect(RevealFrame.at(2.6, ritual: .full).footerOpacity == 0)
        #expect(RevealFrame.at(3.2, ritual: .full).footerOpacity == 1)
        #expect(RevealRitual.full.footerStart == 2.6)
    }

    // MARK: Short and crossfade

    @Test("Short ritual: the bud fades in 0.3 s, the leaf scales 0.6 → 1, text at 0.6 s, done by 1.2 s")
    func shortRitual() {
        #expect(RevealFrame.at(0.3, ritual: .short).budOpacity == 0)
        #expect(RevealFrame.at(0.3, ritual: .short).budSpread == 0)
        #expect(RevealFrame.at(0.1, ritual: .short).leafScale == 0.6)
        #expect(RevealFrame.at(0.6, ritual: .short).textOpacity == 0)
        #expect(RevealFrame.at(0.7, ritual: .short).textOpacity > 0)
        #expect(RevealFrame.at(1.2, ritual: .short).textOpacity == 1)
        // No unfurl, no vein drawing, no drift: it grows in place.
        for t in Self.samples where t > 0 {
            let frame = RevealFrame.at(t, ritual: .short)
            #expect(frame.unfurl == 1)
            #expect(frame.veins == 1)
            #expect(frame.drop == RevealFrame.restingDrop)
        }
    }

    @Test("Reduce Motion: the bud crossfades to the complete leaf and its words over 0.6 s, with no amber")
    func crossfade() {
        for t in Self.samples where t > 0 {
            let frame = RevealFrame.at(t, ritual: .crossfade)
            #expect(frame.leafScale == 1)
            #expect(frame.unfurl == 1)
            #expect(frame.fill == 1)
            #expect(frame.budSpread == 0)
            #expect(frame.textRise == 0)
            #expect(frame.amberBloom == 0)
            #expect(abs(frame.budOpacity + frame.leafOpacity - 1) < 1e-9)
        }
        #expect(RevealFrame.at(0.6, ritual: .crossfade).leafOpacity == 1)
        #expect(RevealRitual.crossfade.settledTime == 0.6)
    }

    // MARK: Rules for every frame

    @Test("Glows never pass their caps and nothing overshoots")
    func capsAndNoOvershoot() {
        for ritual in RevealRitual.allCases {
            for t in Self.samples {
                let frame = RevealFrame.at(t, ritual: ritual)
                #expect(frame.amberBloom <= RevealFrame.amberBloomCap + 1e-9)
                #expect(frame.leafBloom <= RevealFrame.leafBloomCap + 1e-9)
                #expect(frame.leafScale <= 1 + 1e-9)
                #expect(frame.drop <= RevealFrame.restingDrop + 1e-9)
                #expect(frame.budSpread <= 35 + 1e-9)
                for value in [frame.budOpacity, frame.budGlow, frame.unfurl, frame.veins, frame.fill, frame.leafOpacity,
                              frame.shadow, frame.textOpacity, frame.footerOpacity, frame.promptOpacity] {
                    #expect(value >= -1e-9 && value <= 1 + 1e-9)
                }
            }
        }
    }

    @Test("The leaf only ever comes forward: unfurl, veins, fill and words never go back")
    func monotonic() {
        for ritual in RevealRitual.allCases {
            var previous = RevealFrame.at(Self.samples[0], ritual: ritual)
            for t in Self.samples.dropFirst() {
                let frame = RevealFrame.at(t, ritual: ritual)
                #expect(frame.unfurl >= previous.unfurl - 1e-9)
                #expect(frame.veins >= previous.veins - 1e-9)
                #expect(frame.fill >= previous.fill - 1e-9)
                #expect(frame.textOpacity >= previous.textOpacity - 1e-9)
                #expect(frame.footerOpacity >= previous.footerOpacity - 1e-9)
                #expect(frame.budOpacity <= previous.budOpacity + 1e-9)
                previous = frame
            }
        }
    }

    // MARK: Open all

    @Test("Open all: buds start 0.35 s apart with the short ritual, then the list follows")
    func openAllSchedule() {
        let schedule = RevealOpenAllSchedule(count: 3, reduceMotion: false)
        #expect(schedule.start(of: 0) == 0)
        #expect(abs(schedule.start(of: 2) - 0.7) < 1e-9)
        #expect(schedule.frame(of: 2, at: 0.7) == .closed)
        #expect(schedule.frame(of: 2, at: 0.7 + 2) == RevealFrame.at(2, ritual: .short))
        #expect(abs(schedule.listStart - (0.7 + 1.2 + 0.4)) < 1e-9)
        #expect(schedule.listOpacity(at: schedule.listStart) == 0)
        #expect(schedule.listOpacity(at: schedule.settledTime) == 1)
    }

    @Test("Under Reduce Motion, Open all goes straight to the list")
    func openAllReduceMotion() {
        let schedule = RevealOpenAllSchedule(count: 5, reduceMotion: true)
        #expect(schedule.listStart == 0)
        #expect(schedule.listOpacity(at: 0.6) == 1)
        for t in Self.samples {
            #expect(schedule.rowOpacity(at: t) == 0)
        }
    }

    @Test("The row leaves before the list has fully arrived, so the two never stack up")
    func rowLeavesFirst() {
        let schedule = RevealOpenAllSchedule(count: 4, reduceMotion: false)
        #expect(schedule.rowOpacity(at: schedule.listStart) == 1)
        #expect(schedule.rowOpacity(at: schedule.listStart + RevealOpenAllSchedule.listFade / 2) == 0)
        #expect(schedule.listOpacity(at: schedule.listStart + RevealOpenAllSchedule.listFade / 2) < 1)
    }

    @Test("\"Tap to open\" and the footer never show at the same time")
    func promptAndFooterTakeTurns() {
        for ritual in RevealRitual.allCases {
            for t in Self.samples {
                let frame = RevealFrame.at(t, ritual: ritual)
                #expect(frame.promptOpacity == 0 || frame.footerOpacity == 0, "\(ritual) at \(t)")
            }
        }
    }

    @Test("The row holds up to 6 buds a line, gaps tightening to fit")
    func openAllRows() {
        #expect(RevealOpenAllMetrics.rows(count: 0).isEmpty)
        #expect(RevealOpenAllMetrics.rows(count: 3) == [[0, 1, 2]])
        #expect(RevealOpenAllMetrics.rows(count: 8) == [[0, 1, 2, 3, 4, 5], [6, 7]])
        #expect(RevealOpenAllMetrics.gap(perRow: 1, width: 354) == 0)
        #expect(RevealOpenAllMetrics.gap(perRow: 3, width: 354) == 16)
        let six = RevealOpenAllMetrics.gap(perRow: 6, width: 354)
        #expect(abs(6 * 56 + 5 * six - 354) < 1e-9)
    }

    // MARK: Curves and layout

    @Test("The curves start at 0, end at 1 and only rise")
    func easing() {
        for curve in [RevealEasing.reveal, RevealEasing.easeOut, RevealEasing.easeInOut] {
            #expect(curve(0) == 0)
            #expect(curve(1) == 1)
            #expect(curve(-2) == 0)
            #expect(curve(3) == 1)
            var previous = 0.0
            for step in 1...100 {
                let value = curve(Double(step) / 100)
                #expect(value >= previous - 1e-9)
                previous = value
            }
        }
        #expect(abs(RevealEasing.easeInOut(0.5) - 0.5) < 1e-6)
        #expect(abs(RevealEasing.easeInOut(0.2) + RevealEasing.easeInOut(0.8) - 1) < 1e-6)
        // `timingCurve(0.2, 0, 0, 1)` is fast early and long at the end.
        #expect(RevealEasing.reveal(0.5) > 0.8)
    }

    @Test("The bud sits at 40% of the screen's height; the leaf's square is centred on it")
    func layout() {
        let layout = RevealLayout(size: CGSize(width: 402, height: 778), safeArea: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0))
        #expect(layout.screenHeight == 874)
        #expect(layout.budCentreScreenY == 350)
        let budCentre: CGFloat = 350 - 62
        let stageTop: CGFloat = budCentre - 100
        #expect(layout.budCentreY == budCentre)
        #expect(layout.stageTop == stageTop)
    }

    @Test("The unfurling mask starts below the stalk and ends past the tip")
    func unfurlMask() throws {
        let species = try #require(LeafCatalog.shared.species(id: "saccharum"))
        let geometry = LeafGeometry.of(species)
        let stalkEnd = max(geometry.bladeExtent.upperBound, geometry.petiole.start.y, geometry.petiole.end.y)
        let closed = RevealUnfurl.edges(geometry: geometry, unfurl: 0)
        #expect(closed.clear >= stalkEnd, "nothing shows before the sweep starts")
        let open = RevealUnfurl.edges(geometry: geometry, unfurl: 1)
        #expect(open.opaque <= geometry.bladeExtent.lowerBound, "the whole blade shows once it ends")
        let half = RevealUnfurl.edges(geometry: geometry, unfurl: 0.5)
        #expect(half.clear < closed.clear && half.clear > open.clear)
    }
}
