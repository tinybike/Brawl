local ModToggleHotkey = "F9"
local CompanionAIToggleHotkey = "F11"
if MCM then
    ModToggleHotkey = string.upper(MCM.Get("mod_toggle_hotkey"))
    CompanionAIToggleHotkey = string.upper(MCM.Get("companion_ai_toggle_hotkey"))
end
local IsShiftPressed = false
local IsSpacePressed = false
local IsUsingController = false
local ExitFTBButtonSubscription = nil
local FTBItemSubscription = nil

local function safeGetProperty(obj, propName)
    local success, result = pcall(function() return obj[propName] end)
    if success then
        return result
    else
        return nil
    end
end

local function exploreTree(node, visited)
    if not visited then
        visited = {}
    end
    if visited[node] then
        return
    end
    visited[node] = true
    local properties = node:GetAllProperties()
    local name = properties and properties.Name or "nil"
    print("type=" .. tostring(node.Type) .. ", name=" .. tostring(name))
    local function safeGetProperty(obj, propName)
        local success, result = pcall(function() return obj[propName] end)
        if success then
            return result
        else
            return nil
        end
    end
    local childrenCount = safeGetProperty(node, "ChildrenCount") or 0
    for i = 1, childrenCount do
        local childNode = node:Child(i)
        if childNode then
            exploreTree(childNode, visited)
        end
    end
    local visualChildrenCount = safeGetProperty(node, "VisualChildrenCount") or 0
    for i = 1, visualChildrenCount do
        local visualChildNode = node:VisualChild(i)
        if visualChildNode then
            exploreTree(visualChildNode, visited)
        end
    end
end

local function findNodesByNameSubstring(node, targetSubstring, foundNodes, visited)
    visited = visited or {}
    foundNodes = foundNodes or {}
    if visited[node] then
        return
    end
    visited[node] = true
    local nodeName = node:GetProperty("Name")
    if nodeName and string.find(nodeName, targetSubstring) then
        print("found matching node", nodeName, node)
        table.insert(foundNodes, node)
    end
    local childrenCount = safeGetProperty(node, "ChildrenCount") or 0
    for i = 1, childrenCount do
        local childNode = node:Child(i)
        if childNode then
            findNodesByNameSubstring(childNode, targetSubstring, foundNodes, visited)
        end
    end
    local visualChildrenCount = safeGetProperty(node, "VisualChildrenCount") or 0
    for i = 1, visualChildrenCount do
        local visualChildNode = node:VisualChild(i)
        if visualChildNode then
            findNodesByNameSubstring(visualChildNode, targetSubstring, foundNodes, visited)
        end
    end
    return foundNodes
end

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

-- local function onControllerAxisInput(e)
--     if e.Axis == "TriggerRight" then
--         Ext.Timer.WaitFor(2000, function ()
--             if FTBItemSubscription == nil then
--                 FTBItem = getFTBItem()
--                 if FTBItem then
--                     j=1
--                     k=3
--                     FTBItem:Child(j):Child(k):Subscribe("GotFocus", function (e, t) print("GotFocus", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("GotKeyboardFocus", function (e, t) print("GotKeyboardFocus", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("GotMouseCapture", function (e, t) print("GotMouseCapture", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("KeyDown", function (e, t) print("KeyDown", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("KeyUp", function (e, t) print("KeyUp", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("LostFocus", function (e, t) print("LostFocus", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("LostKeyboardFocus", function (e, t) print("LostKeyboardFocus", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("LostMouseCapture", function (e, t) print("LostMouseCapture", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("MouseDown", function (e, t) print("MouseDown", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("MouseEnter", function (e, t) print("MouseEnter", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("MouseLeave", function (e, t) print("MouseLeave", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("MouseLeftButtonDown", function (e, t) print("MouseLeftButtonDown", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("MouseLeftButtonUp", function (e, t) print("MouseLeftButtonUp", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("MouseMove", function (e, t) print("MouseMove", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("MouseRightButtonDown", function (e, t) print("MouseRightButtonDown", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("MouseRightButtonUp", function (e, t) print("MouseRightButtonUp", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("MouseUp", function (e, t) print("MouseUp", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("MouseWheel", function (e, t) print("MouseWheel", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("TouchDown", function (e, t) print("TouchDown", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("TouchMove", function (e, t) print("TouchMove", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("TouchUp", function (e, t) print("TouchUp", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("TouchEnter", function (e, t) print("TouchEnter", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("TouchLeave", function (e, t) print("TouchLeave", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("GotTouchCapture", function (e, t) print("GotTouchCapture", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("LostTouchCapture", function (e, t) print("LostTouchCapture", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("PreviewTouchDown", function (e, t) print("PreviewTouchDown", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("PreviewTouchMove", function (e, t) print("PreviewTouchMove", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("PreviewTouchUp", function (e, t) print("PreviewTouchUp", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("ManipulationStarting", function (e, t) print("ManipulationStarting", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("ManipulationStarted", function (e, t) print("ManipulationStarted", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("ManipulationDelta", function (e, t) print("ManipulationDelta", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("ManipulationInertiaStarting", function (e, t) print("ManipulationInertiaStarting", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("ManipulationCompleted", function (e, t) print("ManipulationCompleted", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("Tapped", function (e, t) print("Tapped", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("DoubleTapped", function (e, t) print("DoubleTapped", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("Holding", function (e, t) print("Holding", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("RightTapped", function (e, t) print("RightTapped", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("PreviewGotKeyboardFocus", function (e, t) print("PreviewGotKeyboardFocus", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("PreviewKeyDown", function (e, t) print("PreviewKeyDown", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("PreviewKeyUp", function (e, t) print("PreviewKeyUp", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("PreviewLostKeyboardFocus", function (e, t) print("PreviewLostKeyboardFocus", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("PreviewMouseDown", function (e, t) print("PreviewMouseDown", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("PreviewMouseLeftButtonDown", function (e, t) print("PreviewMouseLeftButtonDown", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("PreviewMouseLeftButtonUp", function (e, t) print("PreviewMouseLeftButtonUp", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("PreviewMouseMove", function (e, t) print("PreviewMouseMove", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("PreviewMouseRightButtonDown", function (e, t) print("PreviewMouseRightButtonDown", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("PreviewMouseRightButtonUp", function (e, t) print("PreviewMouseRightButtonUp", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("PreviewMouseUp", function (e, t) print("PreviewMouseUp", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("PreviewMouseWheel", function (e, t) print("PreviewMouseWheel", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("PreviewTextInput", function (e, t) print("PreviewTextInput", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("QueryCursor", function (e, t) print("QueryCursor", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("TextInput", function (e, t) print("TextInput", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("PreviewQueryContinueDrag", function (e, t) print("PreviewQueryContinueDrag", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("QueryContinueDrag", function (e, t) print("QueryContinueDrag", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("PreviewGiveFeedback", function (e, t) print("PreviewGiveFeedback", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("GiveFeedback", function (e, t) print("GiveFeedback", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("PreviewDragEnter", function (e, t) print("PreviewDragEnter", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("DragEnter", function (e, t) print("DragEnter", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("PreviewDragOver", function (e, t) print("PreviewDragOver", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("DragOver", function (e, t) print("DragOver", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("PreviewDragLeave", function (e, t) print("PreviewDragLeave", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("DragLeave", function (e, t) print("DragLeave", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("PreviewDrop", function (e, t) print("PreviewDrop", e, t) end)
--                     FTBItem:Child(j):Child(k):Subscribe("Drop", function (e, t) print("Drop", e, t) end)
--                     -- FTBItemSubscription = getFTBItem():Subscribe("GotMouseCapture", function ()
--                     --     Ext.ClientNet.PostMessageToServer("Clicked", "FTBItem")
--                     -- end)
--                     -- _D(FTBItem)
--                     print(FTBItem.ChildrenCount)
--                     print(FTBItem.VisualChildrenCount)
--                     -- exploreTree(FTBItem)
--                 end
--             end
--         end)
--     end
-- end

local function onControllerButtonInput(_)
    -- exploreTree(Ext.UI.GetRoot():Child(1):Child(1))
    -- Ext.Timer.WaitFor(3000, function ()
        -- findNodesByNameSubstring(Ext.UI.GetRoot(), "FTB")
        -- findNodesByNameSubstring(Ext.UI.GetRoot():Child(1):Child(1), "FTB")
        if not IsUsingController then
            IsUsingController = true
            Ext.ClientNet.PostMessageToServer("IsUsingController", "1")
        end
    -- end)
end

windUp = nil

local function onMouseButtonInput(_)
    -- exploreTree(Ext.UI.GetRoot():Child(1):Child(1):Child(3))
    if IsUsingController then
        IsUsingController = false
        Ext.ClientNet.PostMessageToServer("IsUsingController", "0")
    end
    if ExitFTBButtonSubscription == nil then
        Ext.Events.NetMessage:Subscribe(function (data)
            -- print("Got message in client")
            -- _D(data)
            if data.Channel == "IsWindingUp" then
                windUp = data.Payload
                -- local entity = Ext.Entity.Get(windUp)
                -- entity.TurnBased.IsInCombat_M = true
            end
        end)
        ExitFTBButtonSubscription = getExitFTBButton():Subscribe("GotMouseCapture", function ()
            print("Clicked ExitFTBButton in client")
            Ext.ClientNet.PostMessageToServer("Clicked", "ExitFTBButton")
        end)
    end
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
    if IsShiftPressed and IsSpacePressed then
        Ext.ClientNet.PostMessageToServer("Clicked", "ExitFTBButton")
    end    
end

Ext.Events.KeyInput:Subscribe(onKeyInput)
Ext.Events.MouseButtonInput:Subscribe(onMouseButtonInput)
Ext.Events.ControllerButtonInput:Subscribe(onControllerButtonInput)
-- ControllerAxisInputSubscription = Ext.Events.ControllerAxisInput:Subscribe(onControllerAxisInput)
