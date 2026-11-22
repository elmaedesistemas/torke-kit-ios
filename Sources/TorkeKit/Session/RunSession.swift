import Foundation
import Observation

/// The SDK's front door: connect a sensor source, ``arm()``, read ``snapshot`` and listen to
/// ``events()``. The session spots the standstill, the launch and the end by itself, then
/// computes the official times with ``RunAnalyzer``.
///
/// ```swift
/// let session = RunSession()
/// session.start(with: PhoneSensorProvider())   // GPS preview from here
/// session.arm()                                // recording; times start at launch
/// for await event in session.events() {
///     if case .finished(let result) = event { print(result.quarterMile ?? 0) }
/// }
/// ```
@available(iOS 17.0, macOS 14.0, *)
@MainActor
@Observable
public final class RunSession {
    public private(set) var snapshot = RunSnapshot()
    @ObservationIgnored public var options: RunSessionOptions

    @ObservationIgnored private var motion: [RawMotionSample] = []
    @ObservationIgnored private var gps: [GPSSample] = []
    @ObservationIgnored private var peakSpeed = 0.0
    @ObservationIgnored private var passed: Set<DragMark> = []
    @ObservationIgnored private var recordedAt: Date?
    @ObservationIgnored private var movementStart: TimeInterval?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var listeners: [UUID: AsyncStream<RunEvent>.Continuation] = [:]

    public init(options: RunSessionOptions = RunSessionOptions()) {
        self.options = options
    }

    // MARK: - Source

    /// Starts reading a source in the background. Calling it again replaces the previous one.
    /// If the source ends during a run, the run finishes.
    public func start(with provider: some RunDataProvider) {
        stop()
        let stream = provider.samples()
        task = Task { [weak self] in
            for await sample in stream {
                if Task.isCancelled { break }
                self?.process(sample)
            }
            if !Task.isCancelled { self?.finish() }
        }
    }

    /// Reads a source until it ends, then finishes the run. Use it when you manage the task
    /// yourself, and in tests.
    public func run(with provider: some RunDataProvider) async {
        for await sample in provider.samples() {
            if Task.isCancelled { return }
            process(sample)
        }
        finish()
    }

    /// Stops reading the source. A run in progress is cancelled.
    public func stop() {
        task?.cancel()
        task = nil
        if snapshot.phase.isRecording { cancel() }
    }

    // MARK: - Run

    /// Starts recording. The timer starts by itself when the car launches from a standstill.
    public func arm() {
        clear()
        recordedAt = Date()
        snapshot.phase = .waitingStill
    }

    /// Ends the run now and computes the times. Without a launch it fails with
    /// ``RunFailure/noLaunch``.
    @discardableResult
    public func finish() -> RunResult? {
        guard snapshot.phase.isRecording else { return snapshot.result }
        guard case .running = snapshot.phase, let result = RunAnalyzer.analyze(motion: AxisCalibration.forwardAccel(motion), gps: gps) else {
            fail(.noLaunch)
            return nil
        }
        snapshot.result = result
        snapshot.phase = .finished
        emit(.finished(result))
        return result
    }

    /// Drops the run and goes back to ``RunPhase/idle``.
    public func cancel() {
        clear()
    }

    /// Marks the run as failed, for errors the app finds (permissions, sensors).
    public func fail(_ failure: RunFailure) {
        snapshot.phase = .failed(failure)
        emit(.failed(failure))
    }

    /// Everything recorded since ``arm()``, ready to save, share or replay with
    /// ``RecordedRunProvider``.
    public func recording(device: String? = nil, app: String? = nil) -> TorkeRun {
        TorkeRun(recordedAt: recordedAt, device: device, app: app, motion: motion, gps: gps, result: snapshot.result)
    }

    // MARK: - Samples

    /// Feeds one sample by hand. Returns what happened on it.
    @discardableResult
    public func process(_ sample: SensorSample) -> [RunEvent] {
        switch sample {
        case let .motion(m): return process(motion: m)
        case let .gps(g): return process(gps: g)
        }
    }

    @discardableResult
    public func process(motion sample: RawMotionSample) -> [RunEvent] {
        guard snapshot.phase.isRecording else { return [] }
        motion.append(sample)
        var events: [RunEvent] = []
        let o = options

        switch snapshot.phase {
        case .waitingStill:
            if isStill(until: sample.t) {
                snapshot.phase = .armed
                events.append(.armed)
            }
        case .armed:
            // A launch is movement that starts strong and holds. Movement that does not
            // become a launch in time disarms; a bump that goes away does not.
            let horizontal = AxisCalibration.horizontalMagnitude(sample)
            if horizontal >= o.stillAccel {
                let moved = movementStart ?? sample.t
                movementStart = moved
                if horizontal > o.launchAccel, sample.t - moved >= o.launchHold, sustained(from: sample.t - o.launchHold) {
                    snapshot.phase = .running(start: moved)
                    snapshot.startLocation = snapshot.location
                    movementStart = nil
                    events.append(.launched(time: moved, location: snapshot.location))
                } else if sample.t - moved > o.launchHold + o.launchGrace {
                    disarm(&events)
                }
            } else {
                movementStart = nil
            }
        case let .running(start):
            snapshot.elapsed = sample.t - start
            let byDistance = snapshot.distance > o.finishDistance
            let backedOff = peakSpeed > 11 && snapshot.speed < peakSpeed * o.backOffRatio
            if byDistance || backedOff || snapshot.elapsed > o.maxDuration {
                events.forEach(emit)
                finish()
                return events + (snapshot.phase == .finished ? [.finished(snapshot.result!)] : [.failed(.noLaunch)])
            }
        default:
            break
        }
        // While waiting, only the last minute of samples matters
        if snapshot.phase == .waitingStill, motion.count > 6000 { motion.removeFirst(1000) }
        events.forEach(emit)
        return events
    }

    @discardableResult
    public func process(gps sample: GPSSample) -> [RunEvent] {
        if let accuracy = sample.horizontalAccuracy { snapshot.gpsAccuracy = accuracy }
        if let coordinate = sample.coordinate { snapshot.location = coordinate }
        // A fix without speed still moves the location, but nothing else
        guard sample.hasSpeed else { return [] }
        snapshot.speed = sample.speed
        guard snapshot.phase.isRecording else { return [] }

        var events: [RunEvent] = []
        // Rolling before the launch: wait for a standstill again
        if snapshot.phase == .armed, sample.speed >= options.stillSpeed { disarm(&events) }
        if case let .running(start) = snapshot.phase, let last = gps.last {
            snapshot.distance += (sample.speed + last.speed) / 2 * (sample.t - max(last.t, start))
            peakSpeed = max(peakSpeed, sample.speed)
            let elapsed = sample.t - start
            let marks: [(DragMark, Bool)] = [
                (.sixtyFeet, snapshot.distance >= DragDistance.sixtyFeet),
                (.zeroTo100, sample.speed >= DragDistance.speed100),
                (.eighthMile, snapshot.distance >= DragDistance.eighthMile),
                (.quarterMile, snapshot.distance >= DragDistance.quarterMile),
            ]
            for (mark, reached) in marks where reached && !passed.contains(mark) {
                passed.insert(mark)
                events.append(.passed(mark, elapsed: elapsed))
            }
        }
        gps.append(sample)
        events.forEach(emit)
        return events
    }

    // MARK: - Events

    /// A stream of everything that happens from now on. Each call gets its own stream.
    public func events() -> AsyncStream<RunEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<RunEvent>.makeStream()
        listeners[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.listeners[id] = nil }
        }
        return stream
    }

    private func emit(_ event: RunEvent) {
        for continuation in listeners.values { continuation.yield(event) }
    }

    // MARK: - Detection

    /// `stillWindow` seconds without noticeable acceleration and the GPS near zero.
    private func isStill(until t: TimeInterval) -> Bool {
        var count = 0
        for sample in motion.reversed() {
            if sample.t <= t - options.stillWindow { break }
            if AxisCalibration.horizontalMagnitude(sample) >= options.stillAccel { return false }
            count += 1
        }
        return count >= Int(options.stillWindow * 80) && (gps.last?.speed ?? 0) < options.stillSpeed
    }

    private func sustained(from t: TimeInterval) -> Bool {
        var count = 0
        for sample in motion.reversed() {
            if sample.t < t { break }
            if AxisCalibration.horizontalMagnitude(sample) <= options.launchHoldAccel { return false }
            count += 1
        }
        return count >= 10
    }

    private func disarm(_ events: inout [RunEvent]) {
        snapshot.phase = .waitingStill
        movementStart = nil
        events.append(.disarmed)
    }

    private func clear() {
        movementStart = nil
        motion = []
        gps = []
        peakSpeed = 0
        passed = []
        recordedAt = nil
        var fresh = RunSnapshot()
        fresh.gpsAccuracy = snapshot.gpsAccuracy
        fresh.location = snapshot.location
        fresh.speed = snapshot.speed
        snapshot = fresh
    }
}
