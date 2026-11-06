import AirspaceCore
import MapKit
import SwiftUI

/// One display's wallpaper: base map → rings → aircraft → info corner.
/// Used as a single view for previews and snapshots. The desktop windows host the three
/// stacks in separate layers (see `WallpaperController`) so 30 fps aircraft animation never
/// forces the static map to redraw.
struct AirspaceView: View {
    let model: AppModel
    let size: CGSize
    let insets: EdgeInsets
    @State private var shared = SharedObstacles()

    var body: some View {
        ZStack(alignment: .topLeading) {
            BaseStack(model: model, size: size, shared: shared)
            TrafficStack(model: model, size: size, insets: insets, shared: shared)
            InfoStack(model: model, size: size, insets: insets)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Re-resolves the palette once a minute (it follows the sun) and hands it to its content.
struct PaletteReader<Content: View>: View {
    let model: AppModel
    @ViewBuilder let content: (Palette) -> Content

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let palette = model.palette(at: timeline.date)
            content(palette)
                .environment(\.colorScheme, palette.isDark ? .dark : .light)
        }
    }
}

/// Static layer: base map and range rings. Redraws only when location, zoom, style or palette change.
struct BaseStack: View {
    let model: AppModel
    let size: CGSize
    let shared: SharedObstacles

    var body: some View {
        PaletteReader(model: model) { palette in
            ZStack {
                if let center = model.center {
                    let projection = Projection(center: center, size: size, radiusNM: model.settings.radiusNM)
                    BaseMapLayer(model: model, projection: projection, palette: palette, shared: shared)
                    if model.settings.mapStyle == .appleMap {
                        // MapKit is its own view, so rings need a layer above it. The other styles
                        // draw rings into their own canvas to save a full-screen backing surface.
                        RingsLayer(projection: projection, palette: palette, settings: model.settings)
                    }
                } else {
                    PureFieldLayer(palette: palette, dotGrid: true)
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

/// Animated layer: aircraft, trails and labels.
struct TrafficStack: View {
    let model: AppModel
    let size: CGSize
    let insets: EdgeInsets
    let shared: SharedObstacles

    var body: some View {
        PaletteReader(model: model) { palette in
            if let center = model.center {
                AircraftLayer(model: model,
                              projection: Projection(center: center, size: size, radiusNM: model.settings.radiusNM),
                              palette: palette,
                              infoRect: model.settings.infoEnabled
                                  ? InfoCorner.footprint(corner: model.settings.infoCorner, size: size, insets: insets) : nil,
                              shared: shared)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// 1 Hz layer: the info corner.
struct InfoStack: View {
    let model: AppModel
    let size: CGSize
    let insets: EdgeInsets

    var body: some View {
        PaletteReader(model: model) { palette in
            if model.settings.infoEnabled || model.center == nil {
                InfoCorner(model: model, palette: palette, size: size, insets: insets)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Base maps

struct BaseMapLayer: View {
    let model: AppModel
    let projection: Projection
    let palette: Palette
    let shared: SharedObstacles

    var body: some View {
        switch model.settings.mapStyle {
        case .schematic:
            SchematicLayer(geo: model.geo, projection: projection, palette: palette,
                           options: .init(roads: model.settings.showRoads, runways: model.settings.showRunways),
                           dotGrid: model.settings.showDotGrid, shared: shared,
                           rings: RingsLayer(projection: projection, palette: palette, settings: model.settings))
                .onDisappear { shared.rects = [] }
        case .appleMap:
            ZStack {
                AppleMapLayer(projection: projection, dark: palette.isDark)
                if model.settings.tintAppleMap {
                    // Wash the map toward the palette so aircraft stay the brightest thing on screen.
                    palette.water.color.opacity(palette.isDark ? 0.42 : 0.32)
                }
            }
        case .pureField:
            PureFieldLayer(palette: palette, dotGrid: model.settings.showDotGrid,
                           rings: RingsLayer(projection: projection, palette: palette, settings: model.settings))
        }
    }
}

struct PureFieldLayer: View {
    let palette: Palette
    let dotGrid: Bool
    var rings: RingsLayer?

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.land.color))
            if dotGrid { DotGrid.draw(in: &ctx, size: size, color: palette.dotGrid) }
            rings?.draw(in: &ctx, size: size)
        }
    }
}

enum DotGrid {
    static let spacing: CGFloat = 22

    static func draw(in ctx: inout GraphicsContext, size: CGSize, color: RGBA) {
        var path = Path()
        let r: CGFloat = 0.85
        // Centre the grid so it is symmetric on any screen size.
        let ox = (size.width.truncatingRemainder(dividingBy: spacing)) / 2
        let oy = (size.height.truncatingRemainder(dividingBy: spacing)) / 2
        var y = oy
        while y <= size.height {
            var x = ox
            while x <= size.width {
                path.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                x += spacing
            }
            y += spacing
        }
        ctx.fill(path, with: .color(color.color))
    }
}

/// Natural Earth + OurAirports geometry, projected off the main thread and cached.
struct SchematicLayer: View {
    let geo: GeoData?
    let projection: Projection
    let palette: Palette
    let options: SchematicGeometry.Options
    let dotGrid: Bool
    var shared: SharedObstacles?
    var rings: RingsLayer?

    @State private var built: (paths: SchematicPaths, projection: Projection)?
    @Environment(\.renderSynchronously) private var renderSynchronously

    private struct BuildKey: Hashable {
        var projection: Projection
        var options: SchematicGeometry.Options
        var hasGeo: Bool
    }

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.water.color))
            // ImageRenderer never runs `.task`, so headless renders build inline.
            let current = built ?? (renderSynchronously ? geo.map { (SchematicGeometry.build($0, projection: projection, options: options), projection) } : nil)
            if let built = current {
                var map = ctx
                // While a rebuild is in flight (e.g. dragging zoom), stretch the old paths into place.
                map.concatenate(Self.transform(from: built.projection, to: projection))
                draw(built.paths, in: &map, scale: projection.scale / built.projection.scale)
            }
            if dotGrid { DotGrid.draw(in: &ctx, size: size, color: palette.dotGrid.with(alpha: 0.7)) }
            rings?.draw(in: &ctx, size: size)
        }
        .task(id: BuildKey(projection: projection, options: options, hasGeo: geo != nil)) {
            guard let geo else { return }
            if built != nil { try? await Task.sleep(for: .milliseconds(60)) }   // debounce slider drags
            guard !Task.isCancelled else { return }
            let p = projection, o = options
            let paths = await Task.detached(priority: .userInitiated) { SchematicGeometry.build(geo, projection: p, options: o) }.value
            guard !Task.isCancelled else { return }
            built = (paths, p)
            shared?.rects = Self.labelRects(paths)
        }
    }

    private func draw(_ p: SchematicPaths, in ctx: inout GraphicsContext, scale: Double) {
        let hair = 1 / max(0.01, scale)   // keep hairlines ~constant while stretched
        ctx.fill(Path(p.land), with: .color(palette.land.color), style: FillStyle(eoFill: true))
        ctx.fill(Path(p.urban), with: .color(palette.urban.color), style: FillStyle(eoFill: true))
        ctx.fill(Path(p.lakes), with: .color(palette.water.color), style: FillStyle(eoFill: true))
        ctx.stroke(Path(p.lakes), with: .color(palette.river.color), lineWidth: 0.6 * hair)
        ctx.stroke(Path(p.land), with: .color(palette.river.color), lineWidth: 0.6 * hair)
        ctx.stroke(Path(p.rivers), with: .color(palette.river.color), style: StrokeStyle(lineWidth: 0.9 * hair, lineCap: .round, lineJoin: .round))
        ctx.stroke(Path(p.roads), with: .color(palette.road.color), style: StrokeStyle(lineWidth: 0.8 * hair, lineCap: .round, lineJoin: .round))
        ctx.stroke(Path(p.states), with: .color(palette.stateLine.color), style: StrokeStyle(lineWidth: 0.7 * hair, dash: [4 * hair, 3 * hair]))

        // Runways at roughly true width (150 ft), never thinner than a hairline.
        let runwayWidth = max(1.2, min(5, projection.pointsPerNM * 150 / 6076)) * hair
        ctx.stroke(Path(p.runways), with: .color(palette.runway.color), style: StrokeStyle(lineWidth: runwayWidth, lineCap: .butt))
        for label in p.airportLabels {
            let text = Text(label.code)
                .font(.system(size: label.isMajor ? 10 : 8.5, weight: .semibold).width(.expanded))
                .tracking(1.2)
                .foregroundColor(palette.airportLabel.color)
            ctx.draw(text, at: CGPoint(x: label.point.x, y: label.point.y + 16 * hair), anchor: .top)
        }
    }

    /// Where airport codes are drawn, so aircraft labels can avoid them.
    static func labelRects(_ paths: SchematicPaths) -> [CGRect] {
        paths.airportLabels.map { l in
            let w = CGFloat(l.code.count) * (l.isMajor ? 9.5 : 8) + 4
            return CGRect(x: l.point.x - w / 2, y: l.point.y + 14, width: w, height: 14)
        }
    }

    static func transform(from old: Projection, to new: Projection) -> CGAffineTransform {
        if old == new { return .identity }
        let k = new.scale / old.scale
        let co = Projection.world(old.center), cn = Projection.world(new.center)
        let bx = Double(new.size.width) / 2 + Double(co.x - cn.x) * new.scale - Double(old.size.width) / 2 * k
        let by = Double(new.size.height) / 2 + Double(co.y - cn.y) * new.scale - Double(old.size.height) / 2 * k
        return CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: bx, ty: by)
    }
}

/// Apple's muted map, framed to exactly the same Mercator rect as everything drawn on top.
struct AppleMapLayer: NSViewRepresentable {
    let projection: Projection
    let dark: Bool

    func makeNSView(context: Context) -> MKMapView {
        let view = MKMapView()
        let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        config.pointOfInterestFilter = .excludingAll
        config.showsTraffic = false
        view.preferredConfiguration = config
        view.isZoomEnabled = false
        view.isScrollEnabled = false
        view.isRotateEnabled = false
        view.isPitchEnabled = false
        view.showsCompass = false
        view.showsZoomControls = false
        view.showsScale = false
        view.showsUserLocation = false
        view.showsPitchControl = false
        return view
    }

    func updateNSView(_ view: MKMapView, context: Context) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        if view.appearance?.name != appearance?.name { view.appearance = appearance }
        let r = projection.worldRect
        let w = MKMapSize.world.width
        let rect = MKMapRect(x: r.minX * w, y: r.minY * w, width: r.width * w, height: r.height * w)
        let current = view.visibleMapRect
        if abs(current.midX - rect.midX) > 1 || abs(current.width - rect.width) / rect.width > 0.001 {
            view.setVisibleMapRect(rect, animated: false)
        }
    }
}

// MARK: - Range rings & "you are here"

struct RingsLayer: View {
    let projection: Projection
    let palette: Palette
    let settings: WallpaperSettings

    var body: some View {
        Canvas { ctx, size in draw(in: &ctx, size: size) }
            .allowsHitTesting(false)
    }

    func draw(in ctx: inout GraphicsContext, size: CGSize) {
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            if settings.showRangeRings {
                let radii = RangeRings.radii(forZoomMiles: settings.zoomMiles)
                for (i, miles) in radii.enumerated() {
                    let r = miles * Geo.nmPerMile * projection.pointsPerNM
                    let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                    let outer = i == radii.count - 1
                    ctx.stroke(Path(ellipseIn: rect), with: .color(palette.ring.color),
                               style: StrokeStyle(lineWidth: outer ? 0.9 : 0.7, dash: outer ? [] : [2, 4]))
                    // Label just outside the ring at the 1:30 position.
                    let a = -Double.pi / 4
                    let lp = CGPoint(x: c.x + (r + 4) * cos(a), y: c.y + (r + 4) * sin(a))
                    let label = Text(Format.ringLabel(miles)).font(Typeface.mono(8.5, .medium)).tracking(0.8)
                        .foregroundColor(palette.ringLabel.color)
                    ctx.draw(label, at: lp, anchor: .bottomLeading)

                    if outer {
                        // Compass ticks + N on the outer ring.
                        for k in 0..<4 {
                            let θ = Double(k) * .pi / 2 - .pi / 2
                            var tick = Path()
                            tick.move(to: CGPoint(x: c.x + (r - 5) * cos(θ), y: c.y + (r - 5) * sin(θ)))
                            tick.addLine(to: CGPoint(x: c.x + (r + 5) * cos(θ), y: c.y + (r + 5) * sin(θ)))
                            ctx.stroke(tick, with: .color(palette.ringLabel.color), lineWidth: 1)
                        }
                        let n = Text("N").font(Typeface.caption(9)).foregroundColor(palette.ringLabel.color)
                        ctx.draw(n, at: CGPoint(x: c.x, y: c.y - r - 14), anchor: .center)
                    }
                }
            }
            // Crosshair: four short strokes around a gap, plus a centre dot.
            var cross = Path()
            for (dx, dy) in [(1.0, 0.0), (-1, 0), (0, 1), (0, -1)] {
                cross.move(to: CGPoint(x: c.x + dx * 4, y: c.y + dy * 4))
                cross.addLine(to: CGPoint(x: c.x + dx * 10, y: c.y + dy * 10))
            }
            ctx.stroke(cross, with: .color(palette.crosshair.color), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 1.2, y: c.y - 1.2, width: 2.4, height: 2.4)), with: .color(palette.crosshair.color))
    }
}

private struct RenderSynchronouslyKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Set for headless snapshot renders, where async work never runs.
    var renderSynchronously: Bool {
        get { self[RenderSynchronouslyKey.self] }
        set { self[RenderSynchronouslyKey.self] = newValue }
    }
}
