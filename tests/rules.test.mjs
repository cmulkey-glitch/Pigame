// Checks the chamber-0 / chamber-X door rules in src/game/game.js against the ROM
// (tests/traces/rules.json, from tools/trace_rules.py). Run: node tests/rules.test.mjs
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { Game } from '../src/game/game.js';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const cases = JSON.parse(readFileSync(join(root, 'tests', 'traces', 'rules.json')));

// Headless platform: real data files, blank bitmaps, no drawing.
const platform = {
  width: 320, height: 200,
  loadJSON: async (url) => JSON.parse(readFileSync(join(root, url))),
  loadBitmap: async () => ({ width: 256, height: 64, data: new Uint8ClampedArray(256 * 64 * 4) }),
  makeSurface: () => ({}),
  input: { isDown: () => false, takePressed: () => [] },
  gfx: new Proxy({}, { get: () => () => {} }),
};

const game = new Game(platform);
await game.load('.');
let failed = 0;

for (const c of cases) {
  game.difficulty = c.difficultyBefore;
  game.escapeMode = c.escape;
  game.startGame();
  game.difficulty = c.difficultyBefore;
  game.state.treasure[0] = 0;                  // chamber 0's first treasure already collected
  game.state.doorOpen.fill(1);
  game.enterRoom(c.from);
  game.prevRoom = c.prevRoom;
  game.prevTimer = c.prevTimer;
  game.timer = c.timerBefore;
  const door = game.room.def.doors.find((d) => d.at.side === 'right');
  game.player.reset({ x: 0x8D, y: door.at.y, facing: 2 });
  game.goThroughDoor('right');

  const ended = game.mode === 'escaped';
  const got = ended ? { ending: true, difficulty: game.difficulty } : {
    ending: false, room: game.roomIndex, x: game.player.x, y: game.player.y, facing: game.player.facing,
    difficulty: game.difficulty, timer: game.timer, itemsReset: game.state.treasure[0] !== 0,
  };
  const want = c.ending ? { ending: true, difficulty: c.difficulty } : {
    ending: false, room: c.room, x: c.x, y: c.y, facing: c.facing,
    difficulty: c.difficulty, timer: c.timer, itemsReset: c.itemsReset,
  };
  const diff = Object.keys(want).filter((k) => got[k] !== want[k]);
  if (diff.length) {
    failed++;
    console.log(`FAIL ${c.name}: ` + diff.map((k) => `${k} js ${got[k]} rom ${want[k]}`).join(', '));
  } else {
    console.log(`ok   ${c.name}` + (c.ending ? ' (escape ending)' : ` (chamber ${c.room}, timer ${c.timer})`));
  }
}
process.exit(failed ? 1 : 0);
