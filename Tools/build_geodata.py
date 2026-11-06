#!/usr/bin/env python3
"""Builds Resources/geodata.bin from Natural Earth GeoJSON and OurAirports CSV.

Usage: python3 -I Tools/build_geodata.py <download-dir> <output.bin>

The download dir must contain (fetch with Tools/fetch_geodata.sh):
  ne_10m_land, ne_10m_lakes, ne_10m_lakes_north_america, ne_10m_lakes_europe,
  ne_10m_rivers_lake_centerlines, ne_10m_rivers_north_america, ne_10m_rivers_europe,
  ne_10m_urban_areas, ne_10m_roads, ne_10m_admin_1_states_provinces_lines (.geojson)
  runways.csv, airports.csv

Format (all little-endian):
  "ASGD" u8 version=1, then a raw-deflate stream of:
    u8 layerCount
    per layer: u8 layerId, u32 featureCount, features
      feature: u8 rank, u16 ringCount, rings
        ring: varint pointCount, then zigzag-varint deltas of (lat, lon) in 1e-5 degrees
    u32 airportCount
    per airport: u8 rank, u8 codeLen, code bytes, i32 lat, i32 lon (1e-5 deg),
                 u8 runwayCount, runways of 4 x i32 (leLat, leLon, heLat, heLon)

Data sources are public domain (Natural Earth; OurAirports).
"""
import csv
import json
import os
import struct
import sys
import zlib

Q = 100000  # 1e-5 degree quantization (~1.1 m)

LAYER_LAND, LAYER_LAKES, LAYER_RIVERS, LAYER_URBAN, LAYER_ROADS, LAYER_STATES = range(6)


def varint(n, out):
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return


def zigzag(n):
    return (n << 1) ^ (n >> 63)


def dedupe(points):
    """Quantize and drop consecutive duplicates."""
    out = []
    last = None
    for lon, lat in points:
        p = (round(lat * Q), round(lon * Q))
        if p != last:
            out.append(p)
            last = p
    return out


def rings_of(geom):
    t = geom["type"]
    c = geom["coordinates"]
    if t == "LineString":
        return [c]
    if t == "MultiLineString":
        return c
    if t == "Polygon":
        return c
    if t == "MultiPolygon":
        return [ring for poly in c for ring in poly]
    return []


def encode_layer(layer_id, features, out):
    """features: list of (rank, [ring point lists])"""
    body = bytearray()
    count = 0
    for rank, rings in features:
        qrings = [dedupe(r) for r in rings]
        qrings = [r for r in qrings if len(r) >= 2]
        if not qrings:
            continue
        count += 1
        body += struct.pack("<BH", max(0, min(255, rank)), len(qrings))
        for r in qrings:
            varint(len(r), body)
            plat, plon = 0, 0
            for lat, lon in r:
                varint(zigzag(lat - plat), body)
                varint(zigzag(lon - plon), body)
                plat, plon = lat, lon
    out += struct.pack("<BI", layer_id, count)
    out += body
    return count


def load(dirpath, name):
    with open(os.path.join(dirpath, name + ".geojson"), encoding="utf-8") as f:
        return json.load(f)["features"]


def rank_of(props, default=0):
    for key in ("scalerank", "min_zoom"):
        v = props.get(key)
        if isinstance(v, (int, float)):
            return int(v)
    return default


def geo_layer(dirpath, names, keep=lambda p: True):
    feats = []
    for name in names:
        for f in load(dirpath, name):
            if f.get("geometry") is None or not keep(f["properties"]):
                continue
            geom, rank = f["geometry"], rank_of(f["properties"])
            # Split multi-geometries so each part gets its own bounding box at runtime.
            if geom["type"] == "MultiPolygon":
                feats.extend((rank, poly) for poly in geom["coordinates"])
            elif geom["type"] == "MultiLineString":
                feats.extend((rank, [line]) for line in geom["coordinates"])
            else:
                feats.append((rank, rings_of(geom)))
    return feats


ROAD_TYPES = {"Major Highway", "Beltway", "Secondary Highway", "Road"}


def airports(dirpath):
    by_id = {}
    with open(os.path.join(dirpath, "airports.csv"), encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["type"] not in ("large_airport", "medium_airport"):
                continue
            code = row["iata_code"] or row["icao_code"] or row["ident"]
            try:
                lat, lon = float(row["latitude_deg"]), float(row["longitude_deg"])
            except ValueError:
                continue
            rank = 0 if row["type"] == "large_airport" else 1
            by_id[row["id"]] = [rank, code, lat, lon, []]
    with open(os.path.join(dirpath, "runways.csv"), encoding="utf-8") as f:
        for row in csv.DictReader(f):
            ap = by_id.get(row["airport_ref"])
            if ap is None or row["closed"] == "1":
                continue
            try:
                vals = [float(row[k]) for k in ("le_latitude_deg", "le_longitude_deg",
                                                 "he_latitude_deg", "he_longitude_deg")]
            except ValueError:
                continue
            ap[4].append(vals)
    return [a for a in by_id.values() if a[4]]


def main():
    src, dst = sys.argv[1], sys.argv[2]
    payload = bytearray()
    layers = [
        (LAYER_LAND, geo_layer(src, ["ne_10m_land"])),
        (LAYER_LAKES, geo_layer(src, ["ne_10m_lakes", "ne_10m_lakes_north_america",
                                      "ne_10m_lakes_europe"])),
        (LAYER_RIVERS, geo_layer(src, ["ne_10m_rivers_lake_centerlines",
                                       "ne_10m_rivers_north_america", "ne_10m_rivers_europe"])),
        (LAYER_URBAN, geo_layer(src, ["ne_10m_urban_areas"])),
        (LAYER_ROADS, geo_layer(src, ["ne_10m_roads"],
                                keep=lambda p: p.get("type") in ROAD_TYPES)),
        (LAYER_STATES, geo_layer(src, ["ne_10m_admin_1_states_provinces_lines"])),
    ]
    payload += struct.pack("<B", len(layers))
    for layer_id, feats in layers:
        n = encode_layer(layer_id, feats, payload)
        print(f"layer {layer_id}: {n} features", file=sys.stderr)

    aps = airports(src)
    payload += struct.pack("<I", len(aps))
    for rank, code, lat, lon, rws in aps:
        cb = code.encode("utf-8")[:255]
        payload += struct.pack("<BB", rank, len(cb)) + cb
        payload += struct.pack("<ii", round(lat * Q), round(lon * Q))
        rws = rws[:255]
        payload += struct.pack("<B", len(rws))
        for v in rws:
            payload += struct.pack("<iiii", *(round(x * Q) for x in v))
    print(f"airports: {len(aps)}", file=sys.stderr)

    comp = zlib.compressobj(9, zlib.DEFLATED, -15)
    data = comp.compress(bytes(payload)) + comp.flush()
    with open(dst, "wb") as f:
        f.write(b"ASGD" + bytes([1]) + data)
    print(f"raw {len(payload)} bytes -> {len(data)} compressed", file=sys.stderr)


if __name__ == "__main__":
    main()
