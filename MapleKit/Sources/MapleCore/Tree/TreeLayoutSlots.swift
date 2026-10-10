import Foundation

/// Where leaves can hang, and the permanent order species take them in (spec §4.5).
///
/// Spec §4.2 makes every segment endpoint a tip once its segment is half grown. A twig's *end* is the front of its
/// chain, which moves out along the chain as the twig lengthens; a node partway along a limb stays where it is.
/// Both are slots. Twig ends alone all sit on the rim of the young crown (each one is the outermost point of its
/// limb), which left the middle of the crown bare; the nodes along the limbs inside the crown are what fill it.
///
/// Slots are ordered once per seed. Each next slot is the free one farthest from those already taken, both at the
/// growth the k-th species typically arrives at and on the mature tree, so every prefix of the order spreads over
/// the whole dome at every stage. Species take slots in unlock order, so a species' slot never changes.
extension MatureTree {
    /// A place a rosette can hang.
    struct Slot: Sendable {
        /// The slot id: the chain's id for a twig end; `chains.count` and up for nodes along limbs.
        var id: Int
        var chain: Int
        /// The fixed node for a slot along a limb; nil for a twig end (the chain's front).
        var node: Int?
        /// Threshold of g after which the slot exists (−1: from the start).
        var appears: Double
    }

    /// Nodes along a limb sit at least this far apart, mature points.
    static let nodeSlotSpacing = 15.0
    /// Nodes along limbs are slots only inside this much of the crown dome (1 = its outline).
    static let nodeSlotReach = 0.96
    /// The order is built greedily this far; later slots (never needed as primaries) follow by appearance.
    static let orderedSlots = 200

    /// Every slot: the twig end of each chain but the trunk, then the nodes along limbs inside the crown that
    /// never become a twig's front (all nodes of one depth along a chain grow together, so only the last of
    /// them is ever a front).
    static func findSlots(nodes: [Node], chains: [Chain], envelope: CrownEnvelope, forkNode: Int) -> [Slot] {
        var slots: [Slot] = [Slot(id: 0, chain: 0, node: nil, appears: .infinity)]
        for c in chains.indices.dropFirst() {
            slots.append(Slot(id: c, chain: c, node: nil, appears: chains[c].sprout))
        }
        let fork = nodes[forkNode].position
        var taken: [TreePoint] = []
        for (c, chain) in chains.enumerated() where chain.depth >= 2 {
            for (k, j) in chain.nodes.enumerated() {
                guard k + 1 < chain.nodes.count, nodes[chain.nodes[k + 1]].depth == nodes[j].depth else { continue }
                let p = nodes[j].position
                guard envelope.normalizedRadius(p) <= nodeSlotReach, p.distance(to: fork) > 24 else { continue }
                guard taken.allSatisfy({ $0.distance(to: p) >= nodeSlotSpacing }) else { continue }
                taken.append(p)
                slots.append(Slot(id: slots.count, chain: c, node: j, appears: nodes[j].threshold))
            }
        }
        // Ids must index the array: twig ends first (id == chain), then the nodes in order.
        assert(slots.indices.allSatisfy { slots[$0].id == $0 })
        return slots
    }

    /// Structural growth at which a committed member typically holds `species` leaves: the every-feature pacing
    /// of docs/design/rewards.md ("Pacing"), as tended days, through `TreeGrowth`'s curve.
    static func typicalGrowth(species: Int) -> Double {
        let pacing: [(species: Double, days: Double)] = [(1, 0), (4, 1), (11, 7), (32, 30), (89, 180), (124, 365), (155, 639)]
        let n = Double(species)
        var days = pacing[pacing.count - 1].days
        for k in 1..<pacing.count where n <= pacing[k].species {
            let a = pacing[k - 1], b = pacing[k]
            days = a.days + (b.days - a.days) * max(0, n - a.species) / (b.species - a.species)
            break
        }
        return min(1, pow(max(0, days) / TreeGrowth.maturityDays, 0.6))
    }

    /// Every node's position at growth g (tree space): the mature offsets, revealed by emergence and scaled to
    /// the size spec §4.3 asks for.
    func positions(at g: Double) -> [TreePoint] {
        let kx = Self.sample(scaleX, at: g), ky = Self.sample(scaleY, at: g)
        var position = [TreePoint](repeating: .zero, count: nodes.count)
        for j in nodes.indices where nodes[j].parent >= 0 {
            let parent = nodes[j].parent
            let v = nodes[j].position - nodes[parent].position
            position[j] = position[parent] + TreePoint(x: v.x * kx, y: v.y * ky) * emergence(j, at: g)
        }
        return position
    }

    /// The node a chain's twig end is at, at growth g: its last node at least half grown, or nil before it sprouts.
    func front(of chain: Int, at g: Double) -> Int? {
        chains[chain].nodes.last { emergence($0, at: g) >= 0.5 }
    }

    /// Whether the slot is a tip at growth g.
    func exists(_ slot: Slot, at g: Double) -> Bool {
        if let node = slot.node {
            return emergence(node, at: g) >= 0.5
        }
        return emergence(chains[slot.chain].nodes[0], at: g) >= 0.5
    }

    /// Where a slot's leaves hang at growth g; before it exists, where its twig is so far.
    func position(of slot: Slot, in positions: [TreePoint], at g: Double) -> TreePoint {
        if let node = slot.node, emergence(node, at: g) >= 0.5 {
            return positions[node]
        }
        var chain = slot.chain
        while chain > 0 {
            if let node = front(of: chain, at: g) {
                return positions[node]
            }
            chain = chains[chain].parentChain
        }
        return positions[forkNode]
    }

    /// The permanent order species take slots in (spec §4.5: in unlock order, from the crown outward,
    /// alternating left and right). The first is the twig end nearest the young crown's top centre; each next
    /// one is the free slot farthest from those taken, measured in leaf sizes both at the growth its species
    /// typically arrives at and on the mature tree, with a small preference for the other side of the crown.
    func orderedSlotIDs() -> [Int] {
        func slotPositions(at g: Double) -> [TreePoint] {
            let nodes = positions(at: g)
            return slots.map { position(of: $0, in: nodes, at: g) }
        }
        let mature = slotPositions(at: 1)
        let matureLeaf = Self.leafSize(at: 1)
        var chosen: [Int] = []
        var remaining = Array(slots.indices.dropFirst())
        // Nearest distance (in leaf sizes) from each remaining slot to the chosen ones, now and when mature.
        var nearNow = [Double](repeating: .infinity, count: slots.count)
        var nearMature = [Double](repeating: .infinity, count: slots.count)
        var bucket = -1
        var current: [TreePoint] = []
        var currentG = 0.0
        var lastSide = 0.0

        while chosen.count < min(Self.orderedSlots, slots.count - 1), !remaining.isEmpty {
            // The growth this species typically arrives at, or later if no slot exists yet by then.
            var g = Self.typicalGrowth(species: chosen.count + 1)
            if !remaining.contains(where: { exists(slots[$0], at: g) }) {
                let first = remaining.map { slots[$0].appears }.min() ?? 1
                g = min(1, max(g, first + Self.emergenceWindow * 0.5 + 0.005))
            }
            // Positions move slowly with g: re-measure in steps of 0.025.
            let key = Int((g * 40).rounded(.up))
            if key != bucket {
                bucket = key
                currentG = min(1, Double(key) / 40)
                current = slotPositions(at: currentG)
                let leaf = Self.leafSize(at: currentG)
                for s in remaining {
                    nearNow[s] = chosen.reduce(Double.infinity) { min($0, current[s].distance(to: current[$1]) / leaf) }
                }
            }
            let available = remaining.filter { exists(slots[$0], at: currentG) }
            let pool = available.isEmpty ? remaining : available
            let centreX = pool.reduce(0) { $0 + current[$1].x } / Double(max(1, pool.count))
            let top = pool.map { current[$0].y }.max() ?? 0
            var best: (slot: Int, score: Double)?
            for s in pool {
                let p = current[s]
                let score: Double
                if chosen.isEmpty {
                    // From the crown: the twig end nearest the top centre of the young crown.
                    score = slots[s].node == nil ? -p.distance(to: TreePoint(x: centreX, y: top)) : -.infinity
                } else {
                    let side = p.x < centreX ? -1.0 : 1.0
                    score = min(nearNow[s], nearMature[s]) * (side != lastSide ? 1.08 : 1)
                }
                if best.map({ score > $0.score + 1e-9 }) ?? true {
                    best = (s, score)
                }
            }
            guard let pick = best?.slot else { break }
            chosen.append(pick)
            remaining.removeAll { $0 == pick }
            lastSide = current[pick].x < centreX ? -1 : 1
            let leaf = Self.leafSize(at: currentG)
            for s in remaining {
                nearNow[s] = min(nearNow[s], current[s].distance(to: current[pick]) / leaf)
                nearMature[s] = min(nearMature[s], mature[s].distance(to: mature[pick]) / matureLeaf)
            }
        }
        // The rest by when they appear.
        let rest = remaining.sorted { a, b in
            slots[a].appears != slots[b].appears ? slots[a].appears < slots[b].appears : a < b
        }
        return chosen + rest
    }
}
