"""Build the Spiral Shift sideload package: dist/spiral-shift-roku.zip.

Stages dist/spiral-shift-roku/ from dash/roku/ (manifest, source/*.brs, levels/*.txt) plus
generated assets:
  images/ball, triangle, square, diamond.png   player frames, 72 px squares (main.brs);
                                               nose, fin.png: rocket parts for the corner animation
  images/spike_N, pad_N.png                    turned for side N; orb.png; icons, splash
  sounds/level1-10.mp3                         8-bar chiptune loops; die, complete, rocket,
                                               checkpoint.wav

Also writes the store listing artwork (poster 540 x 405, splash 1920 x 1080) to dist/store/.

Needs Pillow and lameenc (pip install pillow lameenc). Usage: python3 dash/tools/build.py
Sideload: open http://<roku-ip> (developer mode) and upload the zip.
"""
import math
import os
import random
import shutil
import struct
import wave
import zipfile

import lameenc
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', 'roku')
DIST = os.path.join(HERE, '..', '..', 'dist')
STAGE = os.path.join(DIST, 'spiral-shift-roku')
SS = 4          # supersampling for smooth edges
RATE = 22050


# ---- images ----
# One block is 48 px. Player frames are 72 px squares (room to rotate); spikes and pads come
# in four turns, one per side of the screen (see main.brs).

BLOCK, CELL = 48, 72
BALL, TRI, SQUARE, DIAMOND = (255, 210, 63), (255, 106, 213), (77, 214, 255), (124, 255, 107)


def canvas(w, h):
    return Image.new('RGBA', (w * SS, h * SS), (0, 0, 0, 0))


def down(img):
    return img.resize((img.width // SS, img.height // SS), Image.LANCZOS)


def sheet(frames, per_row):
    rows = (len(frames) + per_row - 1) // per_row
    out = Image.new('RGBA', (CELL * per_row, CELL * rows), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        x, y = (i % per_row) * CELL, (i // per_row) * CELL
        out.paste(f, (x + (CELL - f.width) // 2, y + (CELL - f.height) // 2), f)
    return out


def turned(img, angle):
    """img (supersampled, CELL-sized canvas) turned counter-clockwise, then shrunk."""
    return down(img.rotate(angle, resample=Image.BICUBIC))


def ball():
    """Yellow ball with a dark band, so it can be seen rolling."""
    img = canvas(CELL, CELL)
    d = ImageDraw.Draw(img)
    S, c, r = SS, CELL // 2, 23
    d.ellipse([(c - r) * S, (c - r) * S, (c + r) * S, (c + r) * S], fill=(0, 0, 0, 255))
    d.ellipse([(c - r + 3) * S, (c - r + 3) * S, (c + r - 3) * S, (c + r - 3) * S], fill=BALL + (255,))
    d.rectangle([(c - r + 3) * S, (c - 4) * S, (c + r - 3) * S, (c + 4) * S], fill=(200, 120, 20, 255))
    d.ellipse([(c - 6) * S, (c - 6) * S, (c + 6) * S, (c + 6) * S], fill=(255, 250, 220, 255))
    return img


def triangle():
    """Pink arrowhead pointing right (the run direction on the bottom edge)."""
    img = canvas(CELL, CELL)
    d = ImageDraw.Draw(img)
    S, c = SS, CELL // 2
    d.polygon([((c - 24) * S, (c - 21) * S), ((c + 25) * S, c * S), ((c - 24) * S, (c + 21) * S)], fill=(0, 0, 0, 255))
    d.polygon([((c - 19) * S, (c - 14) * S), ((c + 16) * S, c * S), ((c - 19) * S, (c + 14) * S)], fill=TRI + (255,))
    d.polygon([((c - 12) * S, (c - 5) * S), ((c + 2) * S, c * S), ((c - 12) * S, (c + 5) * S)], fill=(255, 230, 248, 255))
    return img


def square():
    """Cyan square with nested squares: the same every quarter turn."""
    img = canvas(CELL, CELL)
    d = ImageDraw.Draw(img)
    S, c = SS, CELL // 2
    for half, col in ((24, (0, 0, 0)), (21, SQUARE), (13, (0, 0, 0)), (10, (200, 245, 255)), (4, (0, 0, 0))):
        d.rectangle([(c - half) * S, (c - half) * S, (c + half) * S - 1, (c + half) * S - 1], fill=col + (255,))
    return img


def diamond():
    """Green diamond, long along the run direction."""
    img = canvas(CELL, CELL)
    d = ImageDraw.Draw(img)
    S, c = SS, CELL // 2
    d.polygon([((c - 26) * S, c * S), (c * S, (c - 17) * S), ((c + 26) * S, c * S), (c * S, (c + 17) * S)], fill=(0, 0, 0, 255))
    d.polygon([((c - 20) * S, c * S), (c * S, (c - 12) * S), ((c + 20) * S, c * S), (c * S, (c + 12) * S)], fill=DIAMOND + (255,))
    d.polygon([((c - 8) * S, c * S), (c * S, (c - 5) * S), ((c + 8) * S, c * S), (c * S, (c + 5) * S)], fill=(230, 255, 225, 255))
    return img


def nose():
    """Red nose cone pointing right, for the corner animation's rocket (main.brs)."""
    img = canvas(BLOCK, BLOCK)
    d = ImageDraw.Draw(img)
    S = SS
    d.polygon([(6 * S, 8 * S), (44 * S, 24 * S), (6 * S, 40 * S)], fill=(0, 0, 0, 255))
    d.polygon([(9 * S, 13 * S), (38 * S, 24 * S), (9 * S, 35 * S)], fill=(230, 57, 70, 255))
    d.rectangle([4 * S, 8 * S, 9 * S, 40 * S], fill=(245, 245, 250, 255), outline=(0, 0, 0, 255), width=S)
    return img


def fin():
    """The rocket's upper fin (rocket pointing right): swept back and up."""
    img = canvas(BLOCK, BLOCK)
    d = ImageDraw.Draw(img)
    S = SS
    d.polygon([(10 * S, 40 * S), (4 * S, 6 * S), (40 * S, 40 * S)], fill=(0, 0, 0, 255))
    d.polygon([(13 * S, 37 * S), (9 * S, 14 * S), (33 * S, 37 * S)], fill=(230, 57, 70, 255))
    return img


def ball_frames():
    b = ball()
    return [turned(b, -a) for a in range(0, 360, 10)]                # clockwise, 10 degree steps


def stage_frames(img, angles):
    # row s: the shape on side s (turned 90 degrees per side), then tilted by each angle
    return [turned(img, 90 * s + a) for s in range(4) for a in angles]


def spike():
    img = canvas(BLOCK, BLOCK)
    d = ImageDraw.Draw(img)
    S = SS
    d.polygon([(2 * S, 48 * S), (24 * S, 2 * S), (46 * S, 48 * S)], fill=(255, 255, 255, 255))
    d.polygon([(7 * S, 46 * S), (24 * S, 10 * S), (41 * S, 46 * S)], fill=(12, 12, 22, 255))
    return img


def pad():
    img = canvas(BLOCK, BLOCK)
    d = ImageDraw.Draw(img)
    S = SS
    d.pieslice([5 * S, 35 * S, 43 * S, 61 * S], 180, 360, fill=(255, 225, 77, 255))
    d.rectangle([3 * S, 45 * S, 45 * S, 48 * S], fill=(255, 225, 77, 255))
    return img


def orb():
    img = canvas(BLOCK, BLOCK)
    d = ImageDraw.Draw(img)
    S = SS
    d.ellipse([3 * S, 3 * S, 45 * S, 45 * S], fill=(255, 225, 77, 90))
    d.ellipse([10 * S, 10 * S, 38 * S, 38 * S], fill=(255, 225, 77, 255))
    d.ellipse([16 * S, 16 * S, 32 * S, 32 * S], fill=(255, 255, 220, 255))
    return down(img)


def poster(w, h):
    """The four shapes running around the edges of a screen."""
    img = Image.new('RGBA', (w * 2, h * 2), (42, 72, 232, 255))
    d = ImageDraw.Draw(img)
    W, Hh = img.size
    e = max(4, Hh // 14)
    d.rectangle([0, 0, W, Hh], outline=(24, 41, 143, 255), width=e)
    d.rectangle([0, Hh - e, W, Hh], fill=(24, 41, 143, 255))
    size = int(Hh * 0.3)
    def put(shape, angle, x, y):
        s = shape.rotate(angle, resample=Image.BICUBIC).resize((size, size), Image.LANCZOS)
        img.alpha_composite(s, (int(x - size / 2), int(y - size / 2)))
    put(ball(), 0, W * 0.22, Hh - e - size * 0.33)
    put(triangle(), 90, W - e - size * 0.33, Hh * 0.55)
    put(square(), 0, W * 0.62, e + size * 0.33)
    put(diamond(), -90, e + size * 0.33, Hh * 0.38)
    sp = spike().resize((size // 2, size // 2), Image.LANCZOS)
    for i in range(3):
        img.alpha_composite(sp, (int(W * 0.42) + i * size // 2, Hh - e - size // 2))
    # the name, if a bold font is available (DejaVu ships with most Linux systems)
    try:
        font = ImageFont.truetype('DejaVuSans-Bold.ttf', int(Hh * 0.115))
    except OSError:
        font = None
    if font:
        text = 'SPIRAL SHIFT'
        tw = d.textlength(text, font=font)
        x, y = (W - tw) / 2, Hh * 0.40
        d.text((x + Hh * 0.008, y + Hh * 0.008), text, font=font, fill=(0, 0, 0, 255))
        d.text((x, y), text, font=font, fill=(255, 255, 255, 255))
    return img.resize((w, h), Image.LANCZOS)


# ---- sound ----

NOTE = {n: i for i, n in enumerate(['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'])}


def freq(name, octave):
    return 440.0 * 2 ** ((NOTE[name] + 12 * (octave + 1) - 69) / 12)


def write_wav(path, samples):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm(samples))


def pcm(samples):
    return b''.join(struct.pack('<h', max(-32767, min(32767, int(s * 32767)))) for s in samples)


def write_mp3(path, samples):
    enc = lameenc.Encoder()
    enc.set_bit_rate(96)
    enc.set_in_sample_rate(RATE)
    enc.set_channels(1)
    enc.set_quality(2)
    with open(path, 'wb') as f:
        f.write(enc.encode(pcm(samples)) + enc.flush())


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


def sfx_rocket():
    """A whoosh: noise through a rising, then fading, filter."""
    rng = random.Random(11)
    n = int(RATE * 0.6)
    out, lp = [], 0.0
    for i in range(n):
        t = i / n
        cut = 0.02 + 0.3 * t
        lp += cut * (rng.uniform(-1, 1) - lp)
        out.append(lp * 2.2 * min(1, t * 8) * (1 - t) ** 1.5)
    return out


def sfx_checkpoint():
    out = []
    for f in (freq('G', 5), freq('D', 6)):
        n = int(RATE * 0.09)
        out += [0.3 * (1 if (i * f / RATE) % 1 < 0.5 else -1) * math.exp(-i / (RATE * 0.08)) for i in range(n)]
    return out


# One loop per level, faster and darker as the levels get harder:
# (bpm, four chords, 16-step lead over chord tones: 0-2 = root/third/fifth, 3-5 an octave up)
I, VI, IV, V = ('C', 'E', 'G'), ('A', 'C', 'E'), ('F', 'A', 'C'), ('G', 'B', 'D')
SONGS = [
    (124, [I, VI, IV, V], [0, None, 1, None, 2, 1, 3, None, 2, None, 1, None, 0, 1, 2, None]),
    (128, [IV, V, I, VI], [2, None, 3, 2, 1, None, 0, None, 1, 2, 3, None, 4, None, 3, None]),
    (132, [VI, IV, I, V], [3, 2, 1, 2, 0, None, 1, 2, 3, None, 4, 3, 2, None, 1, None]),
    (136, [('D', 'F#', 'A'), ('B', 'D', 'F#'), ('G', 'B', 'D'), ('A', 'C#', 'E')],
     [0, 2, 4, 2, 1, 3, 5, 3, 0, 2, 4, 2, 1, None, 0, None]),
    (140, [('A', 'C', 'E'), ('F', 'A', 'C'), ('C', 'E', 'G'), ('G', 'B', 'D')],
     [3, None, 3, 4, 5, None, 4, 3, 2, None, 2, 1, 0, None, 1, 2]),
    (144, [('E', 'G', 'B'), ('C', 'E', 'G'), ('G', 'B', 'D'), ('D', 'F#', 'A')],
     [0, 1, 2, 3, 4, 3, 2, 1, 0, None, 2, None, 4, None, 5, None]),
    (148, [('D', 'F', 'A'), ('A#', 'D', 'F'), ('F', 'A', 'C'), ('C', 'E', 'G')],
     [0, 1, 2, 3, 2, 1, 0, None, 3, 4, 5, 4, 3, None, 2, 1]),
    (152, [('B', 'D', 'F#'), ('G', 'B', 'D'), ('D', 'F#', 'A'), ('A', 'C#', 'E')],
     [5, 4, 3, 4, 5, None, 3, None, 2, 1, 0, 1, 2, None, 4, None]),
    (156, [('F', 'G#', 'C'), ('C#', 'F', 'G#'), ('G#', 'C', 'D#'), ('D#', 'G', 'A#')],
     [0, 3, 1, 4, 2, 5, 1, 4, 0, 3, 2, None, 5, 4, 3, None]),
    (160, [('C', 'D#', 'G'), ('G#', 'C', 'D#'), ('D#', 'G', 'A#'), ('A#', 'D', 'F')],
     [0, 2, 3, 5, 3, 2, 0, 2, 1, 3, 4, 3, 1, None, 5, None]),
]


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
    sheet(ball_frames(), 18).save(img('ball.png'))
    sheet(stage_frames(triangle(), range(-40, 45, 5)), 17).save(img('triangle.png'))
    sheet([turned(square(), -a) for a in range(0, 90, 5)], 18).save(img('square.png'))
    sheet(stage_frames(diamond(), (-45, 0, 45)), 3).save(img('diamond.png'))
    parts = Image.new('RGBA', (BLOCK * 4, BLOCK), (0, 0, 0, 0))
    fins = Image.new('RGBA', (BLOCK * 4, BLOCK * 2), (0, 0, 0, 0))
    for side in range(4):
        parts.paste(down(nose().rotate(90 * side)), (BLOCK * side, 0))
        fins.paste(down(fin().rotate(90 * side)), (BLOCK * side, 0))
        fins.paste(down(fin().transpose(Image.FLIP_TOP_BOTTOM).rotate(90 * side)), (BLOCK * side, BLOCK))
    parts.save(img('nose.png'))
    fins.save(img('fin.png'))
    for side in range(4):
        down(spike().rotate(90 * side)).save(img(f'spike_{side}.png'))
        down(pad().rotate(90 * side)).save(img(f'pad_{side}.png'))
    orb().save(img('orb.png'))
    poster(290, 218).save(img('icon_hd.png'))
    poster(214, 144).save(img('icon_sd.png'))
    poster(1280, 720).save(img('splash_hd.png'))
    # store listing artwork for the developer dashboard (not in the package)
    store = os.path.join(DIST, 'store')
    os.makedirs(store, exist_ok=True)
    poster(540, 405).convert('RGB').save(os.path.join(store, 'poster_540x405.png'))
    poster(1920, 1080).convert('RGB').save(os.path.join(store, 'splash_1920x1080.png'))

    snd = lambda name: os.path.join(STAGE, 'sounds', name)
    for i, (bpm, chords, lead) in enumerate(SONGS):
        write_mp3(snd(f'level{i + 1}.mp3'), song(bpm, chords, lead, i + 1))
    write_wav(snd('die.wav'), sfx_die())
    write_wav(snd('complete.wav'), sfx_complete())
    write_wav(snd('checkpoint.wav'), sfx_checkpoint())
    write_wav(snd('rocket.wav'), sfx_rocket())

    out = os.path.join(DIST, 'spiral-shift-roku.zip')
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for base, _, files in os.walk(STAGE):
            for f in sorted(files):
                path = os.path.join(base, f)
                z.write(path, os.path.relpath(path, STAGE))
    print(f'wrote {os.path.relpath(out)} ({os.path.getsize(out)} bytes)')


if __name__ == '__main__':
    main()
