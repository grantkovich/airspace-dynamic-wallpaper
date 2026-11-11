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

@Suite struct RegionalAirlineTests {
    @Test(arguments: [
        ("JIA5501", "AAL", "American Eagle"), ("ENY3811", "AAL", "American Eagle"), ("PDT5960", "AAL", "American Eagle"),
        ("EDV4677", "DAL", "Delta Connection"), ("GJS4566", "UAL", "United Express"), ("ASH6012", "UAL", "United Express"),
        ("QXE2104", "ASA", "Alaska"), ("JZA8611", "ACA", "Air Canada Express"),
    ] as [(String, String, String)])
    func exclusiveRegionalsFlyUnderTheirMainline(_ callsign: String, _ brand: String, _ program: String) throws {
        let id = try #require(Airlines.identity(fromCallsign: callsign))
        #expect(id.brandCode == brand)
        #expect(id.program == program)
        #expect(id.operatorCode == String(callsign.prefix(3)))
        #expect(id.isRegional)
    }

    @Test(arguments: [
        ("SKW3018", "AAL"), ("SKW3927", "DAL"), ("SKW4036", "DAL"), ("SKW4711", "UAL"), ("SKW5375", "UAL"),
        ("SKW6198", "UAL"), ("SKW118R", "SKW"), ("SKW9795", "SKW"), ("RPA3712", "UAL"), ("RPA4557", "AAL"),
    ] as [(String, String)])
    func multiPartnerRegionalsGoByFlightNumberBlock(_ callsign: String, _ brand: String) {
        #expect(Airlines.brandCode(fromCallsign: callsign) == brand)
    }

    @Test func mainlineAndGroupingOff() throws {
        let ual = try #require(Airlines.identity(fromCallsign: "UAL412"))
        #expect(ual.brandCode == "UAL" && ual.program == nil && !ual.isRegional)
        #expect(Airlines.brandCode(fromCallsign: "JIA5501", groupRegionals: false) == "JIA")
        #expect(Airlines.brandCode(fromCallsign: "N456ER") == nil)
    }
}

@Suite struct AirlineColorAssignerTests {
    @Test func busiestAirlinesGetSlotsPreferringBrandHue() {
        var a = AirlineColorAssigner()
        a.update(counts: ["UAL": 12, "AAL": 9, "SKW": 7, "DAL": 4, "SWA": 2, "FDX": 1])
        #expect(a.assignments.count == 4)
        #expect(a.assignments["UAL"] == .blue)        // United prefers blue
        #expect(a.assignments["AAL"] == .magenta)     // American red → magenta, taken before Delta
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

@Suite struct LiveryTests {
    @Test func busierAirlineKeepsItsLiveryAndTheClashSwitches() throws {
        var a = LiveryAssigner()
        a.update(counts: ["UAL": 30, "AAL": 12, "SWA": 9])
        let aal = try #require(Liveries.livery("AAL")), swa = try #require(Liveries.livery("SWA"))
        #expect(a.color("UAL") == Liveries.livery("UAL")?.primary)
        #expect(a.color("AAL") == aal.secondary)   // blue taken by United → red
        #expect(a.color("SWA") == swa.secondary)   // blue taken → sunrise yellow
    }

    @Test func singleColourAirlineWinsATie() throws {
        var a = LiveryAssigner()
        a.update(counts: ["AAL": 22, "UAL": 22])
        #expect(a.color("UAL") == Liveries.livery("UAL")?.primary)
        #expect(a.color("AAL") == Liveries.livery("AAL")?.secondary)
    }

    @Test func choicesStickWhileInViewAndReleaseWhenGone() throws {
        var a = LiveryAssigner()
        a.update(counts: ["UAL": 30, "AAL": 12])
        let red = a.color("AAL")
        a.update(counts: ["UAL": 5, "AAL": 40])    // American now busier, but keeps red
        #expect(a.color("AAL") == red)
        a.update(counts: ["AAL": 40])              // United gone; a fresh American would be blue
        a.update(counts: ["AAL": 0])
        a.update(counts: ["AAL": 3])
        #expect(a.color("AAL") == Liveries.livery("AAL")?.primary)
    }

    @Test func distinctLiveriesAllKeepPrimary() {
        var a = LiveryAssigner()
        a.update(counts: ["UAL": 10, "NKS": 8, "FFT": 6, "DAL": 4])
        for code in ["UAL", "NKS", "FFT", "DAL"] { #expect(a.color(code) == Liveries.livery(code)?.primary) }
        #expect(a.color("XYZ") == nil)
    }

    @Test func oklabRoundTrips() throws {
        for hex: UInt32 in [0x1B5BB7, 0xFFE600, 0xC8102E, 0x00915A, 0x000000, 0xFFFFFF] {
            let c = RGBA(hex: hex)
            let back = try #require(OKLab.rgb(OKLab.lab(c)))
            #expect(abs(back.r - c.r) < 1e-4 && abs(back.g - c.g) < 1e-4 && abs(back.b - c.b) < 1e-4)
        }
    }

    /// Every livery must land in each surface's lightness band and stay a real sRGB colour.
    @Test(arguments: [Palette.night, Palette.aluminum])
    func everyLiveryFitsTheSurface(palette: Palette) {
        for (code, livery) in Liveries.table {
            for raw in [livery.primary] + (livery.secondary.map { [$0] } ?? []) {
                let c = palette.livery(raw)
                let L = OKLab.lab(c).L
                #expect(palette.liveryLightness.contains(L) || abs(L - palette.liveryLightness.lowerBound) < 0.01
                        || abs(L - palette.liveryLightness.upperBound) < 0.01, "\(code) L=\(L)")
                #expect([c.r, c.g, c.b].allSatisfy { (0...1).contains($0) }, "\(code)")
            }
        }
    }

    @Test func navyBrightensOnNightAndYellowDeepensOnAluminum() {
        let navy = RGBA(hex: 0x1B2F6E), yellow = RGBA(hex: 0xFFE600)
        #expect(OKLab.lab(Palette.night.livery(navy)).L > OKLab.lab(navy).L + 0.2)
        #expect(OKLab.lab(Palette.aluminum.livery(yellow)).L <= 0.621)
        // Hue survives: still more blue than red, still more red-green than blue.
        let n = Palette.night.livery(navy), y = Palette.aluminum.livery(yellow)
        #expect(n.b > n.r && y.r > y.b && y.g > y.b)
    }
}

@Suite struct LiveryPaintTests {
    @Test func defaultPaintIsWhiteBodyWithTailAndEnginesInLiveryColours() throws {
        let ual = try #require(Liveries.livery("UAL")).paint
        #expect(ual.body == LiveryPaint.white && ual.wings == LiveryPaint.wingGrey)
        #expect(ual.tailFore == RGBA(hex: 0x1B5BB7) && ual.tailAft == RGBA(hex: 0x1B5BB7) && ual.engines == RGBA(hex: 0x1B5BB7))
        let jbu = try #require(Liveries.livery("JBU")).paint
        #expect(jbu.tailFore == RGBA(hex: 0x0033A0) && jbu.tailAft == RGBA(hex: 0x00A3E0))   // two-tone from secondary
    }

    @Test func overridesForDistinctiveLiveries() throws {
        #expect(try #require(Liveries.livery("SWA")).paint.body == RGBA(hex: 0x304CB2))
        #expect(try #require(Liveries.livery("NKS")).paint.body == RGBA(hex: 0xFFE600))
        let aal = try #require(Liveries.livery("AAL")).paint
        #expect(aal.body == RGBA(hex: 0xC9CED4) && aal.tailFore != aal.tailAft)
    }

    @Test func nightLiftsDarkPaintButKeepsWhite() throws {
        let aca = try #require(Liveries.livery("ACA")).paint
        let night = Palette.night.livery(aca)
        #expect(OKLab.lab(night.tailFore).L >= 0.449)      // black tail lifted off the dark map
        #expect(OKLab.lab(night.body).L > 0.95)            // white crown stays white
        #expect(Palette.aluminum.livery(aca) == aca.map { OKLab.fit($0, lightness: 0...1) })
    }
}
