import CoreGraphics
import Foundation

/// A small drawing of one leaf's skeleton for the Live Activity (F1 design §5.11): its outlines, veins and stalk as
/// x, y byte pairs in a 0...255 square. The widget draws the real species from it without linking the leaf
/// generator, and the whole sketch stays a few hundred bytes of the activity's 4 KB.
public struct LeafSketch: Codable, Hashable, Sendable {
    /// At most this many outline points in all, so every species fits: compound leaves are thinned evenly.
    public static let maximumOutlinePoints = 240
    /// The fewest points a thinned outline keeps.
    static let minimumOutlinePoints = 8

    /// Each blade's closed outline.
    public var outlines: [Data]
    /// Each vein, as an open line.
    public var veins: [Data]
    /// The stalk, as an open line.
    public var stalk: Data

    /// - Parameters:
    ///   - outlines: Each blade's closed outline, in the leaf's own coordinates.
    ///   - veins: Each vein as a line of points, in the same coordinates.
    ///   - stalk: The stalk as a line of points.
    ///   - frame: The square the leaf is framed in (the catalogue's fitted square), mapped onto 0...255.
    public init(outlines: [[CGPoint]], veins: [[CGPoint]], stalk: [CGPoint], frame: CGRect) {
        let quantised = outlines.map { Self.deduplicated(Self.bytes($0, in: frame)) }
        self.outlines = Self.thinned(quantised).map(Self.data)
        self.veins = veins.map { Self.data(Self.bytes($0, in: frame)) }
        self.stalk = Self.data(Self.bytes(stalk, in: frame))
    }

    /// How many outline points the sketch keeps, across every blade.
    public var outlinePointCount: Int {
        outlines.reduce(0) { $0 + $1.count / 2 }
    }

    /// Each blade's outline in `rect`, ready for `Path.addLines` and `closeSubpath`.
    public func outlines(in rect: CGRect) -> [[CGPoint]] {
        outlines.map { Self.points($0, in: rect) }
    }

    /// Each vein as a line in `rect`.
    public func veins(in rect: CGRect) -> [[CGPoint]] {
        veins.map { Self.points($0, in: rect) }
    }

    /// The stalk as a line in `rect`.
    public func stalk(in rect: CGRect) -> [CGPoint] {
        Self.points(stalk, in: rect)
    }

    // MARK: Encoding

    private struct BytePoint: Hashable {
        var x: UInt8
        var y: UInt8
    }

    private static func bytes(_ points: [CGPoint], in frame: CGRect) -> [BytePoint] {
        guard frame.width > 0, frame.height > 0 else { return [] }
        return points.map { point in
            BytePoint(x: byte((point.x - frame.minX) / frame.width), y: byte((point.y - frame.minY) / frame.height))
        }
    }

    private static func byte(_ fraction: CGFloat) -> UInt8 {
        guard fraction.isFinite else { return 0 }
        return UInt8((min(max(fraction, 0), 1) * 255).rounded())
    }

    /// Drops points that land on the same byte pair as the one before.
    private static func deduplicated(_ points: [BytePoint]) -> [BytePoint] {
        var kept: [BytePoint] = []
        for point in points where point != kept.last {
            kept.append(point)
        }
        return kept
    }

    /// Thins every outline evenly so the total fits `maximumOutlinePoints`, keeping at least
    /// `minimumOutlinePoints` of each.
    private static func thinned(_ outlines: [[BytePoint]]) -> [[BytePoint]] {
        let total = outlines.reduce(0) { $0 + $1.count }
        guard total > maximumOutlinePoints else { return outlines }
        let floor = minimumOutlinePoints * outlines.count
        let spare = max(0, maximumOutlinePoints - floor)
        let extra = max(1, total - floor)
        return outlines.map { points in
            guard points.count > minimumOutlinePoints else { return points }
            let keep = min(points.count, minimumOutlinePoints + (points.count - minimumOutlinePoints) * spare / extra)
            return (0..<keep).map { points[$0 * points.count / keep] }
        }
    }

    private static func data(_ points: [BytePoint]) -> Data {
        Data(points.flatMap { [$0.x, $0.y] })
    }

    private static func points(_ data: Data, in rect: CGRect) -> [CGPoint] {
        let bytes = [UInt8](data)
        return stride(from: 0, to: bytes.count - 1, by: 2).map { index in
            CGPoint(x: rect.minX + CGFloat(bytes[index]) / 255 * rect.width,
                    y: rect.minY + CGFloat(bytes[index + 1]) / 255 * rect.height)
        }
    }
}
