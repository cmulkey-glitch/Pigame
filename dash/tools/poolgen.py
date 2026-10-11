"""Generate the random-world pool: dash/roku/pool/0.txt .. 9.txt, one file per difficulty tier.

Each tier holds POOL_SIDES original sides per shape, built and checked exactly like the
classic levels (levelgen.build_stage / stage_ok) at that tier's difficulty and speed, and long
enough for the longest level that can use the tier. A random world (main.brs World_build)
stretches them further:
  cut short     a side may be played shorter than it is (any prefix of a beatable side is
                beatable: past the cut there is nothing left to hit), so one side serves
                every level from its tier's down
  any edge      the physics does not depend on which screen edge a side is drawn on
  reversed      R: the course run backwards (runway and tail kept in place)
  mirrored      M: edge and ceiling swapped (square and diamond only; the ball needs its
                floor, and a mirrored triangle could just sit on the safe edge)
Variants R, M and RM change the course, so each is checked again with stage_ok and only kept
if it passes; the ones kept are listed in the side's "---" line, e.g. "--- jump 2 [OR]: jump".
Originals are also solved with the real game code by dash/tools/solve.mjs (pool files are
read like levels); the variants are checked with this Python copy of the physics only.

Usage: python3 dash/tools/poolgen.py     (then: node dash/tools/solve.mjs pool)
"""
import multiprocessing
import os
import random

import levelgen as g

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'roku', 'pool')
POOL_SIDES = 4
TIERS = 10


def transform(st, rev, mirror):
    """The variant of strip st: content reversed and/or edge and ceiling swapped."""
    out = g.Strip(st.width)
    lo, hi = g.RUNWAY, st.width - g.TAIL - 1
    for c in range(st.width):
        src = c
        if rev and lo <= c <= hi:
            src = lo + hi - c
        for k, r in st.cols[src]:
            if mirror:
                r = g.H - 1 - r
                k = {'^': 'v', 'v': '^'}.get(k, k)
            out.put(k, c, r)
    return out


def tier_width(t):
    # a tier serves its own level and the ones either side of it: the longest is level t - 1
    return g.level_width(max(t - 1, 0))


def make_tier(t):
    d = t / (TIERS - 1) * g.PATTERN_RAMP
    mult = 1 + g.SPEED_STEP * t
    g.set_speed(mult)
    rng = random.Random(5000 + t)
    text = [f'name=Pool tier {t}', f'speed={mult:.2f}']
    counts = {}
    for mode in g.MODES:
        for n in range(POOL_SIDES):
            length = tier_width(t) - g.RUNWAY - g.TAIL
            for _ in range(80):
                st = g.build_stage(mode, d, length, rng)
                if g.stage_ok(st, mode, d):
                    break
            else:
                raise RuntimeError(f'tier {t} {mode} {n}: no fair layout found')
            ok = 'O'
            if g.stage_ok(transform(st, True, False), mode, d):
                ok += 'R'
            if mode in ('flip', 'wave'):
                if g.stage_ok(transform(st, False, True), mode, d):
                    ok += 'M'
                if g.stage_ok(transform(st, True, True), mode, d):
                    ok += 'B'
            counts[ok] = counts.get(ok, 0) + 1
            text.append(f'--- {mode} {n} [{ok}]: {mode}')
            text += st.rows()
    with open(os.path.join(OUT, f'{t}.txt'), 'w') as fh:
        fh.write('\n'.join(text) + '\n')
    return f'tier {t}: width {tier_width(t)}, speed {mult:.2f}, variants {counts}'


def main():
    os.makedirs(OUT, exist_ok=True)
    with multiprocessing.Pool() as pool:
        for line in pool.map(make_tier, range(TIERS)):
            print(line)


if __name__ == '__main__':
    main()
