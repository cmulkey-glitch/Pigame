// Checks src/game/drops.js against ROM traces (tests/traces/drops_*.json, from
// tools/trace_drops.py). Run: node tests/drops.test.mjs
//  1. spawn tables built from rooms.json equal the ROM's RAM tables after chamber load
//  2. one JS update from each ROM frame gives the next ROM frame (spawns, which depend on the
//     shared RNG, are checked against the table and timer range instead)
//  3. the JS hit test agrees with every drop death in the trace
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { Room } from '../src/game/room.js';
import { Drops } from '../src/game/drops.js';
import { Rng } from '../src/game/rng.js';

const here = dirname(fileURLToPath(import.meta.url));
const rooms = JSON.parse(readFileSync(join(here, '..', 'data', 'rooms.json'))).rooms;
const dir = join(here, 'traces');
let failed = 0;

for (const file of readdirSync(dir).filter((f) => f.startsWith('drops_')).sort()) {
  const t = JSON.parse(readFileSync(join(dir, file)));
  const { room: ri, difficulty } = t.start;
  const room = Object.create(Room.prototype);
  room.codes = Uint8Array.from(t.start.map);
  const drops = new Drops(rooms[ri], ri, difficulty, new Rng());
  const errors = [];

  // 1. spawn tables and slot count
  drops.spawns.forEach((s, i) => {
    const [x, y] = t.start.spawns[i];
    if (s.x !== x || s.y !== y) errors.push(`spawn ${i}: js ${s.x},${s.y} rom ${x},${y}`);
  });
  if (drops.slots.length !== t.start.lastSlot + 1)
    errors.push(`slots: js ${drops.slots.length} rom ${t.start.lastSlot + 1}`);
  const n = drops.slots.length;
  const warn = difficulty === 0 ? 0x10 : 0;

  // 2. single-step equivalence
  let steps = 0, spawnsSeen = 0, drop_deaths = 0, fall_deaths = 0, ball_deaths = 0;
  for (let k = 0; k + 1 < t.frames.length && errors.length < 5; k++) {
    if (t.frames[k + 1].frame === t.frames[k].frame) continue;   // lag frame: logic didn't run
    const cur = t.frames[k].drops, next = t.frames[k + 1].drops;
    drops.slots = cur.slice(0, n).map(([x, y, timer, spawn]) => ({ x, y, timer, spawn }));
    drops.rng = { next: () => 1 };          // never spawn inside the step; checked below
    drops.update(room);
    for (let i = 0; i < n; i++) {
      const [x, y, timer, spawn] = next[i];
      const d = drops.slots[i];
      if (cur[i][3] === 0xFF && spawn !== 0xFF) {
        spawnsSeen++;
        const s = drops.spawns[spawn];
        if (s.x !== x || s.y !== y || timer < 0x38 + warn || timer > 0x3F + warn)
          errors.push(`frame ${k + 1} slot ${i}: bad spawn ${x},${y} t=${timer} idx ${spawn}`);
      } else if (d.spawn !== spawn || (spawn !== 0xFF && (d.x !== x || d.y !== y || d.timer !== timer))) {
        errors.push(`frame ${k + 1} slot ${i}: js ${d.x},${d.y},${d.timer},${d.spawn} rom ${x},${y},${timer},${spawn}`);
      }
      steps++;
    }

    // 3. drop collision: ROM checks at frame k+1 with the player and drops from frame k
    const a = t.frames[k], b = t.frames[k + 1];
    if (a.f1 & 0x14) continue;                // regenerating or dead: no check
    drops.slots = cur.slice(0, n).map(([x, y, timer, spawn]) => ({ x, y, timer, spawn }));
    const hit = drops.hits(a.x, a.y);
    const died = !!(b.f1 & 0x10);
    if (hit && !died) errors.push(`frame ${k + 1}: js says drop hit, ROM player lived`);
    if (died && !hit) {
      // [$B7F0] ball/bird box, checked on tick 2
      const [bx, by] = a.ball;
      const ball = bx && ((a.x + 6 - bx) & 0xFF) < 10 && ((a.y + 14 - by) & 0xFF) < 22;
      if (a.air) fall_deaths++;               // landing death
      else if (ball) ball_deaths++;
      else errors.push(`frame ${k + 1}: ROM player died on the ground, js saw no drop or ball hit`);
    }
    if (died && hit) drop_deaths++;
  }

  if (errors.length) {
    failed++;
    console.log(`FAIL ${t.name}\n  ` + errors.slice(0, 5).join('\n  '));
  } else {
    console.log(`ok   ${t.name} (${t.frames.length} frames, ${steps} slot steps, ${spawnsSeen} spawns, ` +
                `${drop_deaths} drop deaths, ${fall_deaths} fall, ${ball_deaths} ball)`);
  }
}
process.exit(failed ? 1 : 0);
