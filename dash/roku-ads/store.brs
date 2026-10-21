' The Roku Pay unlock for the free build (python3 dash/tools/build.py --ads): one one-time
' product, Store_product(), that opens every random world (today's world is free for everyone)
' and turns the ads off (ads.brs checks app.full).
'
' On launch: the catalog (for the price), then the account's purchases (does it own the
' product?). The answer is also kept in the registry ("full"), so a known owner is unlocked at
' once and offline; a purchases list that comes back without the product locks it again
' (a refund). Buying: SetOrder + DoOrder, Roku's own purchase screen; the order's result comes
' back as an roChannelStoreEvent like the others. One request at a time (app.storeStep says
' which), all on the main loop's port (main.brs passes roChannelStoreEvents to Store_event).
'
' Testing: sideload with the dashboard's "billing testing" set on this channel and your Roku
' account added as a test user; purchases are then real calls but not charged.

' The product's identifier in the Developer Dashboard (Monetization > Products).
function Store_product() as string
    return "spiralshift_full"
end function

sub Store_init(app as object)
    app.full = app.reg.Exists("full") and app.reg.Read("full") = "1"
    app.price = ""
    app.storeNote = invalid
    app.store = CreateObject("roChannelStore")
    if app.store = invalid then return
    app.store.SetMessagePort(app.port)
    app.storeStep = "catalog"
    app.store.GetCatalog()
end sub

sub Store_set_full(app as object, full as boolean)
    app.full = full
    v = "0"
    if full then v = "1"
    app.reg.Write("full", v)
    app.reg.Flush()
end sub

sub Store_event(app as object, msg as object)
    req = app.storeStep
    app.storeStep = ""
    items = invalid
    if msg.isRequestSucceeded() then items = msg.GetResponse()
    if req = "catalog" then
        if items <> invalid then
            for each it in items
                if it.code = Store_product() and it.cost <> invalid then app.price = it.cost
            end for
        end if
        app.storeStep = "purchases"
        app.store.GetPurchases()
    else if req = "purchases" then
        if items <> invalid then
            owned = false
            for each it in items
                if it.code = Store_product() and it.status <> "Invalid" then owned = true
            end for
            Store_set_full(app, owned)
        end if
    else if req = "order" then
        if items <> invalid then
            Store_set_full(app, true)
            app.storeNote = "Thank you! Every world is open, and the ads are gone."
        else
            app.storeNote = "The purchase did not go through."
            if msg.isRequestFailed() then app.storeNote = app.storeNote + "  " + msg.GetStatusMessage()
        end if
    end if
end sub

' OK on a locked random world: Roku's purchase screen.
sub Store_buy(app as object)
    if app.full or app.store = invalid then return
    if app.storeStep <> "" then
        app.storeNote = "Still checking the Roku Channel Store: try again in a moment."
        return
    end if
    order = CreateObject("roList")
    order.AddTail({ code: Store_product(), qty: 1 })
    app.store.SetOrder(order)
    if app.store.DoOrder() then
        app.storeStep = "order"
        app.storeNote = "Completing the purchase..."
    else
        app.storeNote = invalid
    end if
end sub
