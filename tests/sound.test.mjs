// Checks src/game/sound.js against the ROM's sound driver (tests/traces/sound.json, from
// tools/trace_sound.py). Replays every playsfx call, stop-all and driver tick in ROM order
// and compares the TIA sound registers (AUDF0/1, AUDC0/1, AUDV0/1) after every frame.
// Run: node tests/sound.test.mjs
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { SoundDriver } from '../src/game/sound.js';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const { sounds } = JSON.parse(readFileSync(join(root, 'data', 'sounds.json')));
const { events } = JSON.parse(readFileSync(join(root, 'tests', 'traces', 'sound.json')));

const driver = new SoundDriver(sounds);
let frame = 0, started = false, bad = null;
const plays = {};
for (const ev of events) {
  if (ev[0] === 'play') { driver.play(ev[1], ev[2]); plays[ev[1]] = (plays[ev[1]] || 0) + 1; started = true; }
  else if (ev[0] === 'stop') { driver.stopAll(); started = true; }
  else if (ev[0] === 'tick') driver.update();
  else if (ev[0] === 'regs') {
    const [f0, f1, c0, c1, v0, v1] = ev[1];
    if (!started) {                         // leftovers from before the trace: adopt them
      driver.regs = [{ f: f0, c: c0, v: v0 }, { f: f1, c: c1, v: v1 }];
    } else {
      const r = driver.regs;
      const got = [r[0].f, r[1].f, r[0].c, r[1].c, r[0].v, r[1].v];
      if (!bad && got.some((v, i) => v !== ev[1][i])) bad = { frame, got, want: ev[1] };
    }
    frame++;
  }
}
if (bad) {
  console.log(`FAIL sound registers at frame ${bad.frame}: js ${bad.got} rom ${bad.want}`);
  process.exit(1);
}
console.log(`ok   sound driver: ${frame} frames match, sounds played: ${JSON.stringify(plays)}`);
