' Spiral Shift for Roku: screen, remote, sound and menus. The game itself (levels, physics) is
' in game.brs.
'
' 1280 x 720, one block = 48 px. The screen has a 48 px edge band on every side; stage s runs
' along one of them, its strip turned onto that side:
'   stage 0  bottom edge, running right      stage 2  top edge, running left
'   stage 1  right edge, running up          stage 3  left edge, running down
' In a strip's own frame the player runs toward +x and y = 0 is the edge (game.brs). View_rect
' maps a box in that frame to the screen. The camera keeps the player a fixed distance from
' the screen edge it runs away from, until the end of the stage comes into view; then it stops
' and the player runs into the screen corner, where the corner animation (Trans_*) turns it
' into a rocket that flies up the next side and becomes the next shape.
'
' Two clocks: ticks at 60 a second drive menus, particles and animations; game steps
' (Run_step) run at 60 a second too, or slower in Kids mode (KIDS_SPEED), which slows the whole
' game down without changing any path through it. Frames are drawn between game steps.
'
' Remote: OK, Play or Up is the button (jump / fly / flip / zig-zag; see game.brs). On the menu
' Left / Right pick a level and Up / Down switch Normal / Kids. Back leaves a level (exits from
' the menu).

function Levels_count() as integer
    return 10
end function

function Kids_speed() as float
    return 0.65
end function

sub Main()
    port = CreateObject("roMessagePort")
    screen = CreateObject("roScreen", true, 1280, 720)
    screen.SetMessagePort(port)
    screen.SetAlphaEnable(true)

    app = App_new(screen)
    clock = CreateObject("roTimespan")
    tickMs = 1000.0 / 60
    acc = 0.0
    gacc = 0.0
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

        dt = clock.TotalMilliseconds()
        clock.Mark()
        if dt > tickMs * 4 then dt = tickMs * 4
        acc = acc + dt
        while acc >= tickMs
            acc = acc - tickMs
            app.tick()
        end while
        stepMs = tickMs
        if app.kids then stepMs = tickMs / Kids_speed()
        if app.running() then
            gacc = gacc + dt
            while gacc >= stepMs
                gacc = gacc - stepMs
                app.step()
            end while
        else
            gacc = 0
        end if
        app.draw(gacc / stepMs)
        screen.SwapBuffers()
    end while
end sub

function App_new(screen as object) as object
    fonts = CreateObject("roFontRegistry")
    app = {
        screen: screen, mode: "menu", sel: 0, levels: [], run: invalid, lv: invalid, kids: false
        attempts: 0, deadTicks: 0, pause: 0, banner: "", frame: 0, parts: [], trans: invalid
        prev: invalid, roll: 0.0, squash: 0, wasGrounded: true
        jumpDown: false, tapped: false
        reg: CreateObject("roRegistrySection", "spiralshift")
        music: CreateObject("roAudioPlayer")
        sfxDie: CreateObject("roAudioResource", "pkg:/sounds/die.wav")
        sfxWin: CreateObject("roAudioResource", "pkg:/sounds/complete.wav")
        sfxCheck: CreateObject("roAudioResource", "pkg:/sounds/checkpoint.wav")
        sfxRocket: CreateObject("roAudioResource", "pkg:/sounds/rocket.wav")
        big: fonts.GetDefaultFont(64, true, false)
        mid: fonts.GetDefaultFont(40, true, false)
        small: fonts.GetDefaultFont(26, false, false)
        key: App_key, tick: App_tick, step: App_step, running: App_running, draw: App_draw
        start: App_start, respawn: App_respawn, best: App_best, setBest: App_setBest
    }
    for i = 1 to Levels_count()
        app.levels.Push(Level_parse(ReadAsciiFile("pkg:/levels/" + i.ToStr() + ".txt")))
    end for
    app.music.SetLoop(true)
    app.kids = app.reg.Exists("kids") and app.reg.Read("kids") = "1"

    app.img = { orb: CreateObject("roBitmap", "pkg:/images/orb.png") }
    for s = 0 to 3
        for each name in ["spike", "pad"]
            app.img[name + s.ToStr()] = CreateObject("roBitmap", "pkg:/images/" + name + "_" + s.ToStr() + ".png")
        end for
    end for
    app.sheets = {}
    for each name in ["ball", "triangle", "square", "diamond", "rocket"]
        app.sheets[name] = Sheet(CreateObject("roBitmap", "pkg:/images/" + name + ".png"), 72)
    end for
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

' Best % per level, kept separately for Kids mode.
function App_best(i as integer) as integer
    k = "best" + i.ToStr()
    if m.kids then k = "kbest" + i.ToStr()
    if m.reg.Exists(k) then return m.reg.Read(k).ToInt()
    return 0
end function

sub App_setBest(i as integer, pct as integer)
    if pct > m.best(i) then
        k = "best" + i.ToStr()
        if m.kids then k = "kbest" + i.ToStr()
        m.reg.Write(k, pct.ToStr())
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
        if code = 4 then m.sel = (m.sel + n - 1) mod n
        if code = 5 then m.sel = (m.sel + 1) mod n
        if code = 2 or code = 3 then
            m.kids = not m.kids
            v = "0"
            if m.kids then v = "1"
            m.reg.Write("kids", v)
            m.reg.Flush()
        end if
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
    m.prev = invalid
    m.parts = []
    m.trans = invalid
    m.deadTicks = 0
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
    m.prev = invalid
    m.attempts = m.attempts + 1
    m.deadTicks = 0
    m.parts = []
    m.tapped = false
    m.pause = 20
    m.banner = ""
end sub

function App_running() as boolean
    return m.mode = "play" and not m.run.dead and m.trans = invalid and m.pause = 0
end function

' 60 a second, in every mode: animations and timers.
sub App_tick()
    m.frame = m.frame + 1
    if m.mode <> "play" then return
    alive = []
    for each p in m.parts
        p.x = p.x + p.vx
        p.y = p.y + p.vy
        p.vx = p.vx * p.drag
        p.vy = p.vy * p.drag
        p.life = p.life - 1
        if p.life > 0 then alive.Push(p)
    end for
    m.parts = alive
    if m.run.dead then
        m.deadTicks = m.deadTicks + 1
        if m.deadTicks >= 50 then m.respawn()
    else if m.trans <> invalid then
        Trans_tick(m)
    else if m.pause > 0 then
        m.pause = m.pause - 1
        if m.pause = 0 then m.banner = ""
        m.tapped = false
    end if
end sub

' One game step (slower in Kids mode).
sub App_step()
    r = m.run
    m.prev = { x: r.x, y: r.y, stage: r.stage }
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
            c = Player_center(r, r.x, r.y)
            color = Shape_info(r.mode).color
            for i = 1 to 30
                a = Rnd(0) * 6.283
                s = 2 + Rnd(0) * 10
                Spark(m, c.x, c.y, Cos(a) * s, Sin(a) * s, 6 + Rnd(10), color, 60)
            end for
        else if e = "checkpoint" then
            m.sfxCheck.Trigger(90)
            m.trans = { t: 0, exit: r.exit }
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

sub Spark(app as object, x as float, y as float, vx as float, vy as float, size as integer, color as integer, life as integer)
    app.parts.Push({ x: x, y: y, vx: vx, vy: vy, size: size, color: color, life: life, drag: 0.96 })
end sub

' ---- the corner animation ----
' Frames (ticks) of each phase: the old shape rolls into the corner, turns into a rocket,
' the rocket flies up the new side to the start, and pops into the new shape.
function Trans_phases() as object
    return { corner: 18, morph: 28, fly: 62, pop: 72 }
end function

sub Trans_tick(app as object)
    t = app.trans
    ph = Trans_phases()
    t.t = t.t + 1
    if t.t = ph.corner then
        ' burst of sparks as the shape becomes a rocket
        c = Trans_corner(app)
        color = Shape_info(t.exit.mode).color
        for i = 1 to 18
            a = Rnd(0) * 6.283
            Spark(app, c.x, c.y, Cos(a) * 6, Sin(a) * 6, 6, color, 25)
        end for
        app.banner = "CHECKPOINT"
    else if t.t = ph.morph then
        app.sfxRocket.Trigger(80)
    else if t.t > ph.morph and t.t < ph.fly then
        ' flame out of the back of the rocket
        p = Trans_rocket_pos(app)
        d = Run_dir(app.run.stage)
        flame = [&hFFE14DFF, &hFF8A2BFF, &hFF4D4DFF]
        for i = 1 to 2
            Spark(app, p.x - d.x * 30 + (Rnd(0) - 0.5) * 12, p.y - d.y * 30 + (Rnd(0) - 0.5) * 12, -d.x * (2 + Rnd(0) * 4) + (Rnd(0) - 0.5) * 2, -d.y * (2 + Rnd(0) * 4) + (Rnd(0) - 0.5) * 2, 5 + Rnd(6), flame[Rnd(3) - 1], 18)
        end for
    else if t.t = ph.fly then
        c = Player_center(app.run, 0, 0)
        color = Shape_info(app.run.mode).color
        for i = 1 to 16
            a = i * 6.283 / 16
            Spark(app, c.x, c.y, Cos(a) * 7, Sin(a) * 7, 7, color, 20)
        end for
        app.banner = Shape_info(app.run.mode).name
    else if t.t >= ph.pop then
        app.trans = invalid
        app.pause = 30          ' a moment to see the new shape before it moves
        app.prev = invalid
    end if
end sub

' Screen center of the corner cell: the end of the old stage, on its edge.
function Trans_corner(app as object) as object
    e = app.trans.exit
    st = app.lv.stages[e.stage]
    b = View_rect(e.stage, st.width, 0, 1, 1, Cam_clamp(e.stage, st.width, st.width))
    return { x: b.x + 24, y: b.y + 24 }
end function

' Run direction of stage s on screen.
function Run_dir(s as integer) as object
    dirs = [{ x: 1, y: 0 }, { x: 0, y: -1 }, { x: -1, y: 0 }, { x: 0, y: 1 }]
    return dirs[s]
end function

function Ease(f as float) as float
    if f < 0 then return 0.0
    if f > 1 then return 1.0
    return f * f * (3 - 2 * f)
end function

function Trans_rocket_pos(app as object) as object
    ph = Trans_phases()
    c = Trans_corner(app)
    s = Player_center(app.run, 0, 0)
    f = Ease((app.trans.t - ph.morph) / (ph.fly - ph.morph))
    return { x: c.x + (s.x - c.x) * f, y: c.y + (s.y - c.y) * f }
end function

sub Trans_draw(app as object)
    s = app.screen
    t = app.trans
    e = t.exit
    ph = Trans_phases()
    if t.t < ph.morph then
        ' the old stage, its camera still stopped at the end
        st = app.lv.stages[e.stage]
        camX = Cam_clamp(e.stage, st.width, st.width)
        Draw_stage(app, e.stage, st, e.mode, camX)
        ex = View_rect(e.stage, e.x, e.y, 1, 1, camX)
        c = Trans_corner(app)
        if t.t < ph.corner then
            ' roll into the corner
            f = Ease(t.t / ph.corner)
            x = ex.x + 24 + (c.x - ex.x - 24) * f
            y = ex.y + 24 + (c.y - ex.y - 24) * f
            Draw_shape(app, e.mode, e.stage, e.angle + t.t * 20, x, y, 1.0)
        else
            ' shrink the shape while the rocket grows in its place
            f = (t.t - ph.corner) / (ph.morph - ph.corner)
            Draw_shape(app, e.mode, e.stage, e.angle, c.x, c.y, 1 - f)
            Draw_rocket(app, (e.stage + 1) mod 4, c.x, c.y, f)
        end if
    else
        Draw_stage(app, app.run.stage, app.run.st, app.run.mode, Cam_x(app.run, 0))
        if t.t < ph.fly then
            p = Trans_rocket_pos(app)
            Draw_rocket(app, app.run.stage, p.x, p.y, 1.0)
        else
            ' pop into the new shape
            c = Player_center(app.run, 0, 0)
            f = (t.t - ph.fly) / (ph.pop - ph.fly)
            Draw_shape(app, app.run.mode, app.run.stage, 0, c.x, c.y, 0.3 + 0.7 * f + 0.25 * Sin(f * 3.14))
        end if
    end if
end sub

sub Draw_rocket(app as object, s as integer, cx as float, cy as float, k as float)
    if k <= 0.05 then return
    fr = app.sheets.rocket[s]
    app.screen.DrawScaledObject(Int(cx - 36 * k), Int(cy - 36 * k), k, k, fr)
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

' Screen length along stage s's run direction.
function Run_len(s as integer) as integer
    if s = 0 or s = 2 then return 1280
    return 720
end function

' The camera: the player at a fixed distance from the trailing screen edge (300 px across,
' 170 px up and down), until the stage's end reaches the inside of the next edge band; then it
' stops, so the player runs into the corner.
function Cam_clamp(s as integer, width as integer, x as float) as float
    off = 170 / 48.0
    if s = 0 or s = 2 then off = 300 / 48.0
    cam = x - off
    last = width + 1 - (Run_len(s) - 48) / 48.0
    if cam > last then cam = last
    return cam
end function

function Cam_x(r as object, x as float) as float
    return Cam_clamp(r.stage, r.st.width, x)
end function

function Player_center(r as object, x as float, y as float) as object
    b = View_rect(r.stage, x, y, 1, 1, Cam_x(r, x))
    return { x: b.x + 24, y: b.y + 24 }
end function

' alpha: how far the game clock is between its last step and the next (0..1).
sub App_draw(alpha as float)
    if m.mode = "menu" then
        Draw_menu(m)
        return
    end if
    r = m.run
    if m.trans <> invalid then
        Trans_draw(m)
    else
        ' draw between the last two steps, so motion is smooth at any game speed
        x = r.x
        y = r.y
        if m.prev <> invalid and m.prev.stage = r.stage and not r.dead then
            x = m.prev.x + (r.x - m.prev.x) * alpha
            y = m.prev.y + (r.y - m.prev.y) * alpha
        end if
        camX = Cam_x(r, x)
        Draw_stage(m, r.stage, r.st, r.mode, camX)
        if not r.dead then
            c = Player_center(r, x, y)
            if r.mode = "jump" then
                Draw_ball(m, r.stage, c.x, c.y)
            else
                Draw_shape(m, r.mode, r.stage, r.angle, c.x, c.y, 1.0)
            end if
        end if
    end if
    for each p in m.parts
        m.screen.DrawRect(Int(p.x), Int(p.y), p.size, p.size, p.color)
    end for
    Draw_hud(m, r)
end sub

' Background, edges and the stage's cells for a camera at camX.
sub Draw_stage(app as object, sg as integer, st as object, mode as string, camX as float)
    s = app.screen
    lv = app.lv
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
                s.DrawObject(b.x, b.y, app.img["spike" + sg.ToStr()])
            else if k = "v" then
                s.DrawObject(b.x, b.y, app.img["spike" + ((sg + 2) mod 4).ToStr()])
            else if k = "_" then
                s.DrawObject(b.x, b.y, app.img["pad" + sg.ToStr()])
            else if k = "o" then
                pulse = 0
                if Int(app.frame / 8) mod 2 = 0 then pulse = 1
                s.DrawObject(b.x - pulse, b.y - pulse, app.img.orb)
            end if
        end for
    end for
    ' the inner ceiling (the ball has none)
    if mode <> "jump" then
        e = View_rect(sg, camX - 2, 10, Run_len(sg) / 48 + 4, 0.05, camX)
        s.DrawRect(e.x, e.y, e.w, e.h, &hFFFFFF50)
    end if
    ' the checkpoint at the end of the stage
    g = View_rect(sg, st.width + 1, 0, 0.2, 10, camX)
    s.DrawRect(g.x, g.y, g.w, g.h, &h7CFF6BA0)
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

' The ball rolls, and squashes toward the edge when it lands (keeping its edge side down).
sub Draw_ball(app as object, sg as integer, cx as float, cy as float)
    frames = app.sheets.ball
    a = app.roll - 90 * sg
    while a < 0
        a = a + 360
    end while
    f = Int(a / 10 + 0.5) mod 36
    k = 1.0 - app.squash * 0.03
    along = 1.0 + app.squash * 0.025
    dirs = [[0, 1], [1, 0], [0, -1], [-1, 0]]
    dir = dirs[sg]
    cx = cx + 23 * (1 - k) * dir[0]
    cy = cy + 23 * (1 - k) * dir[1]
    sx = along
    sy = k
    if sg = 1 or sg = 3 then
        sx = k
        sy = along
    end if
    app.screen.DrawScaledObject(Int(cx - 36 * sx), Int(cy - 36 * sy), sx, sy, frames[f])
end sub

' Any shape at angle (game.brs's r.angle for its mode), centred, scaled by k.
sub Draw_shape(app as object, mode as string, sg as integer, angle as float, cx as float, cy as float, k as float)
    if k <= 0.05 then return
    frames = app.sheets[Shape_info(mode).sheet]
    if mode = "jump" then
        a = angle - 90 * sg
        while a < 0
            a = a + 360
        end while
        fr = frames[Int(a / 10 + 0.5) mod 36]
    else if mode = "fly" then
        a = angle
        if a > 40 then a = 40
        if a < -40 then a = -40
        fr = frames[sg * 17 + Int((a + 40) / 5 + 0.5)]
    else if mode = "flip" then
        a = angle - Int(angle / 90) * 90
        fr = frames[Int(a / 5 + 0.5) mod 18]
    else
        a = angle
        if a > 45 then a = 45
        if a < -45 then a = -45
        fr = frames[sg * 3 + Int((a + 45) / 45 + 0.5)]
    end if
    if k = 1 then
        app.screen.DrawObject(Int(cx - 36), Int(cy - 36), fr)
    else
        app.screen.DrawScaledObject(Int(cx - 36 * k), Int(cy - 36 * k), k, k, fr)
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
    line = "Attempt " + app.attempts.ToStr()
    if app.kids then line = line + "   (Kids mode)"
    Draw_center_at(s, line, cx, cy + 64, &hFFFFFF90, app.small)
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
    s.DrawRect(290, 170, 700, 350, &h00000070)
    s.DrawRect(290, 170, 700, 4, &hFFFFFFC0)
    Draw_center_at(s, "Level " + (app.sel + 1).ToStr() + ":  " + lv.name, 640, 192, &hFFFFFFFF, app.mid)
    Draw_center_at(s, lv.difficulty, 640, 248, &hFFE14DFF, app.small)
    best = app.best(app.sel)
    s.DrawRect(390, 296, 500, 24, &hFFFFFF40)
    s.DrawRect(394, 300, Int(492 * best / 100), 16, &h7CFF6BFF)
    Draw_center_at(s, "Best " + best.ToStr() + "%", 640, 330, &hFFFFFFFF, app.small)
    s.DrawText("<", 230, 300, &hFFFFFFFF, app.big)
    s.DrawText(">", 1012, 300, &hFFFFFFFF, app.big)

    ' the four shapes, one per side
    names = ["ball", "triangle", "square", "diamond"]
    for i = 0 to 3
        fr = app.sheets[names[i]]
        idx = 0
        if i = 1 then idx = 8
        if i = 3 then idx = 1
        s.DrawObject(415 + i * 120, 372, fr[idx])
    end for

    ' Normal / Kids switch
    normal = &hFFFFFFFF
    kids = &hFFFFFF60
    if app.kids then
        normal = &hFFFFFF60
        kids = &hFFFFFFFF
    end if
    s.DrawText("NORMAL", 470, 462, normal, app.small)
    s.DrawText("KIDS (slower)", 660, 462, kids, app.small)
    ux = 470
    uw = app.small.GetOneLineWidth("NORMAL", 400)
    if app.kids then
        ux = 660
        uw = app.small.GetOneLineWidth("KIDS (slower)", 400)
    end if
    s.DrawRect(ux, 494, uw, 3, &hFFE14DFF)

    Draw_center_at(s, "OK: play     Left / Right: level     Up / Down: Normal or Kids     Back: exit", 640, 560, &hFFFFFFB0, app.small)
    Draw_center_at(s, "One button: OK, Play or Up. Each side of the screen is a new shape.", 640, 610, &hFFFFFFB0, app.small)
end sub
