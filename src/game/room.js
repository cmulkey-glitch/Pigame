// Chamber geometry: renders the tile map and builds pixel collision masks.

export const TILE_W = 16, TILE_H = 8;
export const MAP_W = 20, MAP_H = 24;
export const ROOM_W = MAP_W * TILE_W, ROOM_H = MAP_H * TILE_H;   // 320 x 192

export const TILE_ROPE = 1;
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
    this.solid = new Uint8Array(ROOM_W * ROOM_H);
    this.rope = new Uint8Array(ROOM_W * ROOM_H);
    this.rgba = new Uint8ClampedArray(ROOM_W * ROOM_H * 4);
    for (let row = 0; row < MAP_H; row++) {
      for (let col = 0; col < MAP_W; col++) {
        const t = def.tiles[row][col];
        if (!t) continue;
        const [r, g, b] = hexRGB(def.palettesRGB[def.tilePalette[row][col]][2]);
        const bits = tiles[t];
        const mask = t === TILE_ROPE ? this.rope : this.solid;
        for (let y = 0; y < TILE_H; y++) {
          for (let x = 0; x < TILE_W; x++) {
            if (!bits[y * TILE_W + x]) continue;
            const i = (row * TILE_H + y) * ROOM_W + col * TILE_W + x;
            mask[i] = 1;
            this.rgba.set([r, g, b, 255], i * 4);
          }
        }
      }
    }
    // Items to collect; door tiles are scenery.
    this.items = def.objects
      .filter((o) => o.code >= OBJ.DIAMOND)
      .map((o) => ({ ...o, x: o.col * TILE_W, y: o.row * TILE_H, taken: false }));
    this.doorTiles = def.objects.filter((o) => o.code < OBJ.DIAMOND);
  }

  isSolid(x, y) {
    if (x < 0 || x >= ROOM_W || y < 0) return false;
    if (y >= ROOM_H) return true;
    return this.solid[y * ROOM_W + x] === 1;
  }

  isRope(x, y) {
    if (x < 0 || x >= ROOM_W || y < 0 || y >= ROOM_H) return false;
    return this.rope[y * ROOM_W + x] === 1;
  }

  // Top-left player position for a door record from rooms.json (game y is relative to the HUD row).
  static doorSpawn(pos) {
    return { x: pos.x * 2 - 8, y: pos.y - 8, facing: pos.side === 'right' ? -1 : 1 };
  }
}
