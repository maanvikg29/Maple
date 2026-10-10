import Foundation
import Synchronization

/// The broad, slightly asymmetric dome an open-grown sugar maple fills (spec §4.2): about 1.3 : 1 wide to tall,
/// fuller in the shoulders than an ellipse, flatter underneath, lifted near the trunk so the fork stays visible,
/// with a few soft seeded lobes so the outline billows like a real crown. Tree space, mature size.
struct CrownEnvelope: Sendable {
    var centerX: Double
    /// Height of the crown's widest line.
    var equatorY: Double
    var halfWidthLeft: Double
    var halfWidthRight: Double
    /// Equator to top.
    var upHeight: Double
    /// Equator to the underside at the sides.
    var downHeight: Double
    /// How far the underside lifts near the trunk.
    var notch: Double
    /// Horizontal drift of the crown's top, for asymmetry.
    var topShift: Double
    var lobeOrders: [Double]
    var lobeAmplitudes: [Double]
    var lobePhases: [Double]

    init(height: Double, width: Double, rng: inout SplitMix64) {
        let tipsTop = height - 13
        let halfWidth = width / 2 - 11
        let asymmetry = rng.range(0.025, 0.06) * rng.sign()
        centerX = rng.range(-0.025, 0.025) * width
        equatorY = height * rng.range(0.53, 0.57)
        halfWidthLeft = halfWidth * (1 + asymmetry)
        halfWidthRight = halfWidth * (1 - asymmetry)
        upHeight = tipsTop - equatorY
        downHeight = equatorY - height * rng.range(0.25, 0.28)
        notch = downHeight * rng.range(0.22, 0.3)
        topShift = rng.range(0.03, 0.07) * width * rng.sign()
        lobeOrders = [3, 5, 7]
        lobeAmplitudes = [rng.range(0.025, 0.045), rng.range(0.018, 0.03), rng.range(0.008, 0.016)]
        lobePhases = (0..<3).map { _ in rng.range(0, 2 * .pi) }
    }

    /// 1 on the outline, below 1 inside.
    func normalizedRadius(_ p: TreePoint) -> Double {
        let dy = p.y - equatorY
        let lift = dy > 0 ? topShift * min(1, dy / upHeight) : 0
        let dx = p.x - centerX - lift
        let a = dx < 0 ? halfWidthLeft : halfWidthRight
        let gauss = exp(-pow(dx / (0.4 * a), 2))
        let b = dy > 0 ? upHeight : max(8, downHeight - notch * gauss)
        let exponent = dy > 0 ? 2.35 : 2.1
        let u = abs(dx / a), v = abs(dy / b)
        let r = pow(pow(u, exponent) + pow(v, exponent), 1 / exponent)
        let theta = atan2(dy / b, dx / a)
        var lobes = 1.0
        for k in lobeOrders.indices {
            lobes += lobeAmplitudes[k] * sin(lobeOrders[k] * theta + lobePhases[k])
        }
        return r / lobes
    }

    /// How far a shoot from `start` heading along `direction` can grow before it leaves the crown: the distance to
    /// where it last exits the dome (a shoot starting below the dome first enters it). 0 if it never gets inside.
    func reach(from start: TreePoint, along direction: TreePoint) -> Double {
        let step = 2.0
        var travelled = 0.0, lastInside = -1.0
        while travelled < 480 {
            let p = start + direction * travelled
            if normalizedRadius(p) <= 1 {
                lastInside = travelled
            } else if lastInside >= 0 {
                break
            }
            travelled += step
        }
        return max(0, lastInside)
    }
}

/// The fully grown skeleton for one seed, built once by the recursion of spec §4.2 and then revealed by
/// `TreeLayout` as structural growth `g` rises. Every segment belongs to one depth, and each depth emerges at its
/// own threshold of g, so the topology never changes: segments only appear, lengthen and thicken.
///
/// The recursion: a short, stout trunk with a gentle S-curve forks low into 2–3 leaders (each with two side limbs
/// along it); every branch then ends in a fork whose leading child carries on almost straight while the other
/// splits off 22–38° to the side. Children are 0.74 × as long and 0.68 × as wide, each segment bends 4° upward,
/// 12% of the finer shoots are pruned (seeded), and recursion stops at depth 8. Lengths are fitted to the crown
/// dome, so the twig ends fill it evenly and the silhouette is the broad, asymmetric dome of an open-grown maple.
struct MatureTree: Sendable {
    struct Node: Sendable {
        /// Mature position (tree space, points at g = 1 before the growth scale).
        var position: TreePoint
        /// −1 for the trunk base.
        var parent: Int
        /// The recursion depth of the segment ending here: 1 trunk, 2 leaders, … 8 the finest twigs.
        var depth: Int
        /// Mature wood width at this node.
        var width: Double
        var children: [Int] = []
        /// The chain this node's incoming segment belongs to.
        var chain: Int = -1
        /// g at which the incoming segment starts growing; −1 means grown from the start.
        var threshold: Double = -1
    }

    /// A run of nodes drawn as one smooth, tapering limb. Each chain ends at exactly one twig end.
    struct Chain: Sendable {
        /// Base → tip. `nodes[0]`'s parent is `attach`.
        var nodes: [Int]
        /// The node on the parent chain this chain grows from (−1 for the trunk).
        var attach: Int
        var parentChain: Int
        /// 1 trunk, 2 leaders, 3 their limbs, … up to 8.
        var depth: Int
        /// Threshold of the chain's first node: when the twig sprouts.
        var sprout: Double
    }

    static let matureHeight = 350.0
    static let matureWidth = 340.0
    /// Each segment grows from nothing to full length over this much g (spec §4.2).
    static let emergenceWindow = 0.10
    /// Depths 1–3 exist at g = 0; each later depth appears at its threshold (spec §4.2).
    static let depthThresholds: [Double] = [-1, -1, -1, -1, 0.05, 0.18, 0.34, 0.52, 0.72]
    static let maxDepth = 8
    /// Child length and width relative to the parent (spec §4.2).
    static let lengthRatio = 0.74
    static let widthTaper = 0.68
    /// Upward bend per segment, radians (spec §4.2: +4°).
    static let upwardBend = 4 * Double.pi / 180
    /// Seeded pruning of the finer shoots (spec §4.2: 12%).
    static let pruning = 0.12
    /// Trunk width at the ground when mature (spec §4.3).
    static let trunkBaseWidth = 22.0
    /// Twig ends stay outside this fraction of the crown's radius, so the fork and the limbs leaving it show.
    static let innerRadius = 0.2
    static let curveSamples = 100
    /// The seedling's trunk is this fraction of its mature length, and lengthens to full by g = 0.6.
    static let seedlingTrunk = 0.8

    var nodes: [Node]
    var chains: [Chain]
    /// Non-trunk chains in primary-slot order: by sprout time, then from the crown outward, alternating sides.
    var slotOrder: [Int]
    var envelope: CrownEnvelope
    var forkNode: Int
    /// Growth curves sampled at g = i / curveSamples: horizontal and vertical scale, width scale. Non-decreasing.
    var scaleX: [Double]
    var scaleY: [Double]
    var widthScale: [Double]

    // MARK: Cache

    private static let cache = Mutex<[UInt64: MatureTree]>([:])

    /// The mature tree for `seed`, grown once per process (a few milliseconds) and then reused.
    static func of(seed: UInt64) -> MatureTree {
        if let cached = cache.withLock({ $0[seed] }) {
            return cached
        }
        let built = MatureTree(seed: seed)
        return cache.withLock { storage in
            if let raced = storage[seed] {
                return raced
            }
            if storage.count >= 8 {
                storage.removeAll()
            }
            storage[seed] = built
            return built
        }
    }

    // MARK: Growth

    init(seed: UInt64) {
        var rng = SplitMix64(seed: SplitMix64.derive(seed, "maple.tree.structure"))
        let height = Self.matureHeight
        envelope = CrownEnvelope(height: height, width: Self.matureWidth, rng: &rng)
        var grower = Grower(envelope: envelope, rng: SplitMix64(seed: SplitMix64.derive(seed, "maple.tree.branches")))

        // Trunk: short and stout with a gentle S-curve, forking low (0.28 × height).
        let forkY = height * rng.range(0.265, 0.295)
        let sway = rng.range(1.5, 3) * rng.sign()
        let lean = envelope.centerX * 0.3 + rng.range(-2.5, 2.5)
        let trunkSteps = 9
        let trunk = grower.newChain(attach: -1, parentChain: -1, depth: 1)
        for i in 0...trunkSteps {
            let t = Double(i) / Double(trunkSteps)
            let x = sway * sin(2 * .pi * t) * (1 - 0.35 * t) + lean * t * t
            let width = Self.trunkBaseWidth * pow(Self.widthTaper, t)
            _ = grower.add(TreePoint(x: x, y: forkY * t), parent: i - 1, depth: 1, width: width, chain: trunk)
        }
        let fork = grower.nodes.count - 1
        forkNode = fork

        // Leaders: 2 or 3 (3 with probability 0.6), spreading out of the fork toward the crown's shoulders. Each
        // takes its own stretch of the crown's outline, and every fork below splits its stretch between its two
        // children, so the twig ends spread evenly over the whole dome.
        let leaderCount = rng.unit() < 0.6 ? 3 : 2
        let degrees = Double.pi / 180
        let crownTilt = (envelope.halfWidthRight - envelope.halfWidthLeft) / envelope.halfWidthLeft * 0.6
        let angles: [Double] = leaderCount == 3
            ? [-rng.range(38, 48), rng.range(3, 9) * rng.sign(), rng.range(38, 48)].map { $0 * degrees + crownTilt }
            : [-rng.range(28, 38), rng.range(28, 38)].map { $0 * degrees + crownTilt }
        var cuts: [Double] = [0]
        for k in 1..<leaderCount {
            cuts.append(Double(k) / Double(leaderCount) + rng.range(-0.04, 0.04))
        }
        cuts.append(1)
        // Each leader tapers ×0.68 from the trunk's top; three share it a little more thinly (pipe model), at ×0.6.
        let leaderWidth = Self.trunkBaseWidth * Self.widthTaper * (leaderCount == 3 ? 0.6 : Self.widthTaper)
        for (k, angle) in angles.enumerated() {
            let direction = TreePoint.direction(angleFromUp: angle)
            let region = Grower.Region(u: cuts[k]...cuts[k + 1], r: Self.innerRadius...1)
            let length = grower.fittedLength(from: grower.nodes[fork].position, region: region, depth: 2, nominal: 78)
            let chain = grower.newChain(attach: fork, parentChain: trunk, depth: 2)
            // Side limbs start on the outer side of an outer leader; the middle leader's side is seeded. Two
            // leaders carry three limbs each, so every crown has about as many twigs.
            let outward: Double = angle < -0.1 ? -1 : (angle > 0.1 ? 1 : rng.sign())
            grower.grow(
                from: fork, direction: direction, depth: 2, length: length, width: leaderWidth, chain: chain,
                region: region, side: outward, limbs: leaderCount == 3 ? 2 : 3
            )
        }

        // Emergence: depths 1–3 are the seedling; every later depth appears at its own threshold.
        var nodes = grower.nodes
        for j in nodes.indices {
            nodes[j].threshold = Self.depthThresholds[min(Self.maxDepth, nodes[j].depth)]
        }
        var chains = grower.chains
        for c in chains.indices {
            chains[c].sprout = nodes[chains[c].nodes[0]].threshold
        }

        self.nodes = nodes
        self.chains = chains
        slotOrder = []
        scaleX = []
        scaleY = []
        widthScale = []
        slotOrder = Self.orderSlots(nodes: nodes, chains: chains)
        computeCurves()
    }

    /// Builds the branching recursively, recording every node and the chains that join them into limbs.
    ///
    /// The crown is measured in polar terms around a focus low in the dome: `u` runs along the outline from the
    /// left shoulder over the top to the right shoulder (0…1, by arc length) and `r` from the focus (0) to the
    /// outline (1). Seen from the front, a dome's surface covers its whole disc, so twig ends belong everywhere in
    /// it, not only on the rim. Every branch owns a *region* of (u, r); each fork splits its region between its
    /// two children, along u or along r (the leading child keeps the outer part), so the twig ends spread evenly.
    private struct Grower {
        static let gatherDepth = 6
        static let gathering = 0.72

        struct Region {
            var u: ClosedRange<Double>
            var r: ClosedRange<Double>
            /// A chosen spot for a single twig end, in (u, r).
            var aim: (u: Double, r: Double)?

            var uMiddle: Double { (u.lowerBound + u.upperBound) / 2 }
            /// The radius that halves the region's area.
            var rMiddle: Double { ((r.lowerBound * r.lowerBound + r.upperBound * r.upperBound) / 2).squareRoot() }

            /// The region drawn in toward its middle by `factor`, so the twigs inside it gather into one mass of
            /// foliage with a little sky around it.
            func gathered(by factor: Double) -> Region {
                let du = (u.upperBound - u.lowerBound) * factor / 2, dr = (r.upperBound - r.lowerBound) * factor / 2
                let mu = uMiddle, mr = (r.lowerBound + r.upperBound) / 2
                return Region(u: (mu - du)...(mu + du), r: (mr - dr)...(mr + dr))
            }
        }

        let envelope: CrownEnvelope
        var rng: SplitMix64
        var nodes: [Node] = []
        var chains: [Chain] = []
        let focus: TreePoint
        /// The crown's outline, evenly spaced by arc length from the left shoulder to the right.
        let outline: [TreePoint]
        let outlineLength: Double
        let meanRadius: Double

        init(envelope: CrownEnvelope, rng: SplitMix64) {
            self.envelope = envelope
            self.rng = rng
            let focus = TreePoint(x: envelope.centerX, y: envelope.equatorY - envelope.downHeight * 0.2)
            self.focus = focus
            let spread = 118 * Double.pi / 180
            var raw: [TreePoint] = []
            for i in 0...240 {
                let angle = -spread + 2 * spread * Double(i) / 240
                let direction = TreePoint.direction(angleFromUp: angle)
                raw.append(focus + direction * envelope.reach(from: focus, along: direction))
            }
            var lengths = [0.0]
            for i in 1..<raw.count {
                lengths.append(lengths[i - 1] + raw[i].distance(to: raw[i - 1]))
            }
            let total = max(1, lengths[lengths.count - 1])
            var even: [TreePoint] = []
            var j = 0
            for i in 0...200 {
                let target = total * Double(i) / 200
                while j < lengths.count - 2, lengths[j + 1] < target {
                    j += 1
                }
                let span = max(1e-9, lengths[j + 1] - lengths[j])
                even.append(TreePoint.lerp(raw[j], raw[j + 1], min(1, max(0, (target - lengths[j]) / span))))
            }
            outline = even
            outlineLength = total
            meanRadius = even.map { $0.distance(to: focus) }.reduce(0, +) / Double(even.count)
        }

        /// The crown point at outline position `u` and radius `r`.
        func point(u: Double, r: Double) -> TreePoint {
            let x = min(1, max(0, u)) * Double(outline.count - 1)
            let i = min(outline.count - 2, Int(x))
            let edge = TreePoint.lerp(outline[i], outline[i + 1], x - Double(i))
            return focus + (edge - focus) * r
        }

        /// Where a region's twig ends gather: its chosen spot, or else its middle by area.
        func target(of region: Region) -> TreePoint {
            if let aim = region.aim {
                return point(u: aim.u, r: aim.r)
            }
            return point(u: region.uMiddle, r: region.rMiddle)
        }

        /// The region with a seeded spot anywhere inside it (evenly by area) for its twig end, so the finest
        /// twigs never line up in rows or rings.
        mutating func scattered(_ region: Region) -> Region {
            var region = region
            let lo = region.r.lowerBound, hi = region.r.upperBound
            let r = (lo * lo + (hi * hi - lo * lo) * rng.unit()).squareRoot()
            region.aim = (rng.range(region.u.lowerBound, region.u.upperBound), r)
            return region
        }

        mutating func newChain(attach: Int, parentChain: Int, depth: Int) -> Int {
            chains.append(Chain(nodes: [], attach: attach, parentChain: parentChain, depth: depth, sprout: -1))
            return chains.count - 1
        }

        mutating func add(_ position: TreePoint, parent: Int, depth: Int, width: Double, chain: Int) -> Int {
            nodes.append(Node(position: position, parent: parent, depth: depth, width: width, chain: chain))
            let index = nodes.count - 1
            if parent >= 0 {
                nodes[parent].children.append(index)
            }
            chains[chain].nodes.append(index)
            return index
        }

        /// A branch length that lets the branch and everything it will carry reach its region: the distance left
        /// divided by how far the remaining depths reach (1 + 0.74 + 0.74² + … along a gently curving path),
        /// kept near the nominal 0.74 × parent.
        mutating func fittedLength(from start: TreePoint, region: Region, depth: Int, nominal: Double) -> Double {
            let remaining = MatureTree.maxDepth - depth
            // The leaders and their limbs reach a little further than their share, so the sapling (depths 1–3)
            // already spreads like a small crown rather than a broom.
            let reach = depth <= 3 ? 0.76 : 0.88
            let reachFactor = (1 - pow(MatureTree.lengthRatio, Double(remaining + 1))) / (1 - MatureTree.lengthRatio) * reach
            let room = start.distance(to: target(of: region))
            let fill = depth == MatureTree.maxDepth ? rng.range(0.8, 1.05) : rng.range(0.88, 1.02)
            let fitted = room * fill / reachFactor
            return min(max(fitted, nominal * 0.4), nominal * 1.4)
        }

        /// Splits a region in two across its longer side (its arc along u, or its depth along r), with a little
        /// seeded play. Returns the lower-u (or inner) part first.
        mutating func split(_ region: Region) -> (first: Region, second: Region, alongU: Bool) {
            let arc = (region.u.upperBound - region.u.lowerBound) * outlineLength * region.rMiddle
            let depth = (region.r.upperBound - region.r.lowerBound) * meanRadius
            let alongU = arc >= depth * rng.range(0.8, 1.25)
            if alongU {
                let cut = region.u.lowerBound + (region.u.upperBound - region.u.lowerBound) * rng.range(0.42, 0.58)
                return (Region(u: region.u.lowerBound...cut, r: region.r), Region(u: cut...region.u.upperBound, r: region.r), true)
            }
            // Equal areas, nudged outward so the rim is a little fuller than the inside.
            let lo = region.r.lowerBound, hi = region.r.upperBound
            let middle = ((lo * lo + hi * hi) / 2).squareRoot() + (hi - lo) * rng.range(-0.12, 0.12)
            let cut = min(max(middle, lo + 0.15 * (hi - lo)), hi - 0.15 * (hi - lo))
            return (Region(u: region.u, r: lo...cut), Region(u: region.u, r: cut...hi), false)
        }

        /// Grows a branch of `depth` from node `attach`, then everything it carries, steering toward its region.
        /// A leader carries `limbs` side limbs along its length, the first on `side` (±1).
        mutating func grow(
            from attach: Int, direction start: TreePoint, depth: Int, length: Double, width: Double, chain: Int,
            region: Region, side: Double = 1, limbs: Int = 0
        ) {
            let steps = depth == 2 ? 6 : (depth <= 4 ? 3 : 2)
            var direction = start
            var position = nodes[attach].position
            var parent = attach
            var created: [Int] = []
            let wobble = (depth <= 3 ? 2.0 : 4.5) * Double.pi / 180
            let steer = (depth == 2 ? 5.0 : (depth <= 4 ? 9.0 : 12.0)) * Double.pi / 180
            let goal = target(of: region)
            for s in 1...steps {
                var angle = direction.angleFromUp
                // +4° upward per segment, spread over its steps.
                let bend = MatureTree.upwardBend / Double(steps)
                angle -= angle > 0 ? min(angle, bend) : max(angle, -bend)
                // Steer gently toward the branch's region, with a little seeded wobble.
                let toward = (goal - position).normalized(or: direction).angleFromUp
                let turn = remainder(toward - angle, 2 * .pi)
                angle += max(-steer, min(steer, turn)) + rng.range(-wobble, wobble)
                direction = TreePoint.direction(angleFromUp: angle)
                position += direction * (length / Double(steps))
                let w = width * pow(MatureTree.widthTaper, Double(s) / Double(steps))
                parent = add(position, parent: parent, depth: depth, width: w, chain: chain)
                created.append(parent)
            }

            // Side limbs take the u-edges of the region, alternately outer and inner, from low on the leader up;
            // the end fork shares what is left.
            var forkRegion = region
            if limbs > 0 {
                let share = (region.u.upperBound - region.u.lowerBound) / Double(limbs + 2)
                var limbSide = side
                let places: [Double] = limbs == 2 ? [0.33, 0.67] : [0.28, 0.52, 0.76]
                for (k, place) in places.prefix(limbs).enumerated() {
                    let node = created[min(steps - 2, max(0, Int((place * Double(steps)).rounded()) - 1))]
                    let cut = share * rng.range(0.9, 1.1)
                    let lo = forkRegion.u.lowerBound, hi = forkRegion.u.upperBound
                    let limbRegion = Region(u: limbSide < 0 ? lo...(lo + cut) : (hi - cut)...hi, r: region.r)
                    forkRegion.u = limbSide < 0 ? (lo + cut)...hi : lo...(hi - cut)
                    let along = (nodes[node].position - nodes[nodes[node].parent].position).normalized()
                    let spread = rng.range(34, 44) * Double.pi / 180 * (k % 2 == 0 ? 1 : 0.8)
                    let dir = TreePoint.direction(angleFromUp: along.angleFromUp + limbSide * spread)
                    let l = fittedLength(from: nodes[node].position, region: limbRegion, depth: 3, nominal: length * MatureTree.lengthRatio)
                    let c = newChain(attach: node, parentChain: chain, depth: 3)
                    grow(
                        from: node, direction: dir, depth: 3, length: l, width: nodes[node].width * MatureTree.widthTaper,
                        chain: c, region: limbRegion
                    )
                    limbSide = -limbSide
                }
            }
            guard depth < MatureTree.maxDepth else { return }

            // The end fork: the leading child carries on almost straight, the other splits 22–38° to the side.
            // Split along u, each takes its own side; split along r, the leading child keeps the outer part.
            let tip = parent
            let here = nodes[tip].position
            let childDepth = depth + 1
            let theta = rng.range(22, 38) * Double.pi / 180
            let delta = rng.range(6, 14) * Double.pi / 180
            let parts = split(forkRegion)
            var lateralSide = rng.sign()
            var leadRegion: Region, sideRegion: Region
            if parts.alongU {
                leadRegion = lateralSide > 0 ? parts.first : parts.second
                sideRegion = lateralSide > 0 ? parts.second : parts.first
            } else {
                leadRegion = parts.second
                sideRegion = parts.first
                // The inner shoot turns toward the side its region lies on.
                let inner = target(of: sideRegion)
                let cross = direction.x * (inner.y - here.y) - direction.y * (inner.x - here.x)
                lateralSide = cross > 0 ? -1 : 1
            }
            let a = direction.angleFromUp
            let leadDirection = TreePoint.direction(angleFromUp: a - lateralSide * delta)
            let sideDirection = TreePoint.direction(angleFromUp: a + lateralSide * theta)
            var keepLead = true, keepSide = true
            if childDepth >= 4 {
                keepLead = rng.unit() >= MatureTree.pruning
                keepSide = rng.unit() >= MatureTree.pruning
                if !keepLead, !keepSide {
                    keepLead = true
                }
            }
            // A pruned shoot leaves its region to the one that remains.
            if !keepSide {
                leadRegion = forkRegion
            }
            if !keepLead {
                sideRegion = forkRegion
            }
            // The finer twigs gather into masses of foliage, as a crown's leaves do at its branch ends.
            if childDepth == Self.gatherDepth {
                leadRegion = leadRegion.gathered(by: Self.gathering)
                sideRegion = sideRegion.gathered(by: Self.gathering)
            }
            if childDepth == MatureTree.maxDepth {
                leadRegion = scattered(leadRegion)
                sideRegion = scattered(sideRegion)
            }
            let nominal = length * MatureTree.lengthRatio
            let childWidth = width * MatureTree.widthTaper
            let leadLength = fittedLength(from: here, region: leadRegion, depth: childDepth, nominal: nominal)
            let sideLength = fittedLength(from: here, region: sideRegion, depth: childDepth, nominal: nominal * 0.92)
            if keepLead {
                grow(from: tip, direction: leadDirection, depth: childDepth, length: leadLength, width: childWidth, chain: chain, region: leadRegion)
            }
            if keepSide {
                // With the leading shoot pruned, the side shoot carries the limb on.
                let c = keepLead ? newChain(attach: tip, parentChain: chain, depth: childDepth) : chain
                grow(from: tip, direction: sideDirection, depth: childDepth, length: sideLength, width: childWidth, chain: c, region: sideRegion)
            }
        }
    }

    /// Primary-slot order: chains that sprout earlier come first, so the first k species always sit on k distinct
    /// twig ends. Within one sprouting, from the crown outward (nearest the crown's top centre first),
    /// alternating left and right (spec §4.5).
    private static func orderSlots(nodes: [Node], chains: [Chain]) -> [Int] {
        var groups: [Double: [Int]] = [:]
        for c in chains.indices.dropFirst() {
            groups[max(-1, chains[c].sprout), default: []].append(c)
        }
        var order: [Int] = []
        for key in groups.keys.sorted() {
            let members = groups[key] ?? []
            // The position each twig end has when it sprouts: its deepest node grown at that moment.
            func front(_ c: Int) -> TreePoint {
                let chain = chains[c]
                let grown = chain.nodes.last { nodes[$0].threshold <= key } ?? chain.nodes[0]
                return nodes[grown].position
            }
            let fronts = members.map(front)
            let meanX = fronts.map(\.x).reduce(0, +) / Double(max(1, fronts.count))
            let top = fronts.map(\.y).max() ?? 0
            let focus = TreePoint(x: meanX, y: top)
            let sorted = zip(members, fronts).sorted { a, b in
                let da = a.1.distance(to: focus), db = b.1.distance(to: focus)
                return da != db ? da < db : a.0 < b.0
            }
            var left = sorted.filter { $0.1.x < focus.x }.map(\.0)
            var right = sorted.filter { $0.1.x >= focus.x }.map(\.0)
            var takeLeft = (sorted.first.map { $0.1.x < focus.x }) ?? true
            while !left.isEmpty || !right.isEmpty {
                if takeLeft, !left.isEmpty {
                    order.append(left.removeFirst())
                } else if !right.isEmpty {
                    order.append(right.removeFirst())
                } else {
                    order.append(left.removeFirst())
                }
                takeLeft.toggle()
            }
        }
        return order
    }

    /// The non-decreasing sequence closest to `values` in least squares (isotonic regression by pooling adjacent
    /// violators), so the growth curves follow their targets as closely as "only ever grows" allows.
    static func nonDecreasing(_ values: [Double]) -> [Double] {
        var blocks: [(mean: Double, count: Int)] = []
        for value in values {
            blocks.append((value, 1))
            while blocks.count >= 2, blocks[blocks.count - 2].mean > blocks[blocks.count - 1].mean {
                let b = blocks.removeLast(), a = blocks.removeLast()
                let count = a.count + b.count
                blocks.append(((a.mean * Double(a.count) + b.mean * Double(b.count)) / Double(count), count))
            }
        }
        return blocks.flatMap { Array(repeating: $0.mean, count: $0.count) }
    }

    /// The least-squares non-decreasing fit, lifted wherever it would fall below `share` of its target (each depth
    /// spreads the crown in a step while the target widens steadily; a sapling a little wide reads better than a
    /// narrow broom). Still non-decreasing: the lift only ever rises.
    static func nonDecreasing(_ values: [Double], within share: Double) -> [Double] {
        var floor = 0.0
        return zip(nonDecreasing(values), values).map { fitted, value in
            floor = max(floor, value * share)
            return max(fitted, floor)
        }
    }

    // MARK: Emergence

    /// How grown node `j`'s incoming segment is at growth `g`: 0 (not yet) … 1 (full length).
    func emergence(_ j: Int, at g: Double) -> Double {
        if j <= forkNode {
            return j == 0 ? 1 : TreeMath.lerp(Self.seedlingTrunk, 1, 1 - pow(1 - min(1, g / 0.6), 2))
        }
        let threshold = nodes[j].threshold
        guard threshold >= 0 else { return 1 }
        return TreeMath.smoothstep((g - threshold) / Self.emergenceWindow)
    }

    /// Leaf size on the tree at growth g, before seeded variation (spec §4.5).
    static func leafSize(at g: Double) -> Double {
        TreeMath.lerp(18, 11, TreeMath.clamp(g))
    }

    /// Samples a non-decreasing curve at g by linear interpolation.
    static func sample(_ curve: [Double], at g: Double) -> Double {
        let x = TreeMath.clamp(g) * Double(curve.count - 1)
        let i = min(curve.count - 2, Int(x.rounded(.down)))
        return TreeMath.lerp(curve[i], curve[i + 1], x - Double(i))
    }

    /// Scale and girth curves, chosen so the revealed tree matches spec §4.3 (H = lerp(140, 350, g),
    /// W = lerp(110, 340, g), trunk base lerp(4, 22, g)) and made non-decreasing, so segments only ever
    /// lengthen and thicken.
    private mutating func computeCurves() {
        var rawX: [Double] = [], rawY: [Double] = [], rawWidth: [Double] = []
        var position = [TreePoint](repeating: .zero, count: nodes.count)
        for i in 0...Self.curveSamples {
            let g = Double(i) / Double(Self.curveSamples)
            var minX = 0.0, maxX = 0.0, maxY = 0.0
            for j in nodes.indices {
                let e = emergence(j, at: g)
                let parent = nodes[j].parent
                guard parent >= 0 else { continue }
                position[j] = position[parent] + (nodes[j].position - nodes[parent].position) * e
                if e > 0.01 {
                    minX = min(minX, position[j].x)
                    maxX = max(maxX, position[j].x)
                    maxY = max(maxY, position[j].y)
                }
            }
            let leaf = Self.leafSize(at: g)
            let targetHeight = TreeMath.lerp(140, 350, g) - 0.92 * leaf
            let targetWidth = TreeMath.lerp(110, 340, g) - 1.2 * leaf
            let sy = targetHeight / max(1, maxY)
            let sx = min(max(targetWidth / max(1, maxX - minX), sy * 0.72), sy * 1.3)
            rawY.append(sy)
            rawX.append(sx)
            rawWidth.append(TreeMath.lerp(4, 22, g) / Self.trunkBaseWidth)
        }
        scaleX = Self.nonDecreasing(rawX, within: 0.86)
        scaleY = Self.nonDecreasing(rawY)
        widthScale = Self.nonDecreasing(rawWidth)
    }
}
