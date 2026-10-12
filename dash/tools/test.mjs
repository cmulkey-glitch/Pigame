// Run dash/tests/tests.brs (physics checks, and every stage replays its stored solution) against
// dash/roku/source/game.brs and world.brs with the brs interpreter, then compile-check dash/roku with
// BrighterScript, whose parser matches the device (the regular and the ad-supported build).
// Needs `npm install -g brs brighterscript`, or BRS= / BSC= paths to the binaries.
// Usage: node dash/tools/test.mjs
import { spawnSync } from 'node:child_process';
import { appendFileSync, copyFileSync, cpSync, mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const dash = join(dirname(fileURLToPath(import.meta.url)), '..');
const root = join(dash, '..');
// the brs interpreter's own script (brs-device.cjs loads brs's lib/ next to it): BRS=, or the global
// npm install; `shell` so Windows finds npm.cmd
const npmRoot = spawnSync('npm', ['root', '-g'], { encoding: 'utf8', shell: true }).stdout.trim();
const brs = process.env.BRS || join(npmRoot, 'brs', 'bin', 'cli.js');
// brs-device.cjs wraps brs with the Roku's shared for-each iterator (see that file).
const r = spawnSync(process.execPath, [join(root, 'tools', 'brs-device.cjs'), brs, '--root', dash,
  join(dash, 'roku', 'source', 'game.brs'), join(dash, 'roku', 'source', 'world.brs'),
  join(dash, 'tests', 'tests.brs')], { encoding: 'utf8' });
process.stdout.write(r.stdout || '');
process.stderr.write(r.stderr || '');
const bsc = spawnSync(process.env.BSC || 'bsc', ['--root-dir', join(dash, 'roku'), '--create-package', 'false',
  '--staging-dir', join(root, 'dist', 'bsc-staging-dash')], { encoding: 'utf8', shell: true });
const errors = (bsc.stdout || '') + (bsc.stderr || '');
let compiled = bsc.status === 0 && !/ error /.test(errors);
console.log(compiled ? 'ok   device compile check (bsc)' : 'FAIL device compile check (bsc)\n' + errors);
// the ad-supported build (build.py --ads): dash/roku with dash/roku-ads/ads.brs swapped in
const adsDir = mkdtempSync(join(tmpdir(), 'ads-'));
cpSync(join(dash, 'roku'), adsDir, { recursive: true });
copyFileSync(join(dash, 'roku-ads', 'ads.brs'), join(adsDir, 'source', 'ads.brs'));
appendFileSync(join(adsDir, 'manifest'), readFileSync(join(dash, 'roku-ads', 'manifest.extra')));
const bscAds = spawnSync(process.env.BSC || 'bsc', ['--root-dir', adsDir, '--create-package', 'false',
  '--staging-dir', join(root, 'dist', 'bsc-staging-dash-ads')], { encoding: 'utf8', shell: true });
const adsErrors = (bscAds.stdout || '') + (bscAds.stderr || '');
const adsOk = bscAds.status === 0 && !/ error /.test(adsErrors);
console.log(adsOk ? 'ok   device compile check, ads build (bsc)' : 'FAIL device compile check, ads build (bsc)\n' + adsErrors);
compiled = compiled && adsOk;
const nested = /device for-each/.test(r.stderr || '');
process.exit(/ALL PASS/.test(r.stdout || '') && compiled && !nested ? 0 : 1);
