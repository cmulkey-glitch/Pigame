#!/usr/bin/env python3
"""Record player-physics traces from the 7800 ROM for tests/physics.test.mjs.

Usage: trace_player.py path/to/Downland.a78 [outdir]   (default: tests/traces)

Each trace holds the chamber's RAM tile map, the player's starting variables, the input
per frame, and the ROM's resulting x/y/flags per frame. The JS port replays the inputs
and must match. Enemy collisions are patched out so only movement physics is compared.
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(__file__))
import a7800emu
from a7800emu import Emu
from extract_downland import boot, snapshot, restore

JOY = {'R': 0x7F, 'L': 0xBF, 'D': 0xDF, 'U': 0xEF, '-': 0xFF}
ZP = lambda e, a: e.mem.m[0x2000 + a]


def ram_map(e):
    return [e.mem.m[0x2200 + i] for i in range(256)] + [e.mem.m[0x2300 + i] for i in range(224)]


def player_state(e):
    return {k: ZP(e, a) for k, a in (('x', 0xED), ('y', 0xEE), ('facing', 0xF0), ('f1', 0xF1),
                                     ('vyHi', 0xF2), ('vyLo', 0xF3), ('fa', 0xFA), ('hold', 0x144),
                                     ('hangSide', 0x145), ('midair', 0x141), ('splat', 0x142),
                                     ('lives', 0x140))}


def run(e, script):
    # The ROM samples the stick at line ~262 of the previous frame and the buttons at line 0,
    # so each frame's input is applied at line 200 of the frame before it.
    # A neutral first frame keeps frame 0's input from being sampled during setup.
    steps = [('-', 0)] + [(joy, fire) for n, joy, fire in script for _ in range(n)]
    e.joy, e.fire = JOY[steps[0][0]], bool(steps[0][1])
    frames = []
    for i, (joy, fire) in enumerate(steps):
        nxt = steps[i + 1] if i + 1 < len(steps) else steps[i]
        def apply(nxt=nxt):
            e.joy, e.fire = JOY[nxt[0]], bool(nxt[1])
        e.run_frame(on_line=(200, apply))
        frames.append({'in': joy + ('J' if fire else ''), 'frame': ZP(e, 0xE6), **player_state(e)})
    return frames


def record(e, name, setup, script, outdir):
    setup(e)
    start = {'map': ram_map(e), 'frame': ZP(e, 0xE6), **player_state(e)}
    frames = run(e, script)
    json.dump({'name': name, 'start': start, 'frames': frames},
              open(os.path.join(outdir, name + '.json'), 'w'))
    print('%-16s %4d frames  end x=%02X y=%02X f1=%02X' % (name, len(frames), frames[-1]['x'],
                                                          frames[-1]['y'], frames[-1]['f1']))


def main():
    a7800emu.load_rom(sys.argv[1])
    outdir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), '..', 'tests', 'traces')
    os.makedirs(outdir, exist_ok=True)
    e = Emu()
    # Drops and the ball/bird aren't ported yet: disable their player-collision checks
    # ($B7A2, $B7F0) so the traces isolate movement physics.
    e.mem.m[0xB7A2] = e.mem.m[0xB7F0] = 0x60   # RTS
    boot(e)
    for _ in range(60):        # let the chamber finish revealing
        e.run_frame()
    e.joy = JOY['L']           # leave regeneration and walk onto open floor
    for _ in range(80):
        e.run_frame()
    e.joy = JOY['-']
    for _ in range(5):
        e.run_frame()
    floor = snapshot(e)

    def at(x, y):
        def setup(e):
            restore(e, floor)
            e.mem.m[0x20ED], e.mem.m[0x20EE] = x, y
            e.joy = JOY['-']
            for _ in range(8):
                e.run_frame()
        return setup

    same = lambda e: restore(e, floor)
    record(e, 'walk', same, [(60, 'L', 0), (40, 'R', 0), (10, '-', 0)], outdir)
    record(e, 'jump_standing', same, [(2, '-', 1), (70, '-', 0)], outdir)
    record(e, 'jump_running', same, [(8, 'R', 0), (2, 'R', 1), (70, 'R', 0)], outdir)
    record(e, 'rope', same, [(8, 'L', 0), (2, 'L', 1), (24, 'L', 0), (4, '-', 0),
                             (40, 'U', 0), (30, 'D', 0), (60, 'L', 0), (40, 'R', 0),
                             (40, 'L', 0), (80, '-', 0)], outdir)
    record(e, 'rope_drop', same, [(8, 'L', 0), (2, 'L', 1), (24, 'L', 0), (4, '-', 0),
                                  (80, 'D', 0), (20, '-', 0)], outdir)
    record(e, 'ledge_death', at(0x2C, 0x1F), [(40, 'L', 0), (200, '-', 0), (20, 'R', 0)], outdir)
    record(e, 'wall_bounce', at(0x2C, 0x1F), [(4, 'R', 0), (2, 'R', 1), (120, 'R', 0)], outdir)
    record(e, 'jump_spam', same, [(3, 'L', 1), (3, 'L', 0)] * 30, outdir)


if __name__ == '__main__':
    main()
