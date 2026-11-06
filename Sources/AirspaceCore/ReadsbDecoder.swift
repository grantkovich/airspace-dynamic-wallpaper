import Foundation

public enum DecodingFailure: Error, Equatable {
    case missingAircraftList
    case serverMessage(String)
}

/// Decodes the readsb-style JSON served by adsb.lol (`ac`) and adsb.fi (`aircraft`).
public enum ReadsbDecoder {
    public static func decode(_ data: Data, receivedAt: TimeInterval) throws -> [AircraftReport] {
        let root = try JSONSerialization.jsonObject(with: data)
        guard let dict = root as? [String: Any] else { throw DecodingFailure.missingAircraftList }
        guard let list = (dict["ac"] ?? dict["aircraft"]) as? [[String: Any]] else {
            if let message = dict["error"] as? String ?? dict["msg"] as? String {
                throw DecodingFailure.serverMessage(message)
            }
            throw DecodingFailure.missingAircraftList
        }
        return list.compactMap { report(from: $0, receivedAt: receivedAt) }
    }

    static func report(from a: [String: Any], receivedAt: TimeInterval) -> AircraftReport? {
        guard let hex = (a["hex"] as? String)?.lowercased(),
              let lat = number(a["lat"]), let lon = number(a["lon"]) else { return nil }
        let position = Coordinate(latitude: lat, longitude: lon)
        guard position.isValid else { return nil }

        var onGround = false
        var altitude: Double = 0
        if let alt = a["alt_baro"] as? String, alt == "ground" {
            onGround = true
        } else if let alt = number(a["alt_baro"]) ?? number(a["alt_geom"]) {
            altitude = max(0, alt)
        }

        let seenPos = number(a["seen_pos"]) ?? number(a["seen"]) ?? 0
        return AircraftReport(
            hex: hex,
            callsign: trimmed(a["flight"]),
            registration: trimmed(a["r"]),
            typeCode: trimmed(a["t"]),
            category: trimmed(a["category"]),
            position: position,
            altitudeFt: altitude,
            onGround: onGround,
            groundSpeedKt: number(a["gs"]),
            trackDeg: number(a["track"]) ?? number(a["true_heading"]),
            verticalRateFpm: number(a["geom_rate"]) ?? number(a["baro_rate"]),
            squawk: trimmed(a["squawk"]),
            fixTime: receivedAt - max(0, seenPos)
        )
    }

    private static func number(_ v: Any?) -> Double? {
        switch v {
        case let n as NSNumber where CFGetTypeID(n) != CFBooleanGetTypeID(): return n.doubleValue
        default: return nil
        }
    }

    private static func trimmed(_ v: Any?) -> String? {
        guard let s = (v as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}

/// Decodes adsbdb.com responses.
public enum RouteDecoder {
    public struct Route: Hashable, Sendable {
        public var origin: String?
        public var destination: String?
        public var airline: String?
    }

    public struct Airframe: Hashable, Sendable {
        public var manufacturer: String?
        public var type: String?
        public var description: String {
            [manufacturer, type].compactMap { $0 }.joined(separator: " ")
        }
    }

    public static func decodeRoute(_ data: Data) throws -> Route? {
        guard let response = try responseObject(data),
              let fr = response["flightroute"] as? [String: Any] else { return nil }
        func code(_ key: String) -> String? {
            guard let ap = fr[key] as? [String: Any] else { return nil }
            return (ap["iata_code"] as? String) ?? (ap["icao_code"] as? String)
        }
        let airline = (fr["airline"] as? [String: Any])?["name"] as? String
        return Route(origin: code("origin"), destination: code("destination"), airline: airline)
    }

    public static func decodeAircraft(_ data: Data) throws -> Airframe? {
        guard let response = try responseObject(data),
              let ac = response["aircraft"] as? [String: Any] else { return nil }
        return Airframe(manufacturer: ac["manufacturer"] as? String, type: ac["type"] as? String)
    }

    private static func responseObject(_ data: Data) throws -> [String: Any]? {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return root?["response"] as? [String: Any]
    }
}
