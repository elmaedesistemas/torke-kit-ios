import Foundation

/// A recorded run in the open `torke.run` format: every raw sample plus the result.
/// The same JSON is read and written by TorkeKit for iOS and for Android.
///
/// ```json
/// { "format": "torke.run", "version": 1, "recordedAt": "2026-11-21T16:54:06Z",
///   "motion": [{ "t": 0.01, "user": [0, -0.2, 0.1], "gravity": [0, 0.34, -0.94] }],
///   "gps": [{ "t": 0.3, "speed": 0, "speedAccuracy": 0.4 }],
///   "result": { "quarterMile": 13.9, … } }
/// ```
public struct TorkeRun: Sendable, Codable, Equatable {
    public static let formatName = "torke.run"
    public static let currentVersion = 1

    public var format: String
    public var version: Int
    public var recordedAt: Date?
    /// Free text, such as "iPhone16,1".
    public var device: String?
    /// The app that recorded it, such as "Torke 1.0".
    public var app: String?
    public var motion: [RawMotionSample]
    public var gps: [GPSSample]
    public var result: RunResult?
    /// The result of a rolling or braking run.
    public var interval: IntervalResult?
    /// Weather at the strip, for corrected times.
    public var weather: Weather?
    /// The vehicle's suspension when the run was made, to compare setups.
    public var suspension: SuspensionSetup?

    public init(
        recordedAt: Date? = nil, device: String? = nil, app: String? = nil,
        motion: [RawMotionSample], gps: [GPSSample], result: RunResult? = nil,
        interval: IntervalResult? = nil, weather: Weather? = nil, suspension: SuspensionSetup? = nil
    ) {
        self.format = Self.formatName
        self.version = Self.currentVersion
        self.recordedAt = recordedAt
        self.device = device
        self.app = app
        self.motion = motion
        self.gps = gps
        self.result = result
        self.interval = interval
        self.weather = weather
        self.suspension = suspension
    }

    /// Computes the times again from the raw samples.
    public func analyze(stopDistance: Double = DragDistance.quarterMile + 20) -> RunResult? {
        RunAnalyzer.analyze(motion: AxisCalibration.forwardAccel(motion), gps: gps, stopDistance: stopDistance)
    }

    /// A rolling interval, such as 60–130 km/h, from the raw samples.
    public func rolling(fromKmh: Double = 60, toKmh: Double = 130) -> IntervalResult? {
        IntervalAnalyzer.rolling(motion: motion, gps: gps, fromKmh: fromKmh, toKmh: toKmh)
    }

    /// A braking, such as 100–0 km/h, from the raw samples.
    public func braking(fromKmh: Double = 100) -> IntervalResult? {
        IntervalAnalyzer.braking(motion: motion, gps: gps, fromKmh: fromKmh)
    }

    /// How much the run can be trusted. See ``RunQuality``.
    public func quality() -> RunQuality? {
        RunQuality.assess(self)
    }

    /// Where the run launched, from the GPS fix closest before the launch.
    public var startLocation: Coordinate? {
        guard let launch = result?.launchTime else { return nil }
        return gps.last(where: { $0.t <= launch && $0.coordinate != nil })?.coordinate
    }

    // MARK: - JSON

    public func encoded(pretty: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> TorkeRun {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let run = try decoder.decode(TorkeRun.self, from: data)
        guard run.format == formatName else { throw FormatError.notATorkeRun(run.format) }
        guard run.version <= currentVersion else { throw FormatError.newerVersion(run.version) }
        return run
    }

    public enum FormatError: Error, Equatable {
        case notATorkeRun(String)
        /// Written by a newer TorkeKit: update the SDK to read it.
        case newerVersion(Int)
    }
}
