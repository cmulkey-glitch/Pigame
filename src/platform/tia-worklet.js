// TIA sound synth (AudioWorklet). Renders the two channels from the AUDF / AUDC / AUDV values
// the game's SoundDriver posts every frame, the way the Atari TIA does: a 31.4 kHz clock,
// a divide-by-(AUDF+1) counter, and AUDC choosing pure tones, divide-by-31, or 4/5/9-bit
// polynomial noise (after Ron Fries' TIA sound emulation).

const TIA_CLOCK = 3579545 / 114;   // NTSC colour clock / 114, about 31.4 kHz

const BIT4 = [1, 1, 0, 1, 1, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0];
const BIT5 = [0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 1, 1, 0, 1, 1, 1, 0, 1, 0, 1, 0, 0, 0, 0, 1];
const DIV31 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1];
const BIT9 = (() => {             // 9-bit LFSR, x^9 + x^5 + 1
  const out = []; let r = 0x1FF;
  for (let i = 0; i < 511; i++) { out.push(r & 1); const b = ((r >> 0) ^ (r >> 4)) & 1; r = (r >> 1) | (b << 8); }
  return out;
})();

class Channel {
  constructor() { this.f = 0; this.c = 0; this.v = 0; this.cnt = 0; this.max = 0; this.p4 = 0; this.p5 = 0; this.p9 = 0; this.out = 0; }

  set(f, c, v) {
    this.f = f & 31; this.c = c & 15; this.v = v & 15;
    if (this.c === 0 || this.c === 11) { this.cnt = 0; this.out = 1; return; }   // DC: no tone
    const max = (this.f + 1) * ((this.c & 0x0C) === 0x0C ? 3 : 1);
    if (max !== this.max) { this.max = max; if (!this.cnt) this.cnt = max; }
  }

  clock() {
    if (this.cnt > 1) { this.cnt--; return; }
    if (this.cnt !== 1) return;
    this.cnt = this.max;
    this.p5 = (this.p5 + 1) % 31;
    const c = this.c;
    if (!(c & 2) || (!(c & 1) && DIV31[this.p5]) || ((c & 1) && BIT5[this.p5])) {
      if (c & 4) this.out ^= 1;                                        // pure tone
      else if (c & 8) {
        if (c === 8) { this.p9 = (this.p9 + 1) % 511; this.out = BIT9[this.p9]; }   // white noise
        else this.out = BIT5[this.p5];
      } else { this.p4 = (this.p4 + 1) % 15; this.out = BIT4[this.p4]; }
    }
  }

  level() { return this.out ? this.v : 0; }
}

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
