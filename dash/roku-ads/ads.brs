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
    raf = Roku_Ads()
    raf.SetDebugOutput(true)
    raf.SetAdPrefs(true, 2)
    ' Roku's ad measurement, required for US store apps that are not child-directed
    raf.SetContentId("spiral-shift")
    raf.SetContentGenre("Games")
    raf.EnableAdMeasurements(true)
    if Ads_test() then
        raf.SetAdUrl(Ads_test_url())
        Ads_status(app, "ads test build: a break after a finished level, every 30 s")
    end if
    app.raf = raf
end sub

sub Ads_status(app as object, text as string)
    print "ADS: " + text
    if Ads_test() then app.adStatus = text
end sub

sub Ads_break(app as object)
    if app.raf = invalid then return
    wait = Ads_gap() - app.adClock.TotalSeconds()
    if wait > 0 then
        Ads_status(app, "no break yet: " + wait.ToStr() + " s to go")
        return
    end if
    ads = app.raf.GetAds()
    if ads = invalid or ads.Count() = 0 then
        Ads_status(app, "break: the ad server returned no ads")
        return
    end if
    app.music.Stop()
    App_screen_release(app)
    shown = app.raf.ShowAds(ads, invalid, invalid)
    App_screen_new(app)
    app.adClock.Mark()
    result = type(shown)
    if result = "Boolean" or result = "roBoolean" then
        result = "false"
        if shown then result = "true"
    end if
    Ads_status(app, "break: " + ads.Count().ToStr() + " ad pod(s); ShowAds returned " + result)
end sub
