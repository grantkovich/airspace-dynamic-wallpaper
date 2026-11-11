import Foundation
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
}
