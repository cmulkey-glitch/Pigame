// Solve every stage of every level with the real BrightScript game code (dash/tests/solve.brs
// in the brs interpreter) and write the inputs to dash/tests/solutions/N.txt, which
// dash/tools/test.mjs replays. Run after changing levels or physics (python3
// dash/tools/levelgen.py rewrites the levels). Levels run in parallel; a few minutes in all.
// Needs `npm install -g brs`, or BRS= the path to it.
// Usage: node dash/tools/solve.mjs [level numbers...]
//        node dash/tools/solve.mjs pool [tiers...]   (the random-world pool, dash/roku/pool/T.txt,
//                                                     to dash/tests/solutions/poolT.txt)
// A number can name stages, as in `pool 4:3,17`: only those are solved, and their lines replace
// the ones in the solutions file (for stages whose dash/tools/pysolve.py solution fails the
// replay in dash/tools/test.mjs).
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { cpus, tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const dash = join(dirname(fileURLToPath(import.meta.url)), '..');
const root = join(dash, '..');
// the brs interpreter's own script (brs-device.cjs loads brs's lib/ next to it): BRS=, or the global
// npm install; `shell` so Windows finds npm.cmd
const npmRoot = spawnSync('npm', ['root', '-g'], { encoding: 'utf8', shell: true }).stdout.trim();
const brs = process.env.BRS || join(npmRoot, 'brs', 'bin', 'cli.js');
const pool = process.argv[2] === 'pool';
const args = process.argv.slice(pool ? 3 : 2);
const dir = pool ? 'pool' : 'levels';
const all = readdirSync(join(dash, 'roku', dir)).filter((f) => /^\d+\.txt$/.test(f))
  .map((f) => parseInt(f)).sort((a, b) => a - b);
const levels = args.length ? args : all.map(String);
const what = pool ? 'tier' : 'level';
const tmp = mkdtempSync(join(tmpdir(), 'solve-'));
mkdirSync(join(dash, 'tests', 'solutions'), { recursive: true });

function solve(arg) {
  const [n, only = ''] = arg.split(':');
  const entry = join(tmp, `main${n}_${only.replace(/,/g, '_')}.brs`);
  writeFileSync(entry, `sub Main()\n    Solve_level("pkg:/roku/${dir}/${n}.txt", "${only}")\nend sub\n`);
  return new Promise((done) => {
    const p = spawn(process.execPath, [join(root, 'tools', 'brs-device.cjs'), brs, '--root', dash,
      join(dash, 'roku', 'source', 'game.brs'), join(dash, 'tests', 'solve.brs'), entry]);
    let out = '';
    p.stdout.on('data', (d) => { out += d; });
    p.stderr.on('data', (d) => process.stderr.write(d));
    p.on('close', () => {
      const lines = out.split('\n').filter((l) => /^(STAGE|STAGES|STUCK) /.test(l));
      const stuck = lines.filter((l) => l.startsWith('STUCK'));
      const stages = lines.filter((l) => l.startsWith('STAGE '));
      const count = lines.find((l) => l.startsWith('STAGES '));
      const want = only ? only.split(',').length : Number(count?.split(' ')[1]);
      if (stuck.length || !count || stages.length !== want) {
        console.log(`${what} ${n}: FAILED ${stuck.join('; ') || out.trim()}`);
        done(false);
        return;
      }
      const file = join(dash, 'tests', 'solutions', `${pool ? 'pool' : ''}${n}.txt`);
      let result = stages;
      if (only && existsSync(file)) {
        const mine = Object.fromEntries(stages.map((l) => [l.split(' ')[1], l]));
        result = readFileSync(file, 'utf8').trim().split('\n').map((l) => mine[l.split(' ')[1]] || l);
      }
      writeFileSync(file, result.join('\n') + '\n');
      console.log(`${what} ${arg}: solved`);
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
