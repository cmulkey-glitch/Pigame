# Downland port

Goal: HTML5 version of Downland first, then other systems. Assets and layouts come from the
Atari 7800 build (`Downland_03242025_a7800_fix.a78`, not committed).

## Extracting
```
pip install py65 pillow
python3 tools/extract_downland.py path/to/Downland.a78
```
Takes ~75 s (the 7800 runs in a Python emulator to capture screens and sprites).

Outputs: `assets/tiles.png`, `assets/sprites.png` + `.json`, `data/rooms.json`,
`docs/rooms/*.png`. ROM layout: `docs/ROM_NOTES.md`.

## Chamber viewer (HTML5)
```
python3 -m http.server 8000   # then open http://localhost:8000
```
(ES modules + fetch need a server; opening `index.html` directly won't work.)

Arrows walk/climb, Space jumps, `[` `]` / `0`–`9` / `X` pick a chamber, `G` shows the
collision mask. Walk into a door opening to follow the ROM's door graph.

Layout: `src/platform/web.js` is the only browser-specific file (canvas, input, loading,
frame loop). `src/game/` is plain JS game logic — a port to another system replaces the
platform file.

## Ported game logic
- `src/game/player.js` — walk, jump, fall, ropes, hanging, death, animation
- `src/game/drops.js` — acid drops; `src/game/rng.js` — the ROM's random numbers
- `src/game/state.js` + `room.js` — treasures, keys, doors opened by keys
- `src/game/enemies.js` — ball, bird, chamber timer
- `src/game/game.js` — title screen, chamber 0 / X rules, game over, escape ending
- `src/game/sound.js` — the ROM's sound driver (TIA registers); `src/platform/tia-synth.js` renders them (in `tia-worklet.js` on the web)

Documented in `docs/PHYSICS.md` and `docs/ROM_NOTES.md`. Each is checked against traces
recorded from the ROM:
```
for t in tests/*.test.mjs; do node $t; done      # all must pass, no ROM needed
python3 tools/trace_player.py  path/to/Downland.a78   # re-record traces from the ROM
python3 tools/trace_drops.py   path/to/Downland.a78
python3 tools/trace_objects.py path/to/Downland.a78
python3 tools/trace_enemies.py path/to/Downland.a78
python3 tools/trace_rules.py   path/to/Downland.a78
python3 tools/trace_sound.py   path/to/Downland.a78
```

## Chamber editor
`editor.html` (serve the repo root, e.g. `python3 -m http.server`, then open `/editor.html`):
paint terrain, place treasures, keys, doors, drop points and the ball, and tune the player
physics with sliders. **Play-test** runs the chamber with the real game code; slider changes
apply live, and the physics panel shows the jump's height, reach and landing speed (and warns
when your own jump would kill you on flat ground). Edits autosave in the browser; **Export**
writes `levels.json`, **Open in game** plays them in `index.html?pack=editor`.

Physics parameters live in `src/game/physics.js` (`roku/source/physics.brs` on Roku). The
defaults are the ROM's, so the ROM trace tests check them; `tests/traces/physics_custom.json`
(from `tools/record_custom_physics.mjs`) checks the Roku player matches the JS one with other
settings. A level pack is the `rooms.json` format plus an optional `physics` object.

## Level packs
`levels/starter.mjs` holds four original chambers as ASCII maps (the legend is at the top of
the file); `node tools/build_levels.mjs levels/starter.mjs` builds `levels/starter.json`, which
the editor's **Load starter caves** button opens. A pack can set its own `rules` (where a game
starts, which chamber's door home starts a new round, the bonus chamber or -1 for none).

`node tools/solve_pack.mjs levels/starter.json` proves a pack can be played through: it runs
the real player code over every input sequence (drops and enemies aside) and reports any
treasure, key or chamber you can't reach, or a round you can't finish. It passes on the
ROM's chambers and on the starter pack (a few minutes each).

## Roku (sideload prototype)
`roku/source/` is a BrightScript port of `src/game/` (`player.brs`, `world.brs`, `game.brs`)
plus `main.brs` for the screen, remote and sound. Chamber art is pre-rendered, text and items
are drawn from pre-tinted copies of the tile atlas, and sound effects are WAVs rendered by the
same driver + TIA synth as the web (`tools/render_sounds.mjs`), since Roku can't synthesize.
```
node tools/test_roku.mjs          # ROM trace checks (device for-each semantics) + compile check (npm i -g brs brighterscript)
python3 tools/build_roku.py       # -> dist/downland-roku.zip (--pack levels/starter.json etc.)
```
Sideload: enable developer mode on the Roku (Home ×3, Up ×2, Right, Left, Right, Left, Right),
open `http://<roku-ip>` in a browser, log in as `rokudev`, upload the zip, press Install.

Remote, held sideways (top to the left): Up moves left, Down moves right, Right climbs up,
Left climbs down. Play or OK jumps, in the direction held or released in the last ~12 frames,
since a Roku remote can't send two buttons together. A jump keeps its direction until you land,
then you stop unless an arrow is held; Play within ~12 frames of landing chains another jump
the same way. Back returns to the title (exits from the title), Rew / Fwd step through
chambers (playtest).
