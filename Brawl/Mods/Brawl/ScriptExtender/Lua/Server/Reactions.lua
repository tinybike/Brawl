local debugPrint = Utils.debugPrint

-- Persistent storage shape (CharacterLoadouts mod var):
--   CharacterLoadouts[uuid] = { {name, mode, reactions=..., preparedSpells=...}, ... }
-- Each loadout slot bundles multiple typed payloads.  Future types (hotbar, equipment, ...) get added as additional fields on the slot.
-- Old shape was {Reactions = [{name, mode, prefs}]} — migrated transparently on read.

local function getModVars()
    return Ext.Vars.GetModVariables(ModuleUUID)
end

local function migrateOldShape(uuidEntry)
    if type(uuidEntry) ~= "table" then return {} end
    if uuidEntry.Reactions and type(uuidEntry.Reactions) == "table" then
        local migrated = {}
        for i, oldLoadout in ipairs(uuidEntry.Reactions) do
            migrated[i] = {name = oldLoadout.name, mode = oldLoadout.mode, reactions = oldLoadout.prefs}
        end
        return migrated
    end
    return uuidEntry
end

local function getCharacterLoadouts()
    local modVars = getModVars()
    local raw = modVars.CharacterLoadouts or {}
    local migrated = false
    for uuid, entry in pairs(raw) do
        if entry.Reactions then
            raw[uuid] = migrateOldShape(entry)
            migrated = true
        end
    end
    if migrated then modVars.CharacterLoadouts = raw end
    return raw
end

local function setCharacterLoadouts(loadouts)
    -- Reassign to dirty the mod var (writes to subproperties don't trigger sync/persist).
    getModVars().CharacterLoadouts = loadouts
end

-- Single global summon-reaction mode.  Host-only setting that applies to all summons regardless of owner.
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

-- Prepared spells: only meaningful for prepared casters (wizard/cleric/druid/paladin)
local function snapshotPreparedSpells(uuid)
    local entity = Ext.Entity.Get(uuid)
    if not entity or not entity.SpellBookPrepares or not entity.SpellBookPrepares.PreparedSpells then
        return nil
    end
    local snapshot = {}
    for i, spellMeta in ipairs(entity.SpellBookPrepares.PreparedSpells) do
        snapshot[i] = {
            OriginatorPrototype = spellMeta.OriginatorPrototype,
            ProgressionSource = spellMeta.ProgressionSource,
            Source = spellMeta.Source,
            SourceType = spellMeta.SourceType,
        }
    end
    return snapshot
end

local function applyPreparedSpells(uuid, snapshot)
    if not snapshot then return false end
    local entity = Ext.Entity.Get(uuid)
    if not entity or not entity.SpellBookPrepares then return false end
    entity.SpellBookPrepares.PreparedSpells = snapshot
    entity:Replicate("SpellBookPrepares")
    return true
end

-- Hotbar snapshot/apply
local function snapshotHotbar(uuid)
    local entity = Ext.Entity.Get(uuid)
    if not entity or not entity.HotbarContainer or not entity.HotbarContainer.Containers then
        return nil
    end
    local snapshot = {ActiveContainer = entity.HotbarContainer.ActiveContainer, Containers = {}}
    for containerName, bars in pairs(entity.HotbarContainer.Containers) do
        local snapBars = {}
        for barIdx, bar in ipairs(bars) do
            local snapElements = {}
            if bar.Elements then
                for slotIdx, slot in ipairs(bar.Elements) do
                    local snapSlot = {Slot = slot.Slot, IsNew = slot.IsNew, Passive = slot.Passive}
                    if slot.SpellId and slot.SpellId.Prototype and slot.SpellId.Prototype ~= "" then
                        snapSlot.SpellId = {
                            Prototype = slot.SpellId.Prototype,
                            OriginatorPrototype = slot.SpellId.OriginatorPrototype,
                            ProgressionSource = slot.SpellId.ProgressionSource,
                            Source = slot.SpellId.Source,
                            SourceType = slot.SpellId.SourceType,
                        }
                    end
                    if slot.Item then
                        local itemUuid = slot.Item.Uuid and slot.Item.Uuid.EntityUuid
                        if itemUuid then snapSlot.ItemUuid = itemUuid end
                    end
                    snapElements[slotIdx] = snapSlot
                end
            end
            snapBars[barIdx] = {Index = bar.Index, Width = bar.Width, Height = bar.Height, Elements = snapElements}
        end
        snapshot.Containers[containerName] = snapBars
    end
    return snapshot
end

local function applyHotbar(uuid, snapshot)
    if not snapshot or not snapshot.Containers then return false end
    local entity = Ext.Entity.Get(uuid)
    if not entity or not entity.HotbarContainer or not entity.HotbarContainer.Containers then return false end
    for containerName, snapBars in pairs(snapshot.Containers) do
        local liveBars = entity.HotbarContainer.Containers[containerName]
        if liveBars then
            for barIdx, snapBar in ipairs(snapBars) do
                local liveBar = liveBars[barIdx]
                if liveBar and snapBar.Elements then
                    -- Build a whole new Elements array from the snapshot
                    local newElements = {}
                    for slotIdx, snapSlot in ipairs(snapBar.Elements) do
                        local newSlot = {
                            Slot = snapSlot.Slot,
                            IsNew = snapSlot.IsNew or false,
                            Passive = snapSlot.Passive or "",
                        }
                        if snapSlot.SpellId then
                            newSlot.SpellId = {
                                Prototype = snapSlot.SpellId.Prototype or "",
                                OriginatorPrototype = snapSlot.SpellId.OriginatorPrototype or "",
                                ProgressionSource = snapSlot.SpellId.ProgressionSource,
                                Source = snapSlot.SpellId.Source,
                                SourceType = snapSlot.SpellId.SourceType,
                            }
                        end
                        if snapSlot.ItemUuid then
                            local itemEntity = Ext.Entity.Get(snapSlot.ItemUuid)
                            if itemEntity then newSlot.Item = itemEntity end
                        end
                        newElements[slotIdx] = newSlot
                    end
                    liveBar.Elements = newElements
                end
            end
        end
    end
    if snapshot.ActiveContainer then
        entity.HotbarContainer.ActiveContainer = snapshot.ActiveContainer
    end
    entity:Replicate("HotbarContainer")
    return true
end

local function ensureLoadoutList(loadouts, characterUuid)
    if not loadouts[characterUuid] or type(loadouts[characterUuid]) ~= "table" then
        loadouts[characterUuid] = {}
    end
    return loadouts[characterUuid]
end

local function getCurrentModeTag()
    return State.Settings.TurnBasedSwarmMode and "Swarm" or "Real-Time"
end

local function buildLoadoutSnapshot(characterUuid)
    return {
        reactions = snapshotReactions(characterUuid),
        preparedSpells = snapshotPreparedSpells(characterUuid),
        hotbar = snapshotHotbar(characterUuid),
    }
end

local function saveLoadout(characterUuid)
    local payload = buildLoadoutSnapshot(characterUuid)
    if not payload.reactions and not payload.preparedSpells and not payload.hotbar then return false end
    local loadouts = getCharacterLoadouts()
    local list = ensureLoadoutList(loadouts, characterUuid)
    table.insert(list, {
        name = "Loadout " .. tostring(#list + 1),
        mode = getCurrentModeTag(),
        reactions = payload.reactions,
        preparedSpells = payload.preparedSpells,
        hotbar = payload.hotbar,
    })
    setCharacterLoadouts(loadouts)
    return true
end

local function overwriteLoadout(characterUuid, index)
    local payload = buildLoadoutSnapshot(characterUuid)
    if not payload.reactions and not payload.preparedSpells and not payload.hotbar then return false end
    local loadouts = getCharacterLoadouts()
    local list = loadouts[characterUuid]
    if not list or not list[index] then return false end
    list[index].reactions = payload.reactions
    list[index].preparedSpells = payload.preparedSpells
    list[index].hotbar = payload.hotbar
    list[index].mode = getCurrentModeTag()
    setCharacterLoadouts(loadouts)
    return true
end

local function loadLoadout(characterUuid, index)
    local loadouts = getCharacterLoadouts()
    local list = loadouts[characterUuid]
    if not list or not list[index] then return false end
    local slot = list[index]
    if slot.reactions then applyReactions(characterUuid, slot.reactions) end
    if slot.preparedSpells then applyPreparedSpells(characterUuid, slot.preparedSpells) end
    if slot.hotbar then applyHotbar(characterUuid, slot.hotbar) end
    return true
end

local function deleteLoadout(characterUuid, index)
    local loadouts = getCharacterLoadouts()
    local list = loadouts[characterUuid]
    if not list or not list[index] then return false end
    table.remove(list, index)
    -- Renumber remaining default-named loadouts so the displayed numbering stays contiguous.
    for i, l in ipairs(list) do
        if l.name and l.name:match("^Loadout %d+$") then
            l.name = "Loadout " .. tostring(i)
        end
    end
    setCharacterLoadouts(loadouts)
    return true
end

local function getLoadoutsForCharacter(characterUuid)
    local loadouts = getCharacterLoadouts()
    local list = loadouts[characterUuid]
    if not list or type(list) ~= "table" then return {} end
    return list
end

-- Client-facing variant (strips the heavy payloads)
local function getClientLoadoutsForCharacter(characterUuid)
    local out = {}
    for i, l in ipairs(getLoadoutsForCharacter(characterUuid)) do
        out[i] = {
            name = l.name,
            mode = l.mode,
            hasReactions = l.reactions ~= nil,
            hasPreparedSpells = l.preparedSpells ~= nil,
            hasHotbar = l.hotbar ~= nil,
        }
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
