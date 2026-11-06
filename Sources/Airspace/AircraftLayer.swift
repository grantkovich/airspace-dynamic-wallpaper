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
                                 stale: model.isStale, overheadHex: model.overhead?.hex,
                                 colorFor: { model.color(for: $0, palette: palette) })
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
    let colorFor: (AircraftReport) -> RGBA

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
            let color = colorFor(a.report)

            if settings.trailMinutes > 0 { drawTrail(a, head: pt, color: color, alpha: alpha, in: &ctx) }
            if settings.pulse && a.pulse > 0 { drawPulse(at: pt, pulse: a.pulse, color: color, alpha: alpha, in: &ctx) }
            drawGlyph(a, at: pt, color: color, alpha: alpha, in: &ctx)

            if a.id == overheadHex {
                let r: CGFloat = settings.glyph == .silhouette ? 16 : 10
                ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                           with: .color(palette.textPrimary.with(alpha: 0.55 * alpha).color), lineWidth: 0.8)
            }

            if settings.labelMode != .off, bounds.contains(pt), let label = labelImage(a) {
                let distance = hypot(pt.x - size.width / 2, pt.y - size.height / 2)
                let priority = a.id == overheadHex ? -1 : Double(distance) + a.report.altitudeFt / 100
                labelRequests.append(LabelRequest(id: a.id, anchor: pt,
                                                  size: CGSize(width: label.size.width + 2, height: max(12, label.size.height)),
                                                  priority: priority, gap: settings.glyph == .silhouette ? 13 : 8))
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
        let altitude = Format.shortAltitude(a.report.altitudeFt)
        let type = a.report.typeCode
        let secondary: String? = switch settings.labelMode {
        case .off, .callsign: nil
        case .callsignAltitude: altitude
        case .callsignType: type
        case .callsignTypeAltitude: [type, altitude].compactMap { $0 }.joined(separator: " ")
        }
        let name = callsign(a), tertiary = palette.textTertiary, palette = palette
        return MainActor.assumeIsolated {
            LabelImageCache.shared.label(name, secondary, primaryColor: primary, secondaryColor: tertiary, palette: palette)
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
            // In altitude mode each stretch of trail shows the altitude it was flown at.
            let bandColor = settings.colorMode == .altitude && end < a.trail.count
                ? palette.altitudeColor(a.trail[end].altitudeFt) : color
            ctx.stroke(path, with: .color(bandColor.with(alpha: pow(t, 1.6) * peak * alpha).color),
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
        let glowR: CGFloat = settings.glyph == .silhouette ? 15 : 13
        let glowAlpha = (settings.glyph == .silhouette ? 0.5 : 1) * (0.12 + 0.28 * palette.glow) * alpha
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
            let transform = CGAffineTransform(rotationAngle: heading).concatenating(CGAffineTransform(translationX: p.x, y: p.y))
            let shape = Path(Silhouettes.path(for: cls)).applying(transform)
            // A thin halo in the ground colour separates the icon from trails and map lines.
            ctx.stroke(shape, with: .color(palette.land.with(alpha: 0.85 * alpha).color), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            ctx.fill(shape, with: .color(color.with(alpha: alpha).color))
        }
    }
}
