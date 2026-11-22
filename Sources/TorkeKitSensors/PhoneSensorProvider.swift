#if os(iOS)
import CoreLocation
import CoreMotion
import Foundation
import TorkeKit

/// The phone's own sensors: device motion at 100 Hz and the GPS at its top rate.
///
/// Ask for location permission first (``requestPermission()``). Keep the screen on while a
/// run records (`UIApplication.shared.isIdleTimerDisabled`); for background recording add
/// the `location` background mode.
@MainActor
public final class PhoneSensorProvider: NSObject, RunDataProvider {
    /// The current location permission.
    public private(set) var authorization: CLAuthorizationStatus
    public var hasMotionSensors: Bool { motion.isDeviceMotionAvailable }

    private let location = CLLocationManager()
    private let motion = CMMotionManager()
    private var continuation: AsyncStream<SensorSample>.Continuation?
    private var authorizationWaiters: [CheckedContinuation<CLAuthorizationStatus, Never>] = []

    private static let g = 9.80665

    public override init() {
        authorization = location.authorizationStatus
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        location.activityType = .automotiveNavigation
        location.distanceFilter = kCLDistanceFilterNone
    }

    /// Asks for "when in use" location access and returns the answer.
    @discardableResult
    public func requestPermission() async -> CLAuthorizationStatus {
        guard authorization == .notDetermined else { return authorization }
        return await withCheckedContinuation { waiter in
            authorizationWaiters.append(waiter)
            location.requestWhenInUseAuthorization()
        }
    }

    public func samples() -> AsyncStream<SensorSample> {
        stopSensors()
        let (stream, continuation) = AsyncStream<SensorSample>.makeStream(bufferingPolicy: .bufferingNewest(2000))
        self.continuation = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.stopSensors() }
        }
        location.startUpdatingLocation()
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 0.01
            motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] data, _ in
                guard let data else { return }
                MainActor.assumeIsolated { self?.handle(data) }
            }
        }
        return stream
    }

    private func handle(_ data: CMDeviceMotion) {
        let a = data.userAcceleration, g = data.gravity
        continuation?.yield(.motion(RawMotionSample(
            t: data.timestamp,
            user: SIMD3(a.x, a.y, a.z) * Self.g,
            gravity: SIMD3(g.x, g.y, g.z)
        )))
    }

    private func handle(_ fix: CLLocation) {
        // CoreMotion counts from boot; move the fix to the same clock
        let t = ProcessInfo.processInfo.systemUptime - Date().timeIntervalSince(fix.timestamp)
        let valid = fix.horizontalAccuracy >= 0
        continuation?.yield(.gps(GPSSample(
            t: t,
            speed: max(fix.speed, 0),
            speedAccuracy: fix.speedAccuracy >= 0 ? fix.speedAccuracy : (fix.speed >= 0 ? 1 : GPSSample.noSpeed),
            latitude: valid ? fix.coordinate.latitude : nil,
            longitude: valid ? fix.coordinate.longitude : nil,
            horizontalAccuracy: valid ? fix.horizontalAccuracy : nil,
            altitude: fix.verticalAccuracy >= 0 ? fix.altitude : nil
        )))
    }

    private func stopSensors() {
        motion.stopDeviceMotionUpdates()
        location.stopUpdatingLocation()
        continuation?.finish()
        continuation = nil
    }
}

extension PhoneSensorProvider: CLLocationManagerDelegate {
    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            for fix in locations { handle(fix) }
        }
    }

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorization = status
            guard status != .notDetermined else { return }
            authorizationWaiters.forEach { $0.resume(returning: status) }
            authorizationWaiters = []
        }
    }
}
#endif
