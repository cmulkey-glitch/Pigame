' Off-device checks for the pure logic in source/lib. Fixtures in tests/fixtures are trimmed
' real responses (NWS, Wikipedia, BBC RSS, The Verge Atom) captured 2026-10-12. Feeds are .rss/.atom,
' not .xml: brs loads every .xml under the root as a SceneGraph component.
' Run: node roku-dashboard/tools/test.mjs

sub Main()
    fails = 0
    fails = fails + TestCalendar()
    fails = fails + TestHolidays()
    fails = fails + TestFeeds()
    fails = fails + TestWeather()
    fails = fails + TestPotd()
    fails = fails + TestSettings()
    if fails = 0 then print "ALL PASS" else print "FAILURES: "; fails
end sub

function Fixture(name as string) as string
    return ReadAsciiFile("pkg:/tests/fixtures/" + name)
end function

function Md(md as dynamic) as string
    if md = invalid then return "invalid"
    return StrI(md[0]).Trim() + "/" + StrI(md[1]).Trim()
end function

function Check(name as string, got as dynamic, want as dynamic) as integer
    if got = want then
        print "ok   "; name
        return 0
    end if
    print "FAIL "; name; ": got "; got; ", want "; want
    return 1
end function

function TestCalendar() as integer
    f = 0
    f = f + Check("2026-10-12 is a Monday", DayOfWeek(2026, 10, 12), 1)
    f = f + Check("2000-01-01 is a Saturday", DayOfWeek(2000, 1, 1), 6)
    f = f + Check("Easter 2000", Md(EasterDate(2000)), "4/23")
    f = f + Check("Easter 2024", Md(EasterDate(2024)), "3/31")
    f = f + Check("Easter 2025", Md(EasterDate(2025)), "4/20")
    f = f + Check("Easter 2026", Md(EasterDate(2026)), "4/5")
    f = f + Check("Easter 2038", Md(EasterDate(2038)), "4/25")
    f = f + Check("day 256 of 2026", Md(DateFromDayOfYear(2026, 256)), "9/13")
    f = f + Check("day 256 of 2024 (leap)", Md(DateFromDayOfYear(2024, 256)), "9/12")
    f = f + Check("3rd Sunday of July 2026", NthWeekday(2026, 7, 0, 3), 19)
    f = f + Check("last Monday of May 2026", LastWeekday(2026, 5, 1), 25)
    return f
end function

function TestHolidays() as integer
    f = 0
    list = ParseJson(ReadAsciiFile("pkg:/data/holidays.json")).holidays
    byName = {}
    for each h in list
        byName[h.name] = h
    end for
    f = f + Check("Ice Cream Day 2025", Md(Holiday_resolve(byName["National Ice Cream Day"], 2025)), "7/20")
    f = f + Check("Ice Cream Day 2026", Md(Holiday_resolve(byName["National Ice Cream Day"], 2026)), "7/19")
    f = f + Check("Thanksgiving 2026", Md(Holiday_resolve(byName["Thanksgiving"], 2026)), "11/26")
    f = f + Check("Black Friday 2026", Md(Holiday_resolve(byName["Black Friday"], 2026)), "11/27")
    f = f + Check("Election Day 2026", Md(Holiday_resolve(byName["Election Day"], 2026)), "11/3")
    f = f + Check("Mardi Gras 2026", Md(Holiday_resolve(byName["Mardi Gras"], 2026)), "2/17")
    f = f + Check("Memorial Day 2026", Md(Holiday_resolve(byName["Memorial Day"], 2026)), "5/25")
    f = f + Check("Programmers' Day 2024", Md(Holiday_resolve(byName["Programmers' Day"], 2024)), "9/12")
    f = f + Check("no Leap Day in 2026", Md(Holiday_resolve(byName["Leap Day"], 2026)), "invalid")
    f = f + Check("Leap Day 2028", Md(Holiday_resolve(byName["Leap Day"], 2028)), "2/29")

    all = Settings_idSet(Settings_defaults().cats)
    today = Holidays_forDate(list, 2026, 10, 12, all)
    f = f + Check("2026-10-12 has one holiday", today.Count(), 1)
    f = f + Check("2026-10-12 is Columbus Day", today[0].name, "Columbus Day / Indigenous Peoples' Day")
    f = f + Check("category filter", Holidays_forDate(list, 2026, 10, 12, { food: true }).Count(), 0)
    f = f + Check("2026-10-04 has two", Holidays_forDate(list, 2026, 10, 4, all).Count(), 2)

    ' Every entry has a known category and resolves to a real date in each year it occurs.
    cats = {}
    for each c in Holiday_categories()
        cats[c.id] = true
    end for
    bad = ""
    for y = 2024 to 2032
        for each h in list
            md = Holiday_resolve(h, y)
            if not cats.DoesExist(h.cat) then bad = h.name + " (category)"
            if md = invalid and h.name <> "Leap Day" then bad = h.name
            if md <> invalid then
                if md[0] < 1 or md[0] > 12 or md[1] < 1 or md[1] > DaysInMonth(y, md[0]) then bad = h.name
            end if
        end for
    end for
    f = f + Check("every holiday resolves 2024-2032", bad, "")
    return f
end function

function TestFeeds() as integer
    f = 0
    bbc = Feed_parseTitles(Fixture("bbc.rss"), 8)
    f = f + Check("BBC RSS item count", bbc.Count(), 3)
    f = f + Check("BBC first title (CDATA, not channel title)", bbc[0], "Burnham to push for new post-Brexit deals at EU summit")
    verge = Feed_parseTitles(Fixture("verge.atom"), 8)
    f = f + Check("Verge Atom entry count", verge.Count(), 3)
    f = f + Check("Verge Atom first title trimmed", verge[0], "Meta has some Wonder Full new AI models")
    f = f + Check("Atom curly quote kept", verge[2], "The Yandex outage probably didn" + Chr(8217) + "t blitz Russian bots")
    f = f + Check("max limits titles", Feed_parseTitles(Fixture("bbc.rss"), 2).Count(), 2)

    rss = "<rss><channel><title>Feed</title><itemized>x</itemized><item><title>Tom &amp; Jerry&#8217;s "
    rss = rss + "&#x2014; &quot;big&quot;  " + Chr(10) + " day &bogus; &amp</title></item><item><title/></item></channel></rss>"
    got = Feed_parseTitles(rss, 8)
    f = f + Check("entities and whitespace", got[0], "Tom & Jerry" + Chr(8217) + "s " + Chr(8212) + " " + Chr(34) + "big" + Chr(34) + " day &bogus; &amp")
    f = f + Check("empty and look-alike tags skipped", got.Count(), 1)
    f = f + Check("tags stripped", Feed_cleanText("<b>Bold</b> move"), "Bold move")

    mixed = Feed_interleave([{ source: "A", titles: ["a1", "a2", "a3"] }, { source: "B", titles: ["b1"] }])
    f = f + Check("interleave order", mixed[0].title + mixed[1].title + mixed[2].title + mixed[3].title, "a1b1a2a3")
    return f
end function

function TestWeather() as integer
    f = 0
    pts = Weather_parsePoints(ParseJson(Fixture("nws_points.json")))
    f = f + Check("points place", pts.place, "New York, NY")
    f = f + Check("points forecast URL", Right(pts.forecast, 9), "/forecast")
    f = f + Check("points bad input", Weather_parsePoints(ParseJson("{}")), invalid)
    periods = Weather_parsePeriods(ParseJson(Fixture("nws_forecast.json")), 3)
    f = f + Check("forecast periods", periods.Count(), 3)
    f = f + Check("forecast temp unit", periods[0].unit, "F")
    alerts = Weather_parseAlerts(ParseJson(Fixture("nws_alerts.json")))
    f = f + Check("alerts drop Minor", alerts.Count(), 3)
    f = f + Check("alerts most severe first", alerts[0].severity, "Extreme")
    f = f + Check("alerts then Severe", alerts[1].severity, "Severe")
    f = f + Check("no alerts", Weather_parseAlerts(ParseJson("{""features"":[]}")).Count(), 0)
    f = f + Check("71F in C", Weather_formatTemp(71, "F", "C"), "22" + Chr(176))
    f = f + Check("-40F in C", Weather_formatTemp(-40, "F", "C"), "-40" + Chr(176))
    f = f + Check("F stays F", Weather_formatTemp(32, "F", "F"), "32" + Chr(176))
    f = f + Check("missing temp", Weather_formatTemp(invalid, "F", "F"), "--")
    f = f + Check("large icon", Weather_iconUrl("https://x/icons/land/day/sct?size=medium"), "https://x/icons/land/day/sct?size=large")
    return f
end function

function TestPotd() as integer
    f = 0
    p = Potd_parse(ParseJson(Fixture("potd_portrait.json")))
    f = f + Check("portrait detected", p.portrait, true)
    f = f + Check("portrait asks for 1280px", p.url, "https://thumb.wikimedia.org/wikipedia/commons/thumb/d/d1/Gotland_Grand_National_October_2023_12.jpg/1280px-Gotland_Grand_National_October_2023_12.jpg")
    f = f + Check("credit has license", Instr(1, p.credit, "CC BY-SA 4.0") > 0, true)

    wide = { image: { image: { source: "https://u/x/Big_view.jpg?utm=1", width: 6000, height: 3000 },
        thumbnail: { source: "https://t/thumb/a/ab/Big_view.jpg/960px-Big_view.jpg?utm=1" } } }
    f = f + Check("landscape asks for 1920px", Potd_parse(wide).url, "https://t/thumb/a/ab/Big_view.jpg/1920px-Big_view.jpg")
    small = { image: { image: { source: "https://u/x/Small.png", width: 800, height: 600 },
        thumbnail: { source: "https://t/thumb/Small.png/640px-Small.png" } } }
    f = f + Check("small image uses original", Potd_parse(small).url, "https://u/x/Small.png")
    svg = { image: { image: { source: "https://u/x/Map.svg", width: 800, height: 600 },
        thumbnail: { source: "https://t/thumb/Map.svg/640px-Map.svg.png" } } }
    f = f + Check("small SVG rejected", Potd_parse(svg), invalid)
    vid = { image: { image: { source: "https://u/x/Clip.webm", width: 4000, height: 2000 },
        thumbnail: { source: "https://t/thumb/Clip.webm/960px--Clip.webm.jpg" } } }
    f = f + Check("video still frame ok", Right(Potd_parse(vid).url, 4), ".jpg")
    f = f + Check("no image today", Potd_parse(ParseJson("{""tfa"":{}}")), invalid)
    f = f + Check("feed URL", Potd_feedUrl(2026, 3, 7), "https://en.wikipedia.org/api/rest_v1/feed/featured/2026/03/07")
    return f
end function

function TestSettings() as integer
    f = 0
    f = f + Check("12h midnight", Clock_parts(0, 5, false)[0] + Clock_parts(0, 5, false)[2], "12AM")
    f = f + Check("12h noon", Clock_parts(12, 0, false)[0] + ":" + Clock_parts(12, 0, false)[1] + Clock_parts(12, 0, false)[2], "12:00PM")
    f = f + Check("24h", Clock_parts(7, 9, true)[0] + ":" + Clock_parts(7, 9, true)[1], "07:09")
    f = f + Check("date label", Date_label(2026, 10, 12), "Monday, October 12")
    f = f + Check("csv keeps option order", Settings_idCsv({ hn: true, bbc: true }, Feed_presets()), "bbc,hn")
    f = f + Check("night 23h", Is_nightHour(23), true)
    f = f + Check("day 6h", Is_nightHour(6), false)
    worst = 0
    for i = 0 to 15
        o = Drift_offset(i)
        if Abs(o[0]) > worst then worst = Abs(o[0])
        if Abs(o[1]) > worst then worst = Abs(o[1])
    end for
    f = f + Check("drift stays within 24px", worst, 24)
    f = f + Check("ZIP 10001", Zip_find("10001").lat, "40.751")
    f = f + Check("ZIP 90210", Zip_find("90210").lon, "-118.415")
    f = f + Check("ZIP not numeric", Zip_find("9021a"), invalid)
    f = f + Check("ZIP too short", Zip_find("9021"), invalid)
    f = f + Check("ZIP unknown in a known prefix", Zip_find("10099"), invalid)
    return f
end function
