local ModToggleHotkey = "F9"
local CompanionAIToggleHotkey = "F11"
local FullAutoToggleHotkey = "F6"
if MCM then
    ModToggleHotkey = string.upper(MCM.Get("mod_toggle_hotkey"))
    CompanionAIToggleHotkey = string.upper(MCM.Get("companion_ai_toggle_hotkey"))
    FullAutoToggleHotkey = string.upper(MCM.Get("full_auto_toggle_hotkey"))
end

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

local function onMouseButtonInput(e)
    -- if e.Pressed then
    -- end
end

Ext.Events.KeyInput:Subscribe(onKeyInput)
Ext.Events.ControllerButtonInput:Subscribe(onControllerButtonInput)
-- Ext.Events.MouseButtonInput:Subscribe(onMouseButtonInput)
