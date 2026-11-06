# Airspace

A live map of the sky above you, as your macOS wallpaper.

Every aircraft within range is drawn as a small point of light on a calm map, moving
smoothly between updates and colored by altitude, in the spirit of the Design Rules Co.
Metroboard. It lives behind your desktop icons on every Space and display, never takes
clicks, and idles when it's covered, locked, or on battery.

## Features

- **Three map styles:**
  - **Schematic**: land, water, cities, roads and runways drawn from bundled public-domain data; works offline.
  - **Apple Map**: muted and desaturated MapKit.
  - **Pure field**: dots only.
- **Light, dark or dynamic appearance:**
  - **Aluminum** (light) and **Night** (dark).
  - **Dynamic** follows either the macOS appearance or the sun at your location, fading through civil twilight.
- **Location:** system location, a zip code or city, or typed coordinates (`41.97, -87.90`, `41°58'N 87°54'W`, …).
- **Zoom:** 5–150 mile radius, with range rings and a compass.
- **Aircraft:** point-of-light, arrow or silhouette glyphs, altitude colors or monochrome,
  fading trails (1, 3 or 10 minutes), a pulse on each update, and callsign or callsign +
  altitude labels that are placed so they don't collide.
- **Info corner:** place name, time, number of aircraft in view, and the nearest flight
  with its type, altitude, speed, route and airline.
- **Power-aware:**
  - Slower updates on battery or in Low Power Mode.
  - Stops drawing when windows cover the desktop.
  - Stops entirely when the screen is locked or asleep.

## Build & run

You only need the Swift toolchain. Xcode isn't required; the Command Line Tools are enough.

```sh
make run         # build, bundle into build/Airspace.app (ad-hoc signed), launch
make test        # unit tests (Swift Testing)
make snapshots   # render every style/appearance with live traffic into build/snapshots
```

On first launch a welcome window asks where you are. After that, everything lives in the
✈︎ menu-bar item and **Settings…**.

### Distributing

```sh
xcrun notarytool store-credentials airspace   # once
make release SIGN_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=airspace
```

This produces a signed, notarized and stapled `build/Airspace.dmg`. The app is sandboxed and
asks only for network access and location.

## How it works

macOS has no API for live wallpapers. Airspace draws into one borderless, click-through
window per display at the desktop window level: above the system wallpaper, below your
icons. The lock screen and login window still show the system wallpaper.

```
Sources/AirspaceCore   UI-free logic: feed decoding, tracker + motion smoothing, Web Mercator
                       projection, power policy, coordinate parsing, solar position, label
                       layout, settings, palettes, base-map geometry
Sources/Airspace       AppKit/SwiftUI app: desktop windows, layers, menu bar, settings
Tools/                 geodata preprocessor (Natural Earth + OurAirports → Resources/geodata.bin)
```

- **Performance:** the static map, the animated traffic and the info corner are hosted in
  separate layers, so animating aircraft never repaints the map. Label text is cached as
  bitmaps. The default is 20 fps; planes move a few points per second at normal zoom, so
  more frames add cost without smoothness.
- **Motion:** each aircraft is projected forward from its last fix along its track. When a
  new fix arrives, the plane eases from where it was drawn to its new course over 1.2 s, so
  it never jumps.
- **Diagnostics:** every 30 s the app logs its render mode, frame count and source:
  `log stream --level info --predicate 'subsystem == "com.airspace.wallpaper"'`.

## Data

- Live positions: [adsb.lol](https://adsb.lol), with [adsb.fi](https://adsb.fi) as automatic
  fallback. Both are free, need no key, and are fed by community ADS-B receivers.
  Coverage is best near populated areas.
- Routes and airframes: [adsbdb.com](https://www.adsbdb.com), looked up only for the nearest flight.
- Map: [Natural Earth](https://www.naturalearthdata.com) 10m and [OurAirports](https://ourairports.com),
  both public domain. Rebuild the map data with `make geodata`.

Only the map center (and the nearest flight's callsign) is sent to these services.
