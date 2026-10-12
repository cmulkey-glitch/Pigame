' Screensaver apps have no RunUserInterface/Main: Roku calls RunScreenSaver when the TV goes
' idle and RunScreenSaverSettings from Settings > Theme > Screensavers.

sub RunScreenSaver()
    showScene("DashboardScene")
end sub

sub RunScreenSaverSettings()
    showScene("SettingsScene")
end sub

sub showScene(name as string)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)
    screen.CreateScene(name)
    screen.Show()
    while true
        msg = wait(0, port)
        if type(msg) = "roSGScreenEvent" and msg.IsScreenClosed() then return
    end while
end sub
