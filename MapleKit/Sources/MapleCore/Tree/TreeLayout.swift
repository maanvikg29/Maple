import Foundation

/// Deterministic layout of the maple (design spec §4.2–4.5).
///
/// The structure comes from a mature skeleton grown once per seed by **space colonisation**: attraction points
/// fill a broad, slightly asymmetric dome, and branches grow toward them from a short stout trunk that forks low
/// into 2–3 leaders. Every node records when it was born, so structural growth `g` simply reveals nodes in birth
/// order and lengthens them (smoothstep over Δg = 0.10). Widths follow the pipe model (da Vinci rule) over what is
/// grown. Nothing ever moves to a different branch: existing segments only lengthen and thicken.
///
/// Foliage follows the collection: every species owns a permanent twig (its *primary tip*), chosen in unlock
/// order from the twigs that sprout first, from the crown outward, alternating left and right. Extra rosettes
/// (satellites) go to the nearest free twigs, the next leaves hang as buds where they will grow, and the featured
/// leaf takes the crown's top free tip. Pure and deterministic: the same inputs always give the same skeleton.
public enum TreeLayout {
    /// Builds the tree for a seed at structural growth `growth` (g, 0…1).
    ///
    /// - Parameters:
    ///   - seed: The profile's seed (`SplitMix64.seed(for:)`); the silhouette is personal and stable.
    ///   - growth: Structural growth g from `TreeGrowth.structure(tendedDays:)`.
    ///   - species: Placed species ids, in unlock order.
    ///   - buds: The next leaves (up to 3, the Home next leaf first) as neutral buds.
    ///   - featured: The featured species; it gets an extra rosette at the crown's top tip.
    ///   - waiting: Earned species waiting to be opened, in order; each bud sits at its future primary tip.
    public static func generate(
        seed: UInt64,
        growth: Double,
        species: [String],
        buds: [TreeBudRequest] = [],
        featured: String? = nil,
        waiting: [String] = []
    ) -> TreeSkeleton {
        var builder = Builder(seed: seed, growth: growth)
        return builder.build(species: species, buds: buds, featured: featured, waiting: waiting)
    }

    /// The trunk-relative extent spec §4.3 asks for at growth g: height and crown width.
    public static func targetSize(growth g: Double) -> (height: Double, width: Double) {
        let g = TreeMath.clamp(g)
        return (TreeMath.lerp(140, 350, g), TreeMath.lerp(110, 340, g))
    }
}

// MARK: - Builder

private struct Builder {
    private enum Occupant {
        case rosette(Int)
        case bud(Int)
    }

    /// A planned rosette before its leaves are laid out.
    private struct Plan {
        var speciesID: String
        var kind: TreeSkeleton.RosetteKind
        var ordinal: Int
        var leafCount: Int
        var place: Place
    }

    /// Where something hangs: a twig end (shared or not) or a lateral node.
    private enum Place {
        case tip(Int)
        case lateral(Int)
    }

    let seed: UInt64
    let g: Double
    let mature: MatureTree
    var emergence: [Double]
    var position: [TreePoint]
    var width: [Double]
    /// Chain id → index into `tips` for sprouted chains.
    var tipIndex: [Int: Int] = [:]
    var tips: [TreeSkeleton.Tip] = []
    /// Front node of each sprouted chain.
    var front: [Int: Int] = [:]
    var crownCentre = TreePoint.zero
    var crownRadii = TreePoint(x: 1, y: 1)
    var leafSize: Double

    private var occupancy: [Int: [Occupant]] = [:]
    private var lateralTaken: Set<Int> = []
    private var lateralCandidates: [Int]?

    init(seed: UInt64, growth: Double) {
        self.seed = seed
        g = TreeMath.clamp(growth.isFinite ? growth : 0)
        mature = MatureTree.of(seed: seed)
        let nodes = mature.nodes
        let kx = MatureTree.sample(mature.scaleX, at: g)
        let ky = MatureTree.sample(mature.scaleY, at: g)
        let girth = MatureTree.sample(mature.widthScale, at: g)
        var emergence = [Double](repeating: 0, count: nodes.count)
        var position = [TreePoint](repeating: .zero, count: nodes.count)
        var width = [Double](repeating: 0, count: nodes.count)
        for j in nodes.indices {
            let e = mature.emergence(j, at: g)
            emergence[j] = e
            let parent = nodes[j].parent
            if parent >= 0 {
                let v = nodes[j].position - nodes[parent].position
                position[j] = position[parent] + TreePoint(x: v.x * kx, y: v.y * ky) * e
            }
            // Wood thickens with the whole tree; a new shoot starts slender and fills out as it lengthens.
            let shoot = nodes[j].threshold >= 0 ? 0.55 + 0.45 * e : 1
            width[j] = nodes[j].width * girth * shoot
        }
        self.emergence = emergence
        self.position = position
        self.width = width
        leafSize = MatureTree.leafSize(at: g)
        findTips(kx: kx, ky: ky)
    }

    // MARK: Structure

    private mutating func findTips(kx: Double, ky: Double) {
        let nodes = mature.nodes
        for (c, chain) in mature.chains.enumerated().dropFirst() {
            guard emergence[chain.nodes[0]] >= 0.5 else { continue }
            let last = chain.nodes.last { emergence[$0] >= 0.5 } ?? chain.nodes[0]
            front[c] = last
            let parent = nodes[last].parent
            let v = nodes[last].position - nodes[parent].position
            let direction = TreePoint(x: v.x * kx, y: v.y * ky).normalized()
            tipIndex[c] = tips.count
            tips.append(TreeSkeleton.Tip(id: c, position: position[last], direction: direction, shell: 1))
        }
        let xs = tips.map(\.position.x), ys = tips.map(\.position.y)
        let minX = xs.min() ?? -1, maxX = xs.max() ?? 1, minY = ys.min() ?? 0, maxY = ys.max() ?? 1
        crownCentre = TreePoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        crownRadii = TreePoint(x: max(12, (maxX - minX) / 2), y: max(12, (maxY - minY) / 2))
        for i in tips.indices {
            tips[i].shell = shell(of: tips[i].position)
        }
    }

    private func shell(of p: TreePoint) -> Double {
        let dx = (p.x - crownCentre.x) / crownRadii.x, dy = (p.y - crownCentre.y) / crownRadii.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// The sprouted twig a chain's leaves hang from now: the chain itself once it has sprouted, otherwise the
    /// nearest sprouted chain it grows from.
    private func resolve(_ chain: Int) -> Int {
        var c = chain
        while c > 0, tipIndex[c] == nil {
            c = mature.chains[c].parentChain
        }
        if c <= 0 {
            return mature.slotOrder.first { tipIndex[$0] != nil } ?? chain
        }
        return c
    }

    private func segments() -> [TreeSkeleton.Segment] {
        let nodes = mature.nodes
        var result: [TreeSkeleton.Segment] = []
        result.reserveCapacity(nodes.count)
        for j in nodes.indices where nodes[j].parent >= 0 && emergence[j] > 0 {
            let parent = nodes[j].parent
            let sameChain = nodes[parent].chain == nodes[j].chain
            result.append(TreeSkeleton.Segment(
                node: j,
                parentNode: parent,
                depth: nodes[j].depth,
                base: position[parent],
                tip: position[j],
                baseWidth: sameChain ? width[parent] : width[j],
                tipWidth: width[j],
                emergence: emergence[j]
            ))
        }
        return result
    }

    private func branches() -> [TreeSkeleton.Branch] {
        var result: [TreeSkeleton.Branch] = []
        for (c, chain) in mature.chains.enumerated() {
            let visible = chain.nodes.prefix { emergence[$0] > 0 }
            guard let first = visible.first else { continue }
            var points: [TreePoint] = [], widths: [Double] = []
            if chain.attach >= 0 {
                points.append(position[chain.attach])
                widths.append(width[first])
            }
            for node in visible {
                points.append(position[node])
                widths.append(width[node])
            }
            guard points.count >= 2 else { continue }
            result.append(TreeSkeleton.Branch(id: c, depth: chain.depth, points: points, widths: widths))
        }
        return result
    }

    // MARK: Foliage

    mutating func build(species rawSpecies: [String], buds rawBuds: [TreeBudRequest], featured: String?, waiting rawWaiting: [String]) -> TreeSkeleton {
        var seen: Set<String> = []
        let species = rawSpecies.filter { seen.insert($0).inserted }
        let waiting = rawWaiting.filter { seen.insert($0).inserted }
        let budRequests = Array(rawBuds.filter { seen.insert($0.speciesID).inserted }.prefix(3))
        let order = mature.slotOrder
        let n = species.count

        var plans: [Plan] = []
        var primaryTips: [String: Int] = [:]

        // 1. Primary rosettes: permanent twigs in unlock order.
        for (i, id) in species.enumerated() {
            let chain = order[i % order.count]
            primaryTips[id] = chain
            let tip = resolve(chain)
            occupancy[tip, default: []].append(.rosette(plans.count))
            plans.append(Plan(speciesID: id, kind: .primary, ordinal: 0, leafCount: 0, place: .tip(tip)))
        }

        // 2. Buds. Waiting buds sit at their species' future primary tip; the next leaves at the next free twigs.
        var budPlans: [(id: String, progress: Double, isNext: Bool, isWaiting: Bool, tip: Int)] = []
        for (k, id) in waiting.enumerated() {
            let tip = resolve(order[(n + k) % order.count])
            occupancy[tip, default: []].append(.bud(budPlans.count))
            budPlans.append((id, 1, false, true, tip))
        }
        var cursor = n + waiting.count
        for (j, request) in budRequests.enumerated() {
            var chosen: Int?
            var index = cursor
            while index < order.count {
                let chain = order[index]
                if tipIndex[chain] != nil, occupancy[chain] == nil {
                    chosen = chain
                    break
                }
                index += 1
            }
            let tip = chosen ?? resolve(order[cursor % order.count])
            cursor = chosen != nil ? index + 1 : cursor + 1
            occupancy[tip, default: []].append(.bud(budPlans.count))
            budPlans.append((request.speciesID, TreeMath.clamp(request.progress), j == 0, false, tip))
        }

        // 3. Instance budget (spec §4.5): floor(T / n) each, the remainder to the earliest species.
        let total = TreeGrowth.leafInstances(species: n, growth: g)
        var rosetteSizes: [[Int]] = []
        for i in 0..<n {
            let count = total / n + (i < total % n ? 1 : 0)
            // Rosettes of 3–6 leaves, about 5 each; from 6 leaves on a species is at least two rosettes, so a
            // young crown fills out instead of hanging one heavy fan per twig end.
            let rosettes = count >= 6 ? max(2, min(count / 3, Int((Double(count) / 5).rounded()))) : 1
            rosetteSizes.append((0..<rosettes).map { r in count / rosettes + (r < count % rosettes ? 1 : 0) })
            plans[i].leafCount = rosetteSizes[i][0]
        }

        // 4. The featured leaf's extra rosette at the crown's highest free tip.
        if let featured, species.contains(featured) {
            let free = tips.filter { occupancy[$0.id] == nil }
            let pool = free.isEmpty ? tips : free
            if let top = pool.max(by: { $0.position.y < $1.position.y }) {
                occupancy[top.id, default: []].append(.rosette(plans.count))
                plans.append(Plan(speciesID: featured, kind: .featured, ordinal: 0, leafCount: 3, place: .tip(top.id)))
            }
        }

        // 5. Satellites, one round at a time so every species' extra rosettes stay near its primary.
        let rounds = rosetteSizes.map(\.count).max() ?? 0
        if rounds > 1 {
            for round in 1..<rounds {
                for i in 0..<n where rosetteSizes[i].count > round {
                    guard case .tip(let home) = plans[i].place, let homeTip = tipIndex[home] else { continue }
                    let near = tips[homeTip].position
                    let place = nearestFreePlace(to: near, awayFrom: placedAnchors(plans))
                    switch place {
                    case .tip(let tip): occupancy[tip, default: []].append(.rosette(plans.count))
                    case .lateral(let node): lateralTaken.insert(node)
                    }
                    plans.append(Plan(
                        speciesID: species[i], kind: .satellite, ordinal: round,
                        leafCount: rosetteSizes[i][round], place: place
                    ))
                }
            }
        }

        // 6. Leaves.
        var rosettes: [TreeSkeleton.Rosette] = []
        var leaves: [TreeSkeleton.Leaf] = []
        for (p, plan) in plans.enumerated() {
            let (anchor, direction, tipID, rank) = locate(plan.place, occupant: p)
            let inner = shell(of: anchor) < 0.62
            let start = leaves.count
            leaves += fan(plan: plan, anchor: anchor, direction: direction, inner: inner, rosette: rosettes.count)
            rosettes.append(TreeSkeleton.Rosette(
                speciesID: plan.speciesID, kind: plan.kind, tipID: tipID, anchor: anchor, direction: direction,
                shareRank: rank, isInner: inner, leaves: start..<leaves.count
            ))
        }

        var buds: [TreeSkeleton.Bud] = []
        for (b, plan) in budPlans.enumerated() {
            let rank = occupancy[plan.tip]?.firstIndex { if case .bud(b) = $0 { true } else { false } } ?? 0
            let (anchor, direction) = point(onTip: plan.tip, rank: rank, salt: "bud.\(plan.id)")
            let lifted = (direction + TreePoint.up * 0.9).normalized()
            buds.append(TreeSkeleton.Bud(
                speciesID: plan.id, anchor: anchor, direction: lifted, progress: plan.progress,
                isNext: plan.isNext, isWaiting: plan.isWaiting, tipID: plan.tip
            ))
        }

        // Extent and centroid.
        let branchList = branches()
        var minX = 0.0, maxX = 0.0, maxY = 0.0
        for branch in branchList {
            for (point, w) in zip(branch.points, branch.widths) {
                minX = min(minX, point.x - w / 2)
                maxX = max(maxX, point.x + w / 2)
                maxY = max(maxY, point.y)
            }
        }
        var centroid = TreePoint.zero
        for leaf in leaves {
            let reach = leaf.anchor + TreePoint.direction(angleFromUp: leaf.rotation) * (leaf.size * 0.9)
            minX = min(minX, reach.x)
            maxX = max(maxX, reach.x)
            maxY = max(maxY, reach.y)
            centroid += leaf.anchor + TreePoint.direction(angleFromUp: leaf.rotation) * (leaf.size * 0.45)
        }
        if leaves.isEmpty {
            centroid = crownCentre
        } else {
            centroid = centroid * (1 / Double(leaves.count))
        }

        return TreeSkeleton(
            seed: seed, growth: g, segments: segments(), branches: branchList, tips: tips,
            rosettes: rosettes, leaves: leaves, buds: buds, primaryTips: primaryTips,
            trunkBaseWidth: width[0], leafSize: leafSize, crownCentroid: centroid,
            height: maxY, minX: minX, maxX: maxX
        )
    }

    /// Where planned rosettes and buds already hang.
    private func placedAnchors(_ plans: [Plan]) -> [TreePoint] {
        var anchors: [TreePoint] = []
        for (tip, occupants) in occupancy where !occupants.isEmpty {
            if let index = tipIndex[tip] {
                anchors.append(tips[index].position)
            }
        }
        for node in lateralTaken {
            anchors.append(position[node])
        }
        return anchors
    }

    /// A place for a satellite rosette: the nearest free twig end, or point along a twig, with room around it
    /// (2.5 leaf sizes clear of everything placed), so a species' copies stay near its own twig while the crown
    /// fills evenly instead of crowding the twig ends; failing that, the roomiest free place; failing that, the
    /// twig end with the fewest sharers.
    private mutating func nearestFreePlace(to point: TreePoint, awayFrom taken: [TreePoint]) -> Place {
        let room = leafSize * 2.5
        let laterals = lateralNodes()
        var best: (place: Place, score: Double)?
        func consider(_ place: Place, at p: TreePoint, bonus: Double) {
            var clear = room
            for anchor in taken {
                clear = min(clear, anchor.distance(to: p))
            }
            let score = clear + bonus - 0.1 * p.distance(to: point)
            if best.map({ score > $0.score }) ?? true {
                best = (place, score)
            }
        }
        for tip in tips where occupancy[tip.id] == nil {
            consider(.tip(tip.id), at: tip.position, bonus: leafSize * 0.25)
        }
        for node in laterals where !lateralTaken.contains(node) {
            consider(.lateral(node), at: position[node], bonus: 0)
        }
        if let best {
            return best.place
        }
        let shared = tips.min { a, b in
            let ca = occupancy[a.id]?.count ?? 0, cb = occupancy[b.id]?.count ?? 0
            return ca != cb ? ca < cb : a.position.distance(to: point) < b.position.distance(to: point)
        }
        return .tip(shared?.id ?? 0)
    }

    /// Grown nodes along twigs (depth 3 and finer) that are clear of every twig end and of each other.
    private mutating func lateralNodes() -> [Int] {
        if let lateralCandidates {
            return lateralCandidates
        }
        let spacing = leafSize * 0.85
        var chosen: [Int] = []
        var taken = tips.map(\.position)
        let fronts = Set(front.values)
        for j in mature.nodes.indices where emergence[j] >= 0.999 && !fronts.contains(j) {
            let chain = mature.chains[mature.nodes[j].chain]
            guard chain.depth >= 3, shell(of: position[j]) > 0.35 else { continue }
            let p = position[j]
            if taken.allSatisfy({ $0.distance(to: p) >= spacing }) {
                chosen.append(j)
                taken.append(p)
            }
        }
        lateralCandidates = chosen
        return chosen
    }

    /// Anchor, opening direction, tip and share rank of a planned rosette.
    private func locate(_ place: Place, occupant: Int) -> (TreePoint, TreePoint, Int?, Int) {
        switch place {
        case .tip(let tip):
            let rank = occupancy[tip]?.firstIndex { if case .rosette(occupant) = $0 { true } else { false } } ?? 0
            let (anchor, direction) = point(onTip: tip, rank: rank, salt: "rosette.\(occupant)")
            return (anchor, direction, tip, rank)
        case .lateral(let node):
            let p = position[node]
            let outward = (p - crownCentre).normalized()
            return (p, outward, nil, 0)
        }
    }

    /// The twig end itself for rank 0; for later sharers, 8–12 pt further back along the twig each (spec §4.5),
    /// opening alternately to either side.
    private func point(onTip chain: Int, rank: Int, salt: String) -> (TreePoint, TreePoint) {
        guard let index = tipIndex[chain], let frontNode = front[chain] else {
            return (crownCentre, .up)
        }
        let tip = tips[index]
        guard rank > 0 else { return (tip.position, tip.direction) }
        var rng = SplitMix64(seed: SplitMix64.derive(seed, salt))
        var remaining = 0.0
        for _ in 0..<rank {
            remaining += rng.range(8, 12)
        }
        // Walk back from the front toward the trunk.
        var path: [TreePoint] = []
        var node = frontNode
        while node >= 0, path.count < 64 {
            path.append(position[node])
            node = mature.nodes[node].parent
        }
        var point = path.last ?? tip.position
        var heading = tip.direction
        for k in 1..<max(2, path.count) where k < path.count {
            let a = path[k - 1], b = path[k]
            let d = a.distance(to: b)
            if d >= remaining {
                point = TreePoint.lerp(a, b, d > 0 ? remaining / d : 0)
                heading = (a - b).normalized(or: tip.direction)
                remaining = 0
                break
            }
            remaining -= d
        }
        let side = rank % 2 == 1 ? 1.0 : -1.0
        let normal = TreePoint(x: heading.y * side, y: -heading.x * side)
        return (point, (heading * 0.4 + normal + TreePoint.up * 0.3).normalized())
    }

    /// The leaves of one rosette: a fan opening up and out from the twig, stalks meeting at the anchor,
    /// never pointing down (nothing on the tree droops).
    private func fan(plan: Plan, anchor: TreePoint, direction: TreePoint, inner: Bool, rosette: Int) -> [TreeSkeleton.Leaf] {
        let count = plan.leafCount
        guard count > 0 else { return [] }
        let kindSalt = switch plan.kind {
        case .primary: "p"
        case .satellite: "s\(plan.ordinal)"
        case .featured: "f"
        }
        var rng = SplitMix64(seed: SplitMix64.derive(seed, "leaves.\(plan.speciesID).\(kindSalt)"))
        let outward = (anchor - crownCentre).normalized()
        let open = (direction * 0.45 + outward * 0.45 + TreePoint.up * 0.5).normalized()
        let limit = 80 * Double.pi / 180
        let centre = min(max(open.angleFromUp + rng.range(-0.12, 0.12), -limit), limit)
        let spread = min(140, 34 + 19 * Double(count - 1)) * .pi / 180
        var result: [(TreeSkeleton.Leaf, Double)] = []
        for k in 0..<count {
            var angle = centre - spread / 2 + spread * (Double(k) + 0.5) / Double(count) + rng.range(-0.16, 0.16)
            angle = min(max(angle, -2.0), 2.0)
            let size = leafSize * rng.range(0.85, 1.15)
            let offset = TreePoint.direction(angleFromUp: angle) * (size * 0.05)
                + TreePoint(x: rng.range(-0.8, 0.8), y: rng.range(-0.8, 0.8))
            let leaf = TreeSkeleton.Leaf(
                speciesID: plan.speciesID, anchor: anchor + offset, rotation: angle, size: size,
                rosette: rosette, isInner: inner
            )
            result.append((leaf, abs(angle - centre)))
        }
        // The outermost leaves first, so the central leaf lies on top.
        return result.sorted { $0.1 > $1.1 }.map(\.0)
    }
}
