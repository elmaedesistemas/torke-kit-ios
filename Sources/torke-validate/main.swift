// torke-validate: TorkeKit's times against dragstrip timeslips. `swift run torke-validate --help`.
// The same command as in TorkeKit for Android (./gradlew :torke-validate:installDist).
import Foundation
import TorkeKit

let usage = """
torke-validate: TorkeKit's times against dragstrip timeslips.

Usage:
  torke-validate SET.json [--json] [--stored] [--runs]
  torke-validate RUN.torkerun.json [timeslip options] [--json] [--stored]

A set is a torke.validation JSON with many runs and their timeslips. For a single run, give the
timeslip on the command line:
  --60ft S  --330ft S  --1/8 S  --1/8-speed V  --1000ft S  --1/4 S  --1/4-speed V  --mph

Options:
  --json     Print the report as JSON.
  --stored   Use the result saved in each run instead of analyzing it again.
  --runs     Also print every run, mark by mark.

Exit status: 0 when every mark is within its target, 1 when not, 2 on bad input.
"""

let markFlags: [String: ValidationMark] = [
    "--60ft": .sixtyFeet, "--330ft": .threeThirtyFeet, "--1/8": .eighthMile, "--1/8-speed": .eighthMileSpeed,
    "--1000ft": .thousandFeet, "--1/4": .quarterMile, "--1/4-speed": .quarterMileSpeed,
]
let markNames: [ValidationMark: String] = [
    .sixtyFeet: "60 ft", .threeThirtyFeet: "330 ft", .eighthMile: "1/8 mile", .eighthMileSpeed: "1/8 speed",
    .thousandFeet: "1000 ft", .quarterMile: "1/4 mile", .quarterMileSpeed: "1/4 speed",
]

func fail(_ message: String) -> Never {
    print("torke-validate: \(message)")
    exit(2)
}

func f(_ v: Double, _ digits: Int = 3, sign: Bool = true) -> String {
    String(format: sign ? "%+.\(digits)f" : "%.\(digits)f", v)
}

func pad(_ s: String, _ width: Int, left: Bool = false) -> String {
    let fill = String(repeating: " ", count: max(0, width - s.count))
    return left ? s + fill : fill + s
}

func timeslip(from args: [String]) -> Timeslip? {
    var values: [ValidationMark: Double] = [:]
    var i = 0
    while i < args.count {
        if let mark = markFlags[args[i]] {
            guard i + 1 < args.count, let v = Double(args[i + 1]) else { fail("\(args[i]) needs a number") }
            values[mark] = v
            i += 2
        } else {
            i += 1
        }
    }
    guard !values.isEmpty else { return nil }
    return Timeslip(
        sixtyFeet: values[.sixtyFeet], threeThirtyFeet: values[.threeThirtyFeet],
        eighthMile: values[.eighthMile], eighthMileSpeed: values[.eighthMileSpeed],
        thousandFeet: values[.thousandFeet],
        quarterMile: values[.quarterMile], quarterMileSpeed: values[.quarterMileSpeed],
        speedUnit: args.contains("--mph") ? .mph : .kmh
    )
}

func printReport(_ report: ValidationReport, runs showRuns: Bool) {
    let n = report.runs.count
    print("TorkeKit validation · \(n) run\(n == 1 ? "" : "s")" + (report.skipped.isEmpty ? "" : " · skipped (no launch): \(report.skipped.joined(separator: ", "))"))
    print("")
    print(pad("Mark", 10, left: true) + " " + ["Runs", "Bias", "Mean |e|", "RMS", "Worst", "Target"].enumerated().map { pad($1, $0 == 0 ? 5 : 9) }.joined(separator: " "))
    for s in report.summaries {
        let d = s.mark.isSpeed ? 2 : 3
        let cells = [pad("\(s.count)", 5), pad(f(s.bias, d), 9), pad(f(s.meanAbsolute, d, sign: false), 9), pad(f(s.rms, d, sign: false), 9),
                     pad(f(s.worst, d), 9), pad("±" + f(s.limit, d, sign: false), 9)]
        print(pad(markNames[s.mark] ?? s.mark.rawValue, 10, left: true) + " " + cells.joined(separator: " ") + "  " + (s.passed ? "ok" : "OVER"))
    }
    print("")
    print("Times in seconds, speeds in km/h. Error = TorkeKit minus timeslip; the RMS is checked against the target.")
    if showRuns {
        for r in report.runs {
            print("")
            print(r.label ?? "run")
            for m in r.marks {
                let d = m.mark.isSpeed ? 2 : 3
                print("  " + pad(markNames[m.mark] ?? "", 10, left: true) + " " + pad(f(m.measured, d, sign: false), 10) + " " + pad(f(m.reference, d, sign: false), 10) + " " + pad(f(m.error, d), 9))
            }
        }
    }
    print("")
    print(report.passed ? "PASS: every mark is within its target." : report.summaries.isEmpty ? "No marks to compare." : "FAIL: some marks are over their target.")
}

let args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty || args.contains("-h") || args.contains("--help") {
    print(usage)
    exit(args.isEmpty ? 2 : 0)
}
let url = URL(fileURLWithPath: args[0])
guard let data = try? Data(contentsOf: url) else { fail("No such file: \(args[0])") }
let stored = args.contains("--stored")

let report: ValidationReport
do {
    if String(decoding: data, as: UTF8.self).contains("\"torke.validation\"") {
        report = try ValidationSet.decode(data).report(relativeTo: url.deletingLastPathComponent(), useStoredResults: stored)
    } else {
        guard let slip = timeslip(from: Array(args.dropFirst())) else { fail("Give at least one timeslip mark, such as --1/4 12.85. See --help.") }
        let run = try TorkeRun.decode(data)
        let result = stored ? (run.result ?? run.analyze()) : run.analyze()
        report = ValidationReport([(url.lastPathComponent, result, slip)])
    }
} catch {
    fail("\(error)")
}

if args.contains("--json") {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(report), as: UTF8.self))
} else {
    printReport(report, runs: args.contains("--runs"))
}
exit(report.passed ? 0 : 1)
