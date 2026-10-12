' App constants, saved settings, and small display helpers.

function Config() as object
    return {
        ' NWS and Wikimedia ask every client to identify itself with a contact address.
        ' TODO: put a real contact (email or project URL) here before publishing.
        userAgent: "LivingRoomDashboard/0.1 (contact: CHANGE-ME@example.com)"
        ' Optional: a hosted copy of data/holidays.json (e.g. on GitHub Pages) checked once a
        ' day, so holiday fixes ship without a new app version. Empty = built-in list only.
        holidaysUrl: ""
    }
end function

function Settings_defaults() as object
    return {
        zip: "", lat: "", lon: "", place: ""
        clock24: false
        units: "F"            ' "F" or "C"
        background: "potd"    ' "potd" or "solid"
        dimAtNight: true      ' 10 pm - 6 am
        feeds: "bbc,nyt,hn"   ' Feed_presets ids
        cats: "food,animals,silly,awareness,official,cultural"
    }
end function

function Settings_load() as object
    s = Settings_defaults()
    sec = CreateObject("roRegistrySection", "dashboard")
    for each k in s.Keys()
        if sec.Exists(k) then
            v = sec.Read(k)
            if type(s[k]) = "roBoolean" or type(s[k]) = "Boolean" then
                s[k] = (v = "true")
            else
                s[k] = v
            end if
        end if
    end for
    return s
end function

sub Settings_save(s as object)
    sec = CreateObject("roRegistrySection", "dashboard")
    for each k in s
        v = s[k]
        if type(v) = "roBoolean" or type(v) = "Boolean" then
            if v then v = "true" else v = "false"
        end if
        sec.Write(k, v)
    end for
    sec.Flush()
end sub

' "a,b" -> {a: true, b: true}
function Settings_idSet(csv as string) as object
    out = {}
    for each id in csv.Split(",")
        if id <> "" then out[id] = true
    end for
    return out
end function

' {a: true, b: true} in the order of options (an array of {id}) -> "a,b"
function Settings_idCsv(set as object, options as object) as string
    out = ""
    for each o in options
        if set.DoesExist(o.id) then
            if out <> "" then out = out + ","
            out = out + o.id
        end if
    end for
    return out
end function

' ["7", "05", "PM"] for 12-hour, ["19", "05", ""] for 24-hour.
function Clock_parts(h as integer, mi as integer, use24 as boolean) as object
    mm = StrI(mi).Trim()
    if mi < 10 then mm = "0" + mm
    if use24 then
        hh = StrI(h).Trim()
        if h < 10 then hh = "0" + hh
        return [hh, mm, ""]
    end if
    suffix = "AM"
    if h >= 12 then suffix = "PM"
    h12 = h mod 12
    if h12 = 0 then h12 = 12
    return [StrI(h12).Trim(), mm, suffix]
end function

function Date_label(y as integer, mo as integer, d as integer) as string
    days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    months = ["January", "February", "March", "April", "May", "June", "July", "August",
        "September", "October", "November", "December"]
    return days[DayOfWeek(y, mo, d)] + ", " + months[mo - 1] + " " + StrI(d).Trim()
end function

' Burn-in protection: the whole layout walks a small loop, one step per minute, so no pixel
' stays lit by the same edge for long. Max 24 px, inside the 96 px action-safe margin.
function Drift_offset(n as integer) as object
    path = [[0, 0], [12, 6], [24, 0], [12, -6], [0, -12], [-12, -6], [-24, 0], [-12, 6]]
    return path[n mod path.Count()]
end function

function Is_nightHour(h as integer) as boolean
    return h >= 22 or h < 6
end function

' US ZIP -> {lat, lon} from the bundled Census ZCTA table (data/zip/NNN.csv, one file per
' 3-digit prefix, lines "LL,lat,lon"). Returns invalid for unknown ZIPs (PO-box-only ZIPs
' have no ZCTA; the user can enter a nearby ZIP).
function Zip_find(zip as string) as dynamic
    if not Zip_isValid(zip) then return invalid
    return Zip_lookup(zip, ReadAsciiFile("pkg:/data/zip/" + Left(zip, 3) + ".csv"))
end function

function Zip_isValid(zip as string) as boolean
    if Len(zip) <> 5 then return false
    for i = 1 to 5
        if Instr(1, "0123456789", Mid(zip, i, 1)) = 0 then return false
    end for
    return true
end function

function Zip_lookup(zip as string, table as string) as dynamic
    if table = "" then return invalid
    key = Right(zip, 2) + ","
    for each line in table.Split(Chr(10))
        if Left(line, 3) = key then
            parts = line.Split(",")
            if parts.Count() = 3 then return { lat: parts[1].Trim(), lon: parts[2].Trim() }
        end if
    end for
    return invalid
end function
