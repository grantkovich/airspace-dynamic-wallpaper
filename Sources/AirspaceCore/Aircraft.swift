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
    /// Emergency squawk or ADS-B emergency status, if any.
    public var alert: AircraftAlert?
    /// Flagged as military in the aggregator's aircraft database.
    public var isMilitary: Bool
    /// Local epoch seconds when this position was observed.
    public var fixTime: TimeInterval

    public init(hex: String, callsign: String? = nil, registration: String? = nil, typeCode: String? = nil,
                category: String? = nil, position: Coordinate, altitudeFt: Double, onGround: Bool = false,
                groundSpeedKt: Double? = nil, trackDeg: Double? = nil, verticalRateFpm: Double? = nil,
                squawk: String? = nil, alert: AircraftAlert? = nil, isMilitary: Bool = false, fixTime: TimeInterval) {
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
        self.alert = alert
        self.isMilitary = isMilitary
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

/// One end of a route.
public struct RouteAirport: Hashable, Sendable {
    /// IATA code where there is one ("ORD"), else ICAO ("KORD").
    public var code: String
    /// City or municipality ("Chicago").
    public var city: String?
    /// Full airport name ("Chicago O'Hare International Airport").
    public var name: String?
    public var coordinate: Coordinate?

    public init(code: String, city: String? = nil, name: String? = nil, coordinate: Coordinate? = nil) {
        self.code = code
        self.city = city
        self.name = name
        self.coordinate = coordinate
    }
}

/// Route and airframe details for the info corner. All optional: lookups often miss.
public struct FlightDetails: Hashable, Sendable {
    public var origin: RouteAirport?
    public var destination: RouteAirport?
    public var airline: String?
    public var aircraftDescription: String?

    public init(origin: RouteAirport? = nil, destination: RouteAirport? = nil, airline: String? = nil, aircraftDescription: String? = nil) {
        self.origin = origin
        self.destination = destination
        self.airline = airline
        self.aircraftDescription = aircraftDescription
    }
}

/// How far along its route a flight is. Route databases go stale (flight numbers get reused),
/// so a position well off the route between the two airports yields nil rather than a wrong answer.
public struct RouteProgress: Hashable, Sendable {
    /// 0 at the origin, 1 at the destination.
    public var fraction: Double
    public var flownNM: Double
    public var remainingNM: Double

    public init?(origin: Coordinate, destination: Coordinate, position: Coordinate) {
        let total = Geo.distanceNM(origin, destination)
        let flown = Geo.distanceNM(origin, position)
        let remaining = Geo.distanceNM(position, destination)
        guard total > 1 else { return nil }
        // On the route the two legs sum to the total; allow for vectoring, holds and departures.
        guard flown + remaining <= total * 1.25 + 60 else { return nil }
        self.fraction = min(1, max(0, flown / (flown + remaining)))
        self.flownNM = flown
        self.remainingNM = remaining
    }
}

/// Something worth calling out: an emergency squawk or emergency status.
public enum AircraftAlert: String, Hashable, Sendable {
    case emergency, radioFailure, hijack, medical, minimumFuel

    /// Reserved transponder codes, then the ADS-B emergency status field.
    public static func from(squawk: String?, emergencyStatus: String?) -> AircraftAlert? {
        switch squawk {
        case "7700": return .emergency
        case "7600": return .radioFailure
        case "7500": return .hijack
        default: break
        }
        switch emergencyStatus?.lowercased() {
        case "general", "downed": return .emergency
        case "nordo": return .radioFailure
        case "unlawful": return .hijack
        case "lifeguard": return .medical
        case "minfuel": return .minimumFuel
        default: return nil
        }
    }

    public var title: String {
        switch self {
        case .emergency: "Emergency"
        case .radioFailure: "Radio failure"
        case .hijack: "Unlawful interference"
        case .medical: "Medical flight"
        case .minimumFuel: "Minimum fuel"
        }
    }
}
