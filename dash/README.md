# Cube Dash (Roku)

An original auto-runner in the style of Geometry Dash, for Roku sideloading. Not affiliated
with RobTop Games: no names, art or music from Geometry Dash are used; everything here is
drawn and composed by `tools/build.py`.

The cube runs on its own; jump to clear spikes, land on blocks, hit yellow orbs mid-air, ride
jump pads, and fly the ship through the pink portal. One touch of a spike or a block's side
and the attempt restarts. Three levels: First Flight (easy), Orbit Run (normal), Skyline
(hard, with a ship section). Best % per level is saved on the device.

## Remote
- OK, Play or Up: jump. Hold to keep jumping on landing; as a ship, hold to climb.
- Yellow orb: press (or be holding) while touching it for a second jump in mid-air.
- Menu: Left / Right picks a level, OK plays, Back exits.
- In a level: Back returns to the menu.

## Build and sideload
```
pip install pillow
python3 dash/tools/build.py        # -> dist/cube-dash-roku.zip
```
Enable developer mode on the Roku (Home ×3, Up ×2, Right, Left, Right, Left, Right), open
`http://<roku-ip>` in a browser, log in as `rokudev`, upload the zip, press Install.

## Test
```
npm install -g brs brighterscript
node dash/tools/test.mjs           # ~2 minutes
```
Runs `tests/tests.brs` in the brs interpreter: physics checks (jump height and length, spikes,
blocks, pads, orbs, ship), then for each level a search over hold / release every frame must
find a way to the end, and never pressing must die. Then a BrighterScript compile check.

## Layout
- `roku/source/game.brs` — level parsing and the 60 Hz physics step (no Roku objects)
- `roku/source/main.brs` — screen, remote, menus, sound
- `roku/levels/N.txt` — levels as text: header lines, `---`, then rows (top first, last row on
  the ground). `#` block, `^` spike, `v` hanging spike, `_` pad, `o` orb, `S` ship portal,
  `C` cube portal, `.` empty. One character = one block; the level ends at the last column.
  Add a level by adding a file and its number to `Levels_list()` in `main.brs` and to the
  list in `tests/tests.brs`.
