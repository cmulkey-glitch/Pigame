#!/usr/bin/env python3
"""Record ball, bird and chamber-timer traces from the 7800 ROM for tests/enemies.test.mjs.

Usage: trace_enemies.py path/to/Downland.a78 [outdir]   (default: tests/traces)

Per frame: frame counter $E6, ball $F6/$F7/$F8, bird flag ($FA bit 1) and $0149-$014B,
timer $01AA/$01AB, and the player (x, y, $F1). Drop collisions are patched out so any
death comes from the ball, the bird or a fall.
"""
import json, os, random, sys

sys.path.insert(0, os.path.dirname(__file__))
import a7800emu
from a7800emu import Emu
from extract_downland import boot, snapshot, restore, load_room
from trace_player import JOY, ZP

bcd = lambda v: (v >> 4) * 10 + (v & 15)


def sample(e):
    m = e.mem.m
    return {'frame': ZP(e, 0xE6), 'ball': [ZP(e, 0xF6), ZP(e, 0xF7), ZP(e, 0xF8)],
            'bird': bool(ZP(e, 0xFA) & 2), 'birdPos': [m[0x2149], m[0x214A], m[0x214B]],
            'timer': bcd(m[0x21AA]) * 100 + bcd(m[0x21AB]),
            'x': ZP(e, 0xED), 'y': ZP(e, 0xEE), 'f1': ZP(e, 0xF1), 'room': m[0x2146]}


def record(e, name, room, frames, outdir, seed, timer=None, difficulty=1, wander=True):
    e.mem.m[0x215F] = difficulty
    load_room(e, room)
    e.joy = JOY['L']                        # leave regeneration so the timer runs
    for _ in range(12):
        e.run_frame()
    e.joy = JOY['-']
    if timer is not None:                   # BCD
        e.mem.m[0x21AA], e.mem.m[0x21AB] = int(str(timer // 100), 16), int(str(timer % 100), 16)
    start = sample(e)
    rng = random.Random(seed)
    out, joy = [], '-'
    for f in range(frames):
        if wander and f % 40 == 0:
            joy = rng.choice(['L', 'R', '-', '-'])
        e.joy = JOY[joy]
        e.run_frame()
        s = sample(e)
        if s['room'] != room:
            break
        out.append(s)
    e.joy = JOY['-']
    json.dump({'name': name, 'room': room, 'difficulty': difficulty, 'start': start, 'frames': out},
              open(os.path.join(outdir, name + '.json'), 'w'))
    deaths = sum(1 for a, b in zip(out, out[1:]) if not a['f1'] & 0x10 and b['f1'] & 0x10)
    print('%-16s room %2d  %4d frames, bird %s, %d deaths' % (name, room, len(out),
                                                            any(s['bird'] for s in out), deaths))


def main():
    a7800emu.load_rom(sys.argv[1])
    outdir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), '..', 'tests', 'traces')
    os.makedirs(outdir, exist_ok=True)
    e = Emu()
    e.mem.m[0xB7A2] = 0x60                  # no drop deaths
    boot(e)
    base = snapshot(e)
    for name, room, seed, kw in (('enemies_ball0', 0, 1, {}), ('enemies_ball2', 2, 2, {}),
                                 ('enemies_ball5', 5, 3, {}), ('enemies_ball6', 6, 4, {}),
                                 ('enemies_bird1', 1, 5, {'timer': 30}),
                                 ('enemies_bird4', 4, 6, {'timer': 5, 'wander': False}),
                                 ('enemies_timer_d0', 3, 7, {'difficulty': 0, 'wander': False})):
        restore(e, base)
        record(e, name, room, 900, outdir, seed, **kw)


if __name__ == '__main__':
    main()
