import Foundation

public struct RGBA: Hashable, Sendable {
    public var r, g, b, a: Double

    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public init(hex: UInt32, alpha: Double = 1) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255, alpha)
    }

    public func with(alpha: Double) -> RGBA { RGBA(r, g, b, alpha) }

    public static func mix(_ x: RGBA, _ y: RGBA, _ t: Double) -> RGBA {
        RGBA(x.r + (y.r - x.r) * t, x.g + (y.g - x.g) * t, x.b + (y.b - x.b) * t, x.a + (y.a - x.a) * t)
    }
}

/// Colour tokens for one appearance. Night and Aluminum are the two poles; Dynamic mixes them.
public struct Palette: Hashable, Sendable {
    public var water, land, urban, dotGrid, river, road, stateLine: RGBA
    public var runway, airportLabel, ring, ringLabel, crosshair: RGBA
    public var textPrimary, textSecondary, textTertiary: RGBA
    public var monochrome: RGBA
    /// Altitude ramp stops (feet → colour), ascending.
    public var altitudeStops: [Double]
    public var altitudeColors: [RGBA]
    /// 0 (light surfaces, glow reads as a soft halo) … 1 (dark, full bloom).
    public var glow: Double
    public var isDark: Bool

    public func altitudeColor(_ ft: Double) -> RGBA {
        guard let first = altitudeStops.first, ft > first else { return altitudeColors[0] }
        for i in 1..<altitudeStops.count where ft <= altitudeStops[i] {
            let t = (ft - altitudeStops[i - 1]) / (altitudeStops[i] - altitudeStops[i - 1])
            return RGBA.mix(altitudeColors[i - 1], altitudeColors[i], t)
        }
        return altitudeColors[altitudeColors.count - 1]
    }

    static let stops: [Double] = [0, 5_000, 12_000, 24_000, 38_000]

    public static let night = Palette(
        water: RGBA(hex: 0x0B0C0E), land: RGBA(hex: 0x121316), urban: RGBA(hex: 0x17181B),
        dotGrid: RGBA(hex: 0x2A2C30), river: RGBA(hex: 0x1C2026), road: RGBA(hex: 0x202226),
        stateLine: RGBA(hex: 0x2B2D31), runway: RGBA(hex: 0x55575B), airportLabel: RGBA(hex: 0x6E6F72),
        ring: RGBA(hex: 0x2C2E33), ringLabel: RGBA(hex: 0x56585C), crosshair: RGBA(hex: 0x8A8780),
        textPrimary: RGBA(hex: 0xECE8E1), textSecondary: RGBA(hex: 0x9A968F), textTertiary: RGBA(hex: 0x5E5C58),
        monochrome: RGBA(hex: 0xF4F1EA),
        altitudeStops: stops,
        altitudeColors: [RGBA(hex: 0xFFB13B), RGBA(hex: 0xFF7A59), RGBA(hex: 0xE86FB8), RGBA(hex: 0x7CC8FF), RGBA(hex: 0x6F8CFF)],
        glow: 1, isDark: true)

    public static let aluminum = Palette(
        water: RGBA(hex: 0xDCDAD4), land: RGBA(hex: 0xECEAE5), urban: RGBA(hex: 0xE3E1DB),
        dotGrid: RGBA(hex: 0xCFCCC5), river: RGBA(hex: 0xCDCBC5), road: RGBA(hex: 0xD9D6CF),
        stateLine: RGBA(hex: 0xC9C6BF), runway: RGBA(hex: 0x8F8C85), airportLabel: RGBA(hex: 0x86837D),
        ring: RGBA(hex: 0xCBC8C1), ringLabel: RGBA(hex: 0x9C9993), crosshair: RGBA(hex: 0x5D5B57),
        textPrimary: RGBA(hex: 0x1C1D1F), textSecondary: RGBA(hex: 0x6A6863), textTertiary: RGBA(hex: 0xA19E98),
        monochrome: RGBA(hex: 0x26272A),
        altitudeStops: stops,
        altitudeColors: [RGBA(hex: 0xD98200), RGBA(hex: 0xE0502E), RGBA(hex: 0xB83F8C), RGBA(hex: 0x1E86C8), RGBA(hex: 0x3A55D9)],
        glow: 0.25, isDark: false)

    /// Linear blend between two palettes; `t` = 0 → a, 1 → b.
    public static func mix(_ a: Palette, _ b: Palette, _ t: Double) -> Palette {
        if t <= 0 { return a }
        if t >= 1 { return b }
        func m(_ k: KeyPath<Palette, RGBA>) -> RGBA { RGBA.mix(a[keyPath: k], b[keyPath: k], t) }
        return Palette(
            water: m(\.water), land: m(\.land), urban: m(\.urban), dotGrid: m(\.dotGrid), river: m(\.river),
            road: m(\.road), stateLine: m(\.stateLine), runway: m(\.runway), airportLabel: m(\.airportLabel),
            ring: m(\.ring), ringLabel: m(\.ringLabel), crosshair: m(\.crosshair),
            textPrimary: m(\.textPrimary), textSecondary: m(\.textSecondary), textTertiary: m(\.textTertiary),
            monochrome: m(\.monochrome), altitudeStops: a.altitudeStops,
            altitudeColors: zip(a.altitudeColors, b.altitudeColors).map { RGBA.mix($0, $1, t) },
            glow: a.glow + (b.glow - a.glow) * t, isDark: t < 0.5 ? a.isDark : b.isDark)
    }

    /// Resolves the palette for the user's appearance setting.
    /// - Parameters:
    ///   - systemIsDark: current macOS appearance.
    ///   - daylight: 0…1 from `Solar.daylight`, used when following the sun.
    public static func resolve(_ mode: AppearanceMode, source: DynamicSource, systemIsDark: Bool, daylight: Double) -> Palette {
        switch mode {
        case .light: return .aluminum
        case .dark: return .night
        case .dynamic:
            switch source {
            case .system: return systemIsDark ? .night : .aluminum
            case .sun: return mix(.night, .aluminum, daylight)
            }
        }
    }
}
