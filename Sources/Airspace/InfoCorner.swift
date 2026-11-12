import AirspaceCore
import SwiftUI

/// The quiet typographic block in one corner: place, time, count and the flight overhead.
struct InfoCorner: View {
    let model: AppModel
    let palette: Palette
    let size: CGSize
    let insets: EdgeInsets

    static let margin: CGFloat = 52
    static let width: CGFloat = 420

    /// Approximate area the block occupies, so map labels can stay out of it.
    static func footprint(corner: Corner, size: CGSize, insets: EdgeInsets, legendRows: Int = 0, alertRows: Int = 0,
                          showsRoute: Bool = false) -> CGRect {
        let h: CGFloat = 240 + (showsRoute ? 50 : 0) + (legendRows > 0 ? CGFloat(legendRows) * 22 + 44 : 0)
            + CGFloat(min(alertRows, 3)) * 18
        let x = corner == .topLeft || corner == .bottomLeft ? insets.leading + margin - 12 : size.width - insets.trailing - margin - width + 12
        let y = corner == .topLeft || corner == .topRight ? insets.top + margin - 12 : size.height - insets.bottom - margin - h + 12
        return CGRect(x: x, y: y, width: width, height: h)
    }

    private var corner: Corner { model.settings.infoCorner }
    private var isTop: Bool { corner == .topLeft || corner == .topRight }
    private var isLeading: Bool { corner == .topLeft || corner == .bottomLeft }
    private var hAlign: HorizontalAlignment { isLeading ? .leading : .trailing }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(alignment: hAlign, spacing: 18) {
                if isTop {
                    placeBlock(now: timeline.date)
                    alertBlock
                    overheadBlock
                    airlineBlock
                } else {
                    airlineBlock
                    overheadBlock
                    alertBlock
                    placeBlock(now: timeline.date)
                }
            }
            .multilineTextAlignment(isLeading ? .leading : .trailing)
            .frame(width: Self.width, alignment: isLeading ? .leading : .trailing)
            .background {
                // Apple's map has its own labels; give the text a soft plate on that style only.
                if model.settings.mapStyle == .appleMap && model.center != nil {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(palette.land.color.opacity(0.88))
                        .padding(-30)
                        .blur(radius: 22)
                }
            }
            .padding(EdgeInsets(top: insets.top + Self.margin, leading: insets.leading + Self.margin,
                                bottom: insets.bottom + Self.margin, trailing: insets.trailing + Self.margin))
            .frame(width: size.width, height: size.height,
                   alignment: Alignment(horizontal: hAlign, vertical: isTop ? .top : .bottom))
        }
        .allowsHitTesting(false)
    }

    // MARK: Place

    @ViewBuilder
    private func placeBlock(now: Date) -> some View {
        VStack(alignment: hAlign, spacing: 8) {
            Text(model.placeName.uppercased())
                .font(Typeface.display(34))
                .tracking(5)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(palette.textPrimary.color)
            ForEach(metaLines(now: now), id: \.self) { line in
                Text(line)
                    .font(Typeface.mono(11, .medium))
                    .tracking(1.2)
                    .foregroundStyle(palette.textSecondary.color)
                    .lineLimit(1)
            }
            if let status = statusLine(now: now) {
                Text(status)
                    .font(Typeface.mono(10.5, .semibold))
                    .tracking(1.2)
                    .foregroundStyle(palette.altitudeColors[1].color)
            }
        }
    }

    /// Where and when on one line; traffic counts on the next, so neither overflows the column.
    private func metaLines(now: Date) -> [String] {
        var place: [String] = []
        if model.settings.infoShowCoordinates, let c = model.center { place.append(Format.coordinate(c)) }
        if model.settings.infoShowClock { place.append(now.formatted(date: .omitted, time: .shortened).uppercased()) }
        var traffic: [String] = []
        if model.settings.infoShowCount, model.center != nil {
            traffic.append("\(model.aircraftInView) IN VIEW")
            if model.aircraftToday > 0 { traffic.append("\(model.aircraftToday.formatted()) SEEN TODAY") }
        }
        return [place, traffic].filter { !$0.isEmpty }.map { $0.joined(separator: "  ·  ") }
    }

    private func statusLine(now: Date) -> String? {
        if model.center == nil {
            if model.locationMessage != nil { return "LOCATION UNAVAILABLE · OPEN AIRSPACE SETTINGS" }
            return model.settings.hasCompletedOnboarding ? "LOCATING…" : "CHOOSE A LOCATION FROM THE MENU BAR"
        }
        if model.paused { return "PAUSED" }
        if model.isStale { return "NO SIGNAL · UPDATED \(Format.ago(model.lastSuccess, now: now))" }
        return nil
    }

    // MARK: Airlines

    /// Whether the nearest flight has a route strip (it adds two lines): only a route that fits
    /// where the aircraft is and where it's heading.
    static func showsRoute(_ model: AppModel) -> Bool {
        guard model.settings.infoShowOverhead, let o = model.overhead, let a = model.tracker.aircraft[o.hex] else { return false }
        return o.details?.verifiedRoute(position: a.latest.position, trackDeg: a.latest.trackDeg) != nil
    }

    static func legendRows(_ model: AppModel) -> Int {
        guard model.settings.infoEnabled, model.settings.infoShowAirlines, model.settings.colorMode == .airline else { return 0 }
        let l = model.airlineLegend
        return l.entries.count + (l.otherAirlines > 0 ? 1 : 0) + (l.privateAircraft > 0 ? 1 : 0)
    }

    @ViewBuilder
    private var airlineBlock: some View {
        if Self.legendRows(model) > 0 {
            let legend = model.airlineLegend
            VStack(alignment: hAlign, spacing: 5) {
                Text("AIRLINES IN VIEW")
                    .font(Typeface.caption(9.5))
                    .tracking(2.4)
                    .foregroundStyle(palette.textTertiary.color)
                    .padding(.bottom, 3)
                ForEach(legend.entries, id: \.code) { entry in
                    legendRow(name: model.airlineNames[entry.code] ?? entry.code, count: entry.count,
                              color: model.airlineColor(entry.code, palette: palette) ?? palette.otherAirline, emphasis: true,
                              paint: model.paint(code: entry.code, palette: palette))
                }
                if legend.otherAirlines > 0 {
                    legendRow(name: "Other airlines", count: legend.otherAirlines, color: palette.otherAirline, emphasis: false)
                }
                if legend.privateAircraft > 0 {
                    legendRow(name: "Private & other", count: legend.privateAircraft, color: palette.privateAircraft, emphasis: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: isLeading ? .leading : .trailing)
        }
    }

    private func legendRow(name: String, count: Int, color: RGBA, emphasis: Bool, paint: LiveryPaint? = nil) -> some View {
        HStack(spacing: 10) {
            // Full liveries need a little more size than a solid mark for the tail to read.
            PlaneMark(color: color, outline: palette.land, paint: paint, palette: palette)
                .frame(width: paint == nil ? 16 : 21, height: paint == nil ? 16 : 21)
                .frame(width: 21, height: 16)
            Text(name)
                .font(.system(size: 12.5, weight: emphasis ? .medium : .regular))
                .foregroundStyle((emphasis ? palette.textPrimary : palette.textSecondary).color)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text("\(count)")
                .font(Typeface.mono(11, .medium))
                .foregroundStyle(palette.textSecondary.color)
        }
        .frame(width: 230)
    }

    // MARK: Alerts

    @ViewBuilder
    private var alertBlock: some View {
        if model.center != nil, !model.alerts.isEmpty {
            VStack(alignment: hAlign, spacing: 4) {
                ForEach(model.alerts.prefix(3), id: \.hex) { a in
                    Text(alertLine(a))
                        .font(Typeface.mono(10.5, .semibold))
                        .tracking(1.2)
                        .foregroundStyle(palette.alert.color)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: isLeading ? .leading : .trailing)
        }
    }

    private func alertLine(_ a: AlertFlight) -> String {
        let code = a.squawk.map { "SQUAWK \($0)" } ?? a.alert.title.uppercased()
        let miles = Format.distance(miles: a.distanceNM / Geo.nmPerMile)
        return "\(code)  ·  \(a.name)  ·  \(miles) \(Geo.compassPoint(a.bearingDeg))"
    }

    // MARK: Overhead

    @ViewBuilder
    private var overheadBlock: some View {
        if model.settings.infoShowOverhead, let center = model.center, let o = model.overhead,
           let a = model.tracker.aircraft[o.hex] {
            let r = a.latest
            let position = Motion.deadReckon(r, at: Date().timeIntervalSince1970, maxExtrapolation: 75)
            let miles = Geo.distanceNM(position, center) / Geo.nmPerMile
            let direction = Geo.compassPoint(Geo.bearingDeg(from: center, to: position))
            let color = model.color(for: r, palette: palette)
            VStack(alignment: hAlign, spacing: 5) {
                Text("NEAREST  ·  \(Format.distance(miles: miles)) \(direction)")
                    .font(Typeface.caption(9.5))
                    .tracking(2.4)
                    .foregroundStyle(palette.textTertiary.color)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    if !isLeading { Spacer(minLength: 0) }
                    Text(AircraftRenderer.displayName(r))
                        .font(Typeface.mono(22, .semibold))
                        .tracking(1.5)
                        .foregroundStyle(palette.textPrimary.color)
                    PlaneMark(color: color, outline: palette.land, paint: model.paint(for: r, palette: palette), palette: palette)
                        .frame(width: 24, height: 24)
                        .frame(width: 24, height: 18)
                    if isLeading { Spacer(minLength: 0) }
                }
                if let line = operatorLine(r, o.details) {
                    Text(line)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(palette.textSecondary.color)
                        .lineLimit(1)
                }
                // A stale route (flight numbers get reused) is left out rather than shown wrong.
                if let route = o.details?.verifiedRoute(position: position, trackDeg: r.trackDeg) {
                    RouteStrip(origin: route.origin, destination: route.destination, progress: route.progress,
                               color: color, paint: model.paint(for: r, palette: palette), palette: palette)
                        .frame(width: 330)
                        .padding(.vertical, 5)
                }
                Text(statsLine(r, position: position, details: o.details))
                    .font(Typeface.mono(10.5, .medium))
                    .tracking(1)
                    .foregroundStyle(palette.textSecondary.color)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: isLeading ? .leading : .trailing)
        }
    }

    /// "American Eagle · PSA Airlines" for regional flights, the airline for mainline ones,
    /// the airframe for everything else.
    private func operatorLine(_ r: AircraftReport, _ d: FlightDetails?) -> String? {
        var parts: [String] = []
        if r.isMilitary { parts.append("Military") }
        if let id = Airlines.identity(fromCallsign: r.callsign) {
            // `airlineNames` holds the bare code until its lookup returns; a code alone says nothing here.
            let looked = model.airlineNames[id.operatorCode].flatMap { $0 == id.operatorCode ? nil : $0 }
            let operatorName = d?.airline ?? Airlines.displayName(id.operatorCode) ?? looked
            if let program = id.program {
                parts.append(program)
                if let operatorName { parts.append(operatorName) }
            } else if let name = operatorName ?? Airlines.displayName(id.brandCode) {
                parts.append(name)
            }
        } else if let craft = d?.aircraftDescription, !craft.isEmpty {
            parts.append(craft)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    private func statsLine(_ r: AircraftReport, position: Coordinate, details: FlightDetails?) -> String {
        var parts: [String] = []
        if let t = r.typeCode { parts.append(t) }
        let trend = Format.trend(r.verticalRateFpm)
        parts.append((trend.isEmpty ? "" : trend + " ") + Format.altitude(r.altitudeFt, onGround: r.onGround))
        if let gs = r.groundSpeedKt { parts.append("\(Int(gs.rounded())) KT") }
        if let progress = details?.verifiedRoute(position: position, trackDeg: r.trackDeg)?.progress, progress.remainingNM > 5 {
            parts.append("\(Format.distance(miles: progress.remainingNM / Geo.nmPerMile)) TO GO")
        }
        return parts.joined(separator: "  ·  ")
    }
}

/// Origin and destination with their cities, joined by a line that fills in as the flight
/// progresses, the way a departures board or flight tracker shows it.
struct RouteStrip: View {
    let origin: RouteAirport
    let destination: RouteAirport
    /// From `FlightDetails.verifiedRoute`, so the strip only ever shows a checked route.
    let progress: RouteProgress
    let color: RGBA
    var paint: LiveryPaint?
    let palette: Palette

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 10) {
                code(origin.code)
                track.frame(height: 16)
                code(destination.code)
            }
            HStack(alignment: .firstTextBaseline) {
                city(origin)
                Spacer(minLength: 16)
                city(destination).multilineTextAlignment(.trailing)
            }
        }
    }

    private func code(_ c: String) -> some View {
        Text(c)
            .font(Typeface.mono(15, .semibold))
            .tracking(1.2)
            .foregroundStyle(palette.textPrimary.color)
            .fixedSize()
    }

    private func city(_ a: RouteAirport) -> some View {
        Text(a.city ?? a.name ?? "")
            .font(.system(size: 11.5))
            .foregroundStyle(palette.textSecondary.color)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 160, alignment: a == origin ? .leading : .trailing)
    }

    private var track: some View {
        Canvas { ctx, size in
            let y = size.height / 2
            let split = size.width * CGFloat(progress.fraction)
            var ahead = Path()
            ahead.move(to: CGPoint(x: split, y: y))
            ahead.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(ahead, with: .color(palette.textTertiary.color),
                       style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 3]))
            var flown = Path()
            flown.move(to: CGPoint(x: 0, y: y))
            flown.addLine(to: CGPoint(x: split, y: y))
            ctx.stroke(flown, with: .color(color.with(alpha: 0.9).color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            // The plane rides the line, nose toward the destination.
            let x = min(max(split, 8), size.width - 8)
            PlaneMark.draw(in: &ctx, center: CGPoint(x: x, y: y), size: 15, rotation: .pi / 2,
                           color: color, outline: palette.land, paint: paint, palette: palette)
        }
    }
}

/// A small plane icon for legends and the info corner, matching the map's glyph.
struct PlaneMark: View {
    let color: RGBA
    let outline: RGBA
    var paint: LiveryPaint?
    var palette: Palette?

    var body: some View {
        Canvas { ctx, size in
            Self.draw(in: &ctx, center: CGPoint(x: size.width / 2, y: size.height / 2),
                      size: min(size.width, size.height) * 0.92, rotation: .pi / 4,
                      color: color, outline: outline, paint: paint, palette: palette)
        }
    }

    /// A jet icon `size` points long, in full livery when `paint` is given.
    static func draw(in ctx: inout GraphicsContext, center: CGPoint, size: CGFloat, rotation: CGFloat,
                     color: RGBA, outline: RGBA, paint: LiveryPaint?, palette: Palette?) {
        let parts = Silhouettes.jetParts
        let box = parts.outline.boundingBoxOfPath
        let s = size / max(box.width, box.height)
        let t = CGAffineTransform(scaleX: s, y: s)
            .concatenating(CGAffineTransform(rotationAngle: rotation))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
        if let paint {
            LiveryGlyph.draw(parts, transform: t, paint: paint, outline: palette?.liveryOutline ?? outline,
                             outlineWidth: 1.3, alpha: 1, in: &ctx)
            return
        }
        let shape = Path(parts.outline).applying(t)
        ctx.stroke(shape, with: .color(outline.color), lineWidth: 1.2)
        ctx.fill(shape, with: .color(color.color))
    }
}
