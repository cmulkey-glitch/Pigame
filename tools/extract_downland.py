#!/usr/bin/env python3
"""Extract Downland (Atari 7800) tiles, sprites, rooms and exits into port-friendly files.

Usage: extract_downland.py path/to/Downland.a78 [outdir]

Writes (under outdir, default: repo root):
  assets/tiles.png          128 tiles, 16x8 px, 1bpp white on transparent (tint by room colour)
  assets/sprites.png        every non-tile graphic the game put in a display list, rendered
  assets/sprites.json       sprite catalog: ROM address, width, MARIA mode, sheet rect
  data/rooms.json           11 chambers: 20x24 tile map, objects, colours, exits
  docs/rooms/chamberN.png   emulator screenshot of each chamber
  docs/rooms/sheet.png      all chambers on one sheet

See docs/ROM_NOTES.md for the addresses used here.
"""
import json, os, random, sys
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import a7800emu
from a7800emu import Emu, PAL

GFX = 0xE000            # CHARBASE $E0: 8-line zones, pages $E0..$E7, top line in $E7
MAP_BASE = 0xC939       # chamber 0 tile map; one map every $1E3 bytes
MAP_STRIDE = 0x1E3
MAP_W, MAP_H = 20, 24   # 20 double-byte chars x 24 zones; row data split $2200/$2300 in RAM
ROOM_COLOR = 0xF530     # terrain colour (P0C2) per chamber
DOOR_FIRST = 0xF55F     # first door index per chamber (12 entries, last is the total)
DOOR_POS = 0xF53B       # door position in its own chamber (bit7 = right wall, low bits = row)
DOOR_ENTRY = 0xF56B     # arrival position in the destination chamber (same encoding)
DOOR_DEST = 0xF58F      # destination chamber
REC_HI, REC_LO = 0x895C, 0x8968  # per-chamber loader (RTS jump table, index = chamber + 1)
OBJECT_CODES = {0x1A, 0x1C, 0x1E, 0x20, 0x22, 0x24}  # doors ($1A-$1E) and items; the loader blanks these cells
NUM_ROOMS = 11          # chambers 0-9 plus the bonus chamber (shown as "X")
PLAYER_BASE = 0x2F      # player frame f: head at $E02F + 8f, legs 4 bytes later (320C)
PLAYER_FRAMES = 18


def rd(a):
    return ROM[a - 0x8000]


def door_pos(v):
    """Decode a door byte into wall side and pixel coordinates (as the game computes them at $BF5C)."""
    right = bool(v & 0x80)
    return {'raw': v, 'side': 'right' if right else 'left',
            'x': 0x8D if right else 0x0B, 'y': (v & 0x7F) * 8 - 1}


def tile_atlas(path):
    cols = 16
    img = Image.new('RGBA', (cols * 16, (128 // cols) * 8), (0, 0, 0, 0))
    px = img.load()
    for n in range(128):
        ox, oy = (n % cols) * 16, (n // cols) * 8
        for line in range(8):
            page = GFX + (7 - line) * 256
            for k in range(2):
                b = rd(page + ((n * 2 + k) & 0xFF))
                for bit in range(8):
                    if b & (0x80 >> bit):
                        px[ox + k * 8 + bit, oy + line] = (255, 255, 255, 255)
    img.save(path)


def room_records(room):
    """Parse the loader's display-object list: (map index, palette, run length) per run."""
    idx = room + 1
    handler = ((rd(REC_HI + idx) << 8) | rd(REC_LO + idx)) + 1
    code = [rd(handler + i) for i in range(8)]
    assert code[0] == 0xA9 and code[2] == 0x85 and code[4] == 0xA9, hex(handler)
    p = (code[5] << 8) | code[1]
    runs = []
    while True:
        lo, hi, pw, hpos, zone = (rd(p + i) for i in range(5))
        if lo == 0 and hi == 0:
            break
        width = (32 - (pw & 31)) & 31 or 32
        runs.append({'cell': ((hi << 8) | lo) - 0x2200, 'palette': pw >> 5, 'len': width})
        p += 5
    return handler, runs


def rooms_data(palettes):
    rooms = []
    for r in range(NUM_ROOMS):
        base = MAP_BASE + r * MAP_STRIDE
        raw = [rd(base + i) for i in range(256)] + [rd(base + 0x100 + i) for i in range(MAP_W * MAP_H - 256)]
        tiles, objects = [], []
        for row in range(MAP_H):
            line = []
            for col in range(MAP_W):
                c = raw[row * MAP_W + col]
                if c in OBJECT_CODES:
                    objects.append({'code': c, 'col': col, 'row': row})
                    c = 0
                line.append(c // 2)
            tiles.append(line)
        _, runs = room_records(r)
        pal = [[0] * MAP_W for _ in range(MAP_H)]
        for run in runs:
            for i in range(run['len']):
                cell = run['cell'] + i
                if 0 <= cell < MAP_W * MAP_H:
                    pal[cell // MAP_W][cell % MAP_W] = run['palette']
        d0, d1 = rd(DOOR_FIRST + r), rd(DOOR_FIRST + r + 1)
        doors = [{'id': d, 'at': door_pos(rd(DOOR_POS + d)), 'to': rd(DOOR_DEST + d),
                  'arrive': door_pos(rd(DOOR_ENTRY + d))} for d in range(d0, d1)]
        color = rd(ROOM_COLOR + r)
        rooms.append({'id': r, 'name': 'CHAMBER %s' % ('X' if r == 10 else r),
                      'mapAddr': '$%04X' % base, 'color7800': color,
                      'colorRGB': '#%02x%02x%02x' % PAL[color],
                      'tiles': tiles, 'tilePalette': pal, 'objects': objects, 'doors': doors,
                      'palettes7800': palettes[r],
                      'palettesRGB': [['#%02x%02x%02x' % PAL[c] for c in pl] for pl in palettes[r]]})
    return rooms


def boot(e):
    for _ in range(150):
        e.run_frame()
    e.fire = True
    for _ in range(10):
        e.run_frame()
    e.fire = False
    for _ in range(200):
        e.run_frame()


def snapshot(e):
    c = e.cpu
    return (bytes(e.mem.m), bytes(e.regs), c.pc, c.sp, c.a, c.x, c.y, c.p, e.cyc, e.frame)


def restore(e, s):
    e.mem.m[:] = s[0]
    e.regs[:] = s[1]
    c = e.cpu
    c.pc, c.sp, c.a, c.x, c.y, c.p, e.cyc, e.frame = s[2:]


def load_room(e, room):
    """Fake a JSR to the chamber loader ($892F) with the chamber number in $0146."""
    e.mem[0x0146] = room
    ret = e.cpu.pc - 1
    for byte in (ret >> 8, ret & 0xFF):
        e.mem[0x100 + e.cpu.sp] = byte
        e.cpu.sp = (e.cpu.sp - 1) & 0xFF
    e.cpu.pc = 0x892F
    for _ in range(220):  # the chamber is revealed a few tiles per frame
        e.run_frame()


def palette_regs(e):
    return [[e.regs[0x20]] + [e.regs[0x21 + 4 * i + k] for k in range(3)] for i in range(8)]


def collect_sprites(e, seen):
    m, r = e.mem, e.regs
    p = (r[0x2C] << 8) | r[0x30]
    wm = 0
    for _ in range(40):
        dl = (m[p + 1] << 8) | m[p + 2]
        p += 3
        q = dl
        for _ in range(40):
            lo, b1 = m[q], m[q + 1]
            if (b1 & 0x5F) == 0:
                break
            if (b1 & 0x1F) == 0:
                wm, ind, hi, pw = b1 >> 7, b1 & 0x20, m[q + 2], m[q + 3]
                q += 5
            else:
                ind, pw, hi = 0, b1, m[q + 2]
                q += 4
            if ind or not (0xD8 <= hi <= 0xF7):   # skip tile runs and title-screen RAM garbage
                continue
            w = (32 - (pw & 31)) & 31 or 32
            seen.setdefault((lo, w, wm), pw >> 5)


def add_player_frames(seen):
    """The player is 18 head/legs pairs at $E02F + 8*frame; make sure all are in the sheet."""
    for f in range(PLAYER_FRAMES):
        for k in (0, 4):
            seen.setdefault((PLAYER_BASE + 8 * f + k, 4, 1), 4 if 8 <= f <= 11 else 0)


def sprite_sheet(seen, pals, img_path, json_path):
    items = sorted(seen.items())
    cells = []
    for (lo, w, wm), palno in items:
        pw = w * (8 if wm == 0 else 4)
        im = Image.new('RGBA', (pw, 8), (0, 0, 0, 0))
        px = im.load()
        for line in range(8):
            page = GFX + (7 - line) * 256
            x = 0
            for i in range(w):
                b = rd(page + ((lo + i) & 0xFF))
                if wm == 0:        # 320A: 8 px, colour 2 of the palette
                    for bit in range(8):
                        if b & (0x80 >> bit):
                            px[x + bit, line] = PAL[pals[palno][2]] + (255,)
                    x += 8
                else:              # 320C: 4 px, per-pixel-pair palette bits
                    for n in range(4):
                        if b & (0x80 >> n):
                            pp = (palno & 4) | ((b >> (2 if n < 2 else 0)) & 3)
                            px[x + n, line] = PAL[pals[pp][2]] + (255,)
                    x += 4
        cells.append(((lo, w, wm, palno), im))
    sheet_w = 256
    x = y = rowh = 0
    placed = []
    for key, im in cells:
        if x + im.width > sheet_w:
            x, y = 0, y + rowh + 2
            rowh = 0
        placed.append((key, im, x, y))
        x += im.width + 2
        rowh = max(rowh, im.height)
    sheet = Image.new('RGBA', (sheet_w, y + rowh), (0, 0, 0, 0))
    catalog = []
    for (lo, w, wm, palno), im, sx, sy in placed:
        sheet.paste(im, (sx, sy))
        catalog.append({'addr': '$%04X' % (GFX + lo), 'bytes': w, 'mode': '320C' if wm else '320A',
                        'palette': palno, 'x': sx, 'y': sy, 'w': im.width, 'h': im.height})
    sheet.save(img_path)
    index = {(c['addr'], c['mode']): i for i, c in enumerate(catalog)}
    frames = [[index[('$%04X' % (GFX + PLAYER_BASE + 8 * f + k), '320C')] for k in (0, 4)]
              for f in range(PLAYER_FRAMES)]
    json.dump({'note': 'Rows are 8 px; taller objects are stacked entries. Pixels are 320-mode (half width). '
                       'playerFrames[f] = [head, legs] sprite indexes; frame numbers in docs/PHYSICS.md.',
               'playerFrames': frames, 'sprites': catalog}, open(json_path, 'w'), indent=1)
    return len(catalog)


def main():
    global ROM
    ROM = a7800emu.load_rom(sys.argv[1])
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), '..')
    for d in ('assets', 'data', 'docs/rooms'):
        os.makedirs(os.path.join(out, d), exist_ok=True)

    tile_atlas(os.path.join(out, 'assets/tiles.png'))

    e = Emu()
    boot(e)
    base = snapshot(e)
    seen, pals, shots = {}, {}, []
    random.seed(1)
    for r in range(NUM_ROOMS):
        restore(e, base)
        load_room(e, r)
        pals[r] = palette_regs(e)
        img = e.render()
        img.save(os.path.join(out, 'docs/rooms/chamber%d.png' % r))
        shots.append(img)
        for f in range(300):  # wander so the player/enemy animation frames show up
            if f % 20 == 0:
                e.joy = random.choice([0x7F, 0xBF, 0xDF, 0xEF, 0xFF])
                e.fire = random.random() < 0.3
            e.run_frame()
            collect_sprites(e, seen)
        e.joy, e.fire = 0xFF, False

    w, h = shots[0].size
    sheet = Image.new('RGB', (w * 4, h * 3))
    for i, im in enumerate(shots):
        sheet.paste(im, ((i % 4) * w, (i // 4) * h))
    sheet.save(os.path.join(out, 'docs/rooms/sheet.png'))

    add_player_frames(seen)
    n = sprite_sheet(seen, pals[0], os.path.join(out, 'assets/sprites.png'),
                     os.path.join(out, 'assets/sprites.json'))

    rooms = rooms_data(pals)
    json.dump({'tileSize': [16, 8], 'mapSize': [MAP_W, MAP_H],
               'note': 'tiles[row][col] indexes assets/tiles.png (16 per row). Tiles are 1bpp; '
                       'draw them in colorRGB. Object codes: see docs/ROM_NOTES.md.',
               'rooms': rooms}, open(os.path.join(out, 'data/rooms.json'), 'w'), indent=1)
    print('tiles: 128, sprites: %d, rooms: %d, doors: %d' % (n, len(rooms), sum(len(r['doors']) for r in rooms)))


if __name__ == '__main__':
    main()
