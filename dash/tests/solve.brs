' Finds a way through each stage of a level with the real game code, for dash/tools/solve.mjs.
' Prints "STAGE <n> <runs>": runs of "value:frames", the value being the button (0 / 1), or
' for the triangle and square the arrows (-1 / 0 / 1). dash/tests/tests.brs replays them.

' Search over hold / release each frame. States are grouped by mode, half-block height band
' and the mechanic's own state (orbs used, pending press, held, grounded, gravity); each
' group keeps only its fastest rising and fastest falling state. That keeps the frontier
' small (under ~100) while keeping every reachable height.
function Solve_stage(lv as object, s as integer) as object
    start = Run_new(lv)
    Run_enter(start, s)
    start.prev = invalid
    start.a = 0
    frames = Int(start.st.width / start.st.phys.speed) + 20
    states = [start]
    for f = 1 to frames
        lo = {}
        hi = {}
        for each p in states
            acts = [0, 1]
            if p.mode = "fly" then acts = [-1, 0, 1]
            if p.mode = "flip" then
                ' the square only ever needs the arrow toward the other side
                acts = [0, 1]
                if p.grav = -1 then acts = [0, -1]
            end if
            for each a in acts
                t = Run_clone(p)
                t.prev = p
                t.a = a
                if p.mode = "fly" or p.mode = "flip" then Run_step(t, false, a) else Run_step(t, a = 1)
                if t.won or t.stage <> s then return Solve_path(t)
                if not t.dead then
                    key = Str(Int(t.y * 2))
                    ' the triangle can hover, so keep each speed, not only the extremes
                    if t.mode = "fly" then key = key + Str(Int(t.vy * 34 + 100))
                    if t.mode = "jump" or t.mode = "flip" then
                        key = key + Str(t.grav) + Str(t.orbs.Count())
                        if t.buffer > 0 then key = key + "b"
                        if t.held then key = key + "h"
                        if t.grounded then key = key + "g"
                        if t.mode = "flip" then key = key + Str(t.steerPrev)
                    end if
                    ' ties (the diamond's speed is constant) go to the lowest / highest
                    if lo[key] = invalid then
                        lo[key] = t
                    else if t.vy < lo[key].vy or (t.vy = lo[key].vy and t.y < lo[key].y) then
                        lo[key] = t
                    end if
                    if hi[key] = invalid then
                        hi[key] = t
                    else if t.vy > hi[key].vy or (t.vy = hi[key].vy and t.y > hi[key].y) then
                        hi[key] = t
                    end if
                end if
            end for
        end for
        nxt = []
        for each k in lo
            nxt.Push(lo[k])
            if hi[k].vy <> lo[k].vy or hi[k].y <> lo[k].y then nxt.Push(hi[k])
        end for
        if nxt.Count() = 0 then
            print "STUCK " + s.ToStr() + " at" + Str(states[0].x)
            return invalid
        end if
        states = nxt
    end for
    return invalid
end function

' Walk back from the winning state to the start: runs of "value:frames".
function Solve_path(t as object) as string
    vals = []
    while t.prev <> invalid
        vals.Push(t.a)
        t = t.prev
    end while
    out = ""
    i = vals.Count() - 1
    while i >= 0
        v = vals[i]
        n = 0
        while i >= 0 and vals[i] = v
            n = n + 1
            i = i - 1
        end while
        if out <> "" then out = out + " "
        out = out + v.ToStr() + ":" + n.ToStr()
    end while
    return out
end function

sub Solve_level(path as string)
    lv = Level_parse(ReadAsciiFile(path))
    for s = 0 to lv.stages.Count() - 1
        sol = Solve_stage(lv, s)
        if sol <> invalid then print "STAGE " + s.ToStr() + " " + sol.ToStr()    ' ToStr: brs cannot concatenate it as returned
    end for
    print "STAGES " + lv.stages.Count().ToStr()
end sub
