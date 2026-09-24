// Checks src/game/enemies.js (ball, bird, chamber timer) against ROM traces
// (tests/traces/enemies_*.json, from tools/trace_enemies.py). Run: node tests/enemies.test.mjs
// All three are deterministic, so positions and the timer must match on every frame, and
// every ball/bird death in the trace must be one the JS hit tests agree with.
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { Ball, Bird, TIMER_AFTER_BIRD_DEATH, TIMER_FULL } from '../src/game/enemies.js';

const here = dirname(fileURLToPath(import.meta.url));
const rooms = JSON.parse(readFileSync(join(here, '..', 'data', 'rooms.json'))).rooms;
const dir = join(here, 'traces');
let failed = 0;

for (const file of readdirSync(dir).filter((f) => f.startsWith('enemies_')).sort()) {
  const t = JSON.parse(readFileSync(join(dir, file)));
  const def = rooms[t.room];
  const s0 = t.start;
  let ball = null;
  if (def.ball) { ball = new Ball(def.ball, t.room); [ball.x, ball.y, ball.vy] = s0.ball; }
  let bird = null;
  if (s0.bird) { bird = new Bird(); [bird.x, bird.y, bird.dir] = s0.birdPos; }
  let timer = s0.timer;
  const errors = [];
  let prev = s0, deaths = 0;

  for (let i = 0; i < t.frames.length && errors.length < 5; i++) {
    const f = t.frames[i];
    if (f.frame === prev.frame) { prev = f; continue; }   // lag frame
    const tick = f.frame & 3;
    // ROM order: ball move (odd ticks), bird hit + move, timer, then splat end / respawn.
    const ballBefore = ball && { x: ball.x, y: ball.y };
    if (ball && (tick & 1)) ball.update(f.frame);
    const birdBefore = bird && { x: bird.x, y: bird.y };
    const birdHit = bird && !(prev.f1 & 0x10) && bird.hits(f.x, f.y);
    if (bird && !birdHit) bird.update();                  // a hit skips this frame's move
    const regen = !!(f.f1 & 4) && !((prev.f1 & 0x10) && !(f.f1 & 0x10));
    if (!regen && !bird && (t.difficulty !== 0 || !(f.frame & 1))) {
      timer = Math.max(0, timer - 1);
      if (timer === 0) bird = new Bird();
    }
    if ((prev.f1 & 0x10) && !(f.f1 & 0x10)) {           // splat ended: respawn
      bird = null;
      if (timer === 0) timer = t.room === 10 ? TIMER_FULL : TIMER_AFTER_BIRD_DEATH;
    }

    if (ball && (ball.x !== f.ball[0] || ball.y !== f.ball[1] || ball.vy !== f.ball[2]))
      errors.push(`frame ${i}: ball js ${ball.x},${ball.y},${ball.vy} rom ${f.ball.join(',')}`);
    if (!!bird !== f.bird) errors.push(`frame ${i}: bird js ${!!bird} rom ${f.bird}`);
    else if (bird && (bird.x !== f.birdPos[0] || bird.y !== f.birdPos[1] || bird.dir !== f.birdPos[2]))
      errors.push(`frame ${i}: bird js ${bird.x},${bird.y},${bird.dir} rom ${f.birdPos.join(',')}`);
    if (timer !== f.timer) errors.push(`frame ${i}: timer js ${timer} rom ${f.timer}`);

    // A new death on the ground must be a ball hit (tick 2, last frame's ball vs last frame's
    // player) or a bird hit (bird before moving vs this frame's player).
    if (!(prev.f1 & 0x10) && (f.f1 & 0x10) && !(prev.f1 & 1)) {
      const byBall = tick === 2 && ballBefore && !(prev.f1 & 4) &&
        ((prev.x + 6 - ballBefore.x) & 0xFF) < 10 && ((prev.y + 14 - ballBefore.y) & 0xFF) < 22;
      const byBird = birdBefore && ((f.x + 6 - birdBefore.x) & 0xFF) < 14 && ((f.y + 14 - birdBefore.y) & 0xFF) < 22;
      if (byBall || byBird) deaths++;
      else errors.push(`frame ${i}: ROM player died, js saw no ball or bird hit`);
    }
    prev = f;
  }
  if (errors.length) { failed++; console.log(`FAIL ${t.name}\n  ${errors.join('\n  ')}`); }
  else console.log(`ok   ${t.name} (${t.frames.length} frames, ${deaths} ball/bird deaths)`);
}
process.exit(failed ? 1 : 0);
