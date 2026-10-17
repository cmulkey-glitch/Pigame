' Ads: none in this build. The ad-supported build (python3 dash/tools/build.py --ads) replaces
' this file with dash/roku-ads/ads.brs, which shows Roku ad framework video ads at natural breaks.

sub Ads_init(app as object)
end sub

' A natural break (a level, spiral run or world about to start from the menu): where an ad may play.
sub Ads_break(app as object)
end sub

' A crash, after its animation and before the retry: where an ad may play.
sub Ads_death(app as object)
end sub

' The test build's "play an ad now" button (Fast Forward on the menu).
sub Ads_now(app as object)
end sub
