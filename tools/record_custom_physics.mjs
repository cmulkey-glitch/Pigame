// Record player runs with non-ROM physics settings, for checking that the BrightScript player
// (tests/roku/tests.brs) handles the editor's sliders exactly like the JS one. Replays the
// maps and inputs of some ROM traces through the JS player under a few parameter sets.
// Usage: node tools/record_custom_physics.mjs   -> tests/traces/physics_custom.json
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { Room } from '../src/game/room.js';
import { Player } from '../src/game/player.js';
import { physicsFrom } from '../src/game/physics.js';

const traces = join(dirname(fileURLToPath(import.meta.url)), '..', 'tests', 'traces');

const SETS = [
  { stepFrames: 2, walkSpeed: 2, airSpeed: 2, jumpSpeed: 6.5, gravity: 0.5 },
  { gravity: 1.25, maxFallSpeed: 8, deadlyFallSpeed: 9, wallBounce: 0 },
  { stepFrames: 3, airControl: 1, climbUpSpeed: 2, climbDownSpeed: 3, ropeHoldSteps: 3, deadlyFallSpeed: 4 },
];
const RUNS = ['walk', 'jump_running', 'jump_spam', 'wall_bounce', 'rope', 'rope_drop', 'ledge_death'];

function loadPlayer(s, physics) {
  const p = new Player(physics);
  p.x = s.x; p.y = s.y; p.facing = s.facing;
  p.vyHi = s.vyHi; p.vyLo = s.vyLo;
  p.air = !!(s.f1 & 0x01); p.vertical = !!(s.f1 & 0x02); p.regen = !!(s.f1 & 0x04);
  p.jumpLatch = !!(s.f1 & 0x08); p.dead = !!(s.f1 & 0x10); p.running = !!(s.f1 & 0x20);
  p.climbing = !!(s.f1 & 0x40); p.hanging = !!(s.fa & 0x01);
  p.holdCount = s.hold; p.hangSide = s.hangSide; p.midairDeath = s.midair; p.splat = s.splat;
  p.lives = s.lives;
  return p;
}

const f1 = (p) => (p.air ? 0x01 : 0) | (p.air && p.vertical ? 0x02 : 0) | (p.regen ? 0x04 : 0) |
  (p.jumpLatch ? 0x08 : 0) | (p.dead ? 0x10 : 0) | (p.running ? 0x20 : 0) | (p.climbing ? 0x40 : 0);

const input = (s) => ({
  isDown: (k) => ({ left: s.includes('L'), right: s.includes('R'), up: s.includes('U'),
                    down: s.includes('D'), jump: s.includes('J') })[k],
});

const cases = [];
SETS.forEach((set, n) => {
  for (const run of RUNS) {
    const t = JSON.parse(readFileSync(join(traces, run + '.json')));
    const room = Object.create(Room.prototype);
    room.codes = Uint8Array.from(t.start.map);
    const p = loadPlayer(t.start, physicsFrom(set));
    const frames = t.frames.map((f) => {
      p.update(room, input(f.in), f.frame);
      p.events.length = 0;
      return { in: f.in, frame: f.frame, x: p.x, y: p.y, f1: f1(p), vyHi: p.vyHi, vyLo: p.vyLo,
               fa: +p.hanging, hold: p.holdCount };
    });
    cases.push({ name: `set${n + 1}_${run}`, physics: set, start: t.start, frames });
  }
});
writeFileSync(join(traces, 'physics_custom.json'), JSON.stringify({ cases }));
console.log(`${cases.length} runs recorded`);
