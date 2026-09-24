// Replays ROM traces (tests/traces/*.json, from tools/trace_player.py) through the JS player
// and checks it matches the 7800 frame for frame. Run: node tests/physics.test.mjs
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { Room } from '../src/game/room.js';
import { Player } from '../src/game/player.js';

const dir = join(dirname(fileURLToPath(import.meta.url)), 'traces');

function makeRoom(map) {
  const room = Object.create(Room.prototype);
  room.codes = Uint8Array.from(map);
  return room;
}

function loadPlayer(s) {
  const p = new Player();
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
for (const file of readdirSync(dir).filter((f) => f.endsWith('.json')).sort()) {
  const t = JSON.parse(readFileSync(join(dir, file)));
  const room = makeRoom(t.start.map);
  const p = loadPlayer(t.start);
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
process.exit(failed ? 1 : 0);
