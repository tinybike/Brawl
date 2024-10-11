local ModToggleHotkey = "F9"
local CompanionAIToggleHotkey = "F11"
if MCM then
    ModToggleHotkey = string.upper(MCM.Get("mod_toggle_hotkey"))
    CompanionAIToggleHotkey = string.upper(MCM.Get("companion_ai_toggle_hotkey"))
end
local IsRightTriggerPressed = false
local IsLeftTriggerPressed = false

local function onControllerAxisInput(e)
    if e.Axis == "TriggerRight" then
        if IsRightTriggerPressed then
            if e.Value == 0.0 then
                IsRightTriggerPressed = false
            end
            return
        end
        if not IsRightTriggerPressed then
            IsRightTriggerPressed = true
            Ext.ClientNet.PostMessageToServer("ControllerButtonPressed", "RightTrigger")
            return
        end
    elseif e.Axis == "TriggerLeft" then
        if IsLeftTriggerPressed then
            if e.Value == 0.0 then
                IsLeftTriggerPressed = false
            end
            return
        end
        if not IsLeftTriggerPressed then
            IsLeftTriggerPressed = true
            Ext.ClientNet.PostMessageToServer("ControllerButtonPressed", "LeftTrigger")
            return
        end
    end
end

local function onControllerButtonInput(e)
    if e.Pressed == true then
        Ext.ClientNet.PostMessageToServer("ControllerButtonPressed", tostring(e.Button))
    end
end

local function onKeyInput(e)
    if e.Key == ModToggleHotkey and e.Event == "KeyDown" and e.Repeat == false then
        Ext.ClientNet.PostMessageToServer("ModToggle", tostring(e.Key))
    elseif e.Key == CompanionAIToggleHotkey and e.Event == "KeyDown" and e.Repeat == false then
        Ext.ClientNet.PostMessageToServer("CompanionAIToggle", tostring(e.Key))
    end
end

Ext.Events.KeyInput:Subscribe(onKeyInput)
Ext.Events.ControllerButtonInput:Subscribe(onControllerButtonInput)
ControllerAxisInputSubscription = Ext.Events.ControllerAxisInput:Subscribe(onControllerAxisInput)
