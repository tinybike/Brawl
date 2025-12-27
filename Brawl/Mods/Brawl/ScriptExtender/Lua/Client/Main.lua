local ModToggleHotkey = {ScanCode = "F11", Modifier = "NONE"}
local ModeToggleHotkey = {ScanCode = "F11", Modifier = "LCtrl"}
local CompanionAIToggleHotkey = {ScanCode = "F11", Modifier = "LShift"}
local QueueCompanionAIActionsHotkey = {ScanCode = "C", Modifier = "LCtrl"}
local FullAutoToggleHotkey = {ScanCode = "F6", Modifier = "NONE"}
local PauseToggleHotkey = {ScanCode = "SPACE", Modifier = "LShift"}
local TargetCloserEnemyHotkey = {ScanCode = "COMMA", Modifier = "NONE"}
local TargetFartherEnemyHotkey = {ScanCode = "PERIOD", Modifier = "NONE"}
local OnMeHotkey = {ScanCode = "NUM_1", Modifier = "LAlt"}
local AttackMyTargetHotkey = {ScanCode = "NUM_2", Modifier = "LAlt"}
local AttackMoveHotkey = {ScanCode = "A", Modifier = "LAlt"}
local RequestHealHotkey = {ScanCode = "E", Modifier = "LAlt"}
local ChangeTacticsHotkey = {ScanCode = "C", Modifier = "LAlt"}
local LeaderboardToggleHotkey = {ScanCode = "V", Modifier = "LCtrl"}
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
local ControllerModeToggleHotkey = {"", ""}
local ControllerCompanionAIToggleHotkey = {"", ""}
local ControllerQueueCompanionAIActionsHotkey = {"", ""}
local ControllerFullAutoToggleHotkey = {"", ""}
local ControllerPauseToggleHotkey = {"RightStick", ""}
local ControllerTargetCloserEnemyHotkey = {"DPadLeft", ""}
local ControllerTargetFartherEnemyHotkey = {"DPadRight", ""}
local ControllerOnMeHotkey = {"", ""}
local ControllerAttackMyTargetHotkey = {"", ""}
local ControllerAttackMoveHotkey = {"", ""}
local ControllerRequestHealHotkey = {"", ""}
local ControllerChangeTacticsHotkey = {"", ""}
local ControllerLeaderboardToggleHotkey = {"", ""}
local ControllerActionButtonHotkeys = {{"A", ""}, {"B", ""}, {"X", ""}, {"Y", ""}, {"", ""}, {"", ""}, {"", ""}, {"", ""}, {"", ""}}
local ControllerModToggleHotkeyOverride = false
local ControllerModeToggleHotkeyOverride = false
local ControllerCompanionAIToggleHotkeyOverride = false
local ControllerFullAutoToggleHotkeyOverride = false
local ControllerPauseToggleHotkeyOverride = false
local ControllerTargetCloserEnemyHotkeyOverride = false
local ControllerTargetFartherEnemyHotkeyOverride = false
local ControllerOnMeHotkeyOverride = false
local ControllerAttackMyTargetHotkeyOverride = false
local ControllerAttackMoveHotkeyOverride = false
local ControllerRequestHealHotkeyOverride = false
local ControllerChangeTacticsHotkeyOverride = false
local ControllerActionButtonHotkeysOverride = {false, false, false, false, false, false, false, false, false}
local ControllerLeaderboardToggleHotkeyOverride = false
if MCM then
    ModToggleHotkey = MCM.Get("mod_toggle_hotkey")
    ModeToggleHotkey = MCM.Get("mode_toggle_hotkey")
    CompanionAIToggleHotkey = MCM.Get("companion_ai_toggle_hotkey")
    QueueCompanionAIActionsHotkey = MCM.Get("queue_companion_ai_actions_hotkey")
    FullAutoToggleHotkey = MCM.Get("full_auto_toggle_hotkey")
    PauseToggleHotkey = MCM.Get("pause_toggle_hotkey")
    TargetCloserEnemyHotkey = MCM.Get("target_closer_enemy_hotkey")
    TargetFartherEnemyHotkey = MCM.Get("target_farther_enemy_hotkey")
    OnMeHotkey = MCM.Get("on_me_hotkey")
    AttackMyTargetHotkey = MCM.Get("attack_my_target_hotkey")
    AttackMoveHotkey = MCM.Get("attack_move_hotkey")
    RequestHealHotkey = MCM.Get("request_heal_hotkey")
    ChangeTacticsHotkey = MCM.Get("change_tactics_hotkey")
    LeaderboardToggleHotkey = MCM.Get("leaderboard_toggle_hotkey")
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
    ControllerModeToggleHotkey = {MCM.Get("controller_mode_toggle_hotkey"), MCM.Get("controller_mode_toggle_hotkey_2")}
    ControllerCompanionAIToggleHotkey = {MCM.Get("controller_companion_ai_toggle_hotkey"), MCM.Get("controller_companion_ai_toggle_hotkey_2")}
    ControllerQueueCompanionAIActionsHotkey = {MCM.Get("controller_queue_companion_ai_actions_hotkey"), MCM.Get("controller_queue_companion_ai_actions_hotkey_2")}
    ControllerFullAutoToggleHotkey = {MCM.Get("controller_full_auto_toggle_hotkey"), MCM.Get("controller_full_auto_toggle_hotkey_2")}
    ControllerPauseToggleHotkey = {MCM.Get("controller_pause_toggle_hotkey"), MCM.Get("controller_pause_toggle_hotkey_2")}
    ControllerTargetCloserEnemyHotkey = {MCM.Get("controller_target_closer_enemy_hotkey"), MCM.Get("controller_target_closer_enemy_hotkey_2")}
    ControllerTargetFartherEnemyHotkey = {MCM.Get("controller_target_farther_enemy_hotkey"), MCM.Get("controller_target_farther_enemy_hotkey_2")}
    ControllerOnMeHotkey = {MCM.Get("controller_on_me_hotkey"), MCM.Get("controller_on_me_hotkey_2")}
    ControllerAttackMyTargetHotkey = {MCM.Get("controller_attack_my_target_hotkey"), MCM.Get("controller_attack_my_target_hotkey_2")}
    ControllerAttackMoveHotkey = {MCM.Get("controller_attack_move_hotkey"), MCM.Get("controller_attack_move_hotkey_2")}
    ControllerRequestHealHotkey = {MCM.Get("controller_request_heal_hotkey"), MCM.Get("controller_request_heal_hotkey_2")}
    ControllerChangeTacticsHotkey = {MCM.Get("controller_change_tactics_hotkey"), MCM.Get("controller_change_tactics_hotkey_2")}
    ControllerLeaderboardToggleHotkey = {MCM.Get("controller_leaderboard_toggle_hotkey"), MCM.Get("controller_leaderboard_toggle_hotkey_2")}
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
    ControllerModToggleHotkeyOverride = MCM.Get("controller_mod_toggle_hotkey_override")
    ControllerModeToggleHotkeyOverride = MCM.Get("controller_mode_toggle_hotkey_override")
    ControllerCompanionAIToggleHotkeyOverride = MCM.Get("controller_companion_ai_toggle_hotkey_override")
    ControllerQueueCompanionAIActionsHotkeyOverride = MCM.Get("controller_queue_companion_ai_actions_hotkey_override")
    ControllerFullAutoToggleHotkeyOverride = MCM.Get("controller_full_auto_toggle_hotkey_override")
    ControllerPauseToggleHotkeyOverride = MCM.Get("controller_pause_toggle_hotkey_override")
    ControllerTargetCloserEnemyHotkeyOverride = MCM.Get("controller_target_closer_enemy_hotkey_override")
    ControllerTargetFartherEnemyHotkeyOverride = MCM.Get("controller_target_farther_enemy_hotkey_override")
    ControllerOnMeHotkeyOverride = MCM.Get("controller_on_me_hotkey_override")
    ControllerAttackMyTargetHotkeyOverride = MCM.Get("controller_attack_my_target_hotkey_override")
    ControllerAttackMoveHotkeyOverride = MCM.Get("controller_attack_move_hotkey_override")
    ControllerRequestHealHotkeyOverride = MCM.Get("controller_request_heal_hotkey_override")
    ControllerChangeTacticsHotkeyOverride = MCM.Get("controller_change_tactics_hotkey_override")
    ControllerLeaderboardToggleHotkeyOverride = MCM.Get("controller_leaderboard_toggle_hotkey_override")
    ControllerActionButtonHotkeysOverride = {
        MCM.Get("controller_action_1_hotkey_override"),
        MCM.Get("controller_action_2_hotkey_override"),
        MCM.Get("controller_action_3_hotkey_override"),
        MCM.Get("controller_action_4_hotkey_override"),
        MCM.Get("controller_action_5_hotkey_override"),
        MCM.Get("controller_action_6_hotkey_override"),
        MCM.Get("controller_action_7_hotkey_override"),
        MCM.Get("controller_action_8_hotkey_override"),
        MCM.Get("controller_action_9_hotkey_override"),
    }
end
local DirectlyControlledCharacter = nil
local DirectlyControlledCharacterIndex = 1
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
local LeaderboardWindow = nil
local cellRefs = {party = {}, enemy = {}}
local lightYellow = {1, 1, 0.8, 1}
local mediumYellow = {0.9, 0.9, 0.6, 0.9}
local lightBlue = {0.6, 0.8, 1, 1}
local lightRed = {1, 0.8, 0.8, 1}

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

local function setDirectlyControlledCharacterIndex()
    local directlyControlledCharacterUuid = getDirectlyControlledCharacter()
    for _, child in ipairs(Ext.UI:GetRoot():Find("ContentRoot").Children) do
        if child.Name == "PlayerPortraits" then
            local assignedCharacters = child.DataContext.CurrentPlayer.AssignedCharacters
            for characterIndex, assignedCharacter in ipairs(assignedCharacters) do
                if assignedCharacter.EntityUUID == directlyControlledCharacterUuid then
                    print("directly controlled character index", characterIndex)
                    DirectlyControlledCharacterIndex = characterIndex
                end
            end
            break
        end
    end
end

local function getPositionInfo()
    local pickingHelper = Ext.UI.GetPickingHelper(1)
    if pickingHelper and pickingHelper.Inner and pickingHelper.Inner.Position then
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

local function postModeToggle()
    Ext.ClientNet.PostMessageToServer("ModeToggle", "")
end

local function postCompanionAIToggle()
    Ext.ClientNet.PostMessageToServer("CompanionAIToggle", "")
end

local function postQueueCompanionAIActions()
    Ext.ClientNet.PostMessageToServer("QueueCompanionAIActions", "")
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

local function postLeaderboardToggle()
    Ext.ClientNet.PostMessageToServer("LeaderboardToggle", "")
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
        if isKeybindingPressed(e, ModeToggleHotkey) then
            postModeToggle()
            keybindingPressed = true
        end
        if isKeybindingPressed(e, CompanionAIToggleHotkey) then
            postCompanionAIToggle()
            keybindingPressed = true
        end
        if isKeybindingPressed(e, QueueCompanionAIActionsHotkey) then
            postQueueCompanionAIActions()
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
        if isKeybindingPressed(e, LeaderboardToggleHotkey) then
            postLeaderboardToggle()
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
    local override = false
    Ext.ClientNet.PostMessageToServer("ControllerButtonPressed", button)
    if button == "A" then
        postClickPosition()
    end
    if isControllerKeybindingPressed(ControllerModToggleHotkey) then
        postModToggle()
        if ControllerModToggleHotkeyOverride then
            override = true
        end
    end
    if isControllerKeybindingPressed(ControllerModeToggleHotkey) then
        postModeToggle()
        if ControllerModeToggleHotkeyOverride then
            override = true
        end
    end
    if isControllerKeybindingPressed(ControllerCompanionAIToggleHotkey) then
        postCompanionAIToggle()
        if ControllerCompanionAIToggleHotkeyOverride then
            override = true
        end
    end
    if isControllerKeybindingPressed(ControllerQueueCompanionAIActionsHotkey) then
        postQueueCompanionAIActions()
        if ControllerQueueCompanionAIActionsHotkeyOverride then
            override = true
        end
    end
    if isControllerKeybindingPressed(ControllerFullAutoToggleHotkey) then
        postFullAutoToggle()
        if ControllerFullAutoToggleHotkeyOverride then
            override = true
        end
    end
    if isControllerKeybindingPressed(ControllerPauseToggleHotkey) then
        postPauseToggle()
        if ControllerPauseToggleHotkeyOverride then
            override = true
        end
    end
    if isControllerKeybindingPressed(ControllerTargetCloserEnemyHotkey) then
        postTargetCloserEnemy()
        if ControllerTargetCloserEnemyHotkeyOverride then
            override = true
        end
    end
    if isControllerKeybindingPressed(ControllerTargetFartherEnemyHotkey) then
        postTargetFartherEnemy()
        if ControllerTargetFartherEnemyHotkeyOverride then
            override = true
        end
    end
    if isControllerKeybindingPressed(ControllerOnMeHotkey) then
        postOnMe()
        if ControllerOnMeHotkeyOverride then
            override = true
        end
    end
    if isControllerKeybindingPressed(ControllerAttackMyTargetHotkey) then
        postAttackMyTarget()
        if ControllerAttackMyTargetHotkeyOverride then
            override = true
        end
    end
    if isControllerKeybindingPressed(ControllerAttackMoveHotkey) then
        postAttackMove()
        if ControllerAttackMoveHotkeyOverride then
            override = true
        end
    end
    if isControllerKeybindingPressed(ControllerRequestHealHotkey) then
        postRequestHeal()
        if ControllerRequestHealHotkeyOverride then
            override = true
        end
    end
    if isControllerKeybindingPressed(ControllerChangeTacticsHotkey) then
        postChangeTactics()
        if ControllerChangeTacticsHotkeyOverride then
            override = true
        end
    end
    if isControllerKeybindingPressed(ControllerLeaderboardToggleHotkey) then
        postLeaderboardToggle()
        if ControllerLeaderboardToggleHotkeyOverride then
            override = true
        end
    end
    for actionButtonLabel, controllerActionButtonHotkey in ipairs(ControllerActionButtonHotkeys) do
        if isControllerKeybindingPressed(controllerActionButtonHotkey) then
            postControllerActionButton(actionButtonLabel)
            if ControllerActionButtonHotkeysOverride[actionButtonLabel] then
                override = true
            end
        end
    end
    return override
end

local function onControllerAxisInput(e)
    local axis = tostring(e.Axis)
    local override = false
    if axis == "TriggerLeft" or axis == "TriggerRight" then
        if IsControllerButtonPressed[axis] then
            if e.Value == 0.0 then
                IsControllerButtonPressed[axis] = false
            end
        else
            IsControllerButtonPressed[axis] = true
            override = onControllerButtonPressed(axis)
            if override then
                e:PreventAction()
            end
        end
    end
end

local function onControllerButtonInput(e)
    local button = tostring(e.Button)
    local override = false
    IsControllerButtonPressed[button] = e.Pressed
    if e.Pressed then
        override = onControllerButtonPressed(button)
        if override then
            e:PreventAction()
        end
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

local function getDisplayName(uuid)
    local entity = Ext.Entity.Get(uuid)
    if not entity then
        return ""
    end
    if entity.CustomName and entity.CustomName.Name then
        return entity.CustomName.Name
    end
    if not entity.DisplayName or not entity.DisplayName.NameKey or not entity.DisplayName.NameKey.Handle or not entity.DisplayName.NameKey.Handle.Handle then
        return ""
    end
    return Ext.Loca.GetTranslatedString(entity.DisplayName.NameKey.Handle.Handle)
end

local function isPartyMember(uuid)
    if uuid then
        local entity = Ext.Entity.Get(uuid)
        if entity and entity.PartyMember then
            return true
        end
    end
    return false
end

local function showLeaderboard(data)
    if LeaderboardWindow then
        LeaderboardWindow:Destroy()
        cellRefs.party = {}
        cellRefs.enemy = {}
    end
    local damageWidth, takenWidth, killsWidth, healingWidth, receivedWidth = #"Damage", #"Taken", #"Kills", #"Healing", #"Healed"
    local nameWidth, partyCount, enemyCount = 0, 0, 0
    for uuid, stats in pairs(data) do
        nameWidth = math.max(nameWidth, #stats.name)
        damageWidth = math.max(damageWidth, #tostring(stats.damageDone or 0))
        takenWidth = math.max(takenWidth, #tostring(stats.damageTaken or 0))
        killsWidth = math.max(killsWidth, #tostring(stats.kills or 0))
        healingWidth = math.max(healingWidth, #tostring(stats.healingDone or 0))
        receivedWidth = math.max(receivedWidth, #tostring(stats.healingTaken or 0))
        if isPartyMember(uuid) then
            partyCount = partyCount + 1
        else
            enemyCount = enemyCount + 1
        end
    end
    local numColumns = 6
    local windowWidth = (nameWidth + damageWidth + takenWidth + killsWidth + healingWidth + receivedWidth)*8 + (numColumns - 1)*16 + 100
    local rowCount = 3 + partyCount + enemyCount
    local windowHeight = rowCount*18 + 20
    LeaderboardWindow = Ext.IMGUI.NewWindow("Leaderboard")
    LeaderboardWindow:SetSize({windowWidth, windowHeight})
    LeaderboardWindow.Closeable = true
    LeaderboardWindow.NoFocusOnAppearing = true
    -- LeaderboardWindow:AddSeparatorText("Party Totals"):SetColor("Text", lightYellow)
    local partyTable = LeaderboardWindow:AddTable("PartyTotals", numColumns)
    cellRefs.partyTable = partyTable
    do
        local hdr = partyTable:AddRow()
        hdr:AddCell():AddText("")
        hdr:AddCell():AddText("Damage"):SetColor("Text", mediumYellow)
        hdr:AddCell():AddText("Taken"):SetColor("Text", mediumYellow)
        hdr:AddCell():AddText("Kills"):SetColor("Text", mediumYellow)
        hdr:AddCell():AddText("Healing"):SetColor("Text", mediumYellow)
        hdr:AddCell():AddText("Healed"):SetColor("Text", mediumYellow)
    end
    local party = {}
    for uuid, stats in pairs(data) do
        if isPartyMember(uuid) then
            party[#party + 1] = {uuid = uuid, stats = stats}
        end
    end
    table.sort(party, function (a, b)
        return (a.stats.damageDone or 0) > (b.stats.damageDone or 0)
    end)
    for _, e in ipairs(party) do
        local row = partyTable:AddRow()
        row:AddCell():AddText(e.stats.name):SetColor("Text", lightBlue)
        local dmgCell = row:AddCell():AddText(tostring(e.stats.damageDone or 0))
        local takenCell = row:AddCell():AddText(tostring(e.stats.damageTaken or 0))
        local killsCell = row:AddCell():AddText(tostring(e.stats.kills or 0))
        local healCell = row:AddCell():AddText(tostring(e.stats.healingDone or 0))
        local recvCell = row:AddCell():AddText(tostring(e.stats.healingTaken or 0))
        cellRefs.party[e.uuid] = {damage = dmgCell, taken = takenCell, kills = killsCell, healing = healCell, received = recvCell}
    end
    -- LeaderboardWindow:AddSeparatorText("Enemy Totals"):SetColor("Text", lightYellow)
    LeaderboardWindow:AddSeparator()
    local enemyTable = LeaderboardWindow:AddTable("EnemyTotals", numColumns)
    cellRefs.enemyTable = enemyTable
    -- do
    --     local hdr = enemyTable:AddRow()
    --     hdr:AddCell():AddText("")
    --     hdr:AddCell():AddText("Damage"):SetColor("Text", mediumYellow)
    --     hdr:AddCell():AddText("Taken"):SetColor("Text", mediumYellow)
    --     hdr:AddCell():AddText("Kills"):SetColor("Text", mediumYellow)
    --     hdr:AddCell():AddText("Healing"):SetColor("Text", mediumYellow)
    --     hdr:AddCell():AddText("Healed"):SetColor("Text", mediumYellow)
    -- end
    local enemy = {}
    for uuid, stats in pairs(data) do
        if not isPartyMember(uuid) then
            enemy[#enemy + 1] = {uuid = uuid, stats = stats}
        end
    end
    table.sort(enemy, function (a, b)
        return (a.stats.damageDone or 0) > (b.stats.damageDone or 0)
    end)
    for _, e in ipairs(enemy) do
        local row = enemyTable:AddRow()
        row:AddCell():AddText(e.stats.name):SetColor("Text", lightRed)
        local dmgCell = row:AddCell():AddText(tostring(e.stats.damageDone or 0))
        local takenCell = row:AddCell():AddText(tostring(e.stats.damageTaken or 0))
        local killsCell = row:AddCell():AddText(tostring(e.stats.kills or 0))
        local healCell = row:AddCell():AddText(tostring(e.stats.healingDone or 0))
        local recvCell = row:AddCell():AddText(tostring(e.stats.healingTaken or 0))
        cellRefs.enemy[e.uuid] = {damage = dmgCell, taken = takenCell, kills = killsCell, healing = healCell, received = recvCell}
    end
end

local function updateLeaderboard(data)
    for uuid, stats in pairs(data) do
        local refs = cellRefs.party[uuid] or cellRefs.enemy[uuid]
        if refs then
            refs.damage.Label = tostring(stats.damageDone or 0)
            refs.taken.Label = tostring(stats.damageTaken or 0)
            refs.kills.Label = tostring(stats.kills or 0)
            refs.healing.Label = tostring(stats.healingDone or 0)
            refs.received.Label = tostring(stats.healingTaken or 0)
        else
            if isPartyMember(uuid) then
                local row = cellRefs.partyTable:AddRow()
                row:AddCell():AddText(stats.name):SetColor("Text", lightBlue)
                local dmgCell = row:AddCell():AddText(tostring(stats.damageDone or 0))
                local takenCell = row:AddCell():AddText(tostring(stats.damageTaken or 0))
                local killsCell = row:AddCell():AddText(tostring(stats.kills or 0))
                local healCell = row:AddCell():AddText(tostring(stats.healingDone or 0))
                local recvCell = row:AddCell():AddText(tostring(stats.healingTaken or 0))
                cellRefs.party[uuid] = {damage = dmgCell, taken = takenCell, kills = killsCell, healing = healCell, received = recvCell}
            else
                local row = cellRefs.enemyTable:AddRow()
                row:AddCell():AddText(stats.name):SetColor("Text", lightRed)
                local dmgCell = row:AddCell():AddText(tostring(stats.damageDone or 0))
                local takenCell = row:AddCell():AddText(tostring(stats.damageTaken or 0))
                local killsCell = row:AddCell():AddText(tostring(stats.kills or 0))
                local healCell = row:AddCell():AddText(tostring(stats.healingDone or 0))
                local recvCell = row:AddCell():AddText(tostring(stats.healingTaken or 0))
                cellRefs.enemy[uuid] = {damage = dmgCell, taken = takenCell, kills = killsCell, healing = healCell, received = recvCell}
            end
        end
    end
end

local function disableDynamicCombatCamera()
    local globalSwitches = Ext.Utils.GetGlobalSwitches()
    globalSwitches.GameCameraEnableDynamicCombatCamera = false
end

-- thank u focus
local function directlyControlCharacterByIndex(characterIndex)
    if characterIndex then
        for _, child in ipairs(Ext.UI:GetRoot():Find("ContentRoot").Children) do
            if child.Name == "PlayerPortraits" and child.DataContext and child.DataContext.CurrentPlayer and child.DataContext.CurrentPlayer.AssignedCharacters then
                local character = child.DataContext.CurrentPlayer.AssignedCharacters[characterIndex]
                if character then
                    print("setting to character index", character, characterIndex)
                    child.DataContext.SelectCharacter:Execute(character)
                end
                break
            end
        end
    end
end

local function onNetMessage(data)
    if data.Channel == "GainedControl" then
        DirectlyControlledCharacter = data.Payload
    elseif data.Channel == "AwaitingTarget" then
        AwaitingTarget = data.Payload == "1"
    elseif data.Channel == "Notification" then
        showNotification(Ext.Json.Parse(data.Payload))
    elseif data.Channel == "Leaderboard" then
        showLeaderboard(Ext.Json.Parse(data.Payload))
    elseif data.Channel == "UpdateLeaderboard" then
        if LeaderboardWindow then
            updateLeaderboard(Ext.Json.Parse(data.Payload))
        end
    elseif data.Channel == "DisableDynamicCombatCamera" then
        disableDynamicCombatCamera()
    -- elseif data.Channel == "NextCombatRound" then
    --     setDirectlyControlledCharacterIndex()
    -- elseif data.Channel == "CombatRoundStarted" then
    --     directlyControlCharacterByIndex(DirectlyControlledCharacterIndex)
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
