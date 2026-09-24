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
platform file. Movement tuning in `src/game/player.js` is guessed, not yet from the ROM.
