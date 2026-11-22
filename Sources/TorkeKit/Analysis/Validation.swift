import Foundation

// Validation: how far TorkeKit's times are from a dragstrip's timeslip. Each run is analyzed
// again from its raw samples and compared mark by mark; many runs give the bias, the typical
// error and the worst case for each mark.

/// Speeds on a timeslip: km/h or mph, whatever the track prints.
public enum SpeedUnit: String, Sendable, Codable {
    case kmh, mph

    func toKmh(_ v: Double) -> Double { self == .kmh ? v : v * 1.609_344 }
}

/// The times a dragstrip printed for a run. Times in seconds from the moment the car left the
/// staging beam (reaction time is not part of them). Fill in what the slip has.
public struct Timeslip: Sendable, Codable, Equatable {
    public var sixtyFeet: TimeInterval?
    public var threeThirtyFeet: TimeInterval?
    public var eighthMile: TimeInterval?
    public var eighthMileSpeed: Double?
    public var thousandFeet: TimeInterval?
    public var quarterMile: TimeInterval?
    public var quarterMileSpeed: Double?
    /// The unit of `eighthMileSpeed` and `quarterMileSpeed`.
    public var speedUnit: SpeedUnit
    /// Informative only: it is not compared.
    public var reactionTime: TimeInterval?
    public var notes: String?

    public init(
        sixtyFeet: TimeInterval? = nil, threeThirtyFeet: TimeInterval? = nil,
        eighthMile: TimeInterval? = nil, eighthMileSpeed: Double? = nil,
        thousandFeet: TimeInterval? = nil,
        quarterMile: TimeInterval? = nil, quarterMileSpeed: Double? = nil,
        speedUnit: SpeedUnit = .kmh, reactionTime: TimeInterval? = nil, notes: String? = nil
    ) {
        self.sixtyFeet = sixtyFeet
        self.threeThirtyFeet = threeThirtyFeet
        self.eighthMile = eighthMile
        self.eighthMileSpeed = eighthMileSpeed
        self.thousandFeet = thousandFeet
        self.quarterMile = quarterMile
        self.quarterMileSpeed = quarterMileSpeed
        self.speedUnit = speedUnit
        self.reactionTime = reactionTime
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case sixtyFeet, threeThirtyFeet, eighthMile, eighthMileSpeed, thousandFeet, quarterMile, quarterMileSpeed, speedUnit, reactionTime, notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sixtyFeet = try c.decodeIfPresent(Double.self, forKey: .sixtyFeet)
        threeThirtyFeet = try c.decodeIfPresent(Double.self, forKey: .threeThirtyFeet)
        eighthMile = try c.decodeIfPresent(Double.self, forKey: .eighthMile)
        eighthMileSpeed = try c.decodeIfPresent(Double.self, forKey: .eighthMileSpeed)
        thousandFeet = try c.decodeIfPresent(Double.self, forKey: .thousandFeet)
        quarterMile = try c.decodeIfPresent(Double.self, forKey: .quarterMile)
        quarterMileSpeed = try c.decodeIfPresent(Double.self, forKey: .quarterMileSpeed)
        speedUnit = try c.decodeIfPresent(SpeedUnit.self, forKey: .speedUnit) ?? .kmh
        reactionTime = try c.decodeIfPresent(Double.self, forKey: .reactionTime)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }

    /// The reference value for a mark, speeds in km/h.
    public func value(_ mark: ValidationMark) -> Double? {
        switch mark {
        case .sixtyFeet: sixtyFeet
        case .threeThirtyFeet: threeThirtyFeet
        case .eighthMile: eighthMile
        case .eighthMileSpeed: eighthMileSpeed.map(speedUnit.toKmh)
        case .thousandFeet: thousandFeet
        case .quarterMile: quarterMile
        case .quarterMileSpeed: quarterMileSpeed.map(speedUnit.toKmh)
        }
    }
}

/// The marks a timeslip can have. Times in seconds, speeds in km/h.
public enum ValidationMark: String, Sendable, Codable, CaseIterable {
    case sixtyFeet, threeThirtyFeet, eighthMile, eighthMileSpeed, thousandFeet, quarterMile, quarterMileSpeed

    public var isSpeed: Bool { self == .eighthMileSpeed || self == .quarterMileSpeed }

    /// The same mark read from TorkeKit's result.
    public func value(in result: RunResult) -> Double? {
        switch self {
        case .sixtyFeet: result.sixtyFeet
        case .threeThirtyFeet: result.elapsed(toDistance: DragDistance.threeThirtyFeet)
        case .eighthMile: result.eighthMile
        case .eighthMileSpeed: result.eighthMileKmh
        case .thousandFeet: result.thousandFeet
        case .quarterMile: result.quarterMile
        case .quarterMileSpeed: result.quarterMileKmh
        }
    }
}

/// How much error each mark may have. The defaults are TorkeKit's accuracy targets.
public struct ValidationTargets: Sendable, Codable, Equatable {
    public var sixtyFeet: Double
    public var threeThirtyFeet: Double
    public var eighthMile: Double
    public var thousandFeet: Double
    public var quarterMile: Double
    /// For both trap speeds, km/h.
    public var speedKmh: Double

    public init(sixtyFeet: Double = 0.10, threeThirtyFeet: Double = 0.12, eighthMile: Double = 0.12,
                thousandFeet: Double = 0.15, quarterMile: Double = 0.15, speedKmh: Double = 3) {
        self.sixtyFeet = sixtyFeet
        self.threeThirtyFeet = threeThirtyFeet
        self.eighthMile = eighthMile
        self.thousandFeet = thousandFeet
        self.quarterMile = quarterMile
        self.speedKmh = speedKmh
    }

    public func limit(_ mark: ValidationMark) -> Double {
        switch mark {
        case .sixtyFeet: sixtyFeet
        case .threeThirtyFeet: threeThirtyFeet
        case .eighthMile: eighthMile
        case .thousandFeet: thousandFeet
        case .quarterMile: quarterMile
        case .eighthMileSpeed, .quarterMileSpeed: speedKmh
        }
    }
}

/// One mark of one run: what TorkeKit measured against the timeslip.
public struct MarkComparison: Sendable, Codable, Equatable {
    public var mark: ValidationMark
    public var measured: Double
    public var reference: Double
    /// Measured minus reference, in seconds or km/h. For times, positive means TorkeKit read
    /// slower than the track; for speeds, faster.
    public var error: Double { measured - reference }
}

/// One run against its timeslip.
public struct RunComparison: Sendable, Codable, Equatable {
    public var label: String?
    /// The marks both the run and the slip have.
    public var marks: [MarkComparison]

    public init(result: RunResult, timeslip: Timeslip, label: String? = nil) {
        self.label = label
        marks = ValidationMark.allCases.compactMap { mark in
            guard let reference = timeslip.value(mark), let measured = mark.value(in: result) else { return nil }
            return MarkComparison(mark: mark, measured: measured, reference: reference)
        }
    }
}

/// The errors of one mark over every run.
public struct MarkSummary: Sendable, Codable, Equatable {
    public var mark: ValidationMark
    public var count: Int
    /// The mean error: a systematic offset, if any.
    public var bias: Double
    public var meanAbsolute: Double
    /// Root mean square: the typical error, the one checked against the target.
    public var rms: Double
    /// The largest error, with its sign.
    public var worst: Double
    public var limit: Double
    public var passed: Bool { rms <= limit }
}

/// Many runs against their timeslips.
public struct ValidationReport: Sendable, Codable, Equatable {
    public var runs: [RunComparison]
    /// Runs that could not be analyzed (no launch found), by label.
    public var skipped: [String]
    public var summaries: [MarkSummary]
    public var targets: ValidationTargets
    /// Every mark with data is within its target.
    public var passed: Bool { !summaries.isEmpty && summaries.allSatisfy(\.passed) }

    /// - Parameter pairs: each run's result (nil if it had no launch), its timeslip and a label.
    public init(_ pairs: [(label: String, result: RunResult?, timeslip: Timeslip)], targets: ValidationTargets = ValidationTargets()) {
        self.targets = targets
        var runs: [RunComparison] = [], skipped: [String] = []
        for pair in pairs {
            if let result = pair.result { runs.append(RunComparison(result: result, timeslip: pair.timeslip, label: pair.label)) } else { skipped.append(pair.label) }
        }
        self.runs = runs
        self.skipped = skipped
        summaries = ValidationMark.allCases.compactMap { mark in
            let errors = runs.flatMap { $0.marks.filter { $0.mark == mark }.map(\.error) }
            guard !errors.isEmpty else { return nil }
            let n = Double(errors.count)
            return MarkSummary(
                mark: mark, count: errors.count,
                bias: errors.reduce(0, +) / n,
                meanAbsolute: errors.map(abs).reduce(0, +) / n,
                rms: (errors.map { $0 * $0 }.reduce(0, +) / n).squareRoot(),
                worst: errors.max { abs($0) < abs($1) } ?? 0,
                limit: targets.limit(mark)
            )
        }
    }
}

public extension TorkeRun {
    /// This run, analyzed again with the current engine, against its timeslip.
    func compare(with timeslip: Timeslip, label: String? = nil) -> RunComparison? {
        analyze().map { RunComparison(result: $0, timeslip: timeslip, label: label) }
    }
}

/// A set of runs with their timeslips, as JSON (`torke.validation`), for `torke-validate`.
///
/// ```json
/// { "format": "torke.validation", "version": 1,
///   "runs": [{ "run": "runs/first.torkerun.json", "label": "Run 1",
///              "timeslip": { "sixtyFeet": 2.12, "quarterMile": 12.91, "quarterMileSpeed": 114.2, "speedUnit": "mph" } }] }
/// ```
public struct ValidationSet: Sendable, Codable, Equatable {
    public static let formatName = "torke.validation"

    public struct Entry: Sendable, Codable, Equatable {
        /// Path to the `.torkerun.json`, relative to the set's file.
        public var run: String
        public var label: String?
        public var timeslip: Timeslip

        public init(run: String, label: String? = nil, timeslip: Timeslip) {
            self.run = run
            self.label = label
            self.timeslip = timeslip
        }
    }

    public var format: String
    public var version: Int
    public var targets: ValidationTargets?
    public var runs: [Entry]

    public init(runs: [Entry], targets: ValidationTargets? = nil) {
        format = Self.formatName
        version = 1
        self.targets = targets
        self.runs = runs
    }

    public static func decode(_ data: Data) throws -> ValidationSet {
        let set = try JSONDecoder().decode(ValidationSet.self, from: data)
        guard set.format == formatName else { throw TorkeRun.FormatError.notATorkeRun(set.format) }
        guard set.version <= 1 else { throw TorkeRun.FormatError.newerVersion(set.version) }
        return set
    }

    /// Reads every run (paths relative to `directory`) and builds the report.
    public func report(relativeTo directory: URL, useStoredResults: Bool = false) throws -> ValidationReport {
        let pairs = try runs.enumerated().map { i, entry -> (label: String, result: RunResult?, timeslip: Timeslip) in
            let url = URL(fileURLWithPath: entry.run, relativeTo: directory)
            let run = try TorkeRun.decode(Data(contentsOf: url))
            let result = useStoredResults ? (run.result ?? run.analyze()) : run.analyze()
            return (entry.label ?? "\(i + 1)", result, entry.timeslip)
        }
        return ValidationReport(pairs, targets: targets ?? ValidationTargets())
    }
}
