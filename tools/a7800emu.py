"""Minimal Atari 7800 harness for asset extraction.

py65 runs the 6502; MARIA is approximated: MSTAT/VBLANK timing, WSYNC, DLI NMIs, and a
display-list renderer (160A/B, 320A/B/C/D, indirect char mode). Not cycle accurate —
it only has to run the game far enough to capture screens and RAM.
"""
from py65.devices.mpu6502 import MPU
from PIL import Image
import math

ROM = None  # set by load_rom()

def load_rom(path):
    """Load a .a78 image; returns the 32K game ROM mapped at $8000."""
    global ROM
    ROM = open(path, 'rb').read()[128:128 + 0x8000]
    return ROM

def ntsc_palette():
    pal=[]
    for c in range(256):
        hue, lum = c>>4, c&15
        y = lum/15.0
        if hue==0:
            r=g=b=y
        else:
            ang = math.radians((hue-1)*25.7 - 58)
            sat = 0.35
            i = sat*math.cos(ang); q = sat*math.sin(ang)
            yy = 0.1+0.8*y
            r = yy+0.956*i+0.621*q; g = yy-0.272*i-0.647*q; b = yy-1.106*i+1.703*q
        pal.append(tuple(max(0,min(255,int(v*255))) for v in (r,g,b)))
    return pal
PAL = ntsc_palette()

class Mem:
    def __init__(s, emu):
        s.e = emu
        s.m = bytearray(0x10000)
        s.m[0x8000:] = ROM
    def _map(s, a):
        if 0x40 <= a < 0x100: return a + 0x2000
        if 0x140 <= a < 0x200: return a + 0x2000
        if 0x2800 <= a < 0x3000:  # mirrors of 2000-27ff region (approx)
            return a - 0x800
        return a
    def __getitem__(s, a):
        if isinstance(a, slice): return [s[i] for i in range(*a.indices(0x10000))]
        a &= 0xffff
        if a < 0x40:
            return s.e.read_io(a)
        if 0x280 <= a < 0x300:
            return s.e.read_riot(a)
        return s.m[s._map(a)]
    def __setitem__(s, a, v):
        a &= 0xffff
        if a < 0x40:
            s.e.write_io(a, v); return
        if 0x280 <= a < 0x300:
            return
        if a >= 0x8000: return
        s.m[s._map(a)] = v & 0xff
    def __len__(s): return 0x10000

LINES=263; CPL=114; VIS0=16; VIS1=259

class Emu:
    def __init__(s):
        assert ROM is not None, 'call load_rom() first'
        s.regs = bytearray(0x40)
        s.mem = Mem(s)
        s.cpu = MPU(memory=s.mem)
        s.cpu.pc = s.mem[0xfffc] | (s.mem[0xfffd]<<8)
        s.cyc = 0
        s.joy = 0xff   # SWCHA, 1 = released (P0 high nibble: R L D U = bits 7..4)
        s.fire = False
        s.swchb = 0xff
        s.frame = 0
        s.dli_lines = set()
        s.pending_wsync = False
    def line(s): return (s.cyc // CPL) % LINES
    def read_io(s, a):
        if a == 0x28:  # MSTAT
            l = s.line()
            return 0x80 if (l < VIS0 or l >= VIS1) else 0
        if a == 0x0C: return 0x00 if s.fire else 0x80  # INPT4
        if a in (0x08, 0x09): return 0x80 if s.fire else 0x00  # INPT0/1 (7800 buttons, 1 = pressed)
        if a == 0x0D: return 0x80
        return 0
    def read_riot(s, a):
        if a == 0x280: return s.joy
        if a == 0x282: return s.swchb
        if a == 0x284: return (s.cyc>>3)&0xff
        return 0
    def write_io(s, a, v):
        if a == 0x24:  # WSYNC
            s.pending_wsync = True
        s.regs[a] = v
    def run_frame(s, on_line=None):
        """Run one 263-line frame. on_line = (line, fn) calls fn() when that line starts."""
        target = (s.frame+1)*LINES*CPL
        cpu = s.cpu
        while s.cyc < target:
            before = cpu.processorCycles
            cpu.step()
            s.cyc += cpu.processorCycles - before
            if s.pending_wsync:
                s.pending_wsync = False
                s.cyc = (s.cyc//CPL + 1)*CPL
            l = s.line()
            if l != getattr(s,'_last_line',-1):
                s._last_line = l
                if on_line and l == on_line[0]:
                    on_line[1]()
                if l == VIS0:
                    s.compute_dll()
                if l in s.dli_lines:
                    s.dli_lines.discard(l)
                    cpu.nmi()
                    s.cyc += 7
        s.frame += 1
    def compute_dll(s):
        m = s.mem
        dll = (s.regs[0x2C]<<8) | s.regs[0x30]
        s.dll_addr = dll
        l = VIS0; s.dli_lines=set()
        p = dll
        while l < VIS1:
            b0 = m[p]
            h = (b0 & 15) + 1
            if b0 & 0x80:
                s.dli_lines.add(l + h - 1)
            l += h; p += 3
            if p > dll + 3*100: break
    def render(s):
        m = s.mem; r = s.regs
        W=320; H=VIS1-VIS0
        img = Image.new('RGB',(W,H), PAL[r[0x20]])
        px = img.load()
        ctrl = r[0x3C]; rm = ctrl & 3; cw = 2 if ctrl & 0x10 else 1
        pals = [[r[0x20]] + [r[0x21+4*i], r[0x22+4*i], r[0x23+4*i]] for i in range(8)]
        dll = (r[0x2C]<<8) | r[0x30]
        y = 0; p = dll; wm = 0
        while y < H:
            b0 = m[p]; dl = (m[p+1]<<8) | m[p+2]; p += 3
            h = (b0 & 15) + 1; h16 = b0 & 0x40; h8 = b0 & 0x20
            for off in range(h-1, -1, -1):
                if y >= H: break
                linebuf = [None]*320
                q = dl
                for _ in range(64):
                    lo = m[q]; b1 = m[q+1]
                    if (b1 & 0x5F) == 0: break
                    if (b1 & 0x1F) == 0:
                        wm = b1 >> 7; ind = b1 & 0x20
                        hi = m[q+2]; pw = m[q+3]; hp = m[q+4]; q += 5
                    else:
                        ind = 0; pw = b1; hi = m[q+2]; hp = m[q+3]; q += 4
                    palno = pw >> 5; width = (32 - (pw & 31)) & 31 or 32
                    base = (((hi + off) & 0xff) << 8) | lo
                    gbytes = []
                    if ind:
                        cb = r[0x34]
                        for i in range(width):
                            ch = m[(base - (off<<8) + i) & 0xffff]
                            for k in range(cw):
                                gbytes.append(m[(((cb + off)&0xff) << 8) + ((ch + k) & 0xff)])
                    else:
                        ga = base
                        holey = (h16 and (ga & 0x1000)) or (h8 and (ga & 0x0800))
                        for i in range(width):
                            gbytes.append(0 if (holey and ga>=0x8000) else m[(ga + i) & 0xffff])
                    x = (hp*2) & 0x1ff
                    s._draw(linebuf, x, gbytes, palno, rm, wm, pals)
                for xx in range(320):
                    c = linebuf[xx]
                    if c is not None: px[xx, y] = PAL[c]
                y += 1
        return img
    def _draw(s, lb, x, gb, palno, rm, wm, pals):
        def put(xx, c):
            xx &= 0x1ff
            if xx < 320: lb[xx] = c
        for b in gb:
            if rm == 0 and wm == 0:      # 160A
                for i in range(4):
                    v = (b >> (6-2*i)) & 3
                    if v: put(x, pals[palno][v]); put(x+1, pals[palno][v])
                    x += 2
            elif rm == 0:                 # 160B
                for i in range(2):
                    c = (b >> (6-2*i)) & 3
                    pp = (b >> (2-2*i)) & 3
                    if c: put(x, pals[(palno & 4) | pp][c]); put(x+1, pals[(palno & 4) | pp][c])
                    x += 2
            elif rm == 3 and wm == 0:     # 320A
                for i in range(8):
                    if b & (0x80 >> i): put(x, pals[palno][2])
                    x += 1
            elif rm == 3:                 # 320C
                for i in range(4):
                    if b & (0x80 >> i):
                        pp = (palno & 4) | ((b >> (2 if i < 2 else 0)) & 3)
                        put(x, pals[pp][2])
                    x += 1
            elif rm == 2 and wm == 1:     # 320B
                for i in range(4):
                    v = ((b >> (7-i)) & 1) << 1 | ((b >> (3-i)) & 1)
                    if v: put(x, pals[palno][v])
                    x += 1
            else:                          # 320D
                for i in range(8):
                    v = ((b >> (7-i)) & 1) << 1 | ((palno >> (1 - (i & 1))) & 1)
                    if v: put(x, pals[palno & 4][v])
                    x += 1
