"""Find a way through every stage, in the same format as dash/tools/solve.mjs:
dash/tests/solutions/N.txt for the levels, poolT.txt for the random-world pool. The search is
the one in dash/tests/solve.brs over a Python copy of game.brs Run_step that rounds every float
operation as the brs interpreter does, about a hundred times faster than running it in brs.

dash/tools/test.mjs replays every solution with the real BrightScript code, so any difference
between the copies fails there; re-solve such a stage with the real code:
node dash/tools/solve.mjs [pool] N:stage.

Usage: python3 dash/tools/pysolve.py [levels | pool] [numbers...]
"""
import math
import multiprocessing
import os
import struct
import sys

import levelgen as g

DASH = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')


def parse(path):
    """(speed multiplier, [(mode, Strip)]) of a level or pool file."""
    speed, stages, rows, mode = 1.0, [], None, None
    for line in open(path).read().split('\n'):
        line = line.rstrip('\r')
        if line.startswith('---'):
            if rows is not None:
                stages.append((mode, rows))
            rows = []
            mode = line.split(':', 1)[1].strip() if ':' in line else g.MODES[len(stages) % 4]
        elif rows is not None:
            if line:
                rows.append(line)
        elif line.startswith('speed='):
            speed = float(line[6:])
    if rows is not None:
        stages.append((mode, rows))
    out = []
    for mode, rows in stages:
        st = g.Strip(max(len(r) for r in rows))
        for i, row in enumerate(rows):
            for c, k in enumerate(row):
                if k not in '. ':
                    st.cols[c].append((k, len(rows) - 1 - i))
        out.append((mode, st))
    return speed, out


def F(v):
    """A BrightScript Float as the brs interpreter keeps it: float32, then 7 significant digits."""
    return float('%.7g' % struct.unpack('f', struct.pack('f', v))[0])


def phys(mult):
    """Dash_phys() with a level's speed= header applied, as brs computes it."""
    p = {k: F(v) for k, v in dict(g=0.028, jump=0.36, pad=0.457, orb=0.36, maxFall=0.5,
                                  flyAcc=0.03, flyMax=0.15, flipG=0.04, flipKick=0.15,
                                  snap=0.25).items()}
    p['speed'] = p['wave'] = F(F(F(10.4) / 60) * F(mult))
    p['buffer'] = 10
    return p


C = {v: F(v) for v in (0.1, 0.2, 0.3, 0.4, 0.45, 0.55, 0.6, 0.9, 1.1)}


def hit(ax0, ay0, ax1, ay1, bx0, by0, bx1, by1):
    return ax0 < bx1 and ax1 > bx0 and ay0 < by1 and ay1 > by0


def step(r, st, a, p):
    """One frame of game.brs Run_step, operation for operation, with a the button (0 / 1) for
    the ball and diamond or the arrows (-1 / 0 / 1) for the triangle and square."""
    mode = r['mode']
    held = a == 1 and mode in ('jump', 'wave')
    steer = a if mode in ('fly', 'flip') else 0
    if held and not r['held']:
        r['buffer'] = p['buffer']
    r['held'] = held
    vy = r['vy']
    if mode == 'jump':
        if r['gr'] and (held or r['buffer'] > 0):
            vy = p['jump']; r['gr'] = False; r['buffer'] = 0
        vy = F(vy - p['g'])
        if vy < -p['maxFall']: vy = -p['maxFall']
    elif mode == 'fly':
        target = F(steer * p['flyMax'])
        if vy < target:
            vy = min(F(vy + p['flyAcc']), target)
        elif vy > target:
            vy = max(F(vy - p['flyAcc']), target)
    elif mode == 'flip':
        if steer != 0 and steer != r['sp']:
            r['want'] = steer; r['buffer'] = p['buffer']
        if r['gr'] and r['buffer'] > 0:
            want = -1 if r['want'] == 1 else 1
            if want != r['grav']:
                r['grav'] = want; vy = F(-r['grav'] * p['flipKick']); r['gr'] = False
            r['buffer'] = 0
        vy = F(vy - F(p['flipG'] * r['grav']))
        if vy < -p['maxFall']: vy = -p['maxFall']
        if vy > p['maxFall']: vy = p['maxFall']
    else:
        vy = p['wave'] if held else -p['wave']
    py = r['y']
    x = F(r['x'] + p['speed'])
    y = F(py + vy)
    gr = False
    if y <= 0:
        y = 0.0
        if vy < 0: vy = 0.0
        if r['grav'] == 1: gr = True
    if mode != 'jump' and y >= g.H - 1:
        y = float(g.H - 1)
        if vy > 0: vy = 0.0
        if r['grav'] == -1: gr = True
    c0 = max(math.floor(x) - 1, 0)
    c1 = min(math.floor(x) + 2, st.width - 1)
    if mode != 'wave':
        down = r['grav'] == 1
        up = mode == 'fly' or r['grav'] == -1
        for c in range(c0, c1 + 1):
            for k, o in st.cols[c]:
                if k == '#' and hit(x, y, F(x + 1), F(y + 1), c, o, c + 1, o + 1):
                    if down and vy <= 0 and py >= F(o + 1 - p['snap']):
                        y = float(o + 1); vy = 0.0; gr = True
                    elif up and vy >= 0 and F(py + 1) <= F(o + p['snap']):
                        y = float(o - 1); vy = 0.0
                        if r['grav'] == -1: gr = True
    ins = C[0.3] if mode == 'wave' else C[0.2]
    for c in range(c0, c1 + 1):
        for k, o in st.cols[c]:
            box = (F(x + ins), F(y + ins), F(F(x + 1) - ins), F(F(y + 1) - ins))
            if k == '#':
                if hit(*box, c, o, c + 1, o + 1): r['dead'] = True
            elif k == '^':
                if mode != 'wave': box = (F(x + C[0.1]), y, F(x + C[0.9]), F(y + C[0.9]))
                if hit(*box, F(c + C[0.4]), o, F(c + C[0.6]), F(o + C[0.45])): r['dead'] = True
            elif k == 'v':
                if mode != 'wave': box = (F(x + C[0.1]), F(y + C[0.1]), F(x + C[0.9]), F(y + 1))
                if hit(*box, F(c + C[0.4]), F(o + C[0.55]), F(c + C[0.6]), o + 1): r['dead'] = True
            elif k == '_':
                if mode == 'jump' and vy < p['pad'] and \
                        hit(x, y, F(x + 1), F(y + 1), F(c + C[0.1]), o, F(c + C[0.9]), F(o + C[0.3])):
                    vy = p['pad']; gr = False
            elif k == 'o':
                if mode == 'jump' and (held or r['buffer'] > 0) and (c, o) not in r['orbs'] and \
                        hit(x, y, F(x + 1), F(y + 1), F(c - C[0.1]), F(o - C[0.1]), F(c + C[1.1]), F(o + C[1.1])):
                    r['orbs'] = r['orbs'] | {(c, o)}; vy = p['orb']; gr = False; r['buffer'] = 0
    if r['buffer'] > 0: r['buffer'] -= 1
    r['sp'] = steer
    r['x'], r['y'], r['vy'], r['gr'] = x, y, vy, gr
    if not r['dead'] and x >= st.width: r['done'] = True


def solve_stage(mode, st, p):
    """Runs of "value:frames" through the stage, or None."""
    start = g.new_state(mode)
    start.update(want=0, sp=0, path=None)
    states = [start]
    for _ in range(int(st.width / p['speed']) + 20):
        lo, hi = {}, {}
        for q in states:
            if mode == 'fly':
                acts = (-1, 0, 1)
            elif mode == 'flip':
                acts = (0, 1) if q['grav'] == 1 else (0, -1)
            else:
                acts = (0, 1)
            for a in acts:
                t = dict(q)
                t['path'] = (a, q['path'])
                step(t, st, a, p)
                if t['done']:
                    return runs(t['path'])
                if t['dead']:
                    continue
                key = (int(t['y'] * 2),)
                if mode == 'fly':
                    key += (int(t['vy'] * 34 + 100),)
                if mode in ('jump', 'flip'):
                    key += (t['grav'], len(t['orbs']), t['buffer'] > 0, t['held'], t['gr'])
                    if mode == 'flip':
                        key += (t['sp'],)
                if key not in lo or (t['vy'], t['y']) < (lo[key]['vy'], lo[key]['y']):
                    lo[key] = t
                if key not in hi or (t['vy'], t['y']) > (hi[key]['vy'], hi[key]['y']):
                    hi[key] = t
        states = []
        for k, t in lo.items():
            states.append(t)
            if hi[k] is not t:
                states.append(hi[k])
        if not states:
            return None
    return None


def runs(path):
    vals = []
    while path is not None:
        vals.append(path[0])
        path = path[1]
    vals.reverse()
    out = []
    i = 0
    while i < len(vals):
        j = i
        while j < len(vals) and vals[j] == vals[i]:
            j += 1
        out.append(f'{vals[i]}:{j - i}')
        i = j
    return ' '.join(out)


def solve_file(job):
    kind, n = job
    speed, stages = parse(os.path.join(DASH, 'roku', kind, f'{n}.txt'))
    p = phys(speed)
    lines, failed = [], []
    for s, (mode, st) in enumerate(stages):
        sol = solve_stage(mode, st, p)
        if sol is None:
            failed.append(s)
            sol = '0:1'         # fails the replay, so it shows up in the tests
        lines.append(f'STAGE {s} {sol}')
    name = ('pool' if kind == 'pool' else '') + f'{n}.txt'
    with open(os.path.join(DASH, 'tests', 'solutions', name), 'w') as fh:
        fh.write('\n'.join(lines) + '\n')
    return f'{kind} {n}: {len(stages)} stages' + (f', NO WAY THROUGH {failed}' if failed else '')


def main():
    kind = sys.argv[1] if len(sys.argv) > 1 else 'levels'
    nums = [int(a) for a in sys.argv[2:]] or (range(1, 11) if kind == 'levels' else range(10))
    with multiprocessing.Pool() as pool:
        for line in pool.imap_unordered(solve_file, [(kind, n) for n in nums]):
            print(line, flush=True)


if __name__ == '__main__':
    main()
