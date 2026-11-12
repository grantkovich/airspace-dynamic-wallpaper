import Foundation

/// Anything that can list aircraft near a point. Adding a local receiver (dump1090/readsb on a
/// Raspberry Pi) later is one more conformance.
public protocol FlightSource: Sendable {
    var name: String { get }
    func aircraft(near center: Coordinate, radiusNM: Double) async throws -> [AircraftReport]
}

public enum SourceError: Error, Equatable {
    case http(Int)
}

/// Names the app, its version and a page where feed operators can reach the developer.
let userAgent: String = {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    return "Airspace/\(version) (macOS live wallpaper; +https://grantkovich.com/apps/airspace/)"
}()

/// Free, keyless readsb-compatible aggregator APIs.
public struct ReadsbSource: FlightSource {
    public enum Endpoint: String, Sendable, CaseIterable {
        case adsbLol = "adsb.lol"
        case adsbFi = "adsb.fi"

        /// Only a rounded map center leaves the Mac: 0.01° is about a kilometer, enough to keep a
        /// home address private. Rounding moves the center at most ~0.4 nm, so the radius grows
        /// by a mile and the circle still covers the whole map.
        public func url(_ c: Coordinate, _ radiusNM: Double) -> URL {
            let lat = String(format: "%.2f", c.latitude), lon = String(format: "%.2f", c.longitude)
            let nm = Int(min(250, max(1, (radiusNM + 1).rounded(.up))))
            switch self {
            case .adsbLol: return URL(string: "https://api.adsb.lol/v2/point/\(lat)/\(lon)/\(nm)")!
            case .adsbFi: return URL(string: "https://opendata.adsb.fi/api/v2/lat/\(lat)/lon/\(lon)/dist/\(nm)")!
            }
        }
    }

    public let endpoint: Endpoint
    let session: URLSession
    public var name: String { endpoint.rawValue }

    public init(_ endpoint: Endpoint, session: URLSession = .airspace) {
        self.endpoint = endpoint
        self.session = session
    }

    public func aircraft(near center: Coordinate, radiusNM: Double) async throws -> [AircraftReport] {
        var request = URLRequest(url: endpoint.url(center, radiusNM), timeoutInterval: 12)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SourceError.http(http.statusCode)
        }
        return try ReadsbDecoder.decode(data, receivedAt: Date().timeIntervalSince1970)
    }
}

extension URLSession {
    /// No cookies or cache: every poll should hit the network.
    public static let airspace: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 2
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()
}

/// Tries sources in order. After `failuresBeforeSwitch` consecutive failures it moves to the next
/// one, and drifts back to the first after `retryPrimaryAfter` seconds.
public actor FallbackSource: FlightSource {
    private let sources: [any FlightSource]
    private let failuresBeforeSwitch: Int
    private let retryPrimaryAfter: TimeInterval
    private let now: @Sendable () -> TimeInterval
    private var index = 0
    private var failures = 0
    private var switchedAt: TimeInterval = 0

    public nonisolated var name: String { "fallback" }
    public var activeName: String { sources[index].name }

    public init(_ sources: [any FlightSource], failuresBeforeSwitch: Int = 2, retryPrimaryAfter: TimeInterval = 300,
                now: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        precondition(!sources.isEmpty)
        self.sources = sources
        self.failuresBeforeSwitch = failuresBeforeSwitch
        self.retryPrimaryAfter = retryPrimaryAfter
        self.now = now
    }

    public func aircraft(near center: Coordinate, radiusNM: Double) async throws -> [AircraftReport] {
        if index != 0, now() - switchedAt >= retryPrimaryAfter {
            index = 0
            failures = 0
        }
        do {
            let result = try await sources[index].aircraft(near: center, radiusNM: radiusNM)
            failures = 0
            return result
        } catch {
            failures += 1
            guard failures >= failuresBeforeSwitch, sources.count > 1 else { throw error }
            index = (index + 1) % sources.count
            failures = 0
            switchedAt = now()
            return try await sources[index].aircraft(near: center, radiusNM: radiusNM)
        }
    }
}

/// Route + airframe lookups from adsbdb.com, cached for the session (misses too).
public actor FlightDetailsService {
    private var routes: [String: RouteDecoder.Route?] = [:]
    private var airframes: [String: RouteDecoder.Airframe?] = [:]
    private var airlineNames: [String: String?] = [:]
    private let session: URLSession

    public init(session: URLSession = .airspace) { self.session = session }

    public func details(callsign: String?, hex: String) async -> FlightDetails {
        var d = FlightDetails()
        if let cs = callsign, Self.looksLikeFlightNumber(cs), let route = await route(cs) {
            d.origin = route.origin
            d.destination = route.destination
            d.airline = route.airline
        }
        if let frame = await airframe(hex) { d.aircraftDescription = frame.description }
        return d
    }

    /// Airline name for an ICAO designator, shortened ("SkyWest Airlines" → "SkyWest").
    public func airlineName(_ code: String) async -> String? {
        if let known = Airlines.displayName(code) { return known }
        if let cached = airlineNames[code] { return cached }
        guard let data = try? await fetch("https://api.adsbdb.com/v0/airline/\(code)") else { return nil }
        let name = (try? RouteDecoder.decodeAirlineName(data)).flatMap { $0 }.map(Airlines.shortName)
        airlineNames[code] = .some(name)
        return name
    }

    /// Registrations like N456ER have no route; airline flights are 3 letters + digits.
    static func looksLikeFlightNumber(_ cs: String) -> Bool {
        cs.range(of: #"^[A-Z]{3}\d{1,4}[A-Z]?$"#, options: .regularExpression) != nil
    }

    /// The app runs for days; drop the caches rather than let them grow without bound.
    private static let cacheLimit = 4_000

    private func route(_ callsign: String) async -> RouteDecoder.Route? {
        if let cached = routes[callsign] { return cached }
        if routes.count >= Self.cacheLimit { routes.removeAll(keepingCapacity: true) }
        // Only cache real answers (including "unknown"); a network error should be retried next time.
        guard let data = try? await fetch("https://api.adsbdb.com/v0/callsign/\(callsign)") else { return nil }
        let r = (try? RouteDecoder.decodeRoute(data)) ?? nil
        routes[callsign] = .some(r)
        return r
    }

    private func airframe(_ hex: String) async -> RouteDecoder.Airframe? {
        if let cached = airframes[hex] { return cached }
        if airframes.count >= Self.cacheLimit { airframes.removeAll(keepingCapacity: true) }
        guard let data = try? await fetch("https://api.adsbdb.com/v0/aircraft/\(hex)") else { return nil }
        let a = (try? RouteDecoder.decodeAircraft(data)) ?? nil
        airframes[hex] = .some(a)
        return a
    }

    private func fetch(_ url: String) async throws -> Data {
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 500 || http.statusCode == 429 {
            throw SourceError.http(http.statusCode)
        }
        return data
    }
}
