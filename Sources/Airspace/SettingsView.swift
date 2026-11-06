import AirspaceCore
import ServiceManagement
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case location, appearance, map, aircraft, infoCorner, desktop

    var id: Self { self }

    var title: String {
        switch self {
        case .location: "Location"
        case .appearance: "Appearance"
        case .map: "Map"
        case .aircraft: "Aircraft"
        case .infoCorner: "Info Corner"
        case .desktop: "Desktop & Power"
        }
    }

    var symbol: String {
        switch self {
        case .location: "location.fill"
        case .appearance: "circle.lefthalf.filled"
        case .map: "map.fill"
        case .aircraft: "airplane"
        case .infoCorner: "text.alignleft"
        case .desktop: "menubar.dock.rectangle"
        }
    }

    var tint: Color {
        switch self {
        case .location: .blue
        case .appearance: .indigo
        case .map: .green
        case .aircraft: .orange
        case .infoCorner: .teal
        case .desktop: .gray
        }
    }
}

/// System Settings–style window: sections in a sidebar; a live preview above each section's controls.
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var section: SettingsSection

    init(model: AppModel, initialSection: SettingsSection = .location) {
        self.model = model
        _section = State(initialValue: initialSection)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $section) { s in
                Label {
                    Text(s.title)
                } icon: {
                    SectionIcon(symbol: s.symbol, tint: s.tint)
                }
                .tag(s)
            }
            .navigationSplitViewColumnWidth(200)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SettingsPreview(model: model)
                    Group {
                        switch section {
                        case .location: LocationSettings(model: model)
                        case .appearance: AppearanceSettings(model: model)
                        case .map: MapSettings(model: model)
                        case .aircraft: AircraftSettings(model: model)
                        case .infoCorner: InfoSettings(model: model)
                        case .desktop: DesktopSettings(model: model)
                        }
                    }
                }
                .padding(24)
                .toggleStyle(TrailingSwitch())
            }
            .navigationTitle(section.title)
        }
        .frame(width: 820, height: 700)
    }
}

struct SectionIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// The wallpaper itself, live, at the main display's aspect ratio.
struct SettingsPreview: View {
    let model: AppModel
    private let width: CGFloat = 548

    var body: some View {
        let screen = model.primaryScreenSize
        let height = (width * screen.height / max(1, screen.width)).rounded()
        AirspaceView(model: model, size: CGSize(width: width * 2, height: height * 2), insets: EdgeInsets())
            .scaleEffect(0.5, anchor: .topLeading)
            .frame(width: width, height: height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Live wallpaper preview")
    }
}

/// A titled group of rows, styled like a grouped Form section.
struct SettingsGroup<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.headline)
            }
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator.opacity(0.6)))
            if let footer {
                Text(footer).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

/// System Settings–style toggle: label on the left, small switch on the right.
struct TrailingSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 16)
            Toggle("", isOn: configuration.$isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }
}

/// One label/control row inside a `SettingsGroup`.
struct SettingsRow<Control: View>: View {
    let title: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 16)
            control.labelsHidden().fixedSize()
        }
    }
}

// MARK: - Visual pickers

/// A selectable card with an illustration and caption, like macOS's Appearance picker.
struct ChoiceCard<Illustration: View>: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var illustration: Illustration

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                illustration
                    .frame(width: 112, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 3 : 1)
                    )
                Text(title)
                    .font(.callout)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct CardRow<T: Hashable, Card: View>: View {
    let options: [T]
    @ViewBuilder var card: (T) -> Card

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(options, id: \.self) { card($0) }
        }
    }
}

/// Mini illustration: a few planes on a field, drawn with real palette tokens.
struct MiniScene: View {
    let palette: Palette
    var style: MapStyle = .schematic
    var glyph: GlyphStyle = .silhouette
    var colors: [RGBA]? = nil

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            switch style {
            case .schematic:
                ctx.fill(Path(rect), with: .color(palette.water.color))
                var land = Path()
                land.move(to: CGPoint(x: 0, y: 0))
                land.addLine(to: CGPoint(x: size.width * 0.62, y: 0))
                land.addCurve(to: CGPoint(x: size.width * 0.55, y: size.height),
                              control1: CGPoint(x: size.width * 0.5, y: size.height * 0.35),
                              control2: CGPoint(x: size.width * 0.7, y: size.height * 0.6))
                land.addLine(to: CGPoint(x: 0, y: size.height))
                land.closeSubpath()
                ctx.fill(land, with: .color(palette.land.color))
                var road = Path()
                road.move(to: CGPoint(x: 0, y: size.height * 0.7))
                road.addLine(to: CGPoint(x: size.width * 0.58, y: size.height * 0.45))
                ctx.stroke(road, with: .color(palette.road.color), lineWidth: 1)
            case .appleMap:
                ctx.fill(Path(rect), with: .color(palette.land.color))
                var streets = Path()
                for i in stride(from: 8.0, to: size.width, by: 14) {
                    streets.move(to: CGPoint(x: i, y: 0)); streets.addLine(to: CGPoint(x: i - 6, y: size.height))
                }
                for j in stride(from: 10.0, to: size.height, by: 12) {
                    streets.move(to: CGPoint(x: 0, y: j)); streets.addLine(to: CGPoint(x: size.width, y: j + 3))
                }
                ctx.stroke(streets, with: .color(palette.road.color), lineWidth: 0.8)
                ctx.fill(Path(ellipseIn: CGRect(x: size.width * 0.65, y: -10, width: 70, height: 50)), with: .color(palette.water.color))
            case .pureField:
                ctx.fill(Path(rect), with: .color(palette.land.color))
                var dots = Path()
                for x in stride(from: 6.0, to: size.width, by: 10) {
                    for y in stride(from: 6.0, to: size.height, by: 10) {
                        dots.addEllipse(in: CGRect(x: x - 0.7, y: y - 0.7, width: 1.4, height: 1.4))
                    }
                }
                ctx.fill(dots, with: .color(palette.dotGrid.color))
            }
            let spots: [(CGFloat, CGFloat, Double)] = [(0.28, 0.35, 45), (0.7, 0.62, 250), (0.5, 0.78, 100)]
            for (i, spot) in spots.enumerated() {
                let p = CGPoint(x: size.width * spot.0, y: size.height * spot.1)
                let color = colors.map { $0[i % $0.count] } ?? palette.airlineColors[[0, 2, 3][i]]
                MiniScene.drawGlyph(glyph, at: p, heading: spot.2, color: color, palette: palette, in: &ctx)
            }
        }
    }

    static func drawGlyph(_ glyph: GlyphStyle, at p: CGPoint, heading: Double, color: RGBA, palette: Palette,
                          in ctx: inout GraphicsContext) {
        let t = CGAffineTransform(rotationAngle: heading * .pi / 180).concatenating(CGAffineTransform(translationX: p.x, y: p.y))
        switch glyph {
        case .silhouette:
            let shape = Path(Silhouettes.jet).applying(CGAffineTransform(scaleX: 0.8, y: 0.8).concatenating(t))
            ctx.stroke(shape, with: .color(palette.land.color), lineWidth: 1.2)
            ctx.fill(shape, with: .color(color.color))
        case .light:
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16)),
                     with: .radialGradient(Gradient(colors: [color.with(alpha: 0.4).color, color.with(alpha: 0).color]),
                                           center: p, startRadius: 0, endRadius: 8))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.6, y: p.y - 2.6, width: 5.2, height: 5.2)), with: .color(color.color))
        case .arrow:
            var arrow = Path()
            arrow.move(to: CGPoint(x: 0, y: -6.5))
            arrow.addLine(to: CGPoint(x: 4.5, y: 5))
            arrow.addLine(to: CGPoint(x: 0, y: 2.5))
            arrow.addLine(to: CGPoint(x: -4.5, y: 5))
            arrow.closeSubpath()
            ctx.fill(arrow.applying(t), with: .color(color.color))
        }
    }
}

// MARK: - Location

struct LocationSettings: View {
    @Bindable var model: AppModel
    @State private var query = ""

    private var usesSystem: Bool {
        if case .system = model.settings.location { return true }
        return false
    }

    var body: some View {
        SettingsGroup(title: "Center the map on") {
            Picker("Source", selection: Binding(
                get: { usesSystem },
                set: { system in
                    if system { model.useSystemLocation() } else if !query.isEmpty { model.setPlace(query: query) }
                })) {
                Text("My current location").tag(true)
                Text("A place I choose").tag(false)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            HStack {
                TextField("Zip code, city, or coordinates", text: $query, prompt: Text("60601  ·  Chicago  ·  41.97, -87.90"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.setPlace(query: query) }
                Button("Set") { model.setPlace(query: query) }
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Divider()
            HStack {
                Text("Now showing")
                Spacer()
                if model.isResolvingLocation {
                    ProgressView().controlSize(.small)
                } else if let c = model.center {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(model.placeName)
                        Text(Format.coordinate(c)).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Nothing yet").foregroundStyle(.secondary)
                }
            }
            if let message = model.locationMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .onAppear {
            switch model.settings.location {
            case let .search(q, _, _): query = q
            case let .coordinates(c, _): query = String(format: "%.4f, %.4f", c.latitude, c.longitude)
            case .system: break
            }
        }

        SettingsGroup(footer: "Shown in the info corner. Leave empty to use the place name.") {
            SettingsRow(title: "Display name") {
                TextField("Display name", text: $model.settings.displayName, prompt: Text(model.placeName))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }
        }
    }
}

// MARK: - Appearance

struct AppearanceSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        SettingsGroup(title: "Appearance") {
            CardRow(options: AppearanceMode.allCases) { mode in
                ChoiceCard(title: title(mode), selected: model.settings.appearance == mode) {
                    model.settings.appearance = mode
                } illustration: {
                    switch mode {
                    case .light: MiniScene(palette: .aluminum)
                    case .dark: MiniScene(palette: .night)
                    case .dynamic:
                        HStack(spacing: 0) {
                            MiniScene(palette: .aluminum).frame(width: 56).clipped()
                            MiniScene(palette: .night).frame(width: 56).clipped()
                        }
                    }
                }
            }
            if model.settings.appearance == .dynamic {
                Divider()
                SettingsRow(title: "Dynamic follows") {
                    Picker("Dynamic follows", selection: $model.settings.dynamicSource) {
                        Text("The sun at this location").tag(DynamicSource.sun)
                        Text("macOS appearance").tag(DynamicSource.system)
                    }
                }
            }
        }
        if model.settings.appearance == .dynamic && model.settings.dynamicSource == .sun {
            Text("Fades between Aluminum and Night through dusk and dawn, using civil twilight at your location.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func title(_ m: AppearanceMode) -> String {
        switch m {
        case .light: "Aluminum"
        case .dark: "Night"
        case .dynamic: "Dynamic"
        }
    }
}

// MARK: - Map

struct MapSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        let palette = model.palette()
        SettingsGroup(title: "Style") {
            CardRow(options: MapStyle.allCases) { style in
                ChoiceCard(title: title(style), selected: model.settings.mapStyle == style) {
                    model.settings.mapStyle = style
                } illustration: {
                    MiniScene(palette: palette, style: style)
                }
            }
        }

        SettingsGroup(title: "Zoom", footer: "Distance from your location to the nearest screen edge.") {
            HStack(spacing: 12) {
                Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
                Slider(value: $model.settings.zoomMiles, in: WallpaperSettings.zoomRange)
                Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                Text("\(Int(model.settings.zoomMiles)) mi")
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
        }

        SettingsGroup(title: "Details") {
            Toggle("Range rings", isOn: $model.settings.showRangeRings)
            Toggle("Dot grid", isOn: $model.settings.showDotGrid)
            if model.settings.mapStyle == .schematic {
                Toggle("Runways and airport codes", isOn: $model.settings.showRunways)
                Toggle("Major roads", isOn: $model.settings.showRoads)
            }
            if model.settings.mapStyle == .appleMap {
                Toggle("Tint Apple Map to match the palette", isOn: $model.settings.tintAppleMap)
            }
        }
    }

    private func title(_ s: MapStyle) -> String {
        switch s {
        case .schematic: "Schematic"
        case .appleMap: "Apple Map"
        case .pureField: "Pure Field"
        }
    }
}

// MARK: - Aircraft

struct AircraftSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        let palette = model.palette()
        SettingsGroup(title: "Icon") {
            CardRow(options: GlyphStyle.allCases) { glyph in
                ChoiceCard(title: title(glyph), selected: model.settings.glyph == glyph) {
                    model.settings.glyph = glyph
                } illustration: {
                    MiniScene(palette: palette, style: .pureField, glyph: glyph)
                }
            }
        }

        SettingsGroup(title: "Color", footer: footer) {
            CardRow(options: ColorMode.allCases) { mode in
                ChoiceCard(title: title(mode), selected: model.settings.colorMode == mode) {
                    model.settings.colorMode = mode
                } illustration: {
                    MiniScene(palette: palette, style: .pureField, glyph: model.settings.glyph, colors: sample(mode, palette))
                }
            }
            if model.settings.colorMode == .altitude {
                Divider()
                AltitudeKey(palette: palette)
            }
        }

        SettingsGroup(title: "Labels & trails") {
            SettingsRow(title: "Labels") {
                Picker("Labels", selection: $model.settings.labelMode) {
                    Text("Off").tag(LabelMode.off)
                    Text("Callsign").tag(LabelMode.callsign)
                    Text("Callsign + type").tag(LabelMode.callsignType)
                    Text("Callsign + altitude").tag(LabelMode.callsignAltitude)
                    Text("Callsign + type + altitude").tag(LabelMode.callsignTypeAltitude)
                }
            }
            SettingsRow(title: "Trails") {
                Picker("Trails", selection: $model.settings.trailMinutes) {
                    Text("Off").tag(0.0)
                    Text("1 minute").tag(1.0)
                    Text("3 minutes").tag(3.0)
                    Text("10 minutes").tag(10.0)
                }
            }
            Toggle("Pulse on each update", isOn: $model.settings.pulse)
            HStack {
                Text("Brightness")
                Slider(value: $model.settings.brightness, in: 0.3...1)
            }
        }

        SettingsGroup(title: "Filter") {
            Toggle("Show aircraft on the ground", isOn: $model.settings.showGroundTraffic)
            SettingsRow(title: "Minimum altitude") {
                Picker("Minimum altitude", selection: $model.settings.minAltitudeFt) {
                    Text("None").tag(0.0)
                    Text("1,000 ft").tag(1_000.0)
                    Text("5,000 ft").tag(5_000.0)
                    Text("10,000 ft").tag(10_000.0)
                    Text("FL180").tag(18_000.0)
                }
            }
        }
    }

    private var footer: String {
        switch model.settings.colorMode {
        case .airline: "The four busiest airlines on screen each get a color; others stay neutral. The info corner shows the key."
        case .altitude: "Warm near the ground, cool at cruise. Trails show the altitude flown along the way."
        case .monochrome: "Every aircraft in one color."
        }
    }

    private func sample(_ mode: ColorMode, _ p: Palette) -> [RGBA] {
        switch mode {
        case .airline: [p.airlineColors[0], p.airlineColors[2], p.airlineColors[3]]
        case .altitude: [p.altitudeColors[0], p.altitudeColors[2], p.altitudeColors[4]]
        case .monochrome: [p.monochrome]
        }
    }

    private func title(_ g: GlyphStyle) -> String {
        switch g {
        case .silhouette: "Plane"
        case .light: "Point of Light"
        case .arrow: "Arrow"
        }
    }

    private func title(_ m: ColorMode) -> String {
        switch m {
        case .airline: "By Airline"
        case .altitude: "By Altitude"
        case .monochrome: "Monochrome"
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

// MARK: - Info corner

struct InfoSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        SettingsGroup {
            Toggle("Show the info corner", isOn: $model.settings.infoEnabled)
        }
        if model.settings.infoEnabled {
            SettingsGroup(title: "Position") {
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        cornerButton(.topLeft, "arrow.up.left")
                        cornerButton(.topRight, "arrow.up.right")
                    }
                    GridRow {
                        cornerButton(.bottomLeft, "arrow.down.left")
                        cornerButton(.bottomRight, "arrow.down.right")
                    }
                }
            }
            SettingsGroup(title: "Show") {
                Toggle("Coordinates", isOn: $model.settings.infoShowCoordinates)
                Toggle("Clock", isOn: $model.settings.infoShowClock)
                Toggle("Aircraft count", isOn: $model.settings.infoShowCount)
                Toggle("Nearest flight", isOn: $model.settings.infoShowOverhead)
                Toggle("Airline key", isOn: $model.settings.infoShowAirlines)
                    .disabled(model.settings.colorMode != .airline)
            }
        }
    }

    private func cornerButton(_ corner: Corner, _ symbol: String) -> some View {
        let selected = model.settings.infoCorner == corner
        return Button {
            model.settings.infoCorner = corner
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 120, height: 44)
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .background(selected ? Color.accentColor : Color.secondary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(corner.rawValue)
    }
}

// MARK: - Desktop & power

struct DesktopSettings: View {
    @Bindable var model: AppModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        SettingsGroup(title: "Desktop",
                      footer: "macOS tints the menu bar, Mission Control and Show Desktop from the system wallpaper. Matching it to the map keeps those see-through. Your own wallpaper comes back when Airspace quits or this is turned off.") {
            Toggle("Match the menu bar and system wallpaper", isOn: $model.settings.syncSystemWallpaper)
            SettingsRow(title: "Displays") {
                Picker("Displays", selection: $model.settings.displays) {
                    Text("All displays").tag(DisplayTarget.all)
                    Text("Main display only").tag(DisplayTarget.mainOnly)
                }
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

        SettingsGroup(title: "Updates") {
            SettingsRow(title: "Refresh every") {
                Picker("Refresh every", selection: $model.settings.pollInterval) {
                    ForEach(WallpaperSettings.pollChoices, id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                }
            }
            SettingsRow(title: "Frame rate") {
                Picker("Frame rate", selection: $model.settings.fpsCap) {
                    Text("15 fps").tag(15.0)
                    Text("20 fps").tag(20.0)
                    Text("30 fps").tag(30.0)
                    Text("60 fps").tag(60.0)
                }
            }
            Toggle("Battery saver: slower updates on battery", isOn: $model.settings.batterySaver)
        }

        SettingsGroup(title: "Data",
                      footer: "Live positions from the adsb.lol and adsb.fi community networks; routes, airframes and airline names from adsbdb.com. Map data: Natural Earth and OurAirports (public domain).") {
            SettingsRow(title: "Feed") { Text(model.activeSourceName).foregroundStyle(.secondary) }
            SettingsRow(title: "Last update") {
                Text(model.lastSuccess.map { $0.formatted(date: .omitted, time: .standard) } ?? "—").foregroundStyle(.secondary)
            }
            if let e = model.fetchError { Text(e).font(.caption).foregroundStyle(.orange) }
        }
    }
}
