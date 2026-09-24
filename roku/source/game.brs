' Game controller: title screen, play, game over and the escape ending (BrightScript version
' of src/game/game.js, minus drawing). main.brs feeds it input and draws its state.
'   input:   AA of booleans left, right, up, down, jump
'   actions: array of strings from the remote: "title", "prev", "next", "difficulty"
'   m.sfx:   queue of { kind: "play", name, pitch, ch } / { kind: "stop" } for main.brs to play

function Game_new(data as object) as object
    g = {
        defs: data.rooms, titleDef: data.title, doorOpenInitial: data.doorOpenInitial
        rng: Rng_new(), frame: 0, difficulty: 1, beginner: false, escapeMode: false
        hiScore: 0, mode: "title", sfx: []
        sound: SoundDriver_new(data.sounds)
        toTitle: Game_toTitle, updateTitle: Game_updateTitle, cycleLevel: Game_cycleLevel
        startGame: Game_startGame, enterRoom: Game_enterRoom, jumpToRoom: Game_jumpToRoom
        startSpawn: Game_startSpawn, update: Game_update, updatePlay: Game_updatePlay
        handle: Game_handle, goThroughDoor: Game_goThroughDoor, endGame: Game_endGame
        playSound: Game_playSound, stopSounds: Game_stopSounds
    }
    g.toTitle()
    return g
end function

sub Game_playSound(name as string, pitch as integer)
    ch = m.sound.play(name, pitch)
    if ch >= 0 then m.sfx.Push({ kind: "play", name: name, pitch: pitch, ch: ch })
end sub

sub Game_stopSounds()
    m.sound.stopAll()
    m.sfx.Push({ kind: "stop" })
end sub

' ---- title screen ($802A) ----
sub Game_toTitle()
    m.mode = "title"
    m.titleGuard = 30
    m.titleRoom = Room_new(m.titleDef)
    m.drops = Drops_new(m.titleDef, -1, m.difficulty, m.rng, false)
    m.stickWasMoved = true
end sub

sub Game_updateTitle(input as object)
    m.frame = (m.frame + 1) and &hFF
    if m.titleGuard > 0 then m.titleGuard = m.titleGuard - 1
    if input.jump and m.titleGuard = 0 then
        m.startGame()
        return
    end if
    ' [$8110] one change per stick movement: left/right difficulty, up/down the mode
    moved = input.left or input.right or input.up or input.down
    if moved and not m.stickWasMoved then
        if not input.left and not input.right then
            m.escapeMode = not m.escapeMode
        else if input.right then
            m.cycleLevel(1)
        else
            m.cycleLevel(-1)
        end if
    end if
    m.stickWasMoved = moved
    m.drops.update(m.titleRoom)
end sub

' BEGINNER, EASY, NORMAL, HARD (wraps). BEGINNER plays by EASY's rules without drops.
sub Game_cycleLevel(stp as integer)
    if m.beginner then level = -1 else level = m.difficulty
    level = ((level + stp + 5) mod 4) - 1
    m.beginner = (level = -1)
    if level < 0 then m.difficulty = 0 else m.difficulty = level
end sub

' ---- play ----
sub Game_startGame()
    m.mode = "play"
    m.player = Player_new()
    if m.difficulty = 0 then m.player.lives = 5 else m.player.lives = 4
    m.score = 0 : m.keys = 0
    m.state = NewGameState(m.defs, m.doorOpenInitial)
    m.timer = 4096
    m.prevRoom = -1 : m.prevTimer = 0
    m.enterRoom(0, { x: &h88, y: &hB7, facing: 1 }, true)
    m.player.jumpLatch = true
end sub

sub Game_enterRoom(index as integer, spawn as object, regenerating as boolean)
    m.stopSounds()                                  ' [$ADF3] chamber load
    m.roomIndex = index
    def = m.defs[index]
    m.room = Room_new(def)
    m.room.placeObjects(m.state)
    m.drops = Drops_new(def, index, m.difficulty, m.rng, m.beginner)
    if def.ball <> invalid then m.ball = Ball_new(def.ball, index) else m.ball = invalid
    m.bird = invalid
    m.player.reset(spawn, regenerating)
end sub

' Playtest chamber select: fresh timer, player at the chamber's start.
sub Game_jumpToRoom(index as integer)
    if index = 10 then m.timer = 9999 else m.timer = 4096
    m.prevRoom = -1
    m.enterRoom(index, m.startSpawn(index), false)
end sub

function Game_startSpawn(index as integer) as object
    if index = 0 then return { x: &h88, y: &hB7, facing: 1 }
    if index = 10 then
        for each d in m.defs[9].doors
            if d["to"] = 0 then return { x: &h0B, y: d.arrive.y, facing: 2 }
        end for
    end if
    for each def in m.defs
        if def.id <> index then
            for each d in def.doors
                if d["to"] = index then return DoorSpawn(d.arrive)
            end for
        end if
    end for
    return { x: &h50, y: &h1F, facing: 2 }
end function

sub Game_update(input as object, actions as object)
    for each a in actions
        if a = "title" and m.mode <> "title" then
            m.toTitle()
            m.sound.update()
            return
        end if
    end for
    if m.mode = "title" then
        m.updateTitle(input)
    else if m.mode = "gameover" then
        m.endTimer = m.endTimer - 1
        if m.endTimer = 0 then m.toTitle()
    else if m.mode = "escaped" then
        if input.jump and not m.escapeGuard then
            m.toTitle()
        else if not input.jump then
            m.escapeGuard = false
        end if
    else
        n = m.defs.Count()
        for each a in actions
            if a = "next" then m.jumpToRoom((m.roomIndex + 1) mod n)
            if a = "prev" then m.jumpToRoom((m.roomIndex + n - 1) mod n)
        end for
        m.updatePlay(input)
    end if
    m.sound.update()                                ' [$F83F] every frame, every mode
end sub

sub Game_updatePlay(input as object)
    ' same order as the ROM's main loop ($83F8)
    m.frame = (m.frame + 1) and &hFF
    pl = m.player : tick = m.frame and 3
    if not pl.regen and not pl.dead then
        if m.drops.hits(pl.x, pl.y) then
            pl.kill()
        else if tick = 2 and m.ball <> invalid then
            if m.ball.hits(pl.x, pl.y) then pl.kill()
        end if
    end if
    pl.update(m.room, input, m.frame)
    m.drops.update(m.room)
    if (tick and 1) <> 0 and m.ball <> invalid then m.ball.update(m.frame)
    if m.bird <> invalid then
        if not pl.dead and m.bird.hits(pl.x, pl.y) then pl.kill() else m.bird.update()
    end if
    respawned = false
    for each ev in pl.events
        if ev.kind = "respawn" then respawned = true
    end for
    if not (pl.regen and not respawned) and m.bird = invalid and (m.difficulty <> 0 or (m.frame and 1) = 0) then
        m.timer = m.timer - 1
        if m.timer < 0 then m.timer = 0
        if m.timer = 0 then m.bird = Bird_new()
    end if
    if pl.running and (m.frame and &h0F) = 0 then m.playSound("run", 0)
    events = pl.events
    pl.events = []
    for each ev in events
        m.handle(ev)
        if m.mode <> "play" then exit for
    end for
end sub

sub Game_handle(ev as object)
    pl = m.player
    if ev.kind = "sound" then
        if ev.name = "stop" then
            m.stopSounds()
        else
            pitch = 0
            if ev.DoesExist("randomPitch") then pitch = m.rng.nextByte() and 1
            m.playSound(ev.name, pitch)
        end if
    else if ev.kind = "pickup" then
        before = m.score
        m.score = m.score + Collect(m.state, m.room, ev, m.rng)
        if ev.code = &h24 then m.keys = m.keys + 1
        if (before \ 10000) <> (m.score \ 10000) and pl.lives < 5 then
            pl.lives = pl.lives + 1
            m.playSound("extraLife", 0)
        end if
        m.playSound("pickup", 0)
    else if ev.kind = "door" then
        m.goThroughDoor(ev.side)
    else if ev.kind = "respawn" then
        m.bird = invalid
        if m.timer = 0 then
            if m.roomIndex = 10 then m.timer = 4096 else m.timer = 2048
        end if
    else if ev.kind = "gameover" then
        m.endGame("gameover")
    end if
end sub

' [$BEA5 / $BF02 / $BF44] door transition, with the chamber 0 / chamber X rules
sub Game_goThroughDoor(side as string)
    pl = m.player
    row = ((pl.y + 7) and &hFF) >> 3
    door = invalid
    for each d in m.room.def.doors
        if d.at.side = side and (d.at.raw and &h7F) = row then door = d
    end for
    if door = invalid then return
    from = m.roomIndex
    dest = door["to"]
    spawn = DoorSpawn(door.arrive)
    leaving = m.timer
    if dest = m.prevRoom then m.timer = ReturnTimer(m.prevTimer, leaving) else m.timer = 4096
    m.prevRoom = from
    m.prevTimer = leaving
    if dest = 0 then
        if m.difficulty < 2 and not m.beginner then m.difficulty = m.difficulty + 1
        if from = 10 then
            m.endGame("escaped")
            return
        end if
        if from = 9 and m.escapeMode then
            dest = 10
            spawn = { x: &h0B, y: spawn.y, facing: 2 }
        else if from = 9 then
            m.state = NewGameState(m.defs, m.doorOpenInitial)
        end if
    end if
    if dest = 10 then m.timer = 9999
    m.enterRoom(dest, spawn, false)
end sub

sub Game_endGame(mode as string)
    if mode = "escaped" then m.stopSounds()
    m.mode = mode
    m.endTimer = 120
    m.escapeGuard = true
    if m.score > m.hiScore then m.hiScore = m.score
end sub
