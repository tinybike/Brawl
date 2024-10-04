local ModToggleHotkey = "F9"
local CompanionAIToggleHotkey = "F11"
if MCM then
    ModToggleHotkey = string.upper(MCM.Get("mod_toggle_hotkey"))
    CompanionAIToggleHotkey = string.upper(MCM.Get("companion_ai_toggle_hotkey"))
end

-- NB: key rebindings
local function onKeyInput(e)
    if e.Key == ModToggleHotkey and e.Event == "KeyDown" and e.Repeat == false then
        Ext.ClientNet.PostMessageToServer("ModToggle", tostring(e.Key))
    elseif e.Key == CompanionAIToggleHotkey and e.Event == "KeyDown" and e.Repeat == false then
        Ext.ClientNet.PostMessageToServer("CompanionAIToggle", tostring(e.Key))
    elseif e.Key == "LSHIFT" or e.Key == "RSHIFT" then
        IsShiftPressed = e.Event == "KeyDown"
    elseif e.Key == "SPACE" then
        IsSpacePressed = e.Event == "KeyDown"
    end
end

Ext.Events.KeyInput:Subscribe(onKeyInput)
