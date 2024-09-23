---@class Mod
local M = {}

M.UUID = ModuleUUID
M.Prefix = ""
M.TableKey = ""
M.Version = { Major = 0, Minor = 0, Revision = 0, Full = "0.0.0" }
M.Debug = true
M.Dev = false
M.EnableRCE = false
M.NetChannel = "Net_" .. M.UUID

if Ext.Mod.IsModLoaded(M.UUID) then
    local modInfo = Ext.Mod.GetMod(M.UUID)["Info"]

    M.TableKey = modInfo.Directory
    M.Prefix = modInfo.Name
    M.Version = {
        Major = modInfo.ModVersion[1],
        Minor = modInfo.ModVersion[2],
        Revision = modInfo.ModVersion[3],
        Build = modInfo.ModVersion[4],
        Full = tonumber(table.concat(modInfo.ModVersion, "")),
    }
end

local function applyTemplate(vars, template)
    for k, v in pairs(template) do
        if type(v) == "table" then
            if vars[k] == nil then
                vars[k] = {}
            end

            applyTemplate(vars[k], v)
        else
            if vars[k] == nil then
                vars[k] = v
            end
        end
    end
end

-------------------------------------------------------------------------------------------------
--                                                                                             --
--                                       PersistentVars                                        --
--                                                                                             --
-------------------------------------------------------------------------------------------------

M.PersistentVarsTemplate = {}

function M.PreparePersistentVars()
    if not PersistentVars then
        PersistentVars = {}
    end

    -- Remove keys we no longer use in the Template
    for k, _ in pairs(PersistentVars) do
        if M.PersistentVarsTemplate[k] == nil then
            PersistentVars[k] = nil
        end
    end

    -- Add new keys to the PersistentVars recursively
    applyTemplate(PersistentVars, M.PersistentVarsTemplate)
end

-------------------------------------------------------------------------------------------------
--                                                                                             --
--                                           ModVars                                           --
--                                                                                             --
-------------------------------------------------------------------------------------------------

M.Vars = {}

---@param tableKey string
---@param template table
---@param syncServer boolean - sync server to clients
---@param syncClient boolean - sync client to server
function M.CreateModVar(tableKey, template, syncServer, syncClient)
    if syncServer and syncClient then
        error("Mod.CreateModVar - Cannot sync to both server and client.")
    end

    Ext.Vars.RegisterModVariable(M.UUID, tableKey, {
        Persistent = true,
        SyncOnWrite = false,
        SyncOnTick = true,
        Server = Ext.IsServer() or syncClient or syncServer,
        Client = Ext.IsClient() or syncClient or syncServer,
        WriteableOnServer = Ext.IsServer() or syncServer,
        WriteableOnClient = Ext.IsClient() or syncClient,
        SyncToClient = syncServer or false,
        SyncToServer = syncClient or false,
    })

    Ext.Events.SessionLoaded:Subscribe(function()
        local vars = Ext.Vars.GetModVariables(M.UUID)

        if Ext.IsServer() and syncServer ~= true then
            M.Vars = vars
            return
        end

        if Ext.IsClient() and syncClient ~= true then
            M.Vars = vars
            return
        end

        vars[tableKey] = vars[tableKey] or {}

        Ext.OnNextTick(function()
            if type(template) == "table" then
                M.Vars[tableKey] = M.Vars[tableKey] or {}
                applyTemplate(M.Vars[tableKey], template)
            else
                M.Vars[tableKey] = M.Vars[tableKey] or template
            end

            if syncServer or syncClient then
                M.Vars[tableKey] = Require("Hlib/Utils").Table.Proxy(M.Vars[tableKey], function(value, key, raw)
                    vars[tableKey] = raw

                    return value
                end)
            end
        end)
    end)
end

function M.SyncModVars()
    for k, v in pairs(M.Vars) do
        M.Vars[k] = v
    end
    Ext.Vars.SyncModVariables(M.UUID)
end

return M
