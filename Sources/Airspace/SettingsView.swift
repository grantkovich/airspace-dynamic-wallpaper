import AirspaceCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            LocationSettings(model: model).tabItem { Label("Location", systemImage: "location") }
            MapSettings(model: model).tabItem { Label("Map", systemImage: "map") }
            AircraftSettings(model: model).tabItem { Label("Aircraft", systemImage: "airplane") }
            AppearanceSettings(model: model).tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }
            InfoSettings(model: model).tabItem { Label("Info", systemImage: "text.alignleft") }
            AdvancedSettings(model: model).tabItem { Label("Advanced", systemImage: "gearshape") }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 470)
    }
}

// MARK: - Location

struct LocationPicker: View {
    @Bindable var model: AppModel
    @State private var query = ""

    private var usesSystem: Bool {
        if case .system = model.settings.location { return true }
        return false
    }

    var body: some View {
        Picker("Source", selection: Binding(
            get: { usesSystem },
            set: { system in
                if system { model.useSystemLocation() } else if !query.isEmpty { model.setPlace(query: query) }
            })) {
            Text("Use my location").tag(true)
            Text("Choose a place").tag(false)
        }
        .pickerStyle(.radioGroup)

        HStack {
            TextField("Zip code, city, or coordinates", text: $query, prompt: Text("60601 · Chicago · 41.97, -87.90"))
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.setPlace(query: query) }
            Button("Set") { model.setPlace(query: query) }
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear {
            switch model.settings.location {
            case let .search(q, _, _): query = q
            case let .coordinates(c, _): query = String(format: "%.4f, %.4f", c.latitude, c.longitude)
            case .system: break
            }
        }

        LabeledContent("Current") {
            if model.isResolvingLocation {
                ProgressView().controlSize(.small)
            } else if let c = model.center {
                VStack(alignment: .trailing) {
                    Text(model.placeName)
                    Text(Format.coordinate(c)).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            } else {
                Text("None").foregroundStyle(.secondary)
            }
        }
        if let message = model.locationMessage {
            Text(message).font(.callout).foregroundStyle(.orange)
        }
    }
}

struct LocationSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section { LocationPicker(model: model) }
            Section {
                TextField("Display name", text: $model.settings.displayName, prompt: Text(model.placeName))
            } footer: {
                Text("Shown in the info corner. Leave empty to use the place name.").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Map

struct MapSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                Picker("Style", selection: $model.settings.mapStyle) {
                    Text("Schematic").tag(MapStyle.schematic)
                    Text("Apple Map (muted)").tag(MapStyle.appleMap)
                    Text("Pure field").tag(MapStyle.pureField)
                }
                LabeledContent("Zoom") {
                    HStack {
                        Slider(value: $model.settings.zoomMiles, in: WallpaperSettings.zoomRange)
                        Text("\(Int(model.settings.zoomMiles)) mi").monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                }
            } footer: {
                Text("Zoom is the distance from your location to the nearest screen edge.").foregroundStyle(.secondary)
            }
            Section("Details") {
                Toggle("Range rings", isOn: $model.settings.showRangeRings)
                Toggle("Dot grid", isOn: $model.settings.showDotGrid)
                Toggle("Runways and airport codes", isOn: $model.settings.showRunways)
                    .disabled(model.settings.mapStyle != .schematic)
                Toggle("Major roads", isOn: $model.settings.showRoads)
                    .disabled(model.settings.mapStyle != .schematic)
                Toggle("Tint Apple Map to match palette", isOn: $model.settings.tintAppleMap)
                    .disabled(model.settings.mapStyle != .appleMap)
            }
        }
    }
}

// MARK: - Aircraft

struct AircraftSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                Picker("Labels", selection: $model.settings.labelMode) {
                    Text("Off").tag(LabelMode.off)
                    Text("Callsign").tag(LabelMode.callsign)
                    Text("Callsign + altitude").tag(LabelMode.callsignAltitude)
                }
                Picker("Glyph", selection: $model.settings.glyph) {
                    Text("Point of light").tag(GlyphStyle.light)
                    Text("Arrow").tag(GlyphStyle.arrow)
                    Text("Silhouette").tag(GlyphStyle.silhouette)
                }
                Picker("Color", selection: $model.settings.colorMode) {
                    Text("By altitude").tag(ColorMode.altitude)
                    Text("Monochrome").tag(ColorMode.monochrome)
                }
                Picker("Trails", selection: $model.settings.trailMinutes) {
                    Text("Off").tag(0.0)
                    Text("1 minute").tag(1.0)
                    Text("3 minutes").tag(3.0)
                    Text("10 minutes").tag(10.0)
                }
                Toggle("Pulse on each update", isOn: $model.settings.pulse)
                LabeledContent("Brightness") {
                    Slider(value: $model.settings.brightness, in: 0.3...1)
                }
            }
            Section("Filter") {
                Toggle("Show aircraft on the ground", isOn: $model.settings.showGroundTraffic)
                Picker("Minimum altitude", selection: $model.settings.minAltitudeFt) {
                    Text("None").tag(0.0)
                    Text("1,000 ft").tag(1_000.0)
                    Text("5,000 ft").tag(5_000.0)
                    Text("10,000 ft").tag(10_000.0)
                    Text("FL180").tag(18_000.0)
                }
            }
            if model.settings.colorMode == .altitude {
                Section("Altitude key") { AltitudeKey(palette: model.palette()) }
            }
        }
    }
}

struct AltitudeKey: View {
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LinearGradient(stops: palette.altitudeStops.enumerated().map { i, ft in
                .init(color: palette.altitudeColors[i].color, location: ft / palette.altitudeStops.last!)
            }, startPoint: .leading, endPoint: .trailing)
            .frame(height: 8)
            .clipShape(Capsule())
            HStack {
                Text("Ground"); Spacer(); Text("12,000 ft"); Spacer(); Text("FL380+")
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Appearance

struct AppearanceSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $model.settings.appearance) {
                    Text("Light — Aluminum").tag(AppearanceMode.light)
                    Text("Dark — Night").tag(AppearanceMode.dark)
                    Text("Dynamic").tag(AppearanceMode.dynamic)
                }
                .pickerStyle(.radioGroup)
                Picker("Dynamic follows", selection: $model.settings.dynamicSource) {
                    Text("The sun at this location").tag(DynamicSource.sun)
                    Text("macOS appearance").tag(DynamicSource.system)
                }
                .disabled(model.settings.appearance != .dynamic)
            } footer: {
                Text("Following the sun fades between Aluminum and Night through dusk and dawn, using civil twilight at your location.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Info corner

struct InfoSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Show info corner", isOn: $model.settings.infoEnabled)
                Picker("Corner", selection: $model.settings.infoCorner) {
                    Text("Top left").tag(Corner.topLeft)
                    Text("Top right").tag(Corner.topRight)
                    Text("Bottom left").tag(Corner.bottomLeft)
                    Text("Bottom right").tag(Corner.bottomRight)
                }
                .disabled(!model.settings.infoEnabled)
            }
            Section("Contents") {
                Toggle("Coordinates", isOn: $model.settings.infoShowCoordinates)
                Toggle("Clock", isOn: $model.settings.infoShowClock)
                Toggle("Aircraft count", isOn: $model.settings.infoShowCount)
                Toggle("Nearest flight", isOn: $model.settings.infoShowOverhead)
            }
            .disabled(!model.settings.infoEnabled)
        }
    }
}

// MARK: - Advanced

struct AdvancedSettings: View {
    @Bindable var model: AppModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Updates") {
                Picker("Refresh every", selection: $model.settings.pollInterval) {
                    ForEach(WallpaperSettings.pollChoices, id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                }
                Picker("Frame rate", selection: $model.settings.fpsCap) {
                    Text("15 fps").tag(15.0)
                    Text("20 fps").tag(20.0)
                    Text("30 fps").tag(30.0)
                    Text("60 fps").tag(60.0)
                }
                Toggle("Battery saver (slower updates on battery)", isOn: $model.settings.batterySaver)
            }
            Section("System") {
                Picker("Displays", selection: $model.settings.displays) {
                    Text("All displays").tag(DisplayTarget.all)
                    Text("Main display only").tag(DisplayTarget.mainOnly)
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.orange) }
            }
            Section {
                LabeledContent("Feed", value: model.activeSourceName)
                LabeledContent("Last update", value: model.lastSuccess.map { $0.formatted(date: .omitted, time: .standard) } ?? "—")
                if let e = model.fetchError { Text(e).font(.caption).foregroundStyle(.orange) }
            } header: {
                Text("Data")
            } footer: {
                Text("Live positions from the adsb.lol and adsb.fi community networks; routes from adsbdb.com. Map data: Natural Earth and OurAirports (public domain).")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
