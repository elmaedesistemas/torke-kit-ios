import Foundation

/// How much a run can be trusted: the GPS, the strip's slope and the mount.
///
/// It reads the raw samples, so it works on any ``TorkeRun``. A run graded ``Grade/poor``
/// should not go on a leaderboard; ``Grade/fair`` is fine for practice.
public struct RunQuality: Sendable, Equatable, Codable {
    public enum Grade: String, Sendable, Codable, Comparable {
        case good, fair, poor
        public static func < (a: Grade, b: Grade) -> Bool { a.rank < b.rank }
        private var rank: Int { self == .good ? 0 : self == .fair ? 1 : 2 }
    }

    public enum Issue: String, Sendable, Codable, CaseIterable {
        /// The GPS gave fewer fixes than one per second.
        case slowGPS
        /// The GPS speed accuracy was poor (open sky helps).
        case inaccurateGPS
        /// The GPS went silent for a while during the run.
        case gpsDropout
        /// The strip goes up or down more than the limit.
        case slope
        /// The accelerometer ended with a large bias: the mount is loose or tilted a lot.
        case looseMount
        /// The phone changed its angle during the run.
        case phoneMoved
        /// The accelerometer and the GPS tell different speeds.
        case sensorsDisagree
    }

    /// Limits for each issue.
    public struct Limits: Sendable, Equatable, Codable {
        public var minGpsRate = 0.8
        public var maxSpeedAccuracy = 1.0
        public var maxGpsGap = 2.5
        /// Rise over run: 0.01 is 1 %.
        public var maxSlope = 0.01
        public var maxBias = 0.5
        public var maxTiltChange = 8.0
        public var maxDisagreement = 1.5
        public init() {}
    }

    public var grade: Grade
    public var issues: [Issue]
    /// GPS fixes per second during the run.
    public var gpsRate: Double
    /// Median GPS speed accuracy, m/s.
    public var speedAccuracy: Double?
    /// Longest stretch without a GPS fix, seconds.
    public var longestGpsGap: Double
    /// Slope of the strip, rise over run (positive is uphill). Nil without altitudes.
    public var slope: Double?
    /// How much the phone's angle changed, degrees.
    public var tiltChange: Double?
    /// RMS difference between the filtered speed and the GPS speed, m/s.
    public var disagreement: Double?

    /// Grades a run. Nil when it has no standing-start result to grade. A stored result
    /// without its trace is computed again from the samples.
    public static func assess(_ run: TorkeRun, limits: Limits = Limits()) -> RunQuality? {
        let stored = run.result.flatMap { $0.trace.isEmpty ? nil : $0 }
        guard let result = stored ?? run.analyze(), let end = result.trace.last else { return nil }
        let start = result.launchTime, finish = start + end.t
        let fixes = run.gps.filter { $0.hasSpeed && $0.t >= start && $0.t <= finish }.sorted { $0.t < $1.t }

        let duration = max(end.t, 0.001)
        let rate = Double(fixes.count) / duration
        let accuracy = median(fixes.map(\.speedAccuracy))
        let times = [start] + fixes.map(\.t) + [finish]
        let gap = zip(times, times.dropFirst()).map { $1 - $0 }.max() ?? duration

        // Slope: least squares of altitude against distance
        let withAltitude = fixes.compactMap { fix -> (Double, Double)? in
            guard let altitude = fix.altitude, let d = distance(at: fix.t - start, in: result.trace) else { return nil }
            return (d, altitude)
        }
        var slope: Double?
        if withAltitude.count >= 3, let span = withAltitude.map(\.0).max(), span > 50 {
            let n = Double(withAltitude.count)
            let mx = withAltitude.map(\.0).reduce(0, +) / n, my = withAltitude.map(\.1).reduce(0, +) / n
            let sxx = withAltitude.reduce(0) { $0 + ($1.0 - mx) * ($1.0 - mx) }
            let sxy = withAltitude.reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
            if sxx > 0 { slope = sxy / sxx }
        }

        // Tilt: gravity direction over the first and last half second
        let inRun = run.motion.filter { $0.t >= start && $0.t <= finish }
        var tilt: Double?
        if let first = inRun.first?.t, let last = inRun.last?.t, last - first > 1.5 {
            let a = meanDirection(inRun.filter { $0.t < first + 0.5 })
            let b = meanDirection(inRun.filter { $0.t > last - 0.5 })
            let cosine = min(1, max(-1, (a * b).sum()))
            tilt = acos(cosine) * 180 / .pi
        }

        // Sensors against GPS
        let residuals = fixes.compactMap { fix in speed(at: fix.t - start, in: result.trace).map { $0 - fix.speed } }
        let disagreement = residuals.isEmpty ? nil : (residuals.map { $0 * $0 }.reduce(0, +) / Double(residuals.count)).squareRoot()

        var issues: [Issue] = []
        if rate < limits.minGpsRate { issues.append(.slowGPS) }
        if let accuracy, accuracy > limits.maxSpeedAccuracy { issues.append(.inaccurateGPS) }
        if gap > limits.maxGpsGap { issues.append(.gpsDropout) }
        if let slope, abs(slope) > limits.maxSlope { issues.append(.slope) }
        if abs(result.accelBias) > limits.maxBias { issues.append(.looseMount) }
        if let tilt, tilt > limits.maxTiltChange { issues.append(.phoneMoved) }
        if let disagreement, disagreement > limits.maxDisagreement { issues.append(.sensorsDisagree) }

        let serious: Set<Issue> = [.gpsDropout, .phoneMoved, .sensorsDisagree]
        let grade: Grade = issues.contains(where: serious.contains) || issues.count >= 3 ? .poor : issues.isEmpty ? .good : .fair
        return RunQuality(
            grade: grade, issues: issues, gpsRate: rate, speedAccuracy: accuracy, longestGpsGap: gap,
            slope: slope, tiltChange: tilt, disagreement: disagreement
        )
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    static func meanDirection(_ samples: [RawMotionSample]) -> SIMD3<Double> {
        let sum = samples.reduce(SIMD3<Double>(repeating: 0)) { $0 + AxisCalibration.normalized($1.gravity) }
        return AxisCalibration.normalized(sum)
    }

    static func distance(at t: TimeInterval, in trace: [TracePoint]) -> Double? { interpolate(t, trace, \.distance) }
    static func speed(at t: TimeInterval, in trace: [TracePoint]) -> Double? { interpolate(t, trace, \.speed) }

    static func interpolate(_ t: TimeInterval, _ trace: [TracePoint], _ key: KeyPath<TracePoint, Double>) -> Double? {
        guard let i = trace.firstIndex(where: { $0.t >= t }) else { return nil }
        guard i > 0 else { return trace[0][keyPath: key] }
        let a = trace[i - 1], b = trace[i]
        let f = b.t == a.t ? 0 : (t - a.t) / (b.t - a.t)
        return a[keyPath: key] + (b[keyPath: key] - a[keyPath: key]) * f
    }
}
