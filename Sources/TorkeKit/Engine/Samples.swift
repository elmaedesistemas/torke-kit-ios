import Foundation

/// One raw reading of the motion sensor, in the phone's frame.
///
/// `user` is the acceleration without gravity (m/s²); `gravity` is the direction of gravity
/// (any length, it is normalized). Timestamps are seconds on a monotonic clock shared with
/// ``GPSSample/t``.
public struct RawMotionSample: Sendable, Codable, Equatable {
    public var t: TimeInterval
    public var user: SIMD3<Double>
    public var gravity: SIMD3<Double>

    public init(t: TimeInterval, user: SIMD3<Double>, gravity: SIMD3<Double>) {
        self.t = t
        self.user = user
        self.gravity = gravity
    }
}

/// Longitudinal acceleration of the vehicle (m/s², positive forward), already projected on
/// the forward axis by ``AxisCalibration``.
public struct MotionSample: Sendable, Codable, Equatable {
    public var t: TimeInterval
    public var accel: Double

    public init(t: TimeInterval, accel: Double) {
        self.t = t
        self.accel = accel
    }
}

/// One GPS fix: speed (m/s) with its accuracy (m/s, one standard deviation) and, when
/// known, the position.
public struct GPSSample: Sendable, Codable, Equatable {
    public var t: TimeInterval
    public var speed: Double
    public var speedAccuracy: Double
    public var latitude: Double?
    public var longitude: Double?
    /// Horizontal accuracy of the position, in meters.
    public var horizontalAccuracy: Double?

    public init(
        t: TimeInterval,
        speed: Double,
        speedAccuracy: Double,
        latitude: Double? = nil,
        longitude: Double? = nil,
        horizontalAccuracy: Double? = nil
    ) {
        self.t = t
        self.speed = speed
        self.speedAccuracy = speedAccuracy
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
    }

    /// Fixes with `speedAccuracy` of ``noSpeed`` or more carry a position but no speed.
    public static let noSpeed = 50.0
    public var hasSpeed: Bool { speedAccuracy < Self.noSpeed }

    public var coordinate: Coordinate? {
        guard let latitude, let longitude else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }
}

/// A point on Earth, in degrees (WGS 84).
public struct Coordinate: Sendable, Codable, Equatable, Hashable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Official drag racing distances and speeds.
public enum DragDistance {
    /// 1 foot: the rollout tracks discount before the timers start.
    public static let rollout = 0.3048
    /// 60 feet.
    public static let sixtyFeet = 18.288
    /// 1/8 mile.
    public static let eighthMile = 201.168
    /// 1/4 mile.
    public static let quarterMile = 402.336
    /// 100 km/h in m/s.
    public static let speed100 = 100.0 / 3.6
}

/// A point of the run's curve, measured from the launch.
public struct TracePoint: Sendable, Codable, Equatable {
    public var t: TimeInterval
    public var speed: Double
    public var distance: Double

    public init(t: TimeInterval, speed: Double, distance: Double) {
        self.t = t
        self.speed = speed
        self.distance = distance
    }
}

/// The times of a run. Distance times discount the 1-foot rollout, like a dragstrip;
/// 0 to 100 counts from the first movement. Speeds in km/h, times in seconds.
public struct RunResult: Sendable, Codable, Equatable {
    /// When the car started moving, on the samples' clock.
    public var launchTime: TimeInterval
    public var zeroTo100: TimeInterval?
    public var sixtyFeet: TimeInterval?
    public var eighthMile: TimeInterval?
    public var eighthMileKmh: Double?
    public var quarterMile: TimeInterval?
    public var quarterMileKmh: Double?
    public var topSpeedKmh: Double
    /// Accelerometer bias the filter ended with (m/s²): large values mean a loose mount.
    public var accelBias: Double
    public var trace: [TracePoint]

    public init(
        launchTime: TimeInterval, zeroTo100: TimeInterval?, sixtyFeet: TimeInterval?,
        eighthMile: TimeInterval?, eighthMileKmh: Double?, quarterMile: TimeInterval?,
        quarterMileKmh: Double?, topSpeedKmh: Double, accelBias: Double, trace: [TracePoint]
    ) {
        self.launchTime = launchTime
        self.zeroTo100 = zeroTo100
        self.sixtyFeet = sixtyFeet
        self.eighthMile = eighthMile
        self.eighthMileKmh = eighthMileKmh
        self.quarterMile = quarterMile
        self.quarterMileKmh = quarterMileKmh
        self.topSpeedKmh = topSpeedKmh
        self.accelBias = accelBias
        self.trace = trace
    }

    /// The time shown big: the longest distance the run covered.
    public var headline: (mark: DragMark, time: TimeInterval)? {
        if let quarterMile { return (.quarterMile, quarterMile) }
        if let eighthMile { return (.eighthMile, eighthMile) }
        if let zeroTo100 { return (.zeroTo100, zeroTo100) }
        if let sixtyFeet { return (.sixtyFeet, sixtyFeet) }
        return nil
    }
}

/// The marks a drag run is timed at.
public enum DragMark: String, Sendable, Codable, CaseIterable {
    case sixtyFeet, zeroTo100, eighthMile, quarterMile
}
