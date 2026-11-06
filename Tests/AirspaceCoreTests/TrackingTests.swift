import Foundation
import Testing
@testable import AirspaceCore

private func report(_ hex: String = "abc123", lat: Double = 40, lon: Double = -80, alt: Double = 10_000,
                    gs: Double? = 360, track: Double? = 90, t: TimeInterval) -> AircraftReport {
    AircraftReport(hex: hex, callsign: "TST1", position: Coordinate(latitude: lat, longitude: lon),
                   altitudeFt: alt, groundSpeedKt: gs, trackDeg: track, fixTime: t)
}

@Suite struct MotionTests {
    @Test func deadReckoningMovesAlongTrack() {
        // 360 kt east for 60 s = 6 nm = 0.1° of longitude / cos(lat)
        let r = report(lat: 0, lon: 0, gs: 360, track: 90, t: 0)
        let p = Motion.deadReckon(r, at: 60, maxExtrapolation: 120)
        #expect(abs(p.latitude) < 1e-9)
        #expect(abs(p.longitude - 0.1) < 1e-6)
    }

    @Test func deadReckoningIsCapped() {
        let r = report(lat: 0, lon: 0, gs: 360, track: 0, t: 0)
        let p = Motion.deadReckon(r, at: 1_000, maxExtrapolation: 60)
        #expect(abs(p.latitude - 0.1) < 1e-6)
    }

    @Test func missingVelocityStaysPut() {
        let r = report(lat: 1, lon: 2, gs: nil, track: nil, t: 0)
        #expect(Motion.deadReckon(r, at: 30, maxExtrapolation: 60) == r.position)
    }

    @Test func easeOutIsMonotonicAndBounded() {
        #expect(Motion.easeOut(0) == 0)
        #expect(Motion.easeOut(1) == 1)
        #expect(Motion.easeOut(2) == 1)
        #expect(Motion.easeOut(0.5) > 0.5)
    }
}

@Suite struct TrackerTests {
    @Test func newAircraftAppearsAndFadesIn() {
        var tracker = AircraftTracker()
        tracker.ingest([report(t: 100)], at: 100)
        let start = tracker.snapshot(at: 100)
        #expect(start.count == 1)
        #expect(start[0].opacity == 0)
        #expect(tracker.snapshot(at: 101)[0].opacity == 1)
    }

    @Test func newFixEasesInsteadOfJumping() throws {
        var tracker = AircraftTracker()
        tracker.ingest([report(lat: 0, lon: 0, gs: 360, track: 90, t: 0)], at: 0)
        // At t=10 we have been drawing it ~1 nm east. The real fix says it is 1 nm further north.
        let before = try #require(tracker.snapshot(at: 10).first).position
        tracker.ingest([report(lat: 1.0 / 60, lon: 1.0 / 60, gs: 360, track: 90, t: 10)], at: 10)
        let justAfter = try #require(tracker.snapshot(at: 10).first).position
        #expect(abs(justAfter.latitude - before.latitude) < 1e-9)
        #expect(abs(justAfter.longitude - before.longitude) < 1e-9)
        // Once the ease completes we're exactly on the new track.
        let settled = try #require(tracker.snapshot(at: 12).first).position
        let truth = Motion.deadReckon(report(lat: 1.0 / 60, lon: 1.0 / 60, t: 10), at: 12, maxExtrapolation: 120)
        #expect(abs(settled.latitude - truth.latitude) < 1e-9)
        #expect(abs(settled.longitude - truth.longitude) < 1e-9)
    }

    @Test func repeatedFixDoesNotRestartEasingOrGrowTrail() {
        var tracker = AircraftTracker()
        tracker.ingest([report(t: 0)], at: 0)
        tracker.ingest([report(t: 0)], at: 5)
        #expect(tracker.aircraft["abc123"]?.trail.count == 1)
        #expect(tracker.aircraft["abc123"]?.lastSeen == 5)
    }

    @Test func trailIsTrimmedToWindow() {
        var tracker = AircraftTracker(trailDuration: 60)
        for t in stride(from: 0.0, through: 120, by: 10) {
            tracker.ingest([report(lat: 40 + t / 1000, t: t)], at: t)
        }
        let trail = tracker.aircraft["abc123"]?.trail ?? []
        #expect(trail.first?.time == 60)
        #expect(trail.last?.time == 120)
    }

    @Test func staleAircraftFadeThenDisappear() {
        var tracker = AircraftTracker(staleAfter: 60, fadeDuration: 10)
        tracker.ingest([report(t: 0)], at: 0)
        #expect(tracker.snapshot(at: 59)[0].opacity == 1)
        #expect(abs(tracker.snapshot(at: 65)[0].opacity - 0.5) < 1e-9)
        tracker.prune(at: 71)
        #expect(tracker.aircraft.isEmpty)
    }

    @Test func pulseDecaysAfterFreshFix() {
        var tracker = AircraftTracker()
        tracker.ingest([report(t: 0)], at: 0)
        tracker.ingest([report(lat: 40.01, t: 5)], at: 5)
        let fresh = tracker.snapshot(at: 5)[0].pulse
        let later = tracker.snapshot(at: 7)[0].pulse
        #expect(fresh == 1)
        #expect(later == 0)
    }
}

@Suite struct ProjectionTests {
    let projection = Projection(center: Coordinate(latitude: 41.97, longitude: -87.90),
                                size: CGSize(width: 1600, height: 1000), radiusNM: 30)

    @Test func centerMapsToMiddle() {
        let p = projection.point(projection.center)
        #expect(abs(p.x - 800) < 1e-6)
        #expect(abs(p.y - 500) < 1e-6)
    }

    @Test func radiusMapsToShortHalfAxis() {
        let north = Geo.offset(projection.center, distanceNM: 30, bearingDeg: 0)
        let p = projection.point(north)
        #expect(abs(p.y - 0) < 5)        // top edge; Mercator stretches ~0.5% over 30 nm of latitude
        let east = Geo.offset(projection.center, distanceNM: 30, bearingDeg: 90)
        #expect(abs(projection.point(east).x - 1300) < 2)
    }

    @Test func roundTrip() {
        let c = Coordinate(latitude: 42.1, longitude: -88.2)
        let back = projection.coordinate(projection.point(c))
        #expect(abs(back.latitude - c.latitude) < 1e-9)
        #expect(abs(back.longitude - c.longitude) < 1e-9)
    }

    @Test func fetchRadiusCoversCorners() {
        // half-diagonal / short half-axis = hypot(800,500)/500 = 1.887; × 1.15 margin
        #expect(abs(projection.fetchRadiusNM - 30 * 1.8868 * 1.15) < 0.1)
        let tiny = Projection(center: projection.center, size: CGSize(width: 100, height: 100), radiusNM: 0.1)
        #expect(tiny.fetchRadiusNM == 1)
        let huge = Projection(center: projection.center, size: CGSize(width: 3000, height: 1000), radiusNM: 200)
        #expect(huge.fetchRadiusNM == 250)
    }

    @Test func visibleBoundsContainCorners() {
        let b = projection.visibleBounds
        let corner = projection.coordinate(CGPoint(x: 0, y: 0))
        #expect(b.contains(corner))
        #expect(b.contains(projection.center))
    }
}

@Suite struct PowerPolicyTests {
    let settings = PowerSettings(pollInterval: 5, fpsCap: 30, batterySaver: true)

    @Test func normal() {
        #expect(PowerPolicy.mode(PowerInputs(), settings) == PowerMode(kind: .normal, pollInterval: 5, fps: 30))
    }

    @Test func battery() {
        let m = PowerPolicy.mode(PowerInputs(onBattery: true), settings)
        #expect(m == PowerMode(kind: .battery, pollInterval: 15, fps: 15))
        var noSaver = settings
        noSaver.batterySaver = false
        #expect(PowerPolicy.mode(PowerInputs(onBattery: true), noSaver).kind == .normal)
        #expect(PowerPolicy.mode(PowerInputs(lowPowerMode: true), noSaver).kind == .battery)
    }

    @Test func batteryRespectsSlowerUserInterval() {
        var slow = settings
        slow.pollInterval = 30
        slow.fpsCap = 10
        #expect(PowerPolicy.mode(PowerInputs(onBattery: true), slow) == PowerMode(kind: .battery, pollInterval: 30, fps: 10))
    }

    @Test func occludedStopsDrawingButKeepsSlowPoll() {
        #expect(PowerPolicy.mode(PowerInputs(allOccluded: true), settings) == PowerMode(kind: .occluded, pollInterval: 60, fps: 0))
    }

    @Test func suspendedStatesStopEverything() {
        for inputs in [PowerInputs(screenLocked: true), PowerInputs(displaysAsleep: true), PowerInputs(paused: true),
                       PowerInputs(onBattery: true, allOccluded: true, screenLocked: true)] {
            #expect(PowerPolicy.mode(inputs, settings) == PowerMode(kind: .suspended, pollInterval: nil, fps: 0))
        }
    }
}
