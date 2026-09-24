# Downland (A7800) ROM notes

Source: `Downland_03242025_a7800_fix.a78` (not in the repo — `*.a78` is gitignored).

## Cart
- Header claims 64K SuperGame + 16K RAM at `$4000`. The two 32K halves are identical,
  so the game is effectively a flat 32K ROM at `$8000–$FFFF`.
- Vectors: RESET `$FC5C`, NMI (DLI) `$F612`, IRQ `$F681`. Startup is 7800basic-style
  (NTSC/PAL detect → `$2109`, DLL at `$1800`).
- Cart RAM `$4000+` holds the display lists; the chamber tile map lives in `$2200–$23DF`.

## Display
- `CTRL = $53`: 320A/C read mode, double-byte characters, `CHARBASE = $E0`.
- All graphics are in `$E000–$E7FF`: 8-line zones, one pixel row per page, top row in `$E7xx`.
- Chamber = 24 zones of indirect (character) objects, 20 double-byte chars per row, 320A
  (1bpp, 16×8 px per tile at 320 resolution). Terrain uses palette colour 2.
- Sprites are direct objects in 320C (4 px/byte, colour per pixel pair) or 320A.
  The player is two stacked 8-line sprites (head / legs).

## Chambers
| Address | What |
|---|---|
| `$0146` | current chamber (0–9, 10 = "X", `$FF` = title) |
| `$892F` | chamber loader: sets `P0C2` from `$F52F,X`, jumps through `$895C/$8968` (X = chamber+1) |
| `$C939 + n×$1E3` | tile map for chamber n (480 bytes = 20×24; first 256 → `$2200`, rest → `$2300`) |
| `$C7A6` | title screen map (20×20) |
| `$F530` | terrain colour per chamber (`$88 $38 $68 $18 $A8 $48 $B8 $08 $58 $26 $76`) |
| `$87DC–$892E` | progressive reveal: copies 4 cells per frame, blanking object codes |
| loader record lists (e.g. `$8C18`) | 5-byte `lo, hi, palette/width, hpos, zone` runs, terminated by `00 00` |

Tile codes are even (double-byte chars); `tiles.png` index = code / 2.
Codes `$1A $1C $1E $20 $22 $24` are object markers — the loader blanks them and the
game draws the object instead: `$1A–$1E` door graphics, `$20` diamond, `$22` gold ring,
`$24` key. They are listed per chamber in `data/rooms.json` → `objects`.

## Doors
36 doors total. Per chamber n, doors are `$F55F[n] .. $F55F[n+1]-1`.
- `$F53B[d]` door position in its own chamber
- `$F58F[d]` destination chamber
- `$F56B[d]` arrival position in the destination
Position byte: bit 7 = right wall (x = `$8D`, else x = `$0B`), y = `(v & $7F) × 8 − 1`
(decoded at `$BF5C`). Chamber 9 → X happens at `$BFB3` when bit 3 of `$FA` is set.

## Not yet traced
- Rope/drop/spider behaviour and timings, per-chamber tables `$F5B3` / `$F5BE`.
- The emulator shows garbage in the score digits; the HUD path isn't traced yet.
