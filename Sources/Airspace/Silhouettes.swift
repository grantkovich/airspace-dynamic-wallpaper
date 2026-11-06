import AirspaceCore
import CoreGraphics

/// Top-down aircraft icons, nose up (north), centred on the origin, in points.
/// Each is assembled from simple parts and unioned once, so drawing is a single fill.
/// The paths are immutable after creation, so sharing them across threads is safe.
enum Silhouettes {
    static func path(for cls: AircraftClass) -> CGPath {
        switch cls {
        case .jet, .other: jet
        case .heavy: heavy
        case .quad: quad
        case .tailJet: tailJet
        case .turboprop: turboprop
        case .light: light
        case .helicopter: helicopter
        }
    }

    /// Overall icon scale: roughly 22–30 pt long on screen, like a flight tracker.
    private static let base: CGFloat = 1.25

    /// Narrow-body airliner (A320 / 737 class): swept wings, underwing engine pods.
    nonisolated(unsafe) static let jet: CGPath = airliner(engines: [3.6], span: 9.8, scale: base)

    /// Wide-body twin (777 / 787 / A350).
    nonisolated(unsafe) static let heavy: CGPath = airliner(engines: [3.9], span: 10.4, scale: base * 1.3)

    /// Four-engine wide-body (747 / A380 / A340).
    nonisolated(unsafe) static let quad: CGPath = airliner(engines: [3.4, 6.6], span: 10.8, scale: base * 1.42)

    /// Rear-engined jets (CRJ, Gulfstream, Citation): clean wing, pods by the tail, T-tail.
    nonisolated(unsafe) static let tailJet: CGPath = {
        var parts: [CGPath] = [fuselage(halfWidth: 1.05, nose: -9.2, tail: 9.0)]
        parts += mirrored(polygon([(0.9, -0.6), (8.0, 3.2), (8.0, 4.0), (0.9, 2.6)]))         // wing
        parts += mirrored(roundedRect(x: 1.0, y: 4.0, w: 1.7, h: 3.2, r: 0.8))                // rear engine pod
        parts += mirrored(polygon([(0.5, 7.4), (3.8, 8.9), (3.8, 9.6), (0.5, 9.1)]))           // T-tail
        return union(parts, scale: base * 0.95)
    }()

    /// Regional turboprop (ATR / Dash 8): straight wing, forward nacelles, T-tail.
    nonisolated(unsafe) static let turboprop: CGPath = {
        var parts: [CGPath] = [fuselage(halfWidth: 1.15, nose: -8.6, tail: 8.4)]
        parts += mirrored(polygon([(1.0, -2.0), (10.5, -1.4), (10.5, 0.1), (1.0, 0.7)]))
        parts += mirrored(roundedRect(x: 3.5, y: -3.8, w: 1.5, h: 4.4, r: 0.75))
        parts += mirrored(polygon([(0.6, 6.2), (4.4, 6.6), (4.4, 7.7), (0.6, 7.9)]))
        return union(parts, scale: base * 1.05)
    }()

    /// Light single (Cessna class): high straight wing, tapered fuselage.
    nonisolated(unsafe) static let light: CGPath = {
        var parts: [CGPath] = [polygon([(0.95, -6.2), (0.95, -2.4), (0.5, 6.2), (-0.5, 6.2), (-0.95, -2.4), (-0.95, -6.2)])]
        parts.append(roundedRect(x: -7.8, y: -2.6, w: 15.6, h: 2.3, r: 0.9))
        parts.append(roundedRect(x: -3.2, y: 4.5, w: 6.4, h: 1.6, r: 0.6))
        return union(parts, scale: base * 0.9)
    }()

    /// Helicopter: cabin, tail boom, tail rotor, two-blade main rotor.
    nonisolated(unsafe) static let helicopter: CGPath = {
        var parts: [CGPath] = [CGPath(ellipseIn: CGRect(x: -2.3, y: -4.6, width: 4.6, height: 7.2), transform: nil)]
        parts.append(roundedRect(x: -0.45, y: 1.8, w: 0.9, h: 6.6, r: 0.4))
        parts.append(roundedRect(x: -1.8, y: 7.6, w: 3.6, h: 0.8, r: 0.4))
        for angle in [CGFloat.pi / 4, -CGFloat.pi / 4] {
            var t = CGAffineTransform(rotationAngle: angle)
            parts.append(CGPath(roundedRect: CGRect(x: -8, y: -0.5, width: 16, height: 1.0), cornerWidth: 0.5, cornerHeight: 0.5, transform: &t))
        }
        return union(parts, scale: base * 0.95)
    }()

    /// Swept-wing airliner; `engines` are spanwise pod positions, mounted ahead of the leading edge.
    private static func airliner(engines: [CGFloat], span: CGFloat, scale: CGFloat) -> CGPath {
        let sweep: CGFloat = 0.55   // leading-edge rise per unit of span
        var parts: [CGPath] = [fuselage(halfWidth: 1.35, nose: -10, tail: 9.8)]
        parts += mirrored(polygon([(1.0, -1.9), (span, -1.9 + (span - 1) * sweep), (span, -0.7 + (span - 1) * sweep), (1.0, 2.3)]))
        for x in engines {
            let leadingEdge = -1.9 + (x - 1) * sweep
            parts += mirrored(roundedRect(x: x - 0.8, y: leadingEdge - 1.6, w: 1.6, h: 3.0, r: 0.8))
        }
        parts += mirrored(polygon([(0.8, 6.3), (4.4, 8.4), (4.4, 9.2), (0.8, 8.2)]))           // stabiliser
        return union(parts, scale: scale)
    }

    // MARK: Parts

    /// Rounded nose and tapered tail cone.
    private static func fuselage(halfWidth w: CGFloat, nose: CGFloat, tail: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: nose))
        p.addQuadCurve(to: CGPoint(x: w, y: nose + 2.8), control: CGPoint(x: w, y: nose + 0.4))
        p.addLine(to: CGPoint(x: w, y: tail - 2.8))
        p.addQuadCurve(to: CGPoint(x: w * 0.35, y: tail), control: CGPoint(x: w * 0.95, y: tail - 0.6))
        p.addLine(to: CGPoint(x: -w * 0.35, y: tail))
        p.addQuadCurve(to: CGPoint(x: -w, y: tail - 2.8), control: CGPoint(x: -w * 0.95, y: tail - 0.6))
        p.addLine(to: CGPoint(x: -w, y: nose + 2.8))
        p.addQuadCurve(to: CGPoint(x: 0, y: nose), control: CGPoint(x: -w, y: nose + 0.4))
        p.closeSubpath()
        return p
    }

    private static func polygon(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: pts.map { CGPoint(x: $0.0, y: $0.1) })
        p.closeSubpath()
        return p
    }

    private static func roundedRect(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, r: CGFloat) -> CGPath {
        CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
    }

    /// The part plus its mirror image across the centreline.
    private static func mirrored(_ part: CGPath) -> [CGPath] {
        var flip = CGAffineTransform(scaleX: -1, y: 1)
        return [part, part.copy(using: &flip) ?? part]
    }

    /// Boolean union, so overlapping parts never cancel out under any fill rule.
    private static func union(_ parts: [CGPath], scale: CGFloat) -> CGPath {
        var shape = parts[0]
        for part in parts.dropFirst() { shape = shape.union(part) }
        var t = CGAffineTransform(scaleX: scale, y: scale)
        return shape.copy(using: &t) ?? shape
    }
}
