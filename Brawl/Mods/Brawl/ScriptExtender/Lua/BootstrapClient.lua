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
local UseCombatControllerControls = false
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
    local node = findNodeByName(Ext.UI.GetRoot(), "FTBItem")
    _D(node)
    return node
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

local function attachListenersToUpcastButtons(node, uuid, visited)
    local nodeType = tostring(node.Type)
    if nodeType == "ls.LSButton" then
        local name = node:GetProperty("Name")
        if tostring(name) == "HotbarslotBtn" then
            print("upcast buttons", nodeType, name)
            node:Subscribe("GotMouseCapture", function (upcastNode, _)
                print("Upcast GotMouseCapture", upcastNode, nodeType, name)
                local dataContext = upcastNode:GetProperty("DataContext")
                if dataContext ~= nil then
                    if not dataContext:GetProperty("IsFake") then
                        if dataContext:GetProperty("IsUpcasted") then
                            ActionQueue[uuid].upcastLevel = dataContext:GetProperty("SlotLevel")
                        else
                            ActionQueue[uuid].upcastLevel = nil
                        end
                        print("Updated ActionQueue")
                        _D(ActionQueue)
                    end
                else
                    local spell = upcastNode:Child(1):GetProperty("Spell")
                    ActionQueue[uuid].variant = spell:GetProperty("PrototypeID")
                    print("Added variant to ActionQueue")
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
                        ActionQueue[uuid] = {spellName = spell:GetProperty("PrototypeID")}
                        print("Added spell to ActionQueue")
                        _D(ActionQueue)
                    end
                end)
            end
        end
    end
end

local function investigateNode(node)
    local nodeType = tostring(node.Type)
    print(nodeType, node:GetProperty("Name"))
    -- nodeType == "ls.LSButton" and name == "UseSlotBinding"
    -- nodeType == "ls.LSButton" and name == "ShowContextMenu"
    -- nodeType == "ls.LSButton" and name == "SelectButtonVisual"
    -- if nodeType == "ls.LSButton" or nodeType == "Button" then
    local name = node:GetProperty("Name")
    if name ~= nil then
        local nodeName = tostring(name)
        _D(node:GetAllProperties())
        node:Subscribe("GotFocus", function (e, t) print("GotFocus", e, t, nodeType, nodeName) end)
        node:Subscribe("GotKeyboardFocus", function (e, t) print("GotKeyboardFocus", e, t, nodeType, nodeName) end)
        node:Subscribe("GotMouseCapture", function (e, t) print("GotMouseCapture", e, t, nodeType, nodeName) end)
        node:Subscribe("KeyDown", function (e, t) print("KeyDown", e, t, nodeType, nodeName) end)
        node:Subscribe("KeyUp", function (e, t) print("KeyUp", e, t, nodeType, nodeName) end)
        node:Subscribe("LostFocus", function (e, t) print("LostFocus", e, t, nodeType, nodeName) end)
        node:Subscribe("LostKeyboardFocus", function (e, t) print("LostKeyboardFocus", e, t, nodeType, nodeName) end)
        node:Subscribe("LostMouseCapture", function (e, t) print("LostMouseCapture", e, t, nodeType, nodeName) end)
        node:Subscribe("MouseDown", function (e, t) print("MouseDown", e, t, nodeType, nodeName) end)
        node:Subscribe("MouseEnter", function (e, t) print("MouseEnter", e, t, nodeType, nodeName) end)
        node:Subscribe("MouseLeave", function (e, t) print("MouseLeave", e, t, nodeType, nodeName) end)
        node:Subscribe("MouseLeftButtonDown", function (e, t) print("MouseLeftButtonDown", e, t, nodeType, nodeName) end)
        node:Subscribe("MouseLeftButtonUp", function (e, t) print("MouseLeftButtonUp", e, t, nodeType, nodeName) end)
        node:Subscribe("MouseMove", function (e, t) print("MouseMove", e, t, nodeType, nodeName) end)
        node:Subscribe("MouseRightButtonDown", function (e, t) print("MouseRightButtonDown", e, t, nodeType, nodeName) end)
        node:Subscribe("MouseRightButtonUp", function (e, t) print("MouseRightButtonUp", e, t, nodeType, nodeName) end)
        node:Subscribe("MouseUp", function (e, t) print("MouseUp", e, t, nodeType, nodeName) end)
        node:Subscribe("MouseWheel", function (e, t) print("MouseWheel", e, t, nodeType, nodeName) end)
        node:Subscribe("TouchDown", function (e, t) print("TouchDown", e, t, nodeType, nodeName) end)
        node:Subscribe("TouchMove", function (e, t) print("TouchMove", e, t, nodeType, nodeName) end)
        node:Subscribe("TouchUp", function (e, t) print("TouchUp", e, t, nodeType, nodeName) end)
        node:Subscribe("TouchEnter", function (e, t) print("TouchEnter", e, t, nodeType, nodeName) end)
        node:Subscribe("TouchLeave", function (e, t) print("TouchLeave", e, t, nodeType, nodeName) end)
        node:Subscribe("GotTouchCapture", function (e, t) print("GotTouchCapture", e, t, nodeType, nodeName) end)
        node:Subscribe("LostTouchCapture", function (e, t) print("LostTouchCapture", e, t, nodeType, nodeName) end)
        node:Subscribe("PreviewTouchDown", function (e, t) print("PreviewTouchDown", e, t, nodeType, nodeName) end)
        node:Subscribe("PreviewTouchMove", function (e, t) print("PreviewTouchMove", e, t, nodeType, nodeName) end)
        node:Subscribe("PreviewTouchUp", function (e, t) print("PreviewTouchUp", e, t, nodeType, nodeName) end)
        node:Subscribe("ManipulationStarting", function (e, t) print("ManipulationStarting", e, t, nodeType, nodeName) end)
        node:Subscribe("ManipulationStarted", function (e, t) print("ManipulationStarted", e, t, nodeType, nodeName) end)
        node:Subscribe("ManipulationDelta", function (e, t) print("ManipulationDelta", e, t, nodeType, nodeName) end)
        node:Subscribe("ManipulationInertiaStarting", function (e, t) print("ManipulationInertiaStarting", e, t, nodeType, nodeName) end)
        node:Subscribe("ManipulationCompleted", function (e, t) print("ManipulationCompleted", e, t, nodeType, nodeName) end)
        node:Subscribe("Tapped", function (e, t) print("Tapped", e, t, nodeType, nodeName) end)
        node:Subscribe("DoubleTapped", function (e, t) print("DoubleTapped", e, t, nodeType, nodeName) end)
        node:Subscribe("Holding", function (e, t) print("Holding", e, t, nodeType, nodeName) end)
        node:Subscribe("RightTapped", function (e, t) print("RightTapped", e, t, nodeType, nodeName) end)
        node:Subscribe("PreviewGotKeyboardFocus", function (e, t) print("PreviewGotKeyboardFocus", e, t, nodeType, nodeName) end)
        node:Subscribe("PreviewKeyDown", function (e, t) print("PreviewKeyDown", e, t, nodeType, nodeName) end)
        node:Subscribe("PreviewKeyUp", function (e, t) print("PreviewKeyUp", e, t, nodeType, nodeName) end)
        node:Subscribe("PreviewLostKeyboardFocus", function (e, t) print("PreviewLostKeyboardFocus", e, t, nodeType, nodeName) end)
        node:Subscribe("PreviewMouseDown", function (e, t) print("PreviewMouseDown", e, t, nodeType, nodeName) end)
        node:Subscribe("PreviewMouseLeftButtonDown", function (e, t) print("PreviewMouseLeftButtonDown", e, t, nodeType, nodeName) end)
        node:Subscribe("PreviewMouseLeftButtonUp", function (e, t) print("PreviewMouseLeftButtonUp", e, t, nodeType, nodeName) end)
        node:Subscribe("PreviewMouseMove", function (e, t) print("PreviewMouseMove", e, t, nodeType, nodeName) end)
        node:Subscribe("PreviewMouseRightButtonDown", function (e, t) print("PreviewMouseRightButtonDown", e, t, nodeType, nodeName) end)
        node:Subscribe("PreviewMouseRightButtonUp", function (e, t) print("PreviewMouseRightButtonUp", e, t, nodeType, nodeName) end)
        node:Subscribe("PreviewMouseUp", function (e, t) print("PreviewMouseUp", e, t, nodeType, nodeName) end)
        node:Subscribe("PreviewMouseWheel", function (e, t) print("PreviewMouseWheel", e, t, nodeType, nodeName) end)
        node:Subscribe("PreviewTextInput", function (e, t) print("PreviewTextInput", e, t, nodeType, nodeName) end)
        node:Subscribe("QueryCursor", function (e, t) print("QueryCursor", e, t, nodeType, nodeName) end)
        node:Subscribe("TextInput", function (e, t) print("TextInput", e, t, nodeType, nodeName) end)
        node:Subscribe("PreviewQueryContinueDrag", function (e, t) print("PreviewQueryContinueDrag", e, t, nodeType, nodeName) end)
        node:Subscribe("QueryContinueDrag", function (e, t) print("QueryContinueDrag", e, t, nodeType, nodeName) end)
        node:Subscribe("PreviewGiveFeedback", function (e, t) print("PreviewGiveFeedback", e, t, nodeType, nodeName) end)
        node:Subscribe("GiveFeedback", function (e, t) print("GiveFeedback", e, t, nodeType, nodeName) end)
        node:Subscribe("PreviewDragEnter", function (e, t) print("PreviewDragEnter", e, t, nodeType, nodeName) end)
        node:Subscribe("DragEnter", function (e, t) print("DragEnter", e, t, nodeType, nodeName) end)
        node:Subscribe("PreviewDragOver", function (e, t) print("PreviewDragOver", e, t, nodeType, nodeName) end)
        node:Subscribe("DragOver", function (e, t) print("DragOver", e, t, nodeType, nodeName) end)
        node:Subscribe("PreviewDragLeave", function (e, t) print("PreviewDragLeave", e, t, nodeType, nodeName) end)
        node:Subscribe("DragLeave", function (e, t) print("DragLeave", e, t, nodeType, nodeName) end)
        node:Subscribe("PreviewDrop", function (e, t) print("PreviewDrop", e, t, nodeType, nodeName) end)
        node:Subscribe("Drop", function (e, t) print("Drop", e, t, nodeType, nodeName) end)
        node:Subscribe("GotMouseCapture", function (e, t) print("GotMouseCapture", e, t, nodeType, nodeName) end)
    end
end

local function attachListenersToControllerButtons(node, uuid, visited)
    local status, result = pcall(investigateNode, node)
    if not status then
        print("Error:", result)
    end
end

-- thank u focus
function mapHotBarButtons(node, uuid, attachListeners, visited)
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

local function onControllerButtonInput(e)
    -- print("controller button pressed")
    -- _D(e)
    if e.Pressed == true and tostring(e.Button) == "LeftStick" then
        -- local uuid = getDirectlyControlledCharacter()
        -- mapHotBarButtons(Ext.UI.GetRoot(), uuid, attachListenersToControllerButtons)
        Ext.ClientNet.PostMessageToServer("ControllerButtonPressed", tostring(e.Button))
        if tostring(e.Button) == "RightStick" and isInFTB(getDirectlyControlledCharacter()) then
            Ext.ClientNet.PostMessageToServer("ExitFTB", "")
        end
        -- if UseCombatControllerControls then
        --     e:PreventAction()
        -- end
    end
end

local function onNetMessage(data)
    if data.Channel == "Started" then
        checkForHotBar(getDirectlyControlledCharacter())
    elseif data.Channel == "GainedControl" then
        DirectlyControlledCharacter = data.Payload
        checkForHotBar(DirectlyControlledCharacter)
    elseif data.Channel == "UseCombatControllerControls" then
        UseCombatControllerControls = data.Payload == "1"
    elseif data.Channel == "ClearActionQueue" then
        ActionQueue[data.Payload] = nil
    elseif data.Channel == "SpellCastIsCasting" then
        ShouldPreventAction[data.Payload] = true
    end
end

local function onMouseButtonInput(e)
    if e.Pressed then
        if e.Button == 1 then
            if not IsMouseOverHotBar then
                local uuid = getDirectlyControlledCharacter()
                if ShouldPreventAction[uuid] and isInFTB(uuid) then
                    if ActionQueue[uuid] ~= nil and ActionQueue[uuid].spellName ~= nil then
                        ActionQueue[uuid].target = getPositionInfo()
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
    -- Ext.Entity.OnCreateDeferred("HotbarContainer", function (entity, x, y)
    --     print("OnCreateDeferred", entity, x, y)
    -- end)
end

Ext.Events.SessionLoaded:Subscribe(onSessionLoaded)
