import Foundation

/// An area on the map: a circle or a polygon, such as a dragstrip or an event's paddock. Use
/// it to decide where a run counts.
///
/// JSON: `{ "kind": "circle", "center": { "latitude", "longitude" }, "radius": 300 }` or
/// `{ "kind": "polygon", "points": [{ "latitude", "longitude" }, …] }`, with an optional `name`.
public struct Geofence: Sendable, Codable, Equatable {
    public enum Kind: String, Sendable, Codable { case circle, polygon }

    public var kind: Kind
    public var name: String?
    public var center: Coordinate?
    /// Meters, for a circle.
    public var radius: Double?
    /// The corners, in order, for a polygon.
    public var points: [Coordinate]?

    public static func circle(center: Coordinate, radius: Double, name: String? = nil) -> Geofence {
        Geofence(kind: .circle, name: name, center: center, radius: radius, points: nil)
    }

    public static func polygon(_ points: [Coordinate], name: String? = nil) -> Geofence {
        Geofence(kind: .polygon, name: name, center: nil, radius: nil, points: points)
    }

    public func contains(_ c: Coordinate) -> Bool {
        switch kind {
        case .circle:
            guard let center, let radius else { return false }
            return Geo.distance(center, c) <= radius
        case .polygon:
            guard let points, points.count >= 3 else { return false }
            // Ray casting on a local flat projection around the point: fine for a track
            let p = points.map { Geo.local($0, origin: c) }
            var inside = false
            var j = p.count - 1
            for i in 0..<p.count {
                let (xi, yi) = p[i], (xj, yj) = p[j]
                if (yi > 0) != (yj > 0), 0 < (xj - xi) * (0 - yi) / (yj - yi) + xi { inside.toggle() }
                j = i
            }
            return inside
        }
    }
}

/// Where a run was, against a geofence.
public struct GeofenceCheck: Sendable, Codable, Equatable {
    /// The run launched inside.
    public var startInside: Bool
    /// Share of the GPS fixes with a position (during the run) that were inside, 0 to 1.
    public var shareInside: Double
    /// Every positioned fix of the run was inside.
    public var allInside: Bool { shareInside >= 1 }
}

public extension TorkeRun {
    /// Where this run was against `geofence`. Nil without a launch position.
    func check(_ geofence: Geofence) -> GeofenceCheck? {
        guard let start = startLocation else { return nil }
        let launch = result?.launchTime ?? -.infinity
        let end = result.flatMap { r in r.trace.last.map { r.launchTime + $0.t } } ?? .infinity
        let fixes = gps.filter { $0.t >= launch && $0.t <= end }.compactMap(\.coordinate)
        let inside = fixes.filter(geofence.contains).count
        return GeofenceCheck(startInside: geofence.contains(start), shareInside: fixes.isEmpty ? 1 : Double(inside) / Double(fixes.count))
    }
}

public extension Array where Element == Geofence {
    /// The first geofence that contains `coordinate`, such as the track a run launched at.
    func first(containing coordinate: Coordinate) -> Geofence? {
        first { $0.contains(coordinate) }
    }
}

/// Small geodesy for tracks: distances in meters and a local flat projection.
public enum Geo {
    static let earthRadius = 6_371_008.8

    /// Great-circle distance in meters (haversine).
    public static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1, dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, h.squareRoot()))
    }

    /// Meters east (x) and north (y) of `origin`. Accurate within a few kilometers.
    public static func local(_ c: Coordinate, origin: Coordinate) -> (x: Double, y: Double) {
        let x = (c.longitude - origin.longitude) * .pi / 180 * earthRadius * cos(origin.latitude * .pi / 180)
        let y = (c.latitude - origin.latitude) * .pi / 180 * earthRadius
        return (x, y)
    }
}
