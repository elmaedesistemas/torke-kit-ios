import Foundation

/// A timing line across the track, from one edge to the other: the start/finish line or a
/// sector split. Make it a bit wider than the track so every lap crosses it.
public struct TimingLine: Sendable, Codable, Equatable {
    public var a: Coordinate
    public var b: Coordinate
    public var name: String?

    public init(a: Coordinate, b: Coordinate, name: String? = nil) {
        self.a = a
        self.b = b
        self.name = name
    }
}

/// One completed lap.
public struct Lap: Sendable, Codable, Equatable {
    /// 1 for the first full lap.
    public var number: Int
    /// When it started, on the samples' clock.
    public var start: TimeInterval
    /// Seconds.
    public var time: TimeInterval
    /// Time of each sector, in order; the last one ends at the start/finish line. Empty without
    /// sector lines, or if a sector line was missed.
    public var sectors: [TimeInterval]
    /// Meters driven, from the GPS.
    public var distance: Double
}

/// What happened on a fix.
public enum LapEvent: Sendable, Equatable {
    /// The first crossing of the start/finish line: timing begins.
    case started(time: TimeInterval)
    /// A sector line: its index (0 for the first) and the sector's time.
    case sector(index: Int, time: TimeInterval)
    case lap(Lap)
}

/// Lap timing for road courses with the phone's GPS: start/finish line, sectors, the live
/// delta against the best lap and the predicted lap. Feed it every GPS fix with a position.
///
/// Crossings are interpolated between fixes, so even a 1 Hz GPS times a lap to about a tenth;
/// a faster GPS does better. ``RunSnapshot/gpsRate`` tells you what the phone gives.
public final class LapTimer {
    public let start: TimingLine
    public let sectorLines: [TimingLine]
    public private(set) var laps: [Lap] = []
    /// The fastest lap so far.
    public var bestLap: Lap? { laps.min { $0.time < $1.time } }

    /// A line crossed again this soon is ignored (GPS jitter on the line).
    public var minimumLapTime: TimeInterval = 10

    private var last: (t: TimeInterval, c: Coordinate)?
    private var lapStart: TimeInterval?
    private var lastSplit: TimeInterval?
    private var sectors: [TimeInterval] = []
    private var nextSector = 0
    private var distance = 0.0
    /// (meters, seconds) since the start of the current lap, and of the best lap.
    private var profile: [(d: Double, t: TimeInterval)] = []
    private var bestProfile: [(d: Double, t: TimeInterval)] = []

    public init(start: TimingLine, sectors: [TimingLine] = []) {
        self.start = start
        self.sectorLines = sectors
    }

    /// Feeds one fix. Fixes without a position are ignored.
    @discardableResult
    public func process(_ fix: GPSSample) -> [LapEvent] {
        guard let c = fix.coordinate else { return [] }
        defer { last = (fix.t, c) }
        guard let prev = last, fix.t > prev.t else { return [] }
        var events: [LapEvent] = []
        let step = Geo.distance(prev.c, c)

        // Sector lines, in order, only during a lap
        if lapStart != nil, nextSector < sectorLines.count,
           let f = Self.crossing(prev.c, c, sectorLines[nextSector]), let split = lastSplit {
            let t = prev.t + f * (fix.t - prev.t)
            sectors.append(t - split)
            events.append(.sector(index: nextSector, time: t - split))
            lastSplit = t
            nextSector += 1
        }

        if let f = Self.crossing(prev.c, c, start) {
            let t = prev.t + f * (fix.t - prev.t)
            if let begun = lapStart {
                guard t - begun >= minimumLapTime else { return advance(events, prev: prev.t, fix: fix.t, step: step) }
                let partial = step * f
                let lapDistance = distance + partial
                let complete = nextSector == sectorLines.count
                let lastSector = lastSplit.map { t - $0 }
                let lap = Lap(number: laps.count + 1, start: begun, time: t - begun,
                              sectors: complete && !sectorLines.isEmpty ? sectors + [lastSector ?? 0] : [],
                              distance: lapDistance)
                profile.append((lapDistance, t - begun))
                if bestLap.map({ lap.time < $0.time }) ?? true { bestProfile = profile }
                laps.append(lap)
                events.append(.lap(lap))
                // The new lap starts at the crossing; the rest of this step belongs to it
                beginLap(at: t)
                distance = step * (1 - f)
                profile.append((distance, fix.t - t))
            } else {
                events.append(.started(time: t))
                beginLap(at: t)
                distance = step * (1 - f)
                profile.append((distance, fix.t - t))
            }
            return events
        }
        return advance(events, prev: prev.t, fix: fix.t, step: step)
    }

    private func advance(_ events: [LapEvent], prev: TimeInterval, fix: TimeInterval, step: Double) -> [LapEvent] {
        if let begun = lapStart {
            distance += step
            profile.append((distance, fix - begun))
        }
        return events
    }

    private func beginLap(at t: TimeInterval) {
        lapStart = t
        lastSplit = t
        sectors = []
        nextSector = 0
        profile = [(0, 0)]
    }

    /// Seconds into the current lap at `time`; nil before the first crossing.
    public func elapsed(at time: TimeInterval) -> TimeInterval? {
        lapStart.map { time - $0 }
    }

    /// The current lap against the best one at the same distance: negative is ahead. Nil until
    /// there is a best lap.
    public var delta: TimeInterval? {
        guard let now = profile.last, bestProfile.count >= 2 else { return nil }
        guard let bestT = Self.time(atDistance: now.d, in: bestProfile) else { return nil }
        return now.t - bestT
    }

    /// The best lap plus the current delta: where this lap is heading.
    public var predictedLap: TimeInterval? {
        guard let best = bestLap, let delta else { return nil }
        return best.time + delta
    }

    /// Where the segment p→q crosses `line`, as a fraction of p→q; nil if it doesn't.
    static func crossing(_ p: Coordinate, _ q: Coordinate, _ line: TimingLine) -> Double? {
        let origin = p
        let (px, py) = (0.0, 0.0)
        let (qx, qy) = Geo.local(q, origin: origin)
        let (ax, ay) = Geo.local(line.a, origin: origin)
        let (bx, by) = Geo.local(line.b, origin: origin)
        let rx = qx - px, ry = qy - py, sx = bx - ax, sy = by - ay
        let denom = rx * sy - ry * sx
        guard abs(denom) > 1e-12 else { return nil }
        let t = ((ax - px) * sy - (ay - py) * sx) / denom
        let u = ((ax - px) * ry - (ay - py) * rx) / denom
        guard t > 0, t <= 1, u >= 0, u <= 1 else { return nil }
        return t
    }

    static func time(atDistance d: Double, in profile: [(d: Double, t: TimeInterval)]) -> TimeInterval? {
        guard let first = profile.first, let last = profile.last, d >= first.d else { return nil }
        if d >= last.d { return last.t }
        for i in 1..<profile.count where profile[i].d >= d {
            let a = profile[i - 1], b = profile[i]
            let span = b.d - a.d
            return span > 0 ? a.t + (d - a.d) / span * (b.t - a.t) : b.t
        }
        return nil
    }
}
