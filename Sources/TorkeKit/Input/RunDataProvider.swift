import Foundation

/// One reading from a sensor source.
public enum SensorSample: Sendable, Equatable {
    case motion(RawMotionSample)
    case gps(GPSSample)

    public var t: TimeInterval {
        switch self {
        case let .motion(m): m.t
        case let .gps(g): g.t
        }
    }
}

/// Anything that produces motion and GPS samples: the phone's sensors, an external GPS,
/// a recorded run. Motion and GPS timestamps must share one monotonic clock.
@MainActor
public protocol RunDataProvider {
    /// The samples, in time order. The stream ends when the source stops; cancelling it
    /// turns the source off.
    func samples() -> AsyncStream<SensorSample>
}
