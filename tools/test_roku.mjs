// Run tests/roku/tests.brs (the ROM trace checks) against roku/source with the brs
// interpreter. Needs `npm install -g brs` or BRS=/path/to/brs.
// Usage: node tools/test_roku.mjs
import { spawnSync } from 'node:child_process';
import { readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const game = readdirSync(join(root, 'roku', 'source')).filter((f) => f.endsWith('.brs') && f !== 'main.brs')
  .map((f) => join(root, 'roku', 'source', f));
const brs = process.env.BRS || 'brs';
const r = spawnSync(brs, ['--root', root, ...game, join(root, 'tests', 'roku', 'tests.brs')], { encoding: 'utf8' });
process.stdout.write(r.stdout || '');
process.stderr.write(r.stderr || '');
process.exit(/ALL PASS/.test(r.stdout || '') ? 0 : 1);
