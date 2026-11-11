import Foundation

/// How a plane is painted, part by part, seen from above.
public struct LiveryPaint: Hashable, Sendable {
    public var body: RGBA
    public var wings: RGBA
    /// The fin, seen from above as a stripe down the rear fuselage: forward and aft halves.
    public var tailFore: RGBA
    public var tailAft: RGBA
    public var engines: RGBA

    public init(body: RGBA, wings: RGBA, tailFore: RGBA, tailAft: RGBA, engines: RGBA) {
        self.body = body
        self.wings = wings
        self.tailFore = tailFore
        self.tailAft = tailAft
        self.engines = engines
    }

    public func map(_ f: (RGBA) -> RGBA) -> LiveryPaint {
        LiveryPaint(body: f(body), wings: f(wings), tailFore: f(tailFore), tailAft: f(tailAft), engines: f(engines))
    }

    /// Most airliners: white crown, grey wing tops.
    static let white = RGBA(hex: 0xF3F4F5)
    static let wingGrey = RGBA(hex: 0xB4B9C0)
}

/// An airline's livery colours, as close to the paint as a small icon can carry.
public struct Livery: Hashable, Sendable {
    /// The colour people picture the airline by. Single-colour icons and trails use it.
    public var primary: RGBA
    /// A second livery colour, used when the primary would be mistaken for a busier airline's.
    public var secondary: RGBA?
    /// The full paint. By default a white body and grey wings with the tail in the primary and
    /// secondary colours and engines in the primary, which is how most airliners look from above.
    public var paint: LiveryPaint

    init(_ primary: UInt32, _ secondary: UInt32? = nil, body: UInt32? = nil, tail: (UInt32, UInt32)? = nil,
         engines: UInt32? = nil, wings: UInt32? = nil) {
        let p = RGBA(hex: primary), s = secondary.map { RGBA(hex: $0) }
        self.primary = p
        self.secondary = s
        self.paint = LiveryPaint(
            body: body.map { RGBA(hex: $0) } ?? LiveryPaint.white,
            wings: wings.map { RGBA(hex: $0) } ?? LiveryPaint.wingGrey,
            tailFore: tail.map { RGBA(hex: $0.0) } ?? p,
            tailAft: tail.map { RGBA(hex: $0.1) } ?? s ?? p,
            engines: engines.map { RGBA(hex: $0) } ?? p)
    }
}

public enum Liveries {
    /// Brand colours approximated from each airline's current livery and branding. Regional
    /// partners are resolved to their mainline (see `Airlines.identity`), so they paint the same.
    /// Liveries that are mostly white, silver or black use their most recognisable accent.
    static let table: [String: Livery] = [
        // North America
        "UAL": Livery(0x1B5BB7),             // United: rhapsody blue tail and engines
        "AAL": Livery(0x0078D2, 0xC30019,    // American: silver, flag tail, silver engines
                      body: 0xC9CED4, tail: (0x0078D2, 0xC30019), engines: 0xB0B6BD),
        "DAL": Livery(0xC8102E, 0x2A5AA8,    // Delta: red tail, navy engines
                      tail: (0xC8102E, 0x9B0E22), engines: 0x1B3A70),
        "SWA": Livery(0x304CB2, 0xFFBF27,    // Southwest Heart: bold blue crown, yellow accents
                      body: 0x304CB2, tail: (0x304CB2, 0xC8102E), engines: 0xFFBF27, wings: 0xC4C8CE),
        "ASA": Livery(0x2FA4B8, 0x01426A),   // Alaska: atoll teal, midnight
        "JBU": Livery(0x0033A0, 0x00A3E0),   // JetBlue: blue, sky
        "NKS": Livery(0xFFE600, body: 0xFFE600, engines: 0x2A2A2A),   // Spirit: yellow all over
        "FFT": Livery(0x00915A),             // Frontier: green
        "AAY": Livery(0xF59A23, 0x0055A5),   // Allegiant: sunset orange, blue
        "HAL": Livery(0x6E3B9E, 0xCE0E72),   // Hawaiian: purple, orchid
        "SCX": Livery(0xEF6C00, 0x1F3A68),   // Sun Country: orange, navy
        "MXY": Livery(0x0E85C7, 0x1C2D5A),   // Breeze: breeze blue, navy
        "ACA": Livery(0xE8112D, tail: (0x1A1A1A, 0xE8112D), engines: 0x1A1A1A),   // Air Canada: black tail, red leaf
        "WJA": Livery(0x00A0B0, 0x1E3A5F),   // WestJet: teal, navy
        "POE": Livery(0x2A5D8F, 0xB8975A),   // Porter: navy, gold
        "AMX": Livery(0x2B4D8C, 0xA7A9AC),   // Aeroméxico: navy, silver
        "VOI": Livery(0xA50069),             // Volaris: magenta
        "FDX": Livery(0x4D148C, 0xFF6600),   // FedEx: purple, orange
        "UPS": Livery(0x7A5230, 0xFFB500, tail: (0x5A3A22, 0xFFB500), engines: 0x5A3A22),   // UPS: brown tail, gold shield
        // Europe
        "BAW": Livery(0x2A5CAA, 0xEB2226),   // British Airways: chatham blue, red
        "VIR": Livery(0xE10A0A, 0x6C1D45),   // Virgin Atlantic: red, plum
        "DLH": Livery(0x1B2F6E, 0xFFAD00),   // Lufthansa: navy, crane yellow
        "AFR": Livery(0x1B3A8A, 0xE4002B),   // Air France: navy, red
        "KLM": Livery(0x00A1DE, body: 0x00A1DE, engines: 0x00A1DE),   // KLM: blue crown
        "EIN": Livery(0x00857D),             // Aer Lingus: teal
        "RYR": Livery(0x073590, 0xF1C933),   // Ryanair: navy, yellow
        "EZY": Livery(0xFF6600),             // easyJet: orange tail and engines
        "IBE": Livery(0xD7192D, 0xFFCC00),   // Iberia: red, yellow
        "SWR": Livery(0xE30613),             // Swiss: red
        "AUA": Livery(0xEE2D24),             // Austrian: red
        "SAS": Livery(0x2B4FA0),             // SAS: blue
        "FIN": Livery(0x1B2F8A, 0x9AA9C6),   // Finnair: blue, frost
        "ICE": Livery(0x1D3B71, 0xFFC72C),   // Icelandair: blue, gold
        "TAP": Livery(0x00A651, 0xE31937),   // TAP: green, red
        "THY": Livery(0xE81932),             // Turkish: red
        // Middle East, Asia, Oceania
        "UAE": Livery(0xD71921, 0xC8A951, tail: (0xD71921, 0x00843D), engines: 0xB4B9C0),   // Emirates: flag tail
        "QTR": Livery(0x8A1538),             // Qatar: burgundy
        "ETD": Livery(0xBD8B13, body: 0xE9E1D0),   // Etihad: sand body, gold tail
        "SIA": Livery(0xF99F1C, 0x1B3C7A),   // Singapore: gold, navy
        "CPA": Livery(0x00645A),             // Cathay: jade
        "JAL": Livery(0xCC0000),             // JAL: tsurumaru red
        "ANA": Livery(0x1D5AA5, 0x4CC0E8),   // ANA: triton blue, mohican blue
        "KAL": Livery(0x5DB8E6, 0xC4122F,    // Korean Air: sky-blue crown, taegeuk tail
                      body: 0x8DC8EA, tail: (0xC4122F, 0x1D4E9E), engines: 0xB4B9C0),
        "QFA": Livery(0xE40000),             // Qantas: red
        "ANZ": Livery(0x00AFA9, tail: (0x111111, 0x111111), engines: 0x111111),   // Air New Zealand: black tail
        "CCA": Livery(0xE30D14),             // Air China: red
        "CES": Livery(0xC8161D, 0x1B3988),   // China Eastern: red, blue
        "CSN": Livery(0x0079C2, 0xD6001C),   // China Southern: sky blue, kapok red
        "AIC": Livery(0xC8102E, 0x6B2C6E),   // Air India: red, aubergine
    ]

    public static func livery(_ code: String) -> Livery? { table[code] }
}

/// Chooses primary or secondary livery for each airline in view, so two busy airlines with
/// near-identical paint (United and American blue) stay apart. Like the slot assigner, choices
/// stick while an airline stays in view so colours don't flip from one update to the next.
public struct LiveryAssigner: Sendable {
    public private(set) var chosen: [String: RGBA] = [:]

    public init() {}

    /// Colours closer than this (OKLab, lightness normalised) read as the same airline.
    static let minimumSeparation = 0.07

    public mutating func update(counts: [String: Int]) {
        chosen = chosen.filter { (counts[$0.key] ?? 0) > 0 }
        // Airlines with only one livery colour choose first: they have nothing to fall back to,
        // so United keeps its blue and American, which can, moves to its red.
        let waiting = counts.filter { chosen[$0.key] == nil && $0.value > 0 && Liveries.livery($0.key) != nil }
            .sorted {
                let a = Liveries.livery($0.key)?.secondary == nil, b = Liveries.livery($1.key)?.secondary == nil
                if a != b { return a }
                return $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
            }
        for (code, _) in waiting {
            guard let livery = Liveries.livery(code) else { continue }
            let taken = Array(chosen.values)
            if let secondary = livery.secondary, Self.clashes(livery.primary, taken), !Self.clashes(secondary, taken) {
                chosen[code] = secondary
            } else {
                chosen[code] = livery.primary
            }
        }
    }

    /// The raw livery colour for an airline: its current choice, else its primary.
    public func color(_ code: String) -> RGBA? {
        chosen[code] ?? Liveries.livery(code)?.primary
    }

    static func clashes(_ c: RGBA, _ others: [RGBA]) -> Bool {
        others.contains { OKLab.hueDistance(c, $0) < minimumSeparation }
    }
}

/// Just enough of the OKLab colour space to move a brand colour to a legible lightness
/// without changing its hue.
public enum OKLab {
    public struct Lab: Hashable, Sendable { public var L, a, b: Double }

    public static func lab(_ c: RGBA) -> Lab {
        func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let r = lin(c.r), g = lin(c.g), b = lin(c.b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return Lab(L: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                   a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                   b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    /// sRGB for a Lab colour, or nil if it falls outside the sRGB gamut.
    public static func rgb(_ p: Lab, alpha: Double = 1) -> RGBA? {
        let l = pow(p.L + 0.3963377774 * p.a + 0.2158037573 * p.b, 3)
        let m = pow(p.L - 0.1055613458 * p.a - 0.0638541728 * p.b, 3)
        let s = pow(p.L - 0.0894841775 * p.a - 1.2914855480 * p.b, 3)
        let lr = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let lg = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let lb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        func enc(_ v: Double) -> Double? {
            guard v >= -0.0005, v <= 1.0005 else { return nil }
            let x = min(1, max(0, v))
            return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
        }
        guard let r = enc(lr), let g = enc(lg), let b = enc(lb) else { return nil }
        return RGBA(r, g, b, alpha)
    }

    /// Moves `c` into the lightness band, keeping its hue and as much chroma as sRGB allows.
    public static func fit(_ c: RGBA, lightness: ClosedRange<Double>) -> RGBA {
        var p = lab(c)
        p.L = min(lightness.upperBound, max(lightness.lowerBound, p.L))
        if let direct = rgb(p, alpha: c.a) { return direct }
        // Out of gamut at the new lightness: find the most chroma that still fits.
        var lo = 0.0, hi = 1.0
        for _ in 0..<20 {
            let k = (lo + hi) / 2
            if rgb(Lab(L: p.L, a: p.a * k, b: p.b * k)) != nil { lo = k } else { hi = k }
        }
        return rgb(Lab(L: p.L, a: p.a * lo, b: p.b * lo), alpha: c.a) ?? c
    }

    /// Difference in hue and chroma, mostly ignoring lightness, since rendering moves lightness
    /// anyway. Two blues of different darkness end up looking alike on the map.
    public static func hueDistance(_ x: RGBA, _ y: RGBA) -> Double {
        let p = lab(x), q = lab(y)
        return sqrt(pow(p.a - q.a, 2) + pow(p.b - q.b, 2) + pow((p.L - q.L) * 0.25, 2))
    }
}
