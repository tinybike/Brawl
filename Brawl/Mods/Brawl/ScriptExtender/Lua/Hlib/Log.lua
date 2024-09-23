---@type Mod
local Mod = Require("Hlib/Mod")

---@class Log
local M = {}

function M.RainbowText(text, offset)
    function hsvToRgb(h, s, v)
        local r, g, b
        local i = math.floor(h * 6)
        local f = h * 6 - i
        local p = v * (1 - s)
        local q = v * (1 - f * s)
        local t = v * (1 - (1 - f) * s)
        i = i % 6
        if i == 0 then
            r, g, b = v, t, p
        elseif i == 1 then
            r, g, b = q, v, p
        elseif i == 2 then
            r, g, b = p, v, t
        elseif i == 3 then
            r, g, b = p, q, v
        elseif i == 4 then
            r, g, b = t, p, v
        elseif i == 5 then
            r, g, b = v, p, q
        end

        return math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)
    end

    if offset == nil then
        offset = 0
    end
    local length = #text
    local rainbowText = {}
    for i = 1, length do
        local hue = (i + offset - 1) / length
        table.insert(rainbowText, M.ColorText(text:sub(i, i), { hsvToRgb(hue, 1, 1) }))
    end

    return table.concat(rainbowText)
end

function M.ColorText(text, color)
    if type(color) == "table" then
        local r, g, b = color[1], color[2], color[3]
        return string.format("\x1b[38;2;%d;%d;%dm%s\x1b[0m", r, g, b, text)
    end

    return string.format("\x1b[%dm%s\x1b[0m", color or 37, text)
end

local lastTime = 0
local function logTime()
    if not Mod.Debug then
        return ""
    end

    local log = "[" .. Ext.Utils.MonotonicTime() - lastTime .. "]"
    lastTime = Ext.Utils.MonotonicTime()
    return log
end

local rainbowOffset = 0
local function logPrefix()
    rainbowOffset = (rainbowOffset + 1) % 360
    local prefix = M.RainbowText(Mod.Prefix, rainbowOffset) .. " " .. (Ext.IsClient() and "[Client]" or "[Server]")
    return prefix
end

function M.Info(...)
    Ext.Utils.Print(logPrefix() .. M.ColorText("[Info]") .. logTime(), ...)
end

function M.Warn(...)
    Ext.Utils.PrintWarning(logPrefix() .. M.ColorText("[Warning]", 33) .. logTime(), ...)
end

function M.Debug(...)
    if Mod.Debug then
        Ext.Utils.Print(logPrefix() .. M.ColorText("[Debug]", 36) .. logTime(), ...)
    end
end

function M.Dump(...)
    if not Mod.Debug then
        return
    end

    for i, v in pairs({ ... }) do
        M.Debug(i .. ":", type(v) == "string" and v or Ext.DumpExport(v))
    end
end

function M.Error(...)
    Ext.Utils.PrintError(logPrefix() .. M.ColorText("[Error]", 31) .. logTime(), ...)
end

return M
