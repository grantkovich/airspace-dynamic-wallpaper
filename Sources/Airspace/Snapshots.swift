import AirspaceCore
import AppKit
import MapKit
import SwiftUI

/// `Airspace --snapshots <dir> [--at lat,lon] [--name NAME]`
/// Renders each map style × appearance with live traffic into PNGs, for reviewing the look
/// without installing the wallpaper. (Apple Map isn't renderable headlessly and is skipped.)
@MainActor
enum Snapshots {
    static func run(outputDirectory: String, arguments: [String]) {
        let center = value(after: "--at", in: arguments).flatMap(CoordinateParser.parse)
            ?? Coordinate(latitude: 41.93, longitude: -87.80)
        let name = value(after: "--name", in: arguments) ?? "Chicago"
        let size = CGSize(width: 1512, height: 982)
        let dir = URL(fileURLWithPath: outputDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let geo = AppModel.geoDataURL().flatMap { try? GeoData.load(from: $0) }
        let reports = fetchBlocking(center: center, radiusNM: 200)
        print("geodata: \(geo != nil ? "loaded" : "missing"), aircraft: \(reports.count)")

        let variants: [(String, (inout WallpaperSettings) -> Void)] = [
            ("schematic-night", { $0.appearance = .dark }),
            ("schematic-aluminum", { $0.appearance = .light }),
            ("schematic-night-altitude-colors", { $0.appearance = .dark; $0.colorMode = .altitude; $0.labelMode = .callsignTypeAltitude }),
            ("schematic-night-dots", { $0.appearance = .dark; $0.glyph = .light }),
            ("schematic-aluminum-mono-arrow", { $0.appearance = .light; $0.colorMode = .monochrome; $0.glyph = .arrow; $0.infoCorner = .topRight }),
            ("field-night", { $0.appearance = .dark; $0.mapStyle = .pureField }),
            ("field-aluminum-nolabels", { $0.appearance = .light; $0.mapStyle = .pureField; $0.labelMode = .off }),
            ("schematic-night-zoom10", { $0.appearance = .dark; $0.zoomMiles = 10 }),
            ("schematic-night-zoom120", { $0.appearance = .dark; $0.zoomMiles = 120 }),
            ("schematic-night-emergency", { $0.appearance = .dark }),
        ]
        renderGlyphSpecimen(dir: dir)
        renderAppleMap(center: center, name: name, geo: geo, reports: reports, size: size, dir: dir)
        if arguments.contains("--benchmark") {
            benchmark(center: center, geo: geo, reports: reports, size: size)
            return
        }
        for (file, configure) in variants {
            var s = WallpaperSettings()
            s.hasCompletedOnboarding = true
            configure(&s)
            let model = AppModel(settings: s, startServices: false)
            model.primaryScreenSize = size
            model.largestScreenSize = size
            let now = Date().timeIntervalSince1970
            var reports = reports
            if file.hasSuffix("emergency") {
                // Stage a 7700 on an airliner a few miles out, to review the alert styling.
                if let i = reports.firstIndex(where: { !$0.onGround && $0.callsign?.count ?? 0 > 4
                    && (6...20).contains(Geo.distanceNM($0.position, center)) }) {
                    reports[i].squawk = "7700"
                    reports[i].alert = .emergency
                }
            }
            model.stage(center: center, name: name, geo: geo, reports: reports, now: now,
                        details: FlightDetails(
                            origin: RouteAirport(code: "ORD", city: "Chicago",
                                                 coordinate: Coordinate(latitude: 41.9786, longitude: -87.9048)),
                            destination: RouteAirport(code: "LGA", city: "New York",
                                                      coordinate: Coordinate(latitude: 40.7772, longitude: -73.8726))))
            let view = AirspaceView(model: model, size: size, insets: EdgeInsets(top: 33, leading: 0, bottom: 70, trailing: 0))
                .environment(\.renderSynchronously, true)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                print("failed: \(file)"); continue
            }
            let url = dir.appendingPathComponent(file + ".png")
            try? png.write(to: url)
            print("wrote \(url.path)")
        }
    }

    /// Every aircraft class large and at actual size, on both palettes.
    static func renderGlyphSpecimen(dir: URL) {
        let classes: [AircraftClass] = [.jet, .heavy, .quad, .tailJet, .turboprop, .light, .helicopter]
        let view = VStack(spacing: 0) {
            ForEach([Palette.night, Palette.aluminum], id: \.isDark) { palette in
                Canvas { ctx, size in
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.land.color))
                    for (i, cls) in classes.enumerated() {
                        let color = palette.altitudeColors[i % palette.altitudeColors.count]
                        for (scale, y) in [(4.0, 90.0), (1.0, 195.0)] {
                            var t = CGAffineTransform(scaleX: scale, y: scale)
                                .concatenating(CGAffineTransform(rotationAngle: scale == 1 ? .pi / 4 : 0))
                                .concatenating(CGAffineTransform(translationX: 70 + Double(i) * 125, y: y))
                            let shape = Path(Silhouettes.path(for: cls).copy(using: &t)!)
                            ctx.stroke(shape, with: .color(palette.land.color), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                            ctx.fill(shape, with: .color(color.color))
                        }
                    }
                }
                .frame(width: 900, height: 230)
            }
        }
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let tiff = renderer.nsImage?.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent("glyphs.png"))
        }
    }

    /// Apple Map can't go through ImageRenderer, so snapshot the same MKMapRect with
    /// MKMapSnapshotter and composite our layers over it. Checks alignment too.
    static func renderAppleMap(center: Coordinate, name: String, geo: GeoData?, reports: [AircraftReport], size: CGSize, dir: URL) {
        for dark in [true, false] {
            var s = WallpaperSettings()
            s.mapStyle = .appleMap
            s.appearance = dark ? .dark : .light
            s.zoomMiles = 12
            let model = AppModel(settings: s, startServices: false)
            model.primaryScreenSize = size
            model.stage(center: center, name: name, geo: geo, reports: reports, now: Date().timeIntervalSince1970)
            let projection = Projection(center: center, size: size, radiusNM: s.radiusNM)
            let r = projection.worldRect, w = MKMapSize.world.width
            let options = MKMapSnapshotter.Options()
            options.mapRect = MKMapRect(x: r.minX * w, y: r.minY * w, width: r.width * w, height: r.height * w)
            options.size = size
            let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
            config.pointOfInterestFilter = .excludingAll
            options.preferredConfiguration = config
            options.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

            final class Box: @unchecked Sendable { var image: NSImage? }
            let box = Box()
            let done = DispatchSemaphore(value: 0)
            MKMapSnapshotter(options: options).start(with: .global()) { snap, error in
                box.image = snap?.image
                if let error { print("snapshotter: \(error)") }
                done.signal()
            }
            done.wait()
            guard let base = box.image else { continue }
            let palette = model.palette()
            let view = ZStack(alignment: .topLeading) {
                Image(nsImage: base).resizable().saturation(AppleMapLayer.saturation).frame(width: size.width, height: size.height)
                palette.water.color.opacity(palette.isDark ? 0.42 : 0.32)
                RingsLayer(projection: projection, palette: palette, settings: s)
                TrafficStack(model: model, size: size, insets: EdgeInsets(top: 33, leading: 0, bottom: 70, trailing: 0), shared: SharedObstacles())
                InfoStack(model: model, size: size, insets: EdgeInsets(top: 33, leading: 0, bottom: 70, trailing: 0))
                if ProcessInfo.processInfo.environment["AIRSPACE_ALIGNMENT"] != nil {
                    AlignmentMarks(projection: projection, geo: geo)
                }
            }
            .frame(width: size.width, height: size.height)
            .environment(\.renderSynchronously, true)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let tiff = renderer.nsImage?.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                let url = dir.appendingPathComponent(dark ? "apple-night.png" : "apple-aluminum.png")
                try? png.write(to: url)
                print("wrote \(url.path)")
            }
        }
    }

    /// Times one frame of the animated layer (aircraft, trails, labels) rendered offscreen.
    /// ImageRenderer rasterizes on the CPU, so this is an upper bound on per-frame cost.
    static func benchmark(center: Coordinate, geo: GeoData?, reports: [AircraftReport], size: CGSize) {
        let cases: [(String, LabelMode, Double, Double)] = [
            ("full", .callsign, 3, 35), ("full, solid colours", .callsign, 3, 35),
            ("no labels", .off, 3, 35), ("no labels/trails", .off, 0, 35),
            ("stress: 150 mi, 10 min trails, full labels", .callsignTypeAltitude, 10, 150),
        ]
        for (name, labels, trails, zoom) in cases {
            var s = WallpaperSettings()
            s.labelMode = labels
            s.trailMinutes = trails
            s.zoomMiles = zoom
            s.fullLivery = !name.contains("solid")
            let model = AppModel(settings: s, startServices: false)
            model.primaryScreenSize = size
            model.stage(center: center, name: "Bench", geo: geo, reports: reports, now: Date().timeIntervalSince1970)
            let view = TrafficStack(model: model, size: size, insets: EdgeInsets(), shared: SharedObstacles())
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            _ = renderer.cgImage
            let n = 20
            let start = Date()
            for _ in 0..<n {
                renderer.content = TrafficStack(model: model, size: size, insets: EdgeInsets(), shared: SharedObstacles())
                _ = renderer.cgImage
            }
            let ms = Date().timeIntervalSince(start) / Double(n) * 1000
            print(String(format: "%@: %.1f ms/frame (%d aircraft drawn)", name, ms, Diagnostics.aircraftDrawn))
        }
        benchmarkComponents(center: center, reports: reports, size: size)
    }

    /// The per-frame CPU work that the full-frame numbers above can't isolate (the renderer is
    /// rebuilt each iteration there, so its caches never warm up): trail projection, cold vs
    /// cached, and label placement for every aircraft at wide zoom.
    static func benchmarkComponents(center: Coordinate, reports: [AircraftReport], size: CGSize) {
        var s = WallpaperSettings()
        s.zoomMiles = 150
        s.trailMinutes = 10
        let model = AppModel(settings: s, startServices: false)
        model.stage(center: center, name: "Bench", geo: nil, reports: reports, now: Date().timeIntervalSince1970)
        let projection = Projection(center: center, size: size, radiusNM: s.radiusNM)
        let aircraft = model.tracker.snapshot(at: Date().timeIntervalSince1970)
        let points = aircraft.reduce(0) { $0 + $1.trail.count }
        func time(_ n: Int, _ body: () -> Void) -> Double {
            let start = Date()
            for _ in 0..<n { body() }
            return Date().timeIntervalSince(start) / Double(n) * 1000
        }
        let cold = time(50) { for a in aircraft { _ = a.trail.map { projection.point($0.position) } } }
        let cache = TrailProjectionCache()
        let warm = time(50) { cache.beginFrame(); for a in aircraft { _ = cache.points(for: a, projection: projection) } }
        print(String(format: "trail projection, %d aircraft / %d points: %.2f ms uncached, %.3f ms cached", aircraft.count, points, cold, warm))

        let requests = aircraft.map { a in
            LabelRequest(id: a.id, anchor: projection.point(a.position), size: CGSize(width: 64, height: 12),
                         priority: a.report.altitudeFt, gap: 13)
        }
        let bounds = CGRect(origin: .zero, size: size)
        let layout = time(50) { _ = LabelLayout.layout(requests, obstacles: [], bounds: bounds, previous: [:], glyphRadius: 5) }
        print(String(format: "label layout, %d labels: %.2f ms", requests.count, layout))
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    private static func fetchBlocking(center: Coordinate, radiusNM: Double) -> [AircraftReport] {
        final class Box: @unchecked Sendable { var value: [AircraftReport] = [] }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            box.value = (try? await ReadsbSource(.adsbLol).aircraft(near: center, radiusNM: radiusNM)) ?? []
            if box.value.isEmpty {
                box.value = (try? await ReadsbSource(.adsbFi).aircraft(near: center, radiusNM: radiusNM)) ?? []
            }
            done.signal()
        }
        done.wait()
        return box.value
    }
}

/// `Airspace --icon <dir.iconset>`: renders the app icon at every size `iconutil` wants.
@MainActor
enum IconRenderer {
    static func run(outputDirectory: String) {
        let dir = URL(fileURLWithPath: outputDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
            let renderer = ImageRenderer(content: AppIcon().frame(width: 1024, height: 1024))
            renderer.scale = CGFloat(points * scale) / 1024
            guard let tiff = renderer.nsImage?.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
            try? png.write(to: dir.appendingPathComponent(name))
        }
        print("wrote \(dir.path)")
    }
}

/// Night field, dot grid, range rings and three lit aircraft with trails.
struct AppIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let p = Palette.night
            let inset: CGFloat = 100
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            let shape = Path(roundedRect: rect, cornerRadius: 185, style: .continuous)
            ctx.fill(shape, with: .linearGradient(Gradient(colors: [RGBA(hex: 0x17191C).color, RGBA(hex: 0x0A0B0D).color]),
                                                 startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
            ctx.clip(to: shape)
            var dots = Path()
            for x in stride(from: rect.minX + 30, to: rect.maxX, by: 52) {
                for y in stride(from: rect.minY + 30, to: rect.maxY, by: 52) {
                    dots.addEllipse(in: CGRect(x: x - 3, y: y - 3, width: 6, height: 6))
                }
            }
            ctx.fill(dots, with: .color(p.dotGrid.with(alpha: 0.8).color))
            let c = CGPoint(x: rect.midX, y: rect.midY)
            for r in [130.0, 260, 390] {
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                           with: .color(RGBA(hex: 0x3A3C41).color), lineWidth: r == 390 ? 7 : 5)
            }
            let planes: [(CGPoint, CGPoint, RGBA)] = [
                (CGPoint(x: 300, y: 690), CGPoint(x: 560, y: 470), p.altitudeColors[0]),
                (CGPoint(x: 820, y: 330), CGPoint(x: 640, y: 690), p.altitudeColors[3]),
                (CGPoint(x: 250, y: 330), CGPoint(x: 430, y: 300), p.altitudeColors[2]),
            ]
            for (from, to, color) in planes {
                var trail = Path()
                trail.move(to: from)
                trail.addLine(to: to)
                ctx.stroke(trail, with: .linearGradient(Gradient(colors: [color.with(alpha: 0).color, color.with(alpha: 0.75).color]),
                                                        startPoint: from, endPoint: to),
                           style: StrokeStyle(lineWidth: 14, lineCap: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: to.x - 70, y: to.y - 70, width: 140, height: 140)),
                         with: .radialGradient(Gradient(colors: [color.with(alpha: 0.55).color, color.with(alpha: 0).color]),
                                               center: to, startRadius: 0, endRadius: 70))
                ctx.fill(Path(ellipseIn: CGRect(x: to.x - 24, y: to.y - 24, width: 48, height: 48)), with: .color(color.color))
                ctx.fill(Path(ellipseIn: CGRect(x: to.x - 10, y: to.y - 10, width: 20, height: 20)), with: .color(.white.opacity(0.85)))
            }
            var cross = Path()
            for (dx, dy) in [(1.0, 0.0), (-1, 0), (0, 1), (0, -1)] {
                cross.move(to: CGPoint(x: c.x + dx * 18, y: c.y + dy * 18))
                cross.addLine(to: CGPoint(x: c.x + dx * 46, y: c.y + dy * 46))
            }
            ctx.stroke(cross, with: .color(p.crosshair.color), style: StrokeStyle(lineWidth: 9, lineCap: .round))
        }
    }
}

/// Thin cyan runway centrelines from our own data, drawn only in the Apple Map snapshot so
/// misalignment between MapKit and our projection would be obvious.
private struct AlignmentMarks: View {
    let projection: Projection
    let geo: GeoData?

    var body: some View {
        Canvas { ctx, _ in
            guard let geo else { return }
            var p = Path()
            for ap in geo.airports(in: projection.visibleBounds) {
                for (a, b) in ap.runways {
                    p.move(to: projection.point(a))
                    p.addLine(to: projection.point(b))
                }
            }
            ctx.stroke(p, with: .color(.cyan.opacity(0.9)), lineWidth: 1)
        }
    }
}

/// `Airspace --render-settings <dir>`: draws the real Settings window (AppKit controls and all)
/// offscreen for every section, for reviewing the UI without screen-recording access.
@MainActor
enum SettingsRender {
    static func run(outputDirectory: String) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let dir = URL(fileURLWithPath: outputDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var s = WallpaperSettings()
        s.hasCompletedOnboarding = true
        let model = AppModel(settings: s, startServices: false)
        model.primaryScreenSize = CGSize(width: 1512, height: 982)
        let geo = AppModel.geoDataURL().flatMap { try? GeoData.load(from: $0) }
        let center = Coordinate(latitude: 41.93, longitude: -87.80)
        let reports = (try? ReadsbDecoder.decode(Data(contentsOf: URL(fileURLWithPath: "Tests/AirspaceCoreTests/Fixtures/adsbfi.json")),
                                                 receivedAt: Date().timeIntervalSince1970)) ?? []
        model.stage(center: center, name: "Chicago", geo: geo, reports: reports, now: Date().timeIntervalSince1970)

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for section in SettingsSection.allCases {
                let host = NSHostingView(rootView: SettingsView(model: model, initialSection: section)
                    .environment(\.renderSynchronously, true))
                let window = NSWindow(contentRect: CGRect(x: -5000, y: -5000, width: 820, height: 700),
                                      styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                window.contentView = host
                window.layoutIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.6))   // let SwiftUI settle
                let view = window.contentView!.superview ?? host
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let name = "\(section.rawValue)-\(appearance == .aqua ? "light" : "dark").png"
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
                window.close()
            }
        }
        // The menu-bar panel, with the restore prompt showing.
        model.wallpaperNeedsManualRestore = true
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            render(MenuPanel(model: model), size: CGSize(width: 320, height: 640), appearance: appearance,
                   to: dir.appendingPathComponent("menu-restore-\(suffix).png"))
        }
        print("wrote \(dir.path)")
    }

    private static func render(_ root: some View, size: CGSize, appearance: NSAppearance.Name, to url: URL) {
        let host = NSHostingView(rootView: root.environment(\.renderSynchronously, true))
        let window = NSWindow(contentRect: CGRect(x: -5000, y: -5000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.setContentSize(host.fittingSize.height > 0 ? CGSize(width: size.width, height: min(size.height, host.fittingSize.height)) : size)
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.close()
    }
}
