' Cube Dash logic tests, run with the brs interpreter by dash/tools/test.mjs.
' Physics sanity checks on tiny levels, then every shipped level must be beatable (found by a
' search over hold / release each frame) and must not be beatable by never pressing.

sub Main()
    m.fails = 0
    Test_physics()
    levels = ["1", "2", "3"]
    for each n in levels
        Test_level("pkg:/roku/levels/" + n + ".txt")
    end for
    if m.fails = 0 then print "ALL PASS" else print m.fails.ToStr() + " FAILED"
end sub

sub Check(ok as boolean, what as string)
    if ok then
        print "ok   " + what
    else
        print "FAIL " + what
        m.fails = m.fails + 1
    end if
end sub

function Mini(rows as string) as object
    return Level_parse("name=test" + Chr(10) + "---" + Chr(10) + rows)
end function

' Hold for the frames in `pressAt` (one frame each), release otherwise, for n frames.
function Play(lv as object, pressAt as object, n as integer) as object
    r = Run_new(lv)
    presses = {}
    for each f in pressAt
        presses[f.ToStr()] = true
    end for
    for f = 0 to n - 1
        Run_step(r, presses.DoesExist(f.ToStr()))
    end for
    return r
end function

sub Test_physics()
    ' -700818689 is &hD63A5AFF as the device reads it (signed); brs reads big hex literals unsigned
    Check(Hex_color("#D63A5A") = -700818689 and Hex_color("2a48e8") = &h2A48E8FF, "level colours parse")

    flat = Mini("......................................")
    r = Play(flat, [], 30)
    Check(r.y = 0 and r.grounded and not r.dead, "runs along the ground")

    r = Run_new(flat)
    Run_step(r, true)
    top = 0.0
    air = 1
    while not r.grounded and air < 100
        Run_step(r, false)
        if r.y > top then top = r.y
        air = air + 1
    end while
    Check(top > 2.0 and top < 2.3, "jump peaks at 2.0-2.3 blocks (" + Str(top) + ")")
    Check(air >= 22 and air <= 28, "jump lasts 22-28 frames (" + air.ToStr() + ")")
    Check(r.angle = 180 or r.angle = 0, "cube lands square (" + Str(r.angle) + ")")

    spike = Mini("..........^...................")
    Check(Play(spike, [], 90).dead, "running into a spike dies")
    Check(not Play(spike, [44], 120).dead, "jumping over a spike survives")

    wall = Mini("..........#...................")
    Check(Play(wall, [], 90).dead, "running into a block dies")
    r = Play(wall, [44], 60)
    Check(not r.dead, "jumping onto a block survives")

    stairs = Mini("..........##########..........")
    r = Play(stairs, [45], 90)
    Check(not r.dead and r.y = 1 and r.grounded, "lands on a block top (y=" + Str(r.y) + ")")

    ceiling = Mini(".........######......." + Chr(10) + "......................" + Chr(10) + "......................")
    Check(Play(ceiling, [44], 90).dead, "cube hitting a block's underside dies")

    pad = Mini("..........______......................." + Chr(10))
    r = Run_new(pad)
    top = 0.0
    for f = 1 to 80
        Run_step(r, false)
        if r.y > top then top = r.y
    end for
    Check(top > 3.3 and top < 3.8, "pad launches ~3.5 blocks (" + Str(top) + ")")

    orb = Mini("..........o..........." + Chr(10) + "......................" + Chr(10) + "......................")
    r = Play(orb, [40, 52], 80)
    Check(r.orbs.Count() = 1, "pressing inside an orb uses it")
    r = Play(orb, [40], 80)
    Check(r.orbs.Count() = 0, "an orb needs a press")
    r = Run_new(orb)
    for f = 0 to 79
        Run_step(r, f >= 40)
    end for
    Check(r.orbs.Count() = 1, "holding through an orb uses it")

    ship = Mini("..........S.............................................")
    r = Run_new(ship)
    for f = 1 to 200
        Run_step(r, true)
    end for
    Check(r.mode = "ship" and r.y = ship.h - 1 and not r.dead, "ship climbs to the ceiling and stays")
end sub

sub Test_level(path as string)
    lv = Level_parse(ReadAsciiFile(path))
    Check(lv.width > 50, lv.name + ": loaded (" + lv.width.ToStr() + " columns)")
    frames = Int(lv.width / lv.phys.speed) + 10
    Check(Play(lv, [], frames).dead, lv.name + ": never pressing dies")
    ok = Beatable(lv, frames)
    Check(ok, lv.name + ": beatable")
end sub

' Search over hold / release each frame. States are grouped by mode, half-block height band and
' (cube only) orbs used, pending press, held and grounded; each group keeps only its fastest
' rising and fastest falling state. That keeps the frontier small (under ~100) while keeping
' every height reachable, which a plain fixed-size beam does not (it loses the ship's climbs).
function Beatable(lv as object, frames as integer) as boolean
    states = [Run_new(lv)]
    for f = 1 to frames
        lo = {}
        hi = {}
        for each s in states
            for a = 0 to 1
                t = Run_clone(s)
                Run_step(t, a = 1)
                if t.won then return true
                if not t.dead then
                    key = t.mode + Str(Int(t.y * 2))
                    if t.mode = "cube" then
                        key = key + Str(t.orbs.Count())
                        if t.buffer > 0 then key = key + "b"
                        if t.held then key = key + "h"
                        if t.grounded then key = key + "g"
                    end if
                    if lo[key] = invalid or t.vy < lo[key].vy then lo[key] = t
                    if hi[key] = invalid or t.vy > hi[key].vy then hi[key] = t
                end if
            end for
        end for
        nxt = []
        for each k in lo
            nxt.Push(lo[k])
            if hi[k].vy <> lo[k].vy then nxt.Push(hi[k])
        end for
        if nxt.Count() = 0 then
            print "     no way past column " + Str(states[0].x)
            return false
        end if
        states = nxt
    end for
    return false
end function
