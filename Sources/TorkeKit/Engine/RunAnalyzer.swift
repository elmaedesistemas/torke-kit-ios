import Foundation

/// Computes the official times of a recorded run from all its samples.
public enum RunAnalyzer {
    /// Acceleration (m/s²) that marks the launch if held for `launchHold` seconds.
    static let launchAccel = 1.5
    static let launchHold = 0.15
    /// Below this the car is considered not moving yet.
    static let restAccel = 0.35
    static let restSpread = 0.3
    static let stillWindow = 1.0

    /// Analyzes a recorded run. Returns nil when there is no launch from a standstill.
    public static func analyze(motion: [MotionSample], gps: [GPSSample]) -> RunResult? {
        let motion = motion.sorted { $0.t < $1.t }
        guard let (launchIndex, bias) = findLaunch(motion) else { return nil }
        let launchTime = motion[launchIndex].t

        var filter = SpeedFilter(speed: 0, bias: bias)
        var gpsQueue = gps.filter { $0.t > launchTime && $0.hasSpeed }.sorted { $0.t < $1.t }[...]
        var trace = [TracePoint(t: 0, speed: 0, distance: 0)]
        var distance = 0.0
        var lastSpeed = 0.0
        var lastT = launchTime
        filter.predict(motion[launchIndex])

        for sample in motion[(launchIndex + 1)...] {
            filter.predict(sample)
            while let next = gpsQueue.first, next.t <= sample.t {
                filter.correct(next)
                gpsQueue = gpsQueue.dropFirst()
            }
            let speed = max(filter.speed, 0)
            distance += (speed + lastSpeed) / 2 * (sample.t - lastT)
            lastSpeed = speed
            lastT = sample.t
            trace.append(TracePoint(t: sample.t - launchTime, speed: speed, distance: distance))
            if distance > DragDistance.quarterMile + 20 { break }
        }

        let rolloutT = time(atDistance: DragDistance.rollout, in: trace)
        func elapsed(_ d: Double) -> TimeInterval? {
            guard let rolloutT, let t = time(atDistance: d, in: trace) else { return nil }
            return t - rolloutT
        }
        return RunResult(
            launchTime: launchTime,
            zeroTo100: time(atSpeed: DragDistance.speed100, in: trace),
            sixtyFeet: elapsed(DragDistance.sixtyFeet),
            eighthMile: elapsed(DragDistance.eighthMile),
            eighthMileKmh: speed(atDistance: DragDistance.eighthMile, in: trace).map { $0 * 3.6 },
            quarterMile: elapsed(DragDistance.quarterMile),
            quarterMileKmh: speed(atDistance: DragDistance.quarterMile, in: trace).map { $0 * 3.6 },
            topSpeedKmh: (trace.map(\.speed).max() ?? 0) * 3.6,
            accelBias: filter.bias,
            trace: trace
        )
    }

    /// Finds the launch: one second still, then sustained acceleration.
    /// Returns the index of the first movement and the bias measured at rest.
    static func findLaunch(_ motion: [MotionSample]) -> (Int, Double)? {
        guard motion.count > 10 else { return nil }
        // The rest window ends `rampGap` before the evaluated point, so the rise of the
        // acceleration at launch does not count as earlier movement.
        let rampGap = 0.3
        var lo = 0, hi = 0
        for i in motion.indices {
            let t = motion[i].t
            while lo < i, motion[lo].t < t - rampGap - stillWindow { lo += 1 }
            while hi < i, motion[hi].t < t - rampGap { hi += 1 }
            let still = motion[lo..<max(lo, hi)]
            guard let first = still.first, let last = still.last,
                  last.t - first.t >= stillWindow * 0.9 else { continue }
            let n = Double(still.count)
            let bias = still.map(\.accel).reduce(0, +) / n
            let spread = (still.map { ($0.accel - bias) * ($0.accel - bias) }.reduce(0, +) / n).squareRoot()
            // Still = little spread (an idling engine vibrates, but does not accelerate)
            guard spread < restSpread, motion[i].accel - bias > launchAccel else { continue }
            let moving = max(restAccel, 3 * spread)
            // Is it held?
            var j = i
            var held = true
            while j < motion.count, motion[j].t - t < launchHold {
                if motion[j].accel - bias < launchAccel * 0.6 { held = false; break }
                j += 1
            }
            guard held, j < motion.count else { continue }
            // Walk back to the first movement
            var start = i
            while start > 0, motion[start - 1].accel - bias > moving, motion[start - 1].t > last.t { start -= 1 }
            return (start, bias)
        }
        return nil
    }

    static func time(atDistance d: Double, in trace: [TracePoint]) -> TimeInterval? {
        crossing(trace, value: d, key: \.distance).map { lerp(trace[$0.0].t, trace[$0.1].t, $0.2) }
    }

    static func speed(atDistance d: Double, in trace: [TracePoint]) -> Double? {
        crossing(trace, value: d, key: \.distance).map { lerp(trace[$0.0].speed, trace[$0.1].speed, $0.2) }
    }

    static func time(atSpeed v: Double, in trace: [TracePoint]) -> TimeInterval? {
        crossing(trace, value: v, key: \.speed).map { lerp(trace[$0.0].t, trace[$0.1].t, $0.2) }
    }

    /// First pair of points where `key` crosses `value`, with the fraction between them.
    static func crossing(_ trace: [TracePoint], value: Double, key: KeyPath<TracePoint, Double>) -> (Int, Int, Double)? {
        guard trace.count > 1 else { return nil }
        for i in 1..<trace.count {
            let a = trace[i - 1][keyPath: key], b = trace[i][keyPath: key]
            if a < value, b >= value {
                return (i - 1, i, b == a ? 0 : (value - a) / (b - a))
            }
        }
        return nil
    }

    static func lerp(_ a: Double, _ b: Double, _ f: Double) -> Double { a + (b - a) * f }
}
