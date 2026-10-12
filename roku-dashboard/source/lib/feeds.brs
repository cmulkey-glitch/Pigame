' News feed presets and a tolerant headline extractor for RSS 2.0 and Atom. It scans text
' instead of using roXMLElement: real feeds are often not well-formed XML, and only the item
' titles are needed.

function Feed_presets() as object
    return [
        { id: "bbc", title: "BBC News", url: "https://feeds.bbci.co.uk/news/rss.xml" }
        { id: "nyt", title: "New York Times", url: "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml" }
        { id: "npr", title: "NPR News", url: "https://feeds.npr.org/1001/rss.xml" }
        { id: "espn", title: "ESPN", url: "https://www.espn.com/espn/rss/news" }
        { id: "verge", title: "The Verge", url: "https://www.theverge.com/rss/index.xml" }
        { id: "hn", title: "Hacker News", url: "https://hnrss.org/frontpage" }
        { id: "nasa", title: "NASA", url: "https://www.nasa.gov/news-release/feed/" }
    ]
end function

' Up to max headline strings from an RSS or Atom document.
function Feed_parseTitles(text as string, max as integer) as object
    out = []
    itemTag = "item"
    if Instr(1, text, "<item") = 0 then itemTag = "entry"
    at = 1
    while out.Count() < max
        start = Feed_findTag(text, itemTag, at)
        if start = 0 then exit while
        finish = Instr(start, text, "</" + itemTag + ">")
        if finish = 0 then finish = Len(text)
        item = Mid(text, start, finish - start)
        title = Feed_tagText(item, "title")
        if title <> "" then out.Push(title)
        at = finish + 1
    end while
    return out
end function

' Position of the next "<tag>" or "<tag ..." (not "<tagother"), or 0.
function Feed_findTag(text as string, tag as string, from as integer) as integer
    at = from
    while true
        p = Instr(at, text, "<" + tag)
        if p = 0 then return 0
        c = Mid(text, p + Len(tag) + 1, 1)
        if c = ">" or c = " " or c = Chr(9) or c = Chr(10) or c = Chr(13) or c = "/" then return p
        at = p + 1
    end while
    return 0
end function

' Decoded, whitespace-collapsed text of the first <tag> in s, or "".
function Feed_tagText(s as string, tag as string) as string
    p = Feed_findTag(s, tag, 1)
    if p = 0 then return ""
    open = Instr(p, s, ">")
    if open = 0 or Mid(s, open - 1, 1) = "/" then return ""
    close = Instr(open, s, "</" + tag)
    if close = 0 then return ""
    raw = Mid(s, open + 1, close - open - 1)
    cdata = Instr(1, raw, "<![CDATA[")
    if cdata > 0 then
        endData = Instr(cdata, raw, "]]>")
        if endData = 0 then endData = Len(raw) + 1
        raw = Mid(raw, cdata + 9, endData - cdata - 9)
    end if
    return Feed_cleanText(raw)
end function

' Strips tags, decodes common entities, collapses whitespace.
function Feed_cleanText(s as string) as string
    out = ""
    inTag = false
    for i = 1 to Len(s)
        c = Mid(s, i, 1)
        if c = "<" then
            inTag = true
        else if c = ">" and inTag then
            inTag = false
        else if not inTag then
            if c = Chr(9) or c = Chr(10) or c = Chr(13) then c = " "
            out = out + c
        end if
    end for
    out = Feed_decodeEntities(out)
    while Instr(1, out, "  ") > 0
        out = out.Replace("  ", " ")
    end while
    return out.Trim()
end function

function Feed_decodeEntities(s as string) as string
    if Instr(1, s, "&") = 0 then return s
    named = { "amp": "&", "lt": "<", "gt": ">", "quot": Chr(34), "apos": "'", "nbsp": " ",
        "rsquo": Chr(8217), "lsquo": Chr(8216), "ldquo": Chr(8220), "rdquo": Chr(8221),
        "mdash": Chr(8212), "ndash": Chr(8211), "hellip": Chr(8230) }
    out = ""
    i = 1
    n = Len(s)
    while i <= n
        c = Mid(s, i, 1)
        semi = 0
        if c = "&" then semi = Instr(i, s, ";")
        if semi > 0 and semi - i <= 10 then
            name = Mid(s, i + 1, semi - i - 1)
            rep = invalid
            if Left(name, 1) = "#" then
                if LCase(Mid(name, 2, 1)) = "x" then
                    code = Feed_hexValue(Mid(name, 3))
                else
                    code = Val(Mid(name, 2), 10)
                end if
                if code > 0 then rep = Chr(code)
            else if named.DoesExist(LCase(name)) then
                rep = named[LCase(name)]
            end if
            if rep <> invalid then
                out = out + rep
                i = semi + 1
            else
                out = out + c
                i = i + 1
            end if
        else
            out = out + c
            i = i + 1
        end if
    end while
    return out
end function

function Feed_hexValue(h as string) as integer
    v = 0
    for i = 1 to Len(h)
        d = Instr(1, "0123456789abcdef", LCase(Mid(h, i, 1)))
        if d = 0 then return 0
        v = v * 16 + d - 1
    end for
    return v
end function

' Round-robin merge of per-feed headline lists into [{title, source}], so one busy feed
' doesn't crowd out the rest.
function Feed_interleave(perFeed as object) as object
    out = []
    i = 0
    more = true
    while more
        more = false
        for each f in perFeed
            if i < f.titles.Count() then
                out.Push({ title: f.titles[i], source: f.source })
                more = true
            end if
        end for
        i = i + 1
    end while
    return out
end function
