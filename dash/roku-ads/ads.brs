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

function Ads_gap() as integer
    return 300
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
    app.raf = raf
end sub

sub Ads_break(app as object)
    if app.raf = invalid or app.adClock.TotalSeconds() < Ads_gap() then return
    ads = app.raf.GetAds()
    if ads = invalid or ads.Count() = 0 then return
    app.music.Stop()
    App_screen_release(app)
    app.raf.ShowAds(ads, invalid, invalid)
    App_screen_new(app)
    app.adClock.Mark()
end sub
