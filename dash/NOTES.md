# Spiral Shift: design notes, decisions, known issues, plans

Written at version 0.9.6 from the development chat, so the reasons behind the design survive it.
`README.md` says how things work; this file says why, what is shaky, and what is next.

## How it got here (decisions and why)

**Origin.** Started as a Geometry Dash clone for Roku; redesigned into an original game so it can
be sold. The shapes, the spiral and the corner rockets are what set it apart.

**The ball (bottom).** Jump peaks at 2.0 to 2.3 blocks and lasts 22 to 28 frames (tests check
this). Early on level 1 had 5 spikes in a row and a too-tight timing window; patterns are now
generated with a minimum timing window (12 frames on level 1 down to 8). Orbs need a press while
touching (holding through one also works).

**The triangle (right).** Was a gravity-flipper; a 5-year-old could not understand sideways
gravity, so it became steering with the arrows (toward / away from the edge) with no gravity: it
hovers when no arrow is held. That made it too easy, so its patterns became slaloms with gaps
narrowing from 5 rows to 2 by level 8. Was the hardest shape for a while; balance is now OK.

**The square (top).** Too easy as a one-button flipper. Now Up / Down choose the side (a press
toward the side it is already on does nothing), most hazards sit on the side it is on so each
needs a flip, and it gets staggered spike-tipped walls.

**The diamond (left).** "Difficult as-is": unchanged since the start. Hold to cut inward at 45
degrees, release to cut back.

**Corners.** A checkpoint, and an animation: the shape rolls into the corner, nose cone and fins
fly in to make a rocket, it blasts up the next side and changes shape on the way. The first
version did not show the conversion well; the shape now shrinks, flashes and grows mid-flight.

**The spiral.** The original idea was a true spiral where level 2 sits inside level 1 and you can
see it. Inner levels are drawn full size beyond the ceiling of the side in play (not scaled),
11 rows in per ring, scrolling with the run. Corners broke the illusion at first; inner rings
now turn inward one ring in from each corner. A core sits at the centre; a spiral run ends by
flying into it.

**Lengths and speed.** 7 minutes for the whole spiral was not satisfying for a paid game, and
level 10 at 19 s was too short. Sides are now 260 - 16 x level blocks (260 down to 116) and
each level is 3% faster (1.27x on level 10): level 1 about 100 s, level 10 about 35 s, the
spiral about 10 minutes. The obstacle ramp was softened (x0.8) since speed carries some of the
difficulty.

**Spiral run.** Continuous, no pause between levels (they are called "layers" in a run). Quitting
saves the layer; the menu offers continue or new run.

**Easy mode.** Was "Kids mode": everything at 65% speed, so every path is the same and every
timing window 1.5x longer. Renamed because a kids' app has strict ad rules (US child privacy
law). Registry key is still "kids"; Easy records use a "k" prefix.

**Random worlds.** Built from a seed, named by a 5-letter code (24^5 = 7,962,624 worlds; the
alphabet avoids look-alikes). A world of the day is the same for everyone on a date. Each layer
picks each side from the pool (12 sides per shape per tier, 480 in all) at its tier or one
either side, cut short to the layer's length (a prefix of a beatable side is beatable).
Considered and dropped: reversed and mirrored variants. They were only verified by the
Python physics, the ball could not use them, and new sides cost the same to verify and are
more varied. Shapes are shuffled across the sides (24 orders): the owner tried it and kept it.
To make that playable, the ball and diamond take OK or any arrow, and each corner shows the new
shape with its keys for that side ("TRIANGLE: UP / DOWN").

**Records.** Best time and fewest attempts (the owner's choice over a score) per level, per
spiral run and per world, plus best % per level. Registry section "spiralshift": `L<n>t/a`
(level), `St/a` (spiral), `W<code>t/a` (world), `best<n>` (%), `kids`, `lastworld`, and the
spiral save. Easy mode: the same keys with a `k` prefix.

**Controls.** Back or Play/Pause pauses. `*` cannot be used: Roku keeps it for its own options.

**Menu.** Cards: spiral run, single level, speed, random world. Random world is last because it is
meant to be locked behind a purchase.

**Verifying levels.** Every stage of every level and every pool side has a stored solution
(`dash/tests/solutions/`) that the tests replay with the real BrightScript code, and never pressing
must crash. `pysolve.py` copies the brs interpreter's float maths exactly (round to float32, then
to 7 significant digits) and finds solutions about 100x faster than solving in brs. The pool
generator rejects any side `pysolve` cannot finish: one side passed the generator's float64 check
but was impossible in the game.

## Monetization (decided so far)
- Ads must use the Roku Advertising Framework (RAF) to pass certification. Roku's default is an
  inventory split: Roku fills 30% of ad slots and keeps that money (and need not fill them); the
  app fills the other 70% from its own ad source, if it has one. Payouts are quarterly, once a
  quarter reaches $100. Expect little from ads alone until there are thousands of daily players.
- Plan: free with ads only at natural breaks (leaving a finished level, run or world; at most one
  every 5 minutes; never mid-run or after a crash), plus a one-time "remove ads / unlock" purchase
  through Roku Pay (~$2.99). Roku takes a cut of purchases too (believed 20%: check).
- The ad-supported build is a separate channel made from the same code: `build.py --ads`.
- The Downland port elsewhere in this repository must not be sold.

## Publishing notes
- Roku developer dashboard, beta channel. The dashboard accepted the zip directly (no signed .pkg
  needed so far). It rejects an upload whose version is not higher: bump the manifest every time
  (the zip name carries the version so an old file is never uploaded by mistake).
- Static-analysis warnings, all fixed: RSG 1.3 (manifest `rsg_version=1.3`, and minimum firmware
  15.1 set in the dashboard), version not updated, subtitle,
  rsg_version, memory monitor APIs (now guarded with try/catch), icon_sd must be 246x140.
- Store text: `dash/store/listing.md`. The on-device description must stay under 200 characters.
  Store artwork: `dist/store/` (from the build); screenshots can come from `dash/tools/shot.py`.

## Known issues and risks
- **Ads on a device: in progress.** Sideloaded apps get no ads from Roku's default server, so
  `build.py --ads-test` uses Google's sample VAST tag. First device test (0.9.9): the ad played,
  then the app quit, because the roScreen had been let go and a Roku app quits when its last
  screen closes. 0.9.10's test build tries, break by break: keep the roScreen up, a blank
  SceneGraph screen as a placeholder, a blank roImageCanvas; it saves each step so the next launch
  shows where a quit happened. The real ads build uses "keep" until the test says otherwise.
- **Device maths vs the tests.** The tests run in the brs interpreter, which rounds floats
  differently from a real Roku (true float32). Fairness margins should cover it, but a side with
  a very tight window could play differently on the TV. Play-test; note world code and layer.
- **World codes depend on the pool and on `World_build`.** Regenerating the pool or changing the
  build order changes every world for every code, so saved world records and the world of the day
  no longer match. After launch, never change them without versioning (e.g. a pool version in the
  code or the registry keys).
- **Random worlds are not saved mid-run.** Quitting a world loses the progress (the classic spiral
  saves its layer).
- **Possible stutter** the first time a random tier is used (each pool file is parsed on first
  use, about 60 to 125 KB of text). Not measured on a device.
- **Held keys across a corner.** An arrow still held from steering the triangle counts as the
  button when the next shape is the ball or diamond (the 30-frame pause after a corner usually
  covers it).
- **Inner-ring preview is cropped**: levels shrink 16 per layer but rings are drawn 22 in, so the
  last few columns of the next level's preview are not shown. Cosmetic.
- **Screenshot tool font**: DejaVu or Arial, not the Roku's font; spacing on the TV can differ.

## To do / next
1. Test the ads build on the TV: finish a level after 5 minutes, press OK, check that an ad plays
   and the game comes back. Fall back to SceneGraph if not.
2. Lock random worlds behind the purchase (decide what stays free: maybe the world of the day),
   with a padlock and an "unlock" line on the card; Roku Pay one-time product; restore purchases.
3. Refresh store screenshots and artwork from `shot.py` for the new menu and screens.
4. Make the GitHub repository private or delete it (it was public), keep the local copy backed up.
5. Prepare for public release: certification checklist (deep linking is accepted; memory monitor
   in place), parental / content ratings, support contact.
6. Ideas not started: world-of-the-day leaderboard (needs a server), more pool sides, per-world
   music, saving random-world progress.
