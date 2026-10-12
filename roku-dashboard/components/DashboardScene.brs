' Refresh cadence, in minutes.
function Refresh() as object
    return { weather: 30, alerts: 5, feeds: 20, holidays: 1440 }
end function

sub init()
    m.settings = Settings_load()
    m.cats = Settings_idSet(m.settings.cats)
    m.holidays = loadHolidays()
    m.todays = []
    m.holidayIndex = 0
    m.headlines = []
    m.headlineIndex = 0
    m.tasks = {}
    m.driftStep = 0
    m.minutes = 0
    m.lastMinute = -1
    m.lastDay = ""
    m.dt = CreateObject("roDateTime")

    for each id in ["bg", "bgFill", "bgSolid", "content", "clock", "ampm", "date", "wxIcon", "wxTemp",
            "wxText", "wxPlace", "wxPeriods", "holiday", "holidayName", "holidayCount", "alertBar",
            "alertText", "tickerSource", "tickerText", "credit", "dim"]
        m[id] = m.top.FindNode(id)
    end for

    m.bg.ObserveField("loadStatus", "onBgLoad")
    m.top.FindNode("clockTimer").ObserveField("fire", "onTick")
    m.top.FindNode("minuteTimer").ObserveField("fire", "onMinute")
    m.top.FindNode("rotateTimer").ObserveField("fire", "onRotate")
    m.top.FindNode("clockTimer").control = "start"
    m.top.FindNode("minuteTimer").control = "start"
    m.top.FindNode("rotateTimer").control = "start"

    onTick()
    applyNightDim()
    if m.settings.lat = "" then
        m.wxText.text = "Set your ZIP code in screensaver settings"
    else
        refreshWeather()
        refreshAlerts()
    end if
    refreshFeeds()
    if Config().holidaysUrl <> "" then startFetch("holidays", { url: Config().holidaysUrl })
end sub

' --- clock and date ---------------------------------------------------------------------

sub onTick()
    m.dt.Mark()
    m.dt.ToLocalTime()
    minute = m.dt.GetMinutes()
    if minute <> m.lastMinute then
        m.lastMinute = minute
        parts = Clock_parts(m.dt.GetHours(), minute, m.settings.clock24)
        m.clock.text = parts[0] + ":" + parts[1]
        m.ampm.text = parts[2]
        ' Labels without a width size to their text; tuck AM/PM against the digits.
        m.ampm.translation = [120 + m.clock.boundingRect().width + 18, 212]
    end if
    y = m.dt.GetYear()
    mo = m.dt.GetMonth()
    d = m.dt.GetDayOfMonth()
    day = StrI(y).Trim() + "-" + StrI(mo).Trim() + "-" + StrI(d).Trim()
    if day <> m.lastDay then
        m.lastDay = day
        m.date.text = Date_label(y, mo, d)
        m.todays = Holidays_forDate(m.holidays, y, mo, d, m.cats)
        m.holidayIndex = 0
        showHoliday()
        if m.settings.background = "potd" then startFetch("potd", { y: y, m: mo, d: d })
    end if
end sub

sub onMinute()
    m.minutes = m.minutes + 1
    m.driftStep = m.driftStep + 1
    m.content.translation = Drift_offset(m.driftStep)
    applyNightDim()
    r = Refresh()
    if m.settings.lat <> "" then
        if m.minutes mod r.weather = 0 then refreshWeather()
        if m.minutes mod r.alerts = 0 then refreshAlerts()
    end if
    if m.minutes mod r.feeds = 0 then refreshFeeds()
    if m.minutes mod r.holidays = 0 and Config().holidaysUrl <> "" then
        startFetch("holidays", { url: Config().holidaysUrl })
    end if
end sub

sub applyNightDim()
    m.dt.Mark()
    m.dt.ToLocalTime()
    if m.settings.dimAtNight and Is_nightHour(m.dt.GetHours()) then
        m.dim.opacity = 0.55
    else
        m.dim.opacity = 0
    end if
end sub

sub onRotate()
    if m.headlines.Count() > 1 then
        m.headlineIndex = (m.headlineIndex + 1) mod m.headlines.Count()
        showHeadline()
    end if
    if m.todays.Count() > 1 then
        m.holidayIndex = (m.holidayIndex + 1) mod m.todays.Count()
        showHoliday()
    end if
end sub

' --- holidays -----------------------------------------------------------------------------

' The hosted copy (saved by FetchTask) wins over the built-in list when it parses.
function loadHolidays() as object
    for each path in ["cachefs:/holidays.json", "pkg:/data/holidays.json"]
        json = ParseJson(ReadAsciiFile(path))
        if json <> invalid and type(json.holidays) = "roArray" and json.holidays.Count() > 0 then
            return json.holidays
        end if
    end for
    return []
end function

sub showHoliday()
    if m.todays.Count() = 0 then
        m.holiday.visible = false
        return
    end if
    m.holiday.visible = true
    m.holidayName.text = m.todays[m.holidayIndex].name
    if m.todays.Count() > 1 then
        m.holidayCount.text = StrI(m.holidayIndex + 1).Trim() + " of " + StrI(m.todays.Count()).Trim()
    else
        m.holidayCount.text = ""
    end if
end sub

' --- network ------------------------------------------------------------------------------

sub refreshWeather()
    startFetch("weather", { lat: m.settings.lat, lon: m.settings.lon })
end sub

sub refreshAlerts()
    startFetch("alerts", { lat: m.settings.lat, lon: m.settings.lon })
end sub

sub refreshFeeds()
    chosen = Settings_idSet(m.settings.feeds)
    urls = []
    names = []
    for each f in Feed_presets()
        if chosen.DoesExist(f.id) then
            urls.Push(f.url)
            names.Push(f.title)
        end if
    end for
    if urls.Count() = 0 then return
    startFetch("feeds", { urls: urls, names: names })
end sub

' One request per kind at a time; a slow request is not doubled up.
sub startFetch(kind as string, params as object)
    if m.tasks[kind] <> invalid then return
    t = CreateObject("roSGNode", "FetchTask")
    t.kind = kind
    t.params = params
    t.ObserveField("result", "onFetch")
    m.tasks[kind] = t
    t.control = "run"
end sub

sub onFetch(event as object)
    r = event.GetData()
    m.tasks[r.kind] = invalid
    if not r.ok then
        if r.kind = "weather" and m.wxTemp.text = "" then m.wxText.text = "Weather unavailable"
        return
    end if
    if r.kind = "weather" then
        showWeather(r.data)
    else if r.kind = "alerts" then
        showAlerts(r.data)
    else if r.kind = "feeds" then
        m.headlines = r.data
        m.headlineIndex = 0
        showHeadline()
    else if r.kind = "potd" then
        m.credit.text = r.data.credit
        m.bg.uri = r.data.url
        if r.data.portrait then m.bgFill.uri = r.data.url else m.bgFill.uri = ""
    else if r.kind = "holidays" then
        m.holidays = r.data
        m.lastDay = ""
        onTick()
    end if
end sub

' --- rendering ----------------------------------------------------------------------------

sub showWeather(w as object)
    units = m.settings.units
    m.wxTemp.text = Weather_formatTemp(w.now.temp, w.now.unit, units)
    m.wxText.text = w.now.text
    m.wxPlace.text = w.place
    m.wxIcon.uri = Weather_iconUrl(w.now.icon)
    m.wxPeriods.RemoveChildrenIndex(m.wxPeriods.GetChildCount(), 0)
    for each p in w.periods
        col = CreateObject("roSGNode", "Group")
        name = col.CreateChild("Label")
        name.width = 210
        name.text = p.name
        name.color = "0xFFFFFF99"
        name.font = "font:SmallSystemFont"
        temp = col.CreateChild("Label")
        temp.translation = [0, 36]
        temp.text = Weather_formatTemp(p.temp, p.unit, units)
        temp.font = "font:MediumBoldSystemFont"
        text = col.CreateChild("Label")
        text.translation = [0, 84]
        text.width = 210
        text.wrap = true
        text.maxLines = 2
        text.text = p.text
        text.font = "font:SmallestSystemFont"
        text.color = "0xFFFFFFCC"
        m.wxPeriods.AppendChild(col)
    end for
end sub

sub showAlerts(alerts as object)
    if alerts.Count() = 0 then
        m.alertBar.visible = false
        return
    end if
    a = alerts[0]
    if a.severity = "Moderate" then m.alertBar.color = "0xB26A00EE" else m.alertBar.color = "0xB3261EEE"
    text = a.event
    if alerts.Count() > 1 then text = text + "  (+" + StrI(alerts.Count() - 1).Trim() + " more)"
    ' Plain text: the system fonts don't reliably carry symbol glyphs like a warning sign.
    m.alertText.text = "WEATHER ALERT:  " + UCase(text)
    m.alertBar.visible = true
end sub

sub showHeadline()
    if m.headlines.Count() = 0 then return
    h = m.headlines[m.headlineIndex]
    m.tickerSource.text = UCase(h.source)
    m.tickerText.text = h.title
end sub

sub onBgLoad()
    if m.bg.loadStatus = "ready" then
        m.bg.opacity = 1
        if m.bgFill.uri <> "" then m.bgFill.opacity = 0.35 else m.bgFill.opacity = 0
    else if m.bg.loadStatus = "failed" then
        m.bg.opacity = 0
        m.bgFill.opacity = 0
        m.credit.text = ""
    end if
end sub
