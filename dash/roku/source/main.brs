' Cube Dash for Roku: screen, remote, sound and menus. The game itself (levels, physics) is
' in game.brs.
'
' 1280 x 720, one block = 60 px. The ground surface is at screen y 600 and the player is
' drawn with its left edge at screen x 300, so the camera is camX = run.x - 5.
'
' Remote: OK, Play or Up jumps (hold to keep jumping; as a ship, hold to climb). Left / Right
' pick a level on the menu. Back leaves a level (exits from the menu).

function Levels_list() as object
    return ["1", "2", "3"]
end function

sub Main()
    port = CreateObject("roMessagePort")
    screen = CreateObject("roScreen", true, 1280, 720)
    screen.SetMessagePort(port)
    screen.SetAlphaEnable(true)

    app = App_new(screen)
    clock = CreateObject("roTimespan")
    stepMs = 1000.0 / 60
    acc = 0.0
    clock.Mark()
    while true
        msg = port.GetMessage()
        while msg <> invalid
            if type(msg) = "roUniversalControlEvent" then
                if not app.key(msg.GetInt()) then
                    app.music.Stop()
                    return
                end if
            end if
            msg = port.GetMessage()
        end while

        acc = acc + clock.TotalMilliseconds()
        clock.Mark()
        if acc > stepMs * 4 then acc = stepMs * 4
        while acc >= stepMs
            acc = acc - stepMs
            app.update()
        end while
        app.draw()
        screen.SwapBuffers()
    end while
end sub

function App_new(screen as object) as object
    fonts = CreateObject("roFontRegistry")
    app = {
        screen: screen, mode: "menu", sel: 0, levels: [], run: invalid, lv: invalid
        attempts: 0, deadFrames: 0, frame: 0, parts: []
        jumpDown: false, tapped: false
        reg: CreateObject("roRegistrySection", "cubedash")
        music: CreateObject("roAudioPlayer")
        sfxDie: CreateObject("roAudioResource", "pkg:/sounds/die.wav")
        sfxWin: CreateObject("roAudioResource", "pkg:/sounds/complete.wav")
        big: fonts.GetDefaultFont(72, true, false)
        mid: fonts.GetDefaultFont(44, true, false)
        small: fonts.GetDefaultFont(28, false, false)
        key: App_key, update: App_update, draw: App_draw, start: App_start, restart: App_restart
        best: App_best, setBest: App_setBest
    }
    for each n in Levels_list()
        app.levels.Push(Level_parse(ReadAsciiFile("pkg:/levels/" + n + ".txt")))
    end for
    app.music.SetLoop(true)

    app.img = {}
    for each name in ["spike", "spike_down", "orb", "pad", "portal_ship", "portal_cube"]
        app.img[name] = CreateObject("roBitmap", "pkg:/images/" + name + ".png")
    end for
    app.cube = Sheet(CreateObject("roBitmap", "pkg:/images/cube.png"), 90)
    app.ship = Sheet(CreateObject("roBitmap", "pkg:/images/ship.png"), 90)
    return app
end function

' A horizontal strip of square frames -> array of regions.
function Sheet(bmp as object, size as integer) as object
    frames = []
    for i = 0 to bmp.GetWidth() / size - 1
        frames.Push(CreateObject("roRegion", bmp, i * size, 0, size, size))
    end for
    return frames
end function

function App_best(i as integer) as integer
    k = "best" + i.ToStr()
    if m.reg.Exists(k) then return m.reg.Read(k).ToInt()
    return 0
end function

sub App_setBest(i as integer, pct as integer)
    if pct > m.best(i) then
        m.reg.Write("best" + i.ToStr(), pct.ToStr())
        m.reg.Flush()
    end if
end sub

' Returns false to quit the channel.
function App_key(code as integer) as boolean
    isJump = (code = 6 or code = 13 or code = 2)
    if code >= 100 then
        c = code - 100
        if c = 6 or c = 13 or c = 2 then m.jumpDown = false
        return true
    end if
    if m.mode = "menu" then
        if code = 0 then return false
        n = m.levels.Count()
        if code = 4 or code = 3 then m.sel = (m.sel + n - 1) mod n
        if code = 5 then m.sel = (m.sel + 1) mod n
        if code = 6 or code = 13 then m.start(m.sel)
    else if m.mode = "play" then
        if code = 0 then
            m.music.Stop()
            m.mode = "menu"
        else if isJump then
            ' every press counts, even if its release has not arrived yet or came in the same
            ' frame (a quick second tap for an orb)
            m.jumpDown = true
            m.tapped = true
        end if
    else if m.mode = "complete" then
        if code = 0 or code = 6 or code = 13 then m.mode = "menu"
    end if
    return true
end function

sub App_start(i as integer)
    m.lv = m.levels[i]
    m.sel = i
    m.attempts = 0
    m.music.SetContentList([{ url: "pkg:/sounds/" + m.lv.music + ".wav" }])
    m.mode = "play"
    m.restart()
end sub

sub App_restart()
    m.run = Run_new(m.lv)
    m.attempts = m.attempts + 1
    m.deadFrames = 0
    m.parts = []
    ' the button that started the level (or is still held from the crash) must not jump
    m.tapped = false
    m.music.Stop()
    m.music.Play()
end sub

sub App_update()
    m.frame = m.frame + 1
    if m.mode <> "play" then return
    r = m.run
    if r.dead then
        m.deadFrames = m.deadFrames + 1
        for each p in m.parts
            p.x = p.x + p.vx
            p.y = p.y + p.vy
            p.vy = p.vy + 0.6
        end for
        if m.deadFrames >= 60 then m.restart()
        return
    end if
    held = m.jumpDown or m.tapped
    if m.tapped then r.held = false     ' a fresh press: make sure Run_step sees the edge
    m.tapped = false
    Run_step(r, held)
    for each e in r.events
        if e = "die" then
            m.music.Stop()
            m.sfxDie.Trigger(90)
            m.setBest(m.sel, Int(Run_progress(r) * 100))
            cx = 330
            cy = 600 - r.y * 60 - 30
            for i = 1 to 28
                a = Rnd(0) * 6.283
                s = 3 + Rnd(0) * 9
                m.parts.Push({ x: cx, y: cy, vx: Cos(a) * s + 3, vy: Sin(a) * s - 4, size: 8 + Rnd(12) })
            end for
        else if e = "win" then
            m.music.Stop()
            m.sfxWin.Trigger(90)
            m.setBest(m.sel, 100)
            m.mode = "complete"
        end if
    end for
    r.events = []
end sub

sub App_draw()
    s = m.screen
    if m.mode = "menu" then
        Draw_menu(m)
        return
    end if
    r = m.run
    lv = m.lv
    camX = r.x - 5
    s.Clear(lv.bg)
    Draw_backdrop(s, camX)

    ' "Attempt N" scrolls past with the level
    ax = Int((1 - camX) * 60)
    if ax > -600 then s.DrawText("Attempt " + m.attempts.ToStr(), ax, 240, &hFFFFFFFF, m.mid)

    c0 = Int(camX)
    if c0 < 0 then c0 = 0
    c1 = c0 + 23
    if c1 > lv.width - 1 then c1 = lv.width - 1
    for c = c0 to c1
        col = lv.cols[c]
        sx = Int((c - camX) * 60)
        for i = 0 to col.Count() - 1
            o = col[i]
            sy = 540 - o.r * 60
            k = o.k
            if k = "#" then
                s.DrawRect(sx, sy, 60, 60, lv.line)
                s.DrawRect(sx + 4, sy + 4, 52, 52, &h0B0B16FF)
            else if k = "^" then
                s.DrawObject(sx, sy, m.img.spike)
            else if k = "v" then
                s.DrawObject(sx, sy, m.img.spike_down)
            else if k = "_" then
                s.DrawObject(sx, sy, m.img.pad)
            else if k = "o" then
                pulse = 0
                if Int(m.frame / 8) mod 2 = 0 then pulse = 1
                s.DrawObject(sx - pulse, sy - pulse, m.img.orb)
            else if k = "S" then
                s.DrawObject(sx, sy - 60, m.img.portal_ship)
            else if k = "C" then
                s.DrawObject(sx, sy - 60, m.img.portal_cube)
            end if
        end for
    end for

    ' ground
    s.DrawRect(0, 600, 1280, 120, lv.ground)
    gx = -Int(camX * 60) mod 240
    for x = gx to 1280 step 240
        s.DrawRect(x, 600, 3, 120, &h00000030)
    end for
    s.DrawRect(0, 600, 1280, 3, &hFFFFFFC0)

    ' player
    if not r.dead then
        cy = 600 - Int(r.y * 60) - 30
        if r.mode = "cube" then
            a = r.angle - Int(r.angle / 90) * 90
            f = Int(a / 5 + 0.5) mod m.cube.Count()
            s.DrawObject(330 - 45, cy - 45, m.cube[f])
        else
            a = r.angle
            if a > 40 then a = 40
            if a < -40 then a = -40
            s.DrawObject(330 - 45, cy - 45, m.ship[Int((a + 40) / 5 + 0.5)])
        end if
    end if
    for each p in m.parts
        s.DrawRect(Int(p.x), Int(p.y), p.size, p.size, &h7CFF6BFF)
    end for

    ' progress
    pct = Int(Run_progress(r) * 100)
    s.DrawRect(440, 24, 400, 18, &hFFFFFF50)
    s.DrawRect(443, 27, Int(394 * Run_progress(r)), 12, &h7CFF6BFF)
    s.DrawText(pct.ToStr() + "%", 856, 16, &hFFFFFFFF, m.small)

    if m.mode = "complete" then
        s.DrawRect(0, 0, 1280, 720, &h00000090)
        Draw_center(s, "LEVEL COMPLETE!", 230, &hFFE14DFF, m.big)
        Draw_center(s, lv.name, 330, &hFFFFFFFF, m.mid)
        Draw_center(s, "Attempts: " + m.attempts.ToStr(), 400, &hFFFFFFFF, m.mid)
        Draw_center(s, "Press OK", 520, &hFFFFFFB0, m.small)
    end if
end sub

' big faint squares drifting at a quarter of the level's speed
sub Draw_backdrop(s as object, camX as float)
    off = -Int(camX * 15) mod 480
    for x = off - 480 to 1280 step 480
        s.DrawRect(x + 40, 80, 200, 200, &hFFFFFF10)
        s.DrawRect(x + 280, 320, 160, 160, &hFFFFFF0C)
    end for
end sub

sub Draw_center(s as object, text as string, y as integer, color as integer, font as object)
    w = font.GetOneLineWidth(text, 1280)
    s.DrawText(text, Int((1280 - w) / 2), y, color, font)
end sub

sub Draw_menu(app as object)
    s = app.screen
    lv = app.levels[app.sel]
    s.Clear(lv.bg)
    Draw_backdrop(s, app.frame / 30)
    s.DrawRect(0, 600, 1280, 120, lv.ground)
    s.DrawRect(0, 600, 1280, 3, &hFFFFFFC0)

    Draw_center(s, "CUBE DASH", 60, &hFFFFFFFF, app.big)

    ' level card
    s.DrawRect(290, 190, 700, 300, &h00000070)
    s.DrawRect(290, 190, 700, 4, &hFFFFFFC0)
    Draw_center(s, lv.name, 220, &hFFFFFFFF, app.mid)
    Draw_center(s, lv.difficulty, 285, &hFFE14DFF, app.small)
    best = app.best(app.sel)
    s.DrawRect(390, 360, 500, 24, &hFFFFFF40)
    s.DrawRect(394, 364, Int(492 * best / 100), 16, &h7CFF6BFF)
    Draw_center(s, "Best " + best.ToStr() + "%", 400, &hFFFFFFFF, app.small)
    s.DrawText("<", 240, 300, &hFFFFFFFF, app.big)
    s.DrawText(">", 1010, 300, &hFFFFFFFF, app.big)

    ' a cube hopping along the ground
    t = app.frame mod 50
    h = 0.36 * t - 0.014 * t * t
    if h < 0 then h = 0
    f = Int(t * 7.0 / 5) mod app.cube.Count()
    if h = 0 then f = 0
    s.DrawObject(595, 600 - Int(h * 60) - 75, app.cube[f])

    Draw_center(s, "OK: play     Left / Right: level     Back: exit", 530, &hFFFFFFB0, app.small)
    Draw_center(s, "In a level: OK, Play or Up jumps. Hold to keep jumping, or to fly the ship up.", 650, &hFFFFFFB0, app.small)
end sub
