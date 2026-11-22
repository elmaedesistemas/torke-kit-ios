import XCTest
@testable import TorkeKit

final class TorkeRunTests: XCTestCase {

    func testRoundTrip() throws {
        let demo = DemoRun.generate(seed: 3)
        var run = TorkeRun(recordedAt: Date(timeIntervalSince1970: 1_800_000_000), device: "test", motion: demo.motion, gps: demo.gps)
        run.result = run.analyze()
        let back = try TorkeRun.decode(run.encoded())
        XCTAssertEqual(back, run)
    }

    func testVectorsAreArrays() throws {
        let run = TorkeRun(motion: [RawMotionSample(t: 1, user: SIMD3(1, 2, 3), gravity: SIMD3(0, 0, -1))], gps: [])
        let json = String(decoding: try run.encoded(), as: UTF8.self)
        XCTAssertTrue(json.contains(#""user":[1,2,3]"#), json)
        XCTAssertTrue(json.contains(#""format":"torke.run""#), json)
    }

    func testRejectsOtherFormatsAndNewerVersions() {
        XCTAssertThrowsError(try TorkeRun.decode(Data(#"{"format":"x","version":1,"motion":[],"gps":[]}"#.utf8)))
        XCTAssertThrowsError(try TorkeRun.decode(Data(#"{"format":"torke.run","version":99,"motion":[],"gps":[]}"#.utf8))) { error in
            XCTAssertEqual(error as? TorkeRun.FormatError, .newerVersion(99))
        }
    }

    /// The shared fixture: Android reads the same file and must get the same times.
    func testSharedFixture() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "demo-42.torkerun", withExtension: "json", subdirectory: "Resources"))
        let run = try TorkeRun.decode(Data(contentsOf: url))
        let stored = try XCTUnwrap(run.result)
        let again = try XCTUnwrap(run.analyze())
        XCTAssertEqual(again.quarterMile!, stored.quarterMile!, accuracy: 0.0005)
        XCTAssertEqual(again.sixtyFeet!, stored.sixtyFeet!, accuracy: 0.0005)
        XCTAssertEqual(again.zeroTo100!, stored.zeroTo100!, accuracy: 0.0005)
        XCTAssertEqual(again.quarterMileKmh!, stored.quarterMileKmh!, accuracy: 0.05)
    }

    /// Regenerates the fixture: `TORKE_WRITE_FIXTURE=1 swift test --filter writeFixture`.
    func testWriteFixture() throws {
        guard ProcessInfo.processInfo.environment["TORKE_WRITE_FIXTURE"] == "1" else { throw XCTSkip("set TORKE_WRITE_FIXTURE=1") }
        let demo = DemoRun.generate(seed: 42)
        var run = TorkeRun(recordedAt: Date(timeIntervalSince1970: 1_800_000_000), device: "DemoRun", app: "TorkeKit", motion: demo.motion, gps: demo.gps)
        run.result = run.analyze()
        // Keep the fixture small: the result's trace is not needed to check the times
        run.result?.trace = []
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources")
        try run.encoded().write(to: dir.appendingPathComponent("demo-42.torkerun.json"))
        let root = dir.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try run.encoded().write(to: root.appendingPathComponent("Fixtures/demo-42.torkerun.json"))
    }
}
