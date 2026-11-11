import Foundation

/// A WGS84 position in degrees.
public struct Coordinate: Hashable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

public enum Geo {
    public static let earthRadiusNM = 3440.065
    public static let nmPerMile = 0.868976
    public static let metersPerNM = 1852.0

    /// Great-circle distance in nautical miles.
    public static func distanceNM(_ a: Coordinate, _ b: Coordinate) -> Double {
        let φ1 = a.latitude.radians, φ2 = b.latitude.radians
        let dφ = (b.latitude - a.latitude).radians
        let dλ = (b.longitude - a.longitude).radians
        let h = sin(dφ / 2) * sin(dφ / 2) + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
        return 2 * earthRadiusNM * asin(min(1, sqrt(h)))
    }

    /// Point reached by travelling `distanceNM` on initial bearing `bearingDeg`.
    /// Uses a local flat-earth step, which is exact enough for the few miles a plane covers between fixes.
    public static func offset(_ c: Coordinate, distanceNM: Double, bearingDeg: Double) -> Coordinate {
        let b = bearingDeg.radians
        let dLat = distanceNM * cos(b) / 60.0
        let cosLat = max(0.01, cos(c.latitude.radians))
        let dLon = distanceNM * sin(b) / (60.0 * cosLat)
        var lon = c.longitude + dLon
        if lon > 180 { lon -= 360 } else if lon < -180 { lon += 360 }
        return Coordinate(latitude: min(90, max(-90, c.latitude + dLat)), longitude: lon)
    }
}

extension Geo {
    /// Initial great-circle bearing from `a` to `b`, 0…360 degrees clockwise from north.
    public static func bearingDeg(from a: Coordinate, to b: Coordinate) -> Double {
        let φ1 = a.latitude.radians, φ2 = b.latitude.radians, dλ = (b.longitude - a.longitude).radians
        let y = sin(dλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(dλ)
        let θ = atan2(y, x).degrees
        return θ < 0 ? θ + 360 : θ
    }

    /// Eight-point compass direction for a bearing: "N", "NE", …
    public static func compassPoint(_ bearingDeg: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let i = Int(((bearingDeg.truncatingRemainder(dividingBy: 360) + 360 + 22.5) / 45).rounded(.down)) % 8
        return points[i]
    }

    /// Point a fraction `f` of the way along the great circle from `a` to `b`.
    public static func intermediate(_ a: Coordinate, _ b: Coordinate, fraction f: Double) -> Coordinate {
        let d = distanceNM(a, b) / earthRadiusNM
        guard d > 1e-9 else { return a }
        let φ1 = a.latitude.radians, λ1 = a.longitude.radians, φ2 = b.latitude.radians, λ2 = b.longitude.radians
        let A = sin((1 - f) * d) / sin(d), B = sin(f * d) / sin(d)
        let x = A * cos(φ1) * cos(λ1) + B * cos(φ2) * cos(λ2)
        let y = A * cos(φ1) * sin(λ1) + B * cos(φ2) * sin(λ2)
        let z = A * sin(φ1) + B * sin(φ2)
        return Coordinate(latitude: atan2(z, sqrt(x * x + y * y)).degrees, longitude: atan2(y, x).degrees)
    }
}

/// Distinct aircraft seen today. Resets at local midnight.
public struct DailyTally: Codable, Hashable, Sendable {
    public private(set) var day: String
    public private(set) var seen: Set<String>

    public init(day: String = "", seen: Set<String> = []) {
        self.day = day
        self.seen = seen
    }

    public var count: Int { seen.count }

    /// Adds `ids`, starting over if `date` falls on a new day. Returns true if anything changed.
    @discardableResult
    public mutating func record<S: Sequence>(_ ids: S, on date: Date, calendar: Calendar = .current) -> Bool where S.Element == String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let key = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        var changed = false
        if key != day {
            day = key
            seen = []
            changed = true
        }
        for id in ids where seen.insert(id).inserted { changed = true }
        return changed
    }
}

extension Double {
    @inlinable var radians: Double { self * .pi / 180 }
    @inlinable var degrees: Double { self * 180 / .pi }
}
