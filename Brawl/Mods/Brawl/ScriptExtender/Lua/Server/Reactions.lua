local debugPrint = Utils.debugPrint

-- Snapshot/restore of an entity's InterruptPreferences (per-reaction "enabled" + "ask" flags as bitfields).
-- Persistent storage shape (see CharacterLoadouts mod var registered in State.lua):
--   CharacterLoadouts[characterUuid].Reactions = { {name="Loadout 1", prefs={[interruptUuid]=bitfield, ...}}, ... }
-- Summon override mod var: SummonReactionMode = "manual" | "all_on" | "all_off"

local function getModVars()
    return Ext.Vars.GetModVariables(ModuleUUID)
end

local function getCharacterLoadouts()
    local modVars = getModVars()
    return modVars.CharacterLoadouts or {}
end

local function setCharacterLoadouts(loadouts)
    -- Reassign to dirty the mod var (writes to subproperties don't trigger sync/persist).
    getModVars().CharacterLoadouts = loadouts
end

-- Single global summon-reaction mode.  Host-only setting that applies to all summons regardless of owner.  Per-user/per-character variants
-- have stability problems (session-scoped userIds, character trading between sessions), so v1 keeps this simple.
local function getSummonReactionMode()
    local val = getModVars().SummonReactionMode
    if type(val) == "string" then return val end
    return "manual"
end

local function setSummonReactionMode(mode)
    getModVars().SummonReactionMode = mode
end

local function snapshotReactions(uuid)
    local entity = Ext.Entity.Get(uuid)
    if not entity or not entity.InterruptPreferences or not entity.InterruptPreferences.Preferences then
        return nil
    end
    local snapshot = {}
    for interrupt, flag in pairs(entity.InterruptPreferences.Preferences) do
        snapshot[interrupt] = flag
    end
    return snapshot
end

local function applyReactions(uuid, prefs)
    local entity = Ext.Entity.Get(uuid)
    if not entity or not entity.InterruptPreferences or not entity.InterruptPreferences.Preferences then
        return false
    end
    for interrupt, flag in pairs(prefs) do
        if entity.InterruptPreferences.Preferences[interrupt] ~= nil then
            entity.InterruptPreferences.Preferences[interrupt] = flag
        end
    end
    entity:Replicate("InterruptPreferences")
    return true
end

local function applyAllReactionsTo(uuid, isEnabled, isAsk)
    local entity = Ext.Entity.Get(uuid)
    if not entity or not entity.InterruptPreferences or not entity.InterruptPreferences.Preferences then
        return false
    end
    local flag = 0
    if isAsk then flag = flag | 1 end
    if isEnabled then flag = flag | 2 end
    for interrupt, _ in pairs(entity.InterruptPreferences.Preferences) do
        entity.InterruptPreferences.Preferences[interrupt] = flag
    end
    entity:Replicate("InterruptPreferences")
    return true
end

local function ensureReactionsTable(loadouts, characterUuid)
    if not loadouts[characterUuid] then loadouts[characterUuid] = {} end
    if not loadouts[characterUuid].Reactions then loadouts[characterUuid].Reactions = {} end
    return loadouts[characterUuid].Reactions
end

local function getCurrentModeTag()
    return State.Settings.TurnBasedSwarmMode and "Swarm" or "Real-Time"
end

local function saveLoadout(characterUuid)
    local snapshot = snapshotReactions(characterUuid)
    if not snapshot then return false end
    local loadouts = getCharacterLoadouts()
    local reactions = ensureReactionsTable(loadouts, characterUuid)
    table.insert(reactions, {
        name = "Loadout " .. tostring(#reactions + 1),
        mode = getCurrentModeTag(),
        prefs = snapshot,
    })
    setCharacterLoadouts(loadouts)
    return true
end

local function overwriteLoadout(characterUuid, index)
    local snapshot = snapshotReactions(characterUuid)
    if not snapshot then return false end
    local loadouts = getCharacterLoadouts()
    local reactions = loadouts[characterUuid] and loadouts[characterUuid].Reactions
    if not reactions or not reactions[index] then return false end
    reactions[index].prefs = snapshot
    reactions[index].mode = getCurrentModeTag()
    setCharacterLoadouts(loadouts)
    return true
end

local function loadLoadout(characterUuid, index)
    local loadouts = getCharacterLoadouts()
    local reactions = loadouts[characterUuid] and loadouts[characterUuid].Reactions
    if not reactions or not reactions[index] or not reactions[index].prefs then return false end
    return applyReactions(characterUuid, reactions[index].prefs)
end

local function deleteLoadout(characterUuid, index)
    local loadouts = getCharacterLoadouts()
    local reactions = loadouts[characterUuid] and loadouts[characterUuid].Reactions
    if not reactions or not reactions[index] then return false end
    table.remove(reactions, index)
    -- Renumber remaining default-named loadouts so the displayed numbering stays contiguous.
    for i, l in ipairs(reactions) do
        if l.name and l.name:match("^Loadout %d+$") then
            l.name = "Loadout " .. tostring(i)
        end
    end
    setCharacterLoadouts(loadouts)
    return true
end

local function getLoadoutsForCharacter(characterUuid)
    local loadouts = getCharacterLoadouts()
    local entry = loadouts[characterUuid]
    if not entry or not entry.Reactions then return {} end
    return entry.Reactions
end

-- Client-facing variant: strips the prefs blobs (the client only renders name + mode).
local function getClientLoadoutsForCharacter(characterUuid)
    local out = {}
    for i, l in ipairs(getLoadoutsForCharacter(characterUuid)) do
        out[i] = {name = l.name, mode = l.mode}
    end
    return out
end

local function applySummonOverrideTo(uuid)
    if not uuid or M.Osi.IsSummon(uuid) ~= 1 then return end
    local mode = getSummonReactionMode()
    if mode == "all_on" then
        applyAllReactionsTo(uuid, true, false)
    elseif mode == "all_off" then
        applyAllReactionsTo(uuid, false, false)
    end
end

local function applySummonOverrideToAll()
    if getSummonReactionMode() == "manual" then return end
    if not State.Session.Players then return end
    for uuid, _ in pairs(State.Session.Players) do
        if M.Osi.IsSummon(uuid) == 1 then
            applySummonOverrideTo(uuid)
        end
    end
end

return {
    snapshotReactions = snapshotReactions,
    applyReactions = applyReactions,
    saveLoadout = saveLoadout,
    overwriteLoadout = overwriteLoadout,
    loadLoadout = loadLoadout,
    deleteLoadout = deleteLoadout,
    getLoadoutsForCharacter = getLoadoutsForCharacter,
    getClientLoadoutsForCharacter = getClientLoadoutsForCharacter,
    getSummonReactionMode = getSummonReactionMode,
    setSummonReactionMode = setSummonReactionMode,
    applySummonOverrideTo = applySummonOverrideTo,
    applySummonOverrideToAll = applySummonOverrideToAll,
}
