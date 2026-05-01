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

-- Host-only toggle.  When on, applyEquipment's camp-chest fallback scans every camp chest at camp instead of only the user's own.  Lets MP
-- players load loadouts referencing items in other users' chests, which BG3 normally hides via per-user chest access.
local function getSharedCampChestAccess()
    return getModVars().SharedCampChestAccess == true
end

local function setSharedCampChestAccess(value)
    getModVars().SharedCampChestAccess = value and true or false
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
    if not entity then return nil end
    local source
    if entity.PlayerPrepareSpell and entity.PlayerPrepareSpell.Spells then
        source = entity.PlayerPrepareSpell.Spells
    elseif entity.SpellBookPrepares and entity.SpellBookPrepares.PreparedSpells then
        source = entity.SpellBookPrepares.PreparedSpells
    else
        return nil
    end
    local snapshot = {}
    for i, spellMeta in ipairs(source) do
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
    if not entity then return false end
    if entity.PlayerPrepareSpell then
        entity.PlayerPrepareSpell.Spells = snapshot
        entity:Replicate("PlayerPrepareSpell")
    end
    if entity.SpellBookPrepares then
        entity.SpellBookPrepares.PreparedSpells = snapshot
        entity:Replicate("SpellBookPrepares")
    end
    return true
end

-- Equipment snapshot/apply via Osi
local function snapshotEquipment(uuid)
    local snapshot = {}
    local any = false
    for _, slot in ipairs(Constants.EQUIPMENT_SLOTS) do
        local item = Osi.GetEquippedItem(uuid, slot)
        if item and item ~= "" then
            snapshot[slot] = item
            any = true
        end
    end
    if not any then return nil end
    return snapshot
end

local function isInCamp(uuid)
    local entity = Ext.Entity.Get(uuid)
    return entity and entity.CampPresence ~= nil
end

local function findCampChest(characterUuid)
    local userId = Osi.GetReservedUserID(characterUuid)
    if not userId then return nil end
    for _, chest in ipairs(Ext.Entity.GetAllEntitiesWithComponent("CampChest")) do
        if chest.CampChest and chest.CampChest.UserID == userId then
            return chest
        end
    end
    return nil
end

local function isInCampChest(itemUuid, chest)
    if not chest or not chest.InventoryOwner or not chest.InventoryOwner.Inventories then return false end
    for _, invEntity in pairs(chest.InventoryOwner.Inventories) do
        if invEntity and invEntity.InventoryContainer and invEntity.InventoryContainer.Items then
            for _, slotData in pairs(invEntity.InventoryContainer.Items) do
                if slotData.Item and slotData.Item.Uuid and slotData.Item.Uuid.EntityUuid == itemUuid then
                    return true
                end
            end
        end
    end
    return false
end

-- Returns true if `itemUuid` is in any camp chest, used when the host has enabled SharedCampChestAccess.
local function isInAnyCampChest(itemUuid)
    for _, chest in ipairs(Ext.Entity.GetAllEntitiesWithComponent("CampChest")) do
        if isInCampChest(itemUuid, chest) then return true end
    end
    return false
end

local function applyEquipment(uuid, snapshot)
    if not snapshot then return false end
    -- Unequip all current items in the tracked slots
    for _, slot in ipairs(Constants.EQUIPMENT_SLOTS) do
        local current = Osi.GetEquippedItem(uuid, slot)
        if current and current ~= "" then
            Osi.Unequip(uuid, current)
        end
    end
    -- Camp-chest fallback: if character is currently at camp, also accept items in their camp chest.  If shared access is on, accept items in
    -- ANY camp chest at camp instead of just the user's own.
    local atCamp = isInCamp(uuid)
    local sharedAccess = getSharedCampChestAccess()
    local userChest = atCamp and not sharedAccess and findCampChest(uuid) or nil
    for _, slot in ipairs(Constants.EQUIPMENT_SLOTS) do
        local saved = snapshot[slot]
        if saved then
            local inInventory = Osi.GetInventoryOwner(saved) == uuid
            local inCampChest = false
            if atCamp then
                if sharedAccess then
                    inCampChest = isInAnyCampChest(saved)
                elseif userChest then
                    inCampChest = isInCampChest(saved, userChest)
                end
            end
            if inInventory or inCampChest then
                Osi.Equip(uuid, saved)
            end
        end
    end
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
        equipment = snapshotEquipment(characterUuid),
    }
end

local function saveLoadout(characterUuid)
    local payload = buildLoadoutSnapshot(characterUuid)
    if not payload.reactions and not payload.preparedSpells and not payload.hotbar and not payload.equipment then return false end
    local loadouts = getCharacterLoadouts()
    local list = ensureLoadoutList(loadouts, characterUuid)
    table.insert(list, {
        name = "Loadout " .. tostring(#list + 1),
        mode = getCurrentModeTag(),
        reactions = payload.reactions,
        preparedSpells = payload.preparedSpells,
        hotbar = payload.hotbar,
        equipment = payload.equipment,
    })
    setCharacterLoadouts(loadouts)
    return true
end

local function overwriteLoadout(characterUuid, index)
    local payload = buildLoadoutSnapshot(characterUuid)
    if not payload.reactions and not payload.preparedSpells and not payload.hotbar and not payload.equipment then return false end
    local loadouts = getCharacterLoadouts()
    local list = loadouts[characterUuid]
    if not list or not list[index] then return false end
    list[index].reactions = payload.reactions
    list[index].preparedSpells = payload.preparedSpells
    list[index].hotbar = payload.hotbar
    list[index].equipment = payload.equipment
    list[index].mode = getCurrentModeTag()
    setCharacterLoadouts(loadouts)
    return true
end

local function loadLoadout(characterUuid, index)
    local loadouts = getCharacterLoadouts()
    local list = loadouts[characterUuid]
    if not list or not list[index] then return false end
    local slot = list[index]
    if slot.equipment then applyEquipment(characterUuid, slot.equipment) end
    if slot.reactions then applyReactions(characterUuid, slot.reactions) end
    if slot.hotbar then applyHotbar(characterUuid, slot.hotbar) end
    if slot.preparedSpells then applyPreparedSpells(characterUuid, slot.preparedSpells) end
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
            hasEquipment = l.equipment ~= nil,
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
    getSharedCampChestAccess = getSharedCampChestAccess,
    setSharedCampChestAccess = setSharedCampChestAccess,
    applySummonOverrideTo = applySummonOverrideTo,
    applySummonOverrideToAll = applySummonOverrideToAll,
}
