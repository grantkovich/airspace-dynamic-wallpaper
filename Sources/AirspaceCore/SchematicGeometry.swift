import CoreGraphics
import Foundation

/// Pre-projected base-map paths for one projection. Built off the main thread whenever the
/// location, zoom, or screen size changes; drawn every frame from cache.
public struct SchematicPaths: @unchecked Sendable {
    public var land = CGMutablePath()
    public var lakes = CGMutablePath()
    public var urban = CGMutablePath()
    public var rivers = CGMutablePath()
    public var roads = CGMutablePath()
    public var states = CGMutablePath()
    public var runways = CGMutablePath()
    public var airportLabels: [AirportLabel] = []

    public struct AirportLabel: Sendable, Hashable {
        public var code: String
        public var point: CGPoint
        public var isMajor: Bool
    }

    public init() {}
}

public enum SchematicGeometry {
    public struct Options: Hashable, Sendable {
        public var roads = true
        public var runways = true
        public init(roads: Bool = true, runways: Bool = true) {
            self.roads = roads
            self.runways = runways
        }
    }

    public static func build(_ geo: GeoData, projection p: Projection, options: Options = .init()) -> SchematicPaths {
        var out = SchematicPaths()
        let view = CGRect(origin: .zero, size: p.size)
        let near = view.insetBy(dx: -64, dy: -64)
        let bounds = p.unwrappedBounds.expanded(by: 0.08)
        let radius = p.radiusNM

        func add(_ layer: GeoLayer, to path: CGMutablePath, closed: Bool, maxRank: UInt8 = .max) {
            for (feature, shift) in geo.features(layer, nearUnwrapped: bounds) where feature.rank <= maxRank {
                for ring in feature.rings {
                    appendRing(ring, shift: shift, projection: p, near: near, closed: closed, to: path)
                }
            }
        }

        add(.land, to: out.land, closed: true)
        add(.lakes, to: out.lakes, closed: true)
        add(.urban, to: out.urban, closed: true)
        add(.rivers, to: out.rivers, closed: false, maxRank: radius < 50 ? .max : 8)
        add(.states, to: out.states, closed: false)
        if options.roads {
            add(.roads, to: out.roads, closed: false, maxRank: radius < 25 ? .max : (radius < 70 ? 8 : 6))
        }

        if options.runways {
            let pxPerNM = p.pointsPerNM
            for ap in geo.airports where bounds.contains(ap.position) {
                guard ap.rank == 0 || radius < 60 else { continue }
                // Runways are a few thousand feet: skip them when they'd be sub-pixel specks.
                if pxPerNM > 3 {
                    for (a, b) in ap.runways {
                        out.runways.move(to: p.pointUnwrapped(a))
                        out.runways.addLine(to: p.pointUnwrapped(b))
                    }
                }
                let pt = p.pointUnwrapped(ap.position)
                if view.insetBy(dx: 24, dy: 24).contains(pt) {
                    out.airportLabels.append(.init(code: ap.code, point: pt, isMajor: ap.rank == 0))
                }
            }
        }
        return out
    }

    /// Projects one ring with screen-space thinning: fine (0.6 pt) near the view, coarse far away.
    /// Coarse tolerance stays below the margin, so thinned edges can never cut into the view.
    static func appendRing(_ ring: [GeoPoint], shift: Double, projection p: Projection, near: CGRect,
                           closed: Bool, to path: CGMutablePath) {
        guard ring.count >= 2 else { return }
        var last = CGPoint.zero
        var emitted = 0
        for (i, g) in ring.enumerated() {
            let pt = p.pointUnwrapped(Coordinate(latitude: Double(g.x), longitude: Double(g.y) + shift))
            if emitted > 0 && i != ring.count - 1 {
                let tol: CGFloat = near.contains(pt) || near.contains(last) ? 0.6 : 24
                if abs(pt.x - last.x) < tol && abs(pt.y - last.y) < tol { continue }
            }
            if emitted == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            last = pt
            emitted += 1
        }
        if closed { path.closeSubpath() }
    }
}

extension GeoData {
    /// Features overlapping `bounds`, where bounds may extend past ±180°; each comes with the
    /// longitude shift (−360, 0, +360) that brings it next to the view.
    func features(_ layer: GeoLayer, nearUnwrapped bounds: GeoBounds) -> [(GeoFeature, Double)] {
        var out: [(GeoFeature, Double)] = []
        for f in layers[layer] ?? [] {
            for shift in [0.0, -360, 360] {
                var b = f.bounds
                b.minLon += shift
                b.maxLon += shift
                if b.intersects(bounds) {
                    out.append((f, shift))
                    break
                }
            }
        }
        return out
    }
}

extension Projection {
    /// Like `point(_:)` but without antimeridian wrapping, so a feature's points stay continuous.
    public func pointUnwrapped(_ c: Coordinate) -> CGPoint {
        let w = Projection.world(Coordinate(latitude: c.latitude, longitude: 0))
        let wx = (c.longitude + 180) / 360
        let cw = Projection.world(center)
        return CGPoint(x: Double(size.width) / 2 + (wx - Double(cw.x)) * scale,
                       y: Double(size.height) / 2 + Double(w.y - cw.y) * scale)
    }

    /// Visible bounds whose longitudes may run past ±180° (never wrapped).
    public var unwrappedBounds: GeoBounds {
        let r = worldRect
        let top = Projection.coordinate(world: CGPoint(x: 0.5, y: r.minY)).latitude
        let bottom = Projection.coordinate(world: CGPoint(x: 0.5, y: r.maxY)).latitude
        return GeoBounds(minLat: bottom, maxLat: top, minLon: Double(r.minX) * 360 - 180, maxLon: Double(r.maxX) * 360 - 180)
    }
}

public enum RangeRings {
    /// Up to three "nice" ring radii (in miles) that fit inside the zoom radius.
    public static func radii(forZoomMiles zoom: Double) -> [Double] {
        let nice: [Double] = [1, 2, 2.5, 5, 10, 15, 20, 25, 50, 75, 100, 150]
        let outer = nice.last { $0 <= zoom * 0.92 } ?? nice[0]
        var rings = [outer]
        for fraction in [0.5, 0.25] {
            let target = outer * fraction
            if let r = nice.last(where: { $0 <= target * 1.05 }), r < rings.last!, r >= outer * 0.18 {
                rings.append(r)
            }
        }
        return rings.reversed()
    }
}
