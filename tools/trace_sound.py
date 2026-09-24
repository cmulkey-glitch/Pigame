#!/usr/bin/env python3
"""Record sound driver activity from the 7800 ROM for tests/sound.test.mjs.

Usage: trace_sound.py path/to/Downland.a78 [outfile]   (default: tests/traces/sound.json)

Plays a scripted run (walking, jumping into walls, climbing, dying, picking things up)
and logs, in the order they happen, every playsfx call ($F8D9: sound address and pitch
offset), stop-all ($F832) and driver tick ($F83F), plus the TIA sound registers
AUDF0/1, AUDC0/1, AUDV0/1 after every tick.
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(__file__))
import a7800emu
from a7800emu import Emu
from extract_downland import boot, SOUNDS
from trace_player import JOY

NAMES = {a: n for n, a in SOUNDS.items()}


def main():
    a7800emu.load_rom(sys.argv[1])
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), '..', 'tests', 'traces', 'sound.json')
    e = Emu()
    e.mem.m[0xB7A2] = 0x60                      # no drop deaths, so the run is repeatable
    boot(e)
    m = e.mem.m
    events = []
    regs = lambda: [e.regs[0x17], e.regs[0x18], e.regs[0x15], e.regs[0x16], e.regs[0x19], e.regs[0x1A]]

    def on_play():
        addr = m[0x20E0] | m[0x20E1] << 8
        events.append(['play', NAMES.get(addr, '$%04X' % addr), m[0x20E2]])

    def on_stop():
        events.append(['stop'])

    def on_tick():
        events.append(['tick'])

    e.pc_hooks = {0xF8D9: on_play, 0xF832: on_stop, 0xF83F: on_tick}
    def key_drop():                             # fall through chamber 0's first key, score 9800
        m[0x20ED], m[0x20EE], m[0x20F1], m[0x20F2], m[0x20F3] = 0x2A, 0x2D, 0x03, 0xFF, 0
        m[0x21A6], m[0x21A7], m[0x21A8] = 0x00, 0x98, 0x00

    def ledge():                                # top ledge, facing the drop
        m[0x20ED], m[0x20EE], m[0x20F1] = 0x2C, 0x1F, 0x00

    def right_wall():                           # bottom floor next to the right wall
        m[0x20ED], m[0x20EE], m[0x20F1] = 0x8C, 0xB7, 0x00

    # (frames, stick, fire, action before the first frame)
    script = [(80, 'L', 0, None), (5, '-', 0, None),                   # leave regeneration, run
              (8, 'L', 0, None), (2, 'L', 1, None), (24, 'L', 0, None), (4, '-', 0, None),  # onto rope
              (40, 'U', 0, None), (30, 'D', 0, None), (80, 'D', 0, None),                   # climb, drop
              (10, '-', 0, right_wall), (4, 'R', 0, None), (2, 'R', 1, None), (60, 'R', 0, None),  # bump
              (40, '-', 0, key_drop),                                                       # pickup + life
              (60, 'L', 0, ledge), (200, '-', 0, None)]                                     # splat
    frames = 0
    for n, joy, fire, action in script:
        if action:
            action()
        for _ in range(n):
            e.joy, e.fire = JOY[joy], bool(fire)
            e.run_frame()
            events.append(['regs', regs()])
            frames += 1
    counts = {}
    for ev in events:
        if ev[0] == 'play':
            counts[ev[1]] = counts.get(ev[1], 0) + 1
    json.dump({'events': events}, open(out, 'w'))
    print('frames %d, ticks %d, stops %d, plays %s' % (frames, sum(1 for ev in events if ev[0] == 'tick'),
                                                     sum(1 for ev in events if ev[0] == 'stop'), counts))


if __name__ == '__main__':
    main()
