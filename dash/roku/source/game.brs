' Spiral Shift game logic: level parsing and the 60 Hz physics step. No Roku objects in here,
' so dash/tests/tests.brs runs it in the brs interpreter.
'
' A level is four stages run around the edges of the screen: along the bottom, up the right
' side, along the top, down the left side. Each stage is a strip in its own frame, where the
' player always runs toward +x and gravity pulls toward y = 0 (the screen edge); main.brs
' rotates the strip onto its side of the screen. The end of each stage is a checkpoint.
'
' Units are blocks. The player is a 1 x 1 box with its bottom-left corner at (x, y). A cell
' (c, row) covers [c, c+1] x [row, row+1]. Every stage is 10 rows high: the edge is y = 0
' and the inner ceiling is y = 10.
'
' Each stage has its own shape and mechanic (Stage_modes):
'   ball      jump: press to jump, hold to keep jumping as you land
'   triangle  fly: hold to rise, release to fall
'   square    flip: press while on a surface to flip gravity between edge and ceiling
'   diamond   wave: hold to move diagonally inward, release to move diagonally back
'
' Cells:
'   #  block: land on it (ball / square), crash into its sides; the diamond crashes on any touch
'   ^  spike on the edge side of the cell      v  spike on the ceiling side of the cell
'   _  jump pad (ball): launches high          o  orb (ball): press while touching to jump again

function Dash_phys() as object
    return {
        speed: 10.4 / 60    ' blocks per frame (about 10 blocks a second)
        g: 0.028            ' gravity: a jump rises ~2.1 blocks and lasts ~26 frames
        jump: 0.36
        pad: 0.457          ' ~3.5 blocks
        orb: 0.36
        maxFall: 0.5
        spin: 7.0           ' degrees per frame in the air: half a turn per jump
        flyAcc: 0.018       ' triangle: holding accelerates inward, releasing outward
        flyMax: 0.2
        flipKick: 0.1       ' square: starting speed toward the new floor after a flip
        wave: 10.4 / 60     ' diamond: 45 degrees
        snap: 0.25          ' how far into a block top (or underside) still counts as landing
        buffer: 10          ' a press counts for this many frames (orbs, landing); TVs lag
    }
end function

function Stage_modes() as object
    return ["jump", "fly", "flip", "wave"]
end function

' Level text: "key=value" header lines, then four stages, each a "---" line followed by its
' rows, top (ceiling side) first; the last row of a stage sits on the edge. "." is empty.
function Level_parse(text as string) as object
    lv = { name: "Level", difficulty: "", bg: &h2A3CFFFF, ground: &h1C2BB8FF, line: &hFFFFFFFF
           music: "", width: 0, stages: [], phys: Dash_phys() }
    lines = text.Split(Chr(10))
    groups = []
    rows = invalid
    for i = 0 to lines.Count() - 1
        s = lines[i]
        if Right(s, 1) = Chr(13) then s = Left(s, Len(s) - 1)
        if Left(s, 3) = "---" then
            rows = []
            groups.Push(rows)
        else if rows <> invalid then
            if s <> "" then rows.Push(s)
        else
            eq = Instr(1, s, "=")
            if eq > 1 then
                k = Left(s, eq - 1)
                v = Mid(s, eq + 1)
                if k = "name" then lv.name = v
                if k = "difficulty" then lv.difficulty = v
                if k = "music" then lv.music = v
                if k = "bg" then lv.bg = Hex_color(v)
                if k = "ground" then lv.ground = Hex_color(v)
                if k = "line" then lv.line = Hex_color(v)
            end if
        end if
    end for
    modes = Stage_modes()
    for g = 0 to groups.Count() - 1
        st = Strip_parse(groups[g])
        st.mode = modes[g mod 4]
        st.start = lv.width
        lv.width = lv.width + st.width
        lv.stages.Push(st)
    end for
    return lv
end function

function Strip_parse(rows as object) as object
    st = { h: 10, width: 0, cols: [] }
    for i = 0 to rows.Count() - 1
        if Len(rows[i]) > st.width then st.width = Len(rows[i])
    end for
    for c = 0 to st.width - 1
        st.cols.Push([])
    end for
    n = rows.Count()
    for i = 0 to n - 1
        s = rows[i]
        row = n - 1 - i
        for c = 0 to Len(s) - 1
            k = Mid(s, c + 1, 1)
            if k <> "." and k <> " " then st.cols[c].Push({ k: k, r: row, id: c.ToStr() + "_" + row.ToStr() })
        end for
    end for
    return st
end function

function Hex_color(s as string) as integer
    digits = "0123456789ABCDEF"
    s = UCase(s)
    if Left(s, 1) = "#" then s = Mid(s, 2)
    v = 0
    for i = 1 to Len(s)
        v = v * 16 + Instr(1, digits, Mid(s, i, 1)) - 1
    end for
    ' RRGGBBFF as a signed 32-bit integer, without overflowing on the way there
    if v >= &h800000 then v = v - &h1000000
    return v * 256 + 255
end function

function Run_new(lv as object) as object
    r = { lv: lv, held: false, events: [] }
    Run_enter(r, 0)
    return r
end function

' Start (or restart, after a crash) stage s at its beginning.
sub Run_enter(r as object, s as integer)
    r.stage = s
    r.st = r.lv.stages[s]
    r.mode = r.st.mode
    r.x = 0.0
    r.y = 0.0
    r.vy = 0.0
    r.grav = 1          ' square: 1 pulls toward the edge, -1 toward the ceiling
    r.grounded = true
    r.buffer = 0
    r.angle = 0.0
    r.dead = false
    r.won = false
    r.orbs = {}
end sub

function Run_clone(r as object) as object
    t = {}
    for each k in r
        t[k] = r[k]
    end for
    t.orbs = {}
    for each k in r.orbs
        t.orbs[k] = true
    end for
    t.events = []
    return t
end function

function Run_progress(r as object) as float
    x = r.x
    if x > r.st.width then x = r.st.width
    return (r.st.start + x) / r.lv.width
end function

' One frame. held: the button is down this frame (a tap shorter than a frame still counts as
' held for one frame). Appends "jump", "orb", "pad", "flip", "die", "checkpoint", "win" to
' r.events.
sub Run_step(r as object, held as boolean)
    if r.dead or r.won then return
    p = r.lv.phys
    st = r.st
    mode = r.mode
    if held and not r.held then r.buffer = p.buffer
    r.held = held

    if mode = "jump" then
        if r.grounded and (held or r.buffer > 0) then
            r.vy = p.jump
            r.grounded = false
            r.buffer = 0
            r.events.Push("jump")
        end if
        r.vy = r.vy - p.g
        if r.vy < -p.maxFall then r.vy = -p.maxFall
    else if mode = "fly" then
        if held then r.vy = r.vy + p.flyAcc else r.vy = r.vy - p.flyAcc
        if r.vy > p.flyMax then r.vy = p.flyMax
        if r.vy < -p.flyMax then r.vy = -p.flyMax
    else if mode = "flip" then
        if r.grounded and r.buffer > 0 then
            r.grav = -r.grav
            r.vy = -r.grav * p.flipKick
            r.grounded = false
            r.buffer = 0
            r.events.Push("flip")
        end if
        r.vy = r.vy - p.g * r.grav
        if r.vy < -p.maxFall then r.vy = -p.maxFall
        if r.vy > p.maxFall then r.vy = p.maxFall
    else
        if held then r.vy = p.wave else r.vy = -p.wave
    end if

    prevY = r.y
    r.x = r.x + p.speed
    r.y = r.y + r.vy
    r.grounded = false
    if r.y <= 0 then
        r.y = 0
        if r.vy < 0 then r.vy = 0
        if r.grav = 1 then r.grounded = true
    end if
    top = st.h - 1
    if mode <> "jump" and r.y >= top then
        r.y = top
        if r.vy > 0 then r.vy = 0
        if r.grav = -1 then r.grounded = true
    end if

    c0 = Int(r.x) - 1
    c1 = Int(r.x) + 2
    if c0 < 0 then c0 = 0
    if c1 > st.width - 1 then c1 = st.width - 1

    ' pass 1: land on blocks (onto tops while falling toward the edge, onto undersides while
    ' falling toward the ceiling); the triangle is stopped by undersides instead of crashing
    if mode <> "wave" then
        down = (r.grav = 1)
        up = (mode = "fly" or r.grav = -1)
        for c = c0 to c1
            col = st.cols[c]
            for i = 0 to col.Count() - 1
                o = col[i]
                if o.k = "#" and Box_hit(r.x, r.y, r.x + 1, r.y + 1, c, o.r, c + 1, o.r + 1) then
                    if down and r.vy <= 0 and prevY >= o.r + 1 - p.snap then
                        r.y = o.r + 1
                        r.vy = 0
                        r.grounded = true
                    else if up and r.vy >= 0 and prevY + 1 <= o.r + p.snap then
                        r.y = o.r - 1
                        r.vy = 0
                        if r.grav = -1 then r.grounded = true
                    end if
                end if
            end for
        end for
    end if

    ' pass 2: crashes, pads, orbs. The crash box is smaller than the player (grazing a corner
    ' is fine); the diamond's is smaller still since it touches nothing safely.
    inset = 0.2
    if mode = "wave" then inset = 0.3
    for c = c0 to c1
        col = st.cols[c]
        for i = 0 to col.Count() - 1
            o = col[i]
            k = o.k
            if k = "#" then
                if Box_hit(r.x + inset, r.y + inset, r.x + 1 - inset, r.y + 1 - inset, c, o.r, c + 1, o.r + 1) then r.dead = true
            else if k = "^" then
                if mode = "wave" then
                    if Box_hit(r.x + inset, r.y + inset, r.x + 1 - inset, r.y + 1 - inset, c + 0.4, o.r, c + 0.6, o.r + 0.45) then r.dead = true
                else if Box_hit(r.x + 0.1, r.y, r.x + 0.9, r.y + 0.9, c + 0.4, o.r, c + 0.6, o.r + 0.45) then
                    r.dead = true
                end if
            else if k = "v" then
                if mode = "wave" then
                    if Box_hit(r.x + inset, r.y + inset, r.x + 1 - inset, r.y + 1 - inset, c + 0.4, o.r + 0.55, c + 0.6, o.r + 1) then r.dead = true
                else if Box_hit(r.x + 0.1, r.y + 0.1, r.x + 0.9, r.y + 1, c + 0.4, o.r + 0.55, c + 0.6, o.r + 1) then
                    r.dead = true
                end if
            else if k = "_" then
                if mode = "jump" and r.vy < p.pad and Box_hit(r.x, r.y, r.x + 1, r.y + 1, c + 0.1, o.r, c + 0.9, o.r + 0.3) then
                    r.vy = p.pad
                    r.grounded = false
                    r.events.Push("pad")
                end if
            else if k = "o" then
                if mode = "jump" and (held or r.buffer > 0) and not r.orbs.DoesExist(o.id) and Box_hit(r.x, r.y, r.x + 1, r.y + 1, c - 0.1, o.r - 0.1, c + 1.1, o.r + 1.1) then
                    r.orbs[o.id] = true
                    r.vy = p.orb
                    r.grounded = false
                    r.buffer = 0
                    r.events.Push("orb")
                end if
            end if
        end for
    end for

    if mode = "jump" or mode = "flip" then
        if r.grounded then
            r.angle = Int((r.angle + 45) / 90) * 90.0
        else
            r.angle = r.angle + p.spin * r.grav
        end if
        if r.angle >= 360 then r.angle = r.angle - 360
        if r.angle < 0 then r.angle = r.angle + 360
    else if mode = "fly" then
        r.angle = r.vy * 200    ' nose inward while climbing
    else
        r.angle = 0
        if r.vy > 0 then r.angle = 45
        if r.vy < 0 then r.angle = -45
    end if

    if r.buffer > 0 then r.buffer = r.buffer - 1
    if r.dead then
        r.events.Push("die")
    else if r.x >= st.width then
        if r.stage < r.lv.stages.Count() - 1 then
            ' how the player left the stage, for main.brs's corner animation
            r.exit = { stage: r.stage, x: r.x, y: r.y, mode: r.mode, angle: r.angle }
            Run_enter(r, r.stage + 1)
            r.events.Push("checkpoint")
        else
            r.won = true
            r.events.Push("win")
        end if
    end if
end sub

function Box_hit(ax0 as float, ay0 as float, ax1 as float, ay1 as float, bx0 as float, by0 as float, bx1 as float, by1 as float) as boolean
    return ax0 < bx1 and ax1 > bx0 and ay0 < by1 and ay1 > by0
end function
