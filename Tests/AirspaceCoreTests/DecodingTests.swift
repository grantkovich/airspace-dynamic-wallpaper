import Foundation
import Testing
@testable import AirspaceCore

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Suite struct ReadsbDecodingTests {
    @Test func decodesAdsbLolPointResponse() throws {
        let reports = try ReadsbDecoder.decode(try fixture("adsblol"), receivedAt: 1_000)
        #expect(reports.count == 6)

        let cessna = try #require(reports.first { $0.hex == "a588da" })
        #expect(cessna.callsign == "N456ER")         // trailing spaces trimmed
        #expect(cessna.typeCode == "C72R")
        #expect(cessna.registration == "N456ER")
        #expect(cessna.category == "A1")
        #expect(cessna.altitudeFt == 1100)
        #expect(cessna.onGround == false)
        #expect(abs(cessna.position.latitude - 42.204398) < 1e-9)
        #expect(cessna.groundSpeedKt == 75.2)
        #expect(cessna.trackDeg == 256.15)
        #expect(cessna.verticalRateFpm == 896)
        // fix time is local receive time minus seen_pos
        #expect(abs(cessna.fixTime - (1_000 - 0.584)) < 1e-9)
    }

    @Test func groundAltitudeIsOnGround() throws {
        let reports = try ReadsbDecoder.decode(try fixture("adsblol"), receivedAt: 0)
        let taxiing = try #require(reports.first { $0.hex == "a1a3c0" })
        #expect(taxiing.onGround)
        #expect(taxiing.altitudeFt == 0)
    }

    @Test func decodesAdsbFiAircraftKey() throws {
        let reports = try ReadsbDecoder.decode(try fixture("adsbfi"), receivedAt: 0)
        #expect(reports.count == 6)
        let delta = try #require(reports.first { $0.callsign == "DAL2012" })
        #expect(delta.altitudeFt == 33000)
        #expect(delta.typeCode == nil)
        #expect(delta.verticalRateFpm == -64)   // falls back to baro_rate
    }

    @Test func skipsAircraftWithoutPosition() throws {
        let json = #"{"ac":[{"hex":"abc123","flight":"TEST1"},{"hex":"def456","lat":1,"lon":2}]}"#
        let reports = try ReadsbDecoder.decode(Data(json.utf8), receivedAt: 0)
        #expect(reports.map(\.hex) == ["def456"])
        #expect(reports[0].callsign == nil)
    }

    @Test func emptyOrMissingListDecodesToEmpty() throws {
        #expect(try ReadsbDecoder.decode(Data(#"{"ac":[]}"#.utf8), receivedAt: 0).isEmpty)
        #expect(throws: (any Error).self) { try ReadsbDecoder.decode(Data(#"{"error":"nope"}"#.utf8), receivedAt: 0) }
    }
}

@Suite struct RouteDecodingTests {
    @Test func decodesAdsbdbRoute() throws {
        let json = #"""
        {"response":{"flightroute":{"callsign":"AAL100","airline":{"name":"American Airlines","icao":"AAL"},
        "origin":{"iata_code":"JFK","icao_code":"KJFK","municipality":"New York"},
        "destination":{"iata_code":"LHR","icao_code":"EGLL","municipality":"London"}}}}
        """#
        let route = try #require(try RouteDecoder.decodeRoute(Data(json.utf8)))
        #expect(route.origin == "JFK")
        #expect(route.destination == "LHR")
        #expect(route.airline == "American Airlines")
    }

    @Test func unknownCallsignIsNil() throws {
        #expect(try RouteDecoder.decodeRoute(Data(#"{"response":"unknown callsign"}"#.utf8)) == nil)
    }

    @Test func decodesAdsbdbAirline() throws {
        let json = #"{"response":[{"name":"SkyWest Airlines","icao":"SKW","iata":"OO"}]}"#
        #expect(try RouteDecoder.decodeAirlineName(Data(json.utf8)) == "SkyWest Airlines")
        #expect(try RouteDecoder.decodeAirlineName(Data(#"{"response":"unknown airline"}"#.utf8)) == nil)
    }

    @Test func decodesAdsbdbAircraft() throws {
        let json = #"{"response":{"aircraft":{"type":"172R","icao_type":"C72R","manufacturer":"Cessna","registration":"N456ER"}}}"#
        let info = try #require(try RouteDecoder.decodeAircraft(Data(json.utf8)))
        #expect(info.description == "Cessna 172R")
    }
}
