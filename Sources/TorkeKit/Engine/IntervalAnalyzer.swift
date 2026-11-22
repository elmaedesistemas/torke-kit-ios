import Foundation

/// A speed interval measured without a standstill: a rolling start (60–130 km/h) or a
/// braking (100–0 km/h).
public struct IntervalResult: Sendable, Codable, Equatable {
    public enum Kind: String, Sendable, Codable { case rolling, braking }

    public var kind: Kind
    public var fromKmh: Double
    public var toKmh: Double
    /// Seconds from `fromKmh` to `toKmh`.
    public var time: TimeInterval
    /// Meters covered from `fromKmh` to `toKmh`.
    public var distance: Double
    /// Highest acceleration (rolling) or deceleration (braking) in the interval, in g.
    public var peakG: Double
    /// When the interval started, on the samples' clock.
    public var startTime: TimeInterval

    public init(kind: Kind, fromKmh: Double, toKmh: Double, time: TimeInterval, distance: Double, peakG: Double, startTime: TimeInterval) {
        self.kind = kind
        self.fromKmh = fromKmh
        self.toKmh = toKmh
        self.time = time
        self.distance = distance
        self.peakG = peakG
        self.startTime = startTime
    }
}

/// Measures speed intervals while the car is already moving.
///
/// The speed comes from the same filter as ``RunAnalyzer``, started at the first GPS speed.
/// "Forward" is learned from the strongest push and its sign is checked against the GPS, so
/// a braking (where the first strong push is backwards) works too.
public enum IntervalAnalyzer {
    /// 60–130 km/h, a common rolling test.
    public static func rolling(motion raw: [RawMotionSample], gps: [GPSSample], fromKmh: Double = 60, toKmh: Double = 130) -> IntervalResult? {
        guard toKmh > fromKmh, let trace = trace(raw: raw, gps: gps) else { return nil }
        guard let a = crossing(trace.points, kmh: fromKmh, rising: true, from: 0),
              let b = crossing(trace.points, kmh: toKmh, rising: true, from: a.index) else { return nil }
        return result(.rolling, trace, a, b, fromKmh, toKmh, sign: 1)
    }

    /// 100–0 km/h braking. The car must come to a stop.
    public static func braking(motion raw: [RawMotionSample], gps: [GPSSample], fromKmh: Double = 100) -> IntervalResult? {
        guard let trace = trace(raw: raw, gps: gps) else { return nil }
        guard let a = crossing(trace.points, kmh: fromKmh, rising: false, from: 0),
              let b = crossing(trace.points, kmh: 1.8, rising: false, from: a.index) else { return nil }
        return result(.braking, trace, a, b, fromKmh, 0, sign: -1)
    }

    // MARK: - Trace

    struct Point { var t: TimeInterval; var speed: Double; var distance: Double; var accel: Double }
    struct Trace { var points: [Point] }

    static func trace(raw: [RawMotionSample], gps: [GPSSample]) -> Trace? {
        let gps = gps.filter(\.hasSpeed).sorted { $0.t < $1.t }
        guard let first = gps.first else { return nil }
        let motion = AxisCalibration.forwardAccel(raw, orientedBy: gps).filter { $0.t >= first.t }
        guard motion.count > 10 else { return nil }

        var filter = SpeedFilter(speed: first.speed, bias: 0)
        var queue = gps.dropFirst()
        var points: [Point] = []
        var distance = 0.0, smooth = 0.0
        var lastT = motion[0].t, lastSpeed = first.speed
        for sample in motion {
            filter.predict(sample)
            while let next = queue.first, next.t <= sample.t {
                filter.correct(next)
                queue = queue.dropFirst()
            }
            let dt = sample.t - lastT
            let speed = max(filter.speed, 0)
            distance += (speed + lastSpeed) / 2 * dt
            if dt > 0, dt < 0.5 { smooth += (sample.accel - filter.bias - smooth) * min(1, dt / 0.1) }
            points.append(Point(t: sample.t, speed: speed, distance: distance, accel: smooth))
            lastT = sample.t
            lastSpeed = speed
        }
        return Trace(points: points)
    }

    struct Crossing { var index: Int; var t: TimeInterval; var distance: Double }

    static func crossing(_ points: [Point], kmh: Double, rising: Bool, from start: Int) -> Crossing? {
        let v = kmh / 3.6
        guard points.count > start + 1 else { return nil }
        for i in (start + 1)..<points.count {
            let a = points[i - 1], b = points[i]
            let crossed = rising ? (a.speed < v && b.speed >= v) : (a.speed > v && b.speed <= v)
            if crossed {
                let f = b.speed == a.speed ? 0 : (v - a.speed) / (b.speed - a.speed)
                return Crossing(index: i, t: a.t + (b.t - a.t) * f, distance: a.distance + (b.distance - a.distance) * f)
            }
        }
        return nil
    }

    static func result(_ kind: IntervalResult.Kind, _ trace: Trace, _ a: Crossing, _ b: Crossing, _ from: Double, _ to: Double, sign: Double) -> IntervalResult {
        let peak = trace.points[a.index...b.index].map { $0.accel * sign }.max() ?? 0
        return IntervalResult(
            kind: kind, fromKmh: from, toKmh: to, time: b.t - a.t, distance: b.distance - a.distance,
            peakG: peak / DragDistance.g, startTime: a.t
        )
    }
}
