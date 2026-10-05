' Spiral Shift for Roku: screen, remote, sound and menus. The game itself (levels, physics) is
' in game.brs.
'
' 1280 x 720, one block = 48 px. The screen has a 48 px edge band on every side; stage s runs
' along one of them, its strip turned onto that side:
'   stage 0  bottom edge, running right      stage 2  top edge, running left
'   stage 1  right edge, running up          stage 3  left edge, running down
' In a strip's own frame the player runs toward +x and y = 0 is the edge (game.brs). View_rect
' maps a box in that frame to the screen. The player is drawn PLAYER_U px from the screen
' edge it is running away from.
'
' Remote: OK, Play or Up is the button (jump / fly / flip / zig-zag; see game.brs). Left / Right
' pick a level on the menu. Back leaves a level (exits from the menu).

function Levels_count() as integer
    return 10
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
        attempts: 0, deadFrames: 0, pause: 0, banner: "", frame: 0, parts: []
        roll: 0.0, squash: 0, wasGrounded: true
        jumpDown: false, tapped: false
        reg: CreateObject("roRegistrySection", "spiralshift")
        music: CreateObject("roAudioPlayer")
        sfxDie: CreateObject("roAudioResource", "pkg:/sounds/die.wav")
        sfxWin: CreateObject("roAudioResource", "pkg:/sounds/complete.wav")
        sfxCheck: CreateObject("roAudioResource", "pkg:/sounds/checkpoint.wav")
        big: fonts.GetDefaultFont(64, true, false)
        mid: fonts.GetDefaultFont(40, true, false)
        small: fonts.GetDefaultFont(26, false, false)
        key: App_key, update: App_update, draw: App_draw, start: App_start, respawn: App_respawn
        best: App_best, setBest: App_setBest
    }
    for i = 1 to Levels_count()
        app.levels.Push(Level_parse(ReadAsciiFile("pkg:/levels/" + i.ToStr() + ".txt")))
    end for
    app.music.SetLoop(true)

    app.img = { orb: CreateObject("roBitmap", "pkg:/images/orb.png") }
    for s = 0 to 3
        for each name in ["spike", "pad"]
            app.img[name + s.ToStr()] = CreateObject("roBitmap", "pkg:/images/" + name + "_" + s.ToStr() + ".png")
        end for
    end for
    app.sheets = {
        ball: Sheet(CreateObject("roBitmap", "pkg:/images/ball.png"), 72)
        triangle: Sheet(CreateObject("roBitmap", "pkg:/images/triangle.png"), 72)
        square: Sheet(CreateObject("roBitmap", "pkg:/images/square.png"), 72)
        diamond: Sheet(CreateObject("roBitmap", "pkg:/images/diamond.png"), 72)
    }
    return app
end function

' A sheet of square frames, left to right then top to bottom -> array of regions.
function Sheet(bmp as object, size as integer) as object
    frames = []
    cols = Int(bmp.GetWidth() / size)
    rows = Int(bmp.GetHeight() / size)
    for j = 0 to rows - 1
        for i = 0 to cols - 1
            frames.Push(CreateObject("roRegion", bmp, i * size, j * size, size, size))
        end for
    end for
    return frames
end function

function Shape_info(mode as string) as object
    if mode = "jump" then return { name: "BALL", sheet: "ball", color: &hFFD23FFF, hint: "press to jump" }
    if mode = "fly" then return { name: "TRIANGLE", sheet: "triangle", color: &hFF6AD5FF, hint: "hold to rise" }
    if mode = "flip" then return { name: "SQUARE", sheet: "square", color: &h4DD6FFFF, hint: "press to flip gravity" }
    return { name: "DIAMOND", sheet: "diamond", color: &h7CFF6BFF, hint: "hold to cut inward" }
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
    m.attempts = 1
    m.run = Run_new(m.lv)
    m.parts = []
    m.deadFrames = 0
    m.tapped = false
    m.pause = 45
    m.banner = "STAGE 1"
    m.music.Stop()
    m.music.SetContentList([{ url: "pkg:/sounds/" + m.lv.music + ".mp3" }])
    m.music.Play()
    m.mode = "play"
end sub

' After a crash: back to the start of the stage (the last checkpoint).
sub App_respawn()
    Run_enter(m.run, m.run.stage)
    m.attempts = m.attempts + 1
    m.deadFrames = 0
    m.parts = []
    m.tapped = false
    m.pause = 20
    m.banner = ""
end sub

sub App_update()
    m.frame = m.frame + 1
    if m.mode <> "play" then return
    r = m.run
    for each p in m.parts
        p.x = p.x + p.vx
        p.y = p.y + p.vy
        p.vx = p.vx * 0.96
        p.vy = p.vy * 0.96
    end for
    if r.dead then
        m.deadFrames = m.deadFrames + 1
        if m.deadFrames >= 50 then m.respawn()
        return
    end if
    if m.pause > 0 then
        m.pause = m.pause - 1
        if m.pause = 0 then m.banner = ""
        m.tapped = false
        return
    end if
    held = m.jumpDown or m.tapped
    if m.tapped then r.held = false     ' a fresh press: make sure Run_step sees the edge
    m.tapped = false
    Run_step(r, held)

    ' the ball rolls along the ground and squashes when it lands
    m.roll = m.roll + 20
    if m.roll >= 360 then m.roll = m.roll - 360
    if r.mode = "jump" and r.grounded and not m.wasGrounded then m.squash = 8
    if m.squash > 0 then m.squash = m.squash - 1
    m.wasGrounded = r.grounded

    for each e in r.events
        if e = "die" then
            m.sfxDie.Trigger(90)
            m.setBest(m.sel, Int(Run_progress(r) * 100))
            c = Player_center(r)
            color = Shape_info(r.mode).color
            for i = 1 to 30
                a = Rnd(0) * 6.283
                s = 2 + Rnd(0) * 10
                m.parts.Push({ x: c.x, y: c.y, vx: Cos(a) * s, vy: Sin(a) * s, size: 6 + Rnd(10), color: color })
            end for
        else if e = "checkpoint" then
            m.sfxCheck.Trigger(90)
            m.pause = 40
            m.banner = "CHECKPOINT"
            m.wasGrounded = true
        else if e = "win" then
            m.music.Stop()
            m.sfxWin.Trigger(90)
            m.setBest(m.sel, 100)
            m.mode = "complete"
        end if
    end for
    r.events = []
end sub

' ---- drawing ----

' Local box [x0, x0+w] x [y0, y0+h] of stage s -> screen rect, for a camera at camX.
function View_rect(s as integer, x0 as float, y0 as float, w as float, h as float, camX as float) as object
    u0 = (x0 - camX) * 48
    u1 = (x0 + w - camX) * 48
    v0 = y0 * 48
    v1 = (y0 + h) * 48
    if s = 0 then return { x: Int(u0), y: Int(672 - v1), w: Int(u1 - u0 + 0.5), h: Int(v1 - v0 + 0.5) }
    if s = 1 then return { x: Int(1232 - v1), y: Int(720 - u1), w: Int(v1 - v0 + 0.5), h: Int(u1 - u0 + 0.5) }
    if s = 2 then return { x: Int(1280 - u1), y: Int(48 + v0), w: Int(u1 - u0 + 0.5), h: Int(v1 - v0 + 0.5) }
    return { x: Int(48 + v0), y: Int(u0), w: Int(v1 - v0 + 0.5), h: Int(u1 - u0 + 0.5) }
end function

' Distance along the run from the trailing screen edge to the player, and the screen length.
function Run_len(s as integer) as integer
    if s = 0 or s = 2 then return 1280
    return 720
end function

function Cam_x(r as object) as float
    if r.stage = 0 or r.stage = 2 then return r.x - 300 / 48.0
    return r.x - 170 / 48.0
end function

function Player_center(r as object) as object
    b = View_rect(r.stage, r.x, r.y, 1, 1, Cam_x(r))
    return { x: b.x + 24, y: b.y + 24 }
end function

sub App_draw()
    if m.mode = "menu" then
        Draw_menu(m)
        return
    end if
    s = m.screen
    r = m.run
    lv = m.lv
    st = r.st
    sg = r.stage
    camX = Cam_x(r)
    s.Clear(lv.bg)
    Draw_backdrop(s, sg, camX)
    Draw_edges(s, lv, sg, camX)

    c0 = Int(camX) - 1
    if c0 < 0 then c0 = 0
    c1 = Int(camX + Run_len(sg) / 48) + 1
    if c1 > st.width - 1 then c1 = st.width - 1
    for c = c0 to c1
        col = st.cols[c]
        for i = 0 to col.Count() - 1
            o = col[i]
            b = View_rect(sg, c, o.r, 1, 1, camX)
            k = o.k
            if k = "#" then
                s.DrawRect(b.x, b.y, 48, 48, lv.line)
                s.DrawRect(b.x + 3, b.y + 3, 42, 42, &h0B0B16FF)
            else if k = "^" then
                s.DrawObject(b.x, b.y, m.img["spike" + sg.ToStr()])
            else if k = "v" then
                s.DrawObject(b.x, b.y, m.img["spike" + ((sg + 2) mod 4).ToStr()])
            else if k = "_" then
                s.DrawObject(b.x, b.y, m.img["pad" + sg.ToStr()])
            else if k = "o" then
                pulse = 0
                if Int(m.frame / 8) mod 2 = 0 then pulse = 1
                s.DrawObject(b.x - pulse, b.y - pulse, m.img.orb)
            end if
        end for
    end for
    ' the inner ceiling (the ball has none)
    if r.mode <> "jump" then
        e = View_rect(sg, camX - 2, 10, Run_len(sg) / 48 + 4, 0.05, camX)
        s.DrawRect(e.x, e.y, e.w, e.h, &hFFFFFF50)
    end if
    ' the checkpoint at the end of the stage
    g = View_rect(sg, st.width - 0.15, 0, 0.3, 10, camX)
    s.DrawRect(g.x, g.y, g.w, g.h, &h7CFF6BA0)

    if not r.dead then Draw_player(m, r, camX)
    for each p in m.parts
        s.DrawRect(Int(p.x), Int(p.y), p.size, p.size, p.color)
    end for
    Draw_hud(m, r)
end sub

' The four edge bands; the active one is lit and its marks scroll with the run.
sub Draw_edges(s as object, lv as object, sg as integer, camX as float)
    bands = [[0, 672, 1280, 48], [1232, 0, 48, 720], [0, 0, 1280, 48], [0, 0, 48, 720]]
    for i = 0 to 3
        b = bands[i]
        s.DrawRect(b[0], b[1], b[2], b[3], lv.ground)
    end for
    for i = 0 to 3
        if i <> sg then
            b = bands[i]
            s.DrawRect(b[0], b[1], b[2], b[3], &h00000070)
        end if
    end for
    k0 = Int(camX / 4) - 1
    k1 = Int((camX + Run_len(sg) / 48) / 4) + 1
    for k = k0 to k1
        t = View_rect(sg, k * 4, -1, 0.08, 1, camX)
        s.DrawRect(t.x, t.y, t.w, t.h, &h00000040)
    end for
    e = View_rect(sg, camX - 2, -0.06, Run_len(sg) / 48 + 4, 0.06, camX)
    s.DrawRect(e.x, e.y, e.w, e.h, lv.line)
end sub

' Big faint squares drifting against the run direction at a quarter of its speed.
sub Draw_backdrop(s as object, sg as integer, camX as float)
    off = Int(camX * 12) mod 480
    if off < 0 then off = off + 480
    dxs = [-1, 0, 1, 0]
    dys = [0, 1, 0, -1]
    dx = dxs[sg] * off
    dy = dys[sg] * off
    for i = -1 to 3
        for j = -1 to 2
            x = i * 480 + 80 + dx
            y = j * 480 + 140 + dy
            s.DrawRect(x, y, 200, 200, &hFFFFFF0E)
            s.DrawRect(x + 250, y + 240, 140, 140, &hFFFFFF0A)
        end for
    end for
end sub

sub Draw_player(app as object, r as object, camX as float)
    s = app.screen
    sg = r.stage
    info = Shape_info(r.mode)
    frames = app.sheets[info.sheet]
    c = Player_center(r)
    if r.mode = "jump" then
        a = app.roll - 90 * sg
        while a < 0
            a = a + 360
        end while
        f = Int(a / 10 + 0.5) mod 36
        ' squash: flatten toward the edge, keeping the ball's edge side on the ground
        k = 1.0 - app.squash * 0.03
        along = 1.0 + app.squash * 0.025
        dirs = [[0, 1], [1, 0], [0, -1], [-1, 0]]
        dir = dirs[sg]
        cx = c.x + 23 * (1 - k) * dir[0]
        cy = c.y + 23 * (1 - k) * dir[1]
        sx = along
        sy = k
        if sg = 1 or sg = 3 then
            sx = k
            sy = along
        end if
        s.DrawScaledObject(Int(cx - 36 * sx), Int(cy - 36 * sy), sx, sy, frames[f])
    else if r.mode = "fly" then
        a = r.angle
        if a > 40 then a = 40
        if a < -40 then a = -40
        s.DrawObject(c.x - 36, c.y - 36, frames[sg * 17 + Int((a + 40) / 5 + 0.5)])
    else if r.mode = "flip" then
        a = r.angle - Int(r.angle / 90) * 90
        s.DrawObject(c.x - 36, c.y - 36, frames[Int(a / 5 + 0.5) mod 18])
    else
        s.DrawObject(c.x - 36, c.y - 36, frames[sg * 3 + Int((r.angle + 45) / 45)])
    end if
end sub

' Progress, stage and attempts in the open middle of the screen, away from the active edge.
sub Draw_hud(app as object, r as object)
    s = app.screen
    centers = [[640, 110], [380, 300], [640, 570], [900, 300]]
    hc = centers[r.stage]
    cx = hc[0]
    cy = hc[1]
    p = Run_progress(r)
    s.DrawRect(cx - 180, cy, 360, 16, &hFFFFFF50)
    ' stage boundaries on the bar
    for i = 1 to 3
        bx = cx - 180 + Int(360 * app.lv.stages[i].start / app.lv.width)
        s.DrawRect(bx, cy - 4, 2, 24, &hFFFFFF90)
    end for
    s.DrawRect(cx - 177, cy + 3, Int(354 * p), 10, &h7CFF6BFF)
    pct = Int(p * 100).ToStr() + "%"
    s.DrawText(pct, cx + 192, cy - 8, &hFFFFFFFF, app.small)
    info = Shape_info(r.mode)
    Draw_center_at(s, "Stage " + (r.stage + 1).ToStr() + "/4  " + info.name + "  -  " + info.hint, cx, cy + 30, &hFFFFFFC0, app.small)
    Draw_center_at(s, "Attempt " + app.attempts.ToStr(), cx, cy + 64, &hFFFFFF90, app.small)
    if app.banner <> "" then Draw_center_at(s, app.banner, cx, cy - 80, info.color, app.big)

    if app.mode = "complete" then
        s.DrawRect(0, 0, 1280, 720, &h00000090)
        Draw_center_at(s, "LEVEL COMPLETE!", 640, 230, &hFFE14DFF, app.big)
        Draw_center_at(s, app.lv.name, 640, 330, &hFFFFFFFF, app.mid)
        Draw_center_at(s, "Attempts: " + app.attempts.ToStr(), 640, 400, &hFFFFFFFF, app.mid)
        Draw_center_at(s, "Press OK", 640, 520, &hFFFFFFB0, app.small)
    end if
end sub

sub Draw_center_at(s as object, text as string, cx as integer, y as integer, color as integer, font as object)
    w = font.GetOneLineWidth(text, 1280)
    s.DrawText(text, Int(cx - w / 2), y, color, font)
end sub

sub Draw_menu(app as object)
    s = app.screen
    lv = app.levels[app.sel]
    s.Clear(lv.bg)
    Draw_backdrop(s, 0, app.frame / 40)
    Draw_edges(s, lv, 0, app.frame / 10)

    Draw_center_at(s, "SPIRAL SHIFT", 640, 70, &hFFFFFFFF, app.big)

    ' level card
    s.DrawRect(290, 180, 700, 330, &h00000070)
    s.DrawRect(290, 180, 700, 4, &hFFFFFFC0)
    Draw_center_at(s, "Level " + (app.sel + 1).ToStr() + ":  " + lv.name, 640, 205, &hFFFFFFFF, app.mid)
    Draw_center_at(s, lv.difficulty, 640, 265, &hFFE14DFF, app.small)
    best = app.best(app.sel)
    s.DrawRect(390, 320, 500, 24, &hFFFFFF40)
    s.DrawRect(394, 324, Int(492 * best / 100), 16, &h7CFF6BFF)
    Draw_center_at(s, "Best " + best.ToStr() + "%", 640, 356, &hFFFFFFFF, app.small)
    s.DrawText("<", 230, 300, &hFFFFFFFF, app.big)
    s.DrawText(">", 1012, 300, &hFFFFFFFF, app.big)

    ' the four shapes, one per side
    names = ["ball", "triangle", "square", "diamond"]
    for i = 0 to 3
        fr = app.sheets[names[i]]
        idx = 0
        if i = 1 then idx = 8
        if i = 3 then idx = 1
        s.DrawObject(415 + i * 120, 410, fr[idx])
    end for

    Draw_center_at(s, "OK: play     Left / Right: level     Back: exit", 640, 545, &hFFFFFFB0, app.small)
    Draw_center_at(s, "One button: OK, Play or Up. Each side of the screen is a new shape.", 640, 600, &hFFFFFFB0, app.small)
end sub
