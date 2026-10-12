"""Screenshots without a Roku: run the real main.brs in the brs interpreter with the screen,
fonts and bitmaps swapped for stand-ins that log every draw call, then paint the log with
Pillow. Text is measured with the same font that paints it (DejaVu Sans, or Arial; the Roku's own font is
similar but not the same), so centring and layout match.

A scenario file defines `sub Scenario(app as object)`, sets the game up and calls
`Shot(app, "name")` for each picture. dash/tests/shots.brs covers every screen.

Usage: python3 dash/tools/build.py                   (once: the images come from the build)
       python3 dash/tools/shot.py [scenario.brs] [out-dir]    -> dist/shots/<name>.png
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
DASH = os.path.join(HERE, '..')
ROKU = os.path.join(DASH, 'roku')
DIST = os.path.join(DASH, '..', 'dist')
IMGS = os.path.join(DIST, 'spiral-shift-roku')
# DejaVu Sans where it is installed (Linux), else Arial (Windows, macOS)
FONTS = {True: ('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 'DejaVuSans-Bold.ttf', 'arialbd.ttf',
                '/System/Library/Fonts/Supplemental/Arial Bold.ttf'),
         False: ('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 'DejaVuSans.ttf', 'arial.ttf',
                 '/System/Library/Fonts/Supplemental/Arial.ttf')}
SIZES = (20, 22, 24, 26, 28, 30, 32, 36, 40, 48, 64, 72, 80, 90)


def font(size, bold):
    for name in FONTS[bold]:
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    sys.exit('no DejaVu Sans or Arial font found')


STANDINS = r'''
function Shot_font(size as integer, bold as boolean) as object
    k = size.ToStr()
    if bold then k = k + "b"
    return { size: size, bold: bold, w: m.shotWidths[k], GetOneLineWidth: Shot_textw, GetOneLineHeight: function() : return m.size : end function }
end function

function Shot_textw(text as string, maxw as integer) as integer
    w = 0.0
    for i = 1 to Len(text)
        c = Asc(Mid(text, i, 1)).ToStr()
        if m.w.DoesExist(c) then w = w + m.w[c] else w = w + m.size * 0.6
    end for
    if w > maxw then w = maxw
    return Int(w)
end function

function Shot_fonts() as object
    return { GetDefaultFont: function(size, bold, italic) : return Shot_font(size, bold) : end function }
end function

function Shot_bitmap(path as string) as object
    p = Mid(path, 6)
    s = Shot_sizes()
    return { path: p, x: 0, y: 0, w: s[p][0], h: s[p][1], GetWidth: function() : return m.w : end function, GetHeight: function() : return m.h : end function }
end function

function Shot_region(b as object, x as integer, y as integer, w as integer, h as integer) as object
    return { path: b.path, x: x, y: y, w: w, h: h, GetWidth: function() : return m.w : end function, GetHeight: function() : return m.h : end function }
end function

function Shot_screen() as object
    return { log: []
        Clear: sub(c) : m.log.Push("C " + J([c])) : end sub
        DrawRect: sub(x, y, w, h, c) : m.log.Push("R " + J([x, y, w, h, c])) : end sub
        DrawObject: sub(x, y, o) : m.log.Push("O " + J([x, y, 1, 1]) + " " + o.path + " " + J([o.x, o.y, o.w, o.h])) : end sub
        DrawScaledObject: sub(x, y, sx, sy, o) : m.log.Push("O " + J([x, y, sx, sy]) + " " + o.path + " " + J([o.x, o.y, o.w, o.h])) : end sub
        DrawText: sub(t, x, y, c, f)
            b = "0"
            if f.bold then b = "1"
            m.log.Push("T " + J([x, y, c, f.size]) + " " + b + " " + t)
        end sub
        SetMessagePort: sub(p) : end sub, SetAlphaEnable: sub(b) : end sub, SwapBuffers: sub() : end sub
    }
end function

function J(a as object) as string
    s = ""
    for each v in a
        if s <> "" then s = s + " "
        s = s + Str(v).Trim()
    end for
    return s
end function

' Draw the current frame and print its log.
sub Shot(app as object, name as string)
    app.screen.log = []
    app.draw(0)
    print "SHOT " + name
    for each l in app.screen.log
        print l
    end for
    print "END"
end sub

' Advance n frames as the main loop does (ticks and, while running, steps).
sub Frames(app as object, n as integer)
    for i = 1 to n
        app.tick()
        if app.running() then app.step()
    end for
end sub

sub Main()
    m.shotWidths = Shot_widths()
    _brs_.mockComponent("roAudioPlayer", { SetLoop: sub(b) : end sub, Stop: sub() : end sub, Play: sub() : end sub, Pause: sub() : end sub, Resume: sub() : end sub, SetContentList: sub(l) : end sub })
    _brs_.mockComponent("roAudioResource", { Trigger: sub(v) : end sub })
    m.shotReg = {}
    _brs_.mockComponent("roRegistrySection", { Exists: function(k) : return GetGlobalAA().shotReg.DoesExist(k) : end function, Read: function(k) : return GetGlobalAA().shotReg[k] : end function, Write: sub(k, v) : GetGlobalAA().shotReg[k] = v : end sub, Flush: sub() : end sub, Delete: sub(k) : GetGlobalAA().shotReg.Delete(k) : end sub })
    app = App_new(CreateObject("roMessagePort"))
    Scenario(app)
end sub
'''


def generated():
    """Shot_widths (character widths per font) and Shot_sizes (image sizes) as BrightScript."""
    rows = []
    for size in SIZES:
        for bold in (False, True):
            f = font(size, bold)
            ws = ', '.join(f'"{c}": {f.getlength(chr(c)):.2f}' for c in range(32, 127))
            rows.append(f'    t["{size}{"b" if bold else ""}"] = {{ {ws} }}')
    sizes = []
    for f in sorted(os.listdir(os.path.join(IMGS, 'images'))):
        if f.endswith('.png'):
            w, h = Image.open(os.path.join(IMGS, 'images', f)).size
            sizes.append(f'"images/{f}": [{w}, {h}]')
    return ('function Shot_widths() as object\n    t = {}\n' + '\n'.join(rows) + '\n    return t\nend function\n'
            'function Shot_sizes() as object\n    return { ' + ', '.join(sizes) + ' }\nend function\n')


def color(v):
    return tuple((int(float(v)) & 0xFFFFFFFF).to_bytes(4, 'big'))


def paste(img, layer, x, y):
    """Alpha-composite layer onto img at (x, y), clipped to the screen."""
    x0, y0 = max(x, 0), max(y, 0)
    x1, y1 = min(x + layer.width, img.width), min(y + layer.height, img.height)
    if x1 <= x0 or y1 <= y0:
        return
    part = layer.crop((x0 - x, y0 - y, x1 - x, y1 - y))
    img.paste(Image.alpha_composite(img.crop((x0, y0, x1, y1)), part), (x0, y0))


def render(log, cache):
    img = Image.new('RGBA', (1280, 720), (0, 0, 0, 255))
    for line in log:
        kind, rest = line[0], line[2:]
        f = rest.split(' ')
        if kind == 'C':
            img.paste(color(f[0]), (0, 0, 1280, 720))
        elif kind == 'R':
            x, y, w, h = (int(float(v)) for v in f[:4])
            if w > 0 and h > 0:
                paste(img, Image.new('RGBA', (w, h), color(f[4])), x, y)
        elif kind == 'O':
            x, y, sx, sy = (float(v) for v in f[:4])
            path = f[4]
            rx, ry, rw, rh = (int(float(v)) for v in f[5:9])
            if path not in cache:
                cache[path] = Image.open(os.path.join(IMGS, path)).convert('RGBA')
            im = cache[path].crop((rx, ry, rx + rw, ry + rh))
            if sx != 1 or sy != 1:
                im = im.resize((max(1, round(rw * sx)), max(1, round(rh * sy))), Image.LANCZOS)
            paste(img, im, int(x), int(y))
        elif kind == 'T':
            x, y, c, size, bold = float(f[0]), float(f[1]), color(f[2]), int(float(f[3])), f[4] == '1'
            text = rest.split(' ', 5)[5] if len(f) > 5 else ''
            layer = Image.new('RGBA', img.size, (0, 0, 0, 0))
            ImageDraw.Draw(layer).text((x, y), text, fill=c, font=font(size, bold))
            img.alpha_composite(layer)
    return img.convert('RGB')


def main():
    scenario = sys.argv[1] if len(sys.argv) > 1 else os.path.join(DASH, 'tests', 'shots.brs')
    out_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(DIST, 'shots')
    os.makedirs(out_dir, exist_ok=True)
    src = open(os.path.join(ROKU, 'source', 'main.brs')).read()
    src = src.replace('sub Main(args as dynamic)', 'sub Main_real(args as dynamic)')
    src = re.sub(r'(sub Memory_watch\(port as object\)\n).*?(\nend sub)', r'\1\2', src, flags=re.S)
    src = re.sub(r'CreateObject\("roScreen"[^)]*\)', 'Shot_screen()', src)
    src = src.replace('CreateObject("roFontRegistry")', 'Shot_fonts()')
    src = src.replace('CreateObject("roBitmap", ', 'Shot_bitmap(')
    src = src.replace('CreateObject("roRegion", ', 'Shot_region(')
    with tempfile.TemporaryDirectory() as tmp:
        open(os.path.join(tmp, 'main_shot.brs'), 'w').write(src)
        open(os.path.join(tmp, 'standins.brs'), 'w').write(STANDINS + generated())
        files = [os.path.join(ROKU, 'source', f) for f in ('game.brs', 'world.brs', 'ads.brs')]
        files += [os.path.join(tmp, 'main_shot.brs'), os.path.join(tmp, 'standins.brs'), scenario]
        brs = shutil.which('brs') or sys.exit('brs not found: npm install -g brs')
        out = subprocess.run([brs, '--root', ROKU] + files, capture_output=True, text=True)
    if 'SHOT ' not in out.stdout:
        sys.exit(out.stdout[-3000:] + out.stderr[-3000:])
    cache, name, log = {}, None, []
    for line in out.stdout.split('\n'):
        if line.startswith('SHOT '):
            name, log = line[5:].strip(), []
        elif line == 'END' and name:
            path = os.path.join(out_dir, name + '.png')
            render(log, cache).save(path)
            print('wrote', os.path.relpath(path))
            name = None
        elif name:
            log.append(line)
        elif line.strip():
            print(line)


if __name__ == '__main__':
    main()
