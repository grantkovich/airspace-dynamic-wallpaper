import Foundation

public enum GeoLayer: UInt8, CaseIterable, Sendable { case land = 0, lakes, rivers, urban, roads, states }

/// A compact lat/lon pair (Float precision ≈ 1 m, plenty at wallpaper scale).
public typealias GeoPoint = SIMD2<Float>   // (lat, lon)

public struct GeoFeature: Sendable {
    public var rank: UInt8
    public var bounds: GeoBounds
    public var rings: [[GeoPoint]]
}

public struct Airport: Sendable {
    public var code: String
    /// 0 = large, 1 = medium.
    public var rank: UInt8
    public var position: Coordinate
    public var runways: [(Coordinate, Coordinate)]
}

public enum GeoDataError: Error { case badMagic, unsupportedVersion(UInt8), decompressionFailed, truncated }

/// Bundled base-map geometry (Natural Earth 10m + OurAirports). See Tools/build_geodata.py.
public final class GeoData: Sendable {
    public let layers: [GeoLayer: [GeoFeature]]
    public let airports: [Airport]

    init(layers: [GeoLayer: [GeoFeature]], airports: [Airport]) {
        self.layers = layers
        self.airports = airports
    }

    public static func load(from url: URL) throws -> GeoData {
        try decode(try Data(contentsOf: url, options: .mappedIfSafe))
    }

    public func features(_ layer: GeoLayer, in bounds: GeoBounds) -> [GeoFeature] {
        (layers[layer] ?? []).filter { $0.bounds.intersects(bounds) }
    }

    public func airports(in bounds: GeoBounds) -> [Airport] {
        airports.filter { bounds.contains($0.position) }
    }

    public static func decode(_ file: Data) throws -> GeoData {
        guard file.count > 5, file.prefix(4) == Data("ASGD".utf8) else { throw GeoDataError.badMagic }
        let version = file[file.startIndex + 4]
        guard version == 1 else { throw GeoDataError.unsupportedVersion(version) }
        let compressed = file.dropFirst(5)
        guard let raw = try? (Data(compressed) as NSData).decompressed(using: .zlib) as Data else {
            throw GeoDataError.decompressionFailed
        }
        return try raw.withUnsafeBytes { buf in
            var r = Reader(buf: buf)
            var layers: [GeoLayer: [GeoFeature]] = [:]
            let layerCount = try r.u8()
            for _ in 0..<layerCount {
                let id = try r.u8()
                let count = Int(try r.u32())
                var features: [GeoFeature] = []
                features.reserveCapacity(count)
                for _ in 0..<count {
                    let rank = try r.u8()
                    let ringCount = Int(try r.u16())
                    var rings: [[GeoPoint]] = []
                    rings.reserveCapacity(ringCount)
                    var minLat = Float.infinity, maxLat = -Float.infinity, minLon = Float.infinity, maxLon = -Float.infinity
                    for _ in 0..<ringCount {
                        let n = Int(try r.varint())
                        var ring = [GeoPoint]()
                        ring.reserveCapacity(n)
                        var lat: Int64 = 0, lon: Int64 = 0
                        for _ in 0..<n {
                            lat += try r.zigzag()
                            lon += try r.zigzag()
                            let p = GeoPoint(Float(lat) / 100_000, Float(lon) / 100_000)
                            minLat = min(minLat, p.x); maxLat = max(maxLat, p.x)
                            minLon = min(minLon, p.y); maxLon = max(maxLon, p.y)
                            ring.append(p)
                        }
                        rings.append(ring)
                    }
                    features.append(GeoFeature(rank: rank, bounds: GeoBounds(minLat: Double(minLat), maxLat: Double(maxLat),
                                                                              minLon: Double(minLon), maxLon: Double(maxLon)),
                                               rings: rings))
                }
                if let layer = GeoLayer(rawValue: id) { layers[layer] = features }
            }
            let airportCount = Int(try r.u32())
            var airports: [Airport] = []
            airports.reserveCapacity(airportCount)
            for _ in 0..<airportCount {
                let rank = try r.u8()
                let len = Int(try r.u8())
                let code = String(decoding: try r.bytes(len), as: UTF8.self)
                let pos = Coordinate(latitude: Double(try r.i32()) / 100_000, longitude: Double(try r.i32()) / 100_000)
                let rwCount = Int(try r.u8())
                var runways: [(Coordinate, Coordinate)] = []
                for _ in 0..<rwCount {
                    let a = Coordinate(latitude: Double(try r.i32()) / 100_000, longitude: Double(try r.i32()) / 100_000)
                    let b = Coordinate(latitude: Double(try r.i32()) / 100_000, longitude: Double(try r.i32()) / 100_000)
                    runways.append((a, b))
                }
                airports.append(Airport(code: code, rank: rank, position: pos, runways: runways))
            }
            return GeoData(layers: layers, airports: airports)
        }
    }
}

private struct Reader {
    let buf: UnsafeRawBufferPointer
    var i = 0

    mutating func u8() throws -> UInt8 {
        guard i < buf.count else { throw GeoDataError.truncated }
        defer { i += 1 }
        return buf[i]
    }

    mutating func bytes(_ n: Int) throws -> UnsafeRawBufferPointer {
        guard i + n <= buf.count else { throw GeoDataError.truncated }
        defer { i += n }
        return UnsafeRawBufferPointer(rebasing: buf[i..<(i + n)])
    }

    mutating func u16() throws -> UInt16 { try bytes(2).loadUnaligned(as: UInt16.self).littleEndian }
    mutating func u32() throws -> UInt32 { try bytes(4).loadUnaligned(as: UInt32.self).littleEndian }
    mutating func i32() throws -> Int32 { try bytes(4).loadUnaligned(as: Int32.self).littleEndian }

    mutating func varint() throws -> UInt64 {
        var result: UInt64 = 0, shift: UInt64 = 0
        while true {
            let b = try u8()
            result |= UInt64(b & 0x7F) << shift
            if b & 0x80 == 0 { return result }
            shift += 7
            guard shift < 64 else { throw GeoDataError.truncated }
        }
    }

    mutating func zigzag() throws -> Int64 {
        let n = try varint()
        return Int64(bitPattern: (n >> 1) ^ (0 &- (n & 1)))
    }
}
