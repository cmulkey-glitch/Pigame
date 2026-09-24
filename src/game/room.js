// Chamber data: renders the tile map and answers tile-code queries for collision.

export const TILE_W = 16, TILE_H = 8;
export const MAP_W = 20, MAP_H = 24;
export const ROOM_W = MAP_W * TILE_W, ROOM_H = MAP_H * TILE_H;   // 320 x 192

export const FACE_LEFT = 1, FACE_RIGHT = 2;   // $F0 values
export const OBJ = { DOOR_TOP: 0x1A, DOOR_MID: 0x1C, DOOR_BOT: 0x1E, DIAMOND: 0x20, RING: 0x22, KEY: 0x24 };

// Decode the 1bpp tile atlas (16 tiles per row) into per-tile bit arrays.
export function decodeTiles(bitmap) {
  const perRow = bitmap.width / TILE_W;
  const count = perRow * (bitmap.height / TILE_H);
  const tiles = [];
  for (let n = 0; n < count; n++) {
    const bits = new Uint8Array(TILE_W * TILE_H);
    const ox = (n % perRow) * TILE_W, oy = Math.floor(n / perRow) * TILE_H;
    for (let y = 0; y < TILE_H; y++)
      for (let x = 0; x < TILE_W; x++)
        bits[y * TILE_W + x] = bitmap.data[((oy + y) * bitmap.width + ox + x) * 4 + 3] > 127 ? 1 : 0;
    tiles.push(bits);
  }
  return tiles;
}

// 8x8 glyph from the font half of a double-byte char ($C1 = '0', $CC = 'A').
export function glyphBits(tiles, byte) {
  const t = tiles[byte >> 1], half = (byte & 1) * 8;
  const out = new Uint8Array(64);
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) out[y * 8 + x] = t[y * TILE_W + half + x];
  return out;
}

function hexRGB(hex) {
  const v = parseInt(hex.slice(1), 16);
  return [v >> 16, (v >> 8) & 255, v & 255];
}

export class Room {
  constructor(def, tiles) {
    this.def = def;
    this.rgba = new Uint8ClampedArray(ROOM_W * ROOM_H * 4);
    for (let row = 0; row < MAP_H; row++) {
      for (let col = 0; col < MAP_W; col++) {
        const t = def.tiles[row][col];
        if (!t) continue;
        const [r, g, b] = hexRGB(def.palettesRGB[def.tilePalette[row][col]][2]);
        const bits = tiles[t];
        for (let y = 0; y < TILE_H; y++) {
          for (let x = 0; x < TILE_W; x++) {
            if (!bits[y * TILE_W + x]) continue;
            const i = (row * TILE_H + y) * ROOM_W + col * TILE_W + x;
            this.rgba.set([r, g, b, 255], i * 4);
          }
        }
      }
    }
    // Tile codes as the ROM's collision sees them (RAM map at $2200). Terrain comes from the
    // chamber map (object cells already blank); placeObjects() adds items, keys and doors.
    this.codes = new Uint8Array(MAP_W * MAP_H);
    for (let row = 0; row < MAP_H; row++)
      for (let col = 0; col < MAP_W; col++) this.codes[row * MAP_W + col] = def.tiles[row][col] * 2;
  }

  // [$AE4F] Write the chamber's objects from game state into the map: uncollected treasures
  // and keys, and each door open ($1A/$1C/$1E) or closed (wall $08 left, $0A right).
  placeObjects(state) {
    for (const t of this.def.treasures)
      this.setCell(t.col, t.row, state.treasure[t.slot]);
    for (const k of this.def.keys)
      this.setCell(k.col, k.row, state.keyDoor[k.slot] ? OBJ.KEY : 0);
    for (const d of this.def.doors) this.setDoor(d.id, state.doorOpen[d.id]);
  }

  // [$AEFD / $B4AE] Door cells: column 0 or 18, three rows ending at the door's row.
  setDoor(id, open) {
    const d = this.def.doors.find((door) => door.id === id);
    if (!d) return;
    const col = d.at.side === 'right' ? 18 : 0, row = d.at.raw & 0x7F;
    const closed = d.at.side === 'right' ? 0x0A : 0x08;
    const codes = open ? [OBJ.DOOR_BOT, OBJ.DOOR_MID, OBJ.DOOR_TOP] : [closed, closed, closed];
    codes.forEach((c, i) => this.setCell(col, row - i, c));
  }

  setCell(col, row, code) {
    if (col < MAP_W && row < MAP_H) this.codes[row * MAP_W + col] = code;
  }

  cellAt(x, y) {
    return { col: ((x - 4) & 0xFF) >> 3, row: ((y - 8) & 0xFF) >> 3 };
  }

  // Tile code under a point in 7800 coordinates ($C6F3): x = MARIA hpos, y = line with 0 at the
  // top of the HUD row. Column c starts at x = 4 + 8c, row r at y = 8 + 8r.
  tileAt(x, y) {
    const col = ((x - 4) & 0xFF) >> 3, row = ((y - 8) & 0xFF) >> 3;
    if (col >= MAP_W || row >= MAP_H) return 0;
    return this.codes[row * MAP_W + col];
  }

  clearTileAt(x, y) {
    const { col, row } = this.cellAt(x, y);
    this.setCell(col, row, 0);
  }

  // Objects currently in the map (items, open doors, closed-door walls), for drawing.
  *objects() {
    for (const d of this.def.doors) {
      const col = d.at.side === 'right' ? 18 : 0, row = d.at.raw & 0x7F;
      for (let r = row - 2; r <= row; r++) yield { code: this.codes[r * MAP_W + col], col, row: r };
    }
    for (let i = 0; i < this.codes.length; i++)
      if (this.codes[i] >= OBJ.DIAMOND && this.codes[i] <= OBJ.KEY)
        yield { code: this.codes[i], col: i % MAP_W, row: Math.floor(i / MAP_W) };
  }

  // Player position for a door record from rooms.json (already in 7800 coordinates).
  static doorSpawn(pos) {
    return { x: pos.x, y: pos.y, facing: pos.side === 'right' ? FACE_LEFT : FACE_RIGHT };
  }
}
