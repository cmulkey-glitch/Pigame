// Downland: title screen, play, game over and the escape ending, driving the ported logic.
// Platform-agnostic: everything goes through the `platform` object (see src/platform/web.js).
//
// Game logic uses 7800 coordinates (x = hpos, y = line from the top of the HUD row). On the
// 320x200 canvas that is px = x*2 - 8 (tile column c at 16c) and py = y (HUD row at 0).

import { Room, decodeTiles, glyphBits, ROOM_W, ROOM_H, TILE_W, TILE_H, OBJ, FACE_LEFT, FACE_RIGHT } from './room.js';
import { Player } from './player.js';
import { Drops, NO_DROPS } from './drops.js';
import { Rng } from './rng.js';
import { newGameState, collect } from './state.js';
import { Ball, Bird, TIMER_FULL, TIMER_AFTER_BIRD_DEATH, TIMER_CHAMBER_X, returnTimer } from './enemies.js';

const HUD_H = 8;
const toPx = (x) => x * 2 - 8;
const TITLE_GUARD = 30;        // $0147: frames before fire can start a game
const GAME_OVER_FRAMES = 120;  // $0160
const START = { x: 0x88, y: 0xB7, facing: FACE_LEFT };   // [$838D]

export class Game {
  constructor(platform) {
    this.p = platform;
    this.rng = new Rng();
    this.frame = 0;
    this.difficulty = 1;        // $015F: 0 easy, 1 normal (power-on default), 2 hard
    this.beginner = false;      // BEGINNER (added, not in the ROM): EASY rules without drops
    this.escapeMode = false;    // $FA bit 3: chamber 9's exit leads to chamber X
    this.hiScore = Number(platform.storage?.get('downland.hi')) || 0;
    this.mode = 'title';
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
    this.titleDef = rooms.title;
    this.doorOpenInitial = rooms.doorOpenInitial;
    this.tiles = decodeTiles(tileBmp);
    this.sprites = sprites.sprites;
    this.playerFrames = sprites.playerFrames;
    this.dropSprite = this.sprites.findIndex((sp) => sp.addr === '$E02E');
    this.ballFrames = sprites.ballFrames;
    this.birdFrames = sprites.birdFrames;
    this.spriteSheet = spriteBmp;
    this.surfaces = new Map();
    this.titleSurfaces = this.titleDef.flashRGB.map(([p0, p7]) => {
      const palettesRGB = this.titleDef.palettesRGB.map((pl) => pl.slice());
      palettesRGB[0][2] = p0; palettesRGB[7][2] = p7;
      const room = new Room({ ...this.titleDef, palettesRGB }, this.tiles);
      return { surface: this.p.makeSurface(ROOM_W, ROOM_H, room.rgba), palettesRGB };
    });
    this.toTitle();
  }

  // ---- title screen ($802A) ----

  toTitle() {
    this.mode = 'title';
    this.titleGuard = TITLE_GUARD;
    this.titleRoom = new Room(this.titleDef, this.tiles);
    this.drops = new Drops(this.titleDef, -1, this.difficulty, this.rng);
    this.stickWasMoved = true;   // $FA bit 2: wait for the stick to be released first
  }

  updateTitle() {
    const { input } = this.p;
    this.frame = (this.frame + 1) & 0xFF;
    if (this.titleGuard) this.titleGuard--;
    if (input.isDown('jump') && !this.titleGuard) { this.startGame(); return; }
    // [$8110] One change per stick movement: left/right cycle difficulty, up/down the mode.
    const l = input.isDown('left'), r = input.isDown('right');
    const moved = l || r || input.isDown('up') || input.isDown('down');
    if (moved && !this.stickWasMoved) {
      if (!l && !r) this.escapeMode = !this.escapeMode;
      else this.cycleLevel(r ? 1 : -1);
    }
    this.stickWasMoved = moved;
    this.drops.update(this.titleRoom);
  }

  // BEGINNER, EASY, NORMAL, HARD (wraps). BEGINNER plays by EASY's rules without drops.
  cycleLevel(step) {
    const level = ((this.beginner ? -1 : this.difficulty) + step + 5) % 4 - 1;
    this.beginner = level === -1;
    this.difficulty = Math.max(level, 0);
  }

  renderTitle() {
    const g = this.p.gfx;
    // [$80F0] every 64 frames the title colours flip
    const { surface, palettesRGB: pal } = this.titleSurfaces[this.frame & 0x80 ? 0 : 1];
    g.clear('#000');
    g.draw(surface, 0, HUD_H);
    for (const d of this.drops.visible()) this.sprite(this.dropSprite, toPx(d.x), d.y);
    const t = this.titleDef;
    // [$8181] difficulty between diamonds, mode between rings, centred on hpos $48
    const name = this.beginner ? 'BEGINNER' : t.difficultyNames[this.difficulty];
    const ink = pal[this.beginner ? 5 : t.difficultyPalettes[this.difficulty]][2];
    this.flanked(name, OBJ.DIAMOND, 0x82, ink);
    this.flanked(t.modeNames[this.escapeMode ? 1 : 0], OBJ.RING, 0x8C, pal[2][2]);
    const hi = 'HI ' + String(this.hiScore).padStart(6, '0');
    this.text(hi, 320 - 8 * hi.length, 0, pal[7][2]);
  }

  flanked(word, tile, y, color) {
    const x = toPx(0x48 - word.length * 2);
    this.drawBits(this.tiles[tile >> 1], TILE_W, TILE_H, x, y, color);
    this.text(word, x + TILE_W, y, color);
    this.drawBits(this.tiles[tile >> 1], TILE_W, TILE_H, x + TILE_W + 8 * word.length, y, color);
  }

  // ---- play ----

  startGame() {
    this.mode = 'play';
    this.player = new Player();
    this.player.lives = this.difficulty === 0 ? 5 : 4;
    this.score = 0; this.keys = 0;
    this.state = newGameState(this.defs, this.doorOpenInitial);
    this.timer = TIMER_FULL;
    this.prevRoom = -1;    // $0157 / $0159: chamber we came from and its timer when we left
    this.prevTimer = 0;
    this.enterRoom(0, START, true);
    this.player.jumpLatch = true;   // fire started the game: release it before jumping
  }

  enterRoom(index, spawn, regenerating = false) {
    this.roomIndex = index;
    this.room = new Room(this.defs[index], this.tiles);
    this.room.placeObjects(this.state);
    this.drops = this.beginner ? NO_DROPS : new Drops(this.defs[index], index, this.difficulty, this.rng);
    const ball = this.defs[index].ball;
    this.ball = ball ? new Ball(ball, index) : null;
    this.bird = null;      // [$8932] leaving a chamber clears the bird
    if (!this.surfaces.has(index)) this.surfaces.set(index, this.p.makeSurface(ROOM_W, ROOM_H, this.room.rgba));
    this.surface = this.surfaces.get(index);
    this.player.reset(spawn || this.defaultSpawn(), regenerating);
  }

  // Playtest chamber select: fresh timer, no door history, player at the chamber's start.
  jumpToRoom(index) {
    this.timer = index === 10 ? TIMER_CHAMBER_X : TIMER_FULL;
    this.prevRoom = -1;
    this.enterRoom(index, this.startSpawn(index));
  }

  // Where a chamber is normally entered: chamber 0 is the game start; chamber X is the ESCAPE
  // arrival from chamber 9 ($BF9F); any other chamber is the arrival point of the door into it
  // from the lowest-numbered chamber that leads there (1 from 0, 5 from 2, 7 from 5, ...).
  startSpawn(index) {
    if (index === 0) return START;
    if (index === 10) {
      const d = this.defs[9].doors.find((door) => door.to === 0);
      return { x: 0x0B, y: d.arrive.y, facing: FACE_RIGHT };
    }
    for (const def of this.defs) {
      const d = def.id !== index && def.doors.find((door) => door.to === index);
      if (d) return Room.doorSpawn(d.arrive);
    }
    return this.defaultSpawn();
  }

  defaultSpawn() {
    const d = this.room.def.doors[0];
    return d ? Room.doorSpawn(d.at) : { x: 0x50, y: 0x1F, facing: FACE_RIGHT };
  }

  update() {
    const keys = this.p.input.takePressed();
    // R / RESTART acts like the console's RESET switch ($83F0): back to the title.
    if (keys.some((k) => k === 'r' || k === 'R') && this.mode !== 'title') { this.toTitle(); return; }
    if (this.mode === 'title') { this.updateTitle(); return; }
    if (this.mode === 'gameover') {
      if (--this.endTimer === 0) this.toTitle();
      return;
    }
    if (this.mode === 'escaped') {
      // [$C62F] fire returns to the title (released first, so a held button doesn't skip it)
      const fire = this.p.input.isDown('jump');
      if (fire && !this.escapeGuard) this.toTitle();
      else if (!fire) this.escapeGuard = false;
      return;
    }
    for (const k of keys) {
      const n = this.defs.length;
      if (k === ']') this.jumpToRoom((this.roomIndex + 1) % n);
      else if (k === '[') this.jumpToRoom((this.roomIndex + n - 1) % n);
      else if (k >= '0' && k <= '9') this.jumpToRoom(+k);
      else if (k === 'x' || k === 'X') this.jumpToRoom(10);
      else if (k === 'd' || k === 'D') { this.cycleLevel(1); this.enterRoom(this.roomIndex); }
    }
    this.updatePlay();
  }

  updatePlay() {
    const { input } = this.p;
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
    for (const ev of pl.events.splice(0)) {
      this.handle(ev);
      if (this.mode !== 'play') break;
    }
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
      this.goThroughDoor(ev.side);
    } else if (ev.type === 'respawn') {
      // [$B9B8] After a death the bird is gone; if it had come out, the timer restarts at 2048.
      this.bird = null;
      if (this.timer === 0) this.timer = this.roomIndex === 10 ? TIMER_FULL : TIMER_AFTER_BIRD_DEATH;
    } else if (ev.type === 'gameover') {
      this.endGame('gameover');
    }
  }

  // [$BEA5 / $BF02 / $BF44] Door transition, including the chamber 0 / chamber X rules.
  goThroughDoor(side) {
    const pl = this.player;
    const row = ((pl.y + 7) & 0xFF) >> 3;
    const door = this.room.def.doors.find((d) => d.at.side === side && (d.at.raw & 0x7F) === row);
    if (!door) return;
    const from = this.roomIndex;
    let to = door.to, spawn = Room.doorSpawn(door.arrive);

    // Timer: full for a new chamber, partly refunded going straight back.
    const leaving = this.timer;
    this.timer = to === this.prevRoom ? returnTimer(this.prevTimer, leaving) : TIMER_FULL;
    this.prevRoom = from;
    this.prevTimer = leaving;

    if (to === 0) {
      // [$BF47] every entry into chamber 0 steps difficulty up (BEGINNER stays BEGINNER)
      if (this.difficulty < 2 && !this.beginner) this.difficulty++;
      if (from === 10) { this.endGame('escaped'); return; }   // [$BF8B] out of chamber X: you escaped
      if (from === 9 && this.escapeMode) {                    // [$BF9F] ESCAPE mode: on to chamber X
        to = 10;
        spawn = { x: 0x0B, y: spawn.y, facing: FACE_RIGHT };
      } else if (from === 9) {                                // [$BFC0] LOOPING mode: new round
        this.state = newGameState(this.defs, this.doorOpenInitial);
      }
    }
    if (to === 10) this.timer = TIMER_CHAMBER_X;              // [$BFD1]
    this.enterRoom(to, spawn);
  }

  endGame(mode) {
    this.mode = mode;
    this.endTimer = GAME_OVER_FRAMES;
    this.escapeGuard = true;    // fire must be released, then pressed, to leave the ending
    if (this.score > this.hiScore) {       // [$BB43] high score
      this.hiScore = this.score;
      this.p.storage?.set('downland.hi', String(this.hiScore));
    }
  }

  // ---- drawing ----

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
    if (this.mode === 'title') { this.renderTitle(); return; }
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
    this.text('L' + pl.lives + ' K' + this.keys + ' D' + (this.beginner ? 'B' : this.difficulty), 56, 0, pal[4][2]);
    this.text(String(this.timer).padStart(4, '0'), 144, 0, this.timer < 500 ? pal[4][2] : pal[7][2]);
    this.text(def.name, 320 - 8 * def.name.length, 0, pal[7][2]);

    // [$C63F / $C58B] end screens, drawn over the frozen chamber in palette 7
    const [you, escaped, gameOver] = this.titleDef.endText;
    const ink = pal[7][2];
    if (this.mode === 'gameover') this.text(gameOver, toPx(0x3E), 0x50, ink);
    if (this.mode === 'escaped') {
      this.text(you, toPx(0x4A), 0x50, ink);
      this.text(escaped, toPx(0x42), 0x58, ink);
    }
  }
}
