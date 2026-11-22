import Foundation

/// How the tree counts down: Pro lights the three ambers at once and green 0.4 s later;
/// Sportsman lights them one by one, 0.5 s apart, and green 0.5 s after the last.
public enum TreeType: String, Sendable, Codable, CaseIterable {
    case pro, sportsman

    /// Seconds from one amber to the next (0: all at once).
    public var amberGap: TimeInterval { self == .pro ? 0 : 0.5 }
    /// Seconds from the last amber to green.
    public var greenDelay: TimeInterval { self == .pro ? 0.4 : 0.5 }
}

/// One light of the tree, at a time on the samples' clock.
public struct TreeLight: Sendable, Codable, Equatable {
    public enum Kind: String, Sendable, Codable { case amber1, amber2, amber3, green }
    public var kind: Kind
    public var time: TimeInterval
}

/// The driver's reaction: from green to the car leaving the stage beam (after the 1-foot
/// rollout), like a dragstrip. Negative is a red light.
public struct Reaction: Sendable, Codable, Equatable {
    public var time: TimeInterval
    public var isRedLight: Bool { time < 0 }
    /// Within half a millisecond of green: a "perfect light".
    public var isPerfect: Bool { abs(time) < 0.0005 }
}

/// A Christmas tree on the phone's screen. Its lights are times on the same monotonic clock as
/// the sensor samples (iOS: `systemUptime`; Android: `elapsedRealtime`), so the app draws them
/// on schedule and TorkeKit measures the reaction from the run.
///
/// ```swift
/// // When the car is armed (staged):
/// let tree = ChristmasTree.start(type: .pro, stagedAt: ProcessInfo.processInfo.systemUptime)
/// // Draw tree.lights on schedule; after the run:
/// let reaction = result.reaction(on: tree)      // .time, .isRedLight
/// ```
public struct ChristmasTree: Sendable, Codable, Equatable {
    public var type: TreeType
    /// When the (first) amber lights.
    public var activatedAt: TimeInterval

    public init(type: TreeType, activatedAt: TimeInterval) {
        self.type = type
        self.activatedAt = activatedAt
    }

    /// A tree that activates after a random delay from the moment the car is staged, like a
    /// track's auto-start. Give a `seed` for a repeatable delay (tests, replays).
    public static func start(type: TreeType, stagedAt: TimeInterval, delay: ClosedRange<Double> = 0.6...1.1, seed: UInt64? = nil) -> ChristmasTree {
        let unit: Double
        if let seed {
            let state = seed &* 6364136223846793005 &+ 1442695040888963407
            unit = Double(state >> 11) / Double(1 << 53)
        } else {
            unit = Double.random(in: 0..<1)
        }
        return ChristmasTree(type: type, activatedAt: stagedAt + delay.lowerBound + (delay.upperBound - delay.lowerBound) * unit)
    }

    /// Every light in order.
    public var lights: [TreeLight] {
        let g = type.amberGap
        return [
            TreeLight(kind: .amber1, time: activatedAt),
            TreeLight(kind: .amber2, time: activatedAt + g),
            TreeLight(kind: .amber3, time: activatedAt + 2 * g),
            TreeLight(kind: .green, time: greenAt),
        ]
    }

    public var greenAt: TimeInterval { activatedAt + 2 * type.amberGap + type.greenDelay }

    /// The lights that are on at `time` (ambers stay on until green).
    public func lit(at time: TimeInterval) -> [TreeLight.Kind] {
        if time >= greenAt { return [.green] }
        return lights.filter { $0.kind != .green && $0.time <= time }.map(\.kind)
    }

    /// Reaction from the moment the car left the stage beam.
    public func reaction(leftStageAt time: TimeInterval) -> Reaction {
        Reaction(time: time - greenAt)
    }

    /// A live estimate from ``RunEvent/launched(time:location:)``, before the run is analyzed:
    /// adds a typical rollout time. The exact reaction comes from ``RunResult/reaction(on:)``.
    public func estimatedReaction(launchedAt time: TimeInterval, rolloutTime: TimeInterval = 0.15) -> Reaction {
        reaction(leftStageAt: time + rolloutTime)
    }
}

public extension RunResult {
    /// When the car left the stage beam: the launch plus the time to cover the 1-foot rollout.
    var leftStageAt: TimeInterval? {
        RunAnalyzer.time(atDistance: DragDistance.rollout, in: trace).map { launchTime + $0 }
    }

    /// The reaction on `tree`. Nil without the run's trace.
    func reaction(on tree: ChristmasTree) -> Reaction? {
        leftStageAt.map(tree.reaction(leftStageAt:))
    }

    /// Reaction plus elapsed time to the quarter mile: the "package" of bracket racing.
    func package(on tree: ChristmasTree) -> TimeInterval? {
        guard let r = reaction(on: tree), let et = quarterMile else { return nil }
        return r.time + et
    }
}
