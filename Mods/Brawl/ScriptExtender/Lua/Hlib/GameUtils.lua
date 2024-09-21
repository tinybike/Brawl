---@type Mod
local Mod = Require("Hlib/Mod")

---@type Constants
local Constants = Require("Hlib/Constants")

---@type Utils
local Log = Require("Hlib/Log")

---@type Utils
local Utils = Require("Hlib/Utils")

---@class GameUtils
local M = {}

-------------------------------------------------------------------------------------------------
--                                                                                             --
--                                        Client/Server                                        --
--                                                                                             --
-------------------------------------------------------------------------------------------------

M.Entity = {}

---@return EntityHandle[]
function M.Entity.GetParty()
    return Ext.Entity.GetAllEntitiesWithComponent("PartyMember")
end

---@return EntityHandle
function M.Entity.GetHost()
    if Ext.IsClient() then
        --- might not give the correct entity
        return Ext.Entity.GetAllEntitiesWithComponent("ClientControl")[1]
    end

    return Ext.Entity.Get(Osi.GetHostCharacter())
end

---@class EntityDistance
---@field Entity EntityHandle
---@field Guid string GUID
---@field Distance number
---@param source string GUID
---@param radius number|nil
---@param ignoreHeight boolean|nil
---@param withComponent ExtComponentType|nil
---@return EntityDistance[]
-- thanks to AtilioA/BG3-volition-cabinet
function M.Entity.GetNearby(source, radius, ignoreHeight, withComponent)
    radius = radius or 1
    withComponent = withComponent or "Uuid"

    ---@param entity string|EntityHandle GUID
    ---@return number[]|nil {x, y, z}
    local function entityPos(entity)
        entity = type(entity) == "string" and Ext.Entity.Get(entity) or entity
        local ok, pos = pcall(function()
            return entity.Transform.Transform.Translate
        end)
        if ok then
            return { pos[1], pos[2], pos[3] }
        end
        return nil
    end

    local sourcePos = entityPos(source)
    if not sourcePos then
        return {}
    end

    ---@param target number[] {x, y, z}
    ---@return number
    local function calcDisance(target)
        return math.sqrt(
            (sourcePos[1] - target[1]) ^ 2
                + (not ignoreHeight and (sourcePos[2] - target[2]) ^ 2 or 0)
                + (sourcePos[3] - target[3]) ^ 2
        )
    end

    local nearby = {}
    for _, entity in ipairs(Ext.Entity.GetAllEntitiesWithComponent(withComponent)) do
        local pos = entityPos(entity)
        if pos then
            local distance = calcDisance(pos)
            if distance <= radius then
                table.insert(nearby, {
                    Entity = entity,
                    Guid = entity.Uuid and entity.Uuid.EntityUuid,
                    Distance = distance,
                })
            end
        end
    end

    table.sort(nearby, function(a, b)
        return a.Distance < b.Distance
    end)

    return nearby
end

if Ext.IsClient() then
    return M
end

-------------------------------------------------------------------------------------------------
--                                                                                             --
--                                         Server Only                                         --
--                                                                                             --
-------------------------------------------------------------------------------------------------

M.DB = {}

---@param query string
---@param arity number
---@param args table
---@param take number|nil
---@return table
function M.DB.TryGet(query, arity, args, take)
    args = args or {}
    local success, result = pcall(function()
        local db = Osi[query]
        if db and db.Get then
            return db:Get(table.unpack(args, 1, arity))
        end
    end)

    if not success then
        M.Log.Error("Failed to get DB", query, result)
        return {}
    end

    if take then
        result = Utils.Table.Map(result, function(v)
            return v[take]
        end)
    end

    return result
end

---@return string[] list of avatar characters
function M.DB.GetAvatars()
    return M.DB.TryGet("DB_Avatars", 1, nil, 1)
end

---@return string[] list of playable characters
function M.DB.GetPlayers()
    return M.DB.TryGet("DB_Players", 1, nil, 1)
end

M.Character = {}

---@param character string GUID
---@return boolean
function M.Character.IsHireling(character)
    local faction = Osi.GetFaction(character)

    return faction and faction:match("^Hireling") ~= nil
end

---@param character string GUID
---@return boolean
function M.Character.IsOrigin(character)
    local faction = Osi.GetFaction(character)
    if faction and (faction:match("^Origin") ~= nil or faction:match("^Companion") ~= nil) then
        return true
    end

    return Utils.Table.Find(Constants.OriginCharacters, function(v)
        return Utils.UUID.Equals(v, character)
    end) ~= nil
end

---@param character string GUID
---@param checkInPartyIsPlayable boolean|nil default false - party members are considered player characters
---@return boolean
function M.Character.IsNonPlayer(character, checkInPartyIsPlayable)
    if not checkInPartyIsPlayable and (Osi.IsPartyMember(character, 1) == 1 or Osi.IsPartyFollower(character) == 1) then
        return false
    end

    return not M.Character.IsPlayable(character)
end

---@param character string GUID
---@return boolean
function M.Character.IsPlayable(character)
    return M.Character.IsOrigin(character)
        or M.Character.IsHireling(character)
        or Osi.IsPlayer(character) == 1
        or (
            Utils.Table.Find(M.DB.GetAvatars(), function(v)
                return Utils.UUID.Equals(v, character)
            end) ~= nil
        )
end

---@param character string GUID
---@return boolean
function M.Character.IsImportant(character)
    return M.Character.IsPlayable(character)
        or (
            Utils.Table.Find(Constants.NPCCharacters, function(v)
                return Utils.UUID.Equals(v, character)
            end) ~= nil
        )
end

---@param character string GUID
---@return boolean
function M.Character.IsValid(character)
    return Osi.IsCharacter(character) == 1 and Osi.IsOnStage(character) == 1
end

---@param character string GUID
---@return string character GUID
function M.Character.GetPlayer(character)
    character = Osi.CharacterGetOwner(character) or character

    if Osi.IsPlayer(character) ~= 1 then
        character = Osi.GetHostCharacter()
    end

    return character
end

---@param character string GUID
---@return boolean
function M.Character.IsHost(character)
    return Utils.UUID.Equals(Osi.GetHostCharacter(), character)
end

---@param userId number
---@return string character GUID
function M.Character.GetForUser(userId)
    return Osi.GetCurrentCharacter(userId)
end

---@param character string GUID
---@param learnedSpell string
---@param sourceType string|nil
---@param class string|nil
-- thanks to AtilioA/BG3-volition-cabinet
function M.Character.RemoveSpell(character, learnedSpell, sourceType, class)
    local entity = Ext.Entity.Get(character)
    if entity == nil then
        return
    end

    if entity.HotbarContainer ~= nil then
        local hotbar = entity.HotbarContainer
        local editedHotbar = false

        for containerName, container in pairs(hotbar.Containers) do
            for i, subContainer in ipairs(container) do
                for j, spell in ipairs(subContainer.Elements) do
                    if
                        spell.SpellId.OriginatorPrototype == learnedSpell
                        and (sourceType == nil or spell.SpellId.SourceType == sourceType)
                    then
                        hotbar.Containers[containerName][i].Elements[j] = nil
                        editedHotbar = true
                    end
                end
            end
        end

        if editedHotbar then
            entity:Replicate("HotbarContainer")
        end
    end

    if entity.LearnedSpells ~= nil and class ~= nil then
        local learnedSpells = entity.LearnedSpells
        local editedLearnedSpells = false
        for i, spell in ipairs(learnedSpells.field_18[class]) do
            if spell == learnedSpell then
                learnedSpells.field_18[class][i] = nil
                editedLearnedSpells = true
                break
            end
        end

        if editedLearnedSpells then
            entity:Replicate("LearnedSpells")
        end
    end

    if entity.SpellBook ~= nil then
        local spellBook = entity.SpellBook
        local editedSpellBook = false
        for i, spell in ipairs(spellBook.Spells) do
            if
                spell.Id.OriginatorPrototype == learnedSpell
                and (sourceType == nil or spell.Id.SourceType == sourceType)
            then
                spellBook.Spells[i] = nil
                editedSpellBook = true
                break
            end
        end

        if editedSpellBook then
            entity:Replicate("SpellBook")
        end
    end

    if entity.PlayerPrepareSpell ~= nil then
        local playerPrepareSpell = entity.PlayerPrepareSpell
        local editedPlayerPrepareSpell = false
        for i, spell in ipairs(playerPrepareSpell.Spells) do
            if spell.OriginatorPrototype == learnedSpell and (sourceType == nil or spell.SourceType == sourceType) then
                playerPrepareSpell.Spells[i] = nil
                editedPlayerPrepareSpell = true
                break
            end
        end
        if editedPlayerPrepareSpell then
            entity:Replicate("PlayerPrepareSpell")
        end
    end

    if entity.SpellBookPrepares ~= nil then
        local spellBookPrepares = entity.SpellBookPrepares
        local editedSpellBookPrepares = false
        for i, spell in ipairs(spellBookPrepares.PreparedSpells) do
            if spell.OriginatorPrototype == learnedSpell and (sourceType == nil or spell.SourceType == sourceType) then
                spellBookPrepares.PreparedSpells[i] = nil
                editedSpellBookPrepares = true
                break
            end
        end

        if editedSpellBookPrepares then
            entity:Replicate("SpellBookPrepares")
        end
    end

    if entity.SpellContainer ~= nil then
        local spellContainer = entity.SpellContainer
        local editedSpellContainer = false
        for i, spell in ipairs(spellContainer.Spells) do
            if
                spell.SpellId.OriginatorPrototype == learnedSpell
                and (sourceType == nil or spell.SpellId.SourceType == sourceType)
            then
                spellContainer.Spells[i] = nil
                editedSpellContainer = true
                break
            end
        end

        if editedSpellContainer then
            entity:Replicate("SpellContainer")
        end
    end
end

M.Object = {}

-- also works for items
function M.Object.Remove(guid)
    Osi.PROC_RemoveAllPolymorphs(guid)
    Osi.PROC_RemoveAllDialogEntriesForSpeaker(guid)
    Osi.SetOnStage(guid, 0)
    Osi.SetHasDialog(guid, 0)
    Osi.RequestDelete(guid)
    Osi.RequestDeleteTemporary(guid)
    Osi.UnloadItem(guid)
    Osi.Die(guid, 2, Constants.NullGuid, 0, 1)
end

function M.Object.IsOwned(guid)
    return Osi.IsInInventory(guid) == 1 or not M.Character.IsNonPlayer(Osi.GetOwner(guid) or "")
end

return M
