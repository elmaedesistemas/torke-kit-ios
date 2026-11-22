import Foundation

/// Reading any mark from a run's trace, beyond the standard ones.
public extension RunResult {
    /// Time to cover `meters` from the start line, discounting the 1-foot rollout like a
    /// dragstrip. Nil when the trace does not reach it.
    func elapsed(toDistance meters: Double) -> TimeInterval? {
        guard let rollout = RunAnalyzer.time(atDistance: DragDistance.rollout, in: trace),
              let t = RunAnalyzer.time(atDistance: meters, in: trace) else { return nil }
        return t - rollout
    }

    /// Speed (km/h) when the run passed `meters`.
    func speedKmh(atDistance meters: Double) -> Double? {
        RunAnalyzer.speed(atDistance: meters, in: trace).map { $0 * 3.6 }
    }

    /// Time from the first movement to `kmh`.
    func time(toKmh kmh: Double) -> TimeInterval? {
        RunAnalyzer.time(atSpeed: kmh / 3.6, in: trace)
    }

    /// Time from `fromKmh` to `toKmh` during the launch, such as 100–200 km/h.
    func time(fromKmh: Double, toKmh: Double) -> TimeInterval? {
        guard toKmh > fromKmh, let a = time(toKmh: fromKmh), let b = time(toKmh: toKmh) else { return nil }
        return b - a
    }

    /// 0 to 60 mph, from the first movement.
    var zeroTo60mph: TimeInterval? { RunAnalyzer.time(atSpeed: DragDistance.speed60mph, in: trace) }
    /// 1000 feet.
    var thousandFeet: TimeInterval? { elapsed(toDistance: DragDistance.thousandFeet) }
    /// 1/2 mile. Analyze with a `stopDistance` past it to get one.
    var halfMile: TimeInterval? { elapsed(toDistance: DragDistance.halfMile) }
}
