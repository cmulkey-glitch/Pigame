' The Roku Pay unlock: none in this build, where everything is open and there are no ads. The
' free build (python3 dash/tools/build.py --ads) replaces this file with dash/roku-ads/store.brs:
' a one-time "full version" purchase that opens every random world and turns the ads off.

sub Store_init(app as object)
    app.full = true
end sub

sub Store_event(app as object, msg as object)
end sub

sub Store_buy(app as object)
end sub
