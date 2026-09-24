// TIA sound synth (AudioWorklet). Renders the two channels from the AUDF / AUDC / AUDV values
// the game's SoundDriver posts every frame, the way the Atari TIA does: a 31.4 kHz clock,
// a divide-by-(AUDF+1) counter, and AUDC choosing pure tones, divide-by-31, or 4/5/9-bit
// polynomial noise (after Ron Fries' TIA sound emulation).

import { TIA_CLOCK, Channel } from './tia-synth.js';

class TiaProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    this.ch = [new Channel(), new Channel()];
    (options?.processorOptions?.regs || []).forEach((r, i) => this.ch[i].set(r.f, r.c, r.v));
    this.acc = 0;
    this.x1 = 0; this.y1 = 0;          // DC blocker state
    this.port.onmessage = ({ data }) => data.forEach((r, i) => this.ch[i].set(r.f, r.c, r.v));
  }

  process(_inputs, outputs) {
    const out = outputs[0][0];
    const step = TIA_CLOCK / sampleRate;
    for (let i = 0; i < out.length; i++) {
      this.acc += step;
      while (this.acc >= 1) { this.acc -= 1; this.ch[0].clock(); this.ch[1].clock(); }
      const x = (this.ch[0].level() + this.ch[1].level()) / 30;
      const y = x - this.x1 + 0.995 * this.y1;   // remove the TIA's DC offset
      this.x1 = x; this.y1 = y;
      out[i] = y * 0.6;
    }
    for (let c = 1; c < outputs[0].length; c++) outputs[0][c].set(out);
    return true;
  }
}

registerProcessor('tia', TiaProcessor);
