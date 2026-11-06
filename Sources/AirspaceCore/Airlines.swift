import Foundation

/// The four airline colour slots. Order matters only for tie-breaking.
public enum AirlineSlot: Int, CaseIterable, Codable, Sendable { case blue, amber, magenta, green }

public enum Airlines {
    /// ICAO airline designator from a callsign: three letters followed by a flight number.
    /// Registrations (N456ER, C-GABC) and anything else return nil.
    public static func code(fromCallsign callsign: String?) -> String? {
        guard let cs = callsign?.uppercased(), cs.count >= 4 else { return nil }
        let chars = Array(cs)
        guard chars[0...2].allSatisfy({ $0.isASCII && $0.isLetter }), chars[3].isNumber else { return nil }
        // US registrations look like N + digits, never three letters, so no ambiguity there.
        return String(chars[0...2])
    }

    struct Known {
        var name: String
        /// Closest slot to the brand colour, used when that slot is free.
        var slot: AirlineSlot?
    }

    /// Short names and brand-hue preferences for common carriers. Anything else is named via adsbdb.
    static let known: [String: Known] = [
        "UAL": .init(name: "United", slot: .blue), "AAL": .init(name: "American", slot: .blue),
        "DAL": .init(name: "Delta", slot: .magenta), "SWA": .init(name: "Southwest", slot: .amber),
        "ASA": .init(name: "Alaska", slot: .blue), "JBU": .init(name: "JetBlue", slot: .blue),
        "NKS": .init(name: "Spirit", slot: .amber), "FFT": .init(name: "Frontier", slot: .green),
        "AAY": .init(name: "Allegiant", slot: .amber), "HAL": .init(name: "Hawaiian", slot: .magenta),
        "SCX": .init(name: "Sun Country", slot: .amber), "MXY": .init(name: "Breeze", slot: .blue),
        "SKW": .init(name: "SkyWest", slot: .green), "RPA": .init(name: "Republic", slot: .green),
        "ENY": .init(name: "Envoy", slot: .blue), "EDV": .init(name: "Endeavor", slot: .magenta),
        "JIA": .init(name: "PSA", slot: .blue), "PDT": .init(name: "Piedmont", slot: .blue),
        "ASH": .init(name: "Mesa", slot: .blue), "QXE": .init(name: "Horizon", slot: .blue),
        "GJS": .init(name: "GoJet", slot: .green), "AWI": .init(name: "Air Wisconsin", slot: .green),
        "CPZ": .init(name: "Compass", slot: .magenta), "LYM": .init(name: "Key Lime", slot: .green),
        "FDX": .init(name: "FedEx", slot: .magenta), "UPS": .init(name: "UPS", slot: .amber),
        "GTI": .init(name: "Atlas", slot: .blue), "ABX": .init(name: "ABX Air", slot: .green),
        "ACA": .init(name: "Air Canada", slot: .magenta), "WJA": .init(name: "WestJet", slot: .green),
        "JZA": .init(name: "Jazz", slot: .magenta), "POE": .init(name: "Porter", slot: .blue),
        "AMX": .init(name: "Aeroméxico", slot: .blue), "VOI": .init(name: "Volaris", slot: .magenta),
        "BAW": .init(name: "British Airways", slot: .blue), "VIR": .init(name: "Virgin Atlantic", slot: .magenta),
        "DLH": .init(name: "Lufthansa", slot: .amber), "AFR": .init(name: "Air France", slot: .blue),
        "KLM": .init(name: "KLM", slot: .blue), "EIN": .init(name: "Aer Lingus", slot: .green),
        "RYR": .init(name: "Ryanair", slot: .blue), "EZY": .init(name: "easyJet", slot: .amber),
        "IBE": .init(name: "Iberia", slot: .magenta), "SWR": .init(name: "Swiss", slot: .magenta),
        "AUA": .init(name: "Austrian", slot: .magenta), "SAS": .init(name: "SAS", slot: .blue),
        "FIN": .init(name: "Finnair", slot: .blue), "ICE": .init(name: "Icelandair", slot: .amber),
        "TAP": .init(name: "TAP", slot: .green), "THY": .init(name: "Turkish", slot: .magenta),
        "UAE": .init(name: "Emirates", slot: .magenta), "QTR": .init(name: "Qatar", slot: .magenta),
        "ETD": .init(name: "Etihad", slot: .amber), "SIA": .init(name: "Singapore", slot: .amber),
        "CPA": .init(name: "Cathay", slot: .green), "JAL": .init(name: "JAL", slot: .magenta),
        "ANA": .init(name: "ANA", slot: .blue), "KAL": .init(name: "Korean Air", slot: .blue),
        "QFA": .init(name: "Qantas", slot: .magenta), "ANZ": .init(name: "Air New Zealand", slot: .green),
        "CCA": .init(name: "Air China", slot: .magenta), "CES": .init(name: "China Eastern", slot: .blue),
        "CSN": .init(name: "China Southern", slot: .blue), "AIC": .init(name: "Air India", slot: .magenta),
        "EJA": .init(name: "NetJets", slot: .amber), "LXJ": .init(name: "Flexjet", slot: .blue),
        "XOJ": .init(name: "XO", slot: .blue), "JRE": .init(name: "JetSuite", slot: .blue),
    ]

    public static func displayName(_ code: String) -> String? { known[code]?.name }
    static func preferredSlot(_ code: String) -> AirlineSlot? { known[code]?.slot }

    /// "SkyWest Airlines" → "SkyWest". Keeps names where the suffix is the identity ("British Airways").
    public static func shortName(_ full: String) -> String {
        for suffix in [" Air Lines", " Airlines", " Air", " Airways Inc", " Aviation"] where full.hasSuffix(suffix) {
            let trimmed = String(full.dropLast(suffix.count))
            if trimmed.split(separator: " ").count == 1 { return trimmed }
        }
        return full
    }
}

/// Gives the busiest airlines in view one of four colours. Colours follow the airline, not its
/// rank: an airline keeps its colour while it stays in view, and is only displaced by a newcomer
/// that is clearly busier (twice its count and at least 3 more aircraft).
public struct AirlineColorAssigner: Sendable {
    public private(set) var assignments: [String: AirlineSlot] = [:]

    public init() {}

    public mutating func update(counts: [String: Int]) {
        // Release airlines that have left.
        assignments = assignments.filter { (counts[$0.key] ?? 0) > 0 }

        let waiting = counts.filter { assignments[$0.key] == nil && $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        for (code, count) in waiting {
            if let slot = freeSlot(preferring: Airlines.preferredSlot(code)) {
                assignments[code] = slot
                continue
            }
            // Full: displace the smallest holder only if this airline is clearly busier.
            guard let (weakest, weakestCount) = assignments
                .map({ ($0.key, counts[$0.key] ?? 0) })
                .min(by: { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 > $1.0 }),
                count >= weakestCount * 2, count - weakestCount >= 3 else { continue }
            let slot = assignments.removeValue(forKey: weakest)!
            assignments[code] = slot
        }
    }

    private func freeSlot(preferring preferred: AirlineSlot?) -> AirlineSlot? {
        let used = Set(assignments.values)
        if let p = preferred, !used.contains(p) { return p }
        return AirlineSlot.allCases.first { !used.contains($0) }
    }
}
