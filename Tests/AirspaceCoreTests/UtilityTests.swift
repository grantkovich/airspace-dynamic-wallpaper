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
