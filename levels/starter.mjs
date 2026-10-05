// Starter level pack: four original chambers that make one round, each built around one idea.
// Build: node tools/build_levels.mjs levels/starter.mjs   (-> levels/starter.json)
// Check: node tools/solve_pack.mjs levels/starter.json
//
// Map: 24 rows of 20 characters, columns 0-19 (18 is the right wall, 19 stays empty).
//   _ floor (stand on it; you can jump up through it)   | rope   = bar   T rope top
//   [ ] walls   \ / slopes   # pillar   u ceiling knot   r l ledge lips
//   v stalactites: drops fall from these (dropEvery thins them out, dropRows limits the rows)
//   D diamond   O ring   lowercase letter: a key, opening the door named in `keys`
// Doors sit in column 0 (left) or 18 (right); `row` is the floor row you stand on in front of
// them, and the door fills that row and the two above. `to` is the chamber it leads to; you
// arrive at the door there that leads back. `locked` doors open when their key is picked up.
// A key can open a door in another chamber: name it "chamber:door".

export default {
  name: 'Starter caves',
  // Round: 0 -> 1 -> 2 -> 3 -> back to 0. No bonus chamber.
  rules: { start: { x: 0x88, y: 0xB7, facing: 1 }, loopFrom: 3, escape: -1 },
  chambers: [
    {
      // Walk, climb, jump through a floor from below, and a key that opens the way out.
      name: 'FIRST LIGHT',
      colors: { 0: '#3e8ede', 7: '#e8d9a8', 2: '#7bd389', 4: '#ff9f43', 5: '#c8f7ff' },
      dropEvery: 3,
      dropRows: [13],   // only under the middle platform: a quiet first walk
      map: [
        './vvvvvvvvvvvvvvv\\..',
        '[.................].',
        '[.................].',
        '[.................].',
        '[...........______].',
        '[..............|..].',
        '[..............|..].',
        '[..............|..].',
        '[..............|..].',
        '[..............|..].',
        '[..............|..].',
        '[.k........O...|..].',
        '[.____________.|..].',
        '[.vvvvvv|vvvvv....].',
        '[.......|.........].',
        '[.......|.........].',
        '[.......|.........].',
        '[.......|.........].',
        '[.......|.........].',
        '[.......|.........].',
        '[.......|.........].',
        '[.......|.........].',
        '[...D...|.........].',
        '[_________________].',
      ],
      doors: [
        { name: 'exit', side: 'right', row: 4, to: 1, locked: true },
        { name: 'back', side: 'left', row: 23, to: 3, locked: true },   // where a round ends up
      ],
      keys: { k: 'exit' },
    },
    {
      // Rope to rope across a drop. Jump, catch the next rope lower down, climb, jump again.
      name: 'ROPE WALK',
      colors: { 0: '#b86bd6', 7: '#f2e6c9', 2: '#7bd389', 4: '#ff9f43', 5: '#9fe7ff' },
      dropEvery: 2,
      map: [
        './vvvvvuvvuvvuvvv\\..',
        '[......|..|..|....].',
        '[......|..|k.|....].',
        '[......|..|..|....].',
        '[_____.|..|..|....].',
        '[......|..|..|....].',
        '[......|..|..|....].',
        '[......|..|..|....].',
        '[......|..|..|....].',
        '[......|D.|..|..O.].',
        '[......|..|..|.___].',
        '[......|..|..|....].',
        '[......|..|..|....].',
        '[......|..|..|....].',
        '[......|..|.D|....].',
        '[......|..|..|....].',
        '[......|..|..|....].',
        '[......|..|..|....].',
        '[......|..|..|....].',
        '[......|..|..|....].',
        '[......|..|..|....].',
        '[......|..|..|....].',
        '[.................].',
        '[_________________].',
      ],
      doors: [
        { name: 'back', side: 'left', row: 4, to: 0 },
        { name: 'exit', side: 'right', row: 10, to: 2 },
      ],
      keys: { k: '3:exit' },   // opens the vault in chamber 3
    },
    {
      // Zig-zag down under falling drops; the key at the far end opens the exit at the bottom.
      // The rope by the left wall is the way back up.
      name: 'ZIGZAG',
      colors: { 0: '#d9534f', 7: '#f5e1b8', 2: '#7bd389', 4: '#ffd23f', 5: '#bdf2ff' },
      dropEvery: 2,
      map: [
        './vvvvvvvvvvvvvvv\\..',
        '[.................].',
        '[.................].',
        '[.................].',
        '[________.........].',
        '[|vvvvvvv........k].',
        '[|................].',
        '[|.....___________].',
        '[|................].',
        '[|.......O........].',
        '[|__________......].',
        '[|vvvvvvvvv.......].',
        '[|..........D.....].',
        '[|.....___________].',
        '[|................].',
        '[|.D..............].',
        '[|__________......].',
        '[|vvvvvvvvv.......].',
        '[|................].',
        '[|.....___________].',
        '[|................].',
        '[|................].',
        '[_________________].',
        '[.................].',
      ],
      doors: [
        { name: 'back', side: 'left', row: 4, to: 1 },
        { name: 'exit', side: 'right', row: 22, to: 3, locked: true },
      ],
      keys: { k: 'exit' },
    },
    {
      // Climb out of the vault. Its door home needs the key from ROPE WALK.
      name: 'THE VAULT',
      colors: { 0: '#e0a526', 7: '#fff3d6', 2: '#7bd389', 4: '#ff7bac', 5: '#a6f4ff' },
      dropEvery: 3,
      map: [
        './vvvvvvvvvvvvvvv\\..',
        '[.................].',
        '[...........D.....].',
        '[.................].',
        '[...........______].',
        '[............|....].',
        '[............|....].',
        '[....O.......|....].',
        '[..._______..|....].',
        '[..vvvv|vvv..|....].',
        '[......|.....|....].',
        '[......|.....|....].',
        '[......|.....|....].',
        '[......|.....|....].',
        '[......|.....|....].',
        '[......|.....|....].',
        '[......|.....|....].',
        '[......|.....|....].',
        '[......|.....|....].',
        '[......|.....|....].',
        '[......|..D..|....].',
        '[......|.....|..D.].',
        '[_________________].',
        '[.................].',
      ],
      doors: [
        { name: 'back', side: 'left', row: 22, to: 2 },
        { name: 'exit', side: 'right', row: 4, to: 0, locked: true },
      ],
      keys: {},
    },
  ],
};
