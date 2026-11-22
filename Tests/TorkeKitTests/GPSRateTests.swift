import XCTest
@testable import TorkeKit

final class GPSRateTests: XCTestCase {
    @MainActor
    func testSnapshotReportsTheGPSRate() {
        for hz in [1.0, 5.0, 10.0] {
            let sim = Simulator.constantLaunch(gpsHz: hz)
            let session = RunSession()
            XCTAssertNil(session.snapshot.gpsRate)
            session.arm()
            for s in RecordedRunProvider.merge(TorkeRun(motion: sim.motion, gps: sim.gps)) { session.process(s) }
            XCTAssertEqual(session.snapshot.gpsRate ?? 0, hz, accuracy: hz * 0.05, "\(hz) Hz")
        }
    }

    /// A faster GPS keeps the quarter mile on target too (the engine is rate-agnostic).
    func testFasterGPSStaysAccurate() throws {
        for hz in [1.0, 10.0] {
            let sim = Simulator.constantLaunch(gpsHz: hz)
            let r = try XCTUnwrap(RunAnalyzer.analyze(motion: AxisCalibration.forwardAccel(sim.motion), gps: sim.gps))
            let rollout = (2 * DragDistance.rollout / 5).squareRoot()
            XCTAssertEqual(try XCTUnwrap(r.quarterMile), (2 * DragDistance.quarterMile / 5).squareRoot() - rollout, accuracy: 0.15, "\(hz) Hz")
        }
    }
}
