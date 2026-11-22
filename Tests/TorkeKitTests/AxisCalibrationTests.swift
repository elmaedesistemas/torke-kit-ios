import XCTest
@testable import TorkeKit

final class AxisCalibrationTests: XCTestCase {

    /// Rotates a vector by Euler angles (radians).
    func rotate(_ v: SIMD3<Double>, yaw: Double, pitch: Double, roll: Double) -> SIMD3<Double> {
        var r = v
        r = SIMD3(r.x * cos(yaw) - r.y * sin(yaw), r.x * sin(yaw) + r.y * cos(yaw), r.z)
        r = SIMD3(r.x * cos(pitch) + r.z * sin(pitch), r.y, -r.x * sin(pitch) + r.z * cos(pitch))
        r = SIMD3(r.x, r.y * cos(roll) - r.z * sin(roll), r.y * sin(roll) + r.z * cos(roll))
        return r
    }

    func testRecoversForwardAccelerationFromATiltedPhone() {
        // In the car: forward = x, gravity = -z. The phone is turned and tilted.
        let (yaw, pitch, roll) = (1.1, -0.6, 0.35)
        let profile: (Double) -> Double = { t in t < 1 ? 0 : 5 * exp(-(t - 1) / 8) }
        let raw = stride(from: 0.0, to: 6.0, by: 0.01).map { t in
            RawMotionSample(
                t: t,
                user: rotate(SIMD3(profile(t), 0.2 * sin(t * 3), 0), yaw: yaw, pitch: pitch, roll: roll),
                gravity: rotate(SIMD3(0, 0, -1), yaw: yaw, pitch: pitch, roll: roll)
            )
        }
        let forward = AxisCalibration.forwardAccel(raw)
        for (sample, t) in zip(forward, stride(from: 0.0, to: 6.0, by: 0.01)) where t > 1.2 {
            XCTAssertEqual(sample.accel, profile(t), accuracy: 0.25)
        }
    }

    func testWithoutALaunchEverythingIsZero() {
        let raw = (0..<100).map { RawMotionSample(t: Double($0) / 100, user: SIMD3(0.05, 0, 0), gravity: SIMD3(0, 0, -1)) }
        XCTAssertTrue(AxisCalibration.forwardAccel(raw).allSatisfy { $0.accel == 0 })
    }
}
