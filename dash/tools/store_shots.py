"""Store screenshots: dist/store/screenshots/spiral-shift-*.png at 1920 x 1080, plus overview.png.

The menu, each shape in play partway through a busier level (its stored solution from
dash/tests/solutions/ replayed with the real game code up to that point), a corner rocket, the
finale and the spiral complete screen, all rendered by dash/tools/shot.py.

Usage: python3 dash/tools/build.py && python3 dash/tools/store_shots.py
"""
import os
import subprocess
import sys
import tempfile

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
DASH = os.path.join(HERE, '..')
DIST = os.path.join(DASH, '..', 'dist')
OUT = os.path.join(DIST, 'store', 'screenshots')

# (level, side, how far into the side, picture name)
PLAY = [(3, 0, 0.42, '2-ball'), (5, 1, 0.55, '3-triangle'), (4, 2, 0.50, '4-square'),
        (6, 3, 0.47, '5-diamond')]
# from dash/tests/shots.brs, rendered into dist/shots/
SCREENS = [('01-menu', '1-menu'), ('33-corner', '6-corner-rocket'), ('53-finale', '7-finale'),
           ('59-spiral-complete', '8-spiral-complete')]

PLAY_TO = '''
' Replay stored inputs (button 0 / 1, or steer -1 / 0 / 1) on side s of level i for upto
' frames, then take the picture.
sub Play_to(app as object, i as integer, s as integer, seq as object, upto as integer, name as string)
    app.spiral = false
    app.start(i)
    Run_enter(app.run, s)
    app.pause = 0
    app.banner = ""
    app.prev = invalid
    inward = ["2", "4", "3", "5"]
    outward = ["3", "5", "2", "4"]
    f = 0
    for each seg in seq
        for k = 1 to seg[1]
            v = seg[0]
            app.arrows = {}
            app.jumpDown = false
            if app.run.mode = "fly" or app.run.mode = "flip" then
                key = ""
                if v = 1 then key = inward[s]
                if v = -1 then key = outward[s]
                if key <> "" then app.arrows.AddReplace(key, true)
            else
                held = false
                if v = 1 then held = true
                app.jumpDown = held
            end if
            app.tick()
            if app.running() then app.step()
            f = f + 1
            if f >= upto then
                app.ticks = 2730 + i * 611
                Shot(app, name)
                return
            end if
        end for
    end for
end sub
'''


def scenario():
    lines = ['sub Scenario(app as object)']
    for n, s, frac, name in PLAY:
        runs = open(os.path.join(DASH, 'tests', 'solutions', f'{n}.txt')).read().split('\n')[s].split(' ')[2:]
        seq = [tuple(int(x) for x in r.split(':')) for r in runs]
        upto = int(sum(c for _, c in seq) * frac)
        arr = '[' + ', '.join(f'[{v}, {c}]' for v, c in seq) + ']'
        lines.append(f'    Play_to(app, {n - 1}, {s}, {arr}, {upto}, "{name}")')
    return '\n'.join(lines) + '\nend sub\n' + PLAY_TO


def main():
    os.makedirs(OUT, exist_ok=True)
    shot = [sys.executable, os.path.join(HERE, 'shot.py')]
    subprocess.run(shot, check=True, stdout=subprocess.DEVNULL)      # every screen -> dist/shots
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, 'store.brs')
        open(path, 'w').write(scenario())
        subprocess.run(shot + [path, tmp], check=True, stdout=subprocess.DEVNULL)
        sources = [(os.path.join(tmp, name + '.png'), name) for _, _, _, name in PLAY]
        sources += [(os.path.join(DIST, 'shots', src + '.png'), name) for src, name in SCREENS]
        sources.sort(key=lambda p: p[1])
        thumbs = []
        for src, name in sources:
            img = Image.open(src).convert('RGB')
            img.resize((1920, 1080), Image.LANCZOS).save(os.path.join(OUT, f'spiral-shift-{name}.png'))
            thumbs.append(img.resize((480, 270), Image.LANCZOS))
    sheet = Image.new('RGB', (960, 270 * ((len(thumbs) + 1) // 2)))
    for i, t in enumerate(thumbs):
        sheet.paste(t, ((i % 2) * 480, (i // 2) * 270))
    sheet.save(os.path.join(OUT, 'overview.png'))
    print(f'wrote {len(thumbs)} screenshots and overview.png to {os.path.relpath(OUT)}')


if __name__ == '__main__':
    main()
