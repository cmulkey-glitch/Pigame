' Player logic ported from the Atari 7800 Downland ROM (BrightScript version of
' src/game/player.js; see docs/PHYSICS.md). Units are the 7800's: x = MARIA hpos, y = line
' with 0 at the top of the HUD row. Movement runs on a 4-frame tick (tick = frame and 3).
' input is an AA of booleans: left, right, up, down, jump.

function Player_new() as object
    p = {
        events: [], lives: 4
        reset: Player_reset, update: Player_update, walk: Player_walk
        startJump: Player_startJump, airTick: Player_airTick, fall: Player_fall
        catchRope: Player_catchRope, climb: Player_climb, hang: Player_hang
        touchItems: Player_touchItems, pickUp: Player_pickUp, kill: Player_kill
        startSplat: Player_startSplat, updateSplat: Player_updateSplat
        frameIndex: Player_frameIndex, emit: Player_emit
    }
    p.reset({ x: &h40, y: &h1F, facing: 2 }, false)
    return p
end function

sub Player_reset(spawn as object, regenerating as boolean)
    m.x = spawn.x : m.y = spawn.y : m.facing = spawn.facing
    m.vyHi = 0 : m.vyLo = 0
    m.air = false         ' $F1 bit 0
    m.vertical = false    ' $F1 bit 1: no horizontal momentum in the air
    m.regen = regenerating ' $F1 bit 2
    m.jumpLatch = false   ' $F1 bit 3
    m.dead = false        ' $F1 bit 4
    m.running = false     ' $F1 bit 5
    m.climbing = false    ' $F1 bit 6
    m.hanging = false     ' $FA bit 0
    m.holdCount = 0       ' $0144
    m.hangSide = 0        ' $0145
    m.midairDeath = 0     ' $0141
    m.splat = 0           ' $0142
end sub

sub Player_emit(ev as object)
    m.events.Push(ev)
end sub

function Pl_isWall(t as integer) as boolean
    return t > 6 and t < &h20
end function

function Pl_isItem(t as integer) as boolean
    return t >= &h20 and t <= &h24
end function

function Pl_isDoor(t as integer) as boolean
    return t >= &h1A and t <= &h1E
end function

sub Player_update(room as object, input as object, frame as integer)
    tick = frame and 3
    if m.splat > 0 then
        m.updateSplat()
        return
    end if
    if m.midairDeath > 0 then m.midairDeath = m.midairDeath - 1
    if tick = 0 then m.walk(room, input)
    if m.climbing and tick = 0 then m.climb(room, input)
    if input.jump then
        if not m.air and not m.regen then m.startJump(input)
    else
        m.jumpLatch = false
    end if
    if m.air and tick = 0 then m.airTick(room)
    if tick = 1 then m.touchItems(room)
end sub

' [$BD0F] Walking, one hpos per tick. Ends regeneration.
sub Player_walk(room as object, input as object)
    m.running = false
    if m.climbing or m.dead or m.air then return
    right = input.right : left = input.left
    if not right and not left then return
    if right then
        dirn = 1 : probeX = m.x + 7
    else
        dirn = -1 : probeX = m.x
    end if
    t = room.tileAt(probeX, m.y + 8)
    m.regen = false
    atDoor = (right and m.x >= &h8D) or (not right and m.x <= &h0B)
    if atDoor and Pl_isDoor(t) then
        if right then side = "right" else side = "left"
        m.emit({ kind: "door", side: side })
        return
    end if
    if Pl_isItem(t) then
        m.pickUp(room, probeX, m.y + 8, t)
        return
    end if
    if t > 6 then return
    m.x = (m.x + dirn) and &hFF
    if right then m.facing = 2 else m.facing = 1
    if room.tileAt(m.x + 3, m.y + 15) = &h04 then
        m.running = true
        return
    end if
    ' walked off an edge: one extra step out and one line down, then fall
    m.air = true
    m.x = (m.x + dirn) and &hFF
    m.y = (m.y + 1) and &hFF
    m.vyHi = &hFF
end sub

' [$C26B] Jump from the ground or off a rope (off a rope needs a direction).
sub Player_startJump(input as object)
    if m.jumpLatch or m.dead or m.hanging then return
    right = input.right : left = input.left
    m.vertical = not (right or left)
    if m.climbing and m.vertical then
        m.vertical = false
        return
    end if
    if left then m.facing = 1
    if right then m.facing = 2
    m.air = true
    m.climbing = false
    m.jumpLatch = true
    m.vyHi = &h05 : m.vyLo = &h80
    m.emit({ kind: "sound", name: "jump" })
end sub

' [$BFEB] Air: horizontal step with wall bounce, then vertical, then rope catch.
sub Player_airTick(room as object)
    if not m.vertical and not m.dead then
        if m.facing = 1 then
            m.x = (m.x - 1) and &hFF
            if Pl_isWall(room.tileAt(m.x + 1, m.y + 15)) then
                m.x = (m.x + 1) and &hFF
                m.facing = 2
                if m.vyHi < &h80 then m.vyHi = (256 - m.vyHi) and &hFF
                m.emit({ kind: "sound", name: "bump" })
            end if
        else
            m.x = (m.x + 1) and &hFF
            if Pl_isWall(room.tileAt(m.x + 6, m.y + 15)) then
                m.x = (m.x - 1) and &hFF
                m.facing = 1
                if m.vyHi < &h80 then m.vyHi = (256 - m.vyHi) and &hFF
                m.emit({ kind: "sound", name: "bump" })
            end if
        end if
    end if
    if m.midairDeath = 0 then
        if m.fall(room) then return
    end if
    m.catchRope(room)
end sub

' Vertical motion. Returns true if the player died on landing.
function Player_fall(room as object) as boolean
    if m.vyHi >= &h80 then
        if room.tileAt(m.x + 3, m.y + 16) = &h04 and room.tileAt(m.x + 3, (m.y + 16 - m.vyHi) and &hFF) <> &h04 then
            m.y = (m.y and &hF8) + 7
            m.air = false
            m.emit({ kind: "sound", name: "stop" })   ' [$C134] every landing silences both channels
            if m.dead then
                m.startSplat()
                if m.vyHi < &hFA then m.emit({ kind: "sound", name: "splat" })
                return true
            end if
            if m.vyHi < &hFA then
                m.kill()
                return true
            end if
            m.vyHi = 0
            return false
        end if
    end if
    m.y = (m.y - m.vyHi) and &hFF
    if m.y > &hF0 then m.vyHi = &hFF
    vy = ((m.vyHi * 256 + m.vyLo) - &hC0) and &hFFFF      ' gravity
    m.vyHi = vy >> 8 : m.vyLo = vy and &hFF
    if m.vyHi > &h80 and m.vyHi < &hF9 then m.vyHi = &hF9  ' terminal speed
    return false
end function

' [$C19A] Grab a rope when its column lines up exactly, or a bar ($2A) from below.
sub Player_catchRope(room as object)
    t = room.tileAt(m.x + 3, m.y + 6)
    if t <> &h02 and t <> &h2A and t <> &h2C then return
    if t = &h2A then
        if room.tileAt(m.x + 3, m.y + 9) <> &h2A then return
        m.y = (m.y and &hF8) + 5
        if ((m.x and &h0F) + 3) < 8 then m.x = (m.x and &hF0) + 4 else m.x = (m.x and &hF0) + 12
    else if (m.x and &h0F) <> &h04 and (m.x and &h0F) <> &h0C then
        return
    end if
    if m.dead then return
    m.air = false
    m.climbing = true
    m.hanging = false
    m.holdCount = 0
    m.hangSide = 0
end sub

function Pl_onRope(room as object, x as integer, y as integer) as boolean
    t = room.tileAt(x + 3, y + 6)
    return t = &h02 or t = &h2C
end function

' [$B52B] Rope: up 1 line / tick, down 2; off the bottom falls straight down.
sub Player_climb(room as object, input as object)
    up = input.up : down = input.down
    if (not up and not down) or m.hanging then
        m.hang(room, input)
        return
    end if
    if up then
        if not Pl_onRope(room, m.x, m.y - 1) then return
        m.y = m.y - 1
        if (m.y and 1) <> 0 then m.emit({ kind: "sound", name: "climbUp", randomPitch: true })
        return
    end if
    ny = m.y + 2
    if not Pl_onRope(room, m.x, ny) then
        m.climbing = false
        m.air = true
        m.vertical = true
        m.vyHi = &hFF
    else if (m.y and 2) <> 0 then
        m.emit({ kind: "sound", name: "climbDown", randomPitch: true })
    end if
    m.y = ny
end sub

' [$B620] Left/right on a rope: after 6 ticks shift 4 to hang beside it; from a hang,
' 6 ticks back returns to the rope, 6 ticks away lets go.
sub Player_hang(room as object, input as object)
    right = input.right : left = input.left
    if not right and not left then return
    if right then
        want = 2 : dx = 4
    else
        want = 1 : dx = -4
    end if
    if not m.hanging then
        if m.holdCount = 0 then
            m.holdCount = 6
            return
        end if
        m.holdCount = m.holdCount - 1
        if m.holdCount > 0 then return
        m.hanging = true
        m.holdCount = 6
        if right then t = room.tileAt(m.x + 8, m.y + 8) else t = room.tileAt(m.x - 8, m.y + 8)
        if t >= 6 and t < &h20 then
            m.holdCount = 0
            m.hanging = false
            return
        end if
        m.facing = want
        m.hangSide = want
        m.x = (m.x + dx) and &hFF
        return
    end if
    if m.facing <> want then
        m.facing = want
        m.holdCount = 6
        return
    end if
    m.holdCount = m.holdCount - 1
    if m.holdCount > 0 then return
    m.x = (m.x + dx) and &hFF
    m.hanging = false
    if m.hangSide <> want then return   ' stepped back onto the rope
    m.climbing = false
    m.air = true
    m.vertical = true
    m.vyHi = 0
end sub

' [$B252] Items touched while jumping, falling or climbing.
sub Player_touchItems(room as object)
    if not m.air and not m.climbing then return
    if m.vyHi < &h80 then dy = 1 else dy = 15
    t = room.tileAt(m.x + 3, m.y + dy)
    if Pl_isItem(t) then
        m.pickUp(room, m.x + 3, m.y + dy, t)
        return
    end if
    if m.vertical then return
    if m.facing = 1 then px = m.x else px = m.x + 7
    t = room.tileAt(px, m.y + 7)
    if Pl_isItem(t) then m.pickUp(room, px, m.y + 7, t)
end sub

sub Player_pickUp(room as object, x as integer, y as integer, code as integer)
    room.clearTileAt(x, y)
    cell = room.cellAt(x, y)
    m.emit({ kind: "pickup", code: code, col: cell.col, row: cell.row })
end sub

' [$B812] Death. On a rope: drop. In the air: flicker for $2C frames, then fall and splat.
sub Player_kill()
    if m.dead then return
    m.dead = true
    m.splat = 0
    if m.climbing then
        m.climbing = false : m.hanging = false : m.air = true
    end if
    if m.air then
        m.midairDeath = &h2C
        m.vyHi = &hFF
    else
        m.startSplat()
    end if
end sub

sub Player_startSplat()
    m.splat = &h4B - 1
    m.emit({ kind: "sound", name: "splat" })
end sub

' [$B947] Splat countdown, then lose a life and regenerate in place.
sub Player_updateSplat()
    m.splat = m.splat - 1
    if m.splat > 0 then return
    m.dead = false
    m.lives = m.lives - 1
    if m.lives > 0 then
        m.regen = true
        m.emit({ kind: "respawn" })
    else
        m.emit({ kind: "gameover" })
    end if
end sub

' [$B861 / $BA16] Animation frame (index into playerFrames).
function Player_frameIndex(fc as integer) as integer
    left = (m.facing = 1)
    if m.splat > 0 then
        if m.splat > &h43 then return 16 else return 17
    end if
    if m.midairDeath > 0 then
        if (fc and 4) <> 0 then return 14 else return 15
    end if
    if m.climbing and not m.hanging then
        if (m.y and 2) <> 0 then return 13 else return 12
    end if
    if m.air or m.hanging then
        if left then return 15 else return 14
    end if
    lf = 0
    if left then lf = 1
    if m.regen then
        f = 8 + lf * 2
        if (fc and 2) <> 0 then f = f + 1
        return f
    end if
    if m.running then return ((fc and &h1F) >> 3) + lf * 4
    if left then return 6
    return 2
end function
