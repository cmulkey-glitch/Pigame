// Player logic ported from the Atari 7800 Downland ROM. See docs/PHYSICS.md for the trace.
//
// Units are the 7800's: x = MARIA hpos ($ED), y = scanline with 0 at the top of the HUD row
// ($EE). Collision is tile based through room.tileAt(). Movement runs on a 4-frame tick
// (tick = frame & 3); the ROM routine for each step is noted in brackets.

import { FACE_LEFT, FACE_RIGHT } from './room.js';

const T_FLOOR = 0x04;       // only this tile can be stood on
const T_ROPE = 0x02, T_BAR = 0x2A, T_ROPE_TOP = 0x2C;
const T_DOOR_FIRST = 0x1A, T_DOOR_LAST = 0x1E;
const T_ITEM_FIRST = 0x20, T_ITEM_LAST = 0x24;
const DOOR_RIGHT_X = 0x8D, DOOR_LEFT_X = 0x0B;

const JUMP_VY = 0x0580;     // 8.8, positive = up
const GRAVITY = 0x00C0;     // subtracted every tick
const TERMINAL_HI = 0xF9;   // high byte clamp while falling; landing at it kills
const SAFE_LANDING_HI = 0xFA;
const HOLD_TICKS = 6;       // left/right held on a rope before hanging / letting go
const SPLAT_FRAMES = 0x4B;
const SPLAT_SECOND_FRAME = 0x43;
const MIDAIR_DEATH_FRAMES = 0x2C;

const isWall = (t) => t > 6 && t < T_ITEM_FIRST;           // air: 7..$1F
const isItem = (t) => t >= T_ITEM_FIRST && t <= T_ITEM_LAST;
const isDoor = (t) => t >= T_DOOR_FIRST && t <= T_DOOR_LAST;

export class Player {
  constructor() {
    this.events = [];
    this.lives = 4;
    this.reset({ x: 0x40, y: 0x1F, facing: FACE_RIGHT });
  }

  reset(spawn, regenerating = false) {
    this.x = spawn.x; this.y = spawn.y; this.facing = spawn.facing;
    this.vyHi = 0; this.vyLo = 0;
    this.air = false;         // $F1 bit 0
    this.vertical = false;    // $F1 bit 1: no horizontal momentum in the air
    this.regen = regenerating;// $F1 bit 2
    this.jumpLatch = false;   // $F1 bit 3: fire must be released between jumps
    this.dead = false;        // $F1 bit 4
    this.running = false;     // $F1 bit 5
    this.climbing = false;    // $F1 bit 6
    this.hanging = false;     // $FA bit 0
    this.holdCount = 0;       // $0144
    this.hangSide = 0;        // $0145
    this.midairDeath = 0;     // $0141
    this.splat = 0;           // $0142
  }

  get vy() { return ((this.vyHi << 8) | this.vyLo) << 16 >> 16; }
  set vy(v) { v &= 0xFFFF; this.vyHi = v >> 8; this.vyLo = v & 0xFF; }

  emit(type, data = {}) { this.events.push({ type, ...data }); }

  update(room, input, frame) {
    const tick = frame & 3;
    if (this.splat) { this.updateSplat(); return; }
    if (this.midairDeath) this.midairDeath--;

    if (tick === 0) this.walk(room, input);
    if (this.climbing && tick === 0) this.climb(room, input);
    if (input.isDown('jump')) {
      if (!this.air && !this.regen) this.startJump(input);
    } else {
      this.jumpLatch = false;
    }
    if (this.air && tick === 0) this.airTick(room);
    if (tick === 1) this.touchItems(room);
  }

  // [$BD0F] Walking, one hpos per tick. Ends regeneration.
  walk(room, input) {
    this.running = false;
    if (this.climbing || this.dead || this.air) return;
    const right = input.isDown('right'), left = input.isDown('left');
    if (!right && !left) return;
    const dir = right ? 1 : -1;
    const probeX = right ? this.x + 7 : this.x;
    const t = room.tileAt(probeX, this.y + 8);
    this.regen = false;
    if ((right ? this.x >= DOOR_RIGHT_X : this.x <= DOOR_LEFT_X) && isDoor(t)) {
      this.emit('door', { side: right ? 'right' : 'left' });
      return;
    }
    if (isItem(t)) { this.pickUp(room, probeX, this.y + 8, t); return; }
    if (t > 6) return;
    this.x = (this.x + dir) & 0xFF;
    this.facing = right ? FACE_RIGHT : FACE_LEFT;
    if (room.tileAt(this.x + 3, this.y + 15) === T_FLOOR) { this.running = true; return; }
    // Walked off an edge: one extra step out and one line down, then fall.
    this.air = true;
    this.x = (this.x + dir) & 0xFF;
    this.y = (this.y + 1) & 0xFF;
    this.vyHi = 0xFF;
  }

  // [$C26B] Jump from the ground or off a rope (off a rope needs a direction).
  startJump(input) {
    if (this.jumpLatch || this.dead || this.hanging) return;
    const right = input.isDown('right'), left = input.isDown('left');
    this.vertical = !(right || left);
    if (this.climbing && this.vertical) { this.vertical = false; return; }
    if (left) this.facing = FACE_LEFT;
    if (right) this.facing = FACE_RIGHT;
    this.air = true;
    this.climbing = false;
    this.jumpLatch = true;
    this.vy = JUMP_VY;
    this.emit('sound', { name: 'jump' });
  }

  // [$BFEB] Air: horizontal step with wall bounce, then vertical, then rope catch [$C19A].
  airTick(room) {
    if (!this.vertical && !this.dead) {
      const left = this.facing === FACE_LEFT;
      this.x = (this.x + (left ? -1 : 1)) & 0xFF;
      if (isWall(room.tileAt(this.x + (left ? 1 : 6), this.y + 15))) {
        this.x = (this.x + (left ? 1 : -1)) & 0xFF;
        this.facing = left ? FACE_RIGHT : FACE_LEFT;
        if (this.vyHi < 0x80) this.vyHi = (-this.vyHi) & 0xFF;   // rising: bounce downward
        this.emit('sound', { name: 'bump' });
      }
    }
    if (!this.midairDeath && this.fall(room)) return;
    this.catchRope(room);
  }

  // Vertical motion. Returns true if the player died on landing.
  fall(room) {
    if (this.vyHi >= 0x80 &&
        room.tileAt(this.x + 3, this.y + 16) === T_FLOOR &&
        room.tileAt(this.x + 3, (this.y + 16 - this.vyHi) & 0xFF) !== T_FLOOR) {
      this.y = (this.y & 0xF8) + 7;
      this.air = false;
      if (this.dead) { this.startSplat(); return true; }
      if (this.vyHi < SAFE_LANDING_HI) { this.kill(); return true; }
      this.vyHi = 0;
      this.emit('sound', { name: 'land' });
      return false;
    }
    this.y = (this.y - this.vyHi) & 0xFF;
    if (this.y > 0xF0) this.vyHi = 0xFF;
    this.vy = this.vy - GRAVITY;
    if (this.vyHi > 0x80 && this.vyHi < TERMINAL_HI) this.vyHi = TERMINAL_HI;
    return false;
  }

  // [$C19A] Grab a rope when its column lines up exactly, or a bar ($2A) from below.
  catchRope(room) {
    const t = room.tileAt(this.x + 3, this.y + 6);
    if (t !== T_ROPE && t !== T_BAR && t !== T_ROPE_TOP) return;
    if (t === T_BAR) {
      if (room.tileAt(this.x + 3, this.y + 9) !== T_BAR) return;
      this.y = (this.y & 0xF8) + 5;
      this.x = (this.x & 0xF0) + (((this.x & 0x0F) + 3) < 8 ? 4 : 12);
    } else if ((this.x & 0x0F) !== 0x04 && (this.x & 0x0F) !== 0x0C) {
      return;
    }
    if (this.dead) return;
    this.air = false;
    this.climbing = true;
    this.hanging = false;
    this.holdCount = 0;
    this.hangSide = 0;
  }

  // [$B52B] Rope: up 1 line / tick, down 2; off the bottom falls straight down.
  climb(room, input) {
    const up = input.isDown('up'), down = input.isDown('down');
    if ((!up && !down) || this.hanging) { this.hang(room, input); return; }
    const onRope = (y) => {
      const t = room.tileAt(this.x + 3, y + 6);
      return t === T_ROPE || t === T_ROPE_TOP;
    };
    if (up) {
      if (onRope(this.y - 1)) this.y--;
      return;
    }
    const ny = this.y + 2;
    if (!onRope(ny)) {
      this.climbing = false;
      this.air = true;
      this.vertical = true;
      this.vyHi = 0xFF;
    }
    this.y = ny;
  }

  // [$B620] Left/right on a rope: after HOLD_TICKS shift 4 to hang beside it; from a hang,
  // HOLD_TICKS back returns to the rope, HOLD_TICKS away lets go.
  hang(room, input) {
    const right = input.isDown('right'), left = input.isDown('left');
    if (!right && !left) return;
    const want = right ? FACE_RIGHT : FACE_LEFT, dx = right ? 4 : -4;
    if (!this.hanging) {
      if (this.holdCount === 0) { this.holdCount = HOLD_TICKS; return; }
      if (--this.holdCount) return;
      this.hanging = true;
      this.holdCount = HOLD_TICKS;
      const t = room.tileAt(this.x + (right ? 8 : -8), this.y + 8);
      if (t >= 6 && t < T_ITEM_FIRST) { this.holdCount = 0; this.hanging = false; return; }
      this.facing = want;
      this.hangSide = want;
      this.x = (this.x + dx) & 0xFF;
      return;
    }
    if (this.facing !== want) { this.facing = want; this.holdCount = HOLD_TICKS; return; }
    if (--this.holdCount) return;
    this.x = (this.x + dx) & 0xFF;
    this.hanging = false;
    if (this.hangSide !== want) return;   // stepped back onto the rope
    this.climbing = false;
    this.air = true;
    this.vertical = true;
    this.vyHi = 0;
  }

  // [$B252] Items touched while jumping, falling or climbing.
  touchItems(room) {
    if (!this.air && !this.climbing) return;
    const vy = this.vyHi < 0x80 ? 1 : 15;
    let t = room.tileAt(this.x + 3, this.y + vy);
    if (isItem(t)) { this.pickUp(room, this.x + 3, this.y + vy, t); return; }
    if (this.vertical) return;
    const px = this.x + (this.facing === FACE_LEFT ? 0 : 7);
    t = room.tileAt(px, this.y + 7);
    if (isItem(t)) this.pickUp(room, px, this.y + 7, t);
  }

  pickUp(room, x, y, code) {
    room.clearTileAt(x, y);
    this.emit('pickup', { code, ...room.cellAt(x, y) });
  }

  // [$B812] Death. On a rope: drop. In the air: flicker for $2C frames, then fall and splat.
  kill() {
    if (this.dead || this.regen) return;
    this.dead = true;
    this.splat = 0;
    if (this.climbing) { this.climbing = false; this.hanging = false; this.air = true; }
    if (this.air) {
      this.midairDeath = MIDAIR_DEATH_FRAMES;
      this.vyHi = 0xFF;
    } else {
      this.startSplat();
    }
  }

  startSplat() {
    this.splat = SPLAT_FRAMES - 1;
    this.emit('sound', { name: 'splat' });
  }

  // [$B947] Splat countdown (the ROM decrements it in the landing frame too), then lose a
  // life and regenerate in place.
  updateSplat() {
    if (--this.splat) return;
    this.dead = false;
    this.lives--;
    if (this.lives) this.regen = true;   // regenerates where it died
    else this.emit('gameover');
  }

  // [$B861 / $BA16] Animation frame (index into playerFrames).
  frame(frameCounter) {
    const left = this.facing === FACE_LEFT;
    if (this.splat) return this.splat > SPLAT_SECOND_FRAME ? 16 : 17;
    if (this.midairDeath) return frameCounter & 4 ? 14 : 15;
    if (this.climbing && !this.hanging) return 12 + ((this.y & 2) ? 1 : 0);
    if (this.air || this.hanging) return left ? 15 : 14;
    if (this.regen) return 8 + ((frameCounter & 2) ? 1 : 0) + (left ? 2 : 0);
    if (this.running) return ((frameCounter & 0x1F) >> 3) + (left ? 4 : 0);
    return left ? 6 : 2;
  }
}
