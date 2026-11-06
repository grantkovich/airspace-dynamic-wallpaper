import Foundation
import Testing
@testable import AirspaceCore

@Suite struct AirlineCodeTests {
    @Test(arguments: [("UAL412", "UAL"), ("DAL2012", "DAL"), ("SKW5375", "SKW"), ("AAL100A", "AAL")] as [(String, String)])
    func extractsAirline(_ callsign: String, _ code: String) {
        #expect(Airlines.code(fromCallsign: callsign) == code)
    }

    @Test(arguments: ["N456ER", "N4627F", "C-GABC", "UAL", "", "12345", "TEST"])
    func privateOrUnknownHasNoAirline(_ callsign: String) {
        #expect(Airlines.code(fromCallsign: callsign) == nil)
    }

    @Test func shortensNames() {
        #expect(Airlines.shortName("SkyWest Airlines") == "SkyWest")
        #expect(Airlines.shortName("Delta Air Lines") == "Delta")
        #expect(Airlines.shortName("Envoy Air") == "Envoy")
        #expect(Airlines.shortName("British Airways") == "British Airways")
        #expect(Airlines.displayName("UAL") == "United")
    }
}

@Suite struct AirlineColorAssignerTests {
    @Test func busiestAirlinesGetSlotsPreferringBrandHue() {
        var a = AirlineColorAssigner()
        a.update(counts: ["UAL": 12, "AAL": 9, "SKW": 7, "DAL": 4, "SWA": 2, "FDX": 1])
        #expect(a.assignments.count == 4)
        #expect(a.assignments["UAL"] == .blue)        // United prefers blue
        #expect(a.assignments["DAL"] == .magenta)     // Delta red → magenta
        #expect(a.assignments["SWA"] == nil)
        #expect(Set(a.assignments.values).count == 4)
    }

    @Test func colorsFollowTheAirlineNotItsRank() {
        var a = AirlineColorAssigner()
        a.update(counts: ["UAL": 10, "AAL": 8, "SKW": 6, "DAL": 4])
        let before = a.assignments
        a.update(counts: ["UAL": 3, "AAL": 9, "SKW": 11, "DAL": 5])   // reshuffled ranks
        #expect(a.assignments == before)
    }

    @Test func departedAirlineFreesItsSlot() {
        var a = AirlineColorAssigner()
        a.update(counts: ["UAL": 10, "AAL": 8, "SKW": 6, "DAL": 4])
        let deltaSlot = a.assignments["DAL"]
        a.update(counts: ["UAL": 10, "AAL": 8, "SKW": 6, "JBU": 3])
        #expect(a.assignments["DAL"] == nil)
        #expect(a.assignments["JBU"] == deltaSlot)
    }

    @Test func muchBusierNewcomerDisplacesSmallestHolder() {
        var a = AirlineColorAssigner()
        a.update(counts: ["UAL": 10, "AAL": 8, "SKW": 6, "DAL": 1])
        a.update(counts: ["UAL": 10, "AAL": 8, "SKW": 6, "DAL": 1, "SWA": 7])
        #expect(a.assignments["SWA"] != nil)
        #expect(a.assignments["DAL"] == nil)
        // …but a near-tie doesn't churn colours.
        a.update(counts: ["UAL": 10, "AAL": 8, "SKW": 6, "SWA": 7, "DAL": 6])
        #expect(a.assignments["SWA"] != nil && a.assignments["DAL"] == nil)
    }
}
