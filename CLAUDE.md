# Project notes for Claude

The active project is **Spiral Shift**, a Roku game in `dash/`. Read `dash/README.md` (how it
works, every tool, the file layout) and `dash/NOTES.md` (why it is this way, known issues, to-do). The rest of the repository is older work: a
Downland port (`roku/`, `src/`, `tools/` except `tools/brs-device.cjs`) that must not be sold.

## The game in brief
- Each level is the four edges of the screen: ball (bottom, jump), triangle (right, steer with the
  arrows, no gravity), square (top, Up / Down switches gravity side), diamond (left, hold to cut
  inward). Corners are checkpoints with a rocket animation that turns one shape into the next.
- 10 classic levels, each 16 blocks shorter per side and 3% faster than the last; drawn as a true
  spiral (inner levels visible beyond the ceiling), a core in the centre for the finale.
- Spiral run plays all 10 as "layers" with no pause. Random worlds: 10 layers built from a seeded
  pool of 480 solved sides (`dash/roku/pool/`), shapes shuffled across sides, 5-letter world
  codes and a world of the day. Records: best time and fewest attempts per level, spiral, world.
- Easy mode = everything at 65% speed (registry key still "kids"; it used to be Kids mode).
- Controls: OK or any arrow is the button for ball / diamond; arrows steer triangle / square
  (toward / away from the edge they run on); Back or Play/Pause pauses. Not `*`: Roku keeps it.

## Commands (Windows: `python`, not `python3`)
- Build: `python dash/tools/build.py` -> `dist/spiral-shift-roku-<version>.zip`;
  `--ads` -> `dist/spiral-shift-ads-roku-<version>.zip` (separate ad-supported channel).
- Test (about 10 min; needs Node and `npm install -g brs brighterscript`): `node dash/tools/test.mjs`.
- Screenshots of every screen without a Roku: `python dash/tools/shot.py` -> `dist/shots/`.
  Use it to check any visual change before handing a build over.
- Levels: `levelgen.py`, pool: `poolgen.py`, solutions: `pysolve.py` (exact copy of the
  BrightScript float maths; keep it in step with `Run_step` in `game.brs`).
- Bump `build_version` / `minor_version` in `dash/roku/manifest` for every build handed over:
  the dashboard rejects a re-upload with the same version.

## Publishing
- Roku developer dashboard, beta channel. The dashboard accepted the zip directly last time.
- The owner wants direct recommendations, blunt corrections, no hedging.

## Open items
- The ads build (`dash/roku-ads/ads.brs`, Roku Advertising Framework) is an untested prototype:
  it releases the roScreen while RAF plays ads and recreates it. Needs a device test; if RAF will
  not show over a roScreen app, the fallback is a SceneGraph wrapper.
- Random world is the bottom menu card because it is meant to be locked (paid unlock, e.g. a
  "Remove ads / unlock" Roku Pay purchase). Not built yet.
- The GitHub repository was public; the owner is moving to local-only.
