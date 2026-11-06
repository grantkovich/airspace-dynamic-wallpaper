import Foundation

public enum Motion {
    /// Projects a report forward along its track at its ground speed.
    public static func deadReckon(_ r: AircraftReport, at now: TimeInterval, maxExtrapolation: TimeInterval) -> Coordinate {
        guard let gs = r.groundSpeedKt, let track = r.trackDeg, gs > 0 else { return r.position }
        let dt = min(max(0, now - r.fixTime), maxExtrapolation)
        return Geo.offset(r.position, distanceNM: gs * dt / 3600, bearingDeg: track)
    }

    /// Cubic ease-out on 0…1, clamped.
    public static func easeOut(_ t: Double) -> Double {
        let x = min(1, max(0, t))
        return 1 - pow(1 - x, 3)
    }
}

/// A past position, kept for drawing trails.
public struct TrailFix: Hashable, Sendable {
    public var position: Coordinate
    public var altitudeFt: Double
    public var time: TimeInterval
}

public struct TrackedAircraft: Sendable {
    public var latest: AircraftReport
    /// Oldest first; the last element is `latest`'s position.
    public var trail: [TrailFix]
    public var firstSeen: TimeInterval
    /// Local time this aircraft last appeared in any response.
    public var lastSeen: TimeInterval
    /// Local time the latest *new* position arrived (drives the pulse).
    public var lastFixArrival: TimeInterval
    /// Offset (degrees) from the dead-reckoned position that eases out to zero.
    var correctionLat: Double = 0
    var correctionLon: Double = 0
    var correctionStart: TimeInterval = 0
}

/// What the renderer needs for one aircraft at one instant.
public struct DisplayAircraft: Sendable, Identifiable {
    public var id: String { report.hex }
    public var report: AircraftReport
    public var position: Coordinate
    public var trail: [TrailFix]
    /// 0…1, combines fade-in and stale fade-out.
    public var opacity: Double
    /// 1 right after a fresh fix, decaying to 0.
    public var pulse: Double
}

/// Merges successive batches of reports into smoothly moving, fading aircraft.
public struct AircraftTracker: Sendable {
    public var trailDuration: TimeInterval
    public var staleAfter: TimeInterval
    public var fadeDuration: TimeInterval
    public var fadeInDuration: TimeInterval = 0.8
    public var easeDuration: TimeInterval = 1.2
    public var pulseDuration: TimeInterval = 1.6
    public var maxExtrapolation: TimeInterval = 75

    public private(set) var aircraft: [String: TrackedAircraft] = [:]

    public init(trailDuration: TimeInterval = 180, staleAfter: TimeInterval = 60, fadeDuration: TimeInterval = 10) {
        self.trailDuration = trailDuration
        self.staleAfter = staleAfter
        self.fadeDuration = fadeDuration
    }

    public mutating func ingest(_ reports: [AircraftReport], at now: TimeInterval) {
        for r in reports {
            guard var existing = aircraft[r.hex] else {
                aircraft[r.hex] = TrackedAircraft(
                    latest: r,
                    trail: [TrailFix(position: r.position, altitudeFt: r.altitudeFt, time: r.fixTime)],
                    firstSeen: now, lastSeen: now, lastFixArrival: now)
                continue
            }
            existing.lastSeen = now
            if r.fixTime <= existing.latest.fixTime + 0.05 {
                // Same position re-served; keep metadata fresh (callsign can arrive late).
                existing.latest.callsign = r.callsign ?? existing.latest.callsign
                existing.latest.typeCode = r.typeCode ?? existing.latest.typeCode
                aircraft[r.hex] = existing
                continue
            }
            let shown = displayedPosition(existing, at: now)
            existing.latest = r
            existing.lastFixArrival = now
            existing.trail.append(TrailFix(position: r.position, altitudeFt: r.altitudeFt, time: r.fixTime))
            let target = Motion.deadReckon(r, at: now, maxExtrapolation: maxExtrapolation)
            existing.correctionLat = shown.latitude - target.latitude
            existing.correctionLon = wrapped(shown.longitude - target.longitude)
            existing.correctionStart = now
            trimTrail(&existing, now: now)
            aircraft[r.hex] = existing
        }
    }

    /// Removes aircraft that have fully faded out, and trims trails.
    public mutating func prune(at now: TimeInterval) {
        for (hex, var a) in aircraft {
            if now - a.lastSeen >= staleAfter + fadeDuration {
                aircraft[hex] = nil
            } else {
                let before = a.trail.count
                trimTrail(&a, now: now)
                if a.trail.count != before { aircraft[hex] = a }
            }
        }
    }

    public mutating func removeAll() { aircraft.removeAll() }

    public func snapshot(at now: TimeInterval) -> [DisplayAircraft] {
        aircraft.values.map { a in
            let fadeIn = min(1, max(0, (now - a.firstSeen) / fadeInDuration))
            let staleFor = now - a.lastSeen - staleAfter
            let fadeOut = staleFor <= 0 ? 1 : max(0, 1 - staleFor / fadeDuration)
            let sincePulse = now - a.lastFixArrival
            let pulse = a.trail.count > 1 && sincePulse < pulseDuration ? 1 - sincePulse / pulseDuration : 0
            return DisplayAircraft(report: a.latest, position: displayedPosition(a, at: now), trail: a.trail,
                                   opacity: min(fadeIn, fadeOut), pulse: max(0, pulse))
        }
        .sorted { $0.report.altitudeFt > $1.report.altitudeFt }   // draw high traffic first, low on top
    }

    func displayedPosition(_ a: TrackedAircraft, at now: TimeInterval) -> Coordinate {
        let base = Motion.deadReckon(a.latest, at: now, maxExtrapolation: maxExtrapolation)
        let remaining = 1 - Motion.easeOut((now - a.correctionStart) / easeDuration)
        guard remaining > 0 else { return base }
        return Coordinate(latitude: base.latitude + a.correctionLat * remaining,
                          longitude: wrapped(base.longitude + a.correctionLon * remaining))
    }

    private func trimTrail(_ a: inout TrackedAircraft, now: TimeInterval) {
        let cutoff = now - trailDuration
        if let firstKept = a.trail.firstIndex(where: { $0.time >= cutoff }), firstKept > 0 {
            a.trail.removeFirst(firstKept)
        } else if a.trail.count > 1, a.trail.last!.time < cutoff {
            a.trail = [a.trail.last!]
        }
    }

    private func wrapped(_ lon: Double) -> Double {
        lon > 180 ? lon - 360 : (lon < -180 ? lon + 360 : lon)
    }
}
