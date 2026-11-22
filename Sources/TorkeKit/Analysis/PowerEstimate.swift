import Foundation

/// Power estimates from a run. `massKg` is the vehicle with the driver. These are
/// approximations (about ±15 %): good to compare changes on the same car.
public enum PowerEstimate {
    /// Watts in a mechanical horsepower.
    public static let wattsPerHp = 745.7

    /// Flywheel horsepower from the 1/4 mile trap speed (Hale's formula).
    public static func fromTrapSpeed(massKg: Double, quarterMileKmh: Double) -> Double {
        let pounds = massKg * 2.204_62
        let mph = quarterMileKmh / 1.609_344
        return pounds * pow(mph / 234, 3)
    }

    /// Flywheel horsepower from the 1/4 mile elapsed time (Hale's formula). Traction losses
    /// make it read low on cars that spin at the launch; the trap speed is more reliable.
    public static func fromElapsedTime(massKg: Double, quarterMile: TimeInterval) -> Double {
        let pounds = massKg * 2.204_62
        return pounds * pow(5.825 / quarterMile, 3)
    }

    /// Power at the wheels along the run: mass × acceleration × speed, plus the air drag and
    /// the rolling resistance it had to beat.
    ///
    /// - Parameters:
    ///   - dragArea: drag coefficient × frontal area, m². About 0.6 for a sedan, 0.8 for a pickup.
    ///   - rollingResistance: about 0.012 on drag radials, 0.015 on street tires.
    ///   - airDensity: kg/m³, ``Weather/airDensity`` if you have it.
    public static func wheelPower(
        _ result: RunResult, massKg: Double, dragArea: Double = 0.7,
        rollingResistance: Double = 0.015, airDensity: Double = 1.2
    ) -> [PowerPoint] {
        // Speed every 0.05 s, acceleration over ±0.25 s: the GPS corrections make small
        // steps in the speed that a point-to-point derivative would turn into spikes.
        let grid = resample(result.trace, step: 0.05)
        guard grid.count > 10 else { return [] }
        let half = 5
        var out: [PowerPoint] = []
        for i in half..<(grid.count - half) {
            let a = (grid[i + half].speed - grid[i - half].speed) / (grid[i + half].t - grid[i - half].t)
            let v = grid[i].speed
            let force = massKg * a + 0.5 * airDensity * dragArea * v * v + rollingResistance * massKg * DragDistance.g
            out.append(PowerPoint(t: grid[i].t, speedKmh: v * 3.6, watts: max(0, force * v)))
        }
        return out
    }

    static func resample(_ trace: [TracePoint], step: Double) -> [TracePoint] {
        guard let end = trace.last?.t else { return [] }
        var out: [TracePoint] = []
        var j = 1
        var k = 0
        while trace.count > 1 {
            let t = Double(k) * step
            if t > end { break }
            while j < trace.count - 1, trace[j].t < t { j += 1 }
            let a = trace[j - 1], b = trace[j]
            let f = b.t == a.t ? 0 : min(1, max(0, (t - a.t) / (b.t - a.t)))
            out.append(TracePoint(t: t, speed: a.speed + (b.speed - a.speed) * f, distance: a.distance + (b.distance - a.distance) * f))
            k += 1
        }
        return out
    }

    /// The peak of ``wheelPower(_:massKg:dragArea:rollingResistance:airDensity:)`` in hp.
    public static func peakWheelHp(_ result: RunResult, massKg: Double, dragArea: Double = 0.7, rollingResistance: Double = 0.015, airDensity: Double = 1.2) -> Double? {
        wheelPower(result, massKg: massKg, dragArea: dragArea, rollingResistance: rollingResistance, airDensity: airDensity)
            .map(\.hp).max()
    }
}

/// Power at one point of the run.
public struct PowerPoint: Sendable, Equatable {
    public var t: TimeInterval
    public var speedKmh: Double
    public var watts: Double
    public var hp: Double { watts / PowerEstimate.wattsPerHp }
}
