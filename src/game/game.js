// Chamber viewer: loads extracted data, runs the player, draws chamber + HUD.
// Platform-agnostic: everything goes through the `platform` object (see src/platform/web.js).

import { Room, decodeTiles, glyphBits, ROOM_W, ROOM_H, TILE_W, TILE_H, OBJ } from './room.js';
import { Player } from './player.js';

const HUD_H = 8;
const SCORE = { [OBJ.DIAMOND]: 1000, [OBJ.RING]: 500, [OBJ.KEY]: 200 };

// Indexes into assets/sprites.json (player = head over legs).
const SPR = {
  drop: 0,
  stand: [5, 6],
  run: [[1, 2], [3, 4], [7, 8], [3, 4]],
  climb: [25, 26],
  jump: [27, 28],
  splat: [31, 32],
};

export class Game {
  constructor(platform) {
    this.p = platform;
    this.player = new Player();
    this.room = null;
    this.roomIndex = 0;
    this.score = 0;
    this.keys = 0;
    this.showCollision = false;
    this.flash = 0;
  }

  async load(base = '.') {
    const p = this.p;
    const [rooms, tileBmp, sprites, spriteBmp] = await Promise.all([
      p.loadJSON(base + '/data/rooms.json'),
      p.loadBitmap(base + '/assets/tiles.png'),
      p.loadJSON(base + '/assets/sprites.json'),
      p.loadBitmap(base + '/assets/sprites.png'),
    ]);
    this.defs = rooms.rooms;
    this.tiles = decodeTiles(tileBmp);
    this.tileSheet = tileBmp;
    this.sprites = sprites.sprites;
    this.spriteSheet = spriteBmp;
    this.surfaces = new Map();
    this.enterRoom(0, { x: 128, y: 160, facing: 1 });
  }

  enterRoom(index, spawn) {
    this.roomIndex = index;
    this.room = new Room(this.defs[index], this.tiles);
    const key = index;
    if (!this.surfaces.has(key)) this.surfaces.set(key, this.p.makeSurface(ROOM_W, ROOM_H, this.room.rgba));
    this.surface = this.surfaces.get(key);
    this.collisionSurface = null;
    this.spawn = spawn || this.defaultSpawn();
    this.player.reset(this.spawn);
  }

  defaultSpawn() {
    const d = this.room.def.doors[0];
    return d ? Room.doorSpawn(d.at) : { x: 150, y: 0, facing: 1 };
  }

  update() {
    const { input } = this.p;
    for (const k of input.takePressed()) {
      const n = this.defs.length;
      if (k === ']') this.enterRoom((this.roomIndex + 1) % n);
      else if (k === '[') this.enterRoom((this.roomIndex + n - 1) % n);
      else if (k >= '0' && k <= '9') this.enterRoom(+k);
      else if (k === 'x' || k === 'X') this.enterRoom(10);
      else if (k === 'g' || k === 'G') this.showCollision = !this.showCollision;
    }

    const pl = this.player;
    pl.update(this.room, input);
    if (pl.state === 'dead' && pl.deadTimer > 90) pl.reset(this.spawn);

    const side = pl.exitSide();
    if (side) {
      const door = this.room.def.doors
        .filter((d) => d.at.side === side)
        .map((d) => ({ d, dist: Math.abs(Room.doorSpawn(d.at).y - pl.y) }))
        .sort((a, b) => a.dist - b.dist)[0];
      if (door && door.dist <= 12) {
        this.enterRoom(door.d.to, Room.doorSpawn(door.d.arrive));
      } else {
        pl.x = side === 'left' ? 12 : 276;
      }
    }

    for (const it of this.room.items) {
      if (it.taken) continue;
      if (pl.x + 12 > it.x && pl.x + 4 < it.x + TILE_W && pl.y + 16 > it.y && pl.y < it.y + TILE_H) {
        it.taken = true;
        this.score += SCORE[it.code] || 0;
        if (it.code === OBJ.KEY) this.keys++;
      }
    }
    this.flash++;
  }

  // Draw a 1bpp tile or glyph in a solid colour.
  drawBits(bits, w, h, x, y, color) {
    const g = this.p.gfx;
    for (let yy = 0; yy < h; yy++)
      for (let xx = 0; xx < w; xx++)
        if (bits[yy * w + xx]) g.rect(x + xx, y + yy, 1, 1, color);
  }

  text(str, x, y, color) {
    for (const ch of str) {
      let b = null;
      if (ch >= '0' && ch <= '9') b = 0xC1 + (ch.charCodeAt(0) - 48);
      else if (ch >= 'A' && ch <= 'Z') b = 0xCC + (ch.charCodeAt(0) - 65);
      if (b !== null) this.drawBits(glyphBits(this.tiles, b), 8, 8, x, y, color);
      x += 8;
    }
  }

  sprite(index, x, y, flip) {
    const s = this.sprites[index];
    this.p.gfx.blit(this.spriteSheet, s.x, s.y, s.w, s.h, x, y, flip);
  }

  render() {
    const g = this.p.gfx;
    const def = this.room.def;
    const pal = def.palettesRGB;
    g.clear('#000');
    const oy = HUD_H;

    g.draw(this.surface, 0, oy);
    if (this.showCollision) this.drawCollision(oy);

    for (const o of this.room.doorTiles)
      this.drawBits(this.tiles[o.code >> 1], TILE_W, TILE_H, o.col * TILE_W, oy + o.row * TILE_H, pal[2][2]);
    for (const it of this.room.items) {
      if (it.taken) continue;
      const color = it.code === OBJ.KEY ? pal[4][2] : it.code === OBJ.RING ? pal[2][2] : pal[5][2];
      this.drawBits(this.tiles[it.code >> 1], TILE_W, TILE_H, it.x, oy + it.y, color);
    }

    const pl = this.player;
    const flip = pl.facing < 0;
    let frame;
    if (pl.state === 'dead') frame = SPR.splat;
    else if (pl.state === 'climb') frame = SPR.climb;
    else if (pl.state === 'air') frame = SPR.jump;
    else if (this.p.input.isDown('left') || this.p.input.isDown('right'))
      frame = SPR.run[Math.floor(pl.anim / 6) % SPR.run.length];
    else frame = SPR.stand;
    const climbFlip = pl.state === 'climb' ? Math.floor(pl.anim / 8) % 2 === 1 : flip;
    if (pl.state !== 'dead' || this.flash % 20 < 14) {
      this.sprite(frame[0], pl.x, oy + pl.y, climbFlip);
      this.sprite(frame[1], pl.x, oy + pl.y + 8, climbFlip);
    }

    g.rect(0, 0, 320, HUD_H, '#000');
    this.text(String(this.score).padStart(6, '0'), 0, 0, pal[7][2]);
    this.text('K' + this.keys, 64, 0, pal[4][2]);
    this.text(def.name, 320 - 8 * def.name.length, 0, pal[7][2]);
  }

  drawCollision(oy) {
    if (!this.collisionSurface) {
      const rgba = new Uint8ClampedArray(ROOM_W * ROOM_H * 4);
      for (let i = 0; i < ROOM_W * ROOM_H; i++) {
        if (this.room.solid[i]) rgba.set([255, 0, 0, 160], i * 4);
        else if (this.room.rope[i]) rgba.set([0, 255, 0, 160], i * 4);
      }
      this.collisionSurface = this.p.makeSurface(ROOM_W, ROOM_H, rgba);
    }
    this.p.gfx.draw(this.collisionSurface, 0, oy);
    const b = this.player.box;
    this.p.gfx.rect(b.x, oy + b.y + b.h, b.w, 1, '#ff0');
  }
}
