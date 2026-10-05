// Replays ROM traces (tests/traces/*.json, from tools/trace_player.py) through the JS player
// and checks it matches the 7800 frame for frame. Run: node tests/physics.test.mjs
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { Room } from '../src/game/room.js';
import { Player } from '../src/game/player.js';
import { physicsFrom, jumpProfile } from '../src/game/physics.js';

const dir = join(dirname(fileURLToPath(import.meta.url)), 'traces');

function makeRoom(map) {
  const room = Object.create(Room.prototype);
  room.codes = Uint8Array.from(map);
  return room;
}

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

// Flags in $F1 layout. Bit 1 ("vertical") is only meaningful in the air, so it's masked out
// on the ground where the ROM leaves stale values we don't track.
function f1(p) {
  let v = (p.air ? 0x01 : 0) | (p.regen ? 0x04 : 0) | (p.jumpLatch ? 0x08 : 0) |
          (p.dead ? 0x10 : 0) | (p.running ? 0x20 : 0) | (p.climbing ? 0x40 : 0);
  if (p.air) v |= p.vertical ? 0x02 : 0;
  return v;
}

const input = (s) => ({
  isDown: (k) => ({ left: s.includes('L'), right: s.includes('R'), up: s.includes('U'),
                    down: s.includes('D'), jump: s.includes('J') })[k],
});

let failed = 0;
// ROM traces, plus runs with non-ROM physics (tools/record_custom_physics.mjs; mainly there
// for the BrightScript player, here they guard against the JS player drifting).
const runs = [];
for (const file of readdirSync(dir).filter((f) => f.endsWith('.json') && !f.startsWith('drops_')).sort()) {
  const t = JSON.parse(readFileSync(join(dir, file)));
  if (t.cases) runs.push(...t.cases);
  else if (t.start && t.start.facing !== undefined) runs.push(t);   // else not a player trace
}
for (const t of runs) {
  const room = makeRoom(t.start.map);
  const p = loadPlayer(t.start, physicsFrom(t.physics));
  let bad = null;
  t.frames.forEach((f, i) => {
    if (bad) return;
    p.update(room, input(f.in), f.frame);
    p.events.length = 0;
    const romF1 = f.f1 & ((f.f1 & 1) ? 0xFF : 0xFD);
    const got = { x: p.x, y: p.y, f1: f1(p), vyHi: p.vyHi, vyLo: p.vyLo, hang: +p.hanging, hold: p.holdCount };
    const want = { x: f.x, y: f.y, f1: romF1, vyHi: f.vyHi, vyLo: f.vyLo, hang: f.fa & 1, hold: f.hold };
    const airOnly = ['vyHi', 'vyLo'];   // stale on the ground in the ROM
    const diff = Object.keys(want).filter((k) => got[k] !== want[k] && !(airOnly.includes(k) && !(f.f1 & 1)));
    if (diff.length) bad = { i, in: f.in, diff, got, want };
  });
  if (bad) {
    failed++;
    const hex = (o) => Object.entries(o).map(([k, v]) => `${k}=${v.toString(16).toUpperCase()}`).join(' ');
    console.log(`FAIL ${t.name} at frame ${bad.i} (input ${bad.in}): ${bad.diff.join(', ')}`);
    console.log(`     js : ${hex(bad.got)}\n     rom: ${hex(bad.want)}`);
  } else {
    console.log(`ok   ${t.name} (${t.frames.length} frames)`);
  }
}
// The editor's jump readout (jumpProfile) against the real player: a running jump on a flat
// floor, over a sweep of settings.
{
  let checked = 0;
  const bad = [];
  for (const jumpSpeed of [2, 3.5, 5.5, 7, 8]) for (const gravity of [0.25, 0.5, 0.75, 1.25, 2])
  for (const maxFallSpeed of [3, 7, 8]) for (const deadlyFallSpeed of [3, 7, 9]) for (const airSpeed of [0, 1, 3]) {
    const set = { jumpSpeed, gravity, maxFallSpeed, deadlyFallSpeed, airSpeed };
    const prof = jumpProfile(set);
    if (prof.distance > 0x8C - 0x30 || prof.height > 170) continue;   // would leave the screen
    const ph = physicsFrom(set);
    const room = makeRoom(Array.from({ length: 480 }, (_, i) => (i >= 460 ? 4 : 0)));   // floor on row 23
    const p = new Player(ph);
    p.reset({ x: 0x30, y: 183, facing: 2 });
    const jump = input('RJ'), none = input('');
    let f = 1, top = 183, dead = false;
    p.update(room, jump, f);
    while (p.air && f < 4000) { p.update(room, none, ++f); top = Math.min(top, p.y); dead ||= p.dead; }
    if (prof.height !== 183 - top || prof.distance !== p.x - 0x30 || prof.kills !== dead)
      bad.push(`${JSON.stringify(set)}: player ${183 - top}/${p.x - 0x30}/${dead} profile ${prof.height}/${prof.distance}/${prof.kills}`);
    checked++;
  }
  if (bad.length) { failed++; console.log(`FAIL jump readout: ${bad.length}/${checked} differ, e.g. ${bad[0]}`); }
  else console.log(`ok   jump readout matches the player (${checked} settings)`);
}
process.exit(failed ? 1 : 0);
