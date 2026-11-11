import Foundation
import Testing
@testable import AirspaceCore

private struct Boom: Error {}

private final class MockSource: FlightSource, @unchecked Sendable {
    let name: String
    var fail: Bool
    private(set) var calls = 0
    init(_ name: String, fail: Bool) { self.name = name; self.fail = fail }
    func aircraft(near: Coordinate, radiusNM: Double) async throws -> [AircraftReport] {
        calls += 1
        if fail { throw Boom() }
        return [AircraftReport(hex: name, position: near, altitudeFt: 1000, fixTime: 0)]
    }
}

private final class Clock: @unchecked Sendable {
    var now: TimeInterval = 0
}

@Suite struct FallbackSourceTests {
    let here = Coordinate(latitude: 1, longitude: 2)

    @Test func usesPrimaryWhenHealthy() async throws {
        let a = MockSource("a", fail: false), b = MockSource("b", fail: false)
        let src = FallbackSource([a, b])
        #expect(try await src.aircraft(near: here, radiusNM: 10).first?.hex == "a")
        #expect(b.calls == 0)
    }

    @Test func switchesAfterRepeatedFailuresAndReturnsLater() async throws {
        let a = MockSource("a", fail: true), b = MockSource("b", fail: false)
        let clock = Clock()
        let src = FallbackSource([a, b], failuresBeforeSwitch: 2, retryPrimaryAfter: 300, now: { clock.now })

        await #expect(throws: Boom.self) { try await src.aircraft(near: here, radiusNM: 10) }
        // second failure switches and immediately tries the fallback
        #expect(try await src.aircraft(near: here, radiusNM: 10).first?.hex == "b")
        #expect(await src.activeName == "b")

        a.fail = false
        clock.now = 301
        #expect(try await src.aircraft(near: here, radiusNM: 10).first?.hex == "a")
    }

    /// The map center is rounded to 0.01° (about a kilometer) before it leaves the Mac, and
    /// the radius grows by a mile so the rounded circle still covers the whole map.
    @Test func endpointsBuildExpectedURLs() {
        let c = Coordinate(latitude: 41.97, longitude: -87.9)
        #expect(ReadsbSource.Endpoint.adsbLol.url(c, 25.4).absoluteString == "https://api.adsb.lol/v2/point/41.97/-87.90/27")
        #expect(ReadsbSource.Endpoint.adsbFi.url(c, 25).absoluteString == "https://opendata.adsb.fi/api/v2/lat/41.97/lon/-87.90/dist/26")
    }

    @Test(arguments: [(38.897_663, -77.036_574, "38.90/-77.04"), (-33.868_82, 151.209_29, "-33.87/151.21"), (0.004, -0.004, "0.00/-0.00")])
    func sendsOnlyARoundedLocation(_ lat: Double, _ lon: Double, _ expected: String) {
        let url = ReadsbSource.Endpoint.adsbLol.url(Coordinate(latitude: lat, longitude: lon), 10).absoluteString
        #expect(url == "https://api.adsb.lol/v2/point/\(expected)/11")
        // Never more than two decimals in any number of the path.
        #expect(url.range(of: #"\.\d{3}"#, options: .regularExpression) == nil)
    }
}
