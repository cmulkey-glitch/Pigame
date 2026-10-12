' Every screen of the game, for dash/tools/shot.py: python3 dash/tools/shot.py -> dist/shots/.

sub Scenario(app as object)
    Shot(app, "01-menu")
    app.menuRow = 3
    Shot(app, "02-menu-random")
    app.menuRow = 2

    ' a level in play, one picture per side
    app.spiral = false
    app.start(0)
    for s = 0 to 3
        r = app.run
        Run_enter(r, s)
        r.x = 34.0
        if r.mode = "fly" then r.y = 3.5
        app.pause = 0
        app.banner = ""
        app.prev = invalid
        Frames(app, 1)
        Shot(app, "1" + s.ToStr() + "-play-" + r.mode)
    end for

    ' a crash: run into the first obstacle of the ball's side without pressing
    Run_enter(app.run, 0)
    app.pause = 0
    for i = 1 to 2000
        Frames(app, 1)
        if app.run.dead then exit for
    end for
    Frames(app, 6)
    Shot(app, "20-crash")
    Frames(app, 60)

    ' paused
    app.mode = "play"
    app.key(10)
    Shot(app, "21-paused")
    app.key(10)

    ' a corner: the ball runs into it and the rocket takes it up the right side
    r = app.run
    Run_enter(r, 0)
    r.x = r.st.width - 3.0
    app.pause = 0
    app.banner = ""
    for i = 1 to 200
        Frames(app, 1)
        if app.trans <> invalid then exit for
    end for
    n = 0
    for each t in [14, 30, 56, 76]
        while app.trans <> invalid and app.trans.t < t
            Frames(app, 1)
        end while
        n = n + 1
        Shot(app, "3" + n.ToStr() + "-corner")
    end for
    while app.trans <> invalid
        Frames(app, 1)
    end while
    Frames(app, 2)
    Shot(app, "39-after-corner")

    ' a level complete
    Run_enter(r, 3)
    r.x = r.st.width - 2.0
    app.pause = 0
    app.ticks = 3725
    for i = 1 to 300
        Frames(app, 1)
        if app.mode = "complete" then exit for
    end for
    Shot(app, "40-level-complete")
    app.key(6)

    ' a spiral run: the last layer's end, the finale and the spiral complete
    app.spiral = true
    app.attempts = 3
    app.begin(9, false)
    Frames(app, 50)
    Shot(app, "50-spiral-layer10")
    r = app.run
    Run_enter(r, 3)
    r.x = r.st.width - 2.0
    app.ticks = 36000
    for i = 1 to 400
        Frames(app, 1)
        if app.mode = "finale" then exit for
    end for
    for each t in [30, 90, 125]
        while app.mode = "finale" and app.finale.t < t
            Frames(app, 1)
        end while
        Shot(app, "5" + (t \ 30).ToStr() + "-finale")
    end for
    for i = 1 to 300
        if app.mode = "complete" then exit for
        Frames(app, 1)
    end for
    Shot(app, "59-spiral-complete")
    app.key(6)

    ' a random world: playing layer 1, and complete
    App_world(app, 4242)
    Frames(app, 60)
    Shot(app, "60-world-layer1")
    app.begin(9, true)
    r = app.run
    Run_enter(r, 3)
    r.x = r.st.width - 2.0
    for i = 1 to 900
        Frames(app, 1)
        if app.mode = "complete" then exit for
    end for
    Shot(app, "69-world-complete")
end sub
