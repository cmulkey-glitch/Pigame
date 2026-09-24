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
