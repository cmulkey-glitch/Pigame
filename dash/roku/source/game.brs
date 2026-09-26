' Cube Dash game logic: level parsing and the 60 Hz physics step. No Roku objects in here, so
' dash/tests/tests.brs runs it in the brs interpreter.
'
' Units are blocks. x runs right, y runs up, y = 0 is the ground surface. The player is a
' 1 x 1 box whose bottom-left corner is (x, y). A level cell (c, row) covers
' [c, c+1] x [row, row+1].
'
' Level cells:
'   #  block: land on top, crash into the sides (and the underside in cube mode)
'   ^  spike on the floor of the cell      v  spike hanging from the top of the cell
'   _  jump pad: launches a cube high      o  jump orb: press (or hold) while touching: mid-air jump
'   S  ship portal                         C  cube portal (portals act on the whole column)

function Dash_phys() as object
    return {
        speed: 10.4 / 60    ' blocks per frame (about 10 blocks a second)
        g: 0.028            ' cube gravity: a jump rises ~2.1 blocks and lasts ~26 frames
        jump: 0.36
        pad: 0.457          ' ~3.5 blocks
        orb: 0.36
        maxFall: 0.5
        spin: 7.0           ' degrees per frame in the air: half a turn per jump
        shipAcc: 0.018      ' ship: holding accelerates up, releasing down
        shipMax: 0.2
        snap: 0.25          ' how far into a block top (or ship: underside) still counts as landing
        buffer: 10          ' a press counts for this many frames (orbs, landing); TVs lag
    }
end function

' Level text: "key=value" header lines, a "---" line, then the rows, top row first. The last
' row sits on the ground. "." (or space) is empty.
function Level_parse(text as string) as object
    lv = { name: "Level", difficulty: "", bg: &h2A3CFFFF, ground: &h1C2BB8FF, line: &hFFFFFFFF, music: ""
           h: 10, width: 0, cols: [], phys: Dash_phys() }
    lines = text.Split(Chr(10))
    rows = []
    inRows = false
    for i = 0 to lines.Count() - 1
        s = lines[i]
        if Right(s, 1) = Chr(13) then s = Left(s, Len(s) - 1)
        if inRows then
            rows.Push(s)
        else if s = "---" then
            inRows = true
        else
            eq = Instr(1, s, "=")
            if eq > 1 then
                k = Left(s, eq - 1)
                v = Mid(s, eq + 1)
                if k = "name" then lv.name = v
                if k = "music" then lv.music = v
                if k = "difficulty" then lv.difficulty = v
                if k = "bg" then lv.bg = Hex_color(v)
                if k = "ground" then lv.ground = Hex_color(v)
                if k = "line" then lv.line = Hex_color(v)
            end if
        end if
    end for
    ' drop trailing blank lines
    while rows.Count() > 0 and rows[rows.Count() - 1] = ""
        rows.Pop()
    end while
    for i = 0 to rows.Count() - 1
        if Len(rows[i]) > lv.width then lv.width = Len(rows[i])
    end for
    for c = 0 to lv.width - 1
        lv.cols.Push([])
    end for
    n = rows.Count()
    for i = 0 to n - 1
        s = rows[i]
        row = n - 1 - i
        for c = 0 to Len(s) - 1
            k = Mid(s, c + 1, 1)
            if k <> "." and k <> " " then lv.cols[c].Push({ k: k, r: row, id: c.ToStr() + "_" + row.ToStr() })
        end for
    end for
    return lv
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
    return { lv: lv, x: 0.0, y: 0.0, vy: 0.0, mode: "cube", grounded: true, held: false
             buffer: 0, angle: 0.0, dead: false, won: false, orbs: {}, events: [] }
end function

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
    p = r.x / r.lv.width
    if p > 1 then p = 1
    return p
end function

' One frame. held: the jump button is down this frame (a tap shorter than a frame still
' counts as held for one frame). Appends "jump", "orb", "pad", "portal", "die", "win" to
' r.events.
sub Run_step(r as object, held as boolean)
    if r.dead or r.won then return
    p = r.lv.phys
    if held and not r.held then r.buffer = p.buffer
    r.held = held

    if r.mode = "cube" then
        if r.grounded and (held or r.buffer > 0) then
            r.vy = p.jump
            r.grounded = false
            r.buffer = 0
            r.events.Push("jump")
        end if
        r.vy = r.vy - p.g
        if r.vy < -p.maxFall then r.vy = -p.maxFall
    else
        if held then r.vy = r.vy + p.shipAcc else r.vy = r.vy - p.shipAcc
        if r.vy > p.shipMax then r.vy = p.shipMax
        if r.vy < -p.shipMax then r.vy = -p.shipMax
    end if

    prevY = r.y
    r.x = r.x + p.speed
    r.y = r.y + r.vy
    r.grounded = false
    if r.y <= 0 then
        r.y = 0
        if r.vy < 0 then r.vy = 0
        r.grounded = true
    end if
    top = r.lv.h - 1
    if r.mode = "ship" and r.y >= top then
        r.y = top
        if r.vy > 0 then r.vy = 0
    end if

    c0 = Int(r.x) - 1
    c1 = Int(r.x) + 2
    if c0 < 0 then c0 = 0
    if c1 > r.lv.width - 1 then c1 = r.lv.width - 1

    ' pass 1: land on (or, as a ship, bump under) the blocks the box overlaps
    for c = c0 to c1
        col = r.lv.cols[c]
        for i = 0 to col.Count() - 1
            o = col[i]
            if o.k = "#" and Box_hit(r.x, r.y, r.x + 1, r.y + 1, c, o.r, c + 1, o.r + 1) then
                if r.vy <= 0 and prevY >= o.r + 1 - p.snap then
                    r.y = o.r + 1
                    r.vy = 0
                    r.grounded = true
                else if r.mode = "ship" and r.vy >= 0 and prevY + 1 <= o.r + p.snap then
                    r.y = o.r - 1
                    r.vy = 0
                end if
            end if
        end for
    end for

    ' pass 2: crashes, pads, orbs, portals
    for c = c0 to c1
        col = r.lv.cols[c]
        for i = 0 to col.Count() - 1
            o = col[i]
            k = o.k
            if k = "#" then
                ' the inner box: grazing a corner is fine, running into a wall is not
                if Box_hit(r.x + 0.2, r.y + 0.2, r.x + 0.8, r.y + 0.8, c, o.r, c + 1, o.r + 1) then r.dead = true
            else if k = "^" then
                if Box_hit(r.x + 0.1, r.y, r.x + 0.9, r.y + 0.9, c + 0.4, o.r, c + 0.6, o.r + 0.45) then r.dead = true
            else if k = "v" then
                if Box_hit(r.x + 0.1, r.y + 0.1, r.x + 0.9, r.y + 1, c + 0.4, o.r + 0.55, c + 0.6, o.r + 1) then r.dead = true
            else if k = "_" then
                if r.mode = "cube" and r.vy < p.pad and Box_hit(r.x, r.y, r.x + 1, r.y + 1, c + 0.1, o.r, c + 0.9, o.r + 0.3) then
                    r.vy = p.pad
                    r.grounded = false
                    r.events.Push("pad")
                end if
            else if k = "o" then
                if r.mode = "cube" and (held or r.buffer > 0) and not r.orbs.DoesExist(o.id) and Box_hit(r.x, r.y, r.x + 1, r.y + 1, c - 0.1, o.r - 0.1, c + 1.1, o.r + 1.1) then
                    r.orbs[o.id] = true
                    r.vy = p.orb
                    r.grounded = false
                    r.buffer = 0
                    r.events.Push("orb")
                end if
            else if k = "S" or k = "C" then
                mode = "cube"
                if k = "S" then mode = "ship"
                if r.mode <> mode and r.x + 1 > c + 0.3 and r.x < c + 0.7 then
                    r.mode = mode
                    r.events.Push("portal")
                end if
            end if
        end for
    end for

    if r.mode = "cube" then
        if r.grounded then
            r.angle = Int((r.angle + 45) / 90) * 90.0
        else
            r.angle = r.angle + p.spin
        end if
        if r.angle >= 360 then r.angle = r.angle - 360
    else
        r.angle = r.vy * 200    ' nose up while climbing
    end if

    if r.buffer > 0 then r.buffer = r.buffer - 1
    if r.dead then
        r.events.Push("die")
    else if r.x >= r.lv.width then
        r.won = true
        r.events.Push("win")
    end if
end sub

function Box_hit(ax0 as float, ay0 as float, ax1 as float, ay1 as float, bx0 as float, by0 as float, bx1 as float, by1 as float) as boolean
    return ax0 < bx1 and ax1 > bx0 and ay0 < by1 and ay1 > by0
end function
