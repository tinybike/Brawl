---@type Mod
local Mod = Require("Hlib/Mod")

---@type Event
local Event = Require("Hlib/Event")

---@type GameState
local GameState = Require("Hlib/GameState")

---@type Log
local Log = Require("Hlib/Log")

---@class ModEvent
local M = {}

---@param event string
---@vararg any
function M.Trigger(event, ...)
    L.Debug("ModEvent/Trigger", Mod.TableKey, event)
    Ext.ModEvents[Mod.TableKey][event]:Throw(...)
end

---@param event string
function M.Register(event)
    L.Debug("ModEvent/Register", Mod.TableKey, event)
    Ext.RegisterModEvent(Mod.TableKey, event)

    Event.On(event, function(...)
        M.Trigger(event, ...)
    end)
end

---@param mod string
---@param event string
---@return string
function M.EventName(mod, event)
    return "ModEvent_" .. mod .. "_" .. event
end

---@param mod string
---@param events string|string[]
function M.Subscribe(mod, events)
    if type(events) == "string" then
        events = { events }
    end

    assert(type(events) == "table", "ModEvent.Subscribe(..., events) - table expected, got " .. type(events))

    for _, event in ipairs(events) do
        Ext.ModEvents[mod][event]:Subscribe(function(...)
            Event.Trigger(M.EventName(mod, event), ...)
        end)
    end
end

return M
