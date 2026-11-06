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

    @Test func endpointsBuildExpectedURLs() {
        let c = Coordinate(latitude: 41.97, longitude: -87.9)
        #expect(ReadsbSource.Endpoint.adsbLol.url(c, 25.4).absoluteString == "https://api.adsb.lol/v2/point/41.9700/-87.9000/26")
        #expect(ReadsbSource.Endpoint.adsbFi.url(c, 25).absoluteString == "https://opendata.adsb.fi/api/v2/lat/41.9700/lon/-87.9000/dist/25")
    }
}
