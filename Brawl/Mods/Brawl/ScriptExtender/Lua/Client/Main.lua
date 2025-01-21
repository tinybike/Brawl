local ModToggleHotkey = {ScanCode = "F9", Modifier = "NONE"}
local CompanionAIToggleHotkey = {ScanCode = "F11", Modifier = "NONE"}
local FullAutoToggleHotkey = {ScanCode = "F6", Modifier = "NONE"}
local PauseToggleHotkey = {ScanCode = "SPACE", Modifier = "LShift"}
local TargetCloserEnemyHotkey = {ScanCode = "COMMA", Modifier = "NONE"}
local TargetFartherEnemyHotkey = {ScanCode = "PERIOD", Modifier = "NONE"}
local OnMeHotkey = {ScanCode = "NUM_1", Modifier = "LAlt"}
local AttackMyTargetHotkey = {ScanCode = "NUM_2", Modifier = "LAlt"}
local AttackMoveHotkey = {ScanCode = "A", Modifier = "LAlt"}
local RequestHealHotkey = {ScanCode = "E", Modifier = "LAlt"}
local ChangeTacticsHotkey = {ScanCode = "C", Modifier = "LAlt"}
local ActionButtonHotkeys = {
    {ScanCode = "NUM_1", Modifier = "LShift"},
    {ScanCode = "NUM_2", Modifier = "LShift"},
    {ScanCode = "NUM_3", Modifier = "LShift"},
    {ScanCode = "NUM_4", Modifier = "LShift"},
    {ScanCode = "NUM_5", Modifier = "LShift"},
    {ScanCode = "NUM_6", Modifier = "LShift"},
    {ScanCode = "NUM_7", Modifier = "LShift"},
    {ScanCode = "NUM_8", Modifier = "LShift"},
    {ScanCode = "NUM_9", Modifier = "LShift"},
}
local ControllerModToggleHotkey = {"", ""}
local ControllerCompanionAIToggleHotkey = {"", ""}
local ControllerFullAutoToggleHotkey = {"", ""}
local ControllerPauseToggleHotkey = {"RightStick", ""}
local ControllerTargetCloserEnemyHotkey = {"DPadLeft", ""}
local ControllerTargetFartherEnemyHotkey = {"DPadRight", ""}
local ControllerOnMeHotkey = {"", ""}
local ControllerAttackMyTargetHotkey = {"", ""}
local ControllerAttackMoveHotkey = {"", ""}
local ControllerRequestHealHotkey = {"", ""}
local ControllerChangeTacticsHotkey = {"", ""}
local ControllerActionButtonHotkeys = {{"A", ""}, {"B", ""}, {"X", ""}, {"Y", ""}, {"", ""}, {"", ""}, {"", ""}, {"", ""}, {"", ""}}
if MCM then
    ModToggleHotkey = MCM.Get("mod_toggle_hotkey")
    CompanionAIToggleHotkey = MCM.Get("companion_ai_toggle_hotkey")
    FullAutoToggleHotkey = MCM.Get("full_auto_toggle_hotkey")
    PauseToggleHotkey = MCM.Get("pause_toggle_hotkey")
    TargetCloserEnemyHotkey = MCM.Get("target_closer_enemy_hotkey")
    TargetFartherEnemyHotkey = MCM.Get("target_farther_enemy_hotkey")
    OnMeHotkey = MCM.Get("on_me_hotkey")
    AttackMyTargetHotkey = MCM.Get("attack_my_target_hotkey")
    AttackMoveHotkey = MCM.Get("attack_move_hotkey")
    RequestHealHotkey = MCM.Get("request_heal_hotkey")
    ChangeTacticsHotkey = MCM.Get("change_tactics_hotkey")
    ActionButtonHotkeys = {
        MCM.Get("action_1_hotkey"),
        MCM.Get("action_2_hotkey"),
        MCM.Get("action_3_hotkey"),
        MCM.Get("action_4_hotkey"),
        MCM.Get("action_5_hotkey"),
        MCM.Get("action_6_hotkey"),
        MCM.Get("action_7_hotkey"),
        MCM.Get("action_8_hotkey"),
        MCM.Get("action_9_hotkey"),
    }
    ControllerModToggleHotkey = {MCM.Get("controller_mod_toggle_hotkey"), MCM.Get("controller_mod_toggle_hotkey_2")}
    ControllerCompanionAIToggleHotkey = {MCM.Get("controller_companion_ai_toggle_hotkey"), MCM.Get("controller_companion_ai_toggle_hotkey_2")}
    ControllerFullAutoToggleHotkey = {MCM.Get("controller_full_auto_toggle_hotkey"), MCM.Get("controller_full_auto_toggle_hotkey_2")}
    ControllerPauseToggleHotkey = {MCM.Get("controller_pause_toggle_hotkey"), MCM.Get("controller_pause_toggle_hotkey_2")}
    ControllerTargetCloserEnemyHotkey = {MCM.Get("controller_target_closer_enemy_hotkey"), MCM.Get("controller_target_closer_enemy_hotkey_2")}
    ControllerTargetFartherEnemyHotkey = {MCM.Get("controller_target_farther_enemy_hotkey"), MCM.Get("controller_target_farther_enemy_hotkey_2")}
    ControllerOnMeHotkey = {MCM.Get("controller_on_me_hotkey"), MCM.Get("controller_on_me_hotkey_2")}
    ControllerAttackMyTargetHotkey = {MCM.Get("controller_attack_my_target_hotkey"), MCM.Get("controller_attack_my_target_hotkey_2")}
    ControllerAttackMoveHotkey = {MCM.Get("controller_attack_move_hotkey"), MCM.Get("controller_attack_move_hotkey_2")}
    ControllerRequestHealHotkey = {MCM.Get("controller_request_heal_hotkey"), MCM.Get("controller_request_heal_hotkey_2")}
    ControllerChangeTacticsHotkey = {MCM.Get("controller_change_tactics_hotkey"), MCM.Get("controller_change_tactics_hotkey_2")}
    ControllerActionButtonHotkeys = {
        {MCM.Get("controller_action_1_hotkey"), MCM.Get("controller_action_1_hotkey_2")},
        {MCM.Get("controller_action_2_hotkey"), MCM.Get("controller_action_2_hotkey_2")},
        {MCM.Get("controller_action_3_hotkey"), MCM.Get("controller_action_3_hotkey_2")},
        {MCM.Get("controller_action_4_hotkey"), MCM.Get("controller_action_4_hotkey_2")},
        {MCM.Get("controller_action_5_hotkey"), MCM.Get("controller_action_5_hotkey_2")},
        {MCM.Get("controller_action_6_hotkey"), MCM.Get("controller_action_6_hotkey_2")},
        {MCM.Get("controller_action_7_hotkey"), MCM.Get("controller_action_7_hotkey_2")},
        {MCM.Get("controller_action_8_hotkey"), MCM.Get("controller_action_8_hotkey_2")},
        {MCM.Get("controller_action_9_hotkey"), MCM.Get("controller_action_9_hotkey_2")},
    }
end
local DirectlyControlledCharacter = nil
local AwaitingTarget = false
local IsControllerButtonPressed = {
    A = false,
    B = false,
    X = false,
    Y = false,
    DPadLeft = false,
    DPadRight = false,
    DPadUp = false,
    DPadDown = false,
    Back = false,
    Start = false,
    Touchpad = false,
    LeftStick = false,
    RightStick = false,
    TriggerLeft = false,
    TriggerRight = false,
}

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

local function isKeybindingPressed(e, keybinding)
    if e.Key ~= keybinding.ScanCode then
        return false
    end
    return KeybindingManager:IsModifierPressed(e, keybinding.Modifier)
end

local function isControllerKeybindingPressed(keybinding)
    if keybinding[2] == "" then
        return IsControllerButtonPressed[keybinding[1]]
    end
    return IsControllerButtonPressed[keybinding[1]] and IsControllerButtonPressed[keybinding[2]]
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

local function getPositionInfo()
    local pickingHelper = Ext.UI.GetPickingHelper(1)
    if pickingHelper.Inner and pickingHelper.Inner.Position then
        local clickedOn = {}
        if pickingHelper.Inner.Inner and pickingHelper.Inner.Inner[1] and pickingHelper.Inner.Inner[1].GameObject then
            local clickedOnEntity = pickingHelper.Inner.Inner[1].GameObject
            if clickedOnEntity and clickedOnEntity.Uuid and clickedOnEntity.Uuid.EntityUuid then
                clickedOn.uuid = clickedOnEntity.Uuid.EntityUuid
            end
        end
        clickedOn.position = pickingHelper.Inner.Position
        -- _D(clickedOn)
        return clickedOn
    end
    return nil
end

local function postPauseToggle()
    if isInFTB(getDirectlyControlledCharacter()) then
        Ext.ClientNet.PostMessageToServer("ExitFTB", "")
    else
        Ext.ClientNet.PostMessageToServer("EnterFTB", "")
    end
end

local function postModToggle()
    Ext.ClientNet.PostMessageToServer("ModToggle", "")
end

local function postCompanionAIToggle()
    Ext.ClientNet.PostMessageToServer("CompanionAIToggle", "")
end

local function postFullAutoToggle()
    Ext.ClientNet.PostMessageToServer("FullAutoToggle", "")
end

local function postTargetCloserEnemy()
    Ext.ClientNet.PostMessageToServer("TargetCloserEnemy", "")
end

local function postTargetFartherEnemy()
    Ext.ClientNet.PostMessageToServer("TargetFartherEnemy", "")
end

local function postOnMe()
    Ext.ClientNet.PostMessageToServer("OnMe", "")
end

local function postAttackMyTarget()
    Ext.ClientNet.PostMessageToServer("AttackMyTarget", "")
end

local function postAttackMove()
    Ext.ClientNet.PostMessageToServer("AttackMove", "")
end

local function postRequestHeal()
    Ext.ClientNet.PostMessageToServer("RequestHeal", "")
end

local function postChangeTactics()
    Ext.ClientNet.PostMessageToServer("ChangeTactics", "")
end

local function postControllerActionButton(actionButtonLabel)
    Ext.ClientNet.PostMessageToServer("ControllerActionButton", tostring(actionButtonLabel))
end

local function postActionButton(actionButtonLabel)
    Ext.ClientNet.PostMessageToServer("ActionButton", tostring(actionButtonLabel))
end

local function postClickPosition()
    Ext.ClientNet.PostMessageToServer("ClickPosition", Ext.Json.Stringify(getPositionInfo()))
end

local function postCancelQueuedMovement()
    Ext.ClientNet.PostMessageToServer("CancelQueuedMovement", "")
end

local function onKeyInput(e)
    if e.Repeat == false and e.Event == "KeyDown" then
        local key = tostring(e.Key)
        local keybindingPressed = false
        if isKeybindingPressed(e, ModToggleHotkey) then
            postModToggle()
            keybindingPressed = true
        end
        if isKeybindingPressed(e, CompanionAIToggleHotkey) then
            postCompanionAIToggle()
            keybindingPressed = true
        end
        if isKeybindingPressed(e, FullAutoToggleHotkey) then
            postFullAutoToggle()
            keybindingPressed = true
        end
        if isKeybindingPressed(e, PauseToggleHotkey) then
            postPauseToggle()
            keybindingPressed = true
        end
        if isKeybindingPressed(e, TargetCloserEnemyHotkey) then
            postTargetCloserEnemy()
            keybindingPressed = true
        end
        if isKeybindingPressed(e, TargetFartherEnemyHotkey) then
            postTargetFartherEnemy()
            keybindingPressed = true
        end
        if isKeybindingPressed(e, OnMeHotkey) then
            postOnMe()
            keybindingPressed = true
        end
        if isKeybindingPressed(e, AttackMyTargetHotkey) then
            postAttackMyTarget()
            keybindingPressed = true
        end
        if isKeybindingPressed(e, AttackMoveHotkey) then
            postAttackMove()
            keybindingPressed = true
        end
        if isKeybindingPressed(e, RequestHealHotkey) then
            postRequestHeal()
            keybindingPressed = true
        end
        if isKeybindingPressed(e, ChangeTacticsHotkey) then
            postChangeTactics()
            keybindingPressed = true
        end
        for actionButtonLabel, actionButtonHotkey in ipairs(ActionButtonHotkeys) do
            if isKeybindingPressed(e, actionButtonHotkey) then
                postActionButton(actionButtonLabel)
                keybindingPressed = true
            end
        end
        if keybindingPressed then
            e:PreventAction()
        end
    end
end

local function onControllerButtonPressed(button)
    Ext.ClientNet.PostMessageToServer("ControllerButtonPressed", button)
    if button == "A" then
        postClickPosition()
    end
    if isControllerKeybindingPressed(ControllerModToggleHotkey) then
        postModToggle()
    end
    if isControllerKeybindingPressed(ControllerCompanionAIToggleHotkey) then
        postCompanionAIToggle()
    end
    if isControllerKeybindingPressed(ControllerFullAutoToggleHotkey) then
        postFullAutoToggle()
    end
    if isControllerKeybindingPressed(ControllerPauseToggleHotkey) then
        postPauseToggle()
    end
    if isControllerKeybindingPressed(ControllerTargetCloserEnemyHotkey) then
        postTargetCloserEnemy()
    end
    if isControllerKeybindingPressed(ControllerTargetFartherEnemyHotkey) then
        postTargetFartherEnemy()
    end
    if isControllerKeybindingPressed(ControllerOnMeHotkey) then
        postOnMe()
    end
    if isControllerKeybindingPressed(ControllerAttackMyTargetHotkey) then
        postAttackMyTarget()
    end
    if isControllerKeybindingPressed(ControllerAttackMoveHotkey) then
        postAttackMove()
    end
    if isControllerKeybindingPressed(ControllerRequestHealHotkey) then
        postRequestHeal()
    end
    if isControllerKeybindingPressed(ControllerChangeTacticsHotkey) then
        postChangeTactics()
    end
    for actionButtonLabel, controllerActionButtonHotkey in ipairs(ControllerActionButtonHotkeys) do
        if isControllerKeybindingPressed(controllerActionButtonHotkey) then
            postControllerActionButton(actionButtonLabel)
        end
    end
end

local function onControllerAxisInput(e)
    local axis = tostring(e.Axis)
    if axis == "TriggerLeft" or axis == "TriggerRight" then
        if IsControllerButtonPressed[axis] then
            if e.Value == 0.0 then
                IsControllerButtonPressed[axis] = false
            end
        else
            IsControllerButtonPressed[axis] = true
            onControllerButtonPressed(axis)
        end
    end
end

local function onControllerButtonInput(e)
    local button = tostring(e.Button)
    IsControllerButtonPressed[button] = e.Pressed
    if e.Pressed then
        onControllerButtonPressed(button)
    end
end

local function onMouseButtonInput(e)
    if e.Pressed then
        if e.Button == 1 then
            postClickPosition()
            if AwaitingTarget then
                e:PreventAction()
            end
        elseif e.Button == 3 then
            postCancelQueuedMovement()
        end
    end
end

---@param struct userdata|table|any
---@param property string
---@param default any|nil
---@return any
-- thank u hippo
function getProperty(struct, property, default)
    local ok, value = pcall(function ()
        return struct[property]
    end)
    if ok then
        return value
    end
    return default
end

-- thank u hippo
local function getSubtitleWidgetIndex()
    for subtitleWidgetIndex = 1, 12 do
        if getProperty(Ext.UI.GetRoot():Child(1):Child(1):Child(subtitleWidgetIndex), "XAMLPath", ""):match("OverheadInfo") then
            return subtitleWidgetIndex
        end
    end
end

-- thank u hippo
local function showNotification(notification)
    local subtitleWidgetIndex = getSubtitleWidgetIndex()
    if subtitleWidgetIndex then
        local dataContext = Ext.UI.GetRoot():Child(1):Child(1):Child(subtitleWidgetIndex).DataContext
        dataContext.CurrentSubtitleDuration = (notification.duration ~= "") and tonumber(notification.duration) or 2
        dataContext.CurrentSubtitle = notification.text
    end
end

local function onNetMessage(data)
    if data.Channel == "GainedControl" then
        DirectlyControlledCharacter = data.Payload
    elseif data.Channel == "AwaitingTarget" then
        AwaitingTarget = data.Payload == "1"
    elseif data.Channel == "Notification" then
        showNotification(Ext.Json.Parse(data.Payload))
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
    elseif payload.settingId == "target_closer_enemy_hotkey" then
        TargetCloserEnemyHotkey = {ScanCode = payload.value.ScanCode, Modifier = payload.value.Modifier}
    elseif payload.settingId == "target_farther_enemy_hotkey" then
        TargetFartherEnemyHotkey = {ScanCode = payload.value.ScanCode, Modifier = payload.value.Modifier}
    elseif payload.settingId == "on_me_hotkey" then
        OnMeHotkey = {ScanCode = payload.value.ScanCode, Modifier = payload.value.Modifier}
    elseif payload.settingId == "attack_my_target_hotkey" then
        AttackMyTargetHotkey = {ScanCode = payload.value.ScanCode, Modifier = payload.value.Modifier}
    elseif payload.settingId == "attack_move_hotkey" then
        AttackMoveHotkey = {ScanCode = payload.value.ScanCode, Modifier = payload.value.Modifier}
    elseif payload.settingId == "request_heal_hotkey" then
        RequestHealHotkey = {ScanCode = payload.value.ScanCode, Modifier = payload.value.Modifier}
    elseif payload.settingId == "change_tactics_hotkey" then
        ChangeTacticsHotkey = {ScanCode = payload.value.ScanCode, Modifier = payload.value.Modifier}
    elseif payload.settingId == "controller_mod_toggle_hotkey" then
        ControllerModToggleHotkey[1] = payload.value
    elseif payload.settingId == "controller_mod_toggle_hotkey_2" then
        ControllerModToggleHotkey[2] = payload.value
    elseif payload.settingId == "controller_companion_ai_toggle_hotkey" then
        ControllerCompanionAIToggleHotkey[1] = payload.value
    elseif payload.settingId == "controller_companion_ai_toggle_hotkey_2" then
        ControllerCompanionAIToggleHotkey[2] = payload.value
    elseif payload.settingId == "controller_full_auto_toggle_hotkey" then
        ControllerFullAutoToggleHotkey[1] = payload.value
    elseif payload.settingId == "controller_full_auto_toggle_hotkey_2" then
        ControllerFullAutoToggleHotkey[2] = payload.value
    elseif payload.settingId == "controller_pause_toggle_hotkey" then
        ControllerPauseToggleHotkey[1] = payload.value
    elseif payload.settingId == "controller_pause_toggle_hotkey_2" then
        ControllerPauseToggleHotkey[2] = payload.value
    elseif payload.settingId == "controller_target_closer_enemy_hotkey" then
        ControllerTargetCloserEnemyHotkey[1] = payload.value
    elseif payload.settingId == "controller_target_closer_enemy_hotkey_2" then
        ControllerTargetCloserEnemyHotkey[2] = payload.value
    elseif payload.settingId == "controller_target_farther_enemy_hotkey" then
        ControllerTargetFartherEnemyHotkey[1] = payload.value
    elseif payload.settingId == "controller_target_farther_enemy_hotkey_2" then
        ControllerTargetFartherEnemyHotkey[2] = payload.value
    elseif payload.settingId == "controller_on_me_hotkey" then
        ControllerOnMeHotkey[1] = payload.value
    elseif payload.settingId == "controller_on_me_hotkey_2" then
        ControllerOnMeHotkey[2] = payload.value
    elseif payload.settingId == "controller_attack_my_target_hotkey" then
        ControllerAttackMyTargetHotkey[1] = payload.value
    elseif payload.settingId == "controller_attack_my_target_hotkey_2" then
        ControllerAttackMyTargetHotkey[2] = payload.value
    elseif payload.settingId == "controller_attack_move_hotkey" then
        ControllerAttackMoveHotkey[1] = payload.value
    elseif payload.settingId == "controller_attack_move_hotkey_2" then
        ControllerAttackMoveHotkey[2] = payload.value
    elseif payload.settingId == "controller_request_heal_hotkey" then
        ControllerRequestHealHotkey[1] = payload.value
    elseif payload.settingId == "controller_request_heal_hotkey_2" then
        ControllerRequestHealHotkey[2] = payload.value
    elseif payload.settingId == "controller_change_tactics_hotkey" then
        ControllerChangeTacticsHotkey[1] = payload.value
    elseif payload.settingId == "controller_change_tactics_hotkey_2" then
        ControllerChangeTacticsHotkey[2] = payload.value
    elseif payload.settingId:find("controller_action_") ~= nil then
        for actionButtonLabel, controllerActionButtonHotkey in ipairs(ControllerActionButtonHotkeys) do
            if payload.settingId == "controller_action_" .. actionButtonLabel .. "_hotkey" then
                controllerActionButtonHotkey[1] = payload.value
            elseif payload.settingId == "controller_action_" .. actionButtonLabel .. "_hotkey_2" then
                controllerActionButtonHotkey[2] = payload.value
            end
        end
    else
        for actionButtonLabel, actionButtonHotkey in ipairs(ActionButtonHotkeys) do
            if payload.settingId == "action_" .. actionButtonLabel .. "_hotkey" then
                actionButtonHotkey.ScanCode = payload.value.ScanCode
                actionButtonHotkey.Modifier = payload.value.Modifier
            end
        end
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
if MCM then
    Ext.ModEvents.BG3MCM["MCM_Setting_Saved"]:Subscribe(onMCMSettingSaved)
end
