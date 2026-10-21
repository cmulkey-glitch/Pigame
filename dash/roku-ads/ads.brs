Library "Roku_Ads.brs"

' Ads for the ad-supported build (python3 dash/tools/build.py --ads), with the Roku Advertising
' Framework, which Roku requires for any ads. A break comes when a level, spiral run or world is
' started from the menu, or between a crash and the retry once Ads_deaths() crashes have passed
' since the last ad; never mid-run. At most one every Ads_gap() seconds, counting from launch, so
' a session never opens with an ad.
'
' The roScreen stays up while RAF plays the ads. Letting it go made the app quit when the ad
' ended (a Roku app quits when its last screen closes); keeping it, and a blank SceneGraph screen
' as a placeholder, both worked on a device (0.9.10 test). No ad URL is set: RAF then serves
' Roku's own ads, but only to published apps approved for ads (none when sideloaded). For the
' 70% of inventory that is ours under Roku's default inventory split, SetAdUrl() takes a VAST tag
' from an ad network, when there is one.
'
' Test builds (build.py --ads-test, manifest ads_test=1): an ad before every start and every
' second crash, and whenever Fast Forward is pressed on the menu, from Google's public sample
' VAST tag, and what each break did shown on the menu (app.adStatus) and printed
' to the debug console (port 8085).

function Ads_test() as boolean
    return CreateObject("roAppInfo").GetValue("ads_test") = "1"
end function

function Ads_gap() as integer
    if Ads_test() then return 0
    return 180
end function

' Crashes between ads: a crash ad needs this many since the last ad.
function Ads_deaths() as integer
    if Ads_test() then return 2
    return 3
end function

function Ads_test_url() as string
    return "https://pubads.g.doubleclick.net/gampad/ads?iu=/21775744923/external/single_ad_samples&sz=640x480&cust_params=sample_ct%3Dlinear&ciu_szs=300x250%2C728x90&gdfp_req=1&output=vast&unviewed_position_start=1&env=vp&impl=s&correlator="
end function

sub Ads_init(app as object)
    app.adClock = CreateObject("roTimespan")
    app.adClock.Mark()
    app.adBreaks = 0
    app.adDeaths = 0
    raf = Roku_Ads()
    raf.SetDebugOutput(true)
    raf.SetAdPrefs(true, 2)
    ' Roku's ad measurement, required for US store apps that are not child-directed
    raf.SetContentId("spiral-shift")
    raf.SetContentGenre("Games")
    raf.EnableAdMeasurements(true)
    if Ads_test() then
        raf.SetAdUrl(Ads_test_url())
        Ads_status(app, "ads test build: Fast Forward plays an ad; also every start and 2nd crash")
    end if
    app.raf = raf
end sub

sub Ads_status(app as object, text as string)
    print "ADS: " + text
    if Ads_test() then app.adStatus = text
end sub

sub Ads_break(app as object)
    if app.full = true then return      ' the full version (store.brs) has no ads
    if app.raf = invalid or app.adClock.TotalSeconds() < Ads_gap() then return
    Ads_play(app)
end sub

' Test builds: Fast Forward on the menu plays an ad there and then.
sub Ads_now(app as object)
    if app.raf <> invalid and Ads_test() then Ads_play(app)
end sub

sub Ads_play(app as object)
    app.adBreaks = app.adBreaks + 1
    tag = "break " + app.adBreaks.ToStr() + ": "
    ads = app.raf.GetAds()
    if ads = invalid or ads.Count() = 0 then
        ' wait the full gap before asking again: each ask is a network call that holds the game
        app.adClock.Mark()
        app.adDeaths = 0
        Ads_status(app, tag + "the ad server returned no ads")
        return
    end if
    app.music.Stop()
    result = "error"
    try
        shown = app.raf.ShowAds(ads, invalid, invalid)
        result = type(shown)
        if result = "Boolean" or result = "roBoolean" then
            result = "false"
            if shown then result = "true"
        end if
    catch e
        result = "error: " + e.message
    end try
    app.adClock.Mark()
    app.adDeaths = 0
    if app.mode = "play" then app.music.Play()     ' a crash ad: the level goes on
    Ads_status(app, tag + "ShowAds returned " + result)
end sub

sub Ads_death(app as object)
    if app.raf = invalid or app.full = true then return
    app.adDeaths = app.adDeaths + 1
    if app.adDeaths >= Ads_deaths() then Ads_break(app)
end sub
