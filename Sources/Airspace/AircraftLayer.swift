import AirspaceCore
import SwiftUI

/// Remembers which side each label sat on, so labels don't hop between frames.
final class LabelMemory {
    var slots: [String: LabelSlot] = [:]
}

/// Pre-rendered label bitmaps. Drawing a cached image is several times cheaper per frame
/// than laying out text, and callsigns rarely change.
@MainActor
final class LabelImageCache {
    static let shared = LabelImageCache()
    private var images: [String: (image: Image, size: CGSize)] = [:]
    private var paletteKey: Palette?

    func label(_ primary: String, _ secondary: String?, primaryColor: RGBA, secondaryColor: RGBA, palette: Palette) -> (image: Image, size: CGSize)? {
        if paletteKey != palette || images.count > 800 {
            images.removeAll(keepingCapacity: true)
            paletteKey = palette
        }
        let key = primary + "|" + (secondary ?? "") + (primaryColor == palette.textPrimary ? "!" : "")
        if let hit = images[key] { return hit }
        var text = Text(primary).foregroundColor(primaryColor.color)
        if let secondary { text = text + Text(" " + secondary).foregroundColor(secondaryColor.color) }
        let renderer = ImageRenderer(content: text.font(Typeface.label).tracking(Typeface.labelTracking).fixedSize())
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return nil }
        let entry = (Image(decorative: cg, scale: 2), CGSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
        images[key] = entry
        return entry
    }
}

/// Screen rects other layers have claimed (airport codes), shared with the label layout.
final class SharedObstacles {
    var rects: [CGRect] = []
}

struct AircraftLayer: View {
    let model: AppModel
    let projection: Projection
    let palette: Palette
    /// The info corner's area: labels avoid it and traffic beneath it is dimmed.
    let infoRect: CGRect?
    let shared: SharedObstacles

    @State private var memory = LabelMemory()

    var body: some View {
        let fps = model.powerMode.fps
        TimelineView(.animation(minimumInterval: 1 / max(1, fps), paused: fps <= 0)) { timeline in
            Canvas { ctx, size in
                Diagnostics.framesDrawn += 1
                AircraftRenderer(settings: model.settings, palette: palette, projection: projection,
                                 stale: model.isStale, overheadHex: model.overhead?.hex)
                    .draw(model.tracker.snapshot(at: timeline.date.timeIntervalSince1970).filter { model.isVisible($0.report) },
                          in: &ctx, size: size, obstacles: obstacles(size), scrim: infoRect, memory: memory)
            }
        }
        .allowsHitTesting(false)
    }

    private func obstacles(_ size: CGSize) -> [CGRect] {
        let crosshair = CGRect(x: size.width / 2 - 12, y: size.height / 2 - 12, width: 24, height: 24)
        return [crosshair] + shared.rects + (infoRect.map { [$0] } ?? [])
    }
}

struct AircraftRenderer {
    let settings: WallpaperSettings
    let palette: Palette
    let projection: Projection
    let stale: Bool
    let overheadHex: String?

    func draw(_ aircraft: [DisplayAircraft], in ctx: inout GraphicsContext, size: CGSize,
              obstacles: [CGRect], scrim: CGRect?, memory: LabelMemory) {
        let bounds = CGRect(origin: .zero, size: size)
        let cull = bounds.insetBy(dx: -40, dy: -40)
        let dim = (stale ? 0.4 : 1) * settings.brightness

        var drawn = 0
        defer { MainActor.assumeIsolated { Diagnostics.aircraftDrawn = drawn } }
        var labelRequests: [LabelRequest] = []
        var labelInfo: [String: (aircraft: DisplayAircraft, image: Image, size: CGSize)] = [:]

        for a in aircraft {
            let pt = projection.point(a.position)
            guard cull.contains(pt), a.opacity > 0 else { continue }
            drawn += 1
            let alpha = a.opacity * dim
            let color = settings.colorMode == .altitude ? palette.altitudeColor(a.report.onGround ? 0 : a.report.altitudeFt) : palette.monochrome

            if settings.trailMinutes > 0 { drawTrail(a, head: pt, color: color, alpha: alpha, in: &ctx) }
            if settings.pulse && a.pulse > 0 { drawPulse(at: pt, pulse: a.pulse, color: color, alpha: alpha, in: &ctx) }
            drawGlyph(a, at: pt, color: color, alpha: alpha, in: &ctx)

            if a.id == overheadHex {
                let r: CGFloat = settings.glyph == .silhouette ? 14 : 10
                ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                           with: .color(palette.textPrimary.with(alpha: 0.55 * alpha).color), lineWidth: 0.8)
            }

            if settings.labelMode != .off, bounds.contains(pt), let label = labelImage(a) {
                let distance = hypot(pt.x - size.width / 2, pt.y - size.height / 2)
                let priority = a.id == overheadHex ? -1 : Double(distance) + a.report.altitudeFt / 100
                labelRequests.append(LabelRequest(id: a.id, anchor: pt,
                                                  size: CGSize(width: label.size.width + 2, height: max(12, label.size.height)),
                                                  priority: priority, gap: settings.glyph == .silhouette ? 11 : 8))
                labelInfo[a.id] = (a, label.image, label.size)
            }
        }

        if let scrim { punchOut(scrim, in: &ctx) }
        guard !labelRequests.isEmpty else { return }
        let placed = LabelLayout.layout(labelRequests, obstacles: obstacles, bounds: bounds.insetBy(dx: 6, dy: 6),
                                        previous: memory.slots, glyphRadius: 5)
        var slots: [String: LabelSlot] = [:]
        for label in placed {
            guard let info = labelInfo[label.id] else { continue }
            slots[label.id] = label.slot
            var c = ctx
            c.opacity = info.aircraft.opacity * dim
            c.draw(info.image, in: CGRect(x: label.rect.minX + 1, y: label.rect.midY - info.size.height / 2,
                                          width: info.size.width, height: info.size.height))
        }
        memory.slots = slots
    }

    // MARK: Pieces

    /// Fades out whatever was drawn under the info corner, with soft edges (stacked insets are
    /// much cheaper per frame than a blur).
    private func punchOut(_ rect: CGRect, in ctx: inout GraphicsContext) {
        var c = ctx
        c.blendMode = .destinationOut
        let steps = 8
        for i in 0..<steps {
            let inset = CGFloat(steps - i) * 7 - 20
            let r = rect.insetBy(dx: inset, dy: inset)
            c.fill(Path(roundedRect: r, cornerRadius: 40), with: .color(.black.opacity(0.22)))
        }
    }

    private func callsign(_ a: DisplayAircraft) -> String {
        Self.displayName(a.report)
    }

    /// Callsign, else registration, else the ICAO address (readsb marks non-ICAO ids with "~").
    static func displayName(_ r: AircraftReport) -> String {
        r.callsign ?? r.registration ?? r.hex.replacingOccurrences(of: "~", with: "").uppercased()
    }

    private func labelImage(_ a: DisplayAircraft) -> (image: Image, size: CGSize)? {
        let primary = a.id == overheadHex ? palette.textPrimary : RGBA.mix(palette.textSecondary, palette.textPrimary, 0.35)
        let secondary = settings.labelMode == .callsignAltitude ? Format.shortAltitude(a.report.altitudeFt) : nil
        return MainActor.assumeIsolated {
            LabelImageCache.shared.label(callsign(a), secondary, primaryColor: primary,
                                         secondaryColor: palette.textTertiary, palette: palette)
        }
    }

    /// Trail fades from transparent (oldest) to ~half strength at the aircraft, drawn in a few bands.
    private func drawTrail(_ a: DisplayAircraft, head: CGPoint, color: RGBA, alpha: Double, in ctx: inout GraphicsContext) {
        var points = a.trail.map { projection.point($0.position) }
        points.append(head)
        guard points.count >= 2 else { return }
        let segments = points.count - 1
        let bands = min(6, segments)
        let peak = palette.isDark ? 0.5 : 0.6
        for b in 0..<bands {
            let start = b * segments / bands
            let end = (b + 1) * segments / bands
            guard end > start else { continue }
            var path = Path()
            path.move(to: points[start])
            for i in (start + 1)...end { path.addLine(to: points[i]) }
            let t = Double(b + 1) / Double(bands)
            ctx.stroke(path, with: .color(color.with(alpha: pow(t, 1.6) * peak * alpha).color),
                       style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawPulse(at p: CGPoint, pulse: Double, color: RGBA, alpha: Double, in ctx: inout GraphicsContext) {
        let r = 4 + (1 - pulse) * 14
        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                   with: .color(color.with(alpha: pulse * 0.45 * alpha).color), lineWidth: 1)
    }

    private func drawGlyph(_ a: DisplayAircraft, at p: CGPoint, color: RGBA, alpha: Double, in ctx: inout GraphicsContext) {
        let heading = (a.report.trackDeg ?? 0) * .pi / 180
        // Bloom: wide and soft on dark, a faint halo on light.
        let glowR: CGFloat = 13
        let glowAlpha = (0.12 + 0.28 * palette.glow) * alpha
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - glowR, y: p.y - glowR, width: glowR * 2, height: glowR * 2)),
                 with: .radialGradient(Gradient(colors: [color.with(alpha: glowAlpha).color, color.with(alpha: 0).color]),
                                       center: p, startRadius: 0, endRadius: glowR))

        switch settings.glyph {
        case .light:
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.7, y: p.y - 2.7, width: 5.4, height: 5.4)), with: .color(color.with(alpha: alpha).color))
            if palette.isDark {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.1, y: p.y - 1.1, width: 2.2, height: 2.2)),
                         with: .color(RGBA(1, 1, 1, 0.75 * alpha).color))
            }
            if a.report.trackDeg != nil, (a.report.groundSpeedKt ?? 0) > 30 {
                var tick = Path()
                tick.move(to: CGPoint(x: p.x + 4.5 * sin(heading), y: p.y - 4.5 * cos(heading)))
                tick.addLine(to: CGPoint(x: p.x + 10 * sin(heading), y: p.y - 10 * cos(heading)))
                ctx.stroke(tick, with: .color(color.with(alpha: 0.85 * alpha).color), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
        case .arrow:
            var arrow = Path()
            arrow.move(to: CGPoint(x: 0, y: -6.5))
            arrow.addLine(to: CGPoint(x: 4.5, y: 5))
            arrow.addLine(to: CGPoint(x: 0, y: 2.5))
            arrow.addLine(to: CGPoint(x: -4.5, y: 5))
            arrow.closeSubpath()
            ctx.fill(arrow.applying(CGAffineTransform(rotationAngle: heading).concatenating(CGAffineTransform(translationX: p.x, y: p.y))),
                     with: .color(color.with(alpha: alpha).color))
        case .silhouette:
            let cls = AircraftClass.classify(category: a.report.category, typeCode: a.report.typeCode)
            let path = Silhouettes.path(for: cls)
            ctx.fill(path.applying(CGAffineTransform(rotationAngle: heading).concatenating(CGAffineTransform(translationX: p.x, y: p.y))),
                     with: .color(color.with(alpha: alpha).color))
        }
    }
}

/// Small top-down silhouettes, nose up (north), centred on the origin.
enum Silhouettes {
    static func path(for cls: AircraftClass) -> Path {
        switch cls {
        case .heavy: jet(scale: 1.3)
        case .jet, .other: jet(scale: 1)
        case .turboprop: straightWing(span: 13, length: 11, scale: 1)
        case .light: straightWing(span: 11, length: 8, scale: 0.85)
        case .helicopter: helicopter
        }
    }

    private static func jet(scale s: CGFloat) -> Path {
        var p = Path()
        let pts: [(CGFloat, CGFloat)] = [
            (0, -7), (0.9, -5.5), (1, -1.5), (6.5, 1.8), (6.5, 2.8), (1, 1.4), (0.8, 4.8), (2.6, 6.2), (2.6, 7),
            (0, 6.4), (-2.6, 7), (-2.6, 6.2), (-0.8, 4.8), (-1, 1.4), (-6.5, 2.8), (-6.5, 1.8), (-1, -1.5), (-0.9, -5.5),
        ]
        p.addLines(pts.map { CGPoint(x: $0.0 * s, y: $0.1 * s) })
        p.closeSubpath()
        return p
    }

    private static func straightWing(span: CGFloat, length: CGFloat, scale s: CGFloat) -> Path {
        var p = Path()
        let h = length / 2, w = span / 2
        p.addRoundedRect(in: CGRect(x: -0.9 * s, y: -h * s, width: 1.8 * s, height: length * s), cornerSize: CGSize(width: 0.9 * s, height: 0.9 * s))
        p.addRect(CGRect(x: -w * s, y: (-h * 0.35) * s, width: span * s, height: 1.8 * s))
        p.addRect(CGRect(x: -2.6 * s, y: (h - 1.6) * s, width: 5.2 * s, height: 1.2 * s))
        return p
    }

    private static var helicopter: Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: -2.4, y: -3.2, width: 4.8, height: 6))
        p.addRect(CGRect(x: -0.5, y: 2.5, width: 1, height: 5))
        p.addRect(CGRect(x: -2, y: 6.8, width: 4, height: 0.9))
        // rotor disc as a thin cross
        p.addRect(CGRect(x: -7, y: -0.9, width: 14, height: 0.7))
        p.addRect(CGRect(x: -0.35, y: -7.5, width: 0.7, height: 13))
        return p
    }
}
