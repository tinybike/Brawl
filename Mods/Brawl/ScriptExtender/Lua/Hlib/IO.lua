---@type Mod
local Mod = Require("Hlib/Mod")

---@type Utils
local Utils = Require("Hlib/Utils")

---@type Log
local Log = Require("Hlib/Log")

---@class IO
local M = {}

function M.Load(file)
    file = Mod.Prefix .. "/" .. file
    return Ext.IO.LoadFile(file)
end

function M.Save(file, data)
    file = Mod.Prefix .. "/" .. file
    Ext.IO.SaveFile(file, tostring(data))
end

function M.Exists(file)
    file = Mod.Prefix .. "/" .. file
    return Ext.IO.LoadFile(file) ~= nil
end

function M.LoadJson(file)
    if file:sub(-5) ~= ".json" then
        file = file .. ".json"
    end

    local data = M.Load(file)
    if not data then
        return nil
    end

    local ok, res = pcall(Ext.Json.Parse, data)
    if not ok then
        Log.Error(debug.traceback(res))
        res = nil
    end

    return res
end

function M.SaveJson(file, data)
    if file:sub(-5) ~= ".json" then
        file = file .. ".json"
    end

    M.Save(
        file,
        Ext.Json.Stringify(
            Utils.String.Contains(type(data), { "userdata", "table" }) and Utils.Table.Clean(data, 0) or data
        )
    )
end

return M
