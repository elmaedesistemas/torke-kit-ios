import Foundation

/// Weather at the strip. Times and speeds can be corrected to standard air (SAE J1349:
/// 25 °C, 990 hPa of dry air) so runs on different days compare fairly.
public struct Weather: Sendable, Codable, Equatable {
    public var temperatureC: Double
    /// Relative humidity, 0 to 100.
    public var humidity: Double
    /// Station pressure (not sea-level), hPa.
    public var pressureHpa: Double

    public init(temperatureC: Double, humidity: Double, pressureHpa: Double) {
        self.temperatureC = temperatureC
        self.humidity = humidity
        self.pressureHpa = pressureHpa
    }

    /// Water vapor pressure, hPa (Magnus formula).
    public var vaporPressureHpa: Double {
        let saturation = 6.1094 * exp(17.625 * temperatureC / (temperatureC + 243.04))
        return saturation * min(max(humidity, 0), 100) / 100
    }

    /// Pressure of the dry air alone, hPa.
    public var dryPressureHpa: Double { pressureHpa - vaporPressureHpa }

    /// Air density, kg/m³.
    public var airDensity: Double {
        let t = temperatureC + 273.15
        return (dryPressureHpa * 100) / (287.058 * t) + (vaporPressureHpa * 100) / (461.495 * t)
    }

    /// The altitude of the standard atmosphere with the same air density, in meters. Higher
    /// means thinner air and slower runs.
    public var densityAltitude: Double {
        44_330.8 * (1 - pow(airDensity / 1.225, 0.234_969))
    }

    /// SAE J1349 power correction: above 1, the air cost power and the corrected times are
    /// quicker than the measured ones.
    public var correctionFactor: Double {
        1.18 * (990 / dryPressureHpa) * ((temperatureC + 273.15) / 298.15).squareRoot() - 0.18
    }

    /// A time corrected to standard air. Elapsed times go with the cube root of power.
    public func corrected(time: TimeInterval) -> TimeInterval { time * pow(correctionFactor, -1.0 / 3) }

    /// A speed corrected to standard air.
    public func corrected(speed: Double) -> Double { speed * pow(correctionFactor, 1.0 / 3) }
}

public extension RunResult {
    /// The times and speeds corrected to standard air. The trace stays as measured.
    func corrected(for weather: Weather) -> RunResult {
        var r = self
        let t = { (v: TimeInterval?) in v.map { weather.corrected(time: $0) } }
        let s = { (v: Double?) in v.map { weather.corrected(speed: $0) } }
        r.zeroTo100 = t(zeroTo100)
        r.sixtyFeet = t(sixtyFeet)
        r.eighthMile = t(eighthMile)
        r.quarterMile = t(quarterMile)
        r.eighthMileKmh = s(eighthMileKmh)
        r.quarterMileKmh = s(quarterMileKmh)
        r.topSpeedKmh = weather.corrected(speed: topSpeedKmh)
        return r
    }
}
