' Chamber tile codes, random numbers, game state, drops, ball, bird and chamber timer
' (BrightScript versions of src/game/room.js, rng.js, state.js, drops.js, enemies.js).

' ---- 8-bit helpers ----
function Xor8(a as integer, b as integer) as integer
    return ((a or b) - (a and b)) and &hFF
end function

' ---- 7800basic rand ($FA67): 16-bit LFSR in $40/$41 ----
function Rng_new() as object
    return { lo: &h4D, hi: &h74, nextByte: Rng_next }
end function

function Rng_next() as integer
    a = m.lo
    carryIn = a and 1
    a = a >> 1
    carryOut = (m.hi >> 7) and 1
    m.hi = ((m.hi << 1) or carryIn) and &hFF
    if carryOut <> 0 then a = Xor8(a, &hB4)
    m.lo = a
    return Xor8(a, m.hi)
end function

' ---- Chamber: RAM tile map at $2200 (20 x 24) ----
function Room_new(def as object) as object
    r = {
        def: def, codes: CreateObject("roArray", 480, false)
        tileAt: Room_tileAt, cellAt: Room_cellAt, setCell: Room_setCell
        clearTileAt: Room_clearTileAt, placeObjects: Room_placeObjects, setDoor: Room_setDoor
        objects: Room_objects
    }
    for row = 0 to 23
        for col = 0 to 19
            r.codes[row * 20 + col] = def.tiles[row][col] * 2
        end for
    end for
    return r
end function

' [$C6F3] tile code under a point: column (x-4)>>3, row (y-8)>>3
function Room_tileAt(x as integer, y as integer) as integer
    col = ((x - 4) and &hFF) >> 3
    row = ((y - 8) and &hFF) >> 3
    if col >= 20 or row >= 24 then return 0
    return m.codes[row * 20 + col]
end function

function Room_cellAt(x as integer, y as integer) as object
    return { col: ((x - 4) and &hFF) >> 3, row: ((y - 8) and &hFF) >> 3 }
end function

sub Room_setCell(col as integer, row as integer, code as integer)
    if col < 20 and row < 24 then m.codes[row * 20 + col] = code
end sub

sub Room_clearTileAt(x as integer, y as integer)
    c = m.cellAt(x, y)
    m.setCell(c.col, c.row, 0)
end sub

' [$AE4F] treasures, keys and doors from game state
sub Room_placeObjects(state as object)
    for each t in m.def.treasures
        m.setCell(t.col, t.row, state.treasure[t.slot])
    end for
    for each k in m.def.keys
        if state.keyDoor[k.slot] <> 0 then m.setCell(k.col, k.row, &h24) else m.setCell(k.col, k.row, 0)
    end for
    for each d in m.def.doors
        m.setDoor(d.id, state.doorOpen[d.id])
    end for
end sub

' [$AEFD / $B4AE] door cells: column 0 or 18, three rows ending at the door's row
sub Room_setDoor(id as integer, isOpen as integer)
    for each d in m.def.doors
        if d.id = id then
            if d.at.side = "right" then
                col = 18 : closed = &h0A
            else
                col = 0 : closed = &h08
            end if
            row = d.at.raw and &h7F
            if isOpen <> 0 then
                m.setCell(col, row, &h1E) : m.setCell(col, row - 1, &h1C) : m.setCell(col, row - 2, &h1A)
            else
                m.setCell(col, row, closed) : m.setCell(col, row - 1, closed) : m.setCell(col, row - 2, closed)
            end if
        end if
    end for
end sub

' objects to draw: door cells and items
function Room_objects() as object
    out = []
    for each d in m.def.doors
        if d.at.side = "right" then col = 18 else col = 0
        row = d.at.raw and &h7F
        for r = row - 2 to row
            out.Push({ code: m.codes[r * 20 + col], col: col, row: r })
        end for
    end for
    for i = 0 to 479
        c = m.codes[i]
        if c >= &h20 and c <= &h24 then out.Push({ code: c, col: i mod 20, row: i \ 20 })
    end for
    return out
end function

function DoorSpawn(arrive as object) as object
    if arrive.side = "right" then f = 1 else f = 2
    return { x: arrive.x, y: arrive.y, facing: f }
end function

' ---- per-game object state ($853C) ----
function NewGameState(defs as object, doorOpenInitial as object) as object
    n = defs.Count() * 4
    treasure = CreateObject("roArray", n, false)
    keyDoor = CreateObject("roArray", n, false)
    for i = 0 to n - 1
        treasure[i] = &hFF : keyDoor[i] = &hFF
    end for
    for each def in defs
        for each t in def.treasures
            treasure[t.slot] = t.code
        end for
        for each k in def.keys
            keyDoor[k.slot] = k.door + 1
        end for
    end for
    doorOpen = []
    for each v in doorOpenInitial
        doorOpen.Push(v)
    end for
    return { treasure: treasure, keyDoor: keyDoor, doorOpen: doorOpen }
end function

' [$B2F1 / $B393] pickup: update state, open the key's door; returns the points
function Collect(state as object, room as object, ev as object, rng as object) as integer
    def = room.def
    if ev.code = &h24 then
        pts = 250
        for each k in def.keys
            if k.col = ev.col and k.row = ev.row and state.keyDoor[k.slot] <> 0 then
                door = state.keyDoor[k.slot] - 1
                state.keyDoor[k.slot] = 0
                if state.doorOpen[door] = 0 then
                    state.doorOpen[door] = 1
                    room.setDoor(door, 1)
                end if
            end if
        end for
    else
        pts = 350
        for each t in def.treasures
            if t.col = ev.col and t.row = ev.row then state.treasure[t.slot] = 0
        end for
    end if
    ' [$C74F] random 00-99 bonus, one BCD digit at a time
    lo = rng.nextByte() and 15
    while lo > 9
        lo = rng.nextByte() and 15
    end while
    hi = rng.nextByte() and 15
    while hi > 9
        hi = rng.nextByte() and 15
    end while
    return pts + hi * 10 + lo
end function

' ---- acid drops ($C300) ----
function Drops_new(def as object, room as integer, difficulty as integer, rng as object, none as boolean) as object
    d = { rng: rng, difficulty: difficulty, title: (room = -1), slots: [], spawns: []
          update: Drops_update, hits: Drops_hits, visible: Drops_visible, spawn: Drops_spawn }
    if none then return d                                   ' BEGINNER: no drops
    for each s in def.dropSpawns
        d.spawns.Push({ x: s[0], y: s[1] })
    end for
    if room = 8 then d.mask = &h3F else d.mask = &h1F
    if difficulty = 2 and not d.title then                  ' [$B087]
        i = def.dropTweak
        s = d.spawns[i]
        s.x = (s.x - 2) and &hFF
        s.y = (s.y + 2) and &hFF
        d.spawns[i - 1] = { x: s.x, y: s.y }
    end if
    last = 5                                                ' [$B0C4]
    if d.title or room > 5 or difficulty = 2 then last = 7
    if difficulty = 0 and not d.title then last = 5
    for i = 0 to last
        slot = { x: 0, y: 0, timer: 0, spawnIdx: &hFF }
        d.spawn(slot)
        d.slots.Push(slot)
    end for
    return d
end function

sub Drops_spawn(s as object)
    r = m.rng.nextByte() and m.mask
    s.x = m.spawns[r].x
    s.y = m.spawns[r].y
    s.spawnIdx = r
    s.timer = &h38 + (m.rng.nextByte() and 7)
    if m.difficulty = 0 then s.timer = s.timer + &h10
end sub

sub Drops_update(room as object)
    for each d in m.slots
        if d.spawnIdx = &hFF then
            if (m.rng.nextByte() and 7) = 0 then m.spawn(d)
        else if d.timer > 0 then
            d.timer = d.timer - 1
        else
            x = d.x + 1 : y = d.y + 2
            removed = false
            if m.title then                                 ' [$C41D]
                t = room.tileAt(x, y) : sb = x and 7
                if y > &hA2 or (t = &h16 and sb < 4) or (t = &h14 and sb >= 4) then
                    d.spawnIdx = &hFF : removed = true
                end if
            else if room.tileAt(x, y) = &h04 and room.tileAt(x, y + 3) <> &h04 then
                d.spawnIdx = &hFF
            end if
            if not removed then d.y = (d.y + 2) and &hFF
        end if
    end for
end sub

' [$B7A2]
function Drops_hits(px as integer, py as integer) as boolean
    for each d in m.slots
        if d.spawnIdx <> &hFF and d.timer = 0 then
            if ((px + 6 - d.x) and &hFF) < 8 and ((py + 14 - d.y) and &hFF) < 18 then return true
        end if
    end for
    return false
end function

' [$C47D] drops to draw, with the ROM's small vertical jitter
function Drops_visible() as object
    out = []
    if m.slots.Count() = 0 then return out
    jitter = m.rng.nextByte()
    for i = 0 to m.slots.Count() - 1
        d = m.slots[i]
        if d.spawnIdx <> &hFF then
            hidden = false
            if i > 0 and d.timer > 0 then
                for j = 0 to i - 1
                    o = m.slots[j]
                    if o.spawnIdx = d.spawnIdx and o.timer > 0 then hidden = true
                end for
            end if
            if not hidden then out.Push({ x: d.x, y: d.y + (m.rng.nextByte() and 1) + ((jitter >> i) and 1) })
        end if
    end for
    return out
end function

' ---- ball ($B161) ----
function Ball_new(start as object, room as integer) as object
    return { sx: start.x, sy: start.y, x: start.x, y: start.y, vy: 1, room: room
             update: Ball_update, hits: Ball_hits }
end function

sub Ball_update(frame as integer)
    if (frame and 4) <> 0 and (frame and 3) = 3 then return
    m.x = (m.x - 1) and &hFF
    if m.x < &h0C then
        m.x = m.sx : m.y = m.sy : m.vy = 1
    end if
    m.y = (m.y - m.vy) and &hFF
    m.vy = (m.vy - 1) and &hFF
    ' per-chamber floors: [min x, floor y, bounce vy, ends the check]
    if m.room = 0 then
        if m.y > &h90 and m.x > &h68 then
            m.y = &h90 : m.vy = 5
        end if
    else if m.room = 2 then
        if m.y > &hA0 and m.x > &h60 then
            m.y = &hA0 : m.vy = 4 : return
        end if
        if m.y > &hB0 and m.x > &h48 then
            m.y = &hB0 : m.vy = 4 : return
        end if
    else if m.room = 5 then
        if m.y > &h90 and m.x > &h48 then
            m.y = &h90 : m.vy = 5
        end if
    end if
    if m.y > &hBF then
        m.y = &hBF : m.vy = 4
    end if
end sub

function Ball_hits(px as integer, py as integer) as boolean
    return ((px + 6 - m.x) and &hFF) < 10 and ((py + 14 - m.y) and &hFF) < 22
end function

' ---- bird ($85BC / $85D2) ----
function Bird_new() as object
    return { x: &h20, y: &h17, dirn: 3, update: Bird_update, hits: Bird_hits }
end function

sub Bird_update()
    if m.dirn = 1 or m.dirn = 3 then m.x = (m.x + 2) and &hFF else m.x = (m.x - 2) and &hFF
    if m.dirn = 3 or m.dirn = 5 then m.y = (m.y + 2) and &hFF else m.y = (m.y - 2) and &hFF
    if m.x <= &h08 or m.x >= &h90 or m.y <= &h08 or m.y >= &hC0 then
        m.dirn = m.dirn + 2
        if m.dirn > 7 then m.dirn = 1
    end if
end sub

function Bird_hits(px as integer, py as integer) as boolean
    return ((px + 6 - m.x) and &hFF) < 14 and ((py + 14 - m.y) and &hFF) < 22
end function

' [$8710] straight back to the chamber you came from
function ReturnTimer(savedPrevious as integer, current as integer) as integer
    t = savedPrevious + (4096 - current)
    if t >= 4000 then return 4096
    return t
end function

' ---- sound driver ($F8D9 playsfx, $F83F per-frame driver) ----
function SoundDriver_new(sounds as object) as object
    ch = []
    for x = 0 to 1
        ch.Push({ steps: invalid, idx: 0, priority: 0, frames: 0, pitch: 0, wait: 0 })
    end for
    return { sounds: sounds, ch: ch, regs: [{ f: 0, c: 0, v: 0 }, { f: 0, c: 0, v: 0 }]
             play: SoundDriver_play, stopAll: SoundDriver_stopAll, update: SoundDriver_update }
end function

' returns the channel used, or -1
function SoundDriver_play(name as string, pitch as integer) as integer
    s = m.sounds[name]
    if s = invalid then return -1
    if m.ch[0].steps = invalid then
        x = 0
    else if m.ch[1].steps = invalid then
        x = 1
    else if s.priority = 0 then
        return -1
    else if m.ch[0].priority >= m.ch[1].priority then
        x = 1
    else
        x = 0
    end if
    c = m.ch[x]
    c.steps = s.steps : c.idx = 0 : c.priority = s.priority : c.frames = s.frames
    c.pitch = pitch : c.wait = 0
    return x
end function

sub SoundDriver_stopAll()
    for x = 0 to 1
        m.ch[x].steps = invalid
        m.regs[x].f = 0
        m.regs[x].v = 0
    end for
end sub

function SoundDriver_update() as object
    x = 0
    while x < 2
        c = m.ch[x]
        if c.steps <> invalid then
            if c.wait > 0 then
                c.wait = c.wait - 1
            else
                st = c.steps[c.idx]
                if st[1] = &h10 then                    ' command: new step length
                    c.frames = st[2] : c.wait = 0 : c.idx = c.idx + 1
                    x = x - 1
                else
                    c.wait = c.frames
                    if c.priority > 0 then c.priority = c.priority - 1
                    m.regs[x] = { f: (st[0] + c.pitch) and &hFF, c: st[1], v: st[2] }
                    if (st[0] or st[1] or st[2]) = 0 then c.steps = invalid else c.idx = c.idx + 1
                end if
            end if
        end if
        x = x + 1
    end while
    return m.regs
end function
