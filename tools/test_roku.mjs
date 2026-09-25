// Run tests/roku/tests.brs (the ROM trace checks) against roku/source with the brs
// interpreter, then compile-check roku/ with BrighterScript, whose parser matches the device
// (brs accepts things the Roku compiler rejects, e.g. `pos` as a variable).
// Needs `npm install -g brs brighterscript`, or BRS= / BSC= paths to the binaries.
// Usage: node tools/test_roku.mjs
import { spawnSync } from 'node:child_process';
import { readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const game = readdirSync(join(root, 'roku', 'source')).filter((f) => f.endsWith('.brs') && f !== 'main.brs')
  .map((f) => join(root, 'roku', 'source', f));
// brs-device.cjs wraps brs with the Roku's shared for-each iterator (see that file).
const brs = process.env.BRS || spawnSync('which', ['brs'], { encoding: 'utf8' }).stdout.trim();
const r = spawnSync(process.execPath, [join(root, 'tools', 'brs-device.cjs'), brs, '--root', root, ...game,
  join(root, 'tests', 'roku', 'tests.brs')], { encoding: 'utf8' });
process.stdout.write(r.stdout || '');
process.stderr.write(r.stderr || '');
const bsc = spawnSync(process.env.BSC || 'bsc', ['--root-dir', join(root, 'roku'), '--create-package', 'false',
  '--staging-dir', join(root, 'dist', 'bsc-staging')], { encoding: 'utf8' });
const errors = (bsc.stdout || '') + (bsc.stderr || '');
const compiled = bsc.status === 0 && !/ error /.test(errors);
console.log(compiled ? 'ok   device compile check (bsc)' : 'FAIL device compile check (bsc)\n' + errors);
const nested = /device for-each/.test(r.stderr || '');
process.exit(/ALL PASS/.test(r.stdout || '') && compiled && !nested ? 0 : 1);
