import Foundation

/// Plays back a recorded run, for tests, demos and re-analysis.
public struct RecordedRunProvider: RunDataProvider {
    public var run: TorkeRun
    /// 1 plays at the speed it was recorded; 0 (the default) as fast as possible.
    public var speed: Double

    public init(_ run: TorkeRun, speed: Double = 0) {
        self.run = run
        self.speed = speed
    }

    /// The simulated street car of ``DemoRun``.
    public static func demo(seed: UInt64 = 42, speed: Double = 0) -> RecordedRunProvider {
        let demo = DemoRun.generate(seed: seed)
        return RecordedRunProvider(TorkeRun(motion: demo.motion, gps: demo.gps), speed: speed)
    }

    public func samples() -> AsyncStream<SensorSample> {
        let ordered = Self.merge(run)
        let speed = speed
        return AsyncStream { continuation in
            let task = Task {
                var previous: TimeInterval?
                for sample in ordered {
                    if Task.isCancelled { break }
                    if speed > 0, let previous, sample.t > previous {
                        try? await Task.sleep(for: .seconds((sample.t - previous) / speed))
                    }
                    previous = sample.t
                    continuation.yield(sample)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Motion and GPS in one time-ordered list; at equal times, motion first.
    public static func merge(_ run: TorkeRun) -> [SensorSample] {
        var out: [SensorSample] = []
        out.reserveCapacity(run.motion.count + run.gps.count)
        var i = 0, j = 0
        while i < run.motion.count || j < run.gps.count {
            if j >= run.gps.count || (i < run.motion.count && run.motion[i].t <= run.gps[j].t) {
                out.append(.motion(run.motion[i])); i += 1
            } else {
                out.append(.gps(run.gps[j])); j += 1
            }
        }
        return out
    }
}
