import XCTest
@testable import TorkeKit

/// Synthetic runs with known physics: what the analyzer measures is compared with the
/// exact time of the simulation.
final class RunAnalyzerTests: XCTestCase {

    /// Deterministic noise generator.
    struct Noise {
        var state: UInt64
        mutating func uniform() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        /// Standard normal (Box-Muller).
        mutating func gaussian() -> Double {
            let u1 = max(uniform(), 1e-12), u2 = uniform()
            return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        }
    }

    struct Truth { var quarter: Double?; var sixtyFeet: Double?; var zeroTo100: Double?; var launch: Double }

    /// Simulates a run: `still` seconds still, then acceleration a(v).
    static func simulate(
        still: Double = 2,
        duration: Double = 25,
        accel: (Double) -> Double,
        imuHz: Double = 100,
        gpsHz: Double = 1,
        bias: Double = 0,
        imuNoise: Double = 0,
        gpsNoise: Double = 0,
        seed: UInt64 = 7
    ) -> (motion: [MotionSample], gps: [GPSSample], truth: Truth) {
        var noise = Noise(state: seed)
        var motion: [MotionSample] = [], gps: [GPSSample] = []
        let dt = 0.001
        var t = 0.0, v = 0.0, d = 0.0
        var nextImu = 0.0, nextGps = 0.0
        var tRollout: Double?, t60: Double?, tQuarter: Double?, t100: Double?
        while t < still + duration {
            let a = t < still ? 0 : accel(v)
            if t >= nextImu {
                motion.append(MotionSample(t: t, accel: a + bias + imuNoise * noise.gaussian()))
                nextImu += 1 / imuHz
            }
            if t >= nextGps {
                gps.append(GPSSample(t: t, speed: max(0, v + gpsNoise * noise.gaussian()), speedAccuracy: max(gpsNoise, 0.2)))
                nextGps += 1 / gpsHz
            }
            v += a * dt
            d += v * dt
            t += dt
            if tRollout == nil, d >= DragDistance.rollout { tRollout = t }
            if t60 == nil, d >= DragDistance.sixtyFeet { t60 = t }
            if tQuarter == nil, d >= DragDistance.quarterMile { tQuarter = t }
            if t100 == nil, v >= DragDistance.speed100 { t100 = t }
        }
        let truth = Truth(
            quarter: tQuarter.flatMap { q in tRollout.map { q - $0 } },
            sixtyFeet: t60.flatMap { s in tRollout.map { s - $0 } },
            zeroTo100: t100.map { $0 - still },
            launch: still
        )
        return (motion, gps, truth)
    }

    /// A street car: traction that drops with speed.
    static let streetCar: @Sendable (Double) -> Double = { v in 6.5 * (1 - v / 75) }

    func testConstantAccelerationMatchesPhysics() throws {
        let sim = Self.simulate(accel: { _ in 5 }, gpsHz: 1)
        let r = try XCTUnwrap(RunAnalyzer.analyze(motion: sim.motion, gps: sim.gps))
        XCTAssertEqual(r.quarterMile!, sim.truth.quarter!, accuracy: 0.03)
        XCTAssertEqual(r.sixtyFeet!, sim.truth.sixtyFeet!, accuracy: 0.02)
        XCTAssertEqual(r.zeroTo100!, sim.truth.zeroTo100!, accuracy: 0.03)
        XCTAssertEqual(r.quarterMileKmh!, (2 * 5 * DragDistance.quarterMile).squareRoot() * 3.6, accuracy: 1.0)
    }

    func testDetectsLaunchWithinFiftyMilliseconds() throws {
        let sim = Self.simulate(still: 3, accel: Self.streetCar, imuNoise: 0.08, seed: 11)
        let r = try XCTUnwrap(RunAnalyzer.analyze(motion: sim.motion, gps: sim.gps))
        XCTAssertEqual(r.launchTime, sim.truth.launch, accuracy: 0.05)
    }

    func testBiasAndNoiseStayWithinTarget() throws {
        // Mount with 0.3 m/s² of bias, accelerometer noise and a 1 Hz phone GPS
        let sim = Self.simulate(accel: Self.streetCar, gpsHz: 1, bias: 0.3, imuNoise: 0.15, gpsNoise: 0.4, seed: 3)
        let r = try XCTUnwrap(RunAnalyzer.analyze(motion: sim.motion, gps: sim.gps))
        // Targets: ±0.15 s on the 1/4, ±0.10 s on 60 ft, ±0.20 s on 0–100
        XCTAssertEqual(r.quarterMile!, sim.truth.quarter!, accuracy: 0.15)
        XCTAssertEqual(r.sixtyFeet!, sim.truth.sixtyFeet!, accuracy: 0.10)
        XCTAssertEqual(r.zeroTo100!, sim.truth.zeroTo100!, accuracy: 0.20)
    }

    func testFasterGPSImprovesTheQuarter() throws {
        let slow = Self.simulate(accel: Self.streetCar, gpsHz: 1, bias: 0.4, imuNoise: 0.15, gpsNoise: 0.4, seed: 5)
        let fast = Self.simulate(accel: Self.streetCar, gpsHz: 10, bias: 0.4, imuNoise: 0.15, gpsNoise: 0.4, seed: 5)
        let rSlow = try XCTUnwrap(RunAnalyzer.analyze(motion: slow.motion, gps: slow.gps))
        let rFast = try XCTUnwrap(RunAnalyzer.analyze(motion: fast.motion, gps: fast.gps))
        XCTAssertLessThanOrEqual(abs(rFast.quarterMile! - fast.truth.quarter!), abs(rSlow.quarterMile! - slow.truth.quarter!) + 0.01)
        XCTAssertEqual(rFast.quarterMile!, fast.truth.quarter!, accuracy: 0.08)
    }

    func testShortRunHasSixtyFeetButNoQuarter() throws {
        let sim = Self.simulate(duration: 4, accel: Self.streetCar)
        let r = try XCTUnwrap(RunAnalyzer.analyze(motion: sim.motion, gps: sim.gps))
        XCTAssertNotNil(r.sixtyFeet)
        XCTAssertNil(r.quarterMile)
    }

    func testNoLaunchWhenTheCarNeverStops() {
        // Already rolling from the start: no launch from a standstill
        let sim = Self.simulate(still: 0, duration: 10, accel: { _ in 3 })
        XCTAssertNil(RunAnalyzer.analyze(motion: sim.motion, gps: sim.gps))
    }

    func testNoLaunchWhenParked() {
        let motion = (0..<500).map { MotionSample(t: Double($0) / 100, accel: 0.02) }
        XCTAssertNil(RunAnalyzer.analyze(motion: motion, gps: []))
    }
}
