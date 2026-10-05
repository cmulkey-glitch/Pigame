// Build a level pack (the rooms.json format the game, editor and Roku build read) from ASCII
// chamber maps. See levels/starter.mjs for the format.
// Usage: node tools/build_levels.mjs levels/starter.mjs [out.json]   (default: same name, .json)
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join, resolve } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');

// map character -> tile in assets/tiles.png (the chamber editor's Paint tab has the same set)
export const LEGEND = {
  '.': 0, ' ': 0, '|': 1, '_': 2, 'v': 3, '[': 4, ']': 5, 'u': 6, '\\': 7, '/': 8, '#': 12,
  'r': 19, 'l': 20, '=': 21, 'T': 22,
};
const WALLS = new Set([3, 4, 5, 6, 7, 8, 12]);       // drawn in palette 0, the rest in palette 7
const OBJ = { D: 0x20, O: 0x22 };                    // diamond, ring; lowercase letters are keys

const doorPos = (side, row) => ({ raw: (side === 'right' ? 0x80 : 0) | row, side, x: side === 'right' ? 0x8D : 0x0B, y: row * 8 - 1 });

export function buildPack(design) {
  const rom = JSON.parse(readFileSync(join(root, 'data', 'rooms.json'), 'utf8'));
  const doorIds = new Map();     // "chamber:name" -> global door id
  design.chambers.forEach((c, id) => c.doors.forEach((d) => doorIds.set(`${id}:${d.name}`, doorIds.size)));
  const doorOpenInitial = [];
  const rooms = design.chambers.map((c, id) => {
    if (c.map.length !== 24) throw new Error(`${c.name}: the map has ${c.map.length} rows, not 24`);
    c.map.forEach((row, r) => {
      if (row.length !== 20) throw new Error(`${c.name}: map row ${r} has ${row.length} characters, not 20`);
    });
    const tiles = [], tilePalette = [], treasures = [], keys = [], drops = [];
    c.map.forEach((line, row) => {
      const tr = [], pr = [];
      [...line].forEach((ch, col) => {
        let t = LEGEND[ch];
        if (t === undefined) {
          if (OBJ[ch]) treasures.push({ slot: id * 4 + treasures.length, col, row, code: OBJ[ch] });
          else if (c.keys?.[ch]) keys.push({ slot: id * 4 + keys.length, col, row, ref: c.keys[ch] });
          else throw new Error(`${c.name}: unknown map character '${ch}' at col ${col} row ${row}`);
          t = 0;
        }
        if (t === 3 && (!c.dropRows || c.dropRows.includes(row))) {
          drops.push([8 * col + 10, 8 * row + 11]);           // under the stalactite tip
        }
        tr.push(t);
        pr.push(WALLS.has(t) ? 0 : 7);
      });
      tiles.push(tr);
      tilePalette.push(pr);
    });
    if (treasures.length > 4 || keys.length > 4) throw new Error(`${c.name}: at most 4 treasures and 4 keys`);
    const doors = c.doors.map((d) => {
      const doorId = doorIds.get(`${id}:${d.name}`);
      doorOpenInitial[doorId] = d.locked ? 0 : 1;
      const col = d.side === 'right' ? 18 : 0;
      for (let r = d.row - 2; r <= d.row; r++) tiles[r][col] = 0;   // the door replaces the wall
      return { id: doorId, at: doorPos(d.side, d.row), to: d.to, arrive: null, arriveAuto: true, name: d.name };
    });
    // a pick of the stalactites, spread through the chamber, repeated to the 32 entries the game draws from
    const pick = drops.filter((_, i) => i % (c.dropEvery || 3) === 0);
    const dropSpawns = pick.length ? Array.from({ length: 32 }, (_, i) => pick[i % pick.length]) : [];
    const palettesRGB = rom.rooms[0].palettesRGB.map((p) => p.slice());
    for (const [i, color] of Object.entries(c.colors)) palettesRGB[i][2] = color;
    return {
      id, name: c.name, tiles, tilePalette, objects: [], doors, treasures, keys,
      dropSpawns, dropTweak: Math.min(5, Math.max(1, dropSpawns.length - 1)), ball: null,
      palettesRGB, colorRGB: c.colors[0],
    };
  });
  // keys name a door as "chamber:door name" (or just the name for one in the same chamber)
  rooms.forEach((r) => r.keys.forEach((k) => {
    const ref = k.ref.includes(':') ? k.ref : `${r.id}:${k.ref}`;
    if (!doorIds.has(ref)) throw new Error(`${r.name}: key opens unknown door '${k.ref}'`);
    k.door = doorIds.get(ref);
    delete k.ref;
  }));
  // arrival: the door in the destination that leads back, else the opposite wall at the same row
  for (const r of rooms) {
    for (const d of r.doors) {
      const back = rooms[d.to].doors.find((o) => o.to === r.id);
      d.arrive = back ? { ...back.at } : doorPos(d.at.side === 'right' ? 'left' : 'right', d.at.raw & 0x7F);
    }
  }
  return {
    name: design.name, rooms, doorOpenInitial, title: rom.title,
    physics: design.physics || {}, rules: design.rules || {},
  };
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const src = resolve(process.argv[2] || join(root, 'levels', 'starter.mjs'));
  const out = process.argv[3] || src.replace(/\.mjs$/, '.json');
  const { default: design } = await import(pathToFileURL(src).href);
  const pack = buildPack(design);
  writeFileSync(out, JSON.stringify(pack));
  console.log(`${pack.rooms.length} chambers -> ${out}`);
}
