#!/usr/bin/env python3
"""Dump the Downland 7800 graphics block ($E000-$EFFF) as a 1bpp sprite sheet.

Usage: extract_gfx.py path/to/Downland.a78 [out.png]
The ROM is 32K (mirrored to 64K in the .a78), mapped at $8000-$FFFF.
7800 graphics layout: each 256-byte page is one pixel row, top row in the highest page.
"""
import sys
from PIL import Image

ROM_BASE = 0x8000
GFX_ADDR = 0xE000
ZONE_H = 16

def main():
    rom = open(sys.argv[1], 'rb').read()[128:128 + 0x8000]
    out = sys.argv[2] if len(sys.argv) > 2 else 'downland_e000_sheet.png'
    base = GFX_ADDR - ROM_BASE
    img = Image.new('RGB', (2048, ZONE_H))
    for line in range(ZONE_H):
        page = base + (ZONE_H - 1 - line) * 256
        for x in range(256):
            b = rom[page + x]
            for bit in range(8):
                if b & (0x80 >> bit):
                    img.putpixel((x * 8 + bit, line), (255, 255, 255))
    sheet = Image.new('RGB', (1536, 4 * (ZONE_H + 6) * 3), (40, 40, 60))
    for k in range(4):
        strip = img.crop((k * 512, 0, (k + 1) * 512, ZONE_H)).resize((1536, ZONE_H * 3), Image.NEAREST)
        sheet.paste(strip, (0, k * (ZONE_H + 6) * 3 + 9))
    sheet.save(out)

if __name__ == '__main__':
    main()
