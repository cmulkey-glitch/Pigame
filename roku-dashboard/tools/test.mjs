// Run tests/tests.brs against source/lib with the brs interpreter (Roku for-each semantics via
// the repo's tools/brs-device.cjs), then compile-check the app with BrighterScript.
// Needs `npm install -g brs brighterscript`, or BRS= / BSC= paths to the binaries.
// Usage: node roku-dashboard/tools/test.mjs
import { spawnSync } from 'node:child_process';
import { readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const app = join(dirname(fileURLToPath(import.meta.url)), '..');
const lib = readdirSync(join(app, 'source', 'lib')).filter((f) => f.endsWith('.brs'))
  .map((f) => join(app, 'source', 'lib', f));
const brs = process.env.BRS || spawnSync('which', ['brs'], { encoding: 'utf8' }).stdout.trim();
const r = spawnSync(process.execPath, [join(app, '..', 'tools', 'brs-device.cjs'), brs, '--root', app, ...lib,
  join(app, 'tests', 'tests.brs')], { encoding: 'utf8' });
process.stdout.write(r.stdout || '');
process.stderr.write(r.stderr || '');
const bsc = spawnSync(process.env.BSC || 'bsc', ['--root-dir', app, '--create-package', 'false',
  '--staging-dir', join(app, '..', 'dist', 'dashboard-bsc-staging')], { encoding: 'utf8' });
const errors = (bsc.stdout || '') + (bsc.stderr || '');
const compiled = bsc.status === 0 && !/ error /.test(errors);
console.log(compiled ? 'ok   device compile check (bsc)' : 'FAIL device compile check (bsc)\n' + errors);
const nested = /device for-each/.test(r.stderr || '');
process.exit(/ALL PASS/.test(r.stdout || '') && compiled && !nested ? 0 : 1);
