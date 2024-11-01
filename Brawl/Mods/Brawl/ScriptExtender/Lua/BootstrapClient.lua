local ModToggleHotkey = "F9"
local CompanionAIToggleHotkey = "F11"
local FullAutoToggleHotkey = "F6"
if MCM then
    ModToggleHotkey = string.upper(MCM.Get("mod_toggle_hotkey"))
    CompanionAIToggleHotkey = string.upper(MCM.Get("companion_ai_toggle_hotkey"))
    FullAutoToggleHotkey = string.upper(MCM.Get("full_auto_toggle_hotkey"))
end

local ActionQueue = {}
local Players = {}
local ShouldPreventAction = {}
local ListenersAttached = {}

-- thank u focus
local function safeGetProperty(obj, propName)
    local success, result = pcall(function() return obj[propName] end)
    if success then
        return result
    else
        return nil
    end
end

-- thank u focus
local function findNodeByName(node, targetName, visited)
    visited = visited or {}
    if visited[node] then
        return nil
    end
    visited[node] = true
    if node:GetProperty("Name") == targetName then
        return node
    end
    local childrenCount = safeGetProperty(node, "ChildrenCount") or 0
    for i = 1, childrenCount do
        local childNode = node:Child(i)
        if childNode then
            local foundNode = findNodeByName(childNode, targetName, visited)
            if foundNode then
                return foundNode
            end
        end
    end
    local visualChildrenCount = safeGetProperty(node, "VisualChildrenCount") or 0
    for i = 1, visualChildrenCount do
        local visualChildNode = node:VisualChild(i)
        if visualChildNode then
            local foundNode = findNodeByName(visualChildNode, targetName, visited)
            if foundNode then
                return foundNode
            end
        end
    end
    return nil
end

local function getHotBar()
    return findNodeByName(Ext.UI.GetRoot():Child(1):Child(1), "HotBar")
end

local function getFTBItem()
    return findNodeByName(Ext.UI.GetRoot():Child(1):Child(1), "FTBItem")
end

local function getEnterFTBButton()
    return findNodeByName(getHotBar(), "EnterFTBButton")
end

local function getExitFTBButton()
    local button = findNodeByName(getHotBar(), "ExitFTBButton")
    print("ftb exit main", button)
    return button
end

local function getPositionInfo()
    local pickingHelper = Ext.UI.GetPickingHelper(1)
    if pickingHelper.Inner and pickingHelper.Inner.Position then
        -- _D(pickingHelper)
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

-- UseCombatControllerControls = false

-- Ext.Events.NetMessage:Subscribe(function (data)
--     if data.Channel == "UseCombatControllerControls" then
--         print("got msg from client")
--         print("use combat controls", UseCombatControllerControls)
--         UseCombatControllerControls = data.Payload == "1"
--     end
-- end)

local function onControllerButtonInput(e)
    if e.Pressed == true then
        Ext.ClientNet.PostMessageToServer("ControllerButtonPressed", tostring(e.Button))
        -- if UseCombatControllerControls then
        --     e:PreventAction()
        -- end
    end
end

local function onKeyInput(e)
    if e.Key == ModToggleHotkey and e.Event == "KeyDown" and e.Repeat == false then
        Ext.ClientNet.PostMessageToServer("ModToggle", tostring(e.Key))
    elseif e.Key == CompanionAIToggleHotkey and e.Event == "KeyDown" and e.Repeat == false then
        Ext.ClientNet.PostMessageToServer("CompanionAIToggle", tostring(e.Key))
    elseif e.Key == FullAutoToggleHotkey and e.Event == "KeyDown" and e.Repeat == false then
        Ext.ClientNet.PostMessageToServer("FullAutoToggle", tostring(e.Key))
    end
end

-- thank u aahz
local function getLocalControlledCharacter()
    for _, entity in pairs(Ext.Entity.GetAllEntitiesWithComponent("ClientControl")) do
        if entity.UserReservedFor.UserID == 1 then
            return entity.Uuid.EntityUuid
        end
    end
end

local function isInFTB(entity)
    return entity.FTBParticipant and entity.FTBParticipant.field_18 ~= nil
end

local function attachListenersToButtons(node, visited, uuid)
    if not visited then
        visited = {}
    end
    if visited[node] then
        return
    end
    visited[node] = true
    local properties = node:GetAllProperties()
    local name = properties and properties.Name or "nil"
    local nodeType = tostring(node.Type)
    local nodeName = tostring(name)
    local isRegularActionButton = nodeType == "ls.LSButton" and nodeName == "contentContainer"
    local isMainAttackButton = nodeType == "ls.LSButton" and nodeName == "MainAttack"
    local isMeleeWeaponButton = nodeType == "Button" and nodeName == "MeleeWeapon"
    local isRangedWeaponButton = nodeType == "Button" and nodeName == "RangedWeapon"
    if isRegularActionButton or isMainAttackButton or isMeleeWeaponButton or isRangedWeaponButton then
        print("type=" .. tostring(node.Type) .. ", name=" .. tostring(name))
        node:Subscribe("GotMouseCapture", function (e, t)
            print("GotMouseCapture", e, t, tostring(name))
            local entity = Ext.Entity.Get(uuid)
            if isInFTB(entity) then
                local spellProperties = e:Child(1):GetAllProperties().Spell:GetAllProperties()
                _D(spellProperties)
                local spellName = spellProperties.PrototypeID
                print(spellName)
                -- todo: action & bonus action
                -- ActionQueue[uuid] = ActionQueue[uuid] or {}
                -- for _, cost in ipairs(spellProperties.CostSummary) do
                --     -- _D(cost:GetAllProperties())
                --     if cost.TypeId == "ActionPoint" then
                --         if next(ActionQueue[uuid]) ~= nil then
                --             for i, action in ipairs(ActionQueue[uuid]) do
                --             end
                --         end
                --         table.insert(ActionQueue[uuid], {spellName = spellName, target = nil})
                --     elseif cost.TypeId == "BonusActionPoint" then
                --     end
                -- end
                ActionQueue[uuid] = {spellName = spellName, target = nil}
                _D(ActionQueue)
            end
            -- _D(e:GetAllProperties())
            -- local entity = Ext.Entity.Get(uuid)
            -- local defaultBarContainer = entity.HotbarContainer.Containers.DefaultBarContainer
            -- _D(defaultBarContainer[6].Elements[1])
        end)
    end
    local childrenCount = safeGetProperty(node, "ChildrenCount") or 0
    for i = 1, childrenCount do
        local childNode = node:Child(i)
        if childNode then
            attachListenersToButtons(childNode, visited, uuid)
        end
    end
    local visualChildrenCount = safeGetProperty(node, "VisualChildrenCount") or 0
    for i = 1, visualChildrenCount do
        local visualChildNode = node:VisualChild(i)
        if visualChildNode then
            attachListenersToButtons(visualChildNode, visited, uuid)
        end
    end
end

-- thank u volitio
local function checkForHotBar(uuid)
    Ext.Timer.WaitFor(1000, function ()
        local hotBar = getHotBar()
        if hotBar == nil then
            return checkForHotBar(uuid)
        end
        attachListenersToButtons(hotBar, false, uuid)
        ListenersAttached[uuid] = true
    end)
end

local function onNetMessage(data)
    if data.Channel == "Started" then
        print("started client")
        local uuid = getLocalControlledCharacter()
        if not ListenersAttached[uuid] then
            checkForHotBar(uuid)
        end
    elseif data.Channel == "GainedControl" then
        print("gained control")
        local uuid = data.Payload
        print(uuid, ListenersAttached[uuid])
        if not ListenersAttached[uuid] then
            checkForHotBar(uuid)
        end
    elseif data.Channel == "ClearActionQueue" then
        local uuid = data.Payload
        ActionQueue[data.Payload] = nil
    elseif data.Channel == "SyncPlayers" then
        Players = Ext.Json.Parse(data.Payload)
    elseif data.Channel == "DynamicAnimationTags" then
        print("Client got DAT", data.Payload)
        local uuid = data.Payload
        ShouldPreventAction[uuid] = true
    end
end

local function onMouseButtonInput(e)
    if e.Pressed and e.Button == 1 then
        local uuid = getLocalControlledCharacter()
        print("MB input 1", uuid, ShouldPreventAction[uuid])
        local entity = Ext.Entity.Get(uuid)
        if isInFTB(entity) and ShouldPreventAction[uuid] then
            local positionInfo = getPositionInfo()
            ActionQueue[uuid] = ActionQueue[uuid] or {}
            if ActionQueue[uuid] == nil then
                print("No spell name found")
                return
            end
            ActionQueue[uuid].target = positionInfo
            _D(ActionQueue)
            Ext.ClientNet.PostMessageToServer("ActionQueue", Ext.Json.Stringify(ActionQueue))
            e:PreventAction()
            ShouldPreventAction[uuid] = false
            if entity.SpellCastIsCasting ~= nil and entity.SpellCastIsCasting.Cast ~= nil then
                entity.TurnBased.CanAct_M = false
                entity.TurnBased.HadTurnInCombat = false
                entity.TurnBased.IsInCombat_M = false
            end
        end
    end
    if e.Pressed and e.Button == 3 then
        local uuid = getLocalControlledCharacter()
        if isInFTB(Ext.Entity.Get(uuid)) and ShouldPreventAction[uuid] then
            ShouldPreventAction[uuid] = false
            ActionQueue[uuid] = {}
            print("Reset action queue")
        end
        -- Ext.ClientNet.PostMessageToServer("ClickedOn", Ext.Json.Stringify(getPositionInfo()))
    end
end

local function onSessionLoaded()
    Ext.Events.KeyInput:Subscribe(onKeyInput)
    Ext.Events.ControllerButtonInput:Subscribe(onControllerButtonInput)
    Ext.Events.MouseButtonInput:Subscribe(onMouseButtonInput)
    Ext.Events.NetMessage:Subscribe(onNetMessage)
end

Ext.Events.SessionLoaded:Subscribe(onSessionLoaded)
