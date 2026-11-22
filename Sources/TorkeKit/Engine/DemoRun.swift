import Foundation

/// A simulated run to try an app without going to the track: 2 s still, then a street car
/// accelerating past the quarter mile, with the phone tilted in its mount, sensor noise and
/// a 1 Hz GPS. The same seed gives the same run on iOS and Android.
public enum DemoRun {
    public static func generate(seed: UInt64 = 42) -> (motion: [RawMotionSample], gps: [GPSSample]) {
        var state = seed
        func gaussian() -> Double {
            func uniform() -> Double {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return Double(state >> 11) / Double(1 << 53)
            }
            let u1 = max(uniform(), 1e-12), u2 = uniform()
            return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        }
        // Phone turned 90° in the mount and tilted back
        let forward = SIMD3<Double>(0, -0.94, -0.34)
        let gravity = SIMD3<Double>(0, -0.34, 0.94) * -1

        var motion: [RawMotionSample] = [], gps: [GPSSample] = []
        let dt = 0.001, still = 2.0
        var t = 0.0, v = 0.0, d = 0.0, nextImu = 0.0, nextGps = 0.3
        while t < still + 30, d < DragDistance.quarterMile + 60 {
            let a = t < still ? 0 : 6.8 * (1 - v / 72)
            if t >= nextImu {
                let user = forward * a + SIMD3(gaussian(), gaussian(), gaussian()) * 0.08
                motion.append(RawMotionSample(t: t, user: user, gravity: gravity))
                nextImu += 0.01
            }
            if t >= nextGps {
                gps.append(GPSSample(t: t, speed: max(0, v + 0.3 * gaussian()), speedAccuracy: 0.4))
                nextGps += 1
            }
            v += a * dt
            d += v * dt
            t += dt
        }
        return (motion, gps)
    }
}
