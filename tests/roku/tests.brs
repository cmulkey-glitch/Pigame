' Runs the ROM trace checks against the BrightScript port (roku/source) with the off-device
' brs interpreter. Same traces and comparisons as tests/*.test.mjs.
' Run: node tools/test_roku.mjs

sub Main()
    fails = 0
    fails = fails + TestPhysics()
    fails = fails + TestDrops()
    fails = fails + TestEnemies()
    fails = fails + TestDoors()
    fails = fails + TestSound()
    fails = fails + TestRules()
    if fails = 0 then print "ALL PASS" else print "FAILURES: "; fails
end sub

function LoadJson(path as string) as object
    return ParseJson(ReadAsciiFile("pkg:/" + path))
end function

function Num(n as integer) as string
    return StrI(n).Trim()
end function

function Report(name as string, err as string) as integer
    if err = "" then
        print "ok   "; name
        return 0
    end if
    print "FAIL "; name; ": "; err
    return 1
end function

function MapRoom(map as object) as object
    r = { codes: CreateObject("roArray", 480, false), def: invalid }
    for i = 0 to 479
        r.codes[i] = map[i]
    end for
    r.tileAt = Room_tileAt : r.cellAt = Room_cellAt : r.setCell = Room_setCell
    r.clearTileAt = Room_clearTileAt
    return r
end function

function InputOf(s as string) as object
    return { left: Instr(1, s, "L") > 0, right: Instr(1, s, "R") > 0, up: Instr(1, s, "U") > 0
             down: Instr(1, s, "D") > 0, jump: Instr(1, s, "J") > 0 }
end function

function F1Of(p as object) as integer
    v = 0
    if p.air then v = v or 1
    if p.regen then v = v or 4
    if p.jumpLatch then v = v or 8
    if p.dead then v = v or &h10
    if p.running then v = v or &h20
    if p.climbing then v = v or &h40
    if p.air and p.vertical then v = v or 2
    return v
end function

' ---- player physics: tests/traces/*.json with a player start ----
function TestPhysics() as integer
    fails = 0
    names = ["jump_running", "jump_spam", "jump_standing", "ledge_death", "rope", "rope_drop", "walk", "wall_bounce"]
    for each name in names
        t = LoadJson("tests/traces/" + name + ".json")
        s = t.start
        room = MapRoom(s.map)
        p = Player_new()
        p.x = s.x : p.y = s.y : p.facing = s.facing : p.vyHi = s.vyHi : p.vyLo = s.vyLo
        p.air = (s.f1 and 1) <> 0 : p.vertical = (s.f1 and 2) <> 0 : p.regen = (s.f1 and 4) <> 0
        p.jumpLatch = (s.f1 and 8) <> 0 : p.dead = (s.f1 and &h10) <> 0 : p.running = (s.f1 and &h20) <> 0
        p.climbing = (s.f1 and &h40) <> 0 : p.hanging = (s.fa and 1) <> 0
        p.holdCount = s.hold : p.hangSide = s.hangSide : p.midairDeath = s.midair : p.splat = s.splat
        p.lives = s.lives
        err = ""
        i = 0
        for each f in t.frames
            p.update(room, InputOf(f["in"]), f.frame)
            p.events = []
            if (f.f1 and 1) <> 0 then romF1 = f.f1 else romF1 = f.f1 and &hFD
            bad = p.x <> f.x or p.y <> f.y or F1Of(p) <> romF1 or (p.hanging <> ((f.fa and 1) <> 0)) or p.holdCount <> f.hold
            if (f.f1 and 1) <> 0 and (p.vyHi <> f.vyHi or p.vyLo <> f.vyLo) then bad = true
            if bad then
                err = "frame " + Num(i) + ": x " + Num(p.x) + "/" + Num(f.x) + " y " + Num(p.y) + "/" + Num(f.y) + " f1 " + Num(F1Of(p)) + "/" + Num(romF1)
                exit for
            end if
            i = i + 1
        end for
        fails = fails + Report("physics " + name + " (" + Num(t.frames.Count()) + " frames)", err)
    end for
    return fails
end function

' ---- drops: single-step equivalence and hits ----
function TestDrops() as integer
    fails = 0
    rooms = LoadJson("data/rooms.json").rooms
    names = ["drops_c0", "drops_c2_d2", "drops_c6", "drops_c7_d0", "drops_c8"]
    for each name in names
        t = LoadJson("tests/traces/" + name + ".json")
        ri = t.start.room : diff = t.start.difficulty
        room = MapRoom(t.start.map)
        drops = Drops_new(rooms[ri], ri, diff, Rng_new(), false)
        err = ""
        for i = 0 to drops.spawns.Count() - 1
            if drops.spawns[i].x <> t.start.spawns[i][0] or drops.spawns[i].y <> t.start.spawns[i][1] then err = "spawn " + Num(i)
        end for
        if drops.slots.Count() <> t.start.lastSlot + 1 then err = "slot count"
        n = drops.slots.Count()
        if diff = 0 then warn = &h10 else warn = 0
        never = { nextByte: function() as integer
                    return 1
                  end function }
        fr = t.frames
        for k = 0 to fr.Count() - 2
            if err <> "" then exit for
            if fr[k + 1].frame <> fr[k].frame then
                cur = fr[k].drops : nxt = fr[k + 1].drops
                drops.slots = []
                for i = 0 to n - 1
                    drops.slots.Push({ x: cur[i][0], y: cur[i][1], timer: cur[i][2], spawnIdx: cur[i][3] })
                end for
                drops.rng = never
                drops.update(room)
                for i = 0 to n - 1
                    d = drops.slots[i] : w = nxt[i]
                    if cur[i][3] = &hFF and w[3] <> &hFF then
                        sp = drops.spawns[w[3]]
                        if sp.x <> w[0] or sp.y <> w[1] or w[2] < &h38 + warn or w[2] > &h3F + warn then err = "bad spawn at frame " + Num(k + 1)
                    else if d.spawnIdx <> w[3] or (w[3] <> &hFF and (d.x <> w[0] or d.y <> w[1] or d.timer <> w[2])) then
                        err = "frame " + Num(k + 1) + " slot " + Num(i)
                    end if
                end for
                a = fr[k] : b = fr[k + 1]
                if (a.f1 and &h14) = 0 then
                    drops.slots = []
                    for i = 0 to n - 1
                        drops.slots.Push({ x: cur[i][0], y: cur[i][1], timer: cur[i][2], spawnIdx: cur[i][3] })
                    end for
                    hit = drops.hits(a.x, a.y)
                    died = (b.f1 and &h10) <> 0
                    if hit and not died then err = "js hit, ROM lived at frame " + Num(k + 1)
                end if
            end if
        end for
        fails = fails + Report("drops " + name, err)
    end for
    return fails
end function

' ---- ball, bird, timer: frame-exact ----
function TestEnemies() as integer
    fails = 0
    rooms = LoadJson("data/rooms.json").rooms
    names = ["enemies_ball0", "enemies_ball2", "enemies_ball5", "enemies_ball6", "enemies_bird1", "enemies_bird4", "enemies_timer_d0"]
    for each name in names
        t = LoadJson("tests/traces/" + name + ".json")
        def = rooms[t.room] : s0 = t.start
        ball = invalid
        if def.ball <> invalid then
            ball = Ball_new(def.ball, t.room)
            ball.x = s0.ball[0] : ball.y = s0.ball[1] : ball.vy = s0.ball[2]
        end if
        bird = invalid
        if s0.bird then
            bird = Bird_new()
            bird.x = s0.birdPos[0] : bird.y = s0.birdPos[1] : bird.dirn = s0.birdPos[2]
        end if
        timer = s0.timer
        prev = s0
        err = ""
        i = 0
        for each f in t.frames
            if f.frame <> prev.frame then
                tick = f.frame and 3
                if ball <> invalid and (tick and 1) <> 0 then ball.update(f.frame)
                if bird <> invalid then
                    birdHit = ((prev.f1 and &h10) = 0) and bird.hits(f.x, f.y)
                    if not birdHit then bird.update()
                end if
                splatEnded = ((prev.f1 and &h10) <> 0) and ((f.f1 and &h10) = 0)
                regen = ((f.f1 and 4) <> 0) and not splatEnded
                if not regen and bird = invalid and (t.difficulty <> 0 or (f.frame and 1) = 0) then
                    timer = timer - 1
                    if timer < 0 then timer = 0
                    if timer = 0 then bird = Bird_new()
                end if
                if splatEnded then
                    bird = invalid
                    if timer = 0 then timer = 2048
                end if
                if ball <> invalid and (ball.x <> f.ball[0] or ball.y <> f.ball[1] or ball.vy <> f.ball[2]) then err = "ball at frame " + Num(i)
                if (bird <> invalid) <> f.bird then
                    err = "bird presence at frame " + Num(i)
                else if bird <> invalid then
                    if bird.x <> f.birdPos[0] or bird.y <> f.birdPos[1] or bird.dirn <> f.birdPos[2] then err = "bird at frame " + Num(i)
                end if
                if timer <> f.timer then err = "timer at frame " + Num(i) + ": " + Num(timer) + "/" + Num(f.timer)
                if err <> "" then exit for
            end if
            prev = f
            i = i + 1
        end for
        fails = fails + Report("enemies " + name, err)
    end for
    return fails
end function

' ---- object placement and a key pickup ----
function TestDoors() as integer
    data = LoadJson("data/rooms.json")
    tr = LoadJson("tests/traces/objects.json")
    err = ""
    state = NewGameState(data.rooms, data.doorOpenInitial)
    for r = 0 to data.rooms.Count() - 1
        room = Room_new(data.rooms[r])
        room.placeObjects(state)
        for i = 0 to 479
            if room.codes[i] <> tr.rooms[r][i] then err = "chamber " + Num(r) + " cell " + Num(i)
        end for
    end for
    fails = Report("doors: objects in all 11 chambers", err)
    s = NewGameState(data.rooms, data.doorOpenInitial)
    room = Room_new(data.rooms[0])
    room.placeObjects(s)
    p = Player_new()
    p.reset({ x: &h2A, y: &h2D, facing: 2 }, false)
    p.air = true : p.vertical = true : p.vyHi = &hFF
    idle = { left: false, right: false, up: false, down: false, jump: false }
    ev = invalid
    for f = 0 to 7
        p.update(room, idle, f)
        for each e in p.events
            if e.kind = "pickup" then ev = e
        end for
        if ev <> invalid then exit for
    end for
    err = ""
    if ev = invalid then
        err = "no pickup"
    else
        Collect(s, room, ev, Rng_new())
        for i = 0 to 479
            if room.codes[i] <> tr.keyPickup.after[i] then err = "cell " + Num(i)
        end for
        for i = 0 to 35
            if s.doorOpen[i] <> tr.keyPickup.doorOpen[i] then err = "door " + Num(i)
        end for
    end if
    return fails + Report("doors: key opens its door", err)
end function

' ---- sound driver vs TIA registers ----
function TestSound() as integer
    sounds = LoadJson("data/sounds.json").sounds
    ev = LoadJson("tests/traces/sound.json").events
    drv = SoundDriver_new(sounds)
    started = false : frame = 0 : err = ""
    for each e in ev
        k = e[0]
        if k = "play" then
            drv.play(e[1], e[2]) : started = true
        else if k = "stop" then
            drv.stopAll() : started = true
        else if k = "tick" then
            drv.update()
        else if k = "regs" then
            r = e[1]
            if not started then
                drv.regs = [{ f: r[0], c: r[2], v: r[4] }, { f: r[1], c: r[3], v: r[5] }]
            else
                g = drv.regs
                if g[0].f <> r[0] or g[1].f <> r[1] or g[0].c <> r[2] or g[1].c <> r[3] or g[0].v <> r[4] or g[1].v <> r[5] then
                    if err = "" then err = "frame " + Num(frame)
                end if
            end if
            frame = frame + 1
        end if
    end for
    return Report("sound driver (" + Num(frame) + " frames)", err)
end function

' ---- chamber 0 / chamber X door rules ----
function TestRules() as integer
    fails = 0
    data = LoadJson("data/rooms.json")
    snd = LoadJson("data/sounds.json")
    cases = LoadJson("tests/traces/rules.json")
    g = Game_new({ rooms: data.rooms, title: data.title, doorOpenInitial: data.doorOpenInitial, sounds: snd.sounds })
    for each c in cases
        g.difficulty = c.difficultyBefore
        g.escapeMode = c.escape
        g.startGame()
        g.difficulty = c.difficultyBefore
        g.state.treasure[0] = 0
        for i = 0 to g.state.doorOpen.Count() - 1
            g.state.doorOpen[i] = 1
        end for
        g.enterRoom(c["from"], { x: &h40, y: &h1F, facing: 2 }, false)
        g.prevRoom = c.prevRoom : g.prevTimer = c.prevTimer : g.timer = c.timerBefore
        doorY = 0
        for each d in g.room.def.doors
            if d.at.side = "right" then doorY = d.at.y
        end for
        g.player.reset({ x: &h8D, y: doorY, facing: 2 }, false)
        g.goThroughDoor("right")
        err = ""
        if c.ending then
            if g.mode <> "escaped" then err = "expected the ending"
        else
            if g.roomIndex <> c.room or g.player.x <> c.x or g.player.y <> c.y or g.player.facing <> c.facing then err = "arrival"
            if g.difficulty <> c.difficulty then err = "difficulty"
            if g.timer <> c.timer then err = "timer " + Num(g.timer) + "/" + Num(c.timer)
            if (g.state.treasure[0] <> 0) <> c.itemsReset then err = "items reset"
        end if
        fails = fails + Report("rules " + c.name, err)
    end for
    return fails
end function
