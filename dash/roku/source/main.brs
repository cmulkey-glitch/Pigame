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
' and the player runs into the screen corner, where the corner animation (Trans_*) builds a
' rocket around it that flies up the next side, turning it into the next shape on the way.
'
' Two clocks: ticks at 60 a second drive menus, particles and animations; game steps
' (Run_step) run at 60 a second too, or slower in Kids mode (KIDS_SPEED), which slows the whole
' game down without changing any path through it. Frames are drawn between game steps.
'
' The spiral: the levels after the one being played lie inward of it, one ring (Ring_rows) per
' level, drawn full size beyond its inner ceiling (Draw_rings). Spiral mode plays the levels
' in a row; at the end of each the view slides inward to the next (Zoom_*), which waits for OK.
'
' Remote: OK, Play or Up is the button (jump / zig-zag; see game.brs); the arrows steer the
' triangle and switch the square's side (App_steer); * or Back
' pauses (Resume / Quit). Menu: Up / Down pick a row (level, speed, spiral run), Left / Right
' change it, OK starts, Back exits.

function Levels_count() as integer
    return 10
end function

function Kids_speed() as float
    return 0.65
end function

' args: launch parameters (deep links); the game has no content to link to, so it opens the menu.
sub Main(args as dynamic)
    port = CreateObject("roMessagePort")
    screen = CreateObject("roScreen", true, 1280, 720)
    screen.SetMessagePort(port)
    screen.SetAlphaEnable(true)

    app = App_new(screen)
    Deep_link(app, args)
    Memory_watch(port)
    ' deep links while running (supports_input_launch in the manifest): accepted, nothing to open
    input = CreateObject("roInput")
    if input <> invalid then input.SetMessagePort(port)
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
            else if type(msg) = "roAppMemoryMonitorEvent" then
                App_low_memory(app)
            else if type(msg) = "roInputEvent" then
                if msg.IsInput() then Deep_link(app, msg.GetInfo())
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

' A deep link (at launch, or while running): contentId "level<N>" opens that level's menu
' entry; anything else just shows the menu.
sub Deep_link(app as object, info as dynamic)
    if info = invalid or type(info) <> "roAssociativeArray" then return
    contentId = info.contentId
    mediaType = info.mediaType
    if contentId = invalid or mediaType = invalid then return
    if Left(contentId, 5) = "level" then
        n = Mid(contentId, 6).ToInt()
        if n >= 1 and n <= app.levels.Count() and app.mode = "menu" then app.sel = n - 1
    end if
end sub

' Roku asks apps to watch their memory. Ask to be told when it runs low (App_low_memory frees
' what can be rebuilt). Guarded: older firmware lacks some of these calls.
sub Memory_watch(port as object)
    try
        mon = CreateObject("roAppMemoryMonitor")
        if mon = invalid then return
        mon.SetMessagePort(port)
        mon.EnableMemoryWarningEvent(true)
        mon.EnableLowGeneralMemoryEvent(true)
        print "memory: limit"; mon.GetChannelMemoryLimit(); " KB, available"; mon.GetChannelAvailableMemory(); " KB, used"; mon.GetMemoryLimitPercent(); "%"
    catch e
        print "memory monitor unavailable: "; e.message
    end try
end sub

' Low on memory: drop the spiral transition's snapshots (Zoom_start makes them again).
sub App_low_memory(app as object)
    if app.mode <> "zoom" then
        app.snap = invalid
        app.snapNext = invalid
    end if
end sub

function App_new(screen as object) as object
    fonts = CreateObject("roFontRegistry")
    app = {
        screen: screen, screenMain: screen, mode: "menu", sel: 0, levels: [], run: invalid, lv: invalid, kids: false
        attempts: 0, deadTicks: 0, pause: 0, banner: "", frame: 0, parts: [], trans: invalid
        spiral: false, zoom: invalid, menuRow: 0, spiralNew: false, pauseSel: 0, resumeMode: ""
        snap: invalid, snapNext: invalid, arrows: {}, arrowTaps: {}
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
        start: App_start, begin: App_begin, respawn: App_respawn, quit: App_quit
        best: App_best, setBest: App_setBest, spiralSaved: App_spiralSaved, saveSpiral: App_saveSpiral
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
    for each name in ["ball", "triangle", "square", "diamond"]
        app.sheets[name] = Sheet(CreateObject("roBitmap", "pkg:/images/" + name + ".png"), 72)
    end for
    ' rocket parts for the corner animation, one per side (fins: one side's row, then the other)
    app.sheets.nose = Sheet(CreateObject("roBitmap", "pkg:/images/nose.png"), 48)
    app.sheets.fin = Sheet(CreateObject("roBitmap", "pkg:/images/fin.png"), 48)

    ' the spiral transition's snapshots: the last frame of a level and the first of the next
    app.snap = CreateObject("roBitmap", { width: 1280, height: 720, AlphaEnable: true })
    app.snapNext = CreateObject("roBitmap", { width: 1280, height: 720, AlphaEnable: true })
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
    if mode = "fly" then return { name: "TRIANGLE", sheet: "triangle", color: &hFF6AD5FF, hint: "Left / Right to steer" }
    if mode = "flip" then return { name: "SQUARE", sheet: "square", color: &h4DD6FFFF, hint: "Up / Down to switch sides" }
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

' Spiral run progress (the level to continue from), kept per speed.
function App_spiralSaved() as integer
    k = "spiral"
    if m.kids then k = "kspiral"
    if m.reg.Exists(k) then return m.reg.Read(k).ToInt()
    return 0
end function

sub App_saveSpiral(i as integer)
    k = "spiral"
    if m.kids then k = "kspiral"
    if i <= 0 then
        m.reg.Delete(k)
    else
        m.reg.Write(k, i.ToStr())
    end if
    m.reg.Flush()
end sub

' Returns false to quit the channel.
function App_key(code as integer) as boolean
    isJump = (code = 6 or code = 13 or code = 2)
    if code >= 100 then
        c = code - 100
        if c = 6 or c = 13 or c = 2 then m.jumpDown = false
        m.arrows.Delete(c.ToStr())
        return true
    end if
    if code >= 2 and code <= 5 then
        m.arrows[code.ToStr()] = true
        m.arrowTaps[code.ToStr()] = true
    end if
    if m.mode = "menu" then
        if code = 0 then return false
        n = m.levels.Count()
        if code = 2 then m.menuRow = (m.menuRow + 2) mod 3
        if code = 3 then m.menuRow = (m.menuRow + 1) mod 3
        if (code = 4 or code = 5) and m.menuRow = 0 then
            if code = 4 then m.sel = (m.sel + n - 1) mod n else m.sel = (m.sel + 1) mod n
        end if
        if (code = 4 or code = 5 or code = 6 or code = 13) and m.menuRow = 1 then
            m.kids = not m.kids
            v = "0"
            if m.kids then v = "1"
            m.reg.Write("kids", v)
            m.reg.Flush()
        end if
        if (code = 4 or code = 5) and m.menuRow = 2 then m.spiralNew = not m.spiralNew
        if code = 6 or code = 13 then
            if m.menuRow = 0 then
                m.spiral = false
                m.start(m.sel)
            else if m.menuRow = 2 then
                m.spiral = true
                from = m.spiralSaved()
                if m.spiralNew then from = 0
                m.attempts = 1
                m.begin(from)
            end if
        end if
    else if m.mode = "play" or m.mode = "ready" then
        if code = 0 or code = 10 then
            ' Back or *: pause
            m.resumeMode = m.mode
            m.mode = "paused"
            m.pauseSel = 0
            m.music.Pause()
        else if m.mode = "ready" then
            if code = 6 or code = 13 then
                m.mode = "play"
                m.pause = 20
                m.banner = "STAGE 1"
                m.music.Stop()
                m.music.SetContentList([{ url: "pkg:/sounds/" + m.lv.music + ".mp3" }])
                m.music.Play()
            end if
        else if isJump then
            ' every press counts, even if its release has not arrived yet or came in the same
            ' frame (a quick second tap for an orb)
            m.jumpDown = true
            m.tapped = true
        end if
    else if m.mode = "paused" then
        if code = 2 or code = 3 then m.pauseSel = 1 - m.pauseSel
        if code = 0 or code = 10 or ((code = 6 or code = 13) and m.pauseSel = 0) then
            m.mode = m.resumeMode
            m.jumpDown = false
            m.tapped = false
            if m.mode = "play" then m.music.Resume()
        else if (code = 6 or code = 13) and m.pauseSel = 1 then
            m.quit()
        end if
    else if m.mode = "complete" then
        if code = 0 or code = 6 or code = 13 then m.mode = "menu"
    end if
    return true
end function

' Leave a level for the menu; a spiral run remembers the level it was on.
sub App_quit()
    m.music.Stop()
    if m.spiral then m.saveSpiral(m.sel)
    m.mode = "menu"
end sub

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

' Spiral mode: set up level i at its start and wait for OK ("ready").
sub App_begin(i as integer)
    m.lv = m.levels[i]
    m.sel = i
    m.saveSpiral(i)
    m.run = Run_new(m.lv)
    m.prev = invalid
    m.parts = []
    m.trans = invalid
    m.zoom = invalid
    m.deadTicks = 0
    m.tapped = false
    m.pause = 0
    m.banner = ""
    m.music.Stop()
    m.mode = "ready"
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
    if m.mode = "zoom" then
        Zoom_tick(m)
        return
    end if
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
    Run_step(r, held, App_steer(m, r))
    m.arrowTaps = {}

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
            m.setBest(m.sel, 100)
            if m.spiral and m.sel < m.levels.Count() - 1 then
                m.sfxCheck.Trigger(90)
                Zoom_start(m)
            else
                m.music.Stop()
                m.sfxWin.Trigger(90)
                if m.spiral then m.saveSpiral(0)
                m.mode = "complete"
            end if
        end if
    end for
    r.events = []
end sub

' The triangle's and square's steer from the arrows: the arrow pointing inward on its side
' (away from the edge) is 1, the one pointing back at the edge -1. A tap shorter than a game
' step still counts for one step.
function App_steer(app as object, r as object) as integer
    if r.mode <> "fly" and r.mode <> "flip" then return 0
    inward = ["2", "4", "3", "5"]       ' Up, Left, Down, Right
    outward = ["3", "5", "2", "4"]
    a = inward[r.stage]
    b = outward[r.stage]
    goIn = app.arrows.DoesExist(a) or app.arrowTaps.DoesExist(a)
    goOut = app.arrows.DoesExist(b) or app.arrowTaps.DoesExist(b)
    if goIn and not goOut then return 1
    if goOut and not goIn then return -1
    return 0
end function

sub Spark(app as object, x as float, y as float, vx as float, vy as float, size as integer, color as integer, life as integer)
    app.parts.Push({ x: x, y: y, vx: vx, vy: vy, size: size, color: color, life: life, drag: 0.96 })
end sub

' ---- the corner animation ----
' The old shape rolls into the corner and becomes the body of a rocket: nose cone and fins fly
' in and lock on, it ignites and flies up the new side, the body turns into the new shape on
' the way (shrink, white flash, grow), and at the start the rocket parts blow off.
' Tick at which each phase ends:
function Trans_phases() as object
    return { corner: 16, build: 34, ignite: 44, convert: 62, fly: 80, eject: 94 }
end function

sub Trans_tick(app as object)
    t = app.trans
    ph = Trans_phases()
    t.t = t.t + 1
    if t.t = ph.corner then
        app.banner = Shape_info(t.exit.mode).name + "  >>  " + Shape_info(app.run.mode).name
    else if t.t = ph.build then
        ' the parts lock on
        c = Trans_corner(app)
        for i = 1 to 12
            a = i * 6.283 / 12
            Spark(app, c.x, c.y, Cos(a) * 5, Sin(a) * 5, 5, &hFFFFFFFF, 14)
        end for
    else if t.t = ph.ignite then
        app.sfxRocket.Trigger(80)
    else if t.t = ph.convert then
        ' the body changes: white flash ring
        p = Trans_rocket_pos(app)
        color = Shape_info(app.run.mode).color
        for i = 1 to 20
            a = i * 6.283 / 20
            Spark(app, p.x, p.y, Cos(a) * 8, Sin(a) * 8, 7, &hFFFFFFFF, 16)
            Spark(app, p.x, p.y, Cos(a) * 4, Sin(a) * 4, 6, color, 22)
        end for
    else if t.t >= ph.eject then
        app.trans = invalid
        app.banner = Shape_info(app.run.mode).name
        app.pause = 30          ' a moment to see the new shape before it moves
        app.prev = invalid
        return
    end if
    ' flame out of the back of the rocket while it burns
    if t.t > ph.build and t.t < ph.fly then
        p = Trans_rocket_pos(app)
        d = Run_dir(app.run.stage)
        flame = [&hFFE14DFF, &hFF8A2BFF, &hFF4D4DFF]
        n = 1
        if t.t > ph.ignite then n = 3
        for i = 1 to n
            Spark(app, p.x - d.x * 40 + (Rnd(0) - 0.5) * 12, p.y - d.y * 40 + (Rnd(0) - 0.5) * 12, -d.x * (2 + Rnd(0) * 5) + (Rnd(0) - 0.5) * 2, -d.y * (2 + Rnd(0) * 5) + (Rnd(0) - 0.5) * 2, 5 + Rnd(7), flame[Rnd(3) - 1], 18)
        end for
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

' The rocket's center: in the corner (shaking while it ignites), then flying to the start.
function Trans_rocket_pos(app as object) as object
    ph = Trans_phases()
    t = app.trans.t
    c = Trans_corner(app)
    s = Player_center(app.run, 0, 0)
    if t <= ph.ignite then
        if t > ph.build then return { x: c.x + (Rnd(0) - 0.5) * 4, y: c.y + (Rnd(0) - 0.5) * 4 }
        return c
    end if
    f = (t - ph.ignite) / (ph.fly - ph.ignite)
    f = f * f * (3 - 2 * f)
    return { x: c.x + (s.x - c.x) * f, y: c.y + (s.y - c.y) * f }
end function

sub Trans_draw(app as object)
    t = app.trans
    e = t.exit
    ph = Trans_phases()
    ns = app.run.stage
    if t.t < ph.ignite then
        ' the old stage, its camera still stopped at the end
        st = app.lv.stages[e.stage]
        Draw_stage(app, e.stage, st, e.mode, Cam_clamp(e.stage, st.width, st.width))
    else
        Draw_stage(app, ns, app.run.st, app.run.mode, Cam_x(app.run, 0))
    end if
    c = Trans_corner(app)
    if t.t < ph.corner then
        ' roll into the corner
        st = app.lv.stages[e.stage]
        ex = View_rect(e.stage, e.x, e.y, 1, 1, Cam_clamp(e.stage, st.width, st.width))
        f = Ease(t.t / ph.corner)
        Draw_shape(app, e.mode, e.stage, e.angle + t.t * 20, ex.x + 24 + (c.x - ex.x - 24) * f, ex.y + 24 + (c.y - ex.y - 24) * f, 1.0)
        return
    end if
    p = Trans_rocket_pos(app)
    ' the body: the old shape, then (around ph.convert) the new one
    if t.t < ph.convert - 6 then
        Draw_shape(app, e.mode, e.stage, e.angle, p.x, p.y, 1.0)
    else if t.t < ph.convert then
        k = (ph.convert - t.t) / 6.0
        Draw_shape(app, e.mode, e.stage, e.angle + (6 - (ph.convert - t.t)) * 30, p.x, p.y, k)
    else if t.t < ph.convert + 6 then
        k = (t.t - ph.convert) / 6.0
        Draw_shape(app, app.run.mode, ns, (ph.convert + 6 - t.t) * 30, p.x, p.y, k)
    else if t.t < ph.fly then
        Draw_shape(app, app.run.mode, ns, 0, p.x, p.y, 1.0)
    else
        ' landed: the new shape pops as the parts blow away
        f = (t.t - ph.fly) / (ph.eject - ph.fly)
        Draw_shape(app, app.run.mode, ns, 0, p.x, p.y, 1.0 + 0.25 * Sin(f * 3.14))
    end if
    ' the rocket parts: flying in, locked on, then blown off
    if t.t < ph.build then
        out = 1 - Ease((t.t - ph.corner) / (ph.build - ph.corner))
        Draw_parts(app, ns, p.x, p.y, out * 150, 1.0)
    else if t.t < ph.fly then
        Draw_parts(app, ns, p.x, p.y, 0, 1.0)
    else
        f = (t.t - ph.fly) / (ph.eject - ph.fly)
        Draw_parts(app, ns, p.x, p.y, f * 120, 1 - f)
    end if
end sub

' Nose cone ahead of the body and a fin either side behind it, pushed `out` px away from
' their places, scaled by k. The parts face stage s's run direction.
sub Draw_parts(app as object, s as integer, cx as float, cy as float, out as float, k as float)
    if k <= 0.05 then return
    d = Run_dir(s)
    n = { x: d.y, y: -d.x }      ' a quarter turn from the run direction
    parts = [
        { img: app.sheets.nose[s], x: d.x * (30 + out), y: d.y * (30 + out) }
        { img: app.sheets.fin[s], x: -d.x * (20 + out * 0.4) + n.x * (22 + out), y: -d.y * (20 + out * 0.4) + n.y * (22 + out) }
        { img: app.sheets.fin[4 + s], x: -d.x * (20 + out * 0.4) - n.x * (22 + out), y: -d.y * (20 + out * 0.4) - n.y * (22 + out) }
    ]
    for each q in parts
        x = cx + q.x
        y = cy + q.y
        app.screen.DrawScaledObject(Int(x - 24 * k), Int(y - 24 * k), k, k, q.img)
    end for
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
    if m.mode = "zoom" then
        Zoom_draw(m)
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
    if m.mode = "ready" or (m.mode = "paused" and m.resumeMode = "ready") then
        Draw_center_at(m.screen, "Level " + (m.sel + 1).ToStr() + ":  " + m.lv.name, 640, 100, &hFFFFFFFF, m.big)
        Draw_center_at(m.screen, "Press OK to start", 640, 180, &hFFE14DFF, m.mid)
    end if
    if m.mode = "paused" then Draw_pause(m)
end sub

sub Draw_pause(app as object)
    s = app.screen
    s.DrawRect(0, 0, 1280, 720, &h000000A0)
    Draw_center_at(s, "PAUSED", 640, 220, &hFFFFFFFF, app.big)
    items = ["Resume", "Quit to menu"]
    if app.spiral then items[1] = "Quit (the spiral run is saved)"
    for i = 0 to 1
        color = &hFFFFFF80
        if i = app.pauseSel then color = &hFFE14DFF
        Draw_center_at(s, items[i], 640, 340 + i * 70, color, app.mid)
    end for
    Draw_center_at(s, "Up / Down, OK.   * or Back: resume", 640, 520, &hFFFFFFB0, app.small)
end sub

' Background, edges and the stage's cells for a camera at camX.
sub Draw_stage(app as object, sg as integer, st as object, mode as string, camX as float)
    s = app.screen
    lv = app.lv
    s.Clear(lv.bg)
    Draw_backdrop(s, sg, camX)
    Draw_rings(app, app.sel, sg, camX)
    Draw_edges(s, lv, sg, camX)
    c0 = Int(camX) - 1
    if c0 < 0 then c0 = 0
    c1 = Int(camX + Run_len(sg) / 48) + 1
    if c1 > st.width - 1 then c1 = st.width - 1
    for c = c0 to c1
        col = st.cols[c]
        for i = 0 to col.Count() - 1
            Draw_cell(app, s, lv, sg, c, col[i], camX)
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

sub Draw_cell(app as object, s as object, lv as object, sg as integer, c as integer, o as object, camX as float, yoff = 0 as integer)
    b = View_rect(sg, c, o.r + yoff, 1, 1, camX)
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
end sub

' ---- the spiral ----
' The levels after this one lie inward of it, like the turns of a spiral: beyond the inner
' ceiling of the stage in play comes the same side of the next level, full size and scrolling
' with the run, then the one after that, as far as the screen reaches.

function Ring_rows() as integer
    return 11       ' a stage is 10 rows; the next ring's edge band is the 11th
end function

' How much shorter each ring inward is at each end of the screen, in blocks. (A true spiral
' would need 11 per ring, which leaves nothing on a 16:9 screen; 3 reads as one.)
function Ring_inset() as integer
    return 3
end function

' The levels after level idx on side sg, for a camera at camX, shaded so the stage in play
' stands out. Each ring is shorter than the one outside it by Ring_inset() at both ends, where
' its band turns inward: the corners of the spiral. Its course scrolls with the run.
sub Draw_rings(app as object, idx as integer, sg as integer, camX as float)
    s = app.screen
    span = Run_len(sg) / 48.0
    for k = 1 to 2
        j = idx + k
        if j >= app.levels.Count() then exit for
        lv = app.levels[j]
        st = lv.stages[sg]
        base = Ring_rows() * k
        ' along the run, this ring covers [x0, x1] (local, for this camera)
        x0 = camX + 1 + Ring_inset() * k
        x1 = camX + span - 1 - Ring_inset() * k
        if x1 <= x0 then exit for
        deep = Ring_rows() * 2
        b = View_rect(sg, x0, base - 1, x1 - x0, deep, camX)
        s.DrawRect(b.x, b.y, b.w, b.h, lv.bg)
        e = View_rect(sg, x0 - 1, base - 1, x1 - x0 + 2, 1, camX)
        s.DrawRect(e.x, e.y, e.w, e.h, lv.ground)
        ' the corners: the band turns inward at both ends
        for each cx in [x0 - 1, x1]
            t = View_rect(sg, cx, base - 1, 1, deep, camX)
            s.DrawRect(t.x, t.y, t.w, t.h, lv.ground)
        end for
        cam = camX - base
        c0 = Int(x0 - base)
        if c0 < 0 then c0 = 0
        c1 = Int(x1 - base) - 1
        if c1 > st.width - 1 then c1 = st.width - 1
        for c = c0 to c1
            if c + base >= x0 then
                col = st.cols[c]
                for i = 0 to col.Count() - 1
                    Draw_cell(app, s, lv, sg, c, col[i], cam, base)
                end for
            end if
        end for
    end for
    sh = View_rect(sg, camX - 2, 10, span + 4, Ring_rows() * 2 + 2, camX)
    s.DrawRect(sh.x, sh.y, sh.w, sh.h, &h00000070)
end sub

' Spiral mode, end of a level: the shape becomes a rocket in the corner, and the view slides
' inward (down the screen) to the next level, which the rocket flies to. Tick at which each
' phase ends:
function Zoom_phases() as object
    return { build: 20, slide: 80, pop: 92 }
end function

' Snapshot the last frame of this level and the first of the next.
sub Zoom_start(app as object)
    if app.snap = invalid then app.snap = CreateObject("roBitmap", { width: 1280, height: 720, AlphaEnable: true })
    if app.snapNext = invalid then app.snapNext = CreateObject("roBitmap", { width: 1280, height: 720, AlphaEnable: true })
    r = app.run
    e = r.exit
    st = app.lv.stages[e.stage]
    app.screen = app.snap
    Draw_stage(app, e.stage, st, e.mode, Cam_clamp(e.stage, st.width, st.width))
    lv = app.lv
    sel = app.sel
    app.sel = sel + 1
    app.lv = app.levels[app.sel]
    nxt = app.lv.stages[0]
    app.screen = app.snapNext
    Draw_stage(app, 0, nxt, nxt.mode, Cam_clamp(0, nxt.width, 0))
    app.lv = lv
    app.sel = sel
    app.screen = app.screenMain
    app.zoom = { t: 0, from: sel, exit: e }
    app.mode = "zoom"
    app.banner = ""
end sub

' The rocket's corner on the old frame and the start on the new one, at slide f (0..1).
function Zoom_points(app as object, f as float) as object
    e = app.zoom.exit
    st = app.levels[app.zoom.from].stages[e.stage]
    b = View_rect(e.stage, st.width, 0, 1, 1, Cam_clamp(e.stage, st.width, st.width))
    nxt = app.levels[app.zoom.from + 1].stages[0]
    n = View_rect(0, 0, 0, 1, 1, Cam_clamp(0, nxt.width, 0))
    return { corner: { x: b.x + 24, y: b.y + 24 + 720 * f }, start: { x: n.x + 24, y: n.y + 24 - 720 * (1 - f) } }
end function

function Zoom_f(app as object) as float
    ph = Zoom_phases()
    return Ease((app.zoom.t - ph.build) / (ph.slide - ph.build))
end function

function Zoom_rocket(app as object) as object
    f = Zoom_f(app)
    pts = Zoom_points(app, f)
    return { x: pts.corner.x + (pts.start.x - pts.corner.x) * f, y: pts.corner.y + (pts.start.y - pts.corner.y) * f }
end function

sub Zoom_tick(app as object)
    z = app.zoom
    ph = Zoom_phases()
    z.t = z.t + 1
    alive = []
    for each p in app.parts
        p.x = p.x + p.vx
        p.y = p.y + p.vy
        p.life = p.life - 1
        if p.life > 0 then alive.Push(p)
    end for
    app.parts = alive
    if z.t = ph.build then
        app.sfxRocket.Trigger(80)
        app.banner = "LEVEL " + (z.from + 2).ToStr()
    end if
    if z.t > ph.build and z.t < ph.slide then
        p = Zoom_rocket(app)
        flame = [&hFFE14DFF, &hFF8A2BFF, &hFF4D4DFF]
        for i = 1 to 3
            Spark(app, p.x + (Rnd(0) - 0.5) * 12, p.y + 40 + (Rnd(0) - 0.5) * 12, (Rnd(0) - 0.5) * 2, 2 + Rnd(0) * 5, 5 + Rnd(7), flame[Rnd(3) - 1], 18)
        end for
    end if
    if z.t >= ph.pop then app.begin(z.from + 1)
end sub

sub Zoom_draw(app as object)
    s = app.screen
    z = app.zoom
    ph = Zoom_phases()
    f = Zoom_f(app)
    s.Clear(&h000000FF)
    s.DrawObject(0, Int(720 * f), app.snap)
    s.DrawObject(0, Int(-720 * (1 - f)), app.snapNext)
    e = z.exit
    if z.t < ph.build then
        ' the shape becomes the rocket's body as the parts fly in
        c = Zoom_points(app, 0).corner
        Draw_shape(app, e.mode, e.stage, e.angle, c.x, c.y, 1.0)
        Draw_parts(app, 1, c.x, c.y, (1 - Ease(z.t / ph.build)) * 150, 1.0)
    else if z.t < ph.slide then
        p = Zoom_rocket(app)
        if f < 0.5 then
            Draw_shape(app, e.mode, e.stage, e.angle, p.x, p.y, 1.0)
        else
            Draw_shape(app, "jump", 0, 0, p.x, p.y, 1.0)
        end if
        Draw_parts(app, 1, p.x, p.y, 0, 1.0)
    else
        p = Zoom_points(app, 1).start
        k = (z.t - ph.slide) / (ph.pop - ph.slide)
        Draw_shape(app, "jump", 0, 0, p.x, p.y, 1.0 + 0.25 * Sin(k * 3.14))
        Draw_parts(app, 1, p.x, p.y, k * 120, 1 - k)
    end if
    for each q in app.parts
        s.DrawRect(Int(q.x), Int(q.y), q.size, q.size, q.color)
    end for
    if app.banner <> "" then Draw_center_at(s, app.banner, 640, 120, &hFFFFFFFF, app.big)
end sub

' The four edge bands; the active one is lit and its marks scroll with the run.
sub Draw_edges(s as object, lv as object, sg as integer, camX as float)
    ' (not the band opposite: the inner rings of the spiral are drawn there)
    bands = [[0, 672, 1280, 48], [1232, 0, 48, 720], [0, 0, 1280, 48], [0, 0, 48, 720]]
    for i = 0 to 3
        if i <> (sg + 2) mod 4 then
            b = bands[i]
            s.DrawRect(b[0], b[1], b[2], b[3], lv.ground)
            if i <> sg then s.DrawRect(b[0], b[1], b[2], b[3], &h00000070)
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
    s.DrawRect(cx - 300, cy - 14, 600, 110, &h00000070)
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
    if app.spiral then line = "Spiral: level " + (app.sel + 1).ToStr() + "/" + app.levels.Count().ToStr() + "   " + line
    if app.kids then line = line + "   (Kids mode)"
    Draw_center_at(s, line, cx, cy + 64, &hFFFFFF90, app.small)
    if app.banner <> "" then Draw_center_at(s, app.banner, cx, cy - 80, info.color, app.big)

    if app.mode = "complete" then
        s.DrawRect(0, 0, 1280, 720, &h00000090)
        title = "LEVEL COMPLETE!"
        if app.spiral then title = "SPIRAL COMPLETE!"
        Draw_center_at(s, title, 640, 230, &hFFE14DFF, app.big)
        Draw_center_at(s, app.lv.name, 640, 330, &hFFFFFFFF, app.mid)
        Draw_center_at(s, "Attempts: " + app.attempts.ToStr(), 640, 400, &hFFFFFFFF, app.mid)
        Draw_center_at(s, "Press OK", 640, 520, &hFFFFFFB0, app.small)
    end if
end sub

sub Draw_center_at(s as object, text as string, cx as integer, y as integer, color as integer, font as object)
    w = font.GetOneLineWidth(text, 1280)
    s.DrawText(text, Int(cx - w / 2), y, color, font)
end sub

' The menu: the selected level's first side as it starts, the levels after it inward (up the
' screen); three rows over it: level, speed, spiral run.
sub Draw_menu(app as object)
    s = app.screen
    lv = app.levels[app.sel]
    app.lv = lv
    st = lv.stages[0]
    camX = Cam_clamp(0, st.width, 0)
    Draw_stage(app, 0, st, st.mode, camX)
    p = View_rect(0, 0, 0, 1, 1, camX)
    Draw_shape(app, st.mode, 0, 0, p.x + 24, p.y + 24, 1.0)
    s.DrawRect(0, 40, 1280, 110, &h00000080)
    Draw_center_at(s, "SPIRAL SHIFT", 640, 58, &hFFFFFFFF, app.big)

    s.DrawRect(200, 226, 880, 190, &h000000B0)
    best = app.best(app.sel)
    Menu_row(app, 0, "<   Level " + (app.sel + 1).ToStr() + ":  " + lv.name + "  (" + lv.difficulty + ")   best " + best.ToStr() + "%   >", 240)
    speed = "Speed:   NORMAL   /   kids"
    if app.kids then speed = "Speed:   normal   /   KIDS (slower)"
    Menu_row(app, 1, speed, 280)
    saved = app.spiralSaved()
    row3 = "Spiral run:   all levels in a row, from level 1"
    if saved > 0 then
        if app.spiralNew then
            row3 = "Spiral run:   continue from level " + (saved + 1).ToStr() + "   /   NEW RUN"
        else
            row3 = "Spiral run:   CONTINUE FROM LEVEL " + (saved + 1).ToStr() + "   /   new run"
        end if
    end if
    Menu_row(app, 2, row3, 320)
    Draw_center_at(s, "Up / Down: choose    Left / Right: change    OK: start    Back: exit", 640, 372, &hFFFFFF90, app.small)
end sub

sub Menu_row(app as object, row as integer, text as string, y as integer)
    color = &hFFFFFF90
    if row = app.menuRow then
        color = &hFFE14DFF
        app.screen.DrawRect(220, y + 4, 8, 24, &hFFE14DFF)
    end if
    Draw_center_at(app.screen, text, 640, y, color, app.small)
end sub
