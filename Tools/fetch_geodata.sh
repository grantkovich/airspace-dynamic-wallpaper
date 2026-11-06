#!/bin/sh
# Downloads the public-domain source data for Resources/geodata.bin into $1.
set -eu
DIR="${1:?usage: fetch_geodata.sh <download-dir>}"
mkdir -p "$DIR"
NE=https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson
for f in ne_10m_land ne_10m_lakes ne_10m_lakes_north_america ne_10m_lakes_europe \
         ne_10m_rivers_lake_centerlines ne_10m_rivers_north_america ne_10m_rivers_europe \
         ne_10m_urban_areas ne_10m_roads ne_10m_admin_1_states_provinces_lines; do
  curl -fsSL -o "$DIR/$f.geojson" "$NE/$f.geojson"
done
OA=https://davidmegginson.github.io/ourairports-data
curl -fsSL -o "$DIR/runways.csv" "$OA/runways.csv"
curl -fsSL -o "$DIR/airports.csv" "$OA/airports.csv"
