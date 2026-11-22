import Foundation

/// Where a run is.
public enum RunPhase: Sendable, Equatable {
    /// Not recording. Location updates still refresh the snapshot (a GPS preview).
    case idle
    /// Recording, waiting for the car to stand still.
    case waitingStill
    /// Standing still: the timer starts by itself at launch.
    case armed
    /// Moving. `start` is the launch on the samples' clock.
    case running(start: TimeInterval)
    /// Done: ``RunSnapshot/result`` has the times.
    case finished
    case failed(RunFailure)

    public var isRecording: Bool {
        switch self {
        case .waitingStill, .armed, .running: true
        default: false
        }
    }
}

/// Why a run could not be measured.
public enum RunFailure: String, Sendable, Codable, Error, Equatable {
    /// The run ended without a launch from a standstill.
    case noLaunch
    /// The device has no motion sensors (or they are off).
    case noMotionSensors
    /// The app is not allowed to use the location.
    case locationDenied
}

/// What happened during a run, in order. Listen with ``RunSession/events()``.
public enum RunEvent: Sendable, Equatable {
    /// The car stood still long enough: it can launch.
    case armed
    /// It moved before launching: waiting for it to stand still again.
    case disarmed
    /// The car launched, at `time` on the samples' clock, from `location` if the GPS had one.
    case launched(time: TimeInterval, location: Coordinate?)
    /// A live estimate of a mark, from the GPS alone. The official times come in `finished`.
    case passed(DragMark, elapsed: TimeInterval)
    case finished(RunResult)
    case failed(RunFailure)
}

/// The live state of a ``RunSession``, for the screen.
public struct RunSnapshot: Sendable, Equatable {
    public var phase: RunPhase = .idle
    /// Live GPS speed, m/s.
    public var speed: Double = 0
    /// Seconds since the launch.
    public var elapsed: TimeInterval = 0
    /// Meters since the launch, live estimate from the GPS.
    public var distance: Double = 0
    /// Horizontal accuracy of the last fix, in meters.
    public var gpsAccuracy: Double?
    /// The last known position.
    public var location: Coordinate?
    /// Where the run launched. Send it to your server to decide where the run counts.
    public var startLocation: Coordinate?
    /// The official times, once ``phase`` is ``RunPhase/finished``.
    public var result: RunResult?

    public init() {}

    public var speedKmh: Double { speed * 3.6 }
}

/// Thresholds of the live detection. The defaults are tuned for a phone in a rigid mount.
public struct RunSessionOptions: Sendable, Equatable {
    /// Seconds the car must stand still before it is armed.
    public var stillWindow: TimeInterval = 1
    /// Horizontal acceleration (m/s²) under which the car counts as still.
    public var stillAccel: Double = 0.6
    /// GPS speed (m/s) under which the car counts as stopped.
    public var stillSpeed: Double = 1.5
    /// Horizontal acceleration (m/s²) that marks a launch…
    public var launchAccel: Double = 2.0
    /// …when every sample of the last `launchHold` seconds stays above this.
    public var launchHoldAccel: Double = 1.4
    public var launchHold: TimeInterval = 0.15
    /// Movement that has not become a launch this long after `launchHold` disarms.
    public var launchGrace: TimeInterval = 0.35
    /// The run ends by itself this far past the launch (meters).
    public var finishDistance: Double = DragDistance.quarterMile + 25
    /// …or when the speed drops under this share of the peak (lifting off).
    public var backOffRatio: Double = 0.6
    /// …or after this long (seconds).
    public var maxDuration: TimeInterval = 40

    public init() {}
}
