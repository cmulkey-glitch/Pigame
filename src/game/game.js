// Chamber viewer: loads extracted data, runs the ported player logic, draws chamber + HUD.
// Platform-agnostic: everything goes through the `platform` object (see src/platform/web.js).
//
// Game logic uses 7800 coordinates (x = hpos, y = line from the top of the HUD row). On the
// 320x200 canvas that is px = x*2 - 8 (tile column c at 16c) and py = y (HUD row at 0).

import { Room, decodeTiles, glyphBits, ROOM_W, ROOM_H, TILE_W, TILE_H, OBJ, FACE_RIGHT } from './room.js';
import { Player } from './player.js';
import { Drops } from './drops.js';
import { Rng } from './rng.js';
import { newGameState, collect } from './state.js';
import { Ball, Bird, TIMER_FULL, TIMER_AFTER_BIRD_DEATH, TIMER_CHAMBER_X, returnTimer } from './enemies.js';

const HUD_H = 8;
const toPx = (x) => x * 2 - 8;

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
    this.difficulty = 1;   // $015F: 0..2, the ROM's default is 1
    this.rng = new Rng();
    this.timer = TIMER_FULL;
    this.prevRoom = -1;    // $0157 / $0159: chamber we came from and its timer when we left
    this.prevTimer = 0;
  }

  newGameState() { return newGameState(this.defs, this.doorOpenInitial); }

  async load(base = '.') {
    const p = this.p;
    const [rooms, tileBmp, sprites, spriteBmp] = await Promise.all([
      p.loadJSON(base + '/data/rooms.json'),
      p.loadBitmap(base + '/assets/tiles.png'),
      p.loadJSON(base + '/assets/sprites.json'),
      p.loadBitmap(base + '/assets/sprites.png'),
    ]);
    this.defs = rooms.rooms;
    this.doorOpenInitial = rooms.doorOpenInitial;
    this.state = this.newGameState();
    this.tiles = decodeTiles(tileBmp);
    this.sprites = sprites.sprites;
    this.playerFrames = sprites.playerFrames;
    this.dropSprite = this.sprites.findIndex((sp) => sp.addr === '$E02E');
    this.ballFrames = sprites.ballFrames;
    this.birdFrames = sprites.birdFrames;
    this.spriteSheet = spriteBmp;
    this.surfaces = new Map();
    // Chamber 0 start: bottom floor, as the ROM places the player.
    this.enterRoom(0, { x: 0x88, y: 0xB7, facing: FACE_RIGHT }, true);
  }

  enterRoom(index, spawn, regenerating = false) {
    this.roomIndex = index;
    this.room = new Room(this.defs[index], this.tiles);
    this.room.placeObjects(this.state);
    this.drops = new Drops(this.defs[index], index, this.difficulty, this.rng);
    const ball = this.defs[index].ball;
    this.ball = ball ? new Ball(ball, index) : null;
    this.bird = null;      // [$8932] leaving a chamber clears the bird
    if (!this.surfaces.has(index)) this.surfaces.set(index, this.p.makeSurface(ROOM_W, ROOM_H, this.room.rgba));
    this.surface = this.surfaces.get(index);
    this.player.reset(spawn || this.defaultSpawn(), regenerating);
  }

  // Debug chamber select: fresh timer, no door history.
  jumpToRoom(index) {
    this.timer = index === 10 ? TIMER_CHAMBER_X : TIMER_FULL;
    this.prevRoom = -1;
    this.enterRoom(index);
  }

  defaultSpawn() {
    const d = this.room.def.doors[0];
    return d ? Room.doorSpawn(d.at) : { x: 0x50, y: 0x1F, facing: FACE_RIGHT };
  }

  restart() {
    this.player = new Player();
    this.score = 0; this.keys = 0; this.gameOver = false;
    this.state = this.newGameState();
    this.timer = TIMER_FULL; this.prevRoom = -1;
    this.enterRoom(0, { x: 0x88, y: 0xB7, facing: FACE_RIGHT }, true);
  }

  update() {
    const { input } = this.p;
    for (const k of input.takePressed()) {
      const n = this.defs.length;
      if (k === ']') this.jumpToRoom((this.roomIndex + 1) % n);
      else if (k === '[') this.jumpToRoom((this.roomIndex + n - 1) % n);
      else if (k >= '0' && k <= '9') this.jumpToRoom(+k);
      else if (k === 'x' || k === 'X') this.jumpToRoom(10);
      else if (k === 'r' || k === 'R') this.restart();
      else if (k === 'd' || k === 'D') { this.difficulty = (this.difficulty + 1) % 3; this.enterRoom(this.roomIndex); }
    }
    if (this.gameOver) return;

    // Same order as the ROM's main loop ($83F8). The frame counter is incremented first.
    this.frame = (this.frame + 1) & 0xFF;
    const pl = this.player, tick = this.frame & 3;
    if (!pl.regen && !pl.dead) {
      if (this.drops.hits(pl.x, pl.y)) pl.kill();                                  // $B7A2
      else if (tick === 2 && this.ball && this.ball.hits(pl.x, pl.y)) pl.kill();   // $B7F0
    }
    pl.update(this.room, input, this.frame);
    this.drops.update(this.room);                                                  // $C300
    if ((tick & 1) && this.ball) this.ball.update(this.frame);                    // $B161
    if (this.bird) {                                                               // $85D2
      if (!pl.dead && this.bird.hits(pl.x, pl.y)) pl.kill();   // a hit skips this frame's move
      else this.bird.update();
    }
    // [$8584] Chamber timer: paused while regenerating or while the bird is out; half speed
    // on difficulty 0. At zero the bird appears. (On the frame a splat ends, the ROM runs the
    // timer before regeneration starts.)
    const respawned = pl.events.some((e) => e.type === 'respawn');
    if (!(pl.regen && !respawned) && !this.bird && (this.difficulty !== 0 || !(this.frame & 1))) {
      this.timer = Math.max(0, this.timer - 1);
      if (this.timer === 0) this.bird = new Bird();
    }
    for (const ev of pl.events.splice(0)) this.handle(ev);
  }

  handle(ev) {
    const pl = this.player;
    if (ev.type === 'pickup') {
      const before = this.score;
      this.score += collect(this.state, this.room, ev, this.rng);
      if (ev.code === OBJ.KEY) this.keys++;
      // [$B363] Extra life when the ten-thousands digit changes, up to 5.
      if (Math.floor(before / 10000) !== Math.floor(this.score / 10000) && pl.lives < 5) pl.lives++;
    } else if (ev.type === 'door') {
      // [$BEA5] Match the door by row and wall side in the ROM's door table.
      const row = ((pl.y + 7) & 0xFF) >> 3;
      const door = this.room.def.doors.find((d) => d.at.side === ev.side && (d.at.raw & 0x7F) === row);
      if (!door) return;
      // [$BF02] Timer: full for a new chamber, partly refunded going straight back.
      const leaving = this.timer;
      this.timer = door.to === this.prevRoom ? returnTimer(this.prevTimer, leaving) : TIMER_FULL;
      if (door.to === 10) this.timer = TIMER_CHAMBER_X;   // [$BFD1]
      this.prevRoom = this.roomIndex;
      this.prevTimer = leaving;
      this.enterRoom(door.to, Room.doorSpawn(door.arrive));
    } else if (ev.type === 'respawn') {
      // [$B9B8] After a death the bird is gone; if it had come out, the timer restarts at 2048.
      this.bird = null;
      if (this.timer === 0) this.timer = this.roomIndex === 10 ? TIMER_FULL : TIMER_AFTER_BIRD_DEATH;
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
    for (const o of this.room.objects()) {
      if (!o.code) continue;
      const color = o.code === OBJ.KEY ? pal[4][2] : o.code === OBJ.DIAMOND ? pal[5][2]
        : o.code >= OBJ.DOOR_TOP ? pal[2][2] : pal[0][2];   // door / ring / closed-door wall
      this.drawBits(this.tiles[o.code >> 1], TILE_W, TILE_H, o.col * TILE_W, HUD_H + o.row * TILE_H, color);
    }
    for (const d of this.drops.visible()) this.sprite(this.dropSprite, toPx(d.x), d.y);
    if (this.ball) this.sprite(this.ballFrames[this.ball.frame(this.frame)], toPx(this.ball.x), this.ball.y);
    if (this.bird) this.sprite(this.birdFrames[this.bird.frame(this.frame)], toPx(this.bird.x), this.bird.y);

    const pl = this.player;
    const [head, legs] = this.playerFrames[pl.frame(this.frame)];
    this.sprite(head, toPx(pl.x), pl.y);
    this.sprite(legs, toPx(pl.x), pl.y + 8);

    g.rect(0, 0, 320, HUD_H, '#000');
    this.text(String(this.score).padStart(6, '0'), 0, 0, pal[7][2]);
    this.text('L' + pl.lives + ' K' + this.keys + ' D' + this.difficulty, 56, 0, pal[4][2]);
    this.text(String(this.timer).padStart(4, '0'), 144, 0, this.timer < 500 ? pal[4][2] : pal[7][2]);
    const title = this.gameOver ? 'GAME OVER R' : def.name;
    this.text(title, 320 - 8 * title.length, 0, pal[7][2]);
  }
}
