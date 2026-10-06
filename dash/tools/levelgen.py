"""Generate the Spiral Shift levels: dash/roku/levels/1.txt .. 10.txt.

Each level is four stages (jump, fly, flip, wave; see dash/roku/source/game.brs). A stage is
built left to right from obstacle patterns. Every pattern is only kept if it can be cleared
fairly from where the previous pattern left the player:
  jump / flip (tap modes): a greedy player taps in the middle of each timing window; every
    window must be at least min_window frames (12 on level 1 down to 8 on level 10). The
    square has time to spare, so for it the layout whose tightest window is closest to a
    target (14 frames on level 1 down to 8) is kept, out of several tried; most square
    patterns put their hazard on the side the square is on, so each needs a flip.
  fly / wave (hold modes): a search over hold / release keeps every surviving state; the
    states that also make it through the pattern must span at least min_slack blocks of
    height at every frame (how much room there is to be off the ideal line): 2 blocks on
    level 1 down to 1 for the triangle, 1.5 down to 0.75 for the diamond.
Patterns that fail are swapped for another; the seed makes the output repeatable.

The physics here is a Python copy of Run_step, used for design only (float64 vs the device's
float32 can differ by a hair). dash/tools/solve.mjs then solves every stage with the real
BrightScript code and dash/tools/test.mjs replays those solutions, so a drift shows up there.

Usage: python3 dash/tools/levelgen.py            (then: node dash/tools/solve.mjs)
"""
import math
import multiprocessing
import os
import random

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'roku', 'levels')
H = 10
MODES = ['jump', 'fly', 'flip', 'wave']
P = dict(speed=10.4 / 60, g=0.028, jump=0.36, pad=0.457, orb=0.36, maxFall=0.5, spin=7.0,
         flyAcc=0.012, flyMax=0.15, flipG=0.04, flipKick=0.15, wave=10.4 / 60, snap=0.25, buffer=10)


# ---- physics (mirror of game.brs Run_step, one stage) ----

class Strip:
    def __init__(self, width):
        self.width = width
        self.cols = [[] for _ in range(width)]

    def put(self, k, c, r):
        if 0 <= c < self.width and 0 <= r < H:
            self.cols[c] = [o for o in self.cols[c] if o[1] != r] + [(k, r)]

    def get(self, c, r):
        for k, rr in self.cols[c]:
            if rr == r:
                return k
        return None

    def copy(self):
        s = Strip(self.width)
        s.cols = [list(c) for c in self.cols]
        return s

    def rows(self):
        g = [['.'] * self.width for _ in range(H)]
        for c, col in enumerate(self.cols):
            for k, r in col:
                g[r][c] = k
        return [''.join(g[r]) for r in range(H - 1, -1, -1)]


def hit(a, b):
    return a[0] < b[2] and a[2] > b[0] and a[1] < b[3] and a[3] > b[1]


def new_state(mode):
    return dict(mode=mode, x=0.0, y=0.0, vy=0.0, grav=1, gr=True, held=False, buffer=0,
                dead=False, done=False, orbs=frozenset())


def step(r, st, held):
    p = P
    mode = r['mode']
    if held and not r['held']:
        r['buffer'] = p['buffer']
    r['held'] = held
    if mode == 'jump':
        if r['gr'] and (held or r['buffer'] > 0):
            r['vy'] = p['jump']; r['gr'] = False; r['buffer'] = 0
        r['vy'] = max(r['vy'] - p['g'], -p['maxFall'])
    elif mode == 'fly':
        r['vy'] += p['flyAcc'] if held else -p['flyAcc']
        r['vy'] = max(-p['flyMax'], min(p['flyMax'], r['vy']))
    elif mode == 'flip':
        if r['gr'] and r['buffer'] > 0:
            r['grav'] = -r['grav']; r['vy'] = -r['grav'] * p['flipKick']; r['gr'] = False; r['buffer'] = 0
        r['vy'] = max(-p['maxFall'], min(p['maxFall'], r['vy'] - p['flipG'] * r['grav']))
    else:
        r['vy'] = p['wave'] if held else -p['wave']
    py = r['y']
    r['x'] += p['speed']; r['y'] += r['vy']; r['gr'] = False
    if r['y'] <= 0:
        r['y'] = 0.0
        if r['vy'] < 0: r['vy'] = 0.0
        if r['grav'] == 1: r['gr'] = True
    if mode != 'jump' and r['y'] >= H - 1:
        r['y'] = float(H - 1)
        if r['vy'] > 0: r['vy'] = 0.0
        if r['grav'] == -1: r['gr'] = True
    x = r['x']
    c0 = max(math.floor(x) - 1, 0); c1 = min(math.floor(x) + 2, st.width - 1)
    if mode != 'wave':
        down = r['grav'] == 1
        up = mode == 'fly' or r['grav'] == -1
        for c in range(c0, c1 + 1):
            for k, o in st.cols[c]:
                if k == '#' and hit((x, r['y'], x + 1, r['y'] + 1), (c, o, c + 1, o + 1)):
                    if down and r['vy'] <= 0 and py >= o + 1 - p['snap']:
                        r['y'] = float(o + 1); r['vy'] = 0.0; r['gr'] = True
                    elif up and r['vy'] >= 0 and py + 1 <= o + p['snap']:
                        r['y'] = float(o - 1); r['vy'] = 0.0
                        if r['grav'] == -1: r['gr'] = True
    ins = 0.3 if mode == 'wave' else 0.2
    for c in range(c0, c1 + 1):
        for k, o in st.cols[c]:
            y = r['y']
            inner = (x + ins, y + ins, x + 1 - ins, y + 1 - ins)
            if k == '#':
                if hit(inner, (c, o, c + 1, o + 1)): r['dead'] = True
            elif k == '^':
                box = inner if mode == 'wave' else (x + .1, y, x + .9, y + .9)
                if hit(box, (c + .4, o, c + .6, o + .45)): r['dead'] = True
            elif k == 'v':
                box = inner if mode == 'wave' else (x + .1, y + .1, x + .9, y + 1)
                if hit(box, (c + .4, o + .55, c + .6, o + 1)): r['dead'] = True
            elif k == '_':
                if mode == 'jump' and r['vy'] < p['pad'] and hit((x, y, x + 1, y + 1), (c + .1, o, c + .9, o + .3)):
                    r['vy'] = p['pad']; r['gr'] = False
            elif k == 'o':
                if mode == 'jump' and (held or r['buffer'] > 0) and (c, o) not in r['orbs'] and \
                        hit((x, y, x + 1, y + 1), (c - .1, o - .1, c + 1.1, o + 1.1)):
                    r['orbs'] = r['orbs'] | {(c, o)}; r['vy'] = p['orb']; r['gr'] = False; r['buffer'] = 0
    if r['buffer'] > 0: r['buffer'] -= 1
    if not r['dead'] and x >= st.width: r['done'] = True


# ---- fairness checks ----

def run_until(st, r, x_end, taps=(), limit=100000):
    """Step r (in place) without holding, tapping on the given frame offsets, until it dies or
    reaches x_end. Returns the number of frames stepped."""
    taps = set(taps)
    f = 0
    while not r['dead'] and not r['done'] and r['x'] < x_end and f < limit:
        step(r, st, f in taps)
        f += 1
    return f


def tap_check(st, start, x_end, min_window):
    """Greedy tapper from state `start` to x_end. Returns (state at x_end, smallest window) or
    None if some window is below min_window or there is no way through."""
    r = dict(start)
    smallest = 999
    for _ in range(200):
        base = dict(r)
        n = run_until(st, base, x_end)
        if not base['dead']:
            run_until(st, r, x_end)
            return r, smallest
        death_x = base['x']
        good = []
        for f in range(n):
            t = dict(r)
            run_until(st, t, x_end, taps=[f])
            if not t['dead'] or t['x'] > death_x + 1.5:
                good.append(f)
        if not good:
            return None
        win = [good[0]]
        for f in good[1:]:
            if f != win[-1] + 1:
                break
            win.append(f)
        if len(win) < min_window:
            return None
        smallest = min(smallest, len(win))
        mid = win[len(win) // 2]
        run_until(st, r, x_end, taps=[mid], limit=mid + 1)
    return None


def hold_check(st, starts, x_end, min_slack, x_from):
    """Search every hold / release path from the states `starts` to x_end, merging states per
    half-block band (keeping the fastest rising and falling). Returns (end states, smallest
    slack) or None if no path, or if at some frame from x_from on the states that still have
    a way through span less than min_slack blocks of height."""
    def key(t):
        return (math.floor(t['y'] * 2), t['grav'])
    frames = [list(starts)]
    while True:
        cur = frames[-1]
        if all(s['x'] >= x_end for s in cur):
            break
        lo, hi = {}, {}
        for s in cur:
            for a in (False, True):
                t = dict(s)
                step(t, st, a)
                if t['dead']:
                    continue
                k = key(t)
                # ties (the diamond's speed is constant) go to the lowest / highest
                if k not in lo or (t['vy'], t['y']) < (lo[k]['vy'], lo[k]['y']): lo[k] = t
                if k not in hi or (t['vy'], t['y']) > (hi[k]['vy'], hi[k]['y']): hi[k] = t
        nxt = list({id(v): v for v in list(lo.values()) + list(hi.values())}.values())
        if not nxt:
            return None
        frames.append(nxt)
    # walk back: a state still has a way through if pressing or not takes it into a band that
    # has one next frame (bands, not the one merged parent, so no path is lost)
    good_keys = {key(s) for s in frames[-1]}
    smallest = 99.0
    for f in range(len(frames) - 2, -1, -1):
        good = []
        for s in frames[f]:
            for a in (False, True):
                t = dict(s)
                step(t, st, a)
                if not t['dead'] and key(t) in good_keys:
                    good.append(s)
                    break
        if not good:
            return None
        if frames[f][0]['x'] >= x_from:
            ys = [s['y'] for s in good]
            smallest = min(smallest, max(ys) - min(ys))
        good_keys = {key(s) for s in good}
    if smallest < min_slack:
        return None
    return frames[-1], smallest


# ---- patterns ----
# Each returns (cells, length): cells are (kind, col offset, row) with row 0 at the edge.

def blocks(c, r, w=1, h=1, k='#'):
    return [(k, c + i, r + j) for i in range(w) for j in range(h)]


def jump_patterns(d, rng):
    pats = [
        lambda: (blocks(0, 0, 1, 1, '^'), 1),
        lambda: (blocks(0, 0, 2, 1, '^'), 2),
        lambda: (blocks(0, 0, w := rng.randint(3, 6)), w),
        lambda: (blocks(0, 0, 4) + blocks(4, 0, 4, 2), 8),
        lambda: ([('_', 0, 0)] + blocks(3, 0, 3, 3), 6),
        lambda: (blocks(0, 0, 6, 1, '^') + [('o', 2, 2)], 6),
    ]
    if d >= 0.2:
        pats += [
            lambda: (blocks(0, 0, 6) + [('^', 3, 1)], 6),
            lambda: (blocks(0, 0, 2) + blocks(2, 0, 3, 1, '^') + blocks(5, 0, 2), 7),
            lambda: (blocks(0, 0, 3, 1, '^'), 3),
        ]
    if d >= 0.45:
        pats += [
            lambda: (blocks(0, 0, 4) + blocks(4, 0, 4, 2) + blocks(8, 0, 4, 3), 12),
            lambda: (blocks(0, 0, 9, 1, '^') + [('o', 2, 2), ('o', 6, 3)], 9),
            lambda: (blocks(0, 1, 3) + blocks(0, 0, 3, 1, '^') + blocks(3, 0, 3, 1, '^'), 6),
            lambda: ([('_', 0, 0)] + blocks(1, 0, 3, 1, '^') + blocks(4, 0, 3, 2), 7),
        ]
    if d >= 0.7:
        pats += [
            lambda: (blocks(0, 0, 2, 1, '^') + blocks(4, 0, 2, 1, '^'), 6),
            lambda: (blocks(0, 1, 2) + blocks(0, 0, 8, 1, '^') + blocks(5, 2, 2), 8),
        ]
    return pats


def fly_patterns(d, rng):
    gap = 6 if d < 0.4 else 5 if d < 0.75 else 4
    def gate():
        a = rng.randint(1, H - gap - 1)
        return blocks(0, 0, 1, a) + blocks(0, a + gap, 1, H - a - gap), 1
    def tunnel():
        a = rng.randint(1, H - gap - 1)
        w = rng.randint(3, 6)
        return blocks(0, 0, w, a) + blocks(0, a + gap, w, H - a - gap), w
    pats = [
        lambda: (blocks(0, 0, 1, rng.randint(3, 6)), 1),
        lambda: (blocks(0, H - (h := rng.randint(3, 6)), 1, h), 1),
        gate,
    ]
    if d >= 0.4:
        pats.append(tunnel)
    return pats


def flip_patterns(d, rng, top=False):
    """top: the square is on the ceiling now. Most patterns put their hazard on the side the
    square is on, so each one needs a flip."""
    edge, ceil = (H - 1, 'v'), (0, '^')     # (row, spike) of the side you are on / the other
    if not top:
        edge, ceil = ceil, edge
    def run(side):
        w = n()
        return blocks(0, side[0], w, 1, side[1]), w
    def wall(side):
        h, w = rng.randint(2, 4), rng.randint(1, 3)
        return blocks(0, 0 if side[0] == 0 else H - h, w, h), w
    def n(): return rng.randint(3, 5 + int(d * 5))
    def midwall():
        # a wall across the middle: you must not be crossing when you pass it
        a = rng.randint(2, 3)
        return blocks(0, a, 1, H - 2 * a), 1
    def platform():
        # spikes on both sides: ride on top of (or under) a floating platform
        w = rng.randint(6, 9 + int(d * 4))
        return blocks(0, 4, w + 2) + blocks(1, 0, w, 1, '^') + blocks(1, H - 1, w, 1, 'v'), w + 2
    def alt():
        a, gap = n(), rng.randint(3, 5)
        return blocks(0, edge[0], a, 1, edge[1]) + blocks(a + gap, ceil[0], a, 1, ceil[1]), 2 * a + gap
    def zigzag():
        # quick alternating runs: flip, flip, flip
        a, gap = rng.randint(2, 4), rng.randint(2, 4)
        cells = []
        for i in range(3):
            side = edge if i % 2 == 0 else ceil
            cells += blocks(i * (a + gap), side[0], a, 1, side[1])
        return cells, 3 * a + 2 * gap
    def wall_then_spikes():
        # cross only after the wall, and right away
        a = rng.randint(2, 3)
        gap = rng.randint(round(lerp(4, 2, d)), round(lerp(5, 3, d)))
        spikes = blocks(gap, edge[0], n(), 1, edge[1])
        return blocks(0, a, 1, H - 2 * a) + spikes, max(c for _, c, _ in spikes) + 1
    def staggered():
        # tall walls on alternate sides: flip only once past one, and be across before the
        # next. Each block of spacing is ~6 frames of window: ~27 at 6 blocks, ~15 at 4
        cells, c = [], 0
        side = ceil                     # the first wall is on the far side: no flip yet
        for i in range(rng.randint(3, 4)):
            h = rng.randint(4, 5)
            if side[0] == 0:            # spike-tipped, so it can't be landed on
                cells += blocks(c, 0, 1, h) + [('^', c, h)]
            else:
                cells += blocks(c, H - h, 1, h) + [('v', c, H - h - 1)]
            side = edge if side is ceil else ceil
            c += rng.randint(round(lerp(6, 4, d)), round(lerp(7, 4, d)))
        return cells, c - 4
    pats = [
        lambda: run(edge),
        lambda: wall(edge),
        midwall,
        staggered,
        staggered,
        staggered,
        wall_then_spikes,
    ]
    if d >= 0.2:
        pats += [platform, alt]
    if d >= 0.5:
        pats += [zigzag]
    return pats


def wave_patterns(d, rng):
    gap = 5 if d < 0.4 else 4 if d < 0.75 else 3
    def gate():
        a = rng.randint(1, H - gap - 1)
        return blocks(0, 0, 1, a) + blocks(0, a + gap, 1, H - a - gap), 1
    pats = [
        lambda: (blocks(0, 0, 1, rng.randint(3, 7)), 1),
        lambda: (blocks(0, H - (h := rng.randint(3, 7)), 1, h), 1),
        gate,
    ]
    if d >= 0.5:
        def corridor():
            a = rng.randint(1, H - gap - 2)
            w = rng.randint(3, 5)
            return blocks(0, 0, w, a) + blocks(0, a + gap, w, H - a - gap), w
        pats.append(corridor)
    return pats


PATTERNS = dict(jump=jump_patterns, fly=fly_patterns, flip=flip_patterns, wave=wave_patterns)


# ---- stage builder ----

RUNWAY, TAIL = 12, 10


def lerp(a, b, t):
    return a + (b - a) * t


def build_stage(mode, d, length, rng):
    min_window = round(lerp(12, 8, d))
    min_slack = lerp(2.0, 1.0, d) if mode == 'fly' else lerp(1.5, 0.75, d)
    space = (round(lerp(5, 3, d)), round(lerp(9, 6, d)))     # blocks between patterns
    if mode == 'fly':
        space = (round(lerp(10, 7, d)), round(lerp(14, 10, d)))
    if mode == 'wave':
        space = (round(lerp(7, 4, d)), round(lerp(11, 7, d)))
    if mode == 'flip':
        space = (1, round(lerp(3, 2, d)))
    total = RUNWAY + length + TAIL
    st = Strip(total)
    # the triangle (and, from level 6, the diamond) flies over a floor of spikes
    floor_spikes = mode == 'fly' or (mode == 'wave' and d >= 0.5)
    tap = mode in ('jump', 'flip')
    state = new_state(mode) if tap else [new_state(mode)]
    pos = RUNWAY
    first = True
    recent = []
    # the square has slack to spare: try several layouts and keep the one whose tightest
    # timing window is closest to target_window
    tries = 8 if mode == 'flip' else 1
    target_window = lerp(14, 8, d)
    while pos < RUNWAY + length:
        found = []
        for _ in range(30):
            gap = rng.randint(*space)
            pats = flip_patterns(d, rng, state['grav'] == -1) if mode == 'flip' else PATTERNS[mode](d, rng)
            pick = rng.randrange(len(pats))
            if pick in recent and len(pats) > len(recent):
                continue
            cells, w = pats[pick]()
            if first and mode in ('flip', 'wave'):
                # the stage must need a press: start with something on the edge
                cells, w = blocks(0, 0, 3, 1, '^') if mode == 'flip' else blocks(0, 0, 1, 4), (3 if mode == 'flip' else 1)
            at = pos + gap
            if at + w + 4 > total - TAIL:
                break
            trial = st.copy()
            if floor_spikes:
                for c in range(pos, at + w):
                    if not any(o[1] == 0 for o in trial.cols[c]):
                        trial.put('^', c, 0)
            for k, c, r in cells:
                trial.put(k, at + c, r)
            # hold modes: judge the room up to a little past the pattern, so the next one can
            # not catch the player in a spot this one forced
            x_end = at + w + (3 if tap else 6)
            res = tap_check(trial, state, x_end, min_window) if tap else hold_check(trial, state, x_end, min_slack, at - 2)
            if res is None:
                continue
            found.append((abs(res[1] - target_window), trial, res[0], at + w, pick))
            if len(found) >= tries:
                break
        if found:
            _, st, state, pos, pick = min(found, key=lambda f: f[0])
            first = False
            recent = (recent + [pick])[-2:]   # not the same pattern within three
        else:
            pos += 3
            if floor_spikes:
                # keep the floor dangerous across the skipped columns too, if still passable
                trial = st.copy()
                for c in range(pos - 3, pos):
                    if c < total and not any(o[1] == 0 for o in trial.cols[c]):
                        trial.put('^', c, 0)
                res = hold_check(trial, state, pos + 2, min_slack, pos - 3)
                if res is not None:
                    st, state = trial, res[0]
    # pad the tail so the strip ends a few blocks after the last obstacle
    end = min(total, pos + TAIL)
    out = Strip(end)
    out.cols = st.cols[:end]
    return out


def stage_ok(st, mode, d):
    if mode in ('jump', 'flip'):
        return tap_check(st, new_state(mode), st.width + 1, round(lerp(12, 8, d))) is not None
    # room to manoeuvre is a per-pattern rule (measured to just past each pattern); end to
    # end, where one pattern can set up the next, at least half of it
    slack = lerp(2.0, 1.0, d) if mode == 'fly' else lerp(1.5, 0.75, d)
    return hold_check(st, [new_state(mode)], st.width + 1, slack / 2, RUNWAY) is not None


LEVELS = [
    # name, bg, ground, line
    ('Groundwork', '#2A48E8', '#18298F', '#FFFFFF'),
    ('First Turn', '#1F9E89', '#0F5C50', '#FFFFFF'),
    ('Uplift', '#8A2BD6', '#4F1785', '#FFFFFF'),
    ('Ceiling Walk', '#D6702B', '#8A4214', '#FFFFFF'),
    ('Switchback', '#2B8AD6', '#174F85', '#FFFFFF'),
    ('Corkscrew', '#C42D6E', '#7A1A43', '#FFFFFF'),
    ('Vortex', '#3E3EB8', '#22226E', '#FFE14D'),
    ('Gyre', '#1B7F3B', '#0D4720', '#FFE14D'),
    ('Maelstrom', '#A3242E', '#5E1218', '#FFE14D'),
    ('Singularity', '#22222E', '#0A0A12', '#FF6AD5'),
]
DIFFICULTY = ['Easy', 'Easy', 'Normal', 'Normal', 'Hard', 'Hard', 'Harder', 'Harder', 'Insane', 'Insane']


def make_level(i):
    name, bg, ground, line = LEVELS[i]
    d = i / (len(LEVELS) - 1)
    rng = random.Random(1000 + i)
    text = [f'name={name}', f'difficulty={DIFFICULTY[i]}', f'bg={bg}', f'ground={ground}',
            f'line={line}', f'music=level{i + 1}']
    widths = []
    for s, mode in enumerate(MODES):
        length = round(lerp(110, 170, d)) - (20 if mode in ('fly', 'wave') else 0)
        # the patterns were checked one at a time; check the whole stage end to end too
        # (the greedy path can differ) and rebuild it if it fails
        for _ in range(80):
            st = build_stage(mode, d, length, rng)
            if stage_ok(st, mode, d):
                break
        else:
            raise RuntimeError(f'level {i + 1} stage {s + 1}: no fair layout found')
        widths.append(st.width)
        text.append(f'--- stage {s + 1}: {mode}')
        text += st.rows()
    with open(os.path.join(OUT, f'{i + 1}.txt'), 'w') as fh:
        fh.write('\n'.join(text) + '\n')
    secs = sum(widths) / (P['speed'] * 60)
    return f'{i + 1:2}. {name:13} widths {widths}  ~{secs:.0f} s'


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith('.txt'):
            os.remove(os.path.join(OUT, f))
    with multiprocessing.Pool() as pool:
        for line in pool.map(make_level, range(len(LEVELS))):
            print(line)


if __name__ == '__main__':
    main()
