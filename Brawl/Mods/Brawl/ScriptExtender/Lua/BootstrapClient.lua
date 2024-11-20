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
local IsUsingController = false

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
        -- node:Subscribe("GotFocus", function (e, t) print("GotFocus", e, t, nodeType, nodeName) end)
        -- node:Subscribe("GotKeyboardFocus", function (e, t) print("GotKeyboardFocus", e, t, nodeType, nodeName) end)
        -- node:Subscribe("GotMouseCapture", function (e, t) print("GotMouseCapture", e, t, nodeType, nodeName) end)
        -- node:Subscribe("KeyDown", function (e, t) print("KeyDown", e, t, nodeType, nodeName) end)
        -- node:Subscribe("KeyUp", function (e, t) print("KeyUp", e, t, nodeType, nodeName) end)
        -- node:Subscribe("LostFocus", function (e, t)
        --     print("LostFocus", e, t, nodeType, nodeName)
        --     _D(e)
        --     _D(e:GetAllProperties())
        -- end)
        -- node:Subscribe("LostKeyboardFocus", function (e, t)
        --     print("LostKeyboardFocus", e, t, nodeType, nodeName)
        --     _D(e)
        --     _D(e:GetAllProperties())
        -- end)
        -- node:Subscribe("LostMouseCapture", function (e, t) print("LostMouseCapture", e, t, nodeType, nodeName) end)
        -- node:Subscribe("MouseDown", function (e, t) print("MouseDown", e, t, nodeType, nodeName) end)
        -- node:Subscribe("MouseEnter", function (e, t) print("MouseEnter", e, t, nodeType, nodeName) end)
        -- node:Subscribe("MouseLeave", function (e, t) print("MouseLeave", e, t, nodeType, nodeName) end)
        node:Subscribe("MouseLeftButtonDown", function (e, t) print("MouseLeftButtonDown", e, t, nodeType, nodeName) end)
        -- node:Subscribe("MouseLeftButtonUp", function (e, t) print("MouseLeftButtonUp", e, t, nodeType, nodeName) end)
        -- node:Subscribe("MouseMove", function (e, t) print("MouseMove", e, t, nodeType, nodeName) end)
        -- node:Subscribe("MouseRightButtonDown", function (e, t) print("MouseRightButtonDown", e, t, nodeType, nodeName) end)
        -- node:Subscribe("MouseRightButtonUp", function (e, t) print("MouseRightButtonUp", e, t, nodeType, nodeName) end)
        -- node:Subscribe("MouseUp", function (e, t) print("MouseUp", e, t, nodeType, nodeName) end)
        -- node:Subscribe("MouseWheel", function (e, t) print("MouseWheel", e, t, nodeType, nodeName) end)
        -- node:Subscribe("TouchDown", function (e, t) print("TouchDown", e, t, nodeType, nodeName) end)
        -- node:Subscribe("TouchMove", function (e, t) print("TouchMove", e, t, nodeType, nodeName) end)
        -- node:Subscribe("TouchUp", function (e, t) print("TouchUp", e, t, nodeType, nodeName) end)
        -- node:Subscribe("TouchEnter", function (e, t) print("TouchEnter", e, t, nodeType, nodeName) end)
        -- node:Subscribe("TouchLeave", function (e, t) print("TouchLeave", e, t, nodeType, nodeName) end)
        -- node:Subscribe("GotTouchCapture", function (e, t) print("GotTouchCapture", e, t, nodeType, nodeName) end)
        -- node:Subscribe("LostTouchCapture", function (e, t) print("LostTouchCapture", e, t, nodeType, nodeName) end)
        -- node:Subscribe("PreviewTouchDown", function (e, t) print("PreviewTouchDown", e, t, nodeType, nodeName) end)
        -- node:Subscribe("PreviewTouchMove", function (e, t) print("PreviewTouchMove", e, t, nodeType, nodeName) end)
        -- node:Subscribe("PreviewTouchUp", function (e, t) print("PreviewTouchUp", e, t, nodeType, nodeName) end)
        -- node:Subscribe("ManipulationStarting", function (e, t) print("ManipulationStarting", e, t, nodeType, nodeName) end)
        -- node:Subscribe("ManipulationStarted", function (e, t) print("ManipulationStarted", e, t, nodeType, nodeName) end)
        -- node:Subscribe("ManipulationDelta", function (e, t) print("ManipulationDelta", e, t, nodeType, nodeName) end)
        -- node:Subscribe("ManipulationInertiaStarting", function (e, t) print("ManipulationInertiaStarting", e, t, nodeType, nodeName) end)
        -- node:Subscribe("ManipulationCompleted", function (e, t) print("ManipulationCompleted", e, t, nodeType, nodeName) end)
        -- node:Subscribe("Tapped", function (e, t) print("Tapped", e, t, nodeType, nodeName) end)
        -- node:Subscribe("DoubleTapped", function (e, t) print("DoubleTapped", e, t, nodeType, nodeName) end)
        -- node:Subscribe("Holding", function (e, t) print("Holding", e, t, nodeType, nodeName) end)
        -- node:Subscribe("RightTapped", function (e, t) print("RightTapped", e, t, nodeType, nodeName) end)
        -- node:Subscribe("PreviewGotKeyboardFocus", function (e, t) print("PreviewGotKeyboardFocus", e, t, nodeType, nodeName) end)
        -- node:Subscribe("PreviewKeyDown", function (e, t) print("PreviewKeyDown", e, t, nodeType, nodeName) end)
        -- node:Subscribe("PreviewKeyUp", function (e, t) print("PreviewKeyUp", e, t, nodeType, nodeName) end)
        -- node:Subscribe("PreviewLostKeyboardFocus", function (e, t) print("PreviewLostKeyboardFocus", e, t, nodeType, nodeName) end)
        -- node:Subscribe("PreviewMouseDown", function (e, t) print("PreviewMouseDown", e, t, nodeType, nodeName) end)
        -- node:Subscribe("PreviewMouseLeftButtonDown", function (e, t) print("PreviewMouseLeftButtonDown", e, t, nodeType, nodeName) end)
        -- node:Subscribe("PreviewMouseLeftButtonUp", function (e, t) print("PreviewMouseLeftButtonUp", e, t, nodeType, nodeName) end)
        -- node:Subscribe("PreviewMouseMove", function (e, t) print("PreviewMouseMove", e, t, nodeType, nodeName) end)
        -- node:Subscribe("PreviewMouseRightButtonDown", function (e, t) print("PreviewMouseRightButtonDown", e, t, nodeType, nodeName) end)
        -- node:Subscribe("PreviewMouseRightButtonUp", function (e, t) print("PreviewMouseRightButtonUp", e, t, nodeType, nodeName) end)
        -- node:Subscribe("PreviewMouseUp", function (e, t) print("PreviewMouseUp", e, t, nodeType, nodeName) end)
        -- node:Subscribe("PreviewMouseWheel", function (e, t) print("PreviewMouseWheel", e, t, nodeType, nodeName) end)
        -- node:Subscribe("PreviewTextInput", function (e, t) print("PreviewTextInput", e, t, nodeType, nodeName) end)
        -- node:Subscribe("QueryCursor", function (e, t) print("QueryCursor", e, t, nodeType, nodeName) end)
        -- node:Subscribe("TextInput", function (e, t) print("TextInput", e, t, nodeType, nodeName) end)
        -- node:Subscribe("PreviewQueryContinueDrag", function (e, t) print("PreviewQueryContinueDrag", e, t, nodeType, nodeName) end)
        -- node:Subscribe("QueryContinueDrag", function (e, t) print("QueryContinueDrag", e, t, nodeType, nodeName) end)
        -- node:Subscribe("PreviewGiveFeedback", function (e, t) print("PreviewGiveFeedback", e, t, nodeType, nodeName) end)
        -- node:Subscribe("GiveFeedback", function (e, t) print("GiveFeedback", e, t, nodeType, nodeName) end)
        -- node:Subscribe("PreviewDragEnter", function (e, t) print("PreviewDragEnter", e, t, nodeType, nodeName) end)
        -- node:Subscribe("DragEnter", function (e, t) print("DragEnter", e, t, nodeType, nodeName) end)
        -- node:Subscribe("PreviewDragOver", function (e, t) print("PreviewDragOver", e, t, nodeType, nodeName) end)
        -- node:Subscribe("DragOver", function (e, t) print("DragOver", e, t, nodeType, nodeName) end)
        -- node:Subscribe("PreviewDragLeave", function (e, t) print("PreviewDragLeave", e, t, nodeType, nodeName) end)
        -- node:Subscribe("DragLeave", function (e, t) print("DragLeave", e, t, nodeType, nodeName) end)
        -- node:Subscribe("PreviewDrop", function (e, t) print("PreviewDrop", e, t, nodeType, nodeName) end)
        -- node:Subscribe("Drop", function (e, t) print("Drop", e, t, nodeType, nodeName) end)
        node:Subscribe("GotMouseCapture", function (e, t) print("GotMouseCapture", e, t, nodeType, nodeName) end)
    end
end

local function investigateNodeSafe(node, uuid, visited)
    local status, result = pcall(investigateNode, node)
    if not status then
        print("Error:", result)
    end
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
    -- investigateNodeSafe(node, getDirectlyControlledCharacter())
    print(safeGetProperty(node, "Name"))
    if safeGetProperty(node, "Name") == targetName then
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

local function getEnterFTBButton()
    local button = findNodeByName(getHotBar(), "EnterFTBButton")
    return button
end

local function getExitFTBButton()
    return findNodeByName(getHotBar(), "ExitFTBButton")
end

-- thank u aahz
function getDirectlyControlledCharacter()
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
    if e.Repeat == false then
        if e.Key == ModToggleHotkey and e.Event == "KeyDown" then
            Ext.ClientNet.PostMessageToServer("ModToggle", tostring(e.Key))
        elseif e.Key == CompanionAIToggleHotkey and e.Event == "KeyDown" then
            Ext.ClientNet.PostMessageToServer("CompanionAIToggle", tostring(e.Key))
        elseif e.Key == FullAutoToggleHotkey and e.Event == "KeyDown" then
            Ext.ClientNet.PostMessageToServer("FullAutoToggle", tostring(e.Key))
        -- nb: what about rebindings? is there a way to look these up in SE?
        elseif e.Key == "LSHIFT" or e.Key == "RSHIFT" then
            IsShiftPressed = e.Event == "KeyDown"
        elseif e.Key == "SPACE" then
            IsSpacePressed = e.Event == "KeyDown"
        end
        if IsShiftPressed and IsSpacePressed then
            postToggleFTB()
        end
    end
end

local function startFTBButtonListeners()
    if not IsUsingController then
        if isInFTB(getDirectlyControlledCharacter()) then
            -- local exitFTBButton = getExitFTBButton()
            -- print("exit ftb button", exitFTBButton)
            -- exitFTBButton:Subscribe("MouseEnter", function (node, _)
            --     print("MouseEnter", node)
            --     -- Ext.ClientNet.PostMessageToServer("ExitFTB", "")
            -- end)
        else
            -- investigateNodeSafe(getHotBar(), getDirectlyControlledCharacter())
            enterFTBButton:Subscribe("MouseEnter", function (node, _)
                print("MouseEnter", node)
                -- Ext.ClientNet.PostMessageToServer("EnterFTB", "")
            end)
            -- Ext.Timer.WaitFor(100, function ()
            --     local enterFTBButton = getEnterFTBButton()
            --     print("enter ftb button", enterFTBButton)
            --     _D(enterFTBButton)
            --     _D(enterFTBButton:GetAllProperties())
            --     local node = enterFTBButton:VisualChild(1)
            --     _D(node)
            --     _D(node:GetAllProperties())
            --     Ext.Timer.WaitFor(10000, function ()
            --         local enterFTBButton2 = getEnterFTBButton()
            --         print("enter ftb button", enterFTBButton2)
            --         _D(enterFTBButton2)
            --         _D(enterFTBButton2:GetAllProperties())
            --         local node2 = enterFTBButton2:VisualChild(1)
            --         _D(node2)
            --         _D(node2:GetAllProperties())    
            --     end)
            -- end)
        end
    end
end

local function onNetMessage(data)
    if data.Channel == "GainedControl" then
        DirectlyControlledCharacter = data.Payload
        startFTBButtonListeners()
    elseif data.Channel == "FTBToggled" then
        print("FTB toggled", data.Payload)
        startFTBButtonListeners()
    end
end

local function onControllerButtonInput(e)
    if e.Pressed == true then
        if not IsUsingController then
            IsUsingController = true
            Ext.ClientNet.PostMessageToServer("IsUsingController", "1")
        end
        Ext.ClientNet.PostMessageToServer("ControllerButtonPressed", tostring(e.Button))
        local button = tostring(e.Button)
        if button == "A" then
            postClickPosition()
        elseif button == "RightStick" then
            postToggleFTB()
        end
    end
end

local function onMouseButtonInput(e)
    if e.Pressed then
        if IsUsingController then
            IsUsingController = false
            Ext.ClientNet.PostMessageToServer("IsUsingController", "0")
            startFTBButtonListeners()
        end
        if e.Button == 1 then
            postClickPosition()
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
