import Foundation

/// A range with both ends included.
public struct ValueRange: Sendable, Codable, Equatable {
    public var min: Double
    public var max: Double

    public init(_ min: Double, _ max: Double) {
        self.min = Swift.min(min, max)
        self.max = Swift.max(min, max)
    }

    public func contains(_ v: Double) -> Bool { v >= min && v <= max }

    /// How far outside the range, as a share of its width (0 inside).
    public func miss(_ v: Double) -> Double {
        let width = Swift.max(max - min, 1)
        if v < min { return (min - v) / width }
        if v > max { return (v - max) / width }
        return 0
    }
}

/// Where you want the geometry to land. TorkeKit ships no values: they depend on the car,
/// the tires and the track, and each builder or racer brings their own.
public struct TargetWindow: Sendable, Codable, Equatable {
    public var icLength: ValueRange?
    public var icHeight: ValueRange?
    public var antiSquat: ValueRange?
    /// A miss up to this share of a range's width counts as "near".
    public var nearShare: Double

    public init(icLength: ValueRange? = nil, icHeight: ValueRange? = nil, antiSquat: ValueRange? = nil, nearShare: Double = 0.25) {
        self.icLength = icLength
        self.icHeight = icHeight
        self.antiSquat = antiSquat
        self.nearShare = nearShare
    }

    public enum Status: String, Sendable, Codable {
        case inside, near, below, above, unknown
    }

    public enum Metric: String, Sendable, Codable, CaseIterable {
        case icLength, icHeight, antiSquat
    }

    public func status(_ metric: Metric, of geometry: SuspensionGeometry) -> Status {
        let (range, value): (ValueRange?, Double?) = switch metric {
        case .icLength: (icLength, geometry.icLength)
        case .icHeight: (icHeight, geometry.icHeight)
        case .antiSquat: (antiSquat, geometry.antiSquat)
        }
        guard let range, let value else { return .unknown }
        if range.contains(value) { return .inside }
        if range.miss(value) <= nearShare { return .near }
        return value < range.min ? .below : .above
    }

    /// 0 when every set range is met; it grows with the misses. Nil when a needed value is missing.
    public func score(_ geometry: SuspensionGeometry) -> Double? {
        var total = 0.0
        for (range, value) in [(icLength, geometry.icLength), (icHeight, geometry.icHeight), (antiSquat, geometry.antiSquat)] {
            guard let range else { continue }
            guard let value else { return nil }
            total += range.miss(value)
        }
        return total
    }
}

/// The holes each 4-link bracket offers, to try every combination.
public struct FourLinkHoles: Sendable, Codable, Equatable {
    public var upperRear: [Point2]
    public var upperFront: [Point2]
    public var lowerRear: [Point2]
    public var lowerFront: [Point2]

    public init(upperRear: [Point2], upperFront: [Point2], lowerRear: [Point2], lowerFront: [Point2]) {
        self.upperRear = upperRear
        self.upperFront = upperFront
        self.lowerRear = lowerRear
        self.lowerFront = lowerFront
    }

    /// Every combination of holes, best first by the window's score. Combinations without an
    /// instant center forward of the axle are left out.
    public func ranked(base: SuspensionSetup, target: TargetWindow, limit: Int = 20) -> [HoleOption] {
        var out: [HoleOption] = []
        for (a, ur) in upperRear.enumerated() {
            for (b, uf) in upperFront.enumerated() {
                for (c, lr) in lowerRear.enumerated() {
                    for (d, lf) in lowerFront.enumerated() {
                        var setup = base
                        setup.kind = .fourLink
                        setup.points = ["upperRear": ur, "upperFront": uf, "lowerRear": lr, "lowerFront": lf]
                        let geometry = setup.geometry()
                        guard let score = target.score(geometry), (geometry.icLength ?? 0) > 0 else { continue }
                        out.append(HoleOption(holes: [a, b, c, d], setup: setup, geometry: geometry, score: score))
                    }
                }
            }
        }
        return Array(out.sorted { $0.score < $1.score }.prefix(limit))
    }
}

/// One combination of holes.
public struct HoleOption: Sendable, Equatable {
    /// Hole index on each bracket: upper rear, upper front, lower rear, lower front.
    public var holes: [Int]
    public var setup: SuspensionSetup
    public var geometry: SuspensionGeometry
    public var score: Double
}

/// What changed between two setups, to read next to the change in 60-foot time.
public struct SetupChange: Sendable, Equatable {
    public var icLength: Double?
    public var icHeight: Double?
    public var antiSquat: Double?
    /// Points that moved, with how much (after minus before).
    public var moved: [String: Point2]

    public init(from before: SuspensionSetup, to after: SuspensionSetup) {
        let a = before.converted(to: after.unit).geometry(), b = after.geometry()
        func delta(_ x: Double?, _ y: Double?) -> Double? { x.flatMap { x in y.map { $0 - x } } }
        icLength = delta(a.icLength, b.icLength)
        icHeight = delta(a.icHeight, b.icHeight)
        antiSquat = delta(a.antiSquat, b.antiSquat)
        let old = before.converted(to: after.unit).points
        var moved: [String: Point2] = [:]
        for (name, p) in after.points {
            guard let q = old[name] else { continue }
            let d = Point2(x: p.x - q.x, y: p.y - q.y)
            if abs(d.x) > 1e-9 || abs(d.y) > 1e-9 { moved[name] = d }
        }
        self.moved = moved
    }
}
