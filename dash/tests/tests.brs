' Spiral Shift logic tests, run with the brs interpreter by dash/tools/test.mjs.
' Physics checks on tiny stages for each mechanic, then for every level and stage: the stored
' solution (dash/tests/solutions/N.txt, from dash/tools/solve.mjs) must reach the checkpoint,
' and never pressing must crash.

sub Main()
    m.fails = 0
    Test_physics()
    for n = 1 to 10
        Test_level(n)
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

' A one-stage level in the given mode.
function Mini(mode as string, rows as string) as object
    lv = Level_parse("name=test" + Chr(10) + "---" + Chr(10) + rows)
    lv.stages[0].mode = mode
    return lv
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

function Hold(lv as object, n as integer) as object
    r = Run_new(lv)
    for f = 1 to n
        Run_step(r, true)
    end for
    return r
end function

function Empty_rows(n as integer) as string
    s = ""
    for i = 1 to n
        s = s + "........................................................................" + Chr(10)
    end for
    return s
end function

sub Test_physics()
    ' -700818689 is &hD63A5AFF as the device reads it (signed); brs reads big hex literals unsigned
    Check(Hex_color("#D63A5A") = -700818689 and Hex_color("2a48e8") = &h2A48E8FF, "level colours parse")

    ' ball
    flat = Mini("jump", "......................................")
    r = Play(flat, [], 30)
    Check(r.y = 0 and r.grounded and not r.dead, "ball runs along the edge")
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
    spike = Mini("jump", "..........^...................")
    Check(Play(spike, [], 90).dead, "running into a spike crashes")
    Check(not Play(spike, [44], 120).dead, "jumping over a spike survives")
    wall = Mini("jump", "..........#...................")
    Check(Play(wall, [], 90).dead, "running into a block crashes")
    stairs = Mini("jump", "..........##########..........")
    r = Play(stairs, [45], 90)
    Check(not r.dead and r.y = 1 and r.grounded, "lands on a block top (y=" + Str(r.y) + ")")
    pad = Mini("jump", "..........______.......................")
    r = Run_new(pad)
    top = 0.0
    for f = 1 to 80
        Run_step(r, false)
        if r.y > top then top = r.y
    end for
    Check(top > 3.3 and top < 3.8, "pad launches ~3.5 blocks (" + Str(top) + ")")
    orb = Mini("jump", "..........o..........." + Chr(10) + "......................" + Chr(10) + "......................")
    Check(Play(orb, [40, 52], 80).orbs.Count() = 1, "pressing inside an orb uses it")
    Check(Play(orb, [40], 80).orbs.Count() = 0, "an orb needs a press")
    r = Run_new(orb)
    for f = 0 to 79
        Run_step(r, f >= 40)
    end for
    Check(r.orbs.Count() = 1, "holding through an orb uses it")

    ' triangle
    sky = Mini("fly", Empty_rows(10))
    r = Hold(sky, 200)
    Check(r.y = 9 and not r.dead, "triangle climbs to the ceiling and stays")
    r = Play(sky, [], 50)
    Check(r.y = 0 and not r.dead, "triangle sinks to the edge when released")

    ' square
    flip = Mini("flip", Empty_rows(10))
    r = Run_new(flip)
    Run_step(r, true)
    n = 1
    while not r.grounded and n < 100
        Run_step(r, false)
        n = n + 1
    end while
    Check(r.grav = -1 and r.y = 9 and n < 24, "square flips to the ceiling in under 24 frames (" + n.ToStr() + ")")
    r = Hold(flip, 80)
    Check(r.grav = -1 and r.y = 9, "holding flips once, not again on landing")
    floorSpikes = Mini("flip", Empty_rows(9) + "..........^^^^^^^^......................")
    Check(Play(floorSpikes, [], 120).dead, "square on the edge crashes into spikes")
    Check(not Play(floorSpikes, [10], 120).dead, "square on the ceiling passes over them")
    under = Mini("flip", ".........##############################." + Chr(10) + Empty_rows(9))
    r = Play(under, [60], 100)
    Check(not r.dead and r.grav = -1 and r.y = 8, "square lands on a block's underside (y=" + Str(r.y) + ")")

    ' diamond
    wave = Mini("wave", Empty_rows(10))
    r = Run_new(wave)
    for f = 1 to 10
        Run_step(r, true)
    end for
    Check(Abs(r.y - 10 * r.lv.phys.wave) < 0.001 and r.angle = 45, "diamond climbs at 45 degrees")
    r = Hold(wave, 200)
    Check(r.y = 9 and not r.dead, "diamond slides along the ceiling")
    post = Mini("wave", Empty_rows(9) + "..........#.....................")
    Check(Play(post, [], 90).dead, "diamond crashes into a block")
    landing = Mini("wave", Empty_rows(9) + "..........######................")
    Check(Hold(landing, 90).y > 1 and not Hold(landing, 90).dead, "diamond climbing clears a low wall")

    ' checkpoints
    two = Level_parse("name=t" + Chr(10) + "---" + Chr(10) + "......................" + Chr(10) + "---" + Chr(10) + "......................")
    r = Run_new(two)
    events = []
    for f = 1 to 140
        Run_step(r, false)
        events.Append(r.events)
        r.events = []
    end for
    Check(r.stage = 1 and r.mode = "fly" and events.Count() = 1 and events[0] = "checkpoint", "end of a stage is a checkpoint into the next mode")
    Check(r.exit.stage = 0 and r.exit.mode = "jump" and r.exit.x >= 22 and r.exit.y = 0, "the checkpoint records how the stage was left")
    Check(Abs(Run_progress(r) - (22 + r.x) / 44) < 0.001, "progress runs across stages")
    for f = 1 to 140
        Run_step(r, false)
    end for
    Check(r.won and r.exit.stage = 1 and r.exit.mode = "fly", "the last stage ends the level, recording how it was left")
end sub

sub Test_level(n as integer)
    lv = Level_parse(ReadAsciiFile("pkg:/roku/levels/" + n.ToStr() + ".txt"))
    Check(lv.stages.Count() = 4, lv.name + ": 4 stages")
    sols = ReadAsciiFile("pkg:/tests/solutions/" + n.ToStr() + ".txt").Split(Chr(10))
    for s = 0 to lv.stages.Count() - 1
        what = lv.name + " stage " + (s + 1).ToStr() + " (" + lv.stages[s].mode + ")"
        r = Run_new(lv)
        Run_enter(r, s)
        frames = Int(lv.stages[s].width / lv.phys.speed) + 20
        for f = 1 to frames
            Run_step(r, false)
            if r.dead or r.stage <> s or r.won then exit for
        end for
        Check(r.dead, what + ": never pressing crashes")
        Check(Replay(lv, s, sols, s), what + ": stored solution reaches the end")
    end for
end sub

' Replay "STAGE s counts" from the solutions file: alternating release / hold frame counts.
function Replay(lv as object, s as integer, sols as object, line as integer) as boolean
    if line >= sols.Count() then return false
    parts = sols[line].Split(" ")
    if parts.Count() < 3 or parts[0] <> "STAGE" or parts[1] <> s.ToStr() then return false
    r = Run_new(lv)
    Run_enter(r, s)
    held = false
    for i = 2 to parts.Count() - 1
        for f = 1 to parts[i].ToInt()
            Run_step(r, held)
            if r.dead then return false
            if r.won or r.stage <> s then return true
        end for
        held = not held
    end for
    return false
end function
