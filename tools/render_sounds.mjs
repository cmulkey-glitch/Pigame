// Render each sound effect to a WAV file with the same driver and TIA synth the web port
// uses: SoundDriver steps the effect at 60 frames/s, the TIA channel turns the registers into
// samples. For platforms that can play samples but not synthesize (Roku).
// Usage: node tools/render_sounds.mjs outdir   (climbing sounds get _0 / _1 pitch variants)
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { SoundDriver } from '../src/game/sound.js';
import { TIA_CLOCK, Channel } from '../src/platform/tia-synth.js';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = process.argv[2] || join(root, 'roku', 'sounds');
mkdirSync(out, { recursive: true });
const { sounds } = JSON.parse(readFileSync(join(root, 'data', 'sounds.json')));
const RATE = 22050, FRAME = RATE / 60;

function render(name, pitch) {
  const driver = new SoundDriver(sounds);
  driver.play(name, pitch);
  const ch = new Channel();
  const samples = [];
  let acc = 0, x1 = 0, y1 = 0;
  for (let frame = 0; frame < 600 && (frame === 0 || driver.ch[0].steps); frame++) {
    const r = driver.update()[0];
    ch.set(r.f, r.c, r.v);
    for (let i = 0; i < FRAME; i++) {
      acc += TIA_CLOCK / RATE;
      while (acc >= 1) { acc -= 1; ch.clock(); }
      const x = ch.level() / 15;
      const y = x - x1 + 0.995 * y1;       // remove the DC offset, as the web synth does
      x1 = x; y1 = y;
      samples.push(y * 0.6);
    }
  }
  for (let i = 0; i < RATE / 100; i++) samples.push(0);   // 10 ms tail
  return samples;
}

function wav(samples) {
  const buf = Buffer.alloc(44 + samples.length * 2);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + samples.length * 2, 4); buf.write('WAVE', 8);
  buf.write('fmt ', 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(1, 22);
  buf.writeUInt32LE(RATE, 24); buf.writeUInt32LE(RATE * 2, 28); buf.writeUInt16LE(2, 32); buf.writeUInt16LE(16, 34);
  buf.write('data', 36); buf.writeUInt32LE(samples.length * 2, 40);
  samples.forEach((s, i) => buf.writeInt16LE(Math.max(-32767, Math.min(32767, Math.round(s * 32767))), 44 + i * 2));
  return buf;
}

for (const name of Object.keys(sounds)) {
  const pitches = name.startsWith('climb') ? [0, 1] : [0];
  for (const p of pitches) {
    const file = name + (name.startsWith('climb') ? `_${p}` : '') + '.wav';
    const s = render(name, p);
    writeFileSync(join(out, file), wav(s));
    console.log(`${file.padEnd(16)} ${(s.length / RATE * 1000).toFixed(0)} ms`);
  }
}
