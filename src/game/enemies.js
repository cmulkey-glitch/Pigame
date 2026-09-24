// Ball, bird and chamber timer, ported from the 7800 ROM. Coordinates are 7800 units (see
// player.js). All three are deterministic.

// [$B161] Ball: rolls left 1 per step with a bounce; respawns at its start past x = $0C.
// Floors are hardcoded per chamber: [minimum x, floor y, bounce vy, ends the check].
const BALL_FLOORS = {
  0: [[0x68, 0x90, 5, false]],
  2: [[0x60, 0xA0, 4, true], [0x48, 0xB0, 4, true]],
  5: [[0x48, 0x90, 5, false]],
};

export class Ball {
  constructor(start, room) {
    this.start = start;
    this.room = room;
    this.x = start.x; this.y = start.y;
    this.vy = 1;          // $F8, positive = up
  }

  // Runs on odd ticks, except tick 3 when frame & 4.
  update(frame) {
    if ((frame & 4) && (frame & 3) === 3) return;
    this.x = (this.x - 1) & 0xFF;
    if (this.x < 0x0C) { this.x = this.start.x; this.y = this.start.y; this.vy = 1; }
    this.y = (this.y - this.vy) & 0xFF;
    this.vy = (this.vy - 1) & 0xFF;
    for (const [minX, floor, bounce, done] of BALL_FLOORS[this.room] || []) {
      if (this.y > floor && this.x > minX) {
        this.y = floor; this.vy = bounce;
        if (done) return;
      }
    }
    if (this.y > 0xBF) { this.y = 0xBF; this.vy = 4; }
  }

  // [$B7F0] checked on tick 2
  hits(px, py) {
    return ((px + 6 - this.x) & 0xFF) < 10 && ((py + 14 - this.y) & 0xFF) < 22;
  }

  frame(frameCounter) { return frameCounter & 8 ? 1 : 0; }
}

// [$85BC / $85D2] Bird: appears when the chamber timer runs out and flies diagonally 2 per
// frame, turning (direction + 2) whenever it leaves the box x $08-$90, y $08-$C0.
// Directions: 1 right-up, 3 right-down, 5 left-down, 7 left-up.
export class Bird {
  constructor() { this.x = 0x20; this.y = 0x17; this.dir = 3; }

  update() {
    this.x = (this.x + (this.dir === 1 || this.dir === 3 ? 2 : -2)) & 0xFF;
    this.y = (this.y + (this.dir === 3 || this.dir === 5 ? 2 : -2)) & 0xFF;
    if (this.x <= 0x08 || this.x >= 0x90 || this.y <= 0x08 || this.y >= 0xC0) {
      this.dir += 2;
      if (this.dir > 7) this.dir = 1;
    }
  }

  // Checked every frame before moving (unless the player is already dead); on a hit the ROM
  // jumps to the death routine and the bird doesn't move that frame.
  hits(px, py) {
    return ((px + 6 - this.x) & 0xFF) < 14 && ((py + 14 - this.y) & 0xFF) < 22;
  }

  frame(frameCounter) { return frameCounter & 8 ? 1 : 0; }
}

// Chamber timer ($01AA/$01AB, BCD in the ROM, kept here as a plain number).
export const TIMER_FULL = 4096, TIMER_AFTER_BIRD_DEATH = 2048, TIMER_CHAMBER_X = 9999;

// [$8710] Going back through a door to the chamber you just came from: that chamber's saved
// time plus the time spent in the one you're leaving; 4000 or more becomes 4096.
export function returnTimer(savedPrevious, current) {
  const t = savedPrevious + (TIMER_FULL - current);
  return t >= 4000 ? TIMER_FULL : t;
}
