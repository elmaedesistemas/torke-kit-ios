import XCTest
@testable import TorkeKit

/// A round circuit: 200 m radius around a point in Costa Rica, counterclockwise.
enum Circuit {
    static let center = Coordinate(latitude: 9.9412, longitude: -84.2005)
    static let radius = 200.0

    static func coordinate(angle: Double, r: Double = radius) -> Coordinate {
        let x = r * cos(angle), y = r * sin(angle)
        let lat = center.latitude + y / Geo.earthRadius * 180 / .pi
        let lon = center.longitude + x / (Geo.earthRadius * cos(center.latitude * .pi / 180)) * 180 / .pi
        return Coordinate(latitude: lat, longitude: lon)
    }

    static func line(angle: Double) -> TimingLine {
        TimingLine(a: coordinate(angle: angle, r: radius - 20), b: coordinate(angle: angle, r: radius + 20))
    }

    /// Fixes at `hz` while driving `speeds.count` laps, one speed (m/s) per lap, from 10° before the line.
    static func fixes(hz: Double, speeds: [Double]) -> [GPSSample] {
        var out: [GPSSample] = []
        let start = -10 * Double.pi / 180
        var t = 0.0, angle = start
        let end = start + Double(speeds.count) * 2 * .pi + 0.3
        let dt = 1 / hz
        while angle < end {
            let c = coordinate(angle: angle)
            out.append(GPSSample(t: t, speed: 0, speedAccuracy: 0.3, latitude: c.latitude, longitude: c.longitude, horizontalAccuracy: 2))
            // Each timed lap (from the line at angle 0) at its own speed
            let lap = min(Int(max(angle, 0) / (2 * .pi)), speeds.count - 1)
            angle += speeds[lap] / radius * dt
            t += dt
        }
        return out
    }

    /// Exact lap time for a lap at constant `v`.
    static func lapTime(_ v: Double) -> Double { 2 * .pi * radius / v }
}

final class LapTimerTests: XCTestCase {
    private func timer(sectors: Bool = true) -> LapTimer {
        LapTimer(start: Circuit.line(angle: 0), sectors: sectors ? [Circuit.line(angle: 2 * .pi / 3), Circuit.line(angle: 4 * .pi / 3)] : [])
    }

    func testLapTimesAt10And1Hz() {
        for (hz, tolerance) in [(10.0, 0.02), (1.0, 0.1)] {
            let lt = timer()
            var events: [LapEvent] = []
            for f in Circuit.fixes(hz: hz, speeds: [30, 30, 30]) { events += lt.process(f) }
            XCTAssertEqual(lt.laps.count, 3, "\(hz) Hz") // the first crossing only starts timing
            for lap in lt.laps { XCTAssertEqual(lap.time, Circuit.lapTime(30), accuracy: tolerance, "\(hz) Hz") }
            XCTAssertEqual(lt.laps[0].distance, 2 * .pi * Circuit.radius, accuracy: 2 * .pi * Circuit.radius * 0.01)
            if case .started = events.first {} else { XCTFail("first event: \(String(describing: events.first))") }
        }
    }

    func testSectorsAddUpToTheLap() throws {
        let lt = timer()
        Circuit.fixes(hz: 10, speeds: [30, 30]).forEach { lt.process($0) }
        let lap = try XCTUnwrap(lt.laps.first)
        XCTAssertEqual(lap.sectors.count, 3)
        for s in lap.sectors { XCTAssertEqual(s, Circuit.lapTime(30) / 3, accuracy: 0.03) }
        XCTAssertEqual(lap.sectors.reduce(0, +), lap.time, accuracy: 1e-9)
    }

    func testDeltaAndPredictedLap() throws {
        let lt = timer(sectors: false)
        let fixes = Circuit.fixes(hz: 10, speeds: [30, 32, 32])
        var midLapDelta: Double?
        for f in fixes {
            lt.process(f)
            // Halfway through the second timed lap (faster), compare with the first
            if lt.laps.count == 1, let e = lt.elapsed(at: f.t), e > Circuit.lapTime(32) / 2, midLapDelta == nil {
                midLapDelta = lt.delta
                // The best lap plus what was gained so far: the rest is assumed at the best lap's pace
                let predicted = try XCTUnwrap(lt.predictedLap)
                XCTAssertEqual(predicted, try lt.laps[0].time + XCTUnwrap(midLapDelta), accuracy: 1e-9)
                XCTAssertLessThan(predicted, Circuit.lapTime(30))
            }
        }
        // Half a lap at 32 instead of 30 m/s
        let half = Circuit.lapTime(32) / 2 - Circuit.lapTime(30) / 2
        XCTAssertEqual(try XCTUnwrap(midLapDelta), half, accuracy: 0.15)
        XCTAssertNotEqual(lt.bestLap?.number, 1)
    }

    func testIgnoresJitterOnTheLine() {
        let lt = timer(sectors: false)
        let line = Circuit.line(angle: 0)
        // Back and forth over the line within a second
        let a = Circuit.coordinate(angle: -0.01), b = Circuit.coordinate(angle: 0.01)
        for (i, c) in [a, b, a, b].enumerated() {
            lt.process(GPSSample(t: Double(i) * 0.3, speed: 0, speedAccuracy: 1, latitude: c.latitude, longitude: c.longitude))
        }
        XCTAssertTrue(lt.laps.isEmpty)
        XCTAssertNotNil(LapTimer.crossing(a, b, line))
    }
}

final class ChristmasTreeTests: XCTestCase {
    func testLightSchedules() {
        let pro = ChristmasTree(type: .pro, activatedAt: 10)
        XCTAssertEqual(pro.lights.map(\.time), [10, 10, 10, 10.4])
        XCTAssertEqual(pro.greenAt, 10.4, accuracy: 1e-12)
        let sportsman = ChristmasTree(type: .sportsman, activatedAt: 10)
        XCTAssertEqual(sportsman.lights.map(\.time), [10, 10.5, 11, 11.5])
        XCTAssertEqual(sportsman.lit(at: 10.7), [.amber1, .amber2])
        XCTAssertEqual(sportsman.lit(at: 11.6), [.green])
        XCTAssertEqual(sportsman.lit(at: 9), [])
    }

    func testSeededStartIsRepeatable() {
        let a = ChristmasTree.start(type: .pro, stagedAt: 5, seed: 42)
        XCTAssertEqual(a, ChristmasTree.start(type: .pro, stagedAt: 5, seed: 42))
        XCTAssertTrue((5.6...6.1).contains(a.activatedAt))
    }

    func testReactionFromTheDemoRun() throws {
        let run = DemoRun.generate()
        let r = try XCTUnwrap(RunAnalyzer.analyze(motion: AxisCalibration.forwardAccel(run.motion), gps: run.gps))
        let left = try XCTUnwrap(r.leftStageAt)
        XCTAssertGreaterThan(left, r.launchTime)
        let perfect = ChristmasTree(type: .pro, activatedAt: left - 0.4)
        XCTAssertTrue(try XCTUnwrap(r.reaction(on: perfect)).isPerfect)
        let late = ChristmasTree(type: .pro, activatedAt: left - 0.4 - 0.237)
        XCTAssertEqual(try XCTUnwrap(r.reaction(on: late)).time, 0.237, accuracy: 1e-9)
        let red = ChristmasTree(type: .sportsman, activatedAt: left - 1.5 + 0.02)
        XCTAssertTrue(try XCTUnwrap(r.reaction(on: red)).isRedLight)
        XCTAssertEqual(try XCTUnwrap(r.package(on: late)), 0.237 + r.quarterMile!, accuracy: 1e-9)
    }
}

final class GeofenceTests: XCTestCase {
    func testCircleAndPolygon() {
        let circle = Geofence.circle(center: Circuit.center, radius: 250, name: "Óvalo")
        XCTAssertTrue(circle.contains(Circuit.coordinate(angle: 1)))
        XCTAssertFalse(circle.contains(Circuit.coordinate(angle: 1, r: 300)))
        let square = Geofence.polygon([0.25, 0.75, 1.25, 1.75].map { Circuit.coordinate(angle: $0 * .pi, r: 300) })
        XCTAssertTrue(square.contains(Circuit.center))
        XCTAssertTrue(square.contains(Circuit.coordinate(angle: 0.3, r: 200)))
        XCTAssertFalse(square.contains(Circuit.coordinate(angle: 0, r: 290)))   // inside the circle, outside the square's edge
        XCTAssertFalse(square.contains(Circuit.coordinate(angle: 0.25 * .pi, r: 320)))
        XCTAssertEqual([square, circle].first(containing: Circuit.center)?.kind, .polygon)
        XCTAssertNil([circle].first(containing: Circuit.coordinate(angle: 0, r: 400)))
    }

    func testJSONShape() throws {
        let data = try JSONEncoder().encode(Geofence.circle(center: Circuit.center, radius: 300))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["kind"] as? String, "circle")
        XCTAssertEqual(json["radius"] as? Double, 300)
        XCTAssertNil(json["points"])
    }

    func testRunCheck() throws {
        let launch = try TorkeRun.decode(Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "launch.torkerun", withExtension: "json", subdirectory: "Resources"))))
        let start = try XCTUnwrap(launch.startLocation)
        let big = Geofence.circle(center: start, radius: 2000)
        let check = try XCTUnwrap(launch.check(big))
        XCTAssertTrue(check.startInside)
        XCTAssertTrue(check.allInside)
        let far = Coordinate(latitude: start.latitude + 0.05, longitude: start.longitude)
        let elsewhere = try XCTUnwrap(launch.check(.circle(center: far, radius: 300)))
        XCTAssertFalse(elsewhere.startInside)
        XCTAssertEqual(elsewhere.shareInside, 0)
    }
}

final class PhaseFourFixtureTests: XCTestCase {
    private static let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources")

    /// The circuit, the lines, the geofences and the numbers TorkeKit for Android must match:
    /// `TORKE_WRITE_FIXTURE=1 swift test --filter testWritePhaseFourFixture`.
    func testWritePhaseFourFixture() throws {
        guard ProcessInfo.processInfo.environment["TORKE_WRITE_FIXTURE"] == "1" else { throw XCTSkip("set TORKE_WRITE_FIXTURE=1") }
        let circuit = TorkeRun(device: "Simulator", app: "TorkeKit", motion: [], gps: Circuit.fixes(hz: 5, speeds: [30, 32, 31]))
        let start = Circuit.line(angle: 0)
        let sectors = [Circuit.line(angle: 2 * .pi / 3), Circuit.line(angle: 4 * .pi / 3)]
        let timer = LapTimer(start: start, sectors: sectors)
        var deltas: [Double] = []
        for f in circuit.gps {
            timer.process(f)
            if timer.laps.count == 1, let d = timer.delta, deltas.count < 5, Int(f.t * 5) % 40 == 0 { deltas.append(d) }
        }
        let fences = [Geofence.circle(center: Circuit.center, radius: 250, name: "circle"),
                      Geofence.polygon([0.25, 0.75, 1.25, 1.75].map { Circuit.coordinate(angle: $0 * .pi, r: 300) }, name: "square")]
        let probes = [Circuit.center, Circuit.coordinate(angle: 0, r: 290), Circuit.coordinate(angle: 1, r: 240), Circuit.coordinate(angle: 0.25 * .pi, r: 320)]
        let demo = try TorkeRun.decode(Data(contentsOf: Self.resources.appendingPathComponent("demo-42.torkerun.json")))
        let demoResult = try XCTUnwrap(demo.analyze())
        let tree = ChristmasTree(type: .sportsman, activatedAt: 1.0)
        let seeded = ChristmasTree.start(type: .pro, stagedAt: 5, seed: 42)

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        func json<T: Encodable>(_ v: T) throws -> Any { try JSONSerialization.jsonObject(with: enc.encode(v)) }
        let expected: [String: Any] = [
            "start": try json(start),
            "sectors": try json(sectors),
            "geofences": try json(fences),
            "probes": try json(probes),
            "contains": fences.map { f in probes.map(f.contains) },
            "lapTimes": timer.laps.map(\.time),
            "lapSectors": timer.laps.map(\.sectors),
            "lapDistances": timer.laps.map(\.distance),
            "deltas": deltas,
            "seededActivatedAt": seeded.activatedAt,
            "demoLeftStageAt": try XCTUnwrap(demoResult.leftStageAt),
            "demoReactionSportsmanAt1": try XCTUnwrap(demoResult.reaction(on: tree)).time,
        ]
        let root = Self.resources.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try JSONSerialization.data(withJSONObject: expected, options: [.prettyPrinted, .sortedKeys])
        for dir in [Self.resources, root.appendingPathComponent("Fixtures")] {
            try circuit.encoded().write(to: dir.appendingPathComponent("circuit.torkerun.json"))
            try data.write(to: dir.appendingPathComponent("phase4-expected.json"))
        }
    }

    func testPhaseFourFixture() throws {
        let expected = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: Self.resources.appendingPathComponent("phase4-expected.json"))) as? [String: Any])
        func decode<T: Decodable>(_ key: String, as: T.Type) throws -> T {
            try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: XCTUnwrap(expected[key])))
        }
        let circuit = try TorkeRun.decode(Data(contentsOf: Self.resources.appendingPathComponent("circuit.torkerun.json")))
        let timer = LapTimer(start: try decode("start", as: TimingLine.self), sectors: try decode("sectors", as: [TimingLine].self))
        circuit.gps.forEach { timer.process($0) }
        let lapTimes = try XCTUnwrap(expected["lapTimes"] as? [Double])
        XCTAssertEqual(timer.laps.count, lapTimes.count)
        for (lap, t) in zip(timer.laps, lapTimes) { XCTAssertEqual(lap.time, t, accuracy: 1e-6) }
        let fences = try decode("geofences", as: [Geofence].self)
        let probes = try decode("probes", as: [Coordinate].self)
        XCTAssertEqual(fences.map { f in probes.map(f.contains) }, try XCTUnwrap(expected["contains"] as? [[Bool]]))
    }
}
