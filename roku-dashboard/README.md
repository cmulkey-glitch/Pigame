# Living Room Dashboard (Roku screensaver)

A standalone Roku screensaver: big clock and date, National Weather Service forecast and severe
weather alerts, rotating news headlines, today's holidays (including the obscure ones), and
Wikimedia's picture of the day as the background. No backend: the Roku calls free, keyless
public APIs directly.

Roku rules this follows (developer.roku.com, screensavers + certification criteria): screensavers
must be standalone apps with `screensaver_title` and `RunScreenSaver()`, no `Main`/
`RunUserInterface`, no user interaction, ads, in-app purchases, deep links or video. The only
input is the optional settings screen (`RunScreenSaverSettings()`), saved to the registry.

## Layout
- `source/main.brs`: the two entry points
- `components/DashboardScene`: the screensaver; `SettingsScene`: settings; `FetchTask`: network
  and parsing off the render thread
- `source/lib/`: pure logic shared by the components and tested off-device
  - `dates.brs`: calendar math, Easter, holiday rules
  - `feeds.brs`: feed presets, RSS/Atom headline extraction
  - `weather.brs`: NWS points/forecast/alerts parsing
  - `potd.brs`: picture of the day (sized thumbnail, credit line)
  - `settings.brs`: config, saved settings, clock/date/drift helpers, ZIP lookup
- `data/holidays.json`: holiday list (rules, not dates; see the `note` field)
- `data/zip/NNN.csv`: ZIP to lat/lon, from the Census ZCTA gazetteer (`tools/build_zips.py`)

## Data sources
| What | Source | Notes |
|---|---|---|
| Weather, alerts | api.weather.gov | US only; asks for a contact in the User-Agent |
| Picture of the day | en.wikipedia.org/api/rest_v1/feed/featured | Thumbnails only at standard widths (1280/1920) |
| Headlines | Publisher RSS/Atom feeds | Headline + source only |
| ZIP to location | Census ZCTA gazetteer, bundled | PO-box-only ZIPs aren't in it |

## Test, package, sideload
```
npm install -g brs brighterscript
node roku-dashboard/tools/test.mjs          # logic tests + device compile check
python3 roku-dashboard/tools/package.py     # -> dist/roku-dashboard.zip
```
Enable developer mode on the Roku (Home x3, Up x2, Right, Left, Right, Left, Right), open
`http://<roku-ip>`, upload the zip. Then Settings > Theme > Screensavers: pick Living Room
Dashboard, use "Change screensaver settings" to enter a ZIP, and "Preview" to see it.

## Before publishing
- Put a real contact in `Config().userAgent` (`source/lib/settings.brs`).
- Verify every holiday in `data/holidays.json`, especially entries marked `"check": true`, and
  grow the list. Optionally host a copy and set `Config().holidaysUrl`.
- Run it on real hardware for a few hours, including a low-end model: memory with the
  background photo, night dim, alert banner, drift.
- The NPR feed returned 403 from the dev machine; confirm it on a Roku or drop it.
- Not built yet: the built-in nature photo set (background is picture of the day or a solid
  color for now).
