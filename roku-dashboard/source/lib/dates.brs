' Calendar math and holiday rules. Pure functions: no roDateTime, so the brs tests run them.
' Weekdays are 0 = Sunday .. 6 = Saturday; months are 1..12.

function IsLeapYear(y as integer) as boolean
    return (y mod 4 = 0 and y mod 100 <> 0) or y mod 400 = 0
end function

function DaysInMonth(y as integer, mo as integer) as integer
    if mo = 2 then
        if IsLeapYear(y) then return 29
        return 28
    end if
    if mo = 4 or mo = 6 or mo = 9 or mo = 11 then return 30
    return 31
end function

' Sakamoto's method.
function DayOfWeek(y as integer, mo as integer, d as integer) as integer
    t = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
    if mo < 3 then y = y - 1
    return (y + y \ 4 - y \ 100 + y \ 400 + t[mo - 1] + d) mod 7
end function

function DayOfYear(y as integer, mo as integer, d as integer) as integer
    n = d
    for i = 1 to mo - 1
        n = n + DaysInMonth(y, i)
    end for
    return n
end function

' Returns [month, day] for day-of-year n.
function DateFromDayOfYear(y as integer, n as integer) as object
    mo = 1
    while n > DaysInMonth(y, mo)
        n = n - DaysInMonth(y, mo)
        mo = mo + 1
    end while
    return [mo, n]
end function

' Western (Gregorian) Easter, anonymous Gregorian algorithm. Returns [month, day].
function EasterDate(y as integer) as object
    a = y mod 19
    b = y \ 100
    c = y mod 100
    d = b \ 4
    e = b mod 4
    f = (b + 8) \ 25
    g = (b - f + 1) \ 3
    h = (19 * a + b - d - g + 15) mod 30
    i = c \ 4
    k = c mod 4
    l = (32 + 2 * e + 2 * i - h - k) mod 7
    mm = (a + 11 * h + 22 * l) \ 451
    month = (h + l - 7 * mm + 114) \ 31
    day = ((h + l - 7 * mm + 114) mod 31) + 1
    return [month, day]
end function

' Day of month of the nth (1-based) given weekday in a month.
function NthWeekday(y as integer, mo as integer, weekday as integer, n as integer) as integer
    first = DayOfWeek(y, mo, 1)
    return 1 + ((weekday - first + 7) mod 7) + 7 * (n - 1)
end function

function LastWeekday(y as integer, mo as integer, weekday as integer) as integer
    last = DaysInMonth(y, mo)
    return last - ((DayOfWeek(y, mo, last) - weekday + 7) mod 7)
end function

' Resolves a holiday rule to [month, day] in year y, or invalid when it doesn't occur that
' year (Feb 29). Rule kinds (see data/holidays.json):
'   fixed  {month, day}            nth   {month, weekday, n}
'   last   {month, weekday}        easter {offset}
'   doy    {day}                   any rule may add "offset" days (Black Friday, Election Day)
function Holiday_resolve(h as object, y as integer) as object
    rule = h.rule
    if rule = "fixed" then
        if h.day > DaysInMonth(y, h.month) then return invalid
        md = [h.month, h.day]
    else if rule = "nth" then
        md = [h.month, NthWeekday(y, h.month, h.weekday, h.n)]
    else if rule = "last" then
        md = [h.month, LastWeekday(y, h.month, h.weekday)]
    else if rule = "easter" then
        md = EasterDate(y)
    else if rule = "doy" then
        md = DateFromDayOfYear(y, h.day)
    else
        return invalid
    end if
    offset = 0
    if h.offset <> invalid then offset = h.offset
    if offset = 0 then return md
    return DateFromDayOfYear(y, DayOfYear(y, md[0], md[1]) + offset)
end function

' Names of the holidays on y-m-d whose category is in cats (an AA of category -> true).
function Holidays_forDate(list as object, y as integer, mo as integer, d as integer, cats as object) as object
    out = []
    for each h in list
        if cats.DoesExist(h.cat) then
            md = Holiday_resolve(h, y)
            if md <> invalid and md[0] = mo and md[1] = d then out.Push(h)
        end if
    end for
    return out
end function

function Holiday_categories() as object
    return [
        { id: "food", title: "Food & drink" }
        { id: "animals", title: "Animals" }
        { id: "silly", title: "Silly & geeky" }
        { id: "awareness", title: "Awareness & causes" }
        { id: "official", title: "Federal holidays" }
        { id: "cultural", title: "Cultural & religious" }
    ]
end function
