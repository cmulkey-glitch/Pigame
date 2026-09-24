// Player movement against the chamber's pixel collision masks.
// Tuning values are first guesses; replace once the ROM's movement code is traced.

const W = 16, H = 16;
const FEET = [4, 11];          // columns (relative to x) that stand on ground
const STEP_UP = 3, STEP_DOWN = 3;
const GRAVITY = 0.2, MAX_FALL = 3;
const JUMP_VY = -2.4;
const DEADLY_FALL = 24;        // pixels
const DOOR_LEFT_X = 12, DOOR_RIGHT_X = 276;

export class Player {
  constructor() {
    this.reset({ x: 0, y: 0, facing: 1 });
  }

  reset(spawn) {
    this.x = spawn.x; this.y = spawn.y; this.facing = spawn.facing;
    this.startAir(0, 0);
    this.anim = 0;
    this.deadTimer = 0;
  }

  get box() { return { x: this.x, y: this.y, w: W, h: H }; }

  onGround(room) {
    for (let cx = this.x + FEET[0]; cx <= this.x + FEET[1]; cx++)
      if (room.isSolid(cx, this.y + H)) return true;
    return false;
  }

  feetBlocked(room) {
    for (let cx = this.x + FEET[0]; cx <= this.x + FEET[1]; cx++)
      if (room.isSolid(cx, this.y + H - 1)) return true;
    return false;
  }

  bodyBlocked(room, x) {
    const edge = x + (this.facing > 0 ? FEET[1] + 1 : FEET[0] - 1);
    for (let y = this.y + 1; y < this.y + H - STEP_UP; y++)
      if (room.isSolid(edge, y)) return true;
    return false;
  }

  ropeColumn(room) {
    for (let cx = this.x + 5; cx <= this.x + 10; cx++)
      for (let y = this.y + 4; y <= this.y + 12; y++)
        if (room.isRope(cx, y)) return cx;
    return -1;
  }

  // One horizontal pixel with step-up / step-down. Returns false if blocked.
  stepX(room, dx) {
    const ox = this.x, oy = this.y;
    this.x += dx;
    if (this.bodyBlocked(room, this.x)) { this.x = ox; return false; }
    let lift = 0;
    while (this.feetBlocked(room) && lift < STEP_UP) { this.y--; lift++; }
    if (this.feetBlocked(room)) { this.x = ox; this.y = oy; return false; }
    return true;
  }

  startAir(vx, vy) {
    this.state = 'air'; this.vx = vx; this.vy = vy; this.peakY = this.y;
  }

  update(room, input) {
    if (this.state === 'dead') { this.deadTimer++; return; }
    const dir = (input.isDown('right') ? 1 : 0) - (input.isDown('left') ? 1 : 0);
    const vert = (input.isDown('down') ? 1 : 0) - (input.isDown('up') ? 1 : 0);

    if (this.state === 'walk') {
      if (vert) {
        const rc = this.ropeColumn(room);
        if (rc >= 0 && !(vert > 0 && this.onGround(room) && !room.isRope(rc, this.y + H))) {
          this.x = rc - 7; this.state = 'climb'; return;
        }
      }
      if (input.isDown('jump')) { this.startAir(dir, JUMP_VY); return; }
      if (dir) {
        this.facing = dir;
        if (this.stepX(room, dir)) this.anim++;
      }
      if (!this.onGround(room)) {
        let drop = 0;
        while (!this.onGround(room) && drop < STEP_DOWN) { this.y++; drop++; }
        if (!this.onGround(room)) { this.y -= drop; this.startAir(0, 0); }
      }
    } else if (this.state === 'climb') {
      const rc = this.x + 7;
      if (input.isDown('jump') && dir) { this.facing = dir; this.startAir(dir, JUMP_VY / 2); return; }
      if (vert < 0 && room.isRope(rc, this.y + 1)) { this.y--; this.anim++; }
      if (vert > 0) {
        if (this.onGround(room)) { this.state = 'walk'; return; }
        this.y++; this.anim++;
        if (!room.isRope(rc, this.y + 8)) { this.startAir(0, 0); return; }
      }
      if (dir && this.onGround(room)) this.state = 'walk';
    } else if (this.state === 'air') {
      if (vert && this.vy >= 0) {
        const rc = this.ropeColumn(room);
        if (rc >= 0) { this.x = rc - 7; this.state = 'climb'; return; }
      }
      if (this.vx) { this.facing = this.vx; if (!this.stepX(room, this.vx)) this.vx = 0; }
      this.vy = Math.min(this.vy + GRAVITY, MAX_FALL);
      const n = Math.round(Math.abs(this.vy));
      for (let i = 0; i < n; i++) {
        if (this.vy > 0) {
          if (this.onGround(room)) break;
          this.y++;
        } else {
          this.y--;
          this.peakY = Math.min(this.peakY, this.y);
        }
      }
      if (this.vy > 0 && this.onGround(room)) {
        if (this.y - this.peakY > DEADLY_FALL) { this.state = 'dead'; this.deadTimer = 0; }
        else this.state = 'walk';
      }
    }
  }

  // Door the player is touching, if any. Doors sit in columns 0 and 18 and the ROM
  // drops arriving players at x = 14 / 274, just clear of these thresholds.
  exitSide() {
    if (this.x < DOOR_LEFT_X) return 'left';
    if (this.x > DOOR_RIGHT_X) return 'right';
    return null;
  }
}
