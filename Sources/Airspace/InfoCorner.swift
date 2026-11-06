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
    static func footprint(corner: Corner, size: CGSize, insets: EdgeInsets, legendRows: Int = 0) -> CGRect {
        let h: CGFloat = 230 + (legendRows > 0 ? CGFloat(legendRows) * 21 + 44 : 0)
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
                    overheadBlock
                    airlineBlock
                } else {
                    airlineBlock
                    overheadBlock
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
            Text(metaLine(now: now))
                .font(Typeface.mono(11, .medium))
                .tracking(1.2)
                .foregroundStyle(palette.textSecondary.color)
            if let status = statusLine(now: now) {
                Text(status)
                    .font(Typeface.mono(10.5, .semibold))
                    .tracking(1.2)
                    .foregroundStyle(palette.altitudeColors[1].color)
            }
        }
    }

    private func metaLine(now: Date) -> String {
        var parts: [String] = []
        if model.settings.infoShowCoordinates, let c = model.center { parts.append(Format.coordinate(c)) }
        if model.settings.infoShowClock { parts.append(now.formatted(date: .omitted, time: .shortened).uppercased()) }
        if model.settings.infoShowCount, model.center != nil {
            parts.append("\(model.aircraftInView) AIRCRAFT")
        }
        return parts.joined(separator: "  ·  ")
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
                              color: palette.airlineColor(entry.slot), emphasis: true)
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

    private func legendRow(name: String, count: Int, color: RGBA, emphasis: Bool) -> some View {
        HStack(spacing: 10) {
            PlaneMark(color: color, outline: palette.land)
                .frame(width: 16, height: 16)
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

    // MARK: Overhead

    @ViewBuilder
    private var overheadBlock: some View {
        if model.settings.infoShowOverhead, let center = model.center, let o = model.overhead,
           let a = model.tracker.aircraft[o.hex] {
            let r = a.latest
            let miles = Geo.distanceNM(r.position, center) / Geo.nmPerMile
            VStack(alignment: hAlign, spacing: 5) {
                Text("NEAREST")
                    .font(Typeface.caption(9.5))
                    .tracking(2.4)
                    .foregroundStyle(palette.textTertiary.color)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    if !isLeading { Spacer(minLength: 0) }
                    Text(AircraftRenderer.displayName(r))
                        .font(Typeface.mono(22, .semibold))
                        .tracking(1.5)
                        .foregroundStyle(palette.textPrimary.color)
                    PlaneMark(color: model.color(for: r, palette: palette), outline: palette.land)
                        .frame(width: 18, height: 18)
                    if isLeading { Spacer(minLength: 0) }
                }
                if let line = routeLine(o.details) {
                    Text(line)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(palette.textSecondary.color)
                        .lineLimit(1)
                }
                Text(statsLine(r, miles: miles, details: o.details))
                    .font(Typeface.mono(10.5, .medium))
                    .tracking(1)
                    .foregroundStyle(palette.textSecondary.color)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: isLeading ? .leading : .trailing)
        }
    }

    private func routeLine(_ d: FlightDetails?) -> String? {
        guard let d else { return nil }
        var parts: [String] = []
        if let o = d.origin, let dest = d.destination { parts.append("\(o) → \(dest)") }
        if let airline = d.airline { parts.append(airline) } else if let craft = d.aircraftDescription { parts.append(craft) }
        return parts.isEmpty ? nil : parts.joined(separator: "   ")
    }

    private func statsLine(_ r: AircraftReport, miles: Double, details: FlightDetails?) -> String {
        var parts: [String] = []
        if let t = r.typeCode { parts.append(t) }
        parts.append(Format.altitude(r.altitudeFt, onGround: r.onGround))
        if let gs = r.groundSpeedKt { parts.append("\(Int(gs.rounded())) KT") }
        parts.append(Format.distance(miles: miles))
        return parts.joined(separator: "  ·  ")
    }
}

/// A small plane icon for legends and the info corner, matching the map's glyph.
struct PlaneMark: View {
    let color: RGBA
    let outline: RGBA

    var body: some View {
        Canvas { ctx, size in
            let path = Silhouettes.jet
            let box = path.boundingBoxOfPath
            let s = min(size.width, size.height) / max(box.width, box.height) * 0.92
            let t = CGAffineTransform(scaleX: s, y: s)
                .concatenating(CGAffineTransform(rotationAngle: .pi / 4))
                .concatenating(CGAffineTransform(translationX: size.width / 2, y: size.height / 2))
            let shape = Path(path).applying(t)
            ctx.stroke(shape, with: .color(outline.color), lineWidth: 1.2)
            ctx.fill(shape, with: .color(color.color))
        }
    }
}
