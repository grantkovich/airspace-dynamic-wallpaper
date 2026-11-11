import AppKit
import os

/// Cheap counters logged every 30 s:
/// `log stream --level info --predicate 'subsystem == "com.grantkovich.airspace"'`
@MainActor
enum Diagnostics {
    static let log = Logger(subsystem: "com.grantkovich.airspace", category: "render")
    static var framesDrawn = 0
    static var aircraftDrawn = 0

    static func report(model: AppModel) {
        log.info("""
            mode=\(model.powerMode.kind.rawValue, privacy: .public) fps=\(model.powerMode.fps) \
            occluded=\(model.powerInputs.allOccluded) frames=\(framesDrawn) lastAircraft=\(aircraftDrawn) \
            tracked=\(model.tracker.aircraft.count) source=\(model.activeSourceName, privacy: .public) stale=\(model.isStale)
            """)
        framesDrawn = 0
    }

    /// Plain text for a bug report: versions, displays and feed state. Never the location.
    static func summary(model: AppModel) -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let screens = NSScreen.screens.map { s in
            "\(Int(s.frame.width))×\(Int(s.frame.height))@\(Int(s.backingScaleFactor))x"
        }.joined(separator: ", ")
        var lines = [
            "Airspace \(version) (\(build)) on macOS \(os), \(machineArchitecture)",
            "Displays: \(screens)",
            "Power: \(model.powerMode.kind.rawValue), \(model.powerMode.fps) fps, desktop covered: \(model.powerInputs.allOccluded)",
            "Map: \(model.settings.mapStyle.rawValue), \(Int(model.settings.zoomMiles)) mi, system wallpaper sync: \(model.settings.syncSystemWallpaper)",
            "Flights: \(model.tracker.aircraft.count) tracked from \(model.activeSourceName), stale: \(model.isStale)",
        ]
        if let last = model.lastSuccess { lines.append("Last update: \(last.formatted(date: .abbreviated, time: .standard))") }
        if let error = model.fetchError { lines.append("Last error: \(error)") }
        if model.wallpaperNeedsManualRestore { lines.append("Wallpaper: couldn't restore automatically") }
        return lines.joined(separator: "\n")
    }

    static func copySummary(model: AppModel) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary(model: model), forType: .string)
    }

    private static var machineArchitecture: String {
        #if arch(arm64)
        "Apple silicon"
        #else
        "Intel"
        #endif
    }
}
