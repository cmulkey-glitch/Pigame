// Sound driver ported from the 7800 ROM (7800basic's playsfx $F8D9 and its per-frame driver
// $F83F). It produces what the ROM writes to the TIA each frame: AUDF / AUDC / AUDV for two
// channels. Turning those registers into audio is the platform's job (a TIA synth).

export class SoundDriver {
  constructor(sounds) {
    this.sounds = sounds;           // data/sounds.json -> sounds
    this.ch = [0, 1].map(() => ({ steps: null, pos: 0, priority: 0, frames: 0, pitch: 0, wait: 0 }));
    this.regs = [0, 1].map(() => ({ f: 0, c: 0, v: 0 }));
  }

  // [$F8D9] Start a sound: a free channel if there is one; otherwise, unless the new sound's
  // priority is 0, replace channel 1 when channel 0's (decaying) priority is >= channel 1's,
  // else channel 0. The new sound's own priority isn't compared.
  play(name, pitch = 0) {
    const s = this.sounds[name];
    if (!s) return;
    let x;
    if (!this.ch[0].steps) x = 0;
    else if (!this.ch[1].steps) x = 1;
    else if (!s.priority) return;
    else x = this.ch[0].priority >= this.ch[1].priority ? 1 : 0;
    Object.assign(this.ch[x], { steps: s.steps, pos: 0, priority: s.priority, frames: s.frames, pitch, wait: 0 });
  }

  // [$F832] Stop everything and silence both channels (frequency and volume to 0).
  stopAll() {
    for (let x = 0; x < 2; x++) {
      this.ch[x].steps = null;
      this.regs[x].f = 0;
      this.regs[x].v = 0;
    }
  }

  // [$F83F] Once per frame. Each step lasts frames + 1 frames; priority decays by one per step.
  update() {
    for (let x = 0; x < 2; x++) {
      const c = this.ch[x];
      if (!c.steps) continue;
      if (c.wait) { c.wait--; continue; }
      let [f, ctrl, v] = c.steps[c.pos];
      if (ctrl === 0x10) {             // command: new step length
        c.frames = v; c.wait = 0; c.pos++;
        x--; continue;
      }
      c.wait = c.frames;
      if (c.priority) c.priority--;
      this.regs[x] = { f: (f + c.pitch) & 0xFF, c: ctrl, v };
      if (!(f | ctrl | v)) c.steps = null; else c.pos++;
    }
    return this.regs;
  }
}
