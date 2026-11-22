import XCTest
@testable import TorkeKit

final class ValidationTests: XCTestCase {
    private func resource(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources"))
    }

    func testComparesOnlyTheMarksBothHave() {
        let result = RunResult(launchTime: 0, zeroTo100: 5, sixtyFeet: 2.05, eighthMile: 8.4, eighthMileKmh: 146,
                               quarterMile: 12.9, quarterMileKmh: 180, topSpeedKmh: 182, accelBias: 0, trace: [])
        let slip = Timeslip(sixtyFeet: 2.0, quarterMile: 12.8, quarterMileSpeed: 112, speedUnit: .mph)
        let c = RunComparison(result: result, timeslip: slip)
        XCTAssertEqual(c.marks.map(\.mark), [.sixtyFeet, .quarterMile, .quarterMileSpeed])
        XCTAssertEqual(c.marks[0].error, 0.05, accuracy: 1e-9)
        XCTAssertEqual(c.marks[1].error, 0.1, accuracy: 1e-9)
        // 112 mph = 180.246 km/h
        XCTAssertEqual(c.marks[2].reference, 112 * 1.609344, accuracy: 1e-9)
        XCTAssertEqual(c.marks[2].error, 180 - 112 * 1.609344, accuracy: 1e-9)
    }

    func testSummaryStatistics() {
        func result(_ sixty: Double) -> RunResult {
            RunResult(launchTime: 0, zeroTo100: nil, sixtyFeet: sixty, eighthMile: nil, eighthMileKmh: nil,
                      quarterMile: nil, quarterMileKmh: nil, topSpeedKmh: 0, accelBias: 0, trace: [])
        }
        let slip = Timeslip(sixtyFeet: 2.0)
        let report = ValidationReport([("a", result(2.1), slip), ("b", result(1.95), slip), ("c", nil, slip), ("d", result(2.05), slip)])
        XCTAssertEqual(report.skipped, ["c"])
        let s = try! XCTUnwrap(report.summaries.first)
        XCTAssertEqual(report.summaries.count, 1)
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.bias, (0.1 - 0.05 + 0.05) / 3, accuracy: 1e-9)
        XCTAssertEqual(s.meanAbsolute, 0.2 / 3, accuracy: 1e-9)
        XCTAssertEqual(s.rms, ((0.01 + 0.0025 + 0.0025) / 3).squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(s.worst, 0.1, accuracy: 1e-9)
        XCTAssertTrue(s.passed)
        XCTAssertTrue(report.passed)
        let strict = ValidationReport([("a", result(2.1), slip)], targets: ValidationTargets(sixtyFeet: 0.05))
        XCTAssertFalse(strict.passed)
    }

    func testEmptyReportDoesNotPass() {
        XCTAssertFalse(ValidationReport([]).passed)
    }

    /// The demo run against the timeslip of its exact physics: within every target.
    func testDemoRunAgainstPerfectTimeslip() throws {
        let url = try resource("validation")
        let set = try ValidationSet.decode(Data(contentsOf: url))
        let report = try set.report(relativeTo: url.deletingLastPathComponent())
        XCTAssertTrue(report.skipped.isEmpty)
        XCTAssertEqual(report.summaries.count, ValidationMark.allCases.count)
        for s in report.summaries { XCTAssertTrue(s.passed, "\(s.mark): \(s.rms)") }
        XCTAssertTrue(report.passed)
    }

    func testTimeslipJSONDefaultsToKmh() throws {
        let slip = try JSONDecoder().decode(Timeslip.self, from: Data(#"{"quarterMile": 13.1, "quarterMileSpeed": 170}"#.utf8))
        XCTAssertEqual(slip.speedUnit, .kmh)
        XCTAssertEqual(slip.value(.quarterMileSpeed), 170)
        XCTAssertNil(slip.value(.sixtyFeet))
    }

    func testRejectsOtherFormats() {
        XCTAssertThrowsError(try ValidationSet.decode(Data(#"{"format": "torke.run", "version": 1, "runs": []}"#.utf8)))
        XCTAssertThrowsError(try ValidationSet.decode(Data(#"{"format": "torke.validation", "version": 2, "runs": []}"#.utf8)))
    }

    /// Writes the numbers TorkeKit for Android must match: `TORKE_WRITE_FIXTURE=1 swift test --filter testWriteValidationFixture`.
    func testWriteValidationFixture() throws {
        guard ProcessInfo.processInfo.environment["TORKE_WRITE_FIXTURE"] == "1" else { throw XCTSkip("set TORKE_WRITE_FIXTURE=1") }
        let url = try resource("validation")
        let report = try ValidationSet.decode(Data(contentsOf: url)).report(relativeTo: url.deletingLastPathComponent())
        let errors = Dictionary(uniqueKeysWithValues: report.runs[0].marks.map { ($0.mark.rawValue, $0.error) })
        let json = try JSONSerialization.data(withJSONObject: ["errors": errors, "passed": report.passed], options: [.prettyPrinted, .sortedKeys])
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources")
        try json.write(to: dir.appendingPathComponent("validation-expected.json"))
        let root = dir.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try json.write(to: root.appendingPathComponent("Fixtures/validation-expected.json"))
    }

    func testValidationFixture() throws {
        let expected = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: resource("validation-expected"))) as? [String: Any])
        let errors = try XCTUnwrap(expected["errors"] as? [String: Double])
        let url = try resource("validation")
        let report = try ValidationSet.decode(Data(contentsOf: url)).report(relativeTo: url.deletingLastPathComponent())
        for m in report.runs[0].marks { XCTAssertEqual(m.error, try XCTUnwrap(errors[m.mark.rawValue]), accuracy: 1e-6, "\(m.mark)") }
    }
}
