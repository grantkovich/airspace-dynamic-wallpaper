import AirspaceCore
import AppKit
import Observation

/// The nearest airborne flight, shown in the info corner.
struct OverheadFlight: Equatable {
    var hex: String
    var details: FlightDetails?
}

/// Single source of truth: settings, resolved location, live traffic and power state.
@MainActor @Observable
final class AppModel {
    static let defaultsKey = "airspace.settings.v1"

    var settings: WallpaperSettings {
        didSet {
            guard settings != oldValue else { return }
            persist()
            settingsChanged(from: oldValue)
        }
    }

    // MARK: Location
    private(set) var center: Coordinate?
    private(set) var resolvedPlaceName: String?
    private(set) var locationMessage: String?
    private(set) var isResolvingLocation = false

    // MARK: Traffic
    @ObservationIgnored var tracker = AircraftTracker()
    private(set) var lastSuccess: Date?
    private(set) var fetchError: String?
    private(set) var activeSourceName = ReadsbSource.Endpoint.adsbLol.rawValue
    private(set) var aircraftInView = 0
    private(set) var overhead: OverheadFlight?
    /// Bumps on every successful fetch so lightweight views can refresh.
    private(set) var dataGeneration = 0

    // MARK: Map data
    private(set) var geo: GeoData?

    // MARK: Power & appearance
    var powerInputs = PowerInputs() {
        didSet {
            guard powerInputs != oldValue else { return }
            let wasSuspended = powerMode.pollInterval == nil
            updatePowerMode()
            if wasSuspended && powerMode.pollInterval != nil { refreshSoon() }
        }
    }
    private(set) var powerMode = PowerMode(kind: .normal, pollInterval: 5, fps: 30)
    var systemIsDark = false
    var paused: Bool {
        get { powerInputs.paused }
        set { powerInputs.paused = newValue }
    }

    @ObservationIgnored private let source = FallbackSource([ReadsbSource(.adsbLol), ReadsbSource(.adsbFi)])
    @ObservationIgnored private let detailsService = FlightDetailsService()
    @ObservationIgnored let location = LocationProvider()
    @ObservationIgnored private var nextFetch = Date.distantPast
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var resolveTask: Task<Void, Never>?
    /// Largest wallpaper size in points, set by the window controller; drives the fetch radius.
    @ObservationIgnored var largestScreenSize = CGSize(width: 1728, height: 1117)
    @ObservationIgnored var primaryScreenSize = CGSize(width: 1728, height: 1117)

    init(settings: WallpaperSettings? = nil, startServices: Bool = true) {
        self.settings = settings ?? Self.loadSettings()
        tracker.trailDuration = max(10, self.settings.trailMinutes * 60)
        updatePowerMode()
        guard startServices else { return }
        loadGeoData()
        location.onUpdate = { [weak self] coord in self?.systemLocationUpdated(coord) }
        location.onFailure = { [weak self] message in
            self?.locationMessage = message
            self?.isResolvingLocation = false
        }
        // A place chosen in Settings counts even if the welcome window was closed early.
        if self.settings.hasCompletedOnboarding || self.settings.location != .system { applyLocation() }
        loopTask = Task { [weak self] in await self?.runLoop() }
    }

    // MARK: Derived

    var placeName: String {
        let override = settings.displayName.trimmingCharacters(in: .whitespaces)
        if !override.isEmpty { return override }
        if let n = resolvedPlaceName, !n.isEmpty { return n }
        if let c = center { return Format.coordinate(c) }
        return "Locating"
    }

    /// No successful update for a while (and we were supposed to be updating).
    var isStale: Bool {
        guard let interval = powerMode.pollInterval, center != nil else { return false }
        guard let last = lastSuccess else { return fetchError != nil }
        return Date().timeIntervalSince(last) > max(30, interval * 3)
    }

    func palette(at date: Date = Date()) -> Palette {
        let daylight = center.map { Solar.daylight(elevation: Solar.elevation(at: date, coordinate: $0)) } ?? (systemIsDark ? 0 : 1)
        return Palette.resolve(settings.appearance, source: settings.dynamicSource, systemIsDark: systemIsDark, daylight: daylight)
    }

    /// Settings-level filters applied at draw time so toggles take effect instantly.
    func isVisible(_ r: AircraftReport) -> Bool {
        if r.onGround { return settings.showGroundTraffic }
        return r.altitudeFt >= settings.minAltitudeFt
    }

    // MARK: Actions

    func refreshSoon() {
        nextFetch = min(nextFetch, Date().addingTimeInterval(0.3))
    }

    func completeOnboarding(with location: LocationSetting) {
        settings.location = location
        settings.hasCompletedOnboarding = true
        applyLocation()
    }

    /// Starts resolving the current location setting before onboarding completes (welcome preview).
    func beginPreview() {
        if center == nil { applyLocation() }
    }

    /// Selects Core Location, re-requesting even if it was already selected (e.g. after a denial).
    func useSystemLocation() {
        if case .system = settings.location { applyLocation() } else { settings.location = .system }
    }

    /// Accepts coordinates or a place search (zip, city…).
    func setPlace(query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        if let c = CoordinateParser.parse(q) {
            settings.location = .coordinates(c, name: nil)
        } else {
            settings.location = .search(query: q, resolved: nil, name: nil)
        }
    }

    /// Fills the model with a fixed scene for headless snapshots.
    func stage(center: Coordinate, name: String, geo: GeoData?, reports: [AircraftReport], now: TimeInterval,
               details: FlightDetails? = nil) {
        self.center = center
        self.resolvedPlaceName = name
        self.geo = geo
        tracker.removeAll()
        // Synthesize trail history by flying each aircraft backwards along its track.
        let history = stride(from: tracker.trailDuration, through: 5, by: -5).map { $0 }
        for dt in history {
            let past = reports.map { r -> AircraftReport in
                var p = r
                if let gs = r.groundSpeedKt, let track = r.trackDeg {
                    p.position = Geo.offset(r.position, distanceNM: gs * dt / 3600, bearingDeg: track + 180)
                }
                p.fixTime = now - dt
                return p
            }
            tracker.ingest(past, at: now - dt)
        }
        tracker.ingest(reports.map { var r = $0; r.fixTime = now; return r }, at: now - 3)
        lastSuccess = Date(timeIntervalSince1970: now)
        updateDerivedTraffic(center: center)
        if let details, overhead != nil { overhead?.details = details }
    }

    // MARK: Settings side effects

    private func settingsChanged(from old: WallpaperSettings) {
        if old.location != settings.location { applyLocation() }
        if old.zoomMiles != settings.zoomMiles { refreshSoon() }
        if old.pollInterval != settings.pollInterval || old.fpsCap != settings.fpsCap || old.batterySaver != settings.batterySaver {
            updatePowerMode()
        }
        tracker.trailDuration = max(10, settings.trailMinutes * 60)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private static func loadSettings() -> WallpaperSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let s = try? JSONDecoder().decode(WallpaperSettings.self, from: data) else { return WallpaperSettings() }
        return s
    }

    private func updatePowerMode() {
        powerMode = PowerPolicy.mode(powerInputs, settings.powerSettings)
    }

    // MARK: Location

    private func applyLocation() {
        resolveTask?.cancel()
        locationMessage = nil
        switch settings.location {
        case .system:
            isResolvingLocation = center == nil
            location.start()
        case let .coordinates(c, name):
            location.stop()
            setCenter(c, name: name)
            if name == nil { reverseGeocode(c) }
        case let .search(query, resolved, name):
            location.stop()
            if let resolved {
                setCenter(resolved, name: name)
            } else {
                isResolvingLocation = true
                resolveTask = Task { [weak self] in
                    do {
                        let place = try await Geocoding.search(query)
                        guard let self, !Task.isCancelled else { return }
                        self.isResolvingLocation = false
                        self.settings.location = .search(query: query, resolved: place.coordinate, name: place.name)
                    } catch {
                        guard let self, !Task.isCancelled else { return }
                        self.isResolvingLocation = false
                        self.locationMessage = "Couldn’t find “\(query)”. Try a zip code, a city, or coordinates like 41.97, -87.90."
                    }
                }
            }
        }
    }

    private func systemLocationUpdated(_ c: Coordinate) {
        guard case .system = settings.location else { return }
        isResolvingLocation = false
        locationMessage = nil
        // Ignore jitter; only move the map for real changes (> ~1 km).
        if let current = center, Geo.distanceNM(current, c) < 0.5 { return }
        setCenter(c, name: nil)
        reverseGeocode(c)
    }

    private func setCenter(_ c: Coordinate, name: String?) {
        let moved = center.map { Geo.distanceNM($0, c) > 0.5 } ?? true
        center = c
        resolvedPlaceName = name
        isResolvingLocation = false
        if moved {
            tracker.removeAll()
            overhead = nil
            aircraftInView = 0
            refreshSoon()
        }
    }

    private func reverseGeocode(_ c: Coordinate) {
        Task { [weak self] in
            let name = await Geocoding.placeName(for: c)
            guard let self, self.center == c else { return }
            self.resolvedPlaceName = name
        }
    }

    // MARK: Map data

    private func loadGeoData() {
        guard let url = Self.geoDataURL() else { return }
        Task.detached(priority: .utility) {
            let geo = try? GeoData.load(from: url)
            await MainActor.run { [weak self] in self?.geo = geo }
        }
    }

    nonisolated static func geoDataURL() -> URL? {
        if let url = Bundle.main.url(forResource: "geodata", withExtension: "bin") { return url }
        // `swift run` from the repo
        let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/geodata.bin")
        return FileManager.default.fileExists(atPath: local.path) ? local : nil
    }

    // MARK: Polling

    private func runLoop() async {
        var lastReport = Date()
        while !Task.isCancelled {
            if Date().timeIntervalSince(lastReport) >= 30 {
                Diagnostics.report(model: self)
                lastReport = Date()
            }
            if let interval = powerMode.pollInterval, center != nil, Date() >= nextFetch {
                await fetch()
                let backoff = consecutiveFailures == 0 ? interval : min(60, interval * pow(2, Double(consecutiveFailures)))
                nextFetch = max(nextFetch, Date().addingTimeInterval(backoff))
            }
            let now = Date().timeIntervalSince1970
            tracker.prune(at: now)
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func fetch() async {
        guard let center else { return }
        let radius = Projection(center: center, size: largestScreenSize, radiusNM: settings.radiusNM).fetchRadiusNM
        do {
            let reports = try await source.aircraft(near: center, radiusNM: radius)
            guard self.center == center else { return }   // location changed mid-flight
            tracker.ingest(reports, at: Date().timeIntervalSince1970)
            consecutiveFailures = 0
            fetchError = nil
            lastSuccess = Date()
            activeSourceName = await source.activeName
            dataGeneration &+= 1
            updateDerivedTraffic(center: center)
        } catch {
            consecutiveFailures += 1
            fetchError = (error as? URLError)?.localizedDescription ?? String(describing: error)
        }
    }

    private func updateDerivedTraffic(center: Coordinate) {
        let now = Date().timeIntervalSince1970
        let bounds = Projection(center: center, size: primaryScreenSize, radiusNM: settings.radiusNM).visibleBounds
        let visible = tracker.snapshot(at: now).filter { isVisible($0.report) && !$0.report.onGround }
        aircraftInView = visible.filter { bounds.contains($0.position) }.count

        let nearest = visible.min { Geo.distanceNM($0.position, center) < Geo.distanceNM($1.position, center) }
        guard let nearest else { overhead = nil; return }
        if overhead?.hex != nearest.id {
            overhead = OverheadFlight(hex: nearest.id, details: nil)
            let hex = nearest.id, callsign = nearest.report.callsign
            Task { [weak self] in
                guard let self else { return }
                let d = await self.detailsService.details(callsign: callsign, hex: hex)
                if self.overhead?.hex == hex { self.overhead?.details = d }
            }
        }
    }
}
