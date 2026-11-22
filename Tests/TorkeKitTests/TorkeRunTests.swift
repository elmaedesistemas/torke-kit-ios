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

        // Phase 2: a launch with altitudes, weather and a 4-link, a braking, and the numbers
        // both SDKs must agree on
        let weather = Weather(temperatureC: 31, humidity: 70, pressureHpa: 910)
        let setup = SuspensionSetup.fourLink(wheelbase: 106, cgHeight: 21,
                                             upperRear: Point2(x: 4, y: 21), upperFront: Point2(x: 30, y: 23),
                                             lowerRear: Point2(x: 2, y: 9), lowerFront: Point2(x: 32, y: 12))
        let sim = Simulator.constantLaunch(gpsHz: 5, altitudeSlope: 0.02)
        var launch = TorkeRun(recordedAt: Date(timeIntervalSince1970: 1_800_000_000), device: "Simulator", app: "TorkeKit",
                              motion: sim.motion, gps: sim.gps, weather: weather, suspension: setup)
        launch.result = launch.analyze()
        launch.result?.trace = []
        let brakingSim = Simulator.braking()
        var braking = TorkeRun(device: "Simulator", app: "TorkeKit", motion: brakingSim.motion, gps: brakingSim.gps)
        braking.interval = braking.braking()

        let full = try XCTUnwrap(TorkeRun(motion: sim.motion, gps: sim.gps).analyze())
        let geometry = setup.geometry()
        let quality = try XCTUnwrap(TorkeRun(motion: sim.motion, gps: sim.gps).quality())
        let target = TargetWindow(icLength: ValueRange(60, 75), icHeight: ValueRange(8, 12), antiSquat: ValueRange(80, 110))
        let holes = FourLinkHoles(
            upperRear: [Point2(x: 4, y: 21), Point2(x: 4, y: 19), Point2(x: 4, y: 17)],
            upperFront: [Point2(x: 30, y: 23), Point2(x: 30, y: 21), Point2(x: 30, y: 19)],
            lowerRear: [Point2(x: 2, y: 9), Point2(x: 2, y: 7)],
            lowerFront: [Point2(x: 32, y: 12), Point2(x: 32, y: 10), Point2(x: 32, y: 8)]
        )
        let best = try XCTUnwrap(holes.ranked(base: setup, target: target).first)
        let rolling = Simulator.rolling()
        let expected: [String: Any] = [
            "densityAltitude": weather.densityAltitude,
            "correctionFactor": weather.correctionFactor,
            "airDensity": weather.airDensity,
            "correctedQuarterMile": try XCTUnwrap(launch.result?.corrected(for: weather).quarterMile),
            "icLength": try XCTUnwrap(geometry.icLength),
            "icHeight": try XCTUnwrap(geometry.icHeight),
            "antiSquat": try XCTUnwrap(geometry.antiSquat),
            "bestHoles": best.holes,
            "bestScore": best.score,
            "qualityGrade": quality.grade.rawValue,
            "slope": try XCTUnwrap(quality.slope),
            "launchG": try XCTUnwrap(full.launchG),
            "thousandFeet": try XCTUnwrap(full.thousandFeet),
            "hpTrap": PowerEstimate.fromTrapSpeed(massKg: 1500, quarterMileKmh: 160),
            "peakWheelHp": try XCTUnwrap(PowerEstimate.peakWheelHp(full, massKg: 1200)),
            "rollingTime": try XCTUnwrap(IntervalAnalyzer.rolling(motion: rolling.motion, gps: rolling.gps)?.time),
        ]
        for (name, run) in [("launch", launch), ("braking", braking)] {
            try run.encoded().write(to: dir.appendingPathComponent("\(name).torkerun.json"))
            try run.encoded().write(to: root.appendingPathComponent("Fixtures/\(name).torkerun.json"))
        }
        // Rolling is cheap to rebuild from the simulator on each side; ship its samples too
        let rollingRun = TorkeRun(device: "Simulator", motion: rolling.motion, gps: rolling.gps)
        try rollingRun.encoded().write(to: dir.appendingPathComponent("rolling.torkerun.json"))
        try rollingRun.encoded().write(to: root.appendingPathComponent("Fixtures/rolling.torkerun.json"))
        let json = try JSONSerialization.data(withJSONObject: expected, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: dir.appendingPathComponent("phase2-expected.json"))
        try json.write(to: root.appendingPathComponent("Fixtures/phase2-expected.json"))
    }

    /// Phase 2 numbers, as written by the fixture: guards against changes in either SDK.
    func testPhaseTwoFixture() throws {
        func load(_ name: String) throws -> Data {
            try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources")))
        }
        let expected = try XCTUnwrap(JSONSerialization.jsonObject(with: load("phase2-expected")) as? [String: Any])
        func value(_ key: String) -> Double { (expected[key] as? NSNumber)?.doubleValue ?? .nan }
        let launch = try TorkeRun.decode(load("launch.torkerun"))
        let weather = try XCTUnwrap(launch.weather)
        let geometry = try XCTUnwrap(launch.suspension).geometry()
        XCTAssertEqual(weather.densityAltitude, value("densityAltitude"), accuracy: 1e-6)
        XCTAssertEqual(geometry.antiSquat!, value("antiSquat"), accuracy: 1e-9)
        XCTAssertEqual(launch.analyze()!.corrected(for: weather).quarterMile!, value("correctedQuarterMile"), accuracy: 0.0005)
        XCTAssertEqual(launch.quality()?.grade.rawValue, expected["qualityGrade"] as? String)
        let braking = try TorkeRun.decode(load("braking.torkerun"))
        XCTAssertEqual(braking.braking()!.time, braking.interval!.time, accuracy: 0.0005)
        let rolling = try TorkeRun.decode(load("rolling.torkerun"))
        XCTAssertEqual(rolling.rolling()!.time, value("rollingTime"), accuracy: 0.0005)
    }
}
