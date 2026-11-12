import CoreGraphics
import Foundation
import Testing
@testable import AirspaceCore

@Suite struct CoordinateParserTests {
    @Test(arguments: [
        ("41.97, -87.90", 41.97, -87.90),
        ("41.97 -87.90", 41.97, -87.90),
        ("41.97N 87.90W", 41.97, -87.90),
        ("N41.97 W87.90", 41.97, -87.90),
        ("33.9425° S, 151.1750° E", -33.9425, 151.175),
        ("41°58'12\"N 87°54'W", 41.97, -87.90),
        ("87.90W 41.97N", 41.97, -87.90),
        ("  51.47,-0.4543 ", 51.47, -0.4543),
    ])
    func parses(_ input: String, _ lat: Double, _ lon: Double) throws {
        let c = try #require(CoordinateParser.parse(input))
        #expect(abs(c.latitude - lat) < 1e-4)
        #expect(abs(c.longitude - lon) < 1e-4)
    }

    @Test(arguments: ["60601", "Chicago, IL", "", "91, 10", "10, 200", "41.9 N 87.9 N", "1 2 3"])
    func rejects(_ input: String) {
        #expect(CoordinateParser.parse(input) == nil)
    }
}

@Suite struct SolarTests {
    let chicago = Coordinate(latitude: 41.88, longitude: -87.63)

    private func utc(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: s)!
    }

    @Test func summerSolsticeNoonIsHigh() {
        // Solar noon in Chicago on the June solstice is ~17:50 UTC; elevation ≈ 90 − 41.88 + 23.44 = 71.56°
        let e = Solar.elevation(at: utc("2026-06-21T17:50:00Z"), coordinate: chicago)
        #expect(abs(e - 71.5) < 0.5)
    }

    @Test func midnightIsBelowHorizon() {
        #expect(Solar.elevation(at: utc("2026-06-21T05:50:00Z"), coordinate: chicago) < -20)
    }

    @Test func daylightFactorBlendsAcrossTwilight() {
        #expect(Solar.daylight(elevation: -10) == 0)
        #expect(Solar.daylight(elevation: 10) == 1)
        let mid = Solar.daylight(elevation: -1.5)
        #expect(mid > 0.3 && mid < 0.7)
    }
}

@Suite struct LabelLayoutTests {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    let size = CGSize(width: 60, height: 12)

    @Test func prefersRightSlot() {
        let placed = LabelLayout.layout([LabelRequest(id: "a", anchor: CGPoint(x: 500, y: 500), size: size, priority: 0)],
                                        obstacles: [], bounds: bounds, previous: [:])
        #expect(placed.first?.slot == .right)
        #expect(placed.first?.rect.minX ?? 0 > 500)
    }

    @Test func avoidsOverlapByMovingOrDropping() {
        let reqs = [
            LabelRequest(id: "a", anchor: CGPoint(x: 500, y: 500), size: size, priority: 0),
            LabelRequest(id: "b", anchor: CGPoint(x: 505, y: 500), size: size, priority: 1),
            LabelRequest(id: "c", anchor: CGPoint(x: 502, y: 502), size: size, priority: 2),
        ]
        let placed = LabelLayout.layout(reqs, obstacles: [], bounds: bounds, previous: [:])
        for i in placed.indices {
            for j in placed.indices where j > i {
                #expect(!placed[i].rect.intersects(placed[j].rect))
            }
        }
        #expect(placed.first?.id == "a")   // highest priority always wins its slot
    }

    @Test func respectsEdgesAndObstacles() {
        let nearRightEdge = LabelRequest(id: "a", anchor: CGPoint(x: 990, y: 500), size: size, priority: 0)
        #expect(LabelLayout.layout([nearRightEdge], obstacles: [], bounds: bounds, previous: [:]).first?.slot == .left)

        let blocked = LabelLayout.layout([LabelRequest(id: "a", anchor: CGPoint(x: 500, y: 500), size: size, priority: 0)],
                                         obstacles: [CGRect(x: 0, y: 0, width: 1000, height: 1000)], bounds: bounds, previous: [:])
        #expect(blocked.isEmpty)
    }

    /// The grid must place exactly what the obvious all-pairs version places.
    @Test(arguments: [1, 2, 3, 4, 5])
    func gridMatchesBruteForce(seed: UInt64) {
        var rng = SeededRandom(seed: seed)
        let reqs = (0..<400).map { i in
            LabelRequest(id: "a\(i)", anchor: CGPoint(x: .random(in: 0...1000, using: &rng), y: .random(in: 0...1000, using: &rng)),
                         size: CGSize(width: .random(in: 30...90, using: &rng), height: 12),
                         priority: .random(in: 0...1000, using: &rng))
        }
        let obstacles = [CGRect(x: 0, y: 700, width: 420, height: 300), CGRect(x: 488, y: 488, width: 24, height: 24)]
        let previous = Dictionary(uniqueKeysWithValues: reqs.prefix(100).map { ($0.id, LabelSlot.allCases[Int($0.priority) % 4]) })
        let grid = LabelLayout.layout(reqs, obstacles: obstacles, bounds: bounds, previous: previous, glyphRadius: 5)
        let brute = bruteForce(reqs, obstacles: obstacles, previous: previous, glyphRadius: 5)
        #expect(grid == brute)
        #expect(grid.count > 50)
    }

    private func bruteForce(_ requests: [LabelRequest], obstacles: [CGRect], previous: [String: LabelSlot],
                            glyphRadius: CGFloat) -> [PlacedLabel] {
        let glyphs = requests.map { (id: $0.id, rect: CGRect(x: $0.anchor.x - glyphRadius, y: $0.anchor.y - glyphRadius,
                                                             width: glyphRadius * 2, height: glyphRadius * 2)) }
        var placed: [PlacedLabel] = []
        for req in requests.sorted(by: { $0.priority < $1.priority }) {
            var order = LabelSlot.allCases
            if let prev = previous[req.id], let i = order.firstIndex(of: prev) { order.remove(at: i); order.insert(prev, at: 0) }
            for slot in order {
                let r = req.rect(slot)
                guard bounds.contains(r), !obstacles.contains(where: { $0.intersects(r) }),
                      !placed.contains(where: { $0.rect.intersects(r) }),
                      !glyphs.contains(where: { $0.id != req.id && $0.rect.intersects(r) }) else { continue }
                placed.append(PlacedLabel(id: req.id, rect: r, slot: slot))
                break
            }
        }
        return placed
    }

    @Test func keepsPreviousSlotWhenFree() {
        let req = LabelRequest(id: "a", anchor: CGPoint(x: 500, y: 500), size: size, priority: 0)
        #expect(LabelLayout.layout([req], obstacles: [], bounds: bounds, previous: ["a": .below]).first?.slot == .below)
    }
}

@Suite struct SettingsTests {
    @Test func roundTrips() throws {
        var s = WallpaperSettings()
        s.mapStyle = .appleMap
        s.zoomMiles = 80
        s.labelMode = .callsignAltitude
        s.location = .coordinates(Coordinate(latitude: 1, longitude: 2), name: "Somewhere")
        let back = try JSONDecoder().decode(WallpaperSettings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }

    @Test func missingKeysFallBackToDefaults() throws {
        let partial = Data(#"{"zoomMiles": 12, "mapStyle": "pureField", "bogus": true, "labelMode": "nonsense"}"#.utf8)
        let s = try JSONDecoder().decode(WallpaperSettings.self, from: partial)
        #expect(s.zoomMiles == 12)
        #expect(s.mapStyle == .pureField)
        #expect(s.labelMode == WallpaperSettings().labelMode)
        #expect(s.appearance == WallpaperSettings().appearance)
    }

    @Test func migratesOldDotDefaultToPlaneIcons() throws {
        let v1 = try JSONDecoder().decode(WallpaperSettings.self, from: Data(#"{"glyph": "light"}"#.utf8))
        #expect(v1.glyph == .silhouette)
        #expect(v1.schemaVersion == WallpaperSettings.currentSchema)
        // A deliberate choice made after the change is kept.
        let v2 = try JSONDecoder().decode(WallpaperSettings.self, from: Data(#"{"glyph": "light", "schemaVersion": 2}"#.utf8))
        #expect(v2.glyph == .light)
        #expect(v1.colorMode == .airline)
        let chose = try JSONDecoder().decode(WallpaperSettings.self, from: Data(#"{"colorMode": "altitude", "schemaVersion": 3}"#.utf8))
        #expect(chose.colorMode == .altitude)
        let arrow = try JSONDecoder().decode(WallpaperSettings.self, from: Data(#"{"glyph": "arrow"}"#.utf8))
        #expect(arrow.glyph == .arrow)
    }

    @Test func zoomIsClamped() {
        var s = WallpaperSettings()
        s.zoomMiles = 1_000
        #expect(s.zoomMiles == WallpaperSettings.zoomRange.upperBound)
    }
}

@Suite struct PaletteTests {
    @Test func altitudeRampIsWarmLowCoolHigh() {
        let p = Palette.night
        let low = p.altitudeColor(1_000), high = p.altitudeColor(38_000)
        #expect(low.r > low.b)
        #expect(high.b > high.r)
    }

    @Test func mixEndpoints() {
        #expect(Palette.mix(.night, .aluminum, 0) == .night)
        #expect(Palette.mix(.night, .aluminum, 1) == .aluminum)
    }
}

@Suite struct GeoDataTests {
    static var url: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/geodata.bin").standardizedFileURL
    }

    @Test func decodesBundledData() throws {
        let geo = try GeoData.load(from: Self.url)
        #expect(geo.layers[.land]?.isEmpty == false)
        #expect(geo.layers[.lakes]?.isEmpty == false)
        // Lake Michigan exists and is near Chicago
        let chicago = Coordinate(latitude: 41.88, longitude: -87.63)
        let bounds = GeoBounds(minLat: 41.5, maxLat: 42.5, minLon: -88, maxLon: -86.5)
        #expect(geo.features(.lakes, in: bounds).isEmpty == false)
        let ord = try #require(geo.airports.first { $0.code == "ORD" })
        #expect(Geo.distanceNM(ord.position, chicago) < 20)
        #expect(ord.runways.count >= 6)
    }

    @Test func rejectsGarbage() {
        #expect(throws: (any Error).self) { try GeoData.decode(Data("nope".utf8)) }
    }
}

@Suite struct SchematicTests {
    @Test func buildsChicagoWithLakeAndRunways() throws {
        let geo = try GeoData.load(from: GeoDataTests.url)
        let p = Projection(center: Coordinate(latitude: 41.97, longitude: -87.90), size: CGSize(width: 1600, height: 1000), radiusNM: 30)
        let paths = SchematicGeometry.build(geo, projection: p)
        #expect(!paths.lakes.isEmpty)
        #expect(!paths.runways.isEmpty)
        #expect(paths.airportLabels.contains { $0.code == "ORD" && $0.isMajor })
        // The bounding box of Lake Michigan's path should reach into the right half of the screen.
        #expect(paths.lakes.boundingBoxOfPath.maxX > 800)
    }

    @Test func noWrapArtifactsAcrossAntimeridian() throws {
        let geo = try GeoData.load(from: GeoDataTests.url)
        // Fiji sits on the antimeridian
        let p = Projection(center: Coordinate(latitude: -17.75, longitude: 179.9), size: CGSize(width: 1000, height: 800), radiusNM: 60)
        let paths = SchematicGeometry.build(geo, projection: p)
        #expect(!paths.land.isEmpty)
        let box = paths.land.boundingBoxOfPath
        #expect(box.width < 1_000_000)   // a wrap bug would span the whole world's width
    }

    @Test func ringRadii() {
        #expect(RangeRings.radii(forZoomMiles: 35) == [5, 10, 25])
        #expect(RangeRings.radii(forZoomMiles: 5) == [1, 2.5])
        #expect(RangeRings.radii(forZoomMiles: 150) == [25, 50, 100])
    }
}

@Suite struct AircraftClassTests {
    @Test(arguments: [
        ("A3", "B738", AircraftClass.jet), ("A3", "A20N", .jet), ("A5", "B77W", .heavy), ("A5", "B789", .heavy),
        ("A5", "B744", .quad), ("A5", "A388", .quad), ("A3", "CRJ9", .tailJet), ("A2", "GLF5", .tailJet),
        ("A2", "C56X", .tailJet), ("A2", "AT76", .turboprop), ("A1", "C172", .light), ("A7", "EC35", .helicopter),
        ("A3", nil, .jet), (nil, "B39M", .jet), (nil, nil, .other),
    ] as [(String?, String?, AircraftClass)])
    func classifies(_ category: String?, _ type: String?, _ expected: AircraftClass) {
        #expect(AircraftClass.classify(category: category, typeCode: type) == expected)
    }
}

/// Deterministic generator for reproducible randomized tests (SplitMix64).
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite struct RouteProgressTests {
    let ord = Coordinate(latitude: 41.9786, longitude: -87.9048)
    let lga = Coordinate(latitude: 40.7772, longitude: -73.8726)

    @Test func midRouteIsAboutHalfway() throws {
        let mid = Coordinate(latitude: 41.6, longitude: -80.9)
        let p = try #require(RouteProgress(origin: ord, destination: lga, position: mid))
        #expect(abs(p.fraction - 0.5) < 0.05)
        #expect(abs(p.flownNM + p.remainingNM - Geo.distanceNM(ord, lga)) < 5)
    }

    @Test func endsClampAndNearbyDeparturesCount() throws {
        #expect(try #require(RouteProgress(origin: ord, destination: lga, position: ord)).fraction == 0)
        // Climbing out westbound before turning east: off the line but close to the airport.
        let climbOut = Geo.offset(ord, distanceNM: 15, bearingDeg: 270)
        #expect(RouteProgress(origin: ord, destination: lga, position: climbOut) != nil)
    }

    @Test func positionFarOffRouteMeansStaleRoute() {
        let denver = Coordinate(latitude: 39.86, longitude: -104.67)
        #expect(RouteProgress(origin: ord, destination: lga, position: denver) == nil)
    }
    /// RPA4534, 2026-11-12: adsbdb said Pittsburgh → Philadelphia, but the jet was over College
    /// Park, MD at FL320 heading 225°, away from both. Close enough to pass the distance check,
    /// so the heading has to catch it.
    @Test func headingAwayFromTheDestinationMeansStaleRoute() {
        let pit = Coordinate(latitude: 40.4915, longitude: -80.2329)
        let phl = Coordinate(latitude: 39.8719, longitude: -75.2411)
        let overMaryland = Coordinate(latitude: 39.0304, longitude: -76.9496)
        #expect(RouteProgress(origin: pit, destination: phl, position: overMaryland) != nil)   // distance alone passes
        #expect(RouteProgress(origin: pit, destination: phl, position: overMaryland, trackDeg: 225) == nil)
        #expect(RouteProgress(origin: pit, destination: phl, position: overMaryland, trackDeg: 50) != nil)
    }

    /// A route listed backwards puts the plane flying toward its "origin".
    @Test func flyingTowardTheOriginMeansStaleRoute() {
        let mid = Coordinate(latitude: 41.6, longitude: -80.9)
        #expect(RouteProgress(origin: ord, destination: lga, position: mid, trackDeg: 95) != nil)
        #expect(RouteProgress(origin: ord, destination: lga, position: mid, trackDeg: 275) == nil)
    }

    /// Near either airport anything goes: departures turn and arrivals get vectored.
    @Test func anyHeadingNearTheAirports() {
        let climbOut = Geo.offset(ord, distanceNM: 15, bearingDeg: 270)
        #expect(RouteProgress(origin: ord, destination: lga, position: climbOut, trackDeg: 270) != nil)
        let downwind = Geo.offset(lga, distanceNM: 20, bearingDeg: 0)
        #expect(RouteProgress(origin: ord, destination: lga, position: downwind, trackDeg: 270) != nil)
    }
}

@Suite struct VerifiedRouteTests {
    let pit = RouteAirport(code: "PIT", city: "Pittsburgh", coordinate: Coordinate(latitude: 40.4915, longitude: -80.2329))
    let phl = RouteAirport(code: "PHL", city: "Philadelphia", coordinate: Coordinate(latitude: 39.8719, longitude: -75.2411))

    @Test func showsARouteOnlyWhenThePositionFitsIt() {
        let details = FlightDetails(origin: pit, destination: phl)
        let overMaryland = Coordinate(latitude: 39.0304, longitude: -76.9496)
        #expect(details.verifiedRoute(position: overMaryland, trackDeg: 225) == nil)
        let onTheWay = Geo.intermediate(pit.coordinate!, phl.coordinate!, fraction: 0.5)
        let route = details.verifiedRoute(position: onTheWay, trackDeg: Geo.bearingDeg(from: onTheWay, to: phl.coordinate!))
        #expect(route?.origin == pit)
        #expect(route?.destination == phl)
    }

    /// adsbdb often lists a flight number's route backwards. DAL2411, 2026-11-12: listed
    /// Atlanta → New York, but over Virginia at FL340 flying 233°, toward Atlanta. On the line
    /// and pointed at the listed origin, it's the same route the other way.
    @Test func aRouteListedBackwardsIsFlipped() throws {
        let atl = RouteAirport(code: "ATL", city: "Atlanta", coordinate: Coordinate(latitude: 33.6367, longitude: -84.4281))
        let lga = RouteAirport(code: "LGA", city: "New York", coordinate: Coordinate(latitude: 40.7772, longitude: -73.8726))
        let overVirginia = Coordinate(latitude: 38.533, longitude: -78.047)
        let route = try #require(FlightDetails(origin: atl, destination: lga).verifiedRoute(position: overVirginia, trackDeg: 233))
        #expect(route.origin == lga)
        #expect(route.destination == atl)
        #expect(route.progress.fraction > 0.2 && route.progress.fraction < 0.5)
    }

    /// RPA4534 points at neither end (225° vs 300° to Pittsburgh), so it isn't flipped either.
    @Test func aFlightHeadingForNeitherEndShowsNoRoute() {
        let overMaryland = Coordinate(latitude: 39.0304, longitude: -76.9496)
        #expect(FlightDetails(origin: pit, destination: phl).verifiedRoute(position: overMaryland, trackDeg: 225) == nil)
        #expect(FlightDetails(origin: phl, destination: pit).verifiedRoute(position: overMaryland, trackDeg: 225) == nil)
    }

    /// Without airport coordinates the route can't be checked, so it isn't shown.
    @Test func unverifiableRoutesAreHidden() {
        let details = FlightDetails(origin: RouteAirport(code: "PIT"), destination: RouteAirport(code: "PHL"))
        #expect(details.verifiedRoute(position: Coordinate(latitude: 40, longitude: -78), trackDeg: 90) == nil)
    }
}

@Suite struct AlertTests {
    @Test func reservedSquawks() {
        #expect(AircraftAlert.from(squawk: "7700", emergencyStatus: "none") == .emergency)
        #expect(AircraftAlert.from(squawk: "7600", emergencyStatus: nil) == .radioFailure)
        #expect(AircraftAlert.from(squawk: "7500", emergencyStatus: nil) == .hijack)
        #expect(AircraftAlert.from(squawk: "1200", emergencyStatus: "none") == nil)
        #expect(AircraftAlert.from(squawk: nil, emergencyStatus: nil) == nil)
    }

    @Test func emergencyStatusField() {
        #expect(AircraftAlert.from(squawk: "4521", emergencyStatus: "lifeguard") == .medical)
        #expect(AircraftAlert.from(squawk: "4521", emergencyStatus: "minfuel") == .minimumFuel)
        #expect(AircraftAlert.from(squawk: "4521", emergencyStatus: "general") == .emergency)
    }
}

@Suite struct GeoExtrasTests {
    let ord = Coordinate(latitude: 41.9786, longitude: -87.9048)

    @Test func bearingsAndCompass() {
        #expect(abs(Geo.bearingDeg(from: ord, to: Geo.offset(ord, distanceNM: 20, bearingDeg: 90)) - 90) < 0.5)
        #expect(abs(Geo.bearingDeg(from: ord, to: Coordinate(latitude: 43, longitude: -87.9048))) < 0.01)
        #expect(Geo.compassPoint(0) == "N")
        #expect(Geo.compassPoint(359) == "N")
        #expect(Geo.compassPoint(44) == "NE")
        #expect(Geo.compassPoint(225) == "SW")
        #expect(Geo.compassPoint(-90) == "W")
    }

    @Test func greatCircleInterpolation() {
        let lhr = Coordinate(latitude: 51.47, longitude: -0.4543)
        let mid = Geo.intermediate(ord, lhr, fraction: 0.5)
        let total = Geo.distanceNM(ord, lhr)
        #expect(abs(Geo.distanceNM(ord, mid) - total / 2) < 1)
        #expect(mid.latitude > 55)   // great circle bows north of both ends
        #expect(Geo.distanceNM(Geo.intermediate(ord, lhr, fraction: 0), ord) < 0.01)
        #expect(Geo.distanceNM(Geo.intermediate(ord, lhr, fraction: 1), lhr) < 0.01)
    }
}

@Suite struct DailyTallyTests {
    @Test func countsDistinctAndResetsAtMidnight() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Chicago")!
        let morning = cal.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 9))!
        let night = cal.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 23, minute: 59))!
        let tomorrow = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 0, minute: 1))!
        var t = DailyTally()
        let first = t.record(["a", "b"], on: morning, calendar: cal)
        let repeatSighting = t.record(["a"], on: night, calendar: cal)
        let newSighting = t.record(["c"], on: night, calendar: cal)
        #expect(first && !repeatSighting && newSighting)
        #expect(t.count == 3)
        t.record(["a"], on: tomorrow, calendar: cal)
        #expect(t.count == 1 && t.day == "2026-11-09")
    }
}
