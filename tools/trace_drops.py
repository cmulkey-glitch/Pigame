#!/usr/bin/env python3
"""Record acid-drop traces from the 7800 ROM for tests/drops.test.mjs.

Usage: trace_drops.py path/to/Downland.a78 [outdir]   (default: tests/traces)

For each scenario: the chamber's RAM tile map and spawn tables ($23EA/$242A) after load,
then per frame every drop slot (x, y, timer, spawn index), the player and its flags, the
frame counter $E6 (it doesn't advance on lag frames) and the ball/bird position ($F6/$F7).
"""
import json, os, random, sys

sys.path.insert(0, os.path.dirname(__file__))
import a7800emu
from a7800emu import Emu
from extract_downland import boot, snapshot, restore, load_room
from trace_player import JOY, ZP, ram_map

SLOTS = 8


def drops(e):
    m = e.mem.m
    return [[m[0x24EE + i], m[0x24F6 + i], m[0x24FE + i], m[0x2506 + i]] for i in range(SLOTS)]


def record(e, name, room, difficulty, frames, outdir, seed):
    e.mem.m[0x215F] = difficulty            # $015F
    load_room(e, room)
    for _ in range(40):
        e.run_frame()
    m = e.mem.m
    n = 64 if room == 8 else 32
    start = {'room': room, 'difficulty': difficulty, 'map': ram_map(e),
             'spawns': [[m[0x23EA + i], m[0x242A + i]] for i in range(n)],
             'lastSlot': m[0x2148]}
    rng = random.Random(seed)
    out = []
    joy = '-'
    for f in range(frames):
        if f % 30 == 0:                     # wander so drops land on the player now and then
            joy = rng.choice(['L', 'R', 'L', 'R', '-'])
        e.joy = JOY[joy]
        e.run_frame()
        if e.mem.m[0x2146] != room:        # walked through a door: stop, the rest is another chamber
            break
        out.append({'drops': drops(e), 'x': ZP(e, 0xED), 'y': ZP(e, 0xEE), 'f1': ZP(e, 0xF1),
                    'air': ZP(e, 0xF1) & 1, 'frame': ZP(e, 0xE6),
                    'ball': [ZP(e, 0xF6), ZP(e, 0xF7)]})
    e.joy = JOY['-']
    json.dump({'name': name, 'start': start, 'frames': out}, open(os.path.join(outdir, name + '.json'), 'w'))
    deaths = sum(1 for a, b in zip(out, out[1:]) if not a['f1'] & 0x10 and b['f1'] & 0x10)
    print('%-12s room %2d diff %d  %d frames, %d player deaths' % (name, room, difficulty, len(out), deaths))


def main():
    a7800emu.load_rom(sys.argv[1])
    outdir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), '..', 'tests', 'traces')
    os.makedirs(outdir, exist_ok=True)
    e = Emu()
    boot(e)
    base = snapshot(e)
    for name, room, diff, seed in (('drops_c0', 0, 1, 1), ('drops_c6', 6, 1, 2),
                                   ('drops_c8', 8, 1, 3), ('drops_c7_d0', 7, 0, 4),
                                   ('drops_c2_d2', 2, 2, 5)):
        restore(e, base)
        record(e, name, room, diff, 900, outdir, seed)


if __name__ == '__main__':
    main()
