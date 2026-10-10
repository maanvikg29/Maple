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

    var bounds: (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        let pad = 1.12
        return (
            centerX - halfWidthLeft * pad - abs(topShift),
            centerX + halfWidthRight * pad + abs(topShift),
            equatorY - downHeight * pad,
            equatorY + upHeight * pad
        )
    }
}

/// The fully grown skeleton for one seed, grown once by space colonisation and then revealed by `TreeLayout`
/// as structural growth `g` rises. Every node records when it was born, so emergence is a pure function of g:
/// nodes only appear and lengthen, and the topology never changes.
struct MatureTree: Sendable {
    struct Node: Sendable {
        /// Mature position (tree space, points at g = 1 before the growth scale).
        var position: TreePoint
        /// −1 for the trunk base.
        var parent: Int
        /// Growth iteration; 0 for the hand-built trunk and leaders.
        var birth: Int
        var children: [Int] = []
        /// The chain this node's incoming segment belongs to.
        var chain: Int = -1
        /// g at which the incoming segment starts growing; −1 means grown from the start.
        var threshold: Double = -1
        /// Mature subtree size (nodes, including this one).
        var subtree: Int = 1
    }

    /// A run of nodes drawn as one smooth, tapering limb. Each chain ends at exactly one twig end.
    struct Chain: Sendable {
        /// Base → tip. `nodes[0]`'s parent is `attach`.
        var nodes: [Int]
        /// The node on the parent chain this chain grows from (−1 for the trunk).
        var attach: Int
        var parentChain: Int
        /// 1 trunk, 2 leaders, 3 their limbs, … capped at 8.
        var depth: Int
        /// Threshold of the chain's first node: when the twig sprouts.
        var sprout: Double
    }

    static let matureHeight = 350.0
    static let matureWidth = 340.0
    /// Each segment grows from nothing to full length over this much g (spec §4.2).
    static let emergenceWindow = 0.10
    /// The last segment starts growing at this g, so the structure is complete by g ≈ 0.9.
    static let lastSprout = 0.80
    /// Pipe-model exponent: a parent's cross-section carries its children's (da Vinci rule, area-like).
    static let pipeExponent = 2.1
    static let curveSamples = 100
    /// Growth is made denser until the mature crown has at least this many twig ends (155 species, buds and
    /// the featured leaf, with room to spare).
    static let targetTwigEnds = 160
    /// The seedling's trunk is this fraction of its mature length, and lengthens to full by g = 0.6.
    static let seedlingTrunk = 0.62

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
        var nodes: [Node] = []

        // Trunk: short and stout with a gentle S-curve, forking low (0.28 × height).
        let forkY = height * rng.range(0.265, 0.295)
        let sway = rng.range(1.5, 3) * rng.sign()
        let lean = envelope.centerX * 0.3 + rng.range(-2.5, 2.5)
        let trunkSteps = 9
        for i in 0...trunkSteps {
            let t = Double(i) / Double(trunkSteps)
            let x = sway * sin(2 * .pi * t) * (1 - 0.35 * t) + lean * t * t
            nodes.append(Node(position: TreePoint(x: x, y: forkY * t), parent: i - 1, birth: 0))
        }
        let fork = nodes.count - 1
        forkNode = fork

        // Leaders: 2 or 3 (3 with probability 0.6), short, spreading out of the fork. The crown itself is grown
        // from their tips by colonisation, so the limbs find their own way into the dome.
        let leaderCount = rng.unit() < 0.6 ? 3 : 2
        let degrees = Double.pi / 180
        let angles: [Double] = leaderCount == 3
            ? [-rng.range(32, 42), rng.range(7, 13) * rng.sign(), rng.range(30, 40)].map { $0 * degrees }
            : [-rng.range(22, 32), rng.range(22, 32)].map { $0 * degrees }
        let crownTilt = (envelope.halfWidthRight - envelope.halfWidthLeft) / envelope.halfWidthLeft * 0.8
        var growing: Set<Int> = []
        for base in angles {
            let length = height * rng.range(0.085, 0.12) * (abs(base) < 0.2 ? 1.15 : 1)
            let steps = max(2, Int((length / 7).rounded()))
            var position = nodes[fork].position
            var parent = fork
            for s in 1...steps {
                let t = Double(s) / Double(steps)
                let angle = (base + crownTilt) * TreeMath.lerp(1.15, 0.85, t)
                position += TreePoint.direction(angleFromUp: angle) * (length / Double(steps))
                nodes.append(Node(position: position, parent: parent, birth: 0))
                parent = nodes.count - 1
            }
            growing.insert(parent)
        }

        // Space colonisation, made denser until the crown has room for every species on its own twig.
        let scaffold = nodes
        for attractionCount in [4800, 6400] {
            var attempt = rng
            nodes = Self.colonise(scaffold, growing: growing, envelope: envelope, attractionCount: attractionCount, rng: &attempt)
            var parents = Set<Int>()
            for node in nodes where node.parent >= 0 {
                parents.insert(node.parent)
            }
            if nodes.count - parents.count >= Self.targetTwigEnds {
                break
            }
        }

        // Children of the hand-built nodes (added before the loop) and subtree sizes.
        for j in nodes.indices {
            nodes[j].children = []
        }
        for j in nodes.indices where nodes[j].parent >= 0 {
            nodes[nodes[j].parent].children.append(j)
        }
        for j in nodes.indices.reversed() where nodes[j].parent >= 0 {
            nodes[nodes[j].parent].subtree += nodes[j].subtree
        }

        // Chains: a node's earliest-born child continues its chain (ties: the larger subtree); others start
        // new chains one level deeper. The trunk ends at the fork, where every leader starts its own chain.
        var chains: [Chain] = [Chain(nodes: Array(0...fork), attach: -1, parentChain: -1, depth: 1, sprout: -1)]
        for j in 0...fork {
            nodes[j].chain = 0
        }
        var stack: [(start: Int, attach: Int, parentChain: Int, depth: Int)] = []
        for child in nodes[fork].children.reversed() {
            stack.append((child, fork, 0, 2))
        }
        func continuation(of node: Node) -> Int? {
            node.children.min { a, b in
                let na = nodes[a], nb = nodes[b]
                return na.birth != nb.birth ? na.birth < nb.birth : (na.subtree != nb.subtree ? na.subtree > nb.subtree : a < b)
            }
        }
        while let item = stack.popLast() {
            let chainIndex = chains.count
            var members: [Int] = []
            var current: Int? = item.start
            while let node = current {
                members.append(node)
                nodes[node].chain = chainIndex
                let main = continuation(of: nodes[node])
                for child in nodes[node].children.reversed() where child != main {
                    stack.append((child, node, chainIndex, min(8, item.depth + 1)))
                }
                current = main
            }
            chains.append(Chain(nodes: members, attach: item.attach, parentChain: item.parentChain, depth: item.depth, sprout: -1))
        }

        // Smooth the colonised chains (the trunk and leaders are already smooth): space colonisation grows
        // in short straight steps, and a few Laplacian passes turn them into continuous curves.
        for _ in 0..<8 {
            for chain in chains.dropFirst() {
                let path = [chain.attach] + chain.nodes
                guard path.count >= 3 else { continue }
                var updated: [TreePoint] = []
                for k in 1..<(path.count - 1) {
                    let node = path[k]
                    guard nodes[node].birth > 0 else {
                        updated.append(nodes[node].position)
                        continue
                    }
                    let mid = TreePoint.lerp(nodes[path[k - 1]].position, nodes[path[k + 1]].position, 0.5)
                    updated.append(TreePoint.lerp(nodes[node].position, mid, 0.5))
                }
                for k in 1..<(path.count - 1) {
                    nodes[path[k]].position = updated[k - 1]
                }
            }
        }

        // Emergence: the trunk, leaders and the first few colonisation passes form the seedling (g = 0).
        // Later births are revealed in order, paced by cumulative node count so growth looks steady.
        let maxBirth = nodes.map(\.birth).max() ?? 0
        var bornAt = [Int](repeating: 0, count: maxBirth + 1)
        for node in nodes where node.birth > 0 {
            bornAt[node.birth] += 1
        }
        var cumulative = [Int](repeating: 0, count: maxBirth + 1)
        for b in 1...max(1, maxBirth) where b <= maxBirth {
            cumulative[b] = cumulative[b - 1] + bornAt[b]
        }
        // Seedling: the smallest number of passes that gives the sapling enough twig ends for its rosettes and buds.
        var initialPasses = min(2, maxBirth)
        while initialPasses < maxBirth {
            let sprouted = chains.dropFirst().filter { nodes[$0.nodes[0]].birth <= initialPasses }.count
            if sprouted >= 11 {
                break
            }
            initialPasses += 1
        }
        let revealed = Double(max(1, cumulative[maxBirth] - cumulative[initialPasses]))
        for j in nodes.indices {
            let b = nodes[j].birth
            if b <= initialPasses {
                nodes[j].threshold = -1
            } else {
                nodes[j].threshold = Self.lastSprout * Double(cumulative[b - 1] - cumulative[initialPasses]) / revealed
            }
        }
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

    /// Space colonisation (Runions et al. 2007): attraction points fill the crown; each pass, every point pulls
    /// on its nearest growing node, and nodes step toward the points pulling them. Returns the grown nodes.
    private static func colonise(
        _ scaffold: [Node], growing: Set<Int>, envelope: CrownEnvelope, attractionCount: Int, rng: inout SplitMix64
    ) -> [Node] {
        var nodes = scaffold
        var points: [TreePoint] = []
        points.reserveCapacity(attractionCount)
        let box = envelope.bounds
        var guardCount = 0
        while points.count < attractionCount, guardCount < 200_000 {
            guardCount += 1
            let p = TreePoint(x: rng.range(box.minX, box.maxX), y: rng.range(box.minY, box.maxY))
            let rho = envelope.normalizedRadius(p)
            guard rho <= 1 else { continue }
            if rng.unit() < 0.22 + 0.78 * rho * rho * rho {
                points.append(p)
            }
        }

        let step = 6.0
        let influence = 46.0
        let kill = 7.0
        // Lateral buds open only every second node, two passes behind the tip, at most one per node: real shoots
        // branch at spaced nodes, which keeps limbs from sprouting combs of parallel twigs.
        let budSpacing = 2
        var budIndex = [Int](repeating: 0, count: nodes.count)
        func canGrow(_ j: Int, at iteration: Int) -> Bool {
            let node = nodes[j]
            if node.children.isEmpty {
                return node.birth > 0 || growing.contains(j)
            }
            return node.birth > 0 && node.children.count == 1 && budIndex[j] % budSpacing == 0 && iteration - node.birth >= 2
        }
        var alive = [Bool](repeating: true, count: points.count)
        var closest = [Int](repeating: -1, count: points.count)
        var closestDistance = [Double](repeating: .infinity, count: points.count)
        var candidates: [Int] = Array(growing)
        var iteration = 0
        while iteration < 200 {
            iteration += 1
            // Only nodes added since the last pass can become a point's closest node.
            for p in points.indices where alive[p] {
                var best = closestDistance[p]
                var bestNode = closest[p]
                for j in candidates {
                    let d = points[p].distance(to: nodes[j].position)
                    if d < best {
                        best = d
                        bestNode = j
                    }
                }
                closestDistance[p] = best
                closest[p] = bestNode
                if best < kill {
                    alive[p] = false
                }
            }
            candidates = []

            let total = nodes.count
            var pull = [TreePoint](repeating: .zero, count: total)
            var count = [Int](repeating: 0, count: total)
            for p in points.indices where alive[p] && closest[p] >= 0 && closestDistance[p] <= influence {
                let j = closest[p]
                pull[j] += (points[p] - nodes[j].position).normalized()
                count[j] += 1
            }
            var grew = false
            for j in 0..<total where count[j] > 0 && canGrow(j, at: iteration) {
                let attraction = pull[j] * (1 / Double(count[j]))
                guard attraction.length > 0.15 else { continue }
                let parent = nodes[j].parent
                let incoming = parent >= 0 ? (nodes[j].position - nodes[parent].position).normalized() : .up
                let isLateral = !nodes[j].children.isEmpty
                // Laterals leave at an angle; tips keep some momentum. A little seeded wander keeps limbs organic.
                let wander = TreePoint.direction(angleFromUp: rng.range(0, 2 * .pi)) * 0.1
                let direction = (attraction.normalized() + incoming * (isLateral ? 0.05 : 0.42) + TreePoint.up * 0.05 + wander).normalized()
                let position = nodes[j].position + direction * step
                let duplicate = nodes[j].children.contains { nodes[$0].position.distance(to: position) < step * 0.7 }
                guard !duplicate else { continue }
                nodes.append(Node(position: position, parent: j, birth: iteration))
                budIndex.append(isLateral ? 1 : budIndex[j] + 1)
                nodes[j].children.append(nodes.count - 1)
                candidates.append(nodes.count - 1)
                grew = true
            }
            if !grew {
                break
            }
        }

        return nodes
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
                if key < 0 {
                    let grown = chain.nodes.last { nodes[$0].threshold < 0 } ?? chain.nodes[0]
                    return nodes[grown].position
                }
                return nodes[chain.nodes[chain.nodes.count - 1]].position
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

    // MARK: Emergence

    /// How grown node `j`'s incoming segment is at growth `g`: 0 (not yet) … 1 (full length).
    func emergence(_ j: Int, at g: Double) -> Double {
        if j <= forkNode {
            return j == 0 ? 1 : TreeMath.lerp(Self.seedlingTrunk, 1, TreeMath.smoothstep(g / 0.6))
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
        var subtree = [Double](repeating: 0, count: nodes.count)
        var position = [TreePoint](repeating: .zero, count: nodes.count)
        for i in 0...Self.curveSamples {
            let g = Double(i) / Double(Self.curveSamples)
            var minX = 0.0, maxX = 0.0, maxY = 0.0
            for j in nodes.indices {
                let e = emergence(j, at: g)
                subtree[j] = e
                let parent = nodes[j].parent
                guard parent >= 0 else { continue }
                position[j] = position[parent] + (nodes[j].position - nodes[parent].position) * e
                if e > 0.01 {
                    minX = min(minX, position[j].x)
                    maxX = max(maxX, position[j].x)
                    maxY = max(maxY, position[j].y)
                }
            }
            for j in nodes.indices.reversed() where nodes[j].parent >= 0 {
                subtree[nodes[j].parent] += subtree[j]
            }
            let leaf = Self.leafSize(at: g)
            let targetHeight = TreeMath.lerp(140, 350, g) - 0.92 * leaf
            let targetWidth = TreeMath.lerp(110, 340, g) - 2 * leaf
            let sy = targetHeight / max(1, maxY)
            let sx = min(max(targetWidth / max(1, maxX - minX), sy * 0.72), sy * 1.15)
            rawY.append(sy)
            rawX.append(sx)
            rawWidth.append(TreeMath.lerp(4, 22, g) / pow(max(1, subtree[0]), 1 / Self.pipeExponent))
        }
        scaleX = Self.nonDecreasing(rawX)
        scaleY = Self.nonDecreasing(rawY)
        widthScale = Self.nonDecreasing(rawWidth.map { max($0, 0.6) })
    }
}
