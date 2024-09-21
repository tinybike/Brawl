---@type Mod
local Mod = Require("Hlib/Mod")

---@type Utils
local Utils = Require("Hlib/Utils")

---@type Log
local Log = Require("Hlib/Log")

---@type IO
local IO = Require("Hlib/IO")

---@type Event
local Event = Require("Hlib/Event")

---@type Event
local Async = Require("Hlib/Async")

---@type Net
local Net = Require("Hlib/Net")

---@type GameState
local GameState = Require("Hlib/GameState")

---@class Localization
local M = {}

M.Translations = {}
M.UseLoca = true
M.FilePath = "Localization/" .. Mod.TableKey

local function build(text, version, handle)
    local tbl = {
        Version = version,
        Text = text,
        Handle = nil,
        Stack = {},
    }

    if M.UseLoca then
        tbl.Handle = handle or M.GenerateHandle(text, version)
        local locaText = M.Get(tbl.Handle)

        if locaText ~= "" then
            Log.Info("Translation found: ", tbl.Handle, tbl.Text, locaText)

            tbl.Text = locaText
        end
    end

    return tbl
end

local saveFile = Async.Debounce(1000, function()
    IO.SaveJson(
        M.FilePath .. ".json",
        Utils.Table.Map(M.Translations, function(v, k)
            return {
                Text = v.Text,
                Version = v.Version,
                Handle = v.Handle,
                Stack = v.Stack,
            },
                k
        end)
    )
end)

local function extendStack(key, stack)
    local file = stack:match("([^:]+):%d+")

    local t = M.Translations[key]

    if type(t.Stack) ~= "table" then
        t.Stack = {}
    end

    if file == "" then
        return
    end

    for _, v in ipairs(t.Stack) do
        if v == file then
            return
        end
    end

    table.insert(t.Stack, file)

    Event.Trigger("_TranslationChanged")
end

Net.On("_TranslationRequest", function(event)
    Utils.Table.Merge(M.Translations, event.Payload)
end)

Event.On("_TranslationChanged", function()
    Net.Send("_TranslationRequest", M.Translations)
    saveFile()
end)

GameState.OnLoadSession(function()
    local cached = IO.LoadJson(M.FilePath .. ".json") or {}
    for k, v in pairs(cached) do
        M.Translations[k] = build(v.Text, v.Version, v.Handle)
        if type(v.Stack) ~= "table" then
            v.Stack = {}
        end

        M.Translations[k].Stack = v.Stack
    end
end)

function M.Translate(text, version)
    version = version or 1

    local key = text .. ";" .. version

    if M.Translations[key] == nil then
        M.Translations[key] = build(text, version)

        Event.Trigger("_TranslationChanged")

        Log.Debug("Localization/Translate", M.Translations[key].Handle, M.Translations[key].Text)
    end

    if Mod.Dev then
        -- local stack = Utils.String.Trim(Utils.Table.Find(Utils.String.Split(debug.traceback(), "\n"), function(line)
        --     return not line:match("stack traceback:")
        --         and not line:match("Hlib/Localization.lua")
        --         and not line:match("(...tail calls...)")
        -- end) or "")
        extendStack(key, Utils.CallStack({ "Hlib/Localization.lua" }))
    end

    return M.Translations[key].Text
end

---@param handle string
---@vararg any
---@return string
function M.Get(handle, ...)
    local str = Ext.Loca.GetTranslatedString(handle):gsub("<LSTag .->(.-)</LSTag>", "%1"):gsub("<br>", "\n")
    for i, v in pairs({ ... }) do
        str = str:gsub("%[" .. i .. "%]", v)
    end

    return str
end

---@param strict boolean
---@param version number|nil
---@return string
function M.GenerateHandle(str, version)
    return "h" .. Utils.UUID.FromString(str, version):gsub("-", "g")
end

---@param text string text "...;2" for version 2
---@vararg any passed to string.format
---@return string
function M.Localize(text, ...)
    local version = text:match(";%d+$")
    if version then
        text = text:gsub(";%d+$", "")
    end

    return string.format(M.Translate(text, version), ...)
end

function M.BuildLocaFile()
    local xmlWrap = [[
<?xml version="1.0" encoding="utf-8"?>
<contentList>
%s
</contentList>
]]
    local xmlEntry = [[%s
    <content contentuid="%s" version="%d">%s</content>
]]

    local ordered = {}
    for k, v in pairs(M.Translations) do
        table.insert(ordered, k)
    end
    table.sort(ordered)

    local entries = {}
    for _, key in ipairs(ordered) do
        local translation = M.Translations[key]

        local handle = translation.Handle:gsub(";%d+$", "") -- handle should not have a version

        local stack = {}
        for i, file in ipairs(translation.Stack) do
            table.insert(stack, string.format("    <!-- %s -->", file))
        end

        table.insert(entries, string.format(xmlEntry, table.concat(stack, "\n"), handle, 1, translation.Text))
    end

    local loca = string.format(xmlWrap, table.concat(entries, "\n"))

    IO.Save(M.FilePath .. ".xml", loca)
end

return M
