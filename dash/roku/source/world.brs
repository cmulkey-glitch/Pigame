' Random worlds: ten levels built from the pool (pkg:/pool/<tier>.txt, made by
' dash/tools/poolgen.py) by a seed, so the same code always gives the same world.
'
' Level i has sides World_width(i) long (shorter toward the centre, as in the classic spiral)
' and its four shapes in a shuffled order. Each side is an original from the pool of the shape,
' from tier i or a tier either side of it (played at the speed it was verified at), as one of
' the variants verified for it (O original, R reversed, M mirrored, B both; see poolgen.py),
' cut to length. Cutting short keeps a side fair: past the cut there is nothing left to hit.

function World_width(i as integer) as integer
    return 260 - 22 * i         ' as levelgen.py level_width
end function

' A seedable random number generator (BrightScript's Rnd cannot be seeded): an LCG on
' LongIntegers, so the products cannot overflow.
function Rng_new(seed as integer) as object
    return { x: seed + 0&, next: Rng_next, int: Rng_int }
end function

function Rng_next() as integer
    m.x = (m.x * 1103515245& + 12345&) mod 2147483648&
    return CInt(m.x \ 65536&)
end function

' 0 .. n-1
function Rng_int(n as integer) as integer
    return m.next() mod n
end function

' World codes: 5 letters from an alphabet without look-alikes, 24^5 = 7,962,624 worlds.
function Code_alphabet() as string
    return "ACDEFHJKLMNPRTUVWXY34679"
end function

function World_code(seed as integer) as string
    a = Code_alphabet()
    s = ""
    v = seed
    for i = 1 to 5
        s = Mid(a, (v mod 24) + 1, 1) + s
        v = v \ 24             ' not Int(v / 24): / is single precision
    end for
    return s
end function

function World_seed(code as string) as integer
    a = Code_alphabet()
    v = 0
    for i = 1 to Len(code)
        v = v * 24 + Instr(1, a, Mid(code, i, 1)) - 1
    end for
    return v
end function

' Today's world: the same for everyone on a given date.
function World_daily_seed() as integer
    dt = CreateObject("roDateTime")
    dt.ToLocalTime()
    ymd = dt.GetYear() * 10000 + dt.GetMonth() * 100 + dt.GetDayOfMonth()
    return CInt(((ymd + 0&) * 2654435761&) mod 7962624&)
end function

function World_new_seed() as integer
    dt = CreateObject("roDateTime")
    return CInt(((dt.AsSeconds() + 0&) * 40503& + Rnd(100000)) mod 7962624&)
end function

' The pool of tier t, parsed on first use. Each side carries the variants verified for it (the
' "[...]" in its "---" line).
function Pool_tier(app as object, t as integer) as object
    if app.pool = invalid then app.pool = {}
    k = t.ToStr()
    if app.pool[k] = invalid then
        dir = "pkg:/pool/"
        if app.poolDir <> invalid then dir = app.poolDir     ' the tests run from dash/
        text = ReadAsciiFile(dir + k + ".txt")
        lv = Level_parse(text)
        variants = []
        for each line in text.Split(Chr(10))
            if Left(line, 3) = "---" then
                a = Instr(1, line, "[")
                b = Instr(1, line, "]")
                v = "O"
                if a > 0 and b > a then v = Mid(line, a + 1, b - a - 1)
                variants.Push(v)
            end if
        end for
        for i = 0 to lv.stages.Count() - 1
            lv.stages[i].variants = variants[i]
        end for
        app.pool[k] = lv
    end if
    return app.pool[k]
end function

' A side from the pool as variant v ("O", "R", "M" or "B"), cut to width (keeping the empty
' tail at its end).
function Strip_variant(src as object, v as string, width as integer) as object
    st = { h: 10, width: width, cols: [], mode: src.mode, phys: src.phys }
    rev = (v = "R" or v = "B")
    mir = (v = "M" or v = "B")
    lo = 12                     ' the runway (levelgen.py RUNWAY) stays in front
    hi = src.width - 11         ' the last column before the source's tail (TAIL = 10)
    last = width - 11           ' and this one's
    for c = 0 to width - 1
        col = []
        if c <= last then
            s = c
            if rev and c >= lo and c <= hi then s = lo + hi - c
            srcCol = src.cols[s]
            for i = 0 to srcCol.Count() - 1
                o = srcCol[i]
                r = o.r
                k = o.k
                if mir then
                    r = 9 - r
                    if k = "^" then
                        k = "v"
                    else if k = "v" then
                        k = "^"
                    end if
                end if
                col.Push({ k: k, r: r, id: c.ToStr() + "_" + r.ToStr() })
            end for
        end if
        st.cols.Push(col)
    end for
    return st
end function

' The ten levels of world `seed`; colours and music borrowed from the classic levels.
function World_build(app as object, seed as integer) as object
    rng = Rng_new(seed)
    levels = []
    for i = 0 to 9
        look = app.classic[(seed + i * 3) mod app.classic.Count()]
        lv = { name: "Level " + (i + 1).ToStr(), difficulty: app.classic[i].difficulty
               bg: look.bg, ground: look.ground, line: look.line, music: "level" + (i + 1).ToStr()
               width: 0, stages: [], phys: Dash_phys() }
        order = []
        for each mode in Stage_modes()
            order.Push(mode)
        end for
        for j = order.Count() - 1 to 1 step -1
            k = rng.int(j + 1)
            tmp = order[j]
            order[j] = order[k]
            order[k] = tmp
        end for
        w = World_width(i)
        for s = 0 to 3
            mode = order[s]
            t = i + rng.int(3) - 1
            if t < 0 then t = 0
            if t > 9 then t = 9
            cands = World_candidates(Pool_tier(app, t), mode, w)
            if cands.Count() = 0 then cands = World_candidates(Pool_tier(app, i), mode, w)
            src = cands[rng.int(cands.Count())]
            v = Mid(src.variants, rng.int(Len(src.variants)) + 1, 1)
            st = Strip_variant(src, v, w)
            st.start = lv.width
            lv.width = lv.width + w
            lv.stages.Push(st)
        end for
        levels.Push(lv)
    end for
    return levels
end function

function World_candidates(pool as object, mode as string, width as integer) as object
    cands = []
    for i = 0 to pool.stages.Count() - 1
        st = pool.stages[i]
        if st.mode = mode and st.width >= width then cands.Push(st)
    end for
    return cands
end function
