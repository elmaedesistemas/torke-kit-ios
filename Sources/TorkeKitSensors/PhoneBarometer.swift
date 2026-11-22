#if os(iOS)
import CoreMotion
import Foundation

/// The phone's barometer, for ``Weather``: it reads the station pressure, the one the SAE
/// correction needs, right where the car is. Every iPhone since the 6 has one. Uses the motion
/// permission (`NSMotionUsageDescription`).
@MainActor
public final class PhoneBarometer {
    private let altimeter = CMAltimeter()

    public init() {}

    public static var isAvailable: Bool { CMAltimeter.isRelativeAltitudeAvailable() }

    /// The station pressure in hPa, averaged over `readings` samples (about one per second);
    /// nil without a barometer, without permission, or after 6 s.
    public func stationPressureHpa(readings: Int = 3) async -> Double? {
        guard Self.isAvailable else { return nil }
        let reading: Double? = await withCheckedContinuation { continuation in
            var values: [Double] = []
            var done = false
            let finish: (Double?) -> Void = { [altimeter] value in
                guard !done else { return }
                done = true
                altimeter.stopRelativeAltitudeUpdates()
                continuation.resume(returning: value)
            }
            altimeter.startRelativeAltitudeUpdates(to: .main) { data, error in
                guard let data, error == nil else { return finish(nil) }
                values.append(data.pressure.doubleValue * 10) // kPa → hPa
                if values.count >= readings { finish(values.reduce(0, +) / Double(values.count)) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                finish(values.isEmpty ? nil : values.reduce(0, +) / Double(values.count))
            }
        }
        return reading
    }
}
#endif
