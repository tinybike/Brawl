local ModToggleHotkey = {ScanCode = "F9", Modifier = "NONE"}
local CompanionAIToggleHotkey = {ScanCode = "F11", Modifier = "NONE"}
local FullAutoToggleHotkey = {ScanCode = "F6", Modifier = "NONE"}
local PauseToggleHotkey = {ScanCode = "SPACE", Modifier = "LShift"}
local ControllerModToggleHotkey = ""
local ControllerCompanionAIToggleHotkey = ""
local ControllerFullAutoToggleHotkey = ""
local ControllerPauseToggleHotkey = "RightStick"
if MCM then
    ModToggleHotkey = MCM.Get("mod_toggle_hotkey")
    CompanionAIToggleHotkey = MCM.Get("companion_ai_toggle_hotkey")
    FullAutoToggleHotkey = MCM.Get("full_auto_toggle_hotkey")
    PauseToggleHotkey = MCM.Get("pause_toggle_hotkey")
    ControllerModToggleHotkey = MCM.Get("controller_mod_toggle_hotkey")
    ControllerCompanionAIToggleHotkey = MCM.Get("controller_companion_ai_toggle_hotkey")
    ControllerFullAutoToggleHotkey = MCM.Get("controller_full_auto_toggle_hotkey")
    ControllerPauseToggleHotkey = MCM.Get("controller_pause_toggle_hotkey")
end
local IsRightTriggerPressed = false
local IsLeftTriggerPressed = false
local DirectlyControlledCharacter = nil

-- Keybinding stuff from https://github.com/AtilioA/BG3-MCM & modified/re-used with permission

--- Utility function to check if a table contains a value
---@param tbl table The table to search
---@param element any The element to find
---@return boolean - Whether the table contains the element
function table.contains(tbl, element)
    if type(tbl) ~= "table" then
        return false
    end
    if tbl == nil or element == nil then
        return false
    end
    for _, value in pairs(tbl) do
        if value == element then
            return true
        end
    end
    return false
end

local KeybindingManager = {}

function KeybindingManager:IsActiveModifier(modifier)
    return table.contains({"LShift", "RShift", "LCtrl", "RCtrl", "LAlt", "RAlt"}, modifier)
end

function KeybindingManager:ExtractActiveModifiers(modifiers)
    local activeModifiers = {}
    for _, mod in ipairs(modifiers) do
        if self:IsActiveModifier(mod) then
            activeModifiers[mod] = true
        end
    end
    return activeModifiers
end

function KeybindingManager:AreAllModifiersPresent(eModifiers, activeModifiers)
    for _, mod in ipairs(eModifiers) do
        if self:IsActiveModifier(mod) and not activeModifiers[mod] then
            return false
        end
    end
    return true
end

function KeybindingManager:AreAllActiveModifiersPressed(eActiveModifiers, activeModifiers)
    for mod, _ in pairs(activeModifiers) do
        if not eActiveModifiers[mod] then
            return false
        end
    end
    return true
end

function KeybindingManager:IsModifierPressed(e, modifiers)
    local modifiersTable = type(modifiers) == "table" and modifiers or {modifiers}
    -- Necessary to ignore modifiers such as scroll lock, num lock, etc.
    local activeModifiers = self:ExtractActiveModifiers(modifiersTable)
    local eActiveModifiers = self:ExtractActiveModifiers(e.Modifiers)
    return self:AreAllModifiersPresent(e.Modifiers, activeModifiers) and self:AreAllActiveModifiersPressed(eActiveModifiers, activeModifiers)
end

function isKeybindingPressed(e, keybinding)
    if e.Key ~= keybinding.ScanCode then
        return false
    end
    return KeybindingManager:IsModifierPressed(e, keybinding.Modifier)
end

-- thank u aahz
local function getDirectlyControlledCharacter()
    if DirectlyControlledCharacter ~= nil then
        return DirectlyControlledCharacter
    end
    -- nb: this is NOT reliably updated when changing control, just use for initial setup
    for _, entity in pairs(Ext.Entity.GetAllEntitiesWithComponent("ClientControl")) do
        if entity.UserReservedFor.UserID == 1 then
            DirectlyControlledCharacter = entity.Uuid.EntityUuid
            return DirectlyControlledCharacter
        end
    end
end

local function isInFTB(uuid)
    local entity = Ext.Entity.Get(uuid)
    return entity.FTBParticipant and entity.FTBParticipant.field_18 ~= nil
end

local function postToggleFTB()
    if isInFTB(getDirectlyControlledCharacter()) then
        Ext.ClientNet.PostMessageToServer("ExitFTB", "")
    else
        Ext.ClientNet.PostMessageToServer("EnterFTB", "")
    end
end

local function getPositionInfo()
    local pickingHelper = Ext.UI.GetPickingHelper(1)
    if pickingHelper.Inner and pickingHelper.Inner.Position then
        local clickedOn = {position = pickingHelper.Inner.Position}
        if pickingHelper.Inner.Inner and pickingHelper.Inner.Inner[1] and pickingHelper.Inner.Inner[1].GameObject then
            local clickedOnEntity = pickingHelper.Inner.Inner[1].GameObject
            if clickedOnEntity and clickedOnEntity.Uuid and clickedOnEntity.Uuid.EntityUuid then
                clickedOn.uuid = clickedOnEntity.Uuid.EntityUuid
            end
        end
        return clickedOn
    end
    return nil
end

local function postClickPosition()
    Ext.ClientNet.PostMessageToServer("ClickPosition", Ext.Json.Stringify(getPositionInfo()))
end

local function onKeyInput(e)
    if e.Repeat == false and e.Event == "KeyDown" then
        local key = tostring(e.Key)
        if isKeybindingPressed(e, ModToggleHotkey) then
            Ext.ClientNet.PostMessageToServer("ModToggle", key)
        elseif isKeybindingPressed(e, CompanionAIToggleHotkey) then
            Ext.ClientNet.PostMessageToServer("CompanionAIToggle", key)
        elseif isKeybindingPressed(e, FullAutoToggleHotkey) then
            Ext.ClientNet.PostMessageToServer("FullAutoToggle", key)
        elseif isKeybindingPressed(e, PauseToggleHotkey) then
            postToggleFTB()
        end
    end
end

local function onNetMessage(data)
    if data.Channel == "GainedControl" then
        DirectlyControlledCharacter = data.Payload
    end
end

local function onControllerAxisInput(e)
    if e.Axis == "TriggerLeft" then
        if IsLeftTriggerPressed then
            if e.Value == 0.0 then
                IsLeftTriggerPressed = false
            end
            return
        end
        if not IsLeftTriggerPressed then
            IsLeftTriggerPressed = true
            return
        end
    end
end

local function onControllerButtonInput(e)
    if e.Pressed == true then
        Ext.ClientNet.PostMessageToServer("ControllerButtonPressed", tostring(e.Button))
        local button = tostring(e.Button)
        if button == "A" then
            postClickPosition()
        elseif button == "RightStick" and IsLeftTriggerPressed then
            postToggleFTB()
        end
    end
end

local function onMouseButtonInput(e)
    if e.Pressed and e.Button == 1 then
        postClickPosition()
    end
end

local function onMCMSettingSaved(payload)
    if not payload or payload.modUUID ~= ModuleUUID or not payload.settingId then
        return
    end
    if payload.settingId == "mod_toggle_hotkey" then
        ModToggleHotkey = {ScanCode = payload.value.ScanCode, Modifier = payload.value.Modifier}
    elseif payload.settingId == "companion_ai_toggle_hotkey" then
        CompanionAIToggleHotkey = {ScanCode = payload.value.ScanCode, Modifier = payload.value.Modifier}
    elseif payload.settingId == "full_auto_toggle_hotkey" then
        FullAutoToggleHotkey = {ScanCode = payload.value.ScanCode, Modifier = payload.value.Modifier}
    elseif payload.settingId == "pause_toggle_hotkey" then
        PauseToggleHotkey = {ScanCode = payload.value.ScanCode, Modifier = payload.value.Modifier}
    end
end

local function onSessionLoaded()
    Ext.Events.KeyInput:Subscribe(onKeyInput)
    Ext.Events.ControllerButtonInput:Subscribe(onControllerButtonInput)
    Ext.Events.ControllerAxisInput:Subscribe(onControllerAxisInput)
    Ext.Events.MouseButtonInput:Subscribe(onMouseButtonInput)
    Ext.Events.NetMessage:Subscribe(onNetMessage)
end

Ext.Events.SessionLoaded:Subscribe(onSessionLoaded)
Ext.ModEvents.BG3MCM["MCM_Setting_Saved"]:Subscribe(onMCMSettingSaved)
