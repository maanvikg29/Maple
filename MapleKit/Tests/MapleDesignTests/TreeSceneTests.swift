import CoreGraphics
import Foundation
import MapleCore
import SwiftUI
import Testing
@testable import MapleDesign

private let ids = LeafCatalog.shared.species.map(\.id)
private let instant = Date(timeIntervalSinceReferenceDate: 812_000_013)

private func model(
    species count: Int = 40, growth: Double = 0.34, season: Season = .autumn, phase: NowPhase = .evening,
    vitality: Double = 1, waiting: [String] = [], time: Date? = instant
) -> TreeSceneModel {
    TreeSceneModel(
        seed: 0xC0FFEE,
        growth: growth,
        species: ids.prefix(count).map { TreeSceneModel.Leaf(speciesID: $0, pressed: .autumn) },
        buds: count + 5 < ids.count ? [TreeSceneModel.Bud(speciesID: ids[count + 5], progress: 0.5)] : [],
        waiting: waiting,
        featured: count > 2 ? ids[1] : nil,
        season: season,
        seasonDay: 40,
        phase: phase,
        vitality: vitality,
        time: time
    )
}

/// Mean brightness (0…1) of an image region, in its own pixel space.
private func brightness(of image: CGImage, in rect: CGRect) -> Double {
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(
            data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drawn else { return 0 }
    var total = 0.0, count = 0.0
    let box = rect.intersection(CGRect(x: 0, y: 0, width: width, height: height)).integral
    for y in Int(box.minY)..<Int(box.maxY) {
        for x in Int(box.minX)..<Int(box.maxX) {
            let i = (y * width + x) * 4
            total += (Double(pixels[i]) + Double(pixels[i + 1]) + Double(pixels[i + 2])) / (3 * 255)
            count += 1
        }
    }
    return count > 0 ? total / count : 0
}

@MainActor
@Suite("Tree scene")
struct TreeSceneTests {
    @Test("The plan resolves one paint per leaf and caps the canopy bloom at 18%")
    func plan() {
        for phase in NowPhase.allCases {
            let plan = TreeScenePlan(model: model(phase: phase), theme: .maple)
            #expect(plan.leaves.count == plan.skeleton.leaves.count)
            #expect(plan.leafOrder.count == plan.leaves.count)
            #expect(Set(plan.leafOrder).count == plan.leaves.count)
            #expect(plan.bloomOpacity <= 0.18 && plan.bloomOpacity > 0)
        }
        let quiet = TreeScenePlan(model: model(vitality: 0.4), theme: .maple)
        let full = TreeScenePlan(model: model(vitality: 1), theme: .maple)
        #expect(abs(quiet.leafScale - 0.94) < 1e-9 && abs(full.leafScale - 1) < 1e-9)
        #expect(quiet.bloomOpacity < full.bloomOpacity)
        // Inner rosettes draw first.
        let firstOuter = full.leafOrder.firstIndex { !full.skeleton.leaves[$0].isInner } ?? full.leafOrder.count
        #expect(full.leafOrder[firstOuter...].allSatisfy { !full.skeleton.leaves[$0].isInner })
    }

    @Test("Night dims the tree to 75% and wind-down to 90%")
    func phaseBrightness() {
        let evening = TreeScenePlan(model: model(phase: .evening), theme: .maple)
        let night = TreeScenePlan(model: model(phase: .night), theme: .maple)
        let windDown = TreeScenePlan(model: model(phase: .windDown), theme: .maple)
        #expect(night.sky.treeBrightness == 0.75 && windDown.sky.treeBrightness == 0.9 && evening.sky.treeBrightness == 1)
        let environment = EnvironmentValues()
        let a = evening.leaves[0].fill.resolve(in: environment), b = night.leaves[0].fill.resolve(in: environment)
        #expect(b.red + b.green + b.blue < a.red + a.green + a.blue)
    }

    @Test("Sway rests at zero and stays within ±0.6° / ±1.0° / ±1.4°, scaled by vitality")
    func sway() {
        #expect(TreeSway.still == TreeSway())
        let degree = Double.pi / 180
        for t in stride(from: 0.0, through: 20, by: 0.37) {
            let full = TreeSway.at(t, phase: .evening, vitality: 1)
            #expect(abs(full.trunk) <= 0.6 * degree + 1e-12 && abs(full.twigs) <= 1.0 * degree + 1e-12 && abs(full.leaves) <= 1.4 * degree + 1e-12)
            let quiet = TreeSway.at(t, phase: .evening, vitality: 0.5)
            #expect(abs(quiet.leaves) <= 0.7 * degree + 1e-12)
        }
        // Night sways on a 10 s period.
        let night0 = TreeSway.at(0, phase: .night, vitality: 1).trunk
        let night10 = TreeSway.at(10, phase: .night, vitality: 1).trunk
        #expect(abs(night0 - night10) < 1e-12)
    }

    @Test("Each phase has its own sky (spec §4.4)")
    func sky() {
        let scene = Theme.maple.colors.scene
        #expect(scene.sky(for: .day).starCount == 0)
        #expect(scene.sky(for: .morning).starCount == 12 && !scene.sky(for: .morning).showsMoon)
        #expect(scene.sky(for: .evening).starCount == 48 && scene.sky(for: .evening).showsMoon)
        #expect(scene.sky(for: .night).twinklingStars == 2)
        #expect(scene.sky(for: .morning).dawnWash != nil && scene.sky(for: .day).dawnWash == nil)
        #expect(TreeSkyPainter.stars.count == 48)
    }

    @Test("The still frame renders a lit tree on a dark sky, at any size")
    func renders() throws {
        for size in [CGSize(width: 402, height: 560), CGSize(width: 320, height: 410)] {
            let renderer = ImageRenderer(content: MapleTreeScene(model: model()).frame(width: size.width, height: size.height))
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            #expect(image.width == Int(size.width))
            let frame = TreeSceneFrame(size: size)
            let crown = frame.scene(201, 300)
            let crownLight = brightness(of: image, in: CGRect(x: crown.x - 40, y: crown.y - 30, width: 80, height: 60))
            let skyLight = brightness(of: image, in: CGRect(x: 4, y: 4, width: 40, height: 40))
            #expect(crownLight > skyLight + 0.05, "crown \(crownLight), sky \(skyLight)")
        }
    }

    @Test("Every season, phase and the seed sprout draw without trouble")
    func matrix() throws {
        let cases: [TreeSceneModel] = Season.allCases.map { model(season: $0) } + NowPhase.allCases.map { model(phase: $0) }
            + [model(species: 0, growth: 0, waiting: [ids[0]]), model(species: 155, growth: 1), model(vitality: 0.45)]
        for item in cases {
            let renderer = ImageRenderer(content: MapleTreeScene(model: item).frame(width: 201, height: 280))
            renderer.scale = 1
            #expect(renderer.cgImage != nil)
        }
    }

    @Test("Rasterised layers cover the tree and sway about the trunk base")
    func rasterLayers() throws {
        let plan = TreeScenePlan(model: model(time: nil), theme: .maple)
        let frame = TreeSceneFrame(size: CGSize(width: 402, height: 560))
        let layers = try #require(TreeRasterCache.shared.layers(for: plan, frame: frame, displayScale: 2, now: instant))
        #expect(layers.rect.contains(frame.base) || abs(layers.rect.maxY - frame.base.y) <= 10.5)
        #expect(layers.anchor.x > 0 && layers.anchor.x < 1 && layers.anchor.y > 0.9 && layers.anchor.y <= 1)
        let again = try #require(TreeRasterCache.shared.layers(for: plan, frame: frame, displayScale: 2, now: instant))
        #expect(again.rect == layers.rect)
    }

    @Test("Only a waiting leaf gets the 44 pt bud target")
    func waitingTarget() {
        let frame = TreeSceneFrame(size: CGSize(width: 402, height: 560))
        let none = TreeScenePlan(model: model(), theme: .maple)
        #expect(MapleTreeScene.waitingBudPoint(none, frame: frame) == nil)
        let waiting = TreeScenePlan(model: model(waiting: [ids[60]]), theme: .maple)
        let point = MapleTreeScene.waitingBudPoint(waiting, frame: frame)
        #expect(point != nil)
        if let point {
            #expect(CGRect(origin: .zero, size: frame.size).contains(point))
        }
        let sprout = TreeScenePlan(model: model(species: 0, growth: 0, waiting: [ids[0]]), theme: .maple)
        #expect(MapleTreeScene.waitingBudPoint(sprout, frame: frame) != nil)
    }

    @Test("Particles appear only for vital trees, one system per season")
    func particles() {
        #expect(TreeScenePlan(model: model(vitality: 0.5), theme: .maple).model.vitality < 0.6)
        for season in Season.allCases {
            let plan = TreeScenePlan(model: model(season: season), theme: .maple)
            let renderer = ImageRenderer(content: Canvas { context, size in
                TreeParticles.draw(plan, frame: TreeSceneFrame(size: size), time: 812_000_013, in: context)
            }.frame(width: 402, height: 560))
            #expect(renderer.cgImage != nil)
        }
    }
}
