// Chamber viewer: loads extracted data, runs the ported player logic, draws chamber + HUD.
// Platform-agnostic: everything goes through the `platform` object (see src/platform/web.js).
//
// Game logic uses 7800 coordinates (x = hpos, y = line from the top of the HUD row). On the
// 320x200 canvas that is px = x*2 - 8 (tile column c at 16c) and py = y (HUD row at 0).

import { Room, decodeTiles, glyphBits, ROOM_W, ROOM_H, TILE_W, TILE_H, OBJ, FACE_RIGHT } from './room.js';
import { Player } from './player.js';

const HUD_H = 8;
const toPx = (x) => x * 2 - 8;
const SCORE = { [OBJ.KEY]: 250, [OBJ.DIAMOND]: 350, [OBJ.RING]: 350 };  // + random 0..99 ($C74F)

export class Game {
  constructor(platform) {
    this.p = platform;
    this.player = new Player();
    this.room = null;
    this.roomIndex = 0;
    this.score = 0;
    this.keys = 0;
    this.frame = 0;
    this.gameOver = false;
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
    this.sprites = sprites.sprites;
    this.playerFrames = sprites.playerFrames;
    this.spriteSheet = spriteBmp;
    this.surfaces = new Map();
    // Chamber 0 start: bottom floor, as the ROM places the player.
    this.enterRoom(0, { x: 0x88, y: 0xB7, facing: FACE_RIGHT }, true);
  }

  enterRoom(index, spawn, regenerating = false) {
    this.roomIndex = index;
    this.room = new Room(this.defs[index], this.tiles);
    if (!this.surfaces.has(index)) this.surfaces.set(index, this.p.makeSurface(ROOM_W, ROOM_H, this.room.rgba));
    this.surface = this.surfaces.get(index);
    this.player.reset(spawn || this.defaultSpawn(), regenerating);
  }

  defaultSpawn() {
    const d = this.room.def.doors[0];
    return d ? Room.doorSpawn(d.at) : { x: 0x50, y: 0x1F, facing: FACE_RIGHT };
  }

  restart() {
    this.player = new Player();
    this.score = 0; this.keys = 0; this.gameOver = false;
    this.enterRoom(0, { x: 0x88, y: 0xB7, facing: FACE_RIGHT }, true);
  }

  update() {
    const { input } = this.p;
    for (const k of input.takePressed()) {
      const n = this.defs.length;
      if (k === ']') this.enterRoom((this.roomIndex + 1) % n);
      else if (k === '[') this.enterRoom((this.roomIndex + n - 1) % n);
      else if (k >= '0' && k <= '9') this.enterRoom(+k);
      else if (k === 'x' || k === 'X') this.enterRoom(10);
      else if ((k === 'r' || k === 'R') && this.gameOver) this.restart();
    }
    if (this.gameOver) return;

    const pl = this.player;
    pl.update(this.room, input, this.frame);
    for (const ev of pl.events.splice(0)) this.handle(ev);
    this.frame = (this.frame + 1) & 0xFF;
  }

  handle(ev) {
    const pl = this.player;
    if (ev.type === 'pickup') {
      this.score += (SCORE[ev.code] || 0) + Math.floor(Math.random() * 100);
      if (ev.code === OBJ.KEY) this.keys++;
    } else if (ev.type === 'door') {
      // [$BEA5] Match the door by row and wall side in the ROM's door table.
      const row = ((pl.y + 7) & 0xFF) >> 3;
      const door = this.room.def.doors.find((d) => d.at.side === ev.side && (d.at.raw & 0x7F) === row);
      if (door) this.enterRoom(door.to, Room.doorSpawn(door.arrive));
    } else if (ev.type === 'gameover') {
      this.gameOver = true;
    }
  }

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

  sprite(index, x, y) {
    const s = this.sprites[index];
    this.p.gfx.blit(this.spriteSheet, s.x, s.y, s.w, s.h, x, y);
  }

  render() {
    const g = this.p.gfx;
    const def = this.room.def;
    const pal = def.palettesRGB;
    g.clear('#000');

    g.draw(this.surface, 0, HUD_H);
    for (const o of this.room.doorTiles)
      this.drawBits(this.tiles[o.code >> 1], TILE_W, TILE_H, o.col * TILE_W, HUD_H + o.row * TILE_H, pal[2][2]);
    for (const it of this.room.items()) {
      const color = it.code === OBJ.KEY ? pal[4][2] : it.code === OBJ.RING ? pal[2][2] : pal[5][2];
      this.drawBits(this.tiles[it.code >> 1], TILE_W, TILE_H, it.col * TILE_W, HUD_H + it.row * TILE_H, color);
    }

    const pl = this.player;
    const [head, legs] = this.playerFrames[pl.frame(this.frame)];
    this.sprite(head, toPx(pl.x), pl.y);
    this.sprite(legs, toPx(pl.x), pl.y + 8);

    g.rect(0, 0, 320, HUD_H, '#000');
    this.text(String(this.score).padStart(6, '0'), 0, 0, pal[7][2]);
    this.text('L' + pl.lives + ' K' + this.keys, 64, 0, pal[4][2]);
    const title = this.gameOver ? 'GAME OVER R' : def.name;
    this.text(title, 320 - 8 * title.length, 0, pal[7][2]);
  }
}
