import AirspaceCore
import CoreGraphics

/// One icon, split into paintable parts. `outline` is the union of everything, for the halo
/// and for single-colour fills.
struct SilhouetteParts: @unchecked Sendable {
    let outline: CGPath
    let body: CGPath
    let wings: CGPath
    let engines: CGPath?
    /// Horizontal tailplanes. Painted in the tail colour: a stylisation, but it doubles the
    /// colour a 25-point icon shows, which is what makes the airline readable.
    let stabilisers: CGPath
    /// The fin seen from above: a stripe down the rear fuselage, forward and aft halves.
    let tailFore: CGPath
    let tailAft: CGPath
}

/// Top-down aircraft icons, nose up (north), centred on the origin, in points.
/// Each is assembled from simple parts and unioned once, so a single-colour icon is one fill.
/// The paths are immutable after creation, so sharing them across threads is safe.
enum Silhouettes {
    static func path(for cls: AircraftClass) -> CGPath { parts(for: cls).outline }

    static func parts(for cls: AircraftClass) -> SilhouetteParts {
        switch cls {
        case .jet, .other: jetParts
        case .heavy: heavyParts
        case .quad: quadParts
        case .tailJet: tailJetParts
        case .turboprop: turbopropParts
        case .light: lightParts
        case .helicopter: helicopterParts
        }
    }

    /// Overall icon scale: roughly 22–30 pt long on screen, like a flight tracker.
    private static let base: CGFloat = 1.25

    static var jet: CGPath { jetParts.outline }

    /// Narrow-body airliner (A320 / 737 class): swept wings, underwing engine pods.
    static let jetParts = airliner(engines: [3.6], span: 9.8, scale: base)

    /// Wide-body twin (777 / 787 / A350).
    static let heavyParts = airliner(engines: [3.9], span: 10.4, scale: base * 1.3)

    /// Four-engine wide-body (747 / A380 / A340).
    static let quadParts = airliner(engines: [3.4, 6.6], span: 10.8, scale: base * 1.42)

    /// Rear-engined jets (CRJ, Gulfstream, Citation): clean wing, pods by the tail, T-tail.
    static let tailJetParts: SilhouetteParts = assemble(
        body: [fuselage(halfWidth: 1.05, nose: -9.2, tail: 9.0)],
        wings: mirrored(polygon([(0.9, -0.6), (8.0, 3.2), (8.0, 4.0), (0.9, 2.6)])),            // wing
        stabilisers: mirrored(polygon([(0.5, 7.4), (3.8, 8.9), (3.8, 9.6), (0.5, 9.1)])),       // T-tail
        engines: mirrored(roundedRect(x: 1.0, y: 4.0, w: 1.7, h: 3.2, r: 0.8)),                 // rear pods
        fin: (from: 3.2, to: 8.8, halfWidth: 0.65), scale: base * 0.95)

    /// Regional turboprop (ATR / Dash 8): straight wing, forward nacelles, T-tail.
    static let turbopropParts: SilhouetteParts = assemble(
        body: [fuselage(halfWidth: 1.15, nose: -8.6, tail: 8.4)],
        wings: mirrored(polygon([(1.0, -2.0), (10.5, -1.4), (10.5, 0.1), (1.0, 0.7)])),
        stabilisers: mirrored(polygon([(0.6, 6.2), (4.4, 6.6), (4.4, 7.7), (0.6, 7.9)])),
        engines: mirrored(roundedRect(x: 3.5, y: -3.8, w: 1.5, h: 4.4, r: 0.75)),
        fin: (from: 3.0, to: 8.2, halfWidth: 0.7), scale: base * 1.05)

    /// Light single (Cessna class): high straight wing, tapered fuselage.
    static let lightParts: SilhouetteParts = assemble(
        body: [polygon([(0.95, -6.2), (0.95, -2.4), (0.5, 6.2), (-0.5, 6.2), (-0.95, -2.4), (-0.95, -6.2)])],
        wings: [roundedRect(x: -7.8, y: -2.6, w: 15.6, h: 2.3, r: 0.9)],
        stabilisers: [roundedRect(x: -3.2, y: 4.5, w: 6.4, h: 1.6, r: 0.6)],
        engines: [],
        fin: (from: 2.2, to: 6.1, halfWidth: 0.5), scale: base * 0.9)

    /// Helicopter: cabin, tail boom, tail rotor, two-blade main rotor.
    static let helicopterParts: SilhouetteParts = {
        var rotor: [CGPath] = []
        for angle in [CGFloat.pi / 4, -CGFloat.pi / 4] {
            var t = CGAffineTransform(rotationAngle: angle)
            rotor.append(CGPath(roundedRect: CGRect(x: -8, y: -0.5, width: 16, height: 1.0), cornerWidth: 0.5, cornerHeight: 0.5, transform: &t))
        }
        return assemble(
            body: [CGPath(ellipseIn: CGRect(x: -2.3, y: -4.6, width: 4.6, height: 7.2), transform: nil),
                   roundedRect(x: -0.45, y: 1.8, w: 0.9, h: 6.6, r: 0.4)],
            wings: rotor,
            stabilisers: [roundedRect(x: -1.8, y: 7.6, w: 3.6, h: 0.8, r: 0.4)],
            engines: [],
            fin: (from: 3.0, to: 8.3, halfWidth: 0.5), scale: base * 0.95)
    }()

    /// Swept-wing airliner; `engines` are spanwise pod positions, mounted ahead of the leading edge.
    private static func airliner(engines: [CGFloat], span: CGFloat, scale: CGFloat) -> SilhouetteParts {
        let sweep: CGFloat = 0.55   // leading-edge rise per unit of span
        var pods: [CGPath] = []
        for x in engines {
            let leadingEdge = -1.9 + (x - 1) * sweep
            pods += mirrored(roundedRect(x: x - 0.8, y: leadingEdge - 1.6, w: 1.6, h: 3.0, r: 0.8))
        }
        return assemble(
            body: [fuselage(halfWidth: 1.35, nose: -10, tail: 9.8)],
            wings: mirrored(polygon([(1.0, -1.9), (span, -1.9 + (span - 1) * sweep), (span, -0.7 + (span - 1) * sweep), (1.0, 2.3)])),
            stabilisers: mirrored(polygon([(0.8, 6.3), (4.4, 8.4), (4.4, 9.2), (0.8, 8.2)])),
            engines: pods,
            fin: (from: 3.6, to: 9.4, halfWidth: 0.75), scale: scale)
    }

    /// Scales and unions each group of parts, and cuts the fin stripe in two.
    private static func assemble(body: [CGPath], wings: [CGPath], stabilisers: [CGPath], engines: [CGPath],
                                 fin: (from: CGFloat, to: CGFloat, halfWidth: CGFloat), scale: CGFloat) -> SilhouetteParts {
        let mid = (fin.from + fin.to) / 2
        let fore = roundedRect(x: -fin.halfWidth, y: fin.from, w: fin.halfWidth * 2, h: mid - fin.from, r: fin.halfWidth)
        let aft = CGPath(rect: CGRect(x: -fin.halfWidth, y: mid, width: fin.halfWidth * 2, height: fin.to - mid), transform: nil)
        return SilhouetteParts(
            outline: union(body + wings + stabilisers + engines, scale: scale),
            body: union(body, scale: scale),
            wings: union(wings, scale: scale),
            engines: engines.isEmpty ? nil : union(engines, scale: scale),
            stabilisers: union(stabilisers, scale: scale),
            tailFore: union([fore], scale: scale),
            tailAft: union([aft], scale: scale))
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
