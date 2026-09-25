"""Build the Roku sideload package: dist/downland-roku.zip.

Stages dist/roku/ from roku/manifest + roku/source/*.brs plus everything generated from the
extracted data (the same files the web port uses):
  images/chamber_N.png   chamber backgrounds (terrain only; items and doors are drawn live)
  images/title_0/1.png   the two title-screen colour phases
  images/ink_RRGGBB.png  tiles.png pre-tinted in each palette colour (glyphs, items, doors)
  images/sprites.png     sprite sheet (already in colour)
  images/icon_*.png, splash_hd.png
  data/*.json            rooms, sprites, sounds
  sounds/*.wav           effects rendered by tools/render_sounds.mjs

Needs Pillow and node. Usage: python3 tools/build_roku.py
Sideload: open http://<roku-ip> (developer mode) and upload the zip.
"""
import json
import os
import shutil
import subprocess
import zipfile

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
DIST = os.path.join(ROOT, 'dist')
STAGE = os.path.join(DIST, 'roku')
TILE_W, TILE_H, MAP_W, MAP_H = 16, 8, 20, 24


def rgb(hexstr):
    v = int(hexstr[1:], 16)
    return (v >> 16, (v >> 8) & 255, v & 255)


def tile_masks(atlas):
    per_row = atlas.width // TILE_W
    count = per_row * (atlas.height // TILE_H)
    px = atlas.load()
    masks = []
    for n in range(count):
        ox, oy = (n % per_row) * TILE_W, (n // per_row) * TILE_H
        masks.append([[px[ox + x, oy + y][3] > 127 for x in range(TILE_W)] for y in range(TILE_H)])
    return masks


def background(defn, palettes, masks):
    """Same pixels as the web port's Room surface (src/game/room.js)."""
    img = Image.new('RGBA', (MAP_W * TILE_W, MAP_H * TILE_H), (0, 0, 0, 255))
    px = img.load()
    for row in range(MAP_H):
        for col in range(MAP_W):
            t = defn['tiles'][row][col]
            if not t:
                continue
            c = rgb(palettes[defn['tilePalette'][row][col]][2]) + (255,)
            for y in range(TILE_H):
                for x in range(TILE_W):
                    if masks[t][y][x]:
                        px[col * TILE_W + x, row * TILE_H + y] = c
    return img


def icon(src, w, h):
    """Title art letterboxed on black, nearest-neighbour."""
    scale = min(w / src.width, h / src.height)
    art = src.resize((int(src.width * scale), int(src.height * scale)), Image.NEAREST)
    out = Image.new('RGBA', (w, h), (0, 0, 0, 255))
    out.paste(art, ((w - art.width) // 2, (h - art.height) // 2))
    return out


def main():
    shutil.rmtree(STAGE, ignore_errors=True)
    for d in ('source', 'images', 'data', 'sounds'):
        os.makedirs(os.path.join(STAGE, d))
    shutil.copy(os.path.join(ROOT, 'roku', 'manifest'), STAGE)
    for f in sorted(os.listdir(os.path.join(ROOT, 'roku', 'source'))):
        if f.endswith('.brs'):
            shutil.copy(os.path.join(ROOT, 'roku', 'source', f), os.path.join(STAGE, 'source'))
    for src, dst in (('data/rooms.json', 'data'), ('data/sounds.json', 'data'),
                     ('assets/sprites.json', 'data'), ('assets/sprites.png', 'images')):
        shutil.copy(os.path.join(ROOT, src), os.path.join(STAGE, dst))

    rooms = json.load(open(os.path.join(ROOT, 'data', 'rooms.json')))
    atlas = Image.open(os.path.join(ROOT, 'assets', 'tiles.png')).convert('RGBA')
    masks = tile_masks(atlas)
    img = os.path.join(STAGE, 'images')

    colours = set()
    for defn in rooms['rooms']:
        background(defn, defn['palettesRGB'], masks).save(os.path.join(img, f"chamber_{defn['id']}.png"))
        colours.update(p[2] for p in defn['palettesRGB'])
    title = rooms['title']
    for i, (p0, p7) in enumerate(title['flashRGB']):
        pal = [p[:] for p in title['palettesRGB']]
        pal[0][2], pal[7][2] = p0, p7
        background(title, pal, masks).save(os.path.join(img, f'title_{i}.png'))
        colours.update(p[2] for p in pal)
    colours.discard('#000000')
    colours.add('#FFFFFF')      # main.brs key-code overlay

    alpha = atlas.getchannel('A')
    for c in sorted(colours):
        ink = Image.new('RGBA', atlas.size, rgb(c) + (255,))
        ink.putalpha(alpha)
        ink.save(os.path.join(img, f'ink_{c[1:].upper()}.png'))

    art = Image.open(os.path.join(img, 'title_1.png'))
    icon(art, 290, 218).save(os.path.join(img, 'icon_hd.png'))
    icon(art, 214, 144).save(os.path.join(img, 'icon_sd.png'))
    icon(art, 1280, 720).save(os.path.join(img, 'splash_hd.png'))

    subprocess.run(['node', os.path.join(ROOT, 'tools', 'render_sounds.mjs'),
                    os.path.join(STAGE, 'sounds')], check=True)

    out = os.path.join(DIST, 'downland-roku.zip')
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for base, _, files in os.walk(STAGE):
            for f in sorted(files):
                path = os.path.join(base, f)
                z.write(path, os.path.relpath(path, STAGE))
    print(f'{len(colours)} ink colours; wrote {os.path.relpath(out, ROOT)} ({os.path.getsize(out)} bytes)')


if __name__ == '__main__':
    main()
