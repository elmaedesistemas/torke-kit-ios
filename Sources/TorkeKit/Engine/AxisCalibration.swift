import Foundation

/// Turns the phone's readings into the vehicle's forward acceleration, however the phone
/// sits in its mount.
///
/// It keeps the horizontal part (perpendicular to gravity) and takes as "forward" the
/// direction of the first strong acceleration: the launch.
public enum AxisCalibration {
    static let strongAccel = 1.5
    static let learnWindow = 0.5

    /// Forward acceleration for every sample. All zeros if there is no launch to learn from.
    public static func forwardAccel(_ raw: [RawMotionSample]) -> [MotionSample] {
        let horizontal = raw.map { ($0.t, horizontalPart($0)) }
        guard let forward = forwardAxis(horizontal) else {
            return raw.map { MotionSample(t: $0.t, accel: 0) }
        }
        return horizontal.map { MotionSample(t: $0.0, accel: dot($0.1, forward)) }
    }

    /// Horizontal acceleration in any direction (m/s²): detects movement before
    /// "forward" is known.
    public static func horizontalMagnitude(_ s: RawMotionSample) -> Double {
        length(horizontalPart(s))
    }

    static func horizontalPart(_ s: RawMotionSample) -> SIMD3<Double> {
        let g = normalized(s.gravity)
        return s.user - dot(s.user, g) * g
    }

    static func forwardAxis(_ horizontal: [(TimeInterval, SIMD3<Double>)]) -> SIMD3<Double>? {
        guard let start = horizontal.first(where: { length($0.1) > strongAccel })?.0 else { return nil }
        let window = horizontal.filter { $0.0 >= start && $0.0 < start + learnWindow && length($0.1) > strongAccel * 0.5 }
        let sum = window.reduce(SIMD3<Double>(repeating: 0)) { $0 + $1.1 }
        return length(sum) > 0 ? normalized(sum) : nil
    }

    static func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double { (a * b).sum() }
    static func length(_ a: SIMD3<Double>) -> Double { dot(a, a).squareRoot() }
    static func normalized(_ a: SIMD3<Double>) -> SIMD3<Double> { let l = length(a); return l > 0 ? a / l : a }
}
