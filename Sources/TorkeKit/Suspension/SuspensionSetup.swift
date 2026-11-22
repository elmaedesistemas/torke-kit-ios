import Foundation

/// A point in the side view of the car: `x` forward of the rear axle centerline, `y` up from
/// the ground. Any length unit, as long as the whole setup uses the same one.
public struct Point2: Sendable, Codable, Equatable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum LengthUnit: String, Sendable, Codable {
    case inches, centimeters
}

/// The rear suspension of a car, as measured in the garage. The math works in whatever unit
/// the points use; `unit` only says which one it is.
///
/// Points by kind:
/// - ``Kind/fourLink``: `upperRear`, `upperFront`, `lowerRear`, `lowerFront`
///   (rear = bracket on the axle housing, front = bracket on the chassis).
/// - ``Kind/ladderBar``: `pivot`, the ladder bar's front mount on the chassis.
/// - ``Kind/torqueArm``: `armFront` (the torque arm's front mount) and the lower control
///   arms, `lowerRear` and `lowerFront`.
public struct SuspensionSetup: Sendable, Codable, Equatable {
    public enum Kind: String, Sendable, Codable {
        case fourLink, ladderBar, torqueArm
    }

    public var kind: Kind
    public var unit: LengthUnit
    /// Distance between the front and rear axle centerlines.
    public var wheelbase: Double
    /// Height of the center of gravity above the ground. Measure it, or use the crankshaft
    /// height plus a few inches as a starting point.
    public var cgHeight: Double
    public var points: [String: Point2]
    /// Free text, such as "upper bars on hole 3".
    public var notes: String?

    public init(kind: Kind, unit: LengthUnit = .inches, wheelbase: Double, cgHeight: Double, points: [String: Point2], notes: String? = nil) {
        self.kind = kind
        self.unit = unit
        self.wheelbase = wheelbase
        self.cgHeight = cgHeight
        self.points = points
        self.notes = notes
    }

    public static func fourLink(unit: LengthUnit = .inches, wheelbase: Double, cgHeight: Double,
                                upperRear: Point2, upperFront: Point2, lowerRear: Point2, lowerFront: Point2) -> SuspensionSetup {
        SuspensionSetup(kind: .fourLink, unit: unit, wheelbase: wheelbase, cgHeight: cgHeight,
                        points: ["upperRear": upperRear, "upperFront": upperFront, "lowerRear": lowerRear, "lowerFront": lowerFront])
    }

    public static func ladderBar(unit: LengthUnit = .inches, wheelbase: Double, cgHeight: Double, pivot: Point2) -> SuspensionSetup {
        SuspensionSetup(kind: .ladderBar, unit: unit, wheelbase: wheelbase, cgHeight: cgHeight, points: ["pivot": pivot])
    }

    public static func torqueArm(unit: LengthUnit = .inches, wheelbase: Double, cgHeight: Double,
                                 armFront: Point2, lowerRear: Point2, lowerFront: Point2) -> SuspensionSetup {
        SuspensionSetup(kind: .torqueArm, unit: unit, wheelbase: wheelbase, cgHeight: cgHeight,
                        points: ["armFront": armFront, "lowerRear": lowerRear, "lowerFront": lowerFront])
    }

    /// The same setup in another unit.
    public func converted(to target: LengthUnit) -> SuspensionSetup {
        guard target != unit else { return self }
        let k = target == .centimeters ? 2.54 : 1 / 2.54
        var out = self
        out.unit = target
        out.wheelbase *= k
        out.cgHeight *= k
        out.points = points.mapValues { Point2(x: $0.x * k, y: $0.y * k) }
        return out
    }

    /// The instant center, anti-squat and bar angles.
    public func geometry() -> SuspensionGeometry { SuspensionGeometry(self) }
}

/// One bar seen from the side.
public struct Bar: Sendable, Equatable {
    public var name: String
    public var rear: Point2
    public var front: Point2
    /// Degrees from horizontal; positive when the bar rises toward the front.
    public var angle: Double { atan2(front.y - rear.y, front.x - rear.x) * 180 / .pi }
    public var length: Double { hypot(front.x - rear.x, front.y - rear.y) }
}

/// What a suspension setup does under acceleration, from textbook side-view geometry.
///
/// The instant center (IC) is where the axle's links meet, seen from the side. The line from
/// the rear tire's contact patch through the IC sets how much the launch pushes the car up
/// (anti-squat): 100 % holds the rear level, more lifts it, less lets it squat.
///
/// `antiSquat = (icHeight / icLength) / (cgHeight / wheelbase) × 100`
public struct SuspensionGeometry: Sendable, Equatable {
    public enum Warning: String, Sendable, Codable {
        /// Required points are missing.
        case incomplete
        /// The links are parallel: the IC is at infinity.
        case parallelLinks
        /// The IC is at or behind the axle.
        case instantCenterBehindAxle
        /// The IC is below the ground.
        case instantCenterBelowGround
    }

    public var instantCenter: Point2?
    /// IC length: how far forward of the rear axle centerline.
    public var icLength: Double? { instantCenter?.x }
    /// IC height above the ground.
    public var icHeight: Double? { instantCenter?.y }
    /// Percent.
    public var antiSquat: Double?
    public var bars: [Bar]
    public var warnings: [Warning]

    init(_ setup: SuspensionSetup) {
        let p = setup.points
        var ic: Point2?
        var bars: [Bar] = []
        var warnings: [Warning] = []

        switch setup.kind {
        case .fourLink:
            if let ur = p["upperRear"], let uf = p["upperFront"], let lr = p["lowerRear"], let lf = p["lowerFront"] {
                bars = [Bar(name: "upper", rear: ur, front: uf), Bar(name: "lower", rear: lr, front: lf)]
                ic = Self.intersect(ur, uf, lr, lf)
                if ic == nil { warnings.append(.parallelLinks) }
            } else { warnings.append(.incomplete) }
        case .ladderBar:
            if let pivot = p["pivot"] { ic = pivot } else { warnings.append(.incomplete) }
        case .torqueArm:
            // The arm's front mount only pushes up or down: its line of action is vertical.
            if let arm = p["armFront"], let lr = p["lowerRear"], let lf = p["lowerFront"] {
                bars = [Bar(name: "lower", rear: lr, front: lf)]
                ic = Self.intersect(lr, lf, arm, Point2(x: arm.x, y: arm.y + 1))
                if ic == nil { warnings.append(.parallelLinks) }
            } else { warnings.append(.incomplete) }
        }

        var antiSquat: Double?
        if let ic {
            if ic.x <= 0 { warnings.append(.instantCenterBehindAxle) }
            if ic.y < 0 { warnings.append(.instantCenterBelowGround) }
            if ic.x > 0, setup.cgHeight > 0, setup.wheelbase > 0 {
                antiSquat = (ic.y / ic.x) / (setup.cgHeight / setup.wheelbase) * 100
            }
        }
        self.instantCenter = ic
        self.antiSquat = antiSquat
        self.bars = bars
        self.warnings = warnings
    }

    /// Where the line through a1–a2 meets the line through b1–b2. Nil when parallel.
    static func intersect(_ a1: Point2, _ a2: Point2, _ b1: Point2, _ b2: Point2) -> Point2? {
        let d1 = Point2(x: a2.x - a1.x, y: a2.y - a1.y), d2 = Point2(x: b2.x - b1.x, y: b2.y - b1.y)
        let cross = d1.x * d2.y - d1.y * d2.x
        guard abs(cross) > 1e-9 else { return nil }
        let t = ((b1.x - a1.x) * d2.y - (b1.y - a1.y) * d2.x) / cross
        return Point2(x: a1.x + t * d1.x, y: a1.y + t * d1.y)
    }
}
