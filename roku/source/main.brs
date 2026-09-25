' Roku shell for the Downland port: loads the data, runs Game at 60 steps a second, reads the
' remote and draws. Everything the game does lives in game.brs / player.brs / world.brs.
'
' The picture is built in a 320 x 200 bitmap (7800 320-mode resolution, HUD row on top) and
' scaled 3x with nearest-neighbour onto the 1280 x 720 screen. Game coordinates convert as on
' the web: px = x * 2 - 8, py = y.
'
' Remote (held sideways, see Pad_new): arrows move / climb, Play or OK jumps, Back
' returns to the title (exits from the title), Rew / Fwd step through chambers (playtest).

sub Main()
    port = CreateObject("roMessagePort")
    screen = CreateObject("roScreen", true, 1280, 720)
    screen.SetMessagePort(port)
    screen.SetAlphaEnable(true)

    data = {
        rooms: ReadJson("pkg:/data/rooms.json")
        sounds: ReadJson("pkg:/data/sounds.json")
        sprites: ReadJson("pkg:/data/sprites.json")
    }
    game = Game_new({ rooms: data.rooms.rooms, title: data.rooms.title
                      doorOpenInitial: data.rooms.doorOpenInitial, sounds: data.sounds.sounds })
    reg = CreateObject("roRegistrySection", "downland")
    if reg.Exists("hi") then game.hiScore = reg.Read("hi").ToInt()
    savedHi = game.hiScore

    v = View_new(data)
    audio = Audio_new(data.sounds.sounds)
    pad = Pad_new()

    clock = CreateObject("roTimespan")
    stepMs = 1000.0 / 59.94
    acc = 0.0
    clock.Mark()
    while true
        msg = port.GetMessage()
        while msg <> invalid
            if type(msg) = "roUniversalControlEvent" then
                code = msg.GetInt()
                if code = 0 and game.mode = "title" then return    ' Back on the title exits
                pad.key(code)
            end if
            msg = port.GetMessage()
        end while

        acc = acc + clock.TotalMilliseconds()
        clock.Mark()
        if acc > stepMs * 4 then acc = stepMs * 4
        while acc >= stepMs
            acc = acc - stepMs
            game.update(pad.sample(), pad.takeActions())
            for each s in game.sfx
                audio.handle(s)
            end for
            game.sfx = []
        end while

        if game.hiScore <> savedHi then
            savedHi = game.hiScore
            reg.Write("hi", savedHi.ToStr())
            reg.Flush()
        end if

        v.render(game)
        screen.Clear(&h000000FF)
        screen.DrawScaledObject(160, 60, 3, 3, v.region)
        screen.SwapBuffers()
    end while
end sub

function ReadJson(path as string) as object
    return ParseJson(ReadAsciiFile(path))
end function

function Pad6(n as integer, width as integer) as string
    s = n.ToStr()
    while Len(s) < width
        s = "0" + s
    end while
    return s
end function

' ---- remote ----
' The remote is held sideways (top to the left): Up moves left, Right climbs up, Down moves
' right, Left climbs down. Play and OK jump.
' A Roku remote sends one key at a time, so direction + jump can't be held together. Jump goes
' in the direction held, or released, within the last 12 frames; the jump keeps that
' direction for its first frames so the ROM's take-off check sees it.
function Pad_new() as object
    return {
        held: {}, frame: 0, lastLeft: -99, lastRight: -99, jumpFrames: 0, jumpDir: ""
        actions: [], key: Pad_key, sample: Pad_sample, takeActions: Pad_takeActions
    }
end function

function Pad_button(code as integer) as string
    buttons = { "2": "left", "5": "up", "3": "right", "4": "down", "6": "jump", "13": "jump" }
    n = buttons[code.ToStr()]
    if n = invalid then return ""
    return n
end function

sub Pad_key(code as integer)
    if code >= 100 then
        n = Pad_button(code - 100)
        if n <> "" then
            m.held.Delete(n)
            if n = "left" then m.lastLeft = m.frame
            if n = "right" then m.lastRight = m.frame
        end if
        return
    end if
    if code = 0 then m.actions.Push("title")
    if code = 8 then m.actions.Push("prev")
    if code = 9 then m.actions.Push("next")
    n = Pad_button(code)
    if n = "" then return
    m.held[n] = true
    if n = "jump" then
        m.jumpFrames = 6
        m.jumpDir = ""
        if m.held.DoesExist("left") or m.frame - m.lastLeft <= 12 then m.jumpDir = "left"
        if m.held.DoesExist("right") or m.frame - m.lastRight <= 12 then m.jumpDir = "right"
    end if
end sub

function Pad_sample() as object
    m.frame = m.frame + 1
    h = m.held
    inp = { left: h.DoesExist("left"), right: h.DoesExist("right"), up: h.DoesExist("up")
            down: h.DoesExist("down"), jump: h.DoesExist("jump") }
    if inp.left then m.lastLeft = m.frame
    if inp.right then m.lastRight = m.frame
    if m.jumpFrames > 0 then
        m.jumpFrames = m.jumpFrames - 1
        inp.jump = true
        if m.jumpDir = "left" then
            inp.left = true
            inp.right = false
        else if m.jumpDir = "right" then
            inp.right = true
            inp.left = false
        end if
    end if
    return inp
end function

function Pad_takeActions() as object
    a = m.actions
    m.actions = []
    return a
end function

' ---- sound: pre-rendered WAVs played on the TIA channel the driver picked ----
function Audio_new(sounds as object) as object
    a = { res: {}, streams: 1, handle: Audio_handle }
    for each name in sounds
        if Left(name, 5) = "climb" then
            files = [name + "_0", name + "_1"]
        else
            files = [name]
        end if
        for each f in files
            r = CreateObject("roAudioResource", "pkg:/sounds/" + f + ".wav")
            if r <> invalid then
                a.res[f] = r
                a.streams = r.MaxSimulStreams()
            end if
        end for
    end for
    return a
end function

sub Audio_handle(s as object)
    if s.kind = "stop" then
        for each f in m.res
            m.res[f].Stop()
        end for
        return
    end if
    f = s.name
    if Left(f, 5) = "climb" then f = f + "_" + s.pitch.ToStr()
    r = m.res[f]
    if r = invalid then return
    ch = s.ch
    if ch >= m.streams then ch = m.streams - 1
    r.Trigger(80, ch)
end sub

' ---- drawing ----
function View_new(data as object) as object
    v = {
        bmp: CreateObject("roBitmap", { width: 320, height: 200, AlphaEnable: true })
        backgrounds: {}, inks: {}, sprites: []
        rooms: data.rooms.rooms, title: data.rooms.title
        version: "V" + CreateObject("roAppInfo").GetVersion()     ' shown on the title screen
        playerFrames: data.sprites.playerFrames, ballFrames: data.sprites.ballFrames
        birdFrames: data.sprites.birdFrames, dropSprite: 0
        render: View_render, renderTitle: View_renderTitle, renderPlay: View_renderPlay, background: View_background
        ink: View_ink, tile: View_tile, text: View_text, flanked: View_flanked, sprite: View_sprite
        region: invalid, regions: {}, glyph: View_glyph
    }
    v.region = CreateObject("roRegion", v.bmp, 0, 0, 320, 200)
    v.region.SetScaleMode(0)
    sheet = CreateObject("roBitmap", "pkg:/images/sprites.png")
    i = 0
    for each s in data.sprites.sprites
        v.sprites.Push(CreateObject("roRegion", sheet, s.x, s.y, s.w, s.h))
        if s.addr = "$E02E" then v.dropSprite = i
        i = i + 1
    end for
    return v
end function

function View_background(name as string) as object
    b = m.backgrounds[name]
    if b = invalid then
        b = CreateObject("roBitmap", "pkg:/images/" + name + ".png")
        m.backgrounds[name] = b
    end if
    return b
end function

' tiles.png pre-tinted in one colour ("#rrggbb")
function View_ink(colour as string) as object
    key = UCase(Mid(colour, 2))
    b = m.inks[key]
    if b = invalid then
        b = CreateObject("roBitmap", "pkg:/images/ink_" + key + ".png")
        m.inks[key] = b
    end if
    return b
end function

'  cached 8-line region of an ink atlas
function View_glyph(colour as string, x as integer, y as integer, w as integer) as object
    key = colour + ":" + x.ToStr() + ":" + y.ToStr() + ":" + w.ToStr()
    r = m.regions[key]
    if r = invalid then
        r = CreateObject("roRegion", m.ink(colour), x, y, w, 8)
        m.regions[key] = r
    end if
    return r
end function

' tile code (double-byte char, as the map stores it) at a pixel position
sub View_tile(code as integer, x as integer, y as integer, colour as string)
    t = code >> 1
    m.bmp.DrawObject(x, y, m.glyph(colour, (t mod 16) * 16, (t \ 16) * 8, 16))
end sub

' [$C1 = '0', $CC = 'A'] 8x8 glyphs from the font halves of the tiles
sub View_text(s as string, x as integer, y as integer, colour as string)
    for i = 1 to Len(s)
        c = Asc(Mid(s, i, 1))
        b = -1
        if c >= 48 and c <= 57 then b = &hC1 + c - 48
        if c >= 65 and c <= 90 then b = &hCC + c - 65
        if b >= 0 then
            t = b >> 1
            m.bmp.DrawObject(x, y, m.glyph(colour, (t mod 16) * 16 + (b and 1) * 8, (t \ 16) * 8, 8))
        end if
        x = x + 8
    end for
end sub

sub View_flanked(word as string, code as integer, y as integer, colour as string)
    x = (&h48 - Len(word) * 2) * 2 - 8
    m.tile(code, x, y, colour)
    m.text(word, x + 16, y, colour)
    m.tile(code, x + 16 + 8 * Len(word), y, colour)
end sub

sub View_sprite(index as integer, x as integer, y as integer)
    m.bmp.DrawObject(x * 2 - 8, y, m.sprites[index])
end sub

sub View_renderTitle(g as object)
    t = m.title
    ' [$80F0] every 64 frames the title colours flip
    if (g.frame and &h80) <> 0 then phase = 0 else phase = 1
    pal = []
    for each p in t.palettesRGB
        pal.Push(p[2])
    end for
    pal[0] = t.flashRGB[phase][0]
    pal[7] = t.flashRGB[phase][1]
    m.bmp.Clear(&h000000FF)
    m.bmp.DrawObject(0, 8, m.background("title_" + phase.ToStr()))
    for each d in g.drops.visible()
        m.sprite(m.dropSprite, d.x, d.y)
    end for
    if g.beginner then
        name = "BEGINNER" : ink = pal[5]
    else
        name = t.difficultyNames[g.difficulty] : ink = pal[t.difficultyPalettes[g.difficulty]]
    end if
    m.flanked(name, &h20, &h82, ink)
    if g.escapeMode then modeName = t.modeNames[1] else modeName = t.modeNames[0]
    m.flanked(modeName, &h22, &h8C, pal[2])
    hi = "HI " + Pad6(g.hiScore, 6)
    m.text(hi, 320 - 8 * Len(hi), 0, pal[7])
    m.text(m.version, 0, 192, pal[7])     ' font has no '.', so 0.1.4 reads "V0 1 4"
end sub

sub View_render(g as object)
    if g.mode = "title" then
        m.renderTitle(g)
    else
        m.renderPlay(g)
    end if
end sub

sub View_renderPlay(g as object)
    def = g.room.def
    pal = def.palettesRGB
    m.bmp.Clear(&h000000FF)
    m.bmp.DrawObject(0, 8, m.background("chamber_" + g.roomIndex.ToStr()))
    for each o in g.room.objects()
        c = o.code
        if c <> 0 then
            if c = &h24 then
                ink = pal[4][2]
            else if c = &h20 then
                ink = pal[5][2]
            else
                ink = pal[2][2]     ' ring, and door cells open or locked (locked = wall in door colour)
            end if
            m.tile(c, o.col * 16, 8 + o.row * 8, ink)
        end if
    end for
    for each d in g.drops.visible()
        m.sprite(m.dropSprite, d.x, d.y)
    end for
    if (g.frame and 8) <> 0 then anim = 1 else anim = 0
    if g.ball <> invalid then m.sprite(m.ballFrames[anim], g.ball.x, g.ball.y)
    if g.bird <> invalid then m.sprite(m.birdFrames[anim], g.bird.x, g.bird.y)

    pl = g.player
    f = m.playerFrames[pl.frameIndex(g.frame)]
    m.sprite(f[0], pl.x, pl.y)
    m.sprite(f[1], pl.x, pl.y + 8)

    m.bmp.DrawRect(0, 0, 320, 8, &h000000FF)
    m.text(Pad6(g.score, 6), 0, 0, pal[7][2])
    if g.beginner then d = "B" else d = g.difficulty.ToStr()
    m.text("L" + pl.lives.ToStr() + " K" + g.keys.ToStr() + " D" + d, 56, 0, pal[4][2])
    if g.timer < 500 then ink = pal[4][2] else ink = pal[7][2]
    m.text(Pad6(g.timer, 4), 144, 0, ink)
    m.text(def.name, 320 - 8 * Len(def.name), 0, pal[7][2])

    ' [$C63F / $C58B] end screens over the frozen chamber, in palette 7
    endText = m.title.endText
    if g.mode = "gameover" then m.text(endText[2], &h3E * 2 - 8, &h50, pal[7][2])
    if g.mode = "escaped" then
        m.text(endText[0], &h4A * 2 - 8, &h50, pal[7][2])
        m.text(endText[1], &h42 * 2 - 8, &h58, pal[7][2])
    end if
end sub
