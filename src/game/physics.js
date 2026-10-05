// Tunable player physics. The defaults are the 7800 ROM's values (see docs/PHYSICS.md), so the
// ROM trace tests check them; the editor's sliders change them per level pack (pack.physics).
//
// Speeds are per movement step. The player moves once every `stepFrames` frames (the ROM's
// 4-frame tick), so stepFrames is also the overall game speed.

export const ROM_PHYSICS = Object.freeze({
  stepFrames: 4,        // frames per movement step
  walkSpeed: 1,         // pixels per step on the ground
  airSpeed: 1,          // pixels per step sideways in a jump
  jumpSpeed: 5.5,       // take-off speed, lines per step upward
  gravity: 0.75,        // speed lost per step
  maxFallSpeed: 7,      // terminal speed, lines per step (8 at most: floors are 8 lines)
  deadlyFallSpeed: 7,   // landing at this speed or faster kills; 9 = falls never kill
  climbUpSpeed: 1,      // lines per step up a rope
  climbDownSpeed: 2,    // lines per step down a rope
  ropeHoldSteps: 6,     // steps holding left/right on a rope before hanging or letting go
  wallBounce: 1,        // 1: hitting a wall in the air bounces you back; 0: you stop and drop
  airControl: 0,        // 1: left/right steer during a jump (not in the ROM)
});

// Slider descriptions for the editor, in display order.
export const PHYSICS_PARAMS = [
  { key: 'stepFrames', label: 'Game speed (frames per step)', min: 1, max: 8, step: 1,
    help: 'Lower is faster. Everything the player does happens once per step.' },
  { key: 'walkSpeed', label: 'Walk speed', min: 1, max: 4, step: 1, unit: 'px/step' },
  { key: 'airSpeed', label: 'Jump distance (sideways speed)', min: 0, max: 4, step: 1, unit: 'px/step' },
  { key: 'jumpSpeed', label: 'Jump power', min: 2, max: 8, step: 0.25, unit: 'lines/step' },
  { key: 'gravity', label: 'Gravity', min: 0.25, max: 2, step: 0.0625, unit: 'lines/step²' },
  { key: 'maxFallSpeed', label: 'Max fall speed', min: 2, max: 8, step: 1, unit: 'lines/step' },
  { key: 'deadlyFallSpeed', label: 'Deadly landing speed', min: 2, max: 9, step: 1, unit: 'lines/step',
    help: 'Landing at this speed or faster kills. 9 = falls never kill.' },
  { key: 'climbUpSpeed', label: 'Climb up speed', min: 1, max: 4, step: 1, unit: 'lines/step' },
  { key: 'climbDownSpeed', label: 'Climb down speed', min: 1, max: 4, step: 1, unit: 'lines/step' },
  { key: 'ropeHoldSteps', label: 'Rope side-hold time', min: 1, max: 12, step: 1, unit: 'steps',
    help: 'How long to hold left/right on a rope before hanging off it or letting go.' },
  { key: 'wallBounce', label: 'Bounce off walls in the air', toggle: true },
  { key: 'airControl', label: 'Steer in the air (not in the ROM)', toggle: true },
];

// A complete parameter set: missing keys take the ROM value.
export function physicsFrom(p) {
  return { ...ROM_PHYSICS, ...(p || {}) };
}

// What a standing-to-standing jump on flat ground does with these settings, stepping the same
// 8.8 arithmetic and landing test as the player: height in lines, distance in hpos (8 per
// tile), the landing speed, and whether that landing kills. The editor shows it by the sliders.
export function jumpProfile(physics) {
  const p = physicsFrom(physics);
  const gravity = Math.round(p.gravity * 256), safe = -(p.deadlyFallSpeed - 1);
  // y: lines above the starting spot. The feet start on the bottom line of an 8-line floor
  // tile; a fall lands when they are inside it and one more step would leave it (Player.fall).
  let vy = Math.round(p.jumpSpeed * 256), y = 0, height = 0;
  for (let steps = 0; steps < 1000; steps++) {
    const hi = Math.floor(vy / 256);
    if (hi < 0 && y <= 7 && -hi > y) {
      return { height, distance: (steps + 1) * p.airSpeed, landSpeed: -hi, kills: hi < safe };
    }
    y += hi;
    height = Math.max(height, y);
    vy -= gravity;
    if (Math.floor(vy / 256) < -p.maxFallSpeed) vy = -p.maxFallSpeed * 256 + (vy & 0xFF);
  }
  return { height, distance: 0, landSpeed: 0, kills: false };
}
