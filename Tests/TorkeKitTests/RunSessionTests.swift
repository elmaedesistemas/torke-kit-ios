import XCTest
@testable import TorkeKit

@MainActor
final class RunSessionTests: XCTestCase {

    func testDemoRunGoesThroughEveryPhase() async throws {
        let session = RunSession()
        var events: [RunEvent] = []
        session.arm()
        for sample in RecordedRunProvider.merge(RecordedRunProvider.demo().run) {
            events += session.process(sample)
            if case .finished = session.snapshot.phase { break }
        }
        // The demo may end before the session's own finish line: then the app finishes it
        if session.snapshot.phase != .finished { XCTAssertNotNil(session.finish()) }

        XCTAssertEqual(session.snapshot.phase, .finished)
        XCTAssertEqual(events.first, .armed)
        XCTAssertTrue(events.contains { if case .launched = $0 { true } else { false } })
        let marks = events.compactMap { if case let .passed(mark, _) = $0 { mark } else { nil } }
        XCTAssertEqual(marks.first, .sixtyFeet)
        XCTAssertTrue(marks.contains(.quarterMile))
        let result = try XCTUnwrap(session.snapshot.result)
        let expected = try XCTUnwrap(RecordedRunProvider.demo().run.analyze())
        XCTAssertEqual(result.quarterMile!, expected.quarterMile!, accuracy: 0.001)
    }

    func testSessionMatchesTheAnalyzer() async throws {
        let demo = RecordedRunProvider.demo(seed: 9)
        let session = RunSession()
        session.arm()
        await session.run(with: demo)
        let expected = try XCTUnwrap(demo.run.analyze())
        let result = try XCTUnwrap(session.snapshot.result)
        // The session stops at its own finish line, so the trace is shorter but the times match
        XCTAssertEqual(result.quarterMile!, expected.quarterMile!, accuracy: 0.001)
        XCTAssertEqual(result.sixtyFeet!, expected.sixtyFeet!, accuracy: 0.001)
    }

    func testWithoutArmingNothingIsRecorded() {
        let session = RunSession()
        let demo = RecordedRunProvider.demo().run
        for sample in RecordedRunProvider.merge(demo) { XCTAssertEqual(session.process(sample), []) }
        XCTAssertEqual(session.snapshot.phase, .idle)
        XCTAssertTrue(session.recording().motion.isEmpty)
    }

    func testMovingBeforeTheLaunchDisarms() {
        let session = RunSession()
        session.arm()
        var events: [RunEvent] = []
        let still = RawMotionSample(t: 0, user: .zero, gravity: SIMD3(0, 0, -1))
        for i in 0..<150 { var s = still; s.t = Double(i) / 100; events += session.process(motion: s) }
        XCTAssertEqual(events, [.armed])
        // A single bump does not disarm
        events += session.process(motion: RawMotionSample(t: 1.5, user: SIMD3(1, 0, 0), gravity: SIMD3(0, 0, -1)))
        events += session.process(motion: RawMotionSample(t: 1.51, user: .zero, gravity: SIMD3(0, 0, -1)))
        XCTAssertEqual(session.snapshot.phase, .armed)
        // Creeping forward without a launch does
        for i in 0..<80 {
            events += session.process(motion: RawMotionSample(t: 1.6 + Double(i) / 100, user: SIMD3(1, 0, 0), gravity: SIMD3(0, 0, -1)))
        }
        XCTAssertEqual(events.last, .disarmed)
        XCTAssertEqual(session.snapshot.phase, .waitingStill)
    }

    /// A launch that ramps up, like a real car, must still be caught.
    func testRampedLaunchIsDetected() {
        let session = RunSession()
        session.arm()
        var events: [RunEvent] = []
        for i in 0..<400 {
            let t = Double(i) / 100
            let a = t < 2 ? 0 : min(6, (t - 2) * 20)   // 0 to 6 m/s² in 0.3 s
            events += session.process(motion: RawMotionSample(t: t, user: SIMD3(0, a, 0), gravity: SIMD3(0, 0, -1)))
        }
        let launch = events.compactMap { if case let .launched(time, _) = $0 { time } else { nil } }.first
        XCTAssertNotNil(launch, "\(events)")
        XCTAssertEqual(launch ?? 0, 2.03, accuracy: 0.05)
        XCTAssertFalse(events.contains(.disarmed))
    }

    func testFinishingWithoutALaunchFails() {
        let session = RunSession()
        session.arm()
        XCTAssertNil(session.finish())
        XCTAssertEqual(session.snapshot.phase, .failed(.noLaunch))
    }

    func testEventsStream() async {
        let session = RunSession()
        let stream = session.events()
        session.arm()
        await session.run(with: RecordedRunProvider.demo())
        var seen: [RunEvent] = []
        for await event in stream {
            seen.append(event)
            if case .finished = event { break }
            if case .failed = event { break }
        }
        XCTAssertEqual(seen.first, .armed)
        guard case .finished = seen.last else { return XCTFail("\(seen)") }
    }

    func testGpsWithoutSpeedOnlyMovesTheLocation() {
        let session = RunSession()
        session.process(gps: GPSSample(t: 1, speed: 3, speedAccuracy: 0.5))
        session.process(gps: GPSSample(t: 2, speed: 0, speedAccuracy: GPSSample.noSpeed, latitude: 9.9, longitude: -84.1))
        XCTAssertEqual(session.snapshot.speed, 3)
        XCTAssertEqual(session.snapshot.location, Coordinate(latitude: 9.9, longitude: -84.1))
    }
}
