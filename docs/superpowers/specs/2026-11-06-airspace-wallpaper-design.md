# Airspace: live flight-traffic wallpaper for macOS

Date: 2026-11-06
Status: approved in conversation, build authorized

## Intent

A macOS wallpaper that shows live air traffic over a chosen location. Planes are drawn as
points of light on a calm schematic map, in the spirit of the Design Rules Co. Metroboard
(every vehicle is a light on a quiet live map, with a few well-chosen settings). It should
feel like an object, not a flight-tracker app. It is meant to be shared with other people,
so first-run setup and a signable, notarizable build matter.

**Success:** set it once, it lives behind the desktop icons on every Space and display,
never intercepts clicks, uses little power, updates within seconds, and looks good in
light, dark and dynamic modes.

## What the user asked for

- Live traffic over the current location
- Light / dark / dynamic appearance
- Optional callsign labels
- Adjustable zoom
- Location from zip code, typed coordinates, or system location
- Three selectable map styles: Schematic, Apple Map (muted), Pure field
- Extras: altitude-colored trails, info corner, smooth motion, power-aware updates

## Architecture

A menu-bar-only app (`LSUIElement`) called **Airspace**, built as a Swift package.

```
Package.swift
  AirspaceCore  (library, no UI: models, decoding, tracker, motion, projection,
                 power policy, coordinate parsing, solar math, geodata, label layout)
  Airspace      (executable: AppKit/SwiftUI app, windows, views, settings, menu bar)
  AirspaceCoreTests (Swift Testing)
Makefile        build / test / app bundle / run / release (sign, notarize, dmg)
Tools/          geodata preprocessor (Python, stdlib only)
Resources/      Info.plist, entitlements, geodata.bin, icon
```

### Changes from the conversational design (found during setup)

- **No Xcode on the build machine** (only the Command Line Tools), so XcodeGen and
  xcodebuild aren't available. We use SwiftPM plus a Makefile that assembles the `.app`
  bundle and signs it. Local builds are ad-hoc signed. `make release` signs with Developer
  ID and notarizes when `DEVELOPER_ID` and `NOTARY_PROFILE` are set.
- **airplanes.live now requires prior approval** by email, so the fallback feed is
  **adsb.fi open data** (same readsb format, no key).
- **adsb.lol's routeset endpoint returns nothing**, so routes come from **adsbdb.com**
  (`/v0/callsign/{cs}`, free, no key).

### Changes made during the build

- **Occlusion:** `NSWindow.occlusionState` reports desktop-level windows as hidden even
  when they're visible, because Finder's icon layer sits above them. The app instead
  checks every 3 s whether a normal app window covers each screen, using
  `CGWindowListCopyWindowInfo` bounds, which need no screen-recording permission.
- **Layering:** the base map, traffic and info corner live in three separate
  `NSHostingView`s. In a single SwiftUI tree, animating aircraft repainted the base map
  every frame (about 40% CPU on a 6K display).
- **Rings:** range rings are drawn inside the base-map canvas, except over Apple Map,
  saving a full-screen backing surface.
- **Labels:** labels are pre-rendered bitmaps (`LabelImageCache`). An offscreen benchmark
  (`--benchmark`) went from 4.1 to 1.8 ms per frame.
- **Frame rate:** the default is 20 fps (15/20/30/60 selectable).
- **Apple Map:** desaturated to 25% saturation. The info corner gets a soft backdrop on this
  style because MapKit draws its own labels.

### Components

| Unit | Purpose |
|---|---|
| `WallpaperController` | One borderless `NSWindow` per screen at `kCGDesktopWindowLevel`, `ignoresMouseEvents`, `.canJoinAllSpaces/.stationary/.ignoresCycle`. Rebuilds on screen-parameter changes. "Main display only" option. |
| `AirspaceView` | Layer stack: base map → aircraft `Canvas` → info corner. Driven by `TimelineView(.animation(minimumInterval:))` at the power policy's frame rate. |
| `MenuBarExtra` | Pause, appearance, map style, labels, zoom slider, Settings…, Quit. |
| Settings window | Tabs: Location, Map, Aircraft, Appearance, Info, Performance. |
| Welcome window | First run: use my location, or zip / city / coordinates; live preview. |
| `AppModel` | `@Observable` main-actor store: settings (persisted to `UserDefaults`) and live state. |

### Data

- `FlightSource` protocol: `aircraft(near:radiusNM:) async throws -> [AircraftReport]`.
- `ReadsbSource` covers both feeds, configured per endpoint:
  - adsb.lol `https://api.adsb.lol/v2/point/{lat}/{lon}/{nm}` (key `ac`)
  - adsb.fi `https://opendata.adsb.fi/api/v2/lat/{lat}/lon/{lon}/dist/{nm}` (key `aircraft`)
- `FallbackSource`: moves to the next source after 2 consecutive failures, retries the
  primary after 5 minutes.
- The radius is derived from the zoom: half the screen diagonal in nm × 1.15, clamped to
  1…250.
- Poll every 5 s by default. Exponential backoff on failure, capped at 60 s.
- `RouteService`: adsbdb lookup for the info corner's flight only, cached per callsign,
  including misses.

### Tracking & motion

- `AircraftTracker` is keyed by ICAO hex and keeps fixes newer than the trail window
  (default 3 min).
- An aircraft is "stale" after 60 s unseen and fades out over 10 s, then is removed.
- Ground traffic is hidden by default. Optional minimum-altitude filter.
- Dead reckoning: position = last fix + gs × track × (now − fix time), capped at 30 s of
  extrapolation.
- When a new fix arrives, the plane eases from its previously predicted position to the
  new one over 1.2 s, so nothing visibly jumps.

### Projection

Web Mercator centered on the location. The scale comes from the zoom radius in miles,
measured to the shorter screen half-axis. The Apple Map layer gets the identical visible
`MKMapRect`, so streets and planes line up.

### Power

`PowerPolicy` is a pure function of inputs (on battery, low power mode, all windows
occluded, screen locked, displays asleep, user paused) → mode:

| Mode | Poll | FPS |
|---|---|---|
| normal | user setting (default 5 s) | user cap (default 30) |
| battery (if battery saver is on) | max(15 s, setting) | 15 |
| occluded | 60 s | 0 (no drawing) |
| locked / asleep / paused | none | 0 |

### Errors

- Stale data (no successful fetch for 3 poll intervals and at least 30 s): planes dim,
  and the info corner shows "NO SIGNAL · UPDATED 2 MIN AGO".
- Location denied or unavailable: fall back to manual entry and say so in Settings.
- Geocoding: coordinates parsed locally (decimal or DMS); zip codes and city names via
  `CLGeocoder`.

## Visual system

- **Night** (dark): field #0E0F11, faint dot grid, land/water as tonal steps, hairlines
  in warm gray.
- **Aluminum** (light): field #ECEAE5, graphite hairlines, inked aircraft.
- **Dynamic**: follow the system appearance, or the sun at the location (local NOAA
  solar calculation), blending the palettes across ±20 min around sunrise and sunset
  (via civil twilight).
- **Aircraft glyph**: light point with a glow and heading tick (default), arrow, or
  silhouette by class (jet, prop, heli, light aircraft) from readsb `category` / `t`.
- **Color**: altitude ramp (amber < 5k ft → coral → cyan/blue at cruise), or monochrome.
- **Trails** fade along their length. Optional pulse on each fresh update. Brightness
  slider.
- **Labels**: off / callsign / callsign + altitude, in tracked uppercase SF Mono. Greedy
  placement among 4 candidate positions; when there's no room, labels for higher and
  farther aircraft drop first.
- **Schematic map** (Natural Earth 10m + OurAirports, public domain, bundled):
  - land, lakes, rivers, urban areas
  - major roads (toggle), state lines
  - runways with airport codes
  - range rings (toggle), "you are here" crosshair
- **Apple Map**: `MKMapView`, muted emphasis, no POIs, appearance forced to match the
  palette, non-interactive.
- **Pure field**: dot grid only.
- **Info corner** (choose the corner): location name in large tracked caps, time,
  aircraft count, and an "Overhead" block for the nearest flight (callsign, type,
  altitude, speed, route).

## Settings

- **Location**: system / search (zip or city) / coordinates; display name override.
- **Map**: style; zoom radius 5–150 mi; rings; runways; roads; dot grid.
- **Aircraft**: labels; color mode; trail length (off / 1 / 3 / 10 min); glyph; pulse;
  brightness; ground traffic; minimum altitude.
- **Appearance**: light / dark / dynamic (system or sun).
- **Info**: on/off; corner; which items to show.
- **Performance**: refresh interval; battery saver; FPS cap.
- **Displays**: all / main only. Launch at login (`SMAppService`).

## Testing

Swift Testing unit tests in AirspaceCore:

- decoder fixtures for both feeds
- tracker merge and expiry
- dead reckoning and easing
- projection round trip
- power policy table
- coordinate parsing
- solar times
- label layout
- geodata decode

Headless `ImageRenderer` snapshots of each style and appearance, for visual review.

## Out of scope (v1)

Clicking planes (the wallpaper is click-through), historical playback, push alerts, custom
receivers (enabled later by the `FlightSource` protocol), App Store distribution.
