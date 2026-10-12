' Wikimedia picture of the day, from Wikipedia's featured-content feed (no key).
' Wikimedia only serves thumbnails at standard widths, so ask for 1920 (landscape) or 1280
' (portrait, shown fit-to-height). Never the original: those can be tens of megabytes.

function Potd_feedUrl(y as integer, mo as integer, d as integer) as string
    base = "https://en.wikipedia.org/api/rest_v1/feed/featured/"
    return base + StrI(y).Trim() + "/" + Potd_pad2(mo) + "/" + Potd_pad2(d)
end function

function Potd_pad2(n as integer) as string
    s = StrI(n).Trim()
    if Len(s) < 2 then s = "0" + s
    return s
end function

' {url, credit, portrait} or invalid when there is no usable still image.
function Potd_parse(json as dynamic) as dynamic
    if type(json) <> "roAssociativeArray" or type(json.image) <> "roAssociativeArray" then return invalid
    img = json.image
    if img.image = invalid or img.thumbnail = invalid then return invalid
    w = img.image.width
    h = img.image.height
    if w = invalid or h = invalid or w <= 0 or h <= 0 then return invalid
    portrait = h > w
    target = 1920
    if portrait then target = 1280

    url = ""
    thumb = Potd_stripQuery(img.thumbnail.source)
    slash = Potd_lastSlash(thumb)
    px = Instr(slash, thumb, "px-")
    if w > target and slash > 0 and px > slash then
        url = Left(thumb, slash) + StrI(target).Trim() + Mid(thumb, px)
    else
        url = Potd_stripQuery(img.image.source)
    end if
    ext = LCase(Mid(url, Potd_lastDot(url)))
    if ext <> ".jpg" and ext <> ".jpeg" and ext <> ".png" then return invalid

    credit = ""
    if img.artist <> invalid and img.artist.text <> invalid then credit = img.artist.text
    if img.license <> invalid and img.license.type <> invalid then
        if credit <> "" then credit = credit + " · "
        credit = credit + img.license.type
    end if
    if credit <> "" then credit = "Photo: " + credit + " · Wikimedia Commons"
    return { url: url, credit: credit, portrait: portrait }
end function

function Potd_stripQuery(u as dynamic) as string
    if u = invalid then return ""
    q = Instr(1, u, "?")
    if q > 0 then return Left(u, q - 1)
    return u
end function

function Potd_lastSlash(s as string) as integer
    last = 0
    p = Instr(1, s, "/")
    while p > 0
        last = p
        p = Instr(p + 1, s, "/")
    end while
    return last
end function

function Potd_lastDot(s as string) as integer
    last = Len(s) + 1
    p = Instr(1, s, ".")
    while p > 0
        last = p
        p = Instr(p + 1, s, ".")
    end while
    return last
end function
