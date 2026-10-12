sub init()
    m.top.functionName = "fetchMain"
end sub

sub fetchMain()
    kind = m.top.kind
    p = m.top.params
    data = invalid
    if kind = "weather" then
        data = fetchWeather(p.lat, p.lon)
    else if kind = "alerts" then
        data = Weather_parseAlerts(getJson(Weather_alertsUrl(p.lat, p.lon)))
    else if kind = "feeds" then
        data = fetchFeeds(p.urls, p.names)
    else if kind = "potd" then
        data = Potd_parse(getJson(Potd_feedUrl(p.y, p.m, p.d)))
    else if kind = "holidays" then
        data = fetchHolidays(p.url)
    end if
    m.top.result = { kind: kind, ok: data <> invalid, data: data }
end sub

' {place, now: period, periods: [3 periods]}
function fetchWeather(lat as string, lon as string) as dynamic
    points = Weather_parsePoints(getJson(Weather_pointsUrl(lat, lon)))
    if points = invalid then return invalid
    periods = Weather_parsePeriods(getJson(points.forecast), 3)
    hourly = Weather_parsePeriods(getJson(points.hourly), 1)
    if periods = invalid or periods.Count() = 0 then return invalid
    now = periods[0]
    if hourly <> invalid and hourly.Count() > 0 then now = hourly[0]
    return { place: points.place, now: now, periods: periods }
end function

function fetchFeeds(urls as object, names as object) as dynamic
    perFeed = []
    for i = 0 to urls.Count() - 1
        body = getText(urls[i])
        if body <> "" then perFeed.Push({ source: names[i], titles: Feed_parseTitles(body, 8) })
    end for
    if perFeed.Count() = 0 then return invalid
    return Feed_interleave(perFeed)
end function

' Saves a hosted holiday list to cachefs: when it parses; the scene prefers that copy.
function fetchHolidays(url as string) as dynamic
    body = getText(url)
    json = ParseJson(body)
    if json = invalid or type(json.holidays) <> "roArray" or json.holidays.Count() = 0 then return invalid
    WriteAsciiFile("cachefs:/holidays.json", body)
    return json.holidays
end function

function getJson(url as string) as dynamic
    body = getText(url)
    if body = "" then return invalid
    return ParseJson(body)
end function

' Body of a 200 response, or "" on any failure (15 s timeout).
function getText(url as string) as string
    port = CreateObject("roMessagePort")
    xfer = CreateObject("roUrlTransfer")
    xfer.SetMessagePort(port)
    xfer.SetUrl(url)
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.InitClientCertificates()
    xfer.AddHeader("User-Agent", Config().userAgent)
    xfer.EnableEncodings(true)
    xfer.RetainBodyOnError(false)
    if not xfer.AsyncGetToString() then return ""
    msg = wait(15000, port)
    if type(msg) <> "roUrlEvent" then
        xfer.AsyncCancel()
        return ""
    end if
    if msg.GetResponseCode() <> 200 then return ""
    return msg.GetString()
end function
