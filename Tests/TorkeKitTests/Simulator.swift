import Foundation
@testable import TorkeKit

/// Raw-sensor runs with exact physics, for the phase 2 tests and fixtures.
enum Simulator {
    struct Run { var motion: [RawMotionSample]; var gps: [GPSSample] }

    /// `speed0` m/s at t = 0, then acceleration a(t, v) (negative to brake), for `duration` s.
    /// The phone lies tilted: forward is −y, gravity mostly −z.
    static func run(speed0: Double, duration: Double, gpsHz: Double = 1, noise: Double = 0.05, seed: UInt64 = 1,
                    altitudeSlope: Double? = nil, tiltAfter: Double? = nil,
                    accel: (Double, Double) -> Double) -> Run {
        var state = seed
        func gaussian() -> Double {
            func uniform() -> Double {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return Double(state >> 11) / Double(1 << 53)
            }
            let u1 = max(uniform(), 1e-12), u2 = uniform()
            return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        }
        let forward = SIMD3<Double>(0, -0.94, -0.34)
        let gravity = SIMD3<Double>(0, 0.34, -0.94)
        let tilted = SIMD3<Double>(0.3, 0.30, -0.90)
        var motion: [RawMotionSample] = [], gps: [GPSSample] = []
        let dt = 0.001
        var t = 0.0, v = speed0, d = 0.0, nextImu = 0.0, nextGps = 0.0
        while t < duration {
            let a = v <= 0 && accel(t, v) < 0 ? 0 : accel(t, v)
            if t >= nextImu {
                let g = (tiltAfter.map { t > $0 } ?? false) ? tilted : gravity
                motion.append(RawMotionSample(t: t, user: forward * a + SIMD3(gaussian(), gaussian(), gaussian()) * noise, gravity: g))
                nextImu += 0.01
            }
            if t >= nextGps {
                gps.append(GPSSample(t: t, speed: max(0, v + 0.2 * gaussian()), speedAccuracy: 0.3,
                                     latitude: 9.9, longitude: -84.2, horizontalAccuracy: 3,
                                     altitude: altitudeSlope.map { 1000 + $0 * d }))
                nextGps += 1 / gpsHz
            }
            v = max(0, v + a * dt)
            d += v * dt
            t += dt
        }
        return Run(motion: motion, gps: gps)
    }

    /// 2 s still, then a constant 5 m/s² launch.
    static func constantLaunch(duration: Double = 25, gpsHz: Double = 1, altitudeSlope: Double? = nil, tiltAfter: Double? = nil) -> Run {
        run(speed0: 0, duration: duration, gpsHz: gpsHz, altitudeSlope: altitudeSlope, tiltAfter: tiltAfter) { t, _ in t < 2 ? 0 : 5 }
    }

    /// 50 km/h, then 3 m/s² past 140 km/h.
    static func rolling() -> Run {
        run(speed0: 50 / 3.6, duration: 12, gpsHz: 5) { t, _ in t < 1 ? 0 : 3 }
    }

    /// 110 km/h cruising, then −8 m/s² to a stop.
    static func braking() -> Run {
        run(speed0: 110 / 3.6, duration: 9, gpsHz: 5) { t, _ in t < 3 ? 0 : -8 }
    }
}
