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

/// Broad airframe class, used to pick an icon. Type designators win over the emitter
/// category because the category can't tell a 747 from a 777, or a CRJ from an A320.
public enum AircraftClass: String, Sendable, CaseIterable {
    /// Narrow-body airliner with wing-mounted engines (A320, 737, E-jets).
    case jet
    /// Wide-body twin (777, 787, A330, A350).
    case heavy
    /// Four-engine wide-body (747, A380, A340).
    case quad
    /// Jets with engines on the rear fuselage: business jets, CRJs, MD-80s.
    case tailJet
    case turboprop, light, helicopter, other

    private static let quads: Set<String> = [
        "B741", "B742", "B743", "B744", "B748", "B74S", "B74R", "A388", "A342", "A343", "A345", "A346",
        "A124", "A225", "IL76", "C17", "C5M", "K35R", "E3TF", "B52", "BA46", "RJ85", "RJ1H",
    ]
    private static let tailJetPrefixes = [
        "CRJ", "E135", "E145", "E35L", "GLF", "GL5T", "GL6T", "GL7T", "GLEX", "CL30", "CL35", "CL60", "C25",
        "C501", "C510", "C525", "C550", "C560", "C56X", "C650", "C680", "C68A", "C700", "C750", "LJ", "FA",
        "F2TH", "F900", "H25", "E50P", "E55P", "E545", "E550", "PRM1", "HDJT", "MD8", "MD9", "B712", "DC9",
        "F100", "F70", "G280", "SF50", "EA50", "PC24",
    ]
    private static let wideTwinPrefixes = ["B76", "B77", "B78", "A30", "A31", "A33", "A35", "B772", "B773"]
    private static let turboprops: Set<String> = [
        "AT43", "AT45", "AT46", "AT72", "AT73", "AT75", "AT76", "DH8A", "DH8B", "DH8C", "DH8D",
        "SF34", "E120", "JS41", "B190", "BE20", "BE30", "BE9L", "B350", "C208", "PC12",
        "SW4", "D328", "F50", "DHC6", "AN26", "C130", "TBM7", "TBM8", "TBM9", "P180", "L410",
    ]

    public static func classify(category: String?, typeCode: String?) -> AircraftClass {
        if let t = typeCode?.uppercased(), !t.isEmpty {
            if quads.contains(t) { return .quad }
            if turboprops.contains(t) { return .turboprop }
            if tailJetPrefixes.contains(where: t.hasPrefix) { return .tailJet }
            if wideTwinPrefixes.contains(where: t.hasPrefix) { return .heavy }
        }
        switch category?.uppercased() {
        case "A7": return .helicopter
        case "A5": return .heavy
        case "A3", "A4", "A6": return .jet
        case "A2": return .tailJet   // small jets and business aircraft
        case "A1", "B1", "B4": return .light
        default:
            if let t = typeCode?.uppercased() {
                if t.hasPrefix("H") || t.hasPrefix("EC") || t.hasPrefix("AS3") || t.hasPrefix("R44") || t == "R22" { return .helicopter }
                if t.hasPrefix("C1") || t.hasPrefix("P28") || t.hasPrefix("SR2") || t.hasPrefix("C72") || t.hasPrefix("BE3") { return .light }
                if t.hasPrefix("A3") || t.hasPrefix("A2") || t.hasPrefix("B73") || t.hasPrefix("B3") || t.hasPrefix("E1")
                    || t.hasPrefix("E7") || t.hasPrefix("BCS") { return .jet }
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
