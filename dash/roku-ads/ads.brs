Library "Roku_Ads.brs"

' Ads for the ad-supported build (python3 dash/tools/build.py --ads), with the Roku Advertising
' Framework, which Roku requires for any ads. A break comes only after a level, spiral run or
' world is finished, never mid-run or after a crash, and at most one every Ads_gap() seconds
' (counting from launch, so a session never opens with an ad).
'
' No ad URL is set: RAF then serves Roku's own ads (test ads while sideloaded). For the 70% of
' inventory that is ours under Roku's default inventory split, SetAdUrl() takes a VAST tag
' from an ad network, when there is one.
'
' roScreen puts the display in game mode, where no other screen can show, so the screen is let
' go while RAF plays the ads and made again afterwards (App_screen_release / App_screen_new).
' PROTOTYPE: check on a device that ads play and the game comes back.

' Test builds (build.py --ads-test, manifest ads_test=1): a break every 30 seconds, ads from
' Google's public sample VAST tag (Roku's default ad server serves nothing to sideloaded apps),
' and what happened shown on the menu (app.adStatus) and printed to the debug console (port 8085).
function Ads_test() as boolean
    return CreateObject("roAppInfo").GetValue("ads_test") = "1"
end function

function Ads_gap() as integer
    if Ads_test() then return 30
    return 300
end function

function Ads_test_url() as string
    return "https://pubads.g.doubleclick.net/gampad/ads?iu=/21775744923/external/single_ad_samples&sz=640x480&cust_params=sample_ct%3Dlinear&ciu_szs=300x250%2C728x90&gdfp_req=1&output=vast&unviewed_position_start=1&env=vp&impl=s&correlator="
end function

sub Ads_init(app as object)
    app.adClock = CreateObject("roTimespan")
    app.adClock.Mark()
    app.adBreaks = 0
    raf = Roku_Ads()
    raf.SetDebugOutput(true)
    raf.SetAdPrefs(true, 2)
    ' Roku's ad measurement, required for US store apps that are not child-directed
    raf.SetContentId("spiral-shift")
    raf.SetContentGenre("Games")
    raf.EnableAdMeasurements(true)
    if Ads_test() then
        raf.SetAdUrl(Ads_test_url())
        ' how far the last run got, if it ended inside an ad break
        reg = CreateObject("roRegistrySection", "spiralshift_ads")
        ' the break count carries over, so a method that quits the app is not simply tried again
        if reg.Exists("breaks") then app.adBreaks = reg.Read("breaks").ToInt()
        if reg.Exists("crumb") then
            Ads_status(app, "last run's last ad step: " + reg.Read("crumb"))
            reg.Delete("crumb")
            reg.Flush()
        else
            Ads_status(app, "ads test build: a break after a finished level, every 30 s")
        end if
    end if
    app.raf = raf
end sub

sub Ads_status(app as object, text as string)
    print "ADS: " + text
    if Ads_test() then app.adStatus = text
end sub

' A step of an ad break, saved before it is taken: if the app quits there, the next launch of a
' test build shows it.
sub Ads_crumb(app as object, text as string)
    Ads_status(app, text)
    if Ads_test() then
        reg = CreateObject("roRegistrySection", "spiralshift_ads")
        reg.Write("crumb", text)
        reg.Flush()
    end if
end sub

' How an ad is shown over the game. A Roku app quits when its last screen closes, so the game's
' screen cannot simply be let go while RAF shows its own (the first device test did that, and
' the app quit when the ad ended). Under test, break by break in turn:
'   keep    the roScreen stays up while RAF plays
'   scene   a blank SceneGraph screen holds the app open (and is RAF's view); the roScreen is
'           let go and made again after
'   canvas  the same with a blank roImageCanvas (an old component; may be gone from the Roku)
function Ads_strategy(app as object) as string
    if not Ads_test() then return "keep"
    return ["canvas", "keep", "scene"][app.adBreaks mod 3]
end function

sub Ads_break(app as object)
    if app.raf = invalid then return
    wait = Ads_gap() - app.adClock.TotalSeconds()
    if wait > 0 then
        Ads_status(app, "no break yet: " + wait.ToStr() + " s to go")
        return
    end if
    app.adBreaks = app.adBreaks + 1
    if Ads_test() then
        reg = CreateObject("roRegistrySection", "spiralshift_ads")
        reg.Write("breaks", app.adBreaks.ToStr())
        reg.Flush()
    end if
    how = Ads_strategy(app)
    tag = "break " + app.adBreaks.ToStr() + " (" + how + "): "
    Ads_crumb(app, tag + "asking for ads")
    ads = app.raf.GetAds()
    if ads = invalid or ads.Count() = 0 then
        Ads_crumb(app, tag + "the ad server returned no ads")
        return
    end if
    app.music.Stop()
    facade = invalid
    view = invalid
    if how = "scene" then
        facade = CreateObject("roSGScreen")
        facade.SetMessagePort(CreateObject("roMessagePort"))
        view = facade.CreateScene("Scene")
        facade.Show()
        App_screen_release(app)
    else if how = "canvas" then
        facade = CreateObject("ro" + "ImageCanvas")     ' split: the compile check no longer knows it
        if facade = invalid then
            Ads_crumb(app, tag + "roImageCanvas not available on this Roku")
            return
        end if
        facade.Show()
        App_screen_release(app)
    end if
    Ads_crumb(app, tag + "showing " + ads.Count().ToStr() + " ad pod(s)")
    result = "error"
    try
        shown = app.raf.ShowAds(ads, invalid, view)
        result = type(shown)
        if result = "Boolean" or result = "roBoolean" then
            result = "false"
            if shown then result = "true"
        end if
    catch e
        result = "error: " + e.message
    end try
    Ads_crumb(app, tag + "ShowAds returned " + result + "; making the game screen")
    if facade <> invalid then
        App_screen_new(app)
        facade.Close()
    end if
    app.adClock.Mark()
    Ads_crumb(app, tag + "ShowAds returned " + result + "; back in the game")
    if Ads_test() then
        reg = CreateObject("roRegistrySection", "spiralshift_ads")
        reg.Delete("crumb")
        reg.Flush()
    end if
end sub
