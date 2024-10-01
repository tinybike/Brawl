local shiftPressed = false
local spacePressed = false

Ext.Events.KeyInput:Subscribe(function (e)
    if e.Key == "LSHIFT" or e.Key == "RSHIFT" then
        shiftPressed = e.Event == "KeyDown"
    elseif e.Key == "SPACE" then
        spacePressed = e.Event == "KeyDown"
    end
    if shiftPressed and spacePressed then
        Ext.ClientNet.PostMessageToServer("Toggle_TurnBased", "")
    end
end)
