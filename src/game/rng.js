// 7800basic's rand ($FA67): a 16-bit LFSR in $40/$41. Returns 0..255.
export class Rng {
  constructor(seed = 0x744D) { this.lo = seed & 0xFF || 1; this.hi = (seed >> 8) & 0xFF; }

  next() {
    let a = this.lo;
    const carryIn = a & 1;
    a >>= 1;
    const carryOut = this.hi >> 7;
    this.hi = ((this.hi << 1) | carryIn) & 0xFF;
    if (carryOut) a ^= 0xB4;
    this.lo = a;
    return a ^ this.hi;
  }
}
