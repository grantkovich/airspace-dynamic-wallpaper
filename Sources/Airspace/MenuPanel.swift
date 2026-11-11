import AirspaceCore
import SwiftUI

/// The menu-bar dropdown: status at a glance plus the settings people reach for most.
struct MenuPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if model.center == nil && !model.isResolvingLocation {
                Button {
                    WindowRouter.shared.open(model.settings.hasCompletedOnboarding ? .settings : .welcome)
                } label: {
                    Label("Choose Location…", systemImage: "location").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
            Divider()
            row("Appearance") {
                Picker("Appearance", selection: $model.settings.appearance) {
                    Text("Light").tag(AppearanceMode.light)
                    Text("Dark").tag(AppearanceMode.dark)
                    Text("Dynamic").tag(AppearanceMode.dynamic)
                }
            }
            row("Map") {
                Picker("Map", selection: $model.settings.mapStyle) {
                    Text("Schematic").tag(MapStyle.schematic)
                    Text("Apple").tag(MapStyle.appleMap)
                    Text("Field").tag(MapStyle.pureField)
                }
            }
            row("Labels") {
                Picker("Labels", selection: $model.settings.labelMode) {
                    Text("Off").tag(LabelMode.off)
                    Text("Callsign").tag(LabelMode.callsign)
                    Text("+ Altitude").tag(LabelMode.callsignAltitude)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Zoom").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(model.settings.zoomMiles)) mi radius").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Slider(value: $model.settings.zoomMiles, in: WallpaperSettings.zoomRange)
            }
            if model.wallpaperNeedsManualRestore {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Airspace couldn't put your own wallpaper back by itself.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Restore My Wallpaper…") { model.restoreWallpaperManually?() }
                }
            }
            Divider()
            HStack {
                Button(model.paused ? "Resume" : "Pause") { model.paused.toggle() }
                Spacer()
                Button("About") { AboutPanel.show() }
                Button("Settings…") { WindowRouter.shared.open(.settings) }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.regular)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(16)
        .frame(width: 320)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.placeName.uppercased())
                .font(.system(size: 15, weight: .semibold).width(.expanded))
                .tracking(1.5)
                .lineLimit(1)
            Text(statusText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(model.isStale ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        }
    }

    private var statusText: String {
        if model.center == nil { return model.locationMessage == nil ? "Waiting for a location" : "Location unavailable" }
        if model.paused { return "Paused" }
        switch model.powerMode.kind {
        case .suspended: return "Sleeping"
        case .occluded: return "Hidden behind windows · idle"
        default: break
        }
        if model.isStale { return "No signal · updated \(Format.ago(model.lastSuccess).lowercased())" }
        let battery = model.powerMode.kind == .battery ? " · battery saver" : ""
        return "\(model.aircraftInView) aircraft · \(model.activeSourceName)\(battery)"
    }

    private func row<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}
