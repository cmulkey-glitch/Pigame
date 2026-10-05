// Solve every stage of every level with the real BrightScript game code (dash/tests/solve.brs
// in the brs interpreter) and write the inputs to dash/tests/solutions/N.txt, which
// dash/tools/test.mjs replays. Run after changing levels or physics (python3
// dash/tools/levelgen.py rewrites the levels). Levels run in parallel; a few minutes in all.
// Needs `npm install -g brs`, or BRS= the path to it.
// Usage: node dash/tools/solve.mjs [level numbers...]
import { spawn, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readdirSync, writeFileSync } from 'node:fs';
import { cpus, tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const dash = join(dirname(fileURLToPath(import.meta.url)), '..');
const root = join(dash, '..');
const brs = process.env.BRS || spawnSync('which', ['brs'], { encoding: 'utf8' }).stdout.trim();
const all = readdirSync(join(dash, 'roku', 'levels')).filter((f) => /^\d+\.txt$/.test(f))
  .map((f) => parseInt(f)).sort((a, b) => a - b);
const levels = process.argv.length > 2 ? process.argv.slice(2).map(Number) : all;
const tmp = mkdtempSync(join(tmpdir(), 'solve-'));
mkdirSync(join(dash, 'tests', 'solutions'), { recursive: true });

function solve(n) {
  const entry = join(tmp, `main${n}.brs`);
  writeFileSync(entry, `sub Main()\n    Solve_level("pkg:/roku/levels/${n}.txt")\nend sub\n`);
  return new Promise((done) => {
    const p = spawn(process.execPath, [join(root, 'tools', 'brs-device.cjs'), brs, '--root', dash,
      join(dash, 'roku', 'source', 'game.brs'), join(dash, 'tests', 'solve.brs'), entry]);
    let out = '';
    p.stdout.on('data', (d) => { out += d; });
    p.stderr.on('data', (d) => process.stderr.write(d));
    p.on('close', () => {
      const lines = out.split('\n').filter((l) => /^(STAGE|STUCK) /.test(l));
      const stuck = lines.filter((l) => l.startsWith('STUCK'));
      const stages = lines.filter((l) => l.startsWith('STAGE'));
      if (stuck.length || stages.length !== 4) {
        console.log(`level ${n}: FAILED ${stuck.join('; ') || out.trim()}`);
        done(false);
        return;
      }
      writeFileSync(join(dash, 'tests', 'solutions', `${n}.txt`), stages.join('\n') + '\n');
      console.log(`level ${n}: solved`);
      done(true);
    });
  });
}

const queue = [...levels];
let ok = true;
await Promise.all(Array.from({ length: Math.min(cpus().length, queue.length) }, async () => {
  while (queue.length) ok = (await solve(queue.shift())) && ok;
}));
process.exit(ok ? 0 : 1);
