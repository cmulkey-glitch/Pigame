"""Generate the random-world pool: dash/roku/pool/0.txt .. 9.txt, one file per difficulty tier.

Each tier holds POOL_SIDES sides per shape, built and checked exactly like the classic levels
(levelgen.build_stage / stage_ok) at that tier's difficulty and speed, and long enough for the
longest level that can use the tier. A random world (world.brs World_build) plays a side from
its level's tier or one either side of it, cut short to the level's length: any prefix of a
beatable side is beatable, since past the cut there is nothing left to hit. Every side is also
solved by dash/tools/pysolve.py and replayed with the real game code by dash/tools/test.mjs.

Usage: python3 dash/tools/poolgen.py [tiers...]     (then: python3 dash/tools/pysolve.py pool)
"""
import multiprocessing
import os
import random
import sys

import levelgen as g
import pysolve

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'roku', 'pool')
POOL_SIDES = 12
TIERS = 10


def tier_width(t):
    # a tier serves its own level and the ones either side of it: the longest is level t - 1
    return g.level_width(max(t - 1, 0))


def make_tier(t):
    d = t / (TIERS - 1) * g.PATTERN_RAMP
    mult = 1 + g.SPEED_STEP * t
    g.set_speed(mult)
    phys = pysolve.phys(mult)
    rng = random.Random(5000 + t)
    text = [f'name=Pool tier {t}', f'speed={mult:.2f}']
    for mode in g.MODES:
        for n in range(POOL_SIDES):
            length = tier_width(t) - g.RUNWAY - g.TAIL
            for _ in range(80):
                st = g.build_stage(mode, d, length, rng)
                # fair by the generator's check, and beatable with the game's own arithmetic
                if g.stage_ok(st, mode, d) and pysolve.solve_stage(mode, st, phys) is not None:
                    break
            else:
                raise RuntimeError(f'tier {t} {mode} {n}: no fair layout found')
            text.append(f'--- {mode} {n}: {mode}')
            text += st.rows()
    with open(os.path.join(OUT, f'{t}.txt'), 'w') as fh:
        fh.write('\n'.join(text) + '\n')
    return f'tier {t}: width {tier_width(t)}, speed {mult:.2f}'


def main():
    os.makedirs(OUT, exist_ok=True)
    with multiprocessing.Pool() as pool:
        for line in pool.map(make_tier, [int(a) for a in sys.argv[1:]] or range(TIERS)):
            print(line)


if __name__ == '__main__':
    main()
