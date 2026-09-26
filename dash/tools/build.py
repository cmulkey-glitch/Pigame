"""Build the Cube Dash sideload package: dist/cube-dash-roku.zip.

Stages dist/cube-dash-roku/ from dash/roku/ (manifest, source/*.brs, levels/*.txt) plus
generated assets:
  images/cube.png, ship.png   rotation frames, 90 px squares in a strip
  images/spike*.png, orb.png, pad.png, portal_*.png, icon_*.png, splash_hd.png
  sounds/level1-3.wav         8-bar chiptune loops; die.wav, complete.wav

Needs Pillow. Usage: python3 dash/tools/build.py
Sideload: open http://<roku-ip> (developer mode) and upload the zip.
"""
import math
import os
import random
import shutil
import struct
import wave
import zipfile

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', 'roku')
DIST = os.path.join(HERE, '..', '..', 'dist')
STAGE = os.path.join(DIST, 'cube-dash-roku')
SS = 4          # supersampling for smooth edges
RATE = 22050


# ---- images ----

def canvas(w, h):
    return Image.new('RGBA', (w * SS, h * SS), (0, 0, 0, 0))


def down(img):
    return img.resize((img.width // SS, img.height // SS), Image.LANCZOS)


def cube_face(size=60):
    """The player: green square, cyan inner square, two eyes."""
    img = canvas(size, size)
    d = ImageDraw.Draw(img)
    s = size * SS
    d.rectangle([0, 0, s - 1, s - 1], fill=(0, 0, 0, 255))
    d.rectangle([3 * SS, 3 * SS, s - 3 * SS - 1, s - 3 * SS - 1], fill=(124, 255, 107, 255))
    d.rectangle([15 * SS, 15 * SS, s - 15 * SS - 1, s - 15 * SS - 1], fill=(0, 0, 0, 255))
    d.rectangle([18 * SS, 18 * SS, s - 18 * SS - 1, s - 18 * SS - 1], fill=(80, 230, 255, 255))
    for ex in (22, 34):
        d.rectangle([ex * SS, 24 * SS, (ex + 4) * SS, 30 * SS], fill=(0, 0, 0, 255))
    return img


def strip(frames, cell=90):
    out = Image.new('RGBA', (cell * len(frames), cell), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        out.paste(f, (i * cell + (cell - f.width) // 2, (cell - f.height) // 2), f)
    return out


def cube_frames():
    face = cube_face()
    # clockwise, 0..85 degrees; a square repeats every 90
    return [down(face.rotate(-a, resample=Image.BICUBIC, expand=True)) for a in range(0, 90, 5)]


def ship_body():
    img = canvas(64, 64)
    d = ImageDraw.Draw(img)
    S = SS
    hull = [(4 * S, 30 * S), (60 * S, 38 * S), (52 * S, 50 * S), (8 * S, 52 * S)]
    d.polygon(hull, fill=(0, 0, 0, 255))
    inner = [(9 * S, 34 * S), (52 * S, 40 * S), (48 * S, 46 * S), (11 * S, 48 * S)]
    d.polygon(inner, fill=(255, 106, 213, 255))
    # the cube rides in the cockpit
    mini = cube_face().resize((26 * S, 26 * S), Image.LANCZOS)
    img.paste(mini, (18 * S, 8 * S), mini)
    return img


def ship_frames():
    body = ship_body()
    # -40..40 degrees, positive = nose up (counter-clockwise for a ship facing right)
    return [down(body.rotate(a, resample=Image.BICUBIC, expand=True)) for a in range(-40, 45, 5)]


def spike(flip=False):
    img = canvas(60, 60)
    d = ImageDraw.Draw(img)
    S = SS
    d.polygon([(2 * S, 60 * S), (30 * S, 2 * S), (58 * S, 60 * S)], fill=(255, 255, 255, 255))
    d.polygon([(8 * S, 57 * S), (30 * S, 12 * S), (52 * S, 57 * S)], fill=(12, 12, 22, 255))
    img = down(img)
    return img.transpose(Image.FLIP_TOP_BOTTOM) if flip else img


def orb():
    img = canvas(60, 60)
    d = ImageDraw.Draw(img)
    S = SS
    d.ellipse([4 * S, 4 * S, 56 * S, 56 * S], fill=(255, 225, 77, 90))
    d.ellipse([12 * S, 12 * S, 48 * S, 48 * S], fill=(255, 225, 77, 255))
    d.ellipse([20 * S, 20 * S, 40 * S, 40 * S], fill=(255, 255, 220, 255))
    return down(img)


def pad():
    img = canvas(60, 60)
    d = ImageDraw.Draw(img)
    S = SS
    d.pieslice([6 * S, 44 * S, 54 * S, 76 * S], 180, 360, fill=(255, 225, 77, 255))
    d.rectangle([4 * S, 56 * S, 56 * S, 60 * S], fill=(255, 225, 77, 255))
    return down(img)


def portal(rgb):
    img = canvas(60, 180)
    d = ImageDraw.Draw(img)
    S = SS
    d.ellipse([8 * S, 2 * S, 52 * S, 178 * S], outline=rgb + (255,), width=8 * S)
    d.ellipse([18 * S, 16 * S, 42 * S, 164 * S], outline=rgb + (140,), width=4 * S)
    return down(img)


def poster(w, h):
    img = Image.new('RGBA', (w, h), (42, 72, 232, 255))
    d = ImageDraw.Draw(img)
    ground = int(h * 0.78)
    d.rectangle([0, ground, w, h], fill=(26, 47, 168, 255))
    d.rectangle([0, ground, w, ground + max(1, h // 200)], fill=(255, 255, 255, 200))
    size = int(h * 0.3)
    cube = cube_face().resize((size, size), Image.LANCZOS).rotate(-20, resample=Image.BICUBIC, expand=True)
    img.paste(cube, (int(w * 0.18), ground - int(size * 1.6)), cube)
    sp = spike().resize((size, size), Image.LANCZOS)
    for i in range(2):
        img.paste(sp, (int(w * 0.55) + i * size, ground - size), sp)
    return img


# ---- sound ----

NOTE = {n: i for i, n in enumerate(['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'])}


def freq(name, octave):
    return 440.0 * 2 ** ((NOTE[name] + 12 * (octave + 1) - 69) / 12)


def write_wav(path, samples):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(struct.pack('<h', max(-32767, min(32767, int(s * 32767)))) for s in samples))


def song(bpm, chords, lead, seed):
    """8 bars of 16ths: kick on beats, noise hats, square bass on the chord root, pulse lead."""
    rng = random.Random(seed)
    step = int(RATE * 60 / bpm / 4)
    total = step * 16 * 8
    out = [0.0] * total
    noise = [rng.uniform(-1, 1) for _ in range(step)]

    def add(start, n, fn):
        for i in range(min(n, total - start)):
            out[start + i] += fn(i)

    for bar in range(8):
        root, third, fifth = chords[bar % len(chords)]
        for s16 in range(16):
            t0 = (bar * 16 + s16) * step
            if s16 % 4 == 0:                        # kick: falling sine
                add(t0, step * 2, lambda i: 0.55 * math.sin(2 * math.pi * (50 + 90 * math.exp(-i / 500)) * i / RATE) * math.exp(-i / 2500))
            if s16 % 8 == 4:                        # snare: noise burst
                add(t0, step * 2, lambda i: 0.22 * noise[i % step] * math.exp(-i / 1800))
            if s16 % 2 == 1:                        # hat
                add(t0, step // 2, lambda i: 0.07 * noise[(i * 7) % step] * math.exp(-i / 300))
            f = freq(root, 2) * (2 if s16 % 4 == 2 else 1)
            add(t0, step, lambda i, f=f: 0.13 * (1 if (i * f / RATE) % 1 < 0.5 else -1) * (1 - i / step) ** 0.5)
            note = lead[(bar * 16 + s16) % len(lead)]
            if note is not None:
                tone = [root, third, fifth][note % 3]
                fl = freq(tone, 4 + note // 3)
                add(t0, step, lambda i, fl=fl: 0.09 * (1 if (i * fl / RATE) % 1 < 0.25 else -1) * math.exp(-i / 3000))
    peak = max(abs(v) for v in out) or 1
    return [v / peak * 0.8 for v in out]


def sfx_die():
    rng = random.Random(7)
    n = int(RATE * 0.5)
    return [0.8 * rng.uniform(-1, 1) * math.exp(-i / (RATE * 0.12)) for i in range(n)]


def sfx_complete():
    out = []
    for k, f in enumerate([freq('C', 5), freq('E', 5), freq('G', 5), freq('C', 6)]):
        n = int(RATE * (0.12 if k < 3 else 0.5))
        out += [0.35 * (1 if (i * f / RATE) % 1 < 0.5 else -1) * math.exp(-i / (RATE * 0.3)) for i in range(n)]
    return out


SONGS = {
    'level1': (128, [('C', 'E', 'G'), ('A', 'C', 'E'), ('F', 'A', 'C'), ('G', 'B', 'D')],
               [0, None, 1, None, 2, 1, 3, None, 2, None, 1, None, 0, 1, 2, None], 1),
    'level2': (140, [('A', 'C', 'E'), ('F', 'A', 'C'), ('C', 'E', 'G'), ('G', 'B', 'D')],
               [3, 2, 1, 2, 0, None, 1, 2, 3, None, 4, 3, 2, None, 1, None], 2),
    'level3': (150, [('D', 'F', 'A'), ('A#', 'D', 'F'), ('F', 'A', 'C'), ('C', 'E', 'G')],
               [0, 1, 2, 3, 2, 1, 0, None, 3, 4, 5, 4, 3, None, 2, 1], 3),
}


def main():
    shutil.rmtree(STAGE, ignore_errors=True)
    for d in ('source', 'levels', 'images', 'sounds'):
        os.makedirs(os.path.join(STAGE, d))
    shutil.copy(os.path.join(SRC, 'manifest'), STAGE)
    for sub, ext in (('source', '.brs'), ('levels', '.txt')):
        for f in sorted(os.listdir(os.path.join(SRC, sub))):
            if f.endswith(ext):
                shutil.copy(os.path.join(SRC, sub, f), os.path.join(STAGE, sub))

    img = lambda name: os.path.join(STAGE, 'images', name)
    strip(cube_frames()).save(img('cube.png'))
    strip(ship_frames()).save(img('ship.png'))
    spike().save(img('spike.png'))
    spike(flip=True).save(img('spike_down.png'))
    orb().save(img('orb.png'))
    pad().save(img('pad.png'))
    portal((255, 106, 213)).save(img('portal_ship.png'))
    portal((124, 255, 107)).save(img('portal_cube.png'))
    poster(290, 218).save(img('icon_hd.png'))
    poster(214, 144).save(img('icon_sd.png'))
    poster(1280, 720).save(img('splash_hd.png'))

    snd = lambda name: os.path.join(STAGE, 'sounds', name)
    for name, (bpm, chords, lead, seed) in SONGS.items():
        write_wav(snd(name + '.wav'), song(bpm, chords, lead, seed))
    write_wav(snd('die.wav'), sfx_die())
    write_wav(snd('complete.wav'), sfx_complete())

    out = os.path.join(DIST, 'cube-dash-roku.zip')
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for base, _, files in os.walk(STAGE):
            for f in sorted(files):
                path = os.path.join(base, f)
                z.write(path, os.path.relpath(path, STAGE))
    print(f'wrote {os.path.relpath(out)} ({os.path.getsize(out)} bytes)')


if __name__ == '__main__':
    main()
