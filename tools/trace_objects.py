#!/usr/bin/env python3
"""Record chamber object placement from the 7800 ROM for tests/doors.test.mjs.

Usage: trace_objects.py path/to/Downland.a78 [outfile]   (default: tests/traces/objects.json)

- rooms: the RAM tile map of every chamber right after loading it in a fresh game
  (treasures, keys and doors placed from the initial game state)
- keyPickup: chamber 0's map before and after the player falls through the first key,
  which should open door 0 on the right wall
- allKeys: every key in every chamber, dropped through the same way in a fresh game, with
  the doors ($24C2) that the pickup opened
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(__file__))
import a7800emu
from a7800emu import Emu
from extract_downland import boot, snapshot, restore, load_room
from trace_player import ram_map, ZP


def main():
    a7800emu.load_rom(sys.argv[1])
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), '..', 'tests', 'traces', 'objects.json')
    e = Emu()
    e.mem.m[0xB7A2] = e.mem.m[0xB7F0] = 0x60   # no drop/ball deaths while we poke the player
    boot(e)
    base = snapshot(e)
    rooms = []
    for r in range(11):
        restore(e, base)
        load_room(e, r)
        rooms.append(ram_map(e))

    restore(e, base)
    load_room(e, 0)
    before = ram_map(e)
    # Drop the player through the key at column 5, row 6 (x+3 in the column, y+15 in the row).
    e.mem.m[0x20ED], e.mem.m[0x20EE] = 0x2A, 0x2D
    e.mem.m[0x20F1] = 0x03                     # in the air, vertical
    e.mem.m[0x20F2], e.mem.m[0x20F3] = 0xFF, 0x00
    for _ in range(8):
        e.run_frame()
    after = ram_map(e)
    key_pickup = {'before': before, 'after': after,
                  'keysLeft': [e.mem.m[0x2496 + i] for i in range(44)],
                  'doorOpen': [e.mem.m[0x24C2 + i] for i in range(36)]}

    all_keys = []
    for r in range(11):
        for slot in range(r * 4, r * 4 + 4):
            col, row = e.mem.m[0xF487 + slot], e.mem.m[0xF4B3 + slot]   # ROM key tables
            if col == 0xFF:
                continue
            restore(e, base)
            load_room(e, r)
            doors = [e.mem.m[0x24C2 + i] for i in range(36)]
            e.mem.m[0x20ED], e.mem.m[0x20EE] = 4 + 8 * col - 2, 8 + 8 * row - 11
            e.mem.m[0x20F1] = 0x03
            e.mem.m[0x20F2], e.mem.m[0x20F3] = 0xFF, 0x00
            for _ in range(12):
                e.run_frame()
            opened = [i for i in range(36) if e.mem.m[0x24C2 + i] != doors[i]]
            all_keys.append({'chamber': r, 'slot': slot, 'col': col, 'row': row,
                             'taken': e.mem.m[0x2496 + slot] == 0, 'opened': opened})
    json.dump({'rooms': rooms, 'keyPickup': key_pickup, 'allKeys': all_keys}, open(out, 'w'))
    print('keys: ' + ', '.join('c%d slot %d -> %s' % (k['chamber'], k['slot'], k['opened']) for k in all_keys))
    changed = [(i % 20, i // 20, before[i], after[i]) for i in range(480) if before[i] != after[i]]
    print('rooms recorded: %d; key pickup changed cells: %s' % (len(rooms), changed))


if __name__ == '__main__':
    main()
