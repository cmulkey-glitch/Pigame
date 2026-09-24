# Player movement & physics (7800 ROM trace)

Traced from `Downland_03242025_a7800_fix.a78` by reading the disassembly and checking it
against the emulator frame by frame. `src/game/player.js` is a direct port;
`tests/physics.test.mjs` replays ROM traces and currently matches all 8 scenarios on every
frame (x, y, state flags, 8.8 velocity, rope-hold counter).

Reference for the CoCo original: [Downland_C](https://github.com/pw32x/Downland_C) (MIT) and
[Downland Unearthed](https://puffweet.com/2026/01/08/downland-unearthed-boulder-ball-bat-bird/).
The 7800 port keeps the original's structure (jump/fall/climb/hang states, death on landing at
terminal velocity) but uses its own numbers and tile-based collision.

## Units and timing
- `x` = `$ED`, MARIA hpos (tile column c starts at x = 4 + 8c). Player is 8 hpos (16 px) wide.
- `y` = `$EE`, scanline with 0 at the top of the HUD row (tile row r starts at y = 8 + 8r).
  Player is 16 lines tall. Standing y is always ≡ 7 (mod 8).
- 60 Hz frames; frame counter `$E6`. **Physics runs on a 4-frame tick** (`tick = $E6 & 3`).
- Input: stick byte `$2131` (SWCHA copy, bit 7 R, 6 L, 5 D, 4 U, 0 = pressed), fire `$2102`.

## State (`$F1` bits, plus `$FA` bit 0)
| bit | meaning |
|---|---|
| 0 | in the air |
| 1 | vertical — no horizontal momentum in the air (jump with no direction, dropping off a rope) |
| 2 | regenerating (after a death; invulnerable to drops, can't jump) |
| 3 | jump latch — fire must be released before the next jump |
| 4 | dead |
| 5 | running (set each walking tick) |
| 6 | climbing |
| `$FA` bit 0 | hanging beside a rope |

Facing `$F0`: 1 = left, 2 = right.

## Main loop order (`$83F8`)
1. every frame: drop collision `$B7A2` (skipped while regenerating/dead)
2. tick 2: ball/bird collision `$B7F0`
3. tick 0: walk `$BD0F`
4. tick 0 while climbing: climb `$B52B`
5. every frame: drops update `$C300`
6. fire held, on the ground, not regenerating: jump `$C26B`; fire released clears the latch
7. tick 0 while in the air: air physics `$BFEB`
8. tick 1: touch items `$B252`

## Tile collision (`$C6F3`)
`tile(x, y)` = RAM map (`$2200`) at column `(x-4)>>3`, row `(y-8)>>3`.
- `$04` flat floor — **the only tile you can stand or land on**
- `$02` rope, `$2C` rope top, `$2A` bar
- `$1A–$1E` open door; closed doors are written into the map as walls `$08`/`$0A`
- `$20` diamond, `$22` ring, `$24` key
- walking blocks on any code `> $06`; in the air, codes `$07–$1F` are walls

## Walking (`$BD0F`, tick 0)
- Probe `tile(x+7, y+8)` walking right, `tile(x, y+8)` walking left (right has priority).
  - door code and x ≥ `$8D` (right) / x ≤ `$0B` (left) → go through the door (`$BEA5`)
  - item → pick it up (no move this tick)
  - code > 6 → blocked
- Otherwise x ± 1 (**0.25 hpos/frame**). If `tile(x+3, y+15)` is floor → running.
  Else walk off the edge: x ± 1 more, y + 1, velocity high byte `$FF`, in the air
  (horizontal momentum kept).
- Any walking attempt ends regeneration.

## Jumping (`$C26B`)
- Needs: fire, not in air, not regenerating, latch clear, not dead, not hanging.
- No direction held → vertical jump. On a rope a jump needs a direction.
- Velocity `vy` = **`$0580`** (8.8, positive = up).

## Air (`$BFEB`, tick 0)
1. Horizontal (unless vertical/dead): x ± 1; wall probe `tile(x+1, y+15)` left /
   `tile(x+6, y+15)` right. Hit → undo, reverse facing, and if still rising negate the
   velocity high byte (bounce down).
2. Vertical (skipped during the mid-air death pause):
   - Falling (`vy_hi ≥ $80`) and `tile(x+3, y+16)` is floor and `tile(x+3, y+16−vy_hi)` isn't →
     land: `y = (y & $F8) + 7`. **`vy_hi < $FA` on landing = death** (i.e. at terminal speed).
   - Else `y −= vy_hi`, `vy −= $00C0` (**gravity 0.75 line/tick²**); falling `vy_hi` is
     clamped to `$F9` (**terminal 7 lines/tick**, low byte kept).
   - A standing jump rises 20 lines and lasts 14 ticks (56 frames).
   - Walking off an edge, terminal speed is reached after about 26 lines, so any fall longer
     than that (just over 3 tile rows) kills.
3. Rope catch (`$C19A`): `tile(x+3, y+6)` is `$02`/`$2C` and `x & $0F` is 4 or `$C`
   (exactly on the rope column) → climbing. A bar `$2A` (also at `y+9`) snaps to it.

## Climbing (`$B52B`, tick 0)
- Up: y − 1 while `tile(x+3, y+5)` is rope (**0.25 line/frame**); stops at the top.
- Down: y + 2 (**0.5 line/frame**); past the bottom → vertical fall, `vy_hi = $FF`.
- Left/right held (`$B620`): counter `$0144` = 6, counts down 1 per tick, then shift x ± 4
  and hang (refused if a wall tile is there). From a hang: 6 ticks back toward the rope
  returns to climbing; 6 ticks away lets go (vertical fall, `vy_hi = 0`).

## Items (`$B2F1`, `$B252`)
Walking into an item, or touching one while in the air/climbing (probe at y+1 rising /
y+15 falling, and x or x+7 at y+7). Score is BCD `$01A6–$01A8`: key 250, other items 350,
each plus a random 00–99 (`$C74F`). Extra life when the ten-thousands digit changes (max 5).

## Death (`$B812`)
- Causes: drop hit (`$B7A2`, box 8×18), ball/bird hit (`$B7F0`, box 10×22), landing at
  terminal speed.
- On a rope: let go. In the air: freeze and flicker for `$2C` frames (`$0141`), then fall.
- On the ground: splat for `$4B` frames (`$0142`, second splat frame below `$43`), then lose
  a life (`$0140`, starts at 4) and **regenerate in place** (differs from the CoCo original).

## Animation (`$B861`, `$BA16`)
Frame f = head `$E02F + 8f`, legs 4 bytes later (320C). `assets/sprites.json → playerFrames`.
| frames | use |
|---|---|
| 0–3 / 4–7 | run right / left: `($E6 & $1F) >> 3`; standing = 2 / 6 |
| 8–11 | regenerating: `($E6 & 2 ? 1 : 0)` + 2 if facing left |
| 12–13 | climbing: `y & 2 ? 13 : 12` |
| 14 / 15 | air or hanging, facing right / left; mid-air death flickers 14/15 on `$E6 & 4` |
| 16 → 17 | splat |

## Not ported yet
Drops (`$C300`), ball and bird (`$B161`, `$B7F0`), room timer (`$01AA/$01AB`), doors
locked until their key is collected (`$AExx`), chamber-9 → X rule.
