sub init()
    m.settings = Settings_load()
    m.menu = m.top.FindNode("menu")
    m.checkPane = m.top.FindNode("checkPane")
    m.checkTitle = m.top.FindNode("checkTitle")
    m.checks = m.top.FindNode("checks")
    m.checkKey = ""
    m.checkOptions = []
    m.menu.ObserveField("itemSelected", "onMenuSelected")
    buildMenu(0)
    m.menu.SetFocus(true)
end sub

sub buildMenu(focus as integer)
    s = m.settings
    zip = "not set"
    if s.zip <> "" then zip = s.zip
    clock = "12-hour"
    if s.clock24 then clock = "24-hour"
    bg = "Picture of the day (Wikimedia)"
    if s.background = "solid" then bg = "Solid color"
    dimText = "Off"
    if s.dimAtNight then dimText = "On"
    items = [
        "ZIP code (for weather):  " + zip
        "Clock:  " + clock
        "Temperature:  " + Chr(176) + s.units
        "Background:  " + bg
        "Dim at night (10 pm - 6 am):  " + dimText
        "News feeds:  " + countLabel(s.feeds, Feed_presets())
        "Holiday categories:  " + countLabel(s.cats, Holiday_categories())
    ]
    content = CreateObject("roSGNode", "ContentNode")
    for each t in items
        content.CreateChild("ContentNode").title = t
    end for
    m.menu.content = content
    m.menu.jumpToItem = focus
end sub

function countLabel(csv as string, options as object) as string
    n = Settings_idSet(csv).Count()
    if n = 0 then return "none"
    if n = options.Count() then return "all"
    return StrI(n).Trim() + " of " + StrI(options.Count()).Trim()
end function

sub onMenuSelected()
    i = m.menu.itemSelected
    s = m.settings
    if i = 0 then
        askZip()
        return
    else if i = 1 then
        s.clock24 = not s.clock24
    else if i = 2 then
        if s.units = "F" then s.units = "C" else s.units = "F"
    else if i = 3 then
        if s.background = "potd" then s.background = "solid" else s.background = "potd"
    else if i = 4 then
        s.dimAtNight = not s.dimAtNight
    else if i = 5 then
        openChecks("feeds", "News feeds", Feed_presets())
        return
    else if i = 6 then
        openChecks("cats", "Holiday categories", Holiday_categories())
        return
    end if
    Settings_save(s)
    buildMenu(i)
end sub

' --- ZIP entry ----------------------------------------------------------------------------

sub askZip()
    dlg = CreateObject("roSGNode", "StandardKeyboardDialog")
    dlg.title = "Enter your 5-digit US ZIP code"
    dlg.buttons = ["OK", "Cancel"]
    dlg.text = m.settings.zip
    dlg.ObserveField("buttonSelected", "onZipButton")
    m.top.dialog = dlg
end sub

sub onZipButton()
    dlg = m.top.dialog
    ok = dlg.buttonSelected = 0
    zip = dlg.text.Trim()
    dlg.close = true
    if not ok then return
    loc = Zip_find(zip)
    if loc = invalid then
        showMessage("ZIP not found", ["Weather needs a US ZIP code. PO-box-only ZIPs aren't in the map data; try your street ZIP or a nearby one."])
        return
    end if
    m.settings.zip = zip
    m.settings.lat = loc.lat
    m.settings.lon = loc.lon
    Settings_save(m.settings)
    buildMenu(0)
end sub

sub showMessage(title as string, lines as object)
    dlg = CreateObject("roSGNode", "StandardMessageDialog")
    dlg.title = title
    dlg.message = lines
    dlg.buttons = ["OK"]
    dlg.ObserveField("buttonSelected", "onMessageButton")
    m.top.dialog = dlg
end sub

sub onMessageButton()
    m.top.dialog.close = true
end sub

' --- multi-select lists (feeds, holiday categories) ----------------------------------------

sub openChecks(key as string, title as string, options as object)
    m.checkKey = key
    m.checkOptions = options
    chosen = Settings_idSet(m.settings[key])
    content = CreateObject("roSGNode", "ContentNode")
    state = []
    for each o in options
        content.CreateChild("ContentNode").title = o.title
        state.Push(chosen.DoesExist(o.id))
    end for
    m.checkTitle.text = title + "  (OK to toggle, Back when done)"
    m.checks.content = content
    m.checks.checkedState = state
    m.menu.visible = false
    m.checkPane.visible = true
    m.checks.SetFocus(true)
end sub

sub closeChecks()
    state = m.checks.checkedState
    chosen = {}
    for i = 0 to m.checkOptions.Count() - 1
        if state[i] then chosen[m.checkOptions[i].id] = true
    end for
    m.settings[m.checkKey] = Settings_idCsv(chosen, m.checkOptions)
    Settings_save(m.settings)
    focus = 5
    if m.checkKey = "cats" then focus = 6
    m.checkPane.visible = false
    m.menu.visible = true
    buildMenu(focus)
    m.menu.SetFocus(true)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press and key = "back" and m.checkPane.visible then
        closeChecks()
        return true
    end if
    return false
end function
