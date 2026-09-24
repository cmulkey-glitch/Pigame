#!/usr/bin/env python3
"""Record the chamber-0 / chamber-X door rules from the 7800 ROM for tests/rules.test.mjs.

Usage: trace_rules.py path/to/Downland.a78 [outfile]   (default: tests/traces/rules.json)

Each case walks the player out of a chamber's right-hand door and records where the ROM
ends up: chamber, player position/facing, difficulty, timer, whether collected items were
restored, and whether the escape ending is running.
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(__file__))
import a7800emu
from a7800emu import Emu
from extract_downland import boot, snapshot, restore, load_room
from trace_player import JOY, ZP

bcd = lambda v: (v >> 4) * 10 + (v & 15)


def case(e, base, name, room, door_row, escape, difficulty, prev_room):
    restore(e, base)
    m = e.mem.m
    m[0x215F] = difficulty
    load_room(e, room)
    if escape:
        m[0x20FA] |= 0x08
    else:
        m[0x20FA] &= ~0x08 & 0xFF
    m[0x2157] = prev_room               # $0157: chamber we came from
    m[0x246A] = 0                       # pretend chamber 0's first treasure was collected
    # Stand in front of the right-hand door on its row and open it.
    m[0x20ED], m[0x20EE] = 0x8C, door_row * 8 - 1
    m[0x20F1] = 0x00
    for d in range(36):
        m[0x24C2 + d] = 1
    load_room(e, room)                  # redraw with the door open
    m[0x20ED], m[0x20EE] = 0x8C, door_row * 8 - 1
    m[0x20F1] = 0x00
    prev_timer = bcd(m[0x2159]) * 100 + bcd(m[0x215A])
    timer = lambda: bcd(m[0x21AA]) * 100 + bcd(m[0x21AB])
    e.joy = JOY['R']
    timer_before = timer_after = None
    for _ in range(40):
        before = timer()
        e.run_frame()
        if m[0x2146] != room and timer_after is None:
            timer_before, timer_after = before, timer()
    e.joy = JOY['-']
    for _ in range(200):                # let the new chamber finish revealing
        e.run_frame()
    # The ending loop ($C58B) never advances the frame counter $E6; play does.
    f0 = ZP(e, 0xE6)
    for _ in range(20):
        e.run_frame()
    ending = ZP(e, 0xE6) == f0
    out = {'name': name, 'from': room, 'escape': escape, 'difficultyBefore': difficulty,
           'prevRoom': prev_room, 'room': m[0x2146], 'x': ZP(e, 0xED), 'y': ZP(e, 0xEE),
           'facing': ZP(e, 0xF0), 'difficulty': m[0x215F],
           'timerBefore': timer_before, 'prevTimer': prev_timer, 'timer': timer_after,
           'itemsReset': m[0x246A] != 0,
           'ending': ending}
    print(out)
    return out


def main():
    a7800emu.load_rom(sys.argv[1])
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), '..', 'tests', 'traces', 'rules.json')
    e = Emu()
    e.mem.m[0xB7A2] = e.mem.m[0xB7F0] = 0x60
    boot(e)
    base = snapshot(e)
    rom = a7800emu.ROM
    rd = lambda a: rom[a - 0x8000]
    row9 = rd(0xF53B + 33) & 0x7F       # chamber 9's right door (to chamber 0)
    rowX = rd(0xF53B + 35) & 0x7F       # chamber X's right door (to chamber 0)
    row0 = rd(0xF53B + 0) & 0x7F        # chamber 0's right door (to chamber 1)
    cases = [case(e, base, 'looping_9_to_0', 9, row9, False, 1, 8),
             case(e, base, 'escape_9_to_X', 9, row9, True, 1, 8),
             case(e, base, 'hard_stays_hard', 9, row9, False, 2, 8),
             case(e, base, 'escape_X_to_0', 10, rowX, True, 1, 9),
             case(e, base, 'ordinary_0_to_1', 0, row0, True, 1, 1)]
    json.dump(cases, open(out, 'w'), indent=1)


if __name__ == '__main__':
    main()
