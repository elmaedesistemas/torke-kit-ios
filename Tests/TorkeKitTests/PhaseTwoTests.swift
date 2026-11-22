import XCTest
@testable import TorkeKit

final class MarksTests: XCTestCase {
    func testExtraMarksMatchPhysics() throws {
        let sim = Simulator.constantLaunch(duration: 30)
        let r = try XCTUnwrap(RunAnalyzer.analyze(motion: AxisCalibration.forwardAccel(sim.motion), gps: sim.gps, stopDistance: 850))
        // Constant 5 m/s² from rest: t = sqrt(2d/a); speed t = v/a
        let rollout = (2 * DragDistance.rollout / 5).squareRoot()
        XCTAssertEqual(try XCTUnwrap(r.thousandFeet), (2 * DragDistance.thousandFeet / 5).squareRoot() - rollout, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(r.halfMile), (2 * DragDistance.halfMile / 5).squareRoot() - rollout, accuracy: 0.08)
        XCTAssertEqual(try XCTUnwrap(r.zeroTo60mph), DragDistance.speed60mph / 5, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(r.time(fromKmh: 100, toKmh: 200)), 100 / 3.6 / 5, accuracy: 0.08)
        XCTAssertEqual(try XCTUnwrap(r.speedKmh(atDistance: 100)), (2 * 5 * 100.0).squareRoot() * 3.6, accuracy: 1.5)
        XCTAssertNil(RunAnalyzer.analyze(motion: AxisCalibration.forwardAccel(sim.motion), gps: sim.gps)?.halfMile)
    }

    func testGForces() throws {
        let sim = Simulator.constantLaunch()
        let r = try XCTUnwrap(RunAnalyzer.analyze(motion: AxisCalibration.forwardAccel(sim.motion), gps: sim.gps))
        XCTAssertEqual(try XCTUnwrap(r.launchG), 5 / DragDistance.g, accuracy: 0.04)
        XCTAssertEqual(try XCTUnwrap(r.peakG), 5 / DragDistance.g, accuracy: 0.04)
    }
}

final class IntervalTests: XCTestCase {
    func testRolling60to130() throws {
        let sim = Simulator.rolling()
        let r = try XCTUnwrap(IntervalAnalyzer.rolling(motion: sim.motion, gps: sim.gps, fromKmh: 60, toKmh: 130))
        XCTAssertEqual(r.kind, .rolling)
        XCTAssertEqual(r.time, 70 / 3.6 / 3, accuracy: 0.15)
        let v0 = 60 / 3.6, v1 = 130 / 3.6
        XCTAssertEqual(r.distance, (v1 * v1 - v0 * v0) / (2 * 3), accuracy: 4)
        XCTAssertEqual(r.peakG, 3 / DragDistance.g, accuracy: 0.05)
    }

    func testBraking100to0() throws {
        let sim = Simulator.braking()
        let r = try XCTUnwrap(IntervalAnalyzer.braking(motion: sim.motion, gps: sim.gps, fromKmh: 100))
        XCTAssertEqual(r.kind, .braking)
        XCTAssertEqual(r.time, 100 / 3.6 / 8, accuracy: 0.15)
        XCTAssertEqual(r.distance, pow(100 / 3.6, 2) / 16, accuracy: 2.5)
        XCTAssertEqual(r.peakG, 8 / DragDistance.g, accuracy: 0.08)
    }

    func testNoIntervalWhenTheRangeIsNotCovered() {
        let sim = Simulator.rolling()
        XCTAssertNil(IntervalAnalyzer.rolling(motion: sim.motion, gps: sim.gps, fromKmh: 60, toKmh: 250))
        XCTAssertNil(IntervalAnalyzer.braking(motion: sim.motion, gps: sim.gps))
    }

    @MainActor
    func testSessionInRollingAndBrakingModes() {
        let rolling = Simulator.rolling()
        let session = RunSession()
        session.arm(mode: .rolling(fromKmh: 60, toKmh: 130))
        var events: [RunEvent] = []
        for s in RecordedRunProvider.merge(TorkeRun(motion: rolling.motion, gps: rolling.gps)) { events += session.process(s) }
        XCTAssertEqual(session.snapshot.phase, .finished)
        XCTAssertEqual(session.snapshot.interval?.time ?? 0, 70 / 3.6 / 3, accuracy: 0.2)
        XCTAssertTrue(events.contains { if case .intervalFinished = $0 { true } else { false } })

        let braking = Simulator.braking()
        session.arm(mode: .braking(fromKmh: 100))
        for s in RecordedRunProvider.merge(TorkeRun(motion: braking.motion, gps: braking.gps)) { session.process(s) }
        XCTAssertEqual(session.snapshot.phase, .finished)
        XCTAssertEqual(session.snapshot.interval?.time ?? 0, 100 / 3.6 / 8, accuracy: 0.2)
        XCTAssertEqual(session.recording().interval, session.snapshot.interval)
    }
}

final class WeatherAndPowerTests: XCTestCase {
    func testStandardAirNeedsNoCorrection() {
        let standard = Weather(temperatureC: 25, humidity: 0, pressureHpa: 990)
        XCTAssertEqual(standard.correctionFactor, 1, accuracy: 1e-9)
        XCTAssertEqual(standard.corrected(time: 12), 12, accuracy: 1e-9)
    }

    func testDensityAltitude() {
        XCTAssertEqual(Weather(temperatureC: 15, humidity: 0, pressureHpa: 1013.25).densityAltitude, 0, accuracy: 15)
        // A hot, humid afternoon at Parque Viva's height (~900 m): thin air
        let hot = Weather(temperatureC: 31, humidity: 70, pressureHpa: 910)
        XCTAssertGreaterThan(hot.densityAltitude, 1600)
        XCTAssertLessThan(hot.densityAltitude, 2100)
        XCTAssertGreaterThan(hot.correctionFactor, 1.1)
        let r = RunResult(launchTime: 0, zeroTo100: 6, sixtyFeet: 2, eighthMile: 9, eighthMileKmh: 130, quarterMile: 14, quarterMileKmh: 160, topSpeedKmh: 165, accelBias: 0, trace: [])
        let c = r.corrected(for: hot)
        XCTAssertLessThan(c.quarterMile!, 14)
        XCTAssertGreaterThan(c.quarterMileKmh!, 160)
    }

    func testPower() throws {
        // Hale: 1500 kg (3307 lb) at 160 km/h (99.4 mph) → 3307 × (99.4/234)³
        XCTAssertEqual(PowerEstimate.fromTrapSpeed(massKg: 1500, quarterMileKmh: 160), 3306.93 * pow(99.419 / 234, 3), accuracy: 1)
        XCTAssertEqual(PowerEstimate.fromElapsedTime(massKg: 1500, quarterMile: 14), 3306.93 * pow(5.825 / 14, 3), accuracy: 1)
        // m·a·v with no drag: 1000 kg at 5 m/s² pushes with 5000 N, so power / speed ≈ 5000
        let sim = Simulator.constantLaunch()
        let r = try XCTUnwrap(RunAnalyzer.analyze(motion: AxisCalibration.forwardAccel(sim.motion), gps: sim.gps))
        let curve = PowerEstimate.wheelPower(r, massKg: 1000, dragArea: 0, rollingResistance: 0)
            .filter { $0.speedKmh > 40 && $0.speedKmh < 160 }
        let force = curve.map { $0.watts / ($0.speedKmh / 3.6) }.reduce(0, +) / Double(curve.count)
        XCTAssertEqual(force, 5000, accuracy: 250)
        let peak = try XCTUnwrap(PowerEstimate.peakWheelHp(r, massKg: 1000, dragArea: 0, rollingResistance: 0))
        XCTAssertGreaterThan(peak, 5000 * 40 / PowerEstimate.wattsPerHp)
    }
}

final class QualityTests: XCTestCase {
    func testCleanRunIsGood() throws {
        let sim = Simulator.constantLaunch(gpsHz: 5, altitudeSlope: 0)
        let q = try XCTUnwrap(TorkeRun(motion: sim.motion, gps: sim.gps).quality())
        XCTAssertEqual(q.grade, .good, "\(q.issues)")
        XCTAssertEqual(q.slope ?? 1, 0, accuracy: 0.002)
    }

    func testSlopeIsFlagged() throws {
        let sim = Simulator.constantLaunch(gpsHz: 5, altitudeSlope: 0.03)
        let q = try XCTUnwrap(TorkeRun(motion: sim.motion, gps: sim.gps).quality())
        XCTAssertEqual(q.slope ?? 0, 0.03, accuracy: 0.005)
        XCTAssertTrue(q.issues.contains(.slope))
        XCTAssertEqual(q.grade, .fair)
    }

    func testPhoneMovingMakesItPoor() throws {
        let sim = Simulator.constantLaunch(gpsHz: 5, tiltAfter: 6)
        let q = try XCTUnwrap(TorkeRun(motion: sim.motion, gps: sim.gps).quality())
        XCTAssertTrue(q.issues.contains(.phoneMoved), "\(q.issues)")
        XCTAssertEqual(q.grade, .poor)
    }

    func testDropoutIsFlagged() throws {
        var sim = Simulator.constantLaunch(gpsHz: 5)
        sim.gps.removeAll { $0.t > 5 && $0.t < 9 }
        let q = try XCTUnwrap(TorkeRun(motion: sim.motion, gps: sim.gps).quality())
        XCTAssertTrue(q.issues.contains(.gpsDropout))
        XCTAssertEqual(q.grade, .poor)
    }
}

final class SuspensionTests: XCTestCase {
    // Upper: y = 20 + 0.1x, lower: y = 10 + 0.2x → they meet at (100, 30)
    let fourLink = SuspensionSetup.fourLink(
        wheelbase: 100, cgHeight: 20,
        upperRear: Point2(x: 0, y: 20), upperFront: Point2(x: 20, y: 22),
        lowerRear: Point2(x: 0, y: 10), lowerFront: Point2(x: 20, y: 14)
    )

    func testFourLinkInstantCenterAndAntiSquat() throws {
        let g = fourLink.geometry()
        XCTAssertEqual(try XCTUnwrap(g.icLength), 100, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(g.icHeight), 30, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(g.antiSquat), 150, accuracy: 1e-9)   // (30/100)/(20/100)
        XCTAssertEqual(g.bars.first { $0.name == "upper" }!.angle, atan(0.1) * 180 / .pi, accuracy: 1e-9)
        XCTAssertTrue(g.warnings.isEmpty)
    }

    func testParallelBarsHaveNoInstantCenter() {
        var s = fourLink
        s.points["lowerFront"] = Point2(x: 20, y: 12)
        let g = s.geometry()
        XCTAssertNil(g.instantCenter)
        XCTAssertNil(g.antiSquat)
        XCTAssertEqual(g.warnings, [.parallelLinks])
    }

    func testLadderBarAndTorqueArm() throws {
        let ladder = SuspensionSetup.ladderBar(wheelbase: 108, cgHeight: 18, pivot: Point2(x: 54, y: 9))
        XCTAssertEqual(try XCTUnwrap(ladder.geometry().antiSquat), (9.0 / 54) / (18.0 / 108) * 100, accuracy: 1e-9)
        // Lower arm y = 10 + 0.2x meets the vertical through the arm's front mount (x = 50)
        let arm = SuspensionSetup.torqueArm(wheelbase: 100, cgHeight: 20, armFront: Point2(x: 50, y: 25),
                                            lowerRear: Point2(x: 0, y: 10), lowerFront: Point2(x: 20, y: 14))
        let g = arm.geometry()
        XCTAssertEqual(g.instantCenter, Point2(x: 50, y: 20))
        XCTAssertEqual(try XCTUnwrap(g.antiSquat), 200, accuracy: 1e-9)
    }

    func testIncompleteAndBehindTheAxle() {
        var s = fourLink
        s.points["lowerFront"] = nil
        XCTAssertEqual(s.geometry().warnings, [.incomplete])
        // Bars spreading apart toward the front: y = 20 + 0.2x and y = 10 + 0.1x meet at x = −100
        let behind = SuspensionSetup.fourLink(wheelbase: 100, cgHeight: 20,
                                              upperRear: Point2(x: 0, y: 20), upperFront: Point2(x: 20, y: 24),
                                              lowerRear: Point2(x: 0, y: 10), lowerFront: Point2(x: 20, y: 12))
        XCTAssertTrue(behind.geometry().warnings.contains(.instantCenterBehindAxle))
        XCTAssertNil(behind.geometry().antiSquat)
    }

    func testUnitsDoNotChangeTheAntiSquat() throws {
        let cm = fourLink.converted(to: .centimeters)
        XCTAssertEqual(cm.wheelbase, 254, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(cm.geometry().icLength), 254, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(cm.geometry().antiSquat), 150, accuracy: 1e-9)
        XCTAssertEqual(cm.converted(to: .inches).points["upperFront"]!.y, 22, accuracy: 1e-9)
    }

    func testTargetWindowAndHoles() throws {
        let target = TargetWindow(icLength: ValueRange(60, 70), icHeight: ValueRange(10, 14), antiSquat: ValueRange(90, 120))
        let g = fourLink.geometry()
        XCTAssertEqual(target.status(.icLength, of: g), .above)
        XCTAssertEqual(target.status(.icHeight, of: g), .above)
        XCTAssertEqual(target.status(.antiSquat, of: g), .above)

        let holes = FourLinkHoles(
            upperRear: [Point2(x: 0, y: 20), Point2(x: 0, y: 18)],
            upperFront: [Point2(x: 30, y: 20), Point2(x: 30, y: 22)],
            lowerRear: [Point2(x: 0, y: 8), Point2(x: 0, y: 10)],
            lowerFront: [Point2(x: 30, y: 10), Point2(x: 30, y: 12)]
        )
        let ranked = holes.ranked(base: fourLink, target: target)
        XCTAssertFalse(ranked.isEmpty)
        XCTAssertEqual(ranked, ranked.sorted { $0.score < $1.score })
        let best = try XCTUnwrap(ranked.first)
        XCTAssertLessThanOrEqual(best.score, target.score(g)!)
        XCTAssertEqual(best.holes.count, 4)
    }

    func testSetupChange() throws {
        var after = fourLink
        after.points["upperFront"] = Point2(x: 20, y: 23)
        let change = SetupChange(from: fourLink, to: after)
        XCTAssertEqual(change.moved, ["upperFront": Point2(x: 0, y: 1)])
        XCTAssertNotNil(change.icLength)
        XCTAssertNotNil(change.antiSquat)
    }

    func testSetupJSONIsPlain() throws {
        let data = try JSONEncoder().encode(fourLink)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains(#""kind":"fourLink""#), json)
        XCTAssertTrue(json.contains(#""upperRear":{"#), json)
        XCTAssertEqual(try JSONDecoder().decode(SuspensionSetup.self, from: data), fourLink)
    }
}
