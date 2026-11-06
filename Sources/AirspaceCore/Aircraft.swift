import Foundation

/// One position report for one aircraft, as returned by a flight source.
public struct AircraftReport: Hashable, Sendable {
    /// ICAO 24-bit address, lowercase hex. Stable identity across reports.
    public var hex: String
    public var callsign: String?
    public var registration: String?
    /// ICAO type designator, e.g. "B738".
    public var typeCode: String?
    /// ADS-B emitter category, e.g. "A3".
    public var category: String?
    public var position: Coordinate
    /// Barometric altitude in feet; 0 when on the ground.
    public var altitudeFt: Double
    public var onGround: Bool
    public var groundSpeedKt: Double?
    public var trackDeg: Double?
    public var verticalRateFpm: Double?
    public var squawk: String?
    /// Local epoch seconds when this position was observed.
    public var fixTime: TimeInterval

    public init(hex: String, callsign: String? = nil, registration: String? = nil, typeCode: String? = nil,
                category: String? = nil, position: Coordinate, altitudeFt: Double, onGround: Bool = false,
                groundSpeedKt: Double? = nil, trackDeg: Double? = nil, verticalRateFpm: Double? = nil,
                squawk: String? = nil, fixTime: TimeInterval) {
        self.hex = hex
        self.callsign = callsign
        self.registration = registration
        self.typeCode = typeCode
        self.category = category
        self.position = position
        self.altitudeFt = altitudeFt
        self.onGround = onGround
        self.groundSpeedKt = groundSpeedKt
        self.trackDeg = trackDeg
        self.verticalRateFpm = verticalRateFpm
        self.squawk = squawk
        self.fixTime = fixTime
    }
}

/// Broad airframe class, used to pick a silhouette glyph.
public enum AircraftClass: String, Sendable, CaseIterable {
    case jet, heavy, turboprop, light, helicopter, other

    private static let turboprops: Set<String> = [
        "AT43", "AT45", "AT46", "AT72", "AT73", "AT75", "AT76", "DH8A", "DH8B", "DH8C", "DH8D",
        "SF34", "E120", "JS41", "B190", "BE20", "BE30", "BE9L", "B350", "C208", "PC12", "PC24",
        "SW4", "D328", "F50", "DHC6", "AN26", "C130", "TBM7", "TBM8", "TBM9", "P180", "L410",
    ]

    public static func classify(category: String?, typeCode: String?) -> AircraftClass {
        if let t = typeCode?.uppercased(), turboprops.contains(t) { return .turboprop }
        switch category?.uppercased() {
        case "A7": return .helicopter
        case "A5": return .heavy
        case "A3", "A4", "A6": return .jet
        case "A2": return typeCode.map { turboprops.contains($0.uppercased()) } == true ? .turboprop : .jet
        case "A1", "B1", "B4": return .light
        default:
            if let t = typeCode?.uppercased() {
                if t.hasPrefix("H") || t.hasPrefix("EC") || t.hasPrefix("AS3") || t.hasPrefix("R44") || t == "R22" { return .helicopter }
                if t.hasPrefix("C1") || t.hasPrefix("P28") || t.hasPrefix("SR2") || t.hasPrefix("C72") { return .light }
                if t.hasPrefix("A3") || t.hasPrefix("B7") || t.hasPrefix("E1") || t.hasPrefix("CRJ") || t.hasPrefix("E75") { return .jet }
            }
            return .other
        }
    }
}

/// Route and airframe details for the info corner. All optional: lookups often miss.
public struct FlightDetails: Hashable, Sendable {
    public var origin: String?
    public var destination: String?
    public var airline: String?
    public var aircraftDescription: String?

    public init(origin: String? = nil, destination: String? = nil, airline: String? = nil, aircraftDescription: String? = nil) {
        self.origin = origin
        self.destination = destination
        self.airline = airline
        self.aircraftDescription = aircraftDescription
    }
}
