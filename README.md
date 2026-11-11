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
- **Aircraft:** plane icons by airframe (narrow-body, wide-body, four-engine, rear-engine
  jets, turboprops, light aircraft, helicopters), or points of light, or arrows.
- **Color by airline** (default): plane icons are painted in their airline's livery, part
  by part: body, tail and tailplanes, and engines (a white United with a blue tail and
  engines, a silver American with its flag tail, a blue-and-yellow Southwest). Trails, dots
  and arrows use the airline's signature color (United blue, Spirit yellow, FedEx purple…),
  shifted lighter or darker so it reads on the Night and Aluminum maps. When two airlines in view share a color, one with a second
  livery color switches to it (beside United blue, American goes red). The key in the info
  corner lists the six busiest. Turn liveries off for four maximally distinct colors instead.
  Regional flights count as the airline they fly for: PSA, Envoy and Piedmont as American,
  Endeavor as Delta, GoJet/Mesa/CommuteAir as United, and SkyWest and Republic by the
  partner whose flight-number block they're flying. Alternatively color by altitude (trails
  show the altitude flown along the way) or use one color for everything.
- **Labels and trails:** labels show callsign, type and/or altitude and are placed so they
  don't collide. Trails fade over 1, 3 or 10 minutes, with a pulse on each update.
- **Info corner:** place name, time, aircraft in view and seen today, the airline key, and the
  nearest flight: who flies it ("American Eagle · PSA"), both airports with their cities, a
  progress line from origin to destination, distance and direction from you, climbing or
  descending, and miles to go. Its remaining route is drawn on the map as a dashed great circle.
- **Emergencies:** aircraft squawking 7700/7600/7500 (or reporting emergency status) get a
  pulsing red ring and label, and are listed in the info corner even when labels are off.
- **Menu bar match:** macOS tints the menu bar, Mission Control and Show Desktop from the
  *system* wallpaper, so Airspace sets the system wallpaper to a still of the map for each
  display. Your own wallpaper is restored when Airspace quits or the option is turned off.
- **Power-aware:**
  - Slower updates on battery or in Low Power Mode.
  - Stops drawing when windows cover the desktop.
  - Stops entirely when the screen is locked or asleep.

## Build & run

You only need the Swift toolchain. Xcode isn't required; the Command Line Tools are enough.

```sh
make run         # build, bundle into build/Airspace.app (ad-hoc signed), launch
make install     # build, replace /Applications/Airspace.app, relaunch it
make test        # unit tests (Swift Testing)
make snapshots   # render every style/appearance with live traffic into build/snapshots
swift run -c release Airspace --render-settings build/settings   # Settings window, every section
```

On first launch a welcome window asks where you are. After that, everything lives in the
✈︎ menu-bar item and **Settings…**.

### Distributing

Airspace is free and ships without the paid Apple Developer Program. `make release` builds a
universal app (Apple Silicon and Intel) signed with a self-signed certificate, and writes a
zip, a DMG, `SHA256SUMS` and a one-line Terminal installer (`install.sh`). The steps and the
certificate are in [RELEASING.md](RELEASING.md). The app is sandboxed and asks only for
network access and location.

Because it isn't notarized, a DMG downloaded in a browser needs one approval in System
Settings › Privacy & Security › Open Anyway. The installer downloads with curl, so it doesn't:

```sh
curl -fsSL https://downloads.grantkovich.com/airspace/install.sh | sh
```

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
  bitmaps, projected trail points are cached until a new fix arrives, and label collision
  checks use a spatial grid, so wide zoom with hundreds of aircraft stays cheap
  (`swift run -c release Airspace --snapshots build/snapshots --benchmark`). The default is 20 fps; planes move a few points per second at normal zoom, so
  more frames add cost without smoothness.
- **Motion:** each aircraft is projected forward from its last fix along its track. When a
  new fix arrives, the plane eases from where it was drawn to its new course over 1.2 s, so
  it never jumps.
- **Diagnostics:** every 30 s the app logs its render mode, frame count and source:
  `log stream --level info --predicate 'subsystem == "com.grantkovich.airspace"'`.

## Data

- Live positions: [adsb.lol](https://adsb.lol), with [adsb.fi](https://adsb.fi) as automatic
  fallback. Both are free, need no key, and are fed by community ADS-B receivers.
  Coverage is best near populated areas.
- Routes (with airport cities and positions), airframes and airline names:
  [adsbdb.com](https://www.adsbdb.com), looked up only for the nearest flight and for
  airlines that get a color. A route that doesn't fit the aircraft's position (stale flight
  numbers are common) is hidden rather than shown wrong.
- Map: [Natural Earth](https://www.naturalearthdata.com) 10m and [OurAirports](https://ourairports.com),
  both public domain. Rebuild the map data with `make geodata`.

Only the map center (and the nearest flight's callsign) is sent to these services.
