---@type Mod
local Mod = Require("Hlib/Mod")

---@type Utils
local Utils = Require("Hlib/Utils")

---@type Log
local Log = Require("Hlib/Log")

---@type Event
local Event = Require("Hlib/Event")

---@class GameState
local M = {}

M.EventSave = "_GameStateSave"
M.EventLoad = "_GameStateLoad"
M.EventLoadSession = "_GameStateLoadSession"
M.EventUnload = "_GameStateUnload"
M.EventUnloadLevel = "_GameStateUnloadLevel"
M.EventUnloadSession = "_GameStateUnloadSession"
M.EventClientMenuLoad = "_GameStateClientMenuLoad"
M.EventClientMenuUnload = "_GameStateClientMenuUnload"

M.InitStateEnum = {
    NotLoaded = 0,
    SessionLoaded = 1,
    Running = 2,
}
M.InitState = 0

local isLoading = true
function M.IsLoading()
    return isLoading
end

Ext.Events.GameStateChanged:Subscribe(function(e)
    if Mod.Dev then
        Log.Debug("GameState", e.FromState, e.ToState)
    end
    isLoading = false

    if e.FromState == "LoadSession" and e.ToState == "LoadLevel" then
        isLoading = true
        Event.Trigger(M.EventLoadSession)
        M.InitState = M.InitStateEnum.SessionLoaded
    elseif (e.FromState == "Sync" or e.FromState == "PrepareRunning") and e.ToState == "Running" then
        Event.Trigger(M.EventLoad)
        M.InitState = M.InitStateEnum.Running
    elseif e.FromState == "Running" and e.ToState == "Save" then
        isLoading = true
        Event.Trigger(M.EventSave)
    elseif e.FromState == "Save" and e.ToState == "Running" then
        Event.Trigger(M.EventLoad)
    elseif (e.FromState == "StartLoading" or e.FromState == "Running") and e.ToState == "Disconnect" then
        isLoading = true
        Event.Trigger(M.EventUnload)
    elseif (e.FromState == "Running" or e.FromState == "Idle") and e.ToState == "UnloadLevel" then
        isLoading = true
        Event.Trigger(M.EventUnload)
    elseif e.FromState == "UnloadSession" and e.ToState == "LoadSession" then
        isLoading = true
        Event.Trigger(M.EventUnloadSession)
    elseif e.FromState == "Disconnect" and e.ToState == "UnloadLevel" then
        isLoading = true
        Event.Trigger(M.EventUnloadSession)
    elseif e.FromState == "StopLoading" and e.ToState == "Menu" then
        Event.Trigger(M.EventClientMenuLoad)
    elseif e.FromState == "Menu" and e.ToState == "StartLoading" then
        isLoading = true
        Event.Trigger(M.EventClientMenuUnload)
    end
end)

Ext.Events.ResetCompleted:Subscribe(function()
    isLoading = false
    Event.Trigger(M.EventLoadSession)
    M.InitState = M.InitStateEnum.SessionLoaded
    Event.Trigger(M.EventLoad)
    M.InitState = M.InitStateEnum.Running
end)

---@param callback fun()
---@param once boolean|nil
---@return EventListener
function M.OnSave(callback, once)
    return Event.On(M.EventSave, callback, once)
end

---@param callback fun()
---@param once boolean|nil
---@return EventListener
function M.OnLoad(callback, once)
    return Event.On(M.EventLoad, callback, once)
end

---@param callback fun()
---@param once boolean|nil
---@return EventListener
function M.OnUnload(callback, once)
    return Event.On(M.EventUnload, callback, once)
end

---@param callback fun()
---@param once boolean|nil
---@return EventListener
-- same time as Ext.Events.SessionLoaded
function M.OnLoadSession(callback, once)
    return Event.On(M.EventLoadSession, callback, once)
end

---@param callback fun()
---@param once boolean|nil
---@return EventListener
function M.OnUnloadLevel(callback, once)
    return Event.On(M.EventUnloadLevel, callback, once)
end

---@param callback fun()
---@param once boolean|nil
---@return EventListener
function M.OnUnloadSession(callback, once)
    return Event.On(M.EventUnloadSession, callback, once)
end

---@param callback fun()
---@param once boolean|nil
---@return EventListener
function M.OnClientMenuLoad(callback, once)
    return Event.On(M.EventClientMenuLoad, callback, once)
end

---@param callback fun()
---@param once boolean|nil
---@return EventListener
function M.OnClientMenuUnload(callback, once)
    return Event.On(M.EventClientMenuUnload, callback, once)
end

return M
