local isShiftPressed = false
local isSpacePressed = false

-- NB: key rebindings
Ext.Events.KeyInput:Subscribe(function (e)
    if e.Key == "LSHIFT" or e.Key == "RSHIFT" then
        isShiftPressed = e.Event == "KeyDown"
    elseif e.Key == "SPACE" then
        isSpacePressed = e.Event == "KeyDown"
    end
    if isShiftPressed and isSpacePressed then
        Ext.ClientNet.PostMessageToServer("Toggle_TurnBased", "")
    end
end)

Ext.Events.SessionLoaded:Subscribe(function ()
    Ext.UI.GetRoot():Child(1):Child(1):Child(3):VisualChild(1):Child(5):Child(5):Child(7):Subscribe("GotMouseCapture", function ()
        Ext.ClientNet.PostMessageToServer("Toggle_TurnBased", "")
    end)
end)
