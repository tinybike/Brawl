local ModToggleHotkey = "F9"
local CompanionAIToggleHotkey = "F11"
local FullAutoToggleHotkey = "F6"
if MCM then
    ModToggleHotkey = string.upper(MCM.Get("mod_toggle_hotkey"))
    CompanionAIToggleHotkey = string.upper(MCM.Get("companion_ai_toggle_hotkey"))
    FullAutoToggleHotkey = string.upper(MCM.Get("full_auto_toggle_hotkey"))
end
local IsShiftPressed = false
local IsSpacePressed = false
local DirectlyControlledCharacter = nil
-- local UseCombatControllerControls = false
local IsMouseOverHotBar = false
local HotBarListeners = nil
local ActionQueue = {}
local ShouldPreventAction = {}

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
    return findNodeByName(getHotBar(), "ExitFTBButton")
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
            return entity.Uuid.EntityUuid
        end
    end
end

local function isInFTB(uuid)
    local entity = Ext.Entity.Get(uuid)
    return entity.FTBParticipant and entity.FTBParticipant.field_18 ~= nil
end

local function getPositionInfo()
    local pickingHelper = Ext.UI.GetPickingHelper(1)
    -- _D(pickingHelper)
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

local function checkCancelMidAction()
    local uuid = getDirectlyControlledCharacter()
    if ShouldPreventAction[uuid] and isInFTB(uuid) then
        ShouldPreventAction[uuid] = false
        ActionQueue[uuid] = {}
        print("Reset action queue", uuid)
    end
end

local function onKeyInput(e)
    if e.Repeat == false then
        if e.Key == ModToggleHotkey and e.Event == "KeyDown" then
            Ext.ClientNet.PostMessageToServer("ModToggle", tostring(e.Key))
        elseif e.Key == CompanionAIToggleHotkey and e.Event == "KeyDown" then
            Ext.ClientNet.PostMessageToServer("CompanionAIToggle", tostring(e.Key))
        elseif e.Key == FullAutoToggleHotkey and e.Event == "KeyDown" then
            Ext.ClientNet.PostMessageToServer("FullAutoToggle", tostring(e.Key))
        elseif e.Key == "ESCAPE" and e.Event == "KeyDown" then
            checkCancelMidAction()
        -- nb: what about rebindings? is there a way to look these up in SE?
        elseif e.Key == "LSHIFT" or e.Key == "RSHIFT" then
            IsShiftPressed = e.Event == "KeyDown"
        elseif e.Key == "SPACE" then
            IsSpacePressed = e.Event == "KeyDown"
        end
        if IsShiftPressed and IsSpacePressed and isInFTB(getDirectlyControlledCharacter()) then
            Ext.ClientNet.PostMessageToServer("ExitFTB", "")
        end
    end
end

local function mapHotBarButtons(node, uuid, attachListeners, visited)
    visited = visited or {}
    if not visited[node] then
        visited[node] = true
        attachListeners(node, uuid, visited)
        local childrenCount = safeGetProperty(node, "ChildrenCount") or 0
        local visualChildrenCount = safeGetProperty(node, "VisualChildrenCount") or 0
        if childrenCount > 0 then
            for i = 1, childrenCount do
                local childNode = node:Child(i)
                if childNode then
                    mapHotBarButtons(childNode, uuid, attachListeners, visited)
                end
            end
        end
        if visualChildrenCount > 0 then
            for i = 1, visualChildrenCount do
                local visualChildNode = node:VisualChild(i)
                if visualChildNode then
                    mapHotBarButtons(visualChildNode, uuid, attachListeners, visited)
                end
            end
        end
    end
end

local function attachListenersToUpcastButtons(node, uuid, visited)
    local nodeType = tostring(node.Type)
    if nodeType == "ls.LSButton" then
        local name = node:GetProperty("Name")
        if tostring(name) == "HotbarslotBtn" then
            print("upcast buttons", nodeType, name)
            node:Subscribe("GotMouseCapture", function (upcastNode, _)
                print("Upcast GotMouseCapture", upcastNode, nodeType, name)
                local dataContext = upcastNode:GetProperty("DataContext")
                if not dataContext:GetProperty("IsFake") then
                    ActionQueue[uuid].isUpcasted = dataContext:GetProperty("IsUpcasted")
                    ActionQueue[uuid].slotLevel = dataContext:GetProperty("SlotLevel")
                    -- ActionQueue[uuid].resourceName = dataContext:GetProperty("ResourceName")
                    print("Updated ActionQueue with upcasted spell")
                    _D(ActionQueue)
                end
            end)
        end
    end
end

local function attachListenersToButtons(node, uuid, visited)
    local nodeType = tostring(node.Type)
    if nodeType == "ls.LSButton" or nodeType == "Button" then
        local name = node:GetProperty("Name")
        if name ~= nil then
            local nodeName = tostring(name)
            local isRegularActionButton = nodeType == "ls.LSButton" and nodeName == "contentContainer"
            local isMainAttackButton = nodeType == "ls.LSButton" and nodeName == "MainAttack"
            local isMeleeWeaponButton = nodeType == "Button" and nodeName == "MeleeWeapon"
            local isRangedWeaponButton = nodeType == "Button" and nodeName == "RangedWeapon"
            if isRegularActionButton or isMainAttackButton or isMeleeWeaponButton or isRangedWeaponButton then
                node:Subscribe("GotMouseCapture", function (buttonNode, _)
                    print("GotMouseCapture", buttonNode, nodeType, nodeName)
                    if isInFTB(uuid) then
                        -- nb: use OnCreateDeferred instead? what is the component type to listen for?
                        Ext.Timer.WaitFor(1000, function ()
                            mapHotBarButtons(getHotBar(), uuid, attachListenersToUpcastButtons)
                        end)
                        local spell = buttonNode:Child(1):GetProperty("Spell")
                        ActionQueue[uuid] = {spellName = spell:GetProperty("PrototypeID"), isUpcasted = false}
                        print("Updated ActionQueue")
                        _D(ActionQueue)
                    end
                end)
            end
        end
    end
end

-- thank u volitio
function checkForHotBar(uuid)
    -- nb: use OnCreateDeferred instead?
    Ext.Timer.WaitFor(1000, function ()
        local hotBar = getHotBar()
        if hotBar == nil then
            return checkForHotBar(uuid)
        end
        if HotBarListeners ~= nil then
            hotBar:Unsubscribe(HotBarListeners.onMouseEnter)
            hotBar:Unsubscribe(HotBarListeners.onMouseLeave)
        end
        HotBarListeners = {
            onMouseEnter = hotBar:Subscribe("MouseEnter", function (_, _) IsMouseOverHotBar = true end),
            onMouseLeave = hotBar:Subscribe("MouseLeave", function (_, _) IsMouseOverHotBar = false end),
        }
        mapHotBarButtons(hotBar, uuid, attachListenersToButtons)
    end)
end

local function onNetMessage(data)
    if data.Channel == "Started" then
        checkForHotBar(getDirectlyControlledCharacter())
    elseif data.Channel == "GainedControl" then
        print("gained control", data.Payload)
        DirectlyControlledCharacter = data.Payload
        checkForHotBar(DirectlyControlledCharacter)
    elseif data.Channel == "ClearActionQueue" then
        ActionQueue[data.Payload] = nil
    elseif data.Channel == "SpellCastIsCasting" then
        print("Client got SpellCastIsCasting", data.Payload)
        ShouldPreventAction[data.Payload] = true
    end
end

local function onMouseButtonInput(e)
    if e.Pressed then
        if e.Button == 1 then
            if not IsMouseOverHotBar then
                print("mouse button input 1")
                local uuid = getDirectlyControlledCharacter()
                print(uuid)
                print("should prevent action?")
                _D(ShouldPreventAction)
                if ShouldPreventAction[uuid] and isInFTB(uuid) then
                    if ActionQueue[uuid] ~= nil and ActionQueue[uuid].spellName ~= nil then
                        ActionQueue[uuid].target = getPositionInfo()
                        print("updated ActionQueue with target")
                        _D(ActionQueue)
                        Ext.ClientNet.PostMessageToServer("ActionQueue", Ext.Json.Stringify(ActionQueue))
                        ShouldPreventAction[uuid] = false
                        e:PreventAction()
                    else
                        print("No spell name found - what happened?")
                        _D(ActionQueue)
                    end
                end
            end
        elseif e.Button == 3 then
            checkCancelMidAction()
        end
    end
end

local function onSessionLoaded()
    Ext.Events.KeyInput:Subscribe(onKeyInput)
    Ext.Events.ControllerButtonInput:Subscribe(onControllerButtonInput)
    Ext.Events.MouseButtonInput:Subscribe(onMouseButtonInput)
    Ext.Events.NetMessage:Subscribe(onNetMessage)
end

Ext.Events.SessionLoaded:Subscribe(onSessionLoaded)
