import Foundation

/// Two-state Kalman filter: speed and accelerometer bias.
///
/// The accelerometer predicts the speed at 100 Hz; the GPS (1 to 25 Hz) corrects it and,
/// over time, estimates the bias a slightly tilted mount leaves.
public struct SpeedFilter: Sendable {
    public private(set) var speed: Double
    public private(set) var bias: Double
    private var p00: Double, p01: Double, p11: Double
    private var lastT: TimeInterval?

    /// Accelerometer noise (m/s² / √s) and bias drift (m/s³ / √s).
    private let accelNoise: Double
    private let biasDrift: Double

    public init(speed: Double = 0, bias: Double = 0, accelNoise: Double = 0.35, biasDrift: Double = 0.02) {
        self.speed = speed
        self.bias = bias
        self.p00 = 0.01
        self.p01 = 0
        self.p11 = 0.05
        self.accelNoise = accelNoise
        self.biasDrift = biasDrift
    }

    /// Moves the filter forward with one accelerometer sample.
    public mutating func predict(_ sample: MotionSample) {
        defer { lastT = sample.t }
        guard let lastT else { return }
        let dt = sample.t - lastT
        guard dt > 0, dt < 0.5 else { return }
        speed += (sample.accel - bias) * dt
        // P = F P Fᵀ + Q, with F = [[1, -dt], [0, 1]]
        let n00 = p00 - 2 * dt * p01 + dt * dt * p11 + accelNoise * accelNoise * dt
        let n01 = p01 - dt * p11
        let n11 = p11 + biasDrift * biasDrift * dt
        p00 = n00; p01 = n01; p11 = n11
    }

    /// Corrects with a GPS speed.
    public mutating func correct(_ gps: GPSSample) {
        let r = max(gps.speedAccuracy, 0.15)
        let s = p00 + r * r
        let k0 = p00 / s
        let k1 = p01 / s
        let innovation = gps.speed - speed
        speed += k0 * innovation
        bias += k1 * innovation
        let n00 = (1 - k0) * p00
        let n01 = (1 - k0) * p01
        let n11 = p11 - k1 * p01
        p00 = n00; p01 = n01; p11 = n11
        speed = max(speed, 0)
    }

    /// Acceleration corrected for the bias.
    public func corrected(_ accel: Double) -> Double { accel - bias }
}
