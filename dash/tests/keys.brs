' Remote handling in main.brs, run with dash/tools/shot.py (which runs main.brs headless):
'   python3 dash/tools/shot.py dash/tests/keys.brs      -> prints ok / FAIL lines
' A tap of OK or an arrow is one jump; holding either keeps bouncing; letting go stops it.

sub Scenario(app as object)
    app.spiral = false
    for each k in [6, 2, 3, 4, 5]
        Keys_check(app, k, 2, 1, 1, "tap of key " + k.ToStr() + ": one jump")
        Keys_check(app, k, 150, 3, 99, "holding key " + k.ToStr() + ": keeps bouncing")
    end for
end sub

' Press key k for `hold` frames, release, run on; the jumps counted must be in [lo, hi] and the
' button must not stay held.
sub Keys_check(app as object, k as integer, hold as integer, lo as integer, hi as integer, what as string)
    app.start(0)
    app.run.st = Keys_flat()
    Frames(app, 50)
    jumps = 0
    wasUp = false
    app.key(k)
    for i = 1 to hold + 200
        if i = hold then app.key(100 + k)
        Frames(app, 1)
        up = app.run.y > 0.5
        if up and not wasUp then jumps = jumps + 1
        wasUp = up
    end for
    ok = jumps >= lo and jumps <= hi and not app.jumpDown and app.arrows.Count() = 0
    if ok then print "ok   " + what else print "FAIL " + what + " (" + jumps.ToStr() + " jumps)"
end sub

' An empty side to bounce on.
function Keys_flat() as object
    rows = ""
    for i = 1 to 10
        rows = rows + String(400, ".") + Chr(10)
    end for
    st = Level_parse("name=t" + Chr(10) + "---: jump" + Chr(10) + rows).stages[0]
    return st
end function
