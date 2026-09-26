// Run dash/tests/tests.brs (physics checks, and every level must be beatable) against
// dash/roku/source/game.brs with the brs interpreter, then compile-check dash/roku with
// BrighterScript, whose parser matches the device.
// Needs `npm install -g brs brighterscript`, or BRS= / BSC= paths to the binaries.
// Usage: node dash/tools/test.mjs   (the level search takes a minute or two)
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const dash = join(dirname(fileURLToPath(import.meta.url)), '..');
const root = join(dash, '..');
const brs = process.env.BRS || spawnSync('which', ['brs'], { encoding: 'utf8' }).stdout.trim();
// brs-device.cjs wraps brs with the Roku's shared for-each iterator (see that file).
const r = spawnSync(process.execPath, [join(root, 'tools', 'brs-device.cjs'), brs, '--root', dash,
  join(dash, 'roku', 'source', 'game.brs'), join(dash, 'tests', 'tests.brs')], { encoding: 'utf8' });
process.stdout.write(r.stdout || '');
process.stderr.write(r.stderr || '');
const bsc = spawnSync(process.env.BSC || 'bsc', ['--root-dir', join(dash, 'roku'), '--create-package', 'false',
  '--staging-dir', join(root, 'dist', 'bsc-staging-dash')], { encoding: 'utf8' });
const errors = (bsc.stdout || '') + (bsc.stderr || '');
const compiled = bsc.status === 0 && !/ error /.test(errors);
console.log(compiled ? 'ok   device compile check (bsc)' : 'FAIL device compile check (bsc)\n' + errors);
const nested = /device for-each/.test(r.stderr || '');
process.exit(/ALL PASS/.test(r.stdout || '') && compiled && !nested ? 0 : 1);
