import Foundation

extension LeafProgress {
    /// Home's next-leaf row while a session runs (F1 design §4.3): an hours leaf with the session's provisional seconds
    /// added to its counter, as the dial reads display credit, so the two agree. Only a checkpoint unlocks a leaf,
    /// so the row stops one second short of the threshold ("1m to go", never "0m"). Other categories, a reached
    /// threshold and no session are returned unchanged.
    public func displaying(provisionalSeconds seconds: Int) -> LeafProgress {
        guard category == .hoursSaved, seconds > 0, state == .locked, current < threshold else { return self }
        let shown = min(current + Double(seconds) / 3600, threshold - 1.0 / 3600)
        guard shown > current else { return self }
        return LeafProgress(
            speciesID: speciesID, category: category, threshold: threshold, tier: tier, current: shown,
            availability: availability, state: state, estimatedDays: estimatedDays, floor: floor
        )
    }
}
