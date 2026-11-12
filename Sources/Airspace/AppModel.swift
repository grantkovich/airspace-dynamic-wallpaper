import AirspaceCore
import AppKit
import Observation

struct AirlineLegend: Equatable {
    struct Entry: Equatable { var code: String; var count: Int }
    var entries: [Entry] = []
    var otherAirlines = 0
    var privateAircraft = 0
}

/// The nearest airborne flight, shown in the info corner.
struct OverheadFlight: Equatable {
    var hex: String
    var details: FlightDetails?
    /// Set once the route has passed the heading check, so turns and vectors don't hide it.
    var confirmed: RouteDirection?
}

/// An aircraft in view squawking an emergency code.
struct AlertFlight: Equatable {
    var hex: String
    var name: String
    var alert: AircraftAlert
    var squawk: String?
    var distanceNM: Double
    var bearingDeg: Double
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

    // MARK: System wallpaper
    /// A display shows a map still and its own picture couldn't be put back automatically.
    /// Set by SystemWallpaperSync; the menu and Settings then offer "Restore My Wallpaper…".
    var wallpaperNeedsManualRestore = false
    @ObservationIgnored var restoreWallpaperManually: (() -> Void)?
    /// Set by the app delegate: Sparkle's "Check for Updates".
    @ObservationIgnored var checkForUpdates: (() -> Void)?

    // MARK: Traffic
    @ObservationIgnored var tracker = AircraftTracker()
    private(set) var lastSuccess: Date?
    private(set) var fetchError: String?
    private(set) var activeSourceName = ReadsbSource.Endpoint.adsbLol.rawValue
    private(set) var aircraftInView = 0
    private(set) var overhead: OverheadFlight?
    /// Airline (ICAO code) → colour slot, for the airlines with a colour right now.
    private(set) var airlineSlots: [String: AirlineSlot] = [:]
    private(set) var airlineLegend = AirlineLegend()
    private(set) var airlineNames: [String: String] = [:]
    /// Emergencies in view, nearest first.
    private(set) var alerts: [AlertFlight] = []
    /// Distinct aircraft seen in view today.
    private(set) var aircraftToday = 0
    @ObservationIgnored private var tally = DailyTally()
    @ObservationIgnored private var persistsTally = true
    @ObservationIgnored private var tallySavedAt = Date.distantPast
    @ObservationIgnored private var airlineAssigner = AirlineColorAssigner()
    @ObservationIgnored private var liveryAssigner = LiveryAssigner()
    /// Livery colours fitted to the current palette; refitting costs a colour-space round trip.
    @ObservationIgnored private var fittedLiveries: [RGBA: RGBA] = [:]
    @ObservationIgnored private var fittedLightness: ClosedRange<Double>?
    @ObservationIgnored private var fittedPaints: [String: LiveryPaint] = [:]
    @ObservationIgnored private var fittedPartLightness: ClosedRange<Double>?
    /// Livery mode names more airlines than the four slots, so the key shows a few more.
    static let liveryLegendRows = 6
    /// Callsign → brand code. Colouring asks for every aircraft on every frame, and callsigns
    /// change far less often than that.
    @ObservationIgnored private var brandCache: [String: String] = [:]
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
    /// Routes that passed the heading check, by aircraft and callsign, so a plane that turns away
    /// and later becomes the nearest again keeps its route. Capped: the app runs for days.
    @ObservationIgnored private var confirmedRoutes: [String: RouteDirection] = [:]
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
        persistsTally = startServices
        tally = startServices ? Self.loadTally() : DailyTally()
        tally.record([String](), on: Date())   // drop yesterday's
        aircraftToday = tally.count
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

    /// The colour an aircraft is drawn in, per the colour mode.
    func color(for r: AircraftReport, palette: Palette) -> RGBA {
        switch settings.colorMode {
        case .altitude: return palette.altitudeColor(r.onGround ? 0 : r.altitudeFt)
        case .monochrome: return palette.monochrome
        case .airline:
            guard let code = brandCode(r.callsign) else { return palette.privateAircraft }
            return airlineColor(code, palette: palette) ?? palette.otherAirline
        }
    }

    /// The full livery an aircraft is painted in, or nil to draw it in one colour.
    func paint(for r: AircraftReport, palette: Palette) -> LiveryPaint? {
        brandCode(r.callsign).flatMap { paint(code: $0, palette: palette) }
    }

    func paint(code: String, palette: Palette) -> LiveryPaint? {
        guard settings.colorMode == .airline, settings.liveryColors, settings.fullLivery, settings.glyph == .silhouette
        else { return nil }
        if fittedPartLightness != palette.liveryPartLightness {
            fittedPaints.removeAll(keepingCapacity: true)
            fittedPartLightness = palette.liveryPartLightness
        }
        if let hit = fittedPaints[code] { return hit }
        guard let livery = Liveries.livery(code) else { return nil }
        let fitted = palette.livery(livery.paint)
        fittedPaints[code] = fitted
        return fitted
    }

    /// An airline's colour in airline mode, or nil if it has none (it's drawn as "other").
    func airlineColor(_ code: String, palette: Palette) -> RGBA? {
        guard settings.liveryColors else { return airlineSlots[code].map(palette.airlineColor) }
        guard let raw = liveryAssigner.color(code) else { return nil }
        if fittedLightness != palette.liveryLightness {
            fittedLiveries.removeAll(keepingCapacity: true)
            fittedLightness = palette.liveryLightness
        }
        if let hit = fittedLiveries[raw] { return hit }
        let fitted = palette.livery(raw)
        fittedLiveries[raw] = fitted
        return fitted
    }

    /// The airline a callsign is counted and coloured as, memoized (nil for private flights).
    func brandCode(_ callsign: String?) -> String? {
        guard let callsign else { return nil }
        if let hit = brandCache[callsign] { return hit.isEmpty ? nil : hit }
        if brandCache.count > 5_000 { brandCache.removeAll(keepingCapacity: true) }
        let code = Airlines.brandCode(fromCallsign: callsign, groupRegionals: settings.groupRegionals)
        brandCache[callsign] = code ?? ""
        return code
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
        if old.groupRegionals != settings.groupRegionals, let center {
            brandCache.removeAll()
            airlineAssigner = AirlineColorAssigner()
            liveryAssigner = LiveryAssigner()
            updateDerivedTraffic(center: center)
        }
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
            airlineAssigner = AirlineColorAssigner()
            liveryAssigner = LiveryAssigner()
            airlineSlots = [:]
            airlineLegend = AirlineLegend()
            alerts = []
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

    /// Counts airlines on screen, keeps the colour assignment stable, and names new airlines.
    private func updateAirlines(_ inView: [DisplayAircraft]) {
        var counts: [String: Int] = [:]
        var privateCount = 0
        for a in inView {
            if let code = brandCode(a.report.callsign) {
                counts[code, default: 0] += 1
            } else {
                privateCount += 1
            }
        }
        airlineAssigner.update(counts: counts)
        if airlineSlots != airlineAssigner.assignments { airlineSlots = airlineAssigner.assignments }
        liveryAssigner.update(counts: counts)

        // The key lists the busiest airlines that have a colour; everyone else is "other".
        let byCount = { (a: String, b: String) in (counts[a] ?? 0) != (counts[b] ?? 0) ? (counts[a] ?? 0) > (counts[b] ?? 0) : a < b }
        let assigned: [String] = settings.liveryColors
            ? Array(counts.keys.filter { liveryAssigner.color($0) != nil }.sorted(by: byCount).prefix(Self.liveryLegendRows))
            : airlineSlots.keys.sorted(by: byCount)
        let listed = Set(assigned)
        let otherCount = counts.filter { !listed.contains($0.key) }.values.reduce(0, +)
        airlineLegend = AirlineLegend(
            entries: assigned.map { .init(code: $0, count: counts[$0] ?? 0) },
            otherAirlines: otherCount, privateAircraft: privateCount)

        for code in assigned where airlineNames[code] == nil {
            airlineNames[code] = Airlines.displayName(code) ?? code   // placeholder until the lookup returns
            Task { [weak self] in
                guard let self, let name = await self.detailsService.airlineName(code) else { return }
                self.airlineNames[code] = name
            }
        }
    }

    // MARK: Daily tally

    static let tallyKey = "airspace.tally.v1"

    private static func loadTally() -> DailyTally {
        guard let data = UserDefaults.standard.data(forKey: tallyKey),
              let t = try? JSONDecoder().decode(DailyTally.self, from: data) else { return DailyTally() }
        return t
    }

    private func updateTally(_ inView: [DisplayAircraft]) {
        let now = Date()
        guard tally.record(inView.map(\.id), on: now) else { return }
        aircraftToday = tally.count
        // A wallpaper restarts at login; persist so the count survives, but not on every poll.
        if persistsTally, now.timeIntervalSince(tallySavedAt) > 60, let data = try? JSONEncoder().encode(tally) {
            UserDefaults.standard.set(data, forKey: Self.tallyKey)
            tallySavedAt = now
        }
    }

    private func updateDerivedTraffic(center: Coordinate) {
        let now = Date().timeIntervalSince1970
        let bounds = Projection(center: center, size: primaryScreenSize, radiusNM: settings.radiusNM).visibleBounds
        let visible = tracker.snapshot(at: now).filter { isVisible($0.report) && !$0.report.onGround }
        let inView = visible.filter { bounds.contains($0.position) }
        aircraftInView = inView.count
        updateAirlines(inView)
        updateTally(inView)

        let newAlerts = inView.compactMap { a -> AlertFlight? in
            guard let alert = a.report.alert else { return nil }
            return AlertFlight(hex: a.id, name: AircraftRenderer.displayName(a.report), alert: alert, squawk: a.report.squawk,
                               distanceNM: Geo.distanceNM(center, a.position), bearingDeg: Geo.bearingDeg(from: center, to: a.position))
        }.sorted { $0.distanceNM < $1.distanceNM }
        if newAlerts != alerts { alerts = newAlerts }

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
        confirmRoute(for: nearest)
    }

    /// Checks the overhead route's heading until it passes once, then remembers which way round.
    private func confirmRoute(for a: DisplayAircraft) {
        guard let details = overhead?.details else { return }
        let key = "\(a.id)|\(a.report.callsign ?? "")"
        if confirmedRoutes[key] == nil,
           let route = details.verifiedRoute(position: a.position, trackDeg: a.report.trackDeg, altitudeFt: a.report.altitudeFt) {
            if confirmedRoutes.count >= 2_000 { confirmedRoutes.removeAll(keepingCapacity: true) }
            confirmedRoutes[key] = route.direction
        }
        let confirmed = confirmedRoutes[key]
        if overhead?.confirmed != confirmed { overhead?.confirmed = confirmed }
    }
}
