import Foundation

public enum MapStyle: String, Codable, CaseIterable, Sendable { case schematic, appleMap, pureField }
public enum AppearanceMode: String, Codable, CaseIterable, Sendable { case light, dark, dynamic }
public enum DynamicSource: String, Codable, CaseIterable, Sendable { case system, sun }
public enum LabelMode: String, Codable, CaseIterable, Sendable { case off, callsign, callsignAltitude }
public enum ColorMode: String, Codable, CaseIterable, Sendable { case altitude, monochrome }
public enum GlyphStyle: String, Codable, CaseIterable, Sendable { case light, arrow, silhouette }
public enum Corner: String, Codable, CaseIterable, Sendable { case topLeft, topRight, bottomLeft, bottomRight }
public enum DisplayTarget: String, Codable, CaseIterable, Sendable { case all, mainOnly }

public enum LocationSetting: Codable, Hashable, Sendable {
    /// Follow Core Location.
    case system
    /// A typed search (zip, city) and the place it resolved to.
    case search(query: String, resolved: Coordinate?, name: String?)
    /// Typed coordinates.
    case coordinates(Coordinate, name: String?)
}

/// Everything the user can change. Decoding is tolerant: unknown or invalid values fall back
/// to defaults, so adding settings never wipes someone's configuration.
public struct WallpaperSettings: Codable, Hashable, Sendable {
    public static let zoomRange: ClosedRange<Double> = 5...150
    public static let trailChoices: [Double] = [0, 1, 3, 10]
    public static let pollChoices: [Double] = [5, 10, 15, 30]

    public var location: LocationSetting = .system
    /// Overrides the place name shown in the info corner.
    public var displayName: String = ""

    public var mapStyle: MapStyle = .schematic
    /// Radius from the centre to the nearer screen edge, in statute miles.
    public var zoomMiles: Double = 35 { didSet { zoomMiles = min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, zoomMiles)) } }
    public var showRangeRings = true
    public var showRunways = true
    public var showRoads = true
    public var showDotGrid = true
    /// Wash the Apple map with the palette so it sits back like the other styles.
    public var tintAppleMap = true

    public var labelMode: LabelMode = .callsign
    public var colorMode: ColorMode = .altitude
    public var trailMinutes: Double = 3
    public var glyph: GlyphStyle = .light
    public var pulse = true
    public var brightness: Double = 0.9
    public var showGroundTraffic = false
    public var minAltitudeFt: Double = 0

    public var appearance: AppearanceMode = .dynamic
    public var dynamicSource: DynamicSource = .sun

    public var infoEnabled = true
    public var infoCorner: Corner = .bottomLeft
    public var infoShowClock = true
    public var infoShowCoordinates = true
    public var infoShowCount = true
    public var infoShowOverhead = true

    public var pollInterval: Double = 5
    public var batterySaver = true
    public var fpsCap: Double = 20
    public var displays: DisplayTarget = .all

    public var hasCompletedOnboarding = false

    public init() {}

    public var radiusNM: Double { zoomMiles * Geo.nmPerMile }

    public var powerSettings: PowerSettings {
        PowerSettings(pollInterval: pollInterval, fpsCap: fpsCap, batterySaver: batterySaver)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case location, displayName, mapStyle, zoomMiles, showRangeRings, showRunways, showRoads, showDotGrid,
             tintAppleMap, labelMode, colorMode, trailMinutes, glyph, pulse, brightness, showGroundTraffic,
             minAltitudeFt, appearance, dynamicSource, infoEnabled, infoCorner, infoShowClock,
             infoShowCoordinates, infoShowCount, infoShowOverhead, pollInterval, batterySaver, fpsCap,
             displays, hasCompletedOnboarding
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        let d = WallpaperSettings()
        location = v(.location, d.location)
        displayName = v(.displayName, d.displayName)
        mapStyle = v(.mapStyle, d.mapStyle)
        zoomMiles = v(.zoomMiles, d.zoomMiles)
        showRangeRings = v(.showRangeRings, d.showRangeRings)
        showRunways = v(.showRunways, d.showRunways)
        showRoads = v(.showRoads, d.showRoads)
        showDotGrid = v(.showDotGrid, d.showDotGrid)
        tintAppleMap = v(.tintAppleMap, d.tintAppleMap)
        labelMode = v(.labelMode, d.labelMode)
        colorMode = v(.colorMode, d.colorMode)
        trailMinutes = v(.trailMinutes, d.trailMinutes)
        glyph = v(.glyph, d.glyph)
        pulse = v(.pulse, d.pulse)
        brightness = v(.brightness, d.brightness)
        showGroundTraffic = v(.showGroundTraffic, d.showGroundTraffic)
        minAltitudeFt = v(.minAltitudeFt, d.minAltitudeFt)
        appearance = v(.appearance, d.appearance)
        dynamicSource = v(.dynamicSource, d.dynamicSource)
        infoEnabled = v(.infoEnabled, d.infoEnabled)
        infoCorner = v(.infoCorner, d.infoCorner)
        infoShowClock = v(.infoShowClock, d.infoShowClock)
        infoShowCoordinates = v(.infoShowCoordinates, d.infoShowCoordinates)
        infoShowCount = v(.infoShowCount, d.infoShowCount)
        infoShowOverhead = v(.infoShowOverhead, d.infoShowOverhead)
        pollInterval = v(.pollInterval, d.pollInterval)
        batterySaver = v(.batterySaver, d.batterySaver)
        fpsCap = v(.fpsCap, d.fpsCap)
        displays = v(.displays, d.displays)
        hasCompletedOnboarding = v(.hasCompletedOnboarding, d.hasCompletedOnboarding)
    }
}
