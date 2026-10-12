' Parsers for the National Weather Service API (api.weather.gov): free, no key, US only.
' Flow: /points/{lat},{lon} gives the forecast URLs and place name; /alerts/active?point=
' gives active alerts. Each parser takes the decoded JSON and returns invalid on bad input.

function Weather_pointsUrl(lat as string, lon as string) as string
    return "https://api.weather.gov/points/" + lat + "," + lon
end function

function Weather_alertsUrl(lat as string, lon as string) as string
    return "https://api.weather.gov/alerts/active?point=" + lat + "," + lon
end function

' {forecast, hourly, place}
function Weather_parsePoints(json as dynamic) as dynamic
    if type(json) <> "roAssociativeArray" or type(json.properties) <> "roAssociativeArray" then return invalid
    p = json.properties
    if p.forecast = invalid or p.forecastHourly = invalid then return invalid
    place = ""
    rl = p.relativeLocation
    if rl <> invalid and rl.properties <> invalid and rl.properties.city <> invalid then
        place = rl.properties.city
        if rl.properties.state <> invalid then place = place + ", " + rl.properties.state
    end if
    return { forecast: p.forecast, hourly: p.forecastHourly, place: place }
end function

' Periods from /forecast or /forecast/hourly: [{name, temp, unit, text, icon, isDaytime}]
function Weather_parsePeriods(json as dynamic, max as integer) as dynamic
    if type(json) <> "roAssociativeArray" or json.properties = invalid then return invalid
    periods = json.properties.periods
    if type(periods) <> "roArray" then return invalid
    out = []
    for each p in periods
        if out.Count() >= max then exit for
        out.Push({ name: p.name, temp: p.temperature, unit: p.temperatureUnit,
            text: p.shortForecast, icon: p.icon, isDaytime: p.isDaytime })
    end for
    return out
end function

' Alerts worth a banner, most severe first: [{event, severity, headline}].
' Minor and Unknown severities are dropped.
function Weather_parseAlerts(json as dynamic) as dynamic
    if type(json) <> "roAssociativeArray" or type(json.features) <> "roArray" then return invalid
    rank = { "Extreme": 0, "Severe": 1, "Moderate": 2 }
    buckets = [[], [], []]
    for each f in json.features
        p = f.properties
        if p <> invalid and p.severity <> invalid and rank.DoesExist(p.severity) then
            buckets[rank[p.severity]].Push({ event: p.event, severity: p.severity, headline: p.headline })
        end if
    end for
    out = []
    for each b in buckets
        out.Append(b)
    end for
    return out
end function

' Temperature string in the chosen units ("F" or "C"). NWS reports Fahrenheit.
function Weather_formatTemp(temp as dynamic, unit as dynamic, want as string) as string
    if temp = invalid then return "--"
    t = temp
    if unit = "F" and want = "C" then t = (temp - 32) * 5 / 9
    if unit = "C" and want = "F" then t = temp * 9 / 5 + 32
    ' Int is floor, so this rounds half up for negatives too (-39.5 -> -39, -40.0 -> -40).
    return StrI(Int(t + 0.5)).Trim() + Chr(176)
end function

' NWS icon URLs end in "?size=medium"; ask for the large variant for a TV.
function Weather_iconUrl(icon as dynamic) as string
    if icon = invalid then return ""
    return icon.Replace("size=medium", "size=large").Replace("size=small", "size=large")
end function
