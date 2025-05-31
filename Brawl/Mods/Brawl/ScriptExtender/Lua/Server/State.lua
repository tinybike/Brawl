-- local Constants = require("Server/Constants.lua")
-- local Utils = require("Server/Utils.lua")
-- local Resources = require("Server/Resources.lua")

local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump
local getDisplayName = Utils.getDisplayName
local isSilenced = Utils.isSilenced

-- Settings
local Settings = {
    ModEnabled = true,
    CompanionAIEnabled = true,
    TruePause = true,
    AutoPauseOnDowned = true,
    ActionInterval = 6.0,
    InitiativeDie = 20,
    FullAuto = false,
    HitpointsMultiplier = 1.0,
    CompanionTactics = "Balanced",
    DefensiveTacticsMaxDistance = 15,
    CompanionAIMaxSpellLevel = 0,
    HogwildMode = false,
    MaxPartySize = 4,
    MurderhoboMode = false,
    TurnBasedSwarmMode = false,
}
if MCM then
    Settings.ModEnabled = MCM.Get("mod_enabled")
    Settings.CompanionAIEnabled = MCM.Get("companion_ai_enabled")
    Settings.TruePause = MCM.Get("true_pause")
    Settings.AutoPauseOnDowned = MCM.Get("auto_pause_on_downed")
    Settings.ActionInterval = MCM.Get("action_interval")
    Settings.InitiativeDie = MCM.Get("initiative_die")
    Settings.FullAuto = MCM.Get("full_auto")
    Settings.HitpointsMultiplier = MCM.Get("hitpoints_multiplier")
    Settings.CompanionTactics = MCM.Get("companion_tactics")
    Settings.DefensiveTacticsMaxDistance = MCM.Get("defensive_tactics_max_distance")
    Settings.CompanionAIMaxSpellLevel = MCM.Get("companion_ai_max_spell_level")
    Settings.HogwildMode = MCM.Get("hogwild_mode")
    Settings.MaxPartySize = MCM.Get("max_party_size")
    Settings.MurderhoboMode = MCM.Get("murderhobo_mode")
    Settings.TurnBasedSwarmMode = MCM.Get("turn_based_swarm_mode")
end

-- Session state
local Session = {
    SpellTable = {},
    Listeners = {},
    Brawlers = {},
    Players = {},
    PulseAddNearbyTimers = {},
    PulseRepositionTimers = {},
    PulseActionTimers = {},
    BrawlFizzler = {},
    IsAttackingOrBeingAttackedByPlayer = {},
    ClosestEnemyBrawlers = {},
    PlayerMarkedTarget = {},
    PlayerCurrentTarget = {},
    ActionsInProgress = {},
    MovementQueue = {},
    PartyMembersMovementResourceListeners = {},
    PartyMembersHitpointsListeners = {},
    ActionResourcesListeners = {},
    TurnBasedListeners = {},
    SpellCastMovementListeners = {},
    FTBLockedIn = {},
    LastClickPosition = {},
    ActiveCombatGroups = {},
    AwaitingTarget = {},
    RemainingMovement = {},
    HealRequested = {},
    HealRequestedTimer = {},
    CountdownTimer = {},
    ExtraAttacksRemaining = {},
    StoryActionIDSpellName = {},
    ToTTimer = nil,
    ToTRoundTimer = nil,
    ModStatusMessageTimer = nil,
    MovementSpeedThresholds = Constants.MOVEMENT_SPEED_THRESHOLDS.EASY,
}

-- Persistent state
Ext.Vars.RegisterModVariable(ModuleUUID, "SpellRequirements", {Server = true, Client = false, SyncToClient = false})
Ext.Vars.RegisterModVariable(ModuleUUID, "ModifiedHitpoints", {Server = true, Client = false, SyncToClient = false})
Ext.Vars.RegisterModVariable(ModuleUUID, "MovementDistances", {Server = true, Client = false, SyncToClient = false})
Ext.Vars.RegisterModVariable(ModuleUUID, "PartyArchetypes", {Server = true, Client = false, SyncToClient = false})

local function hasTargetCondition(targetConditionString, condition)
    local parts = {}
    for part in targetConditionString:gmatch("%S+") do
        table.insert(parts, part)
    end
    for i, p in ipairs(parts) do
        if p == condition then
            if i == 1 or parts[i - 1] ~= "not" then
                return true
            end
        end
    end
    return false
end

local function isSafeAoESpell(spellName)
    for _, safeAoESpell in ipairs(Constants.SAFE_AOE_SPELLS) do
        if spellName == safeAoESpell then
            return true
        end
    end
    return false
end

local function hasStringInSpellRoll(spell, target)
    if spell and spell.SpellRoll and spell.SpellRoll.Default then
        return string.find(spell.SpellRoll.Default, target, 1, true) ~= nil
    end
    return false
end

local function spellId(spell, spellName)
    return spell.Name == spellName
end

local function extraAttackSpellCheck(spell)
    return hasStringInSpellRoll(spell, "WeaponAttack") or hasStringInSpellRoll(spell, "UnarmedAttack") or hasStringInSpellRoll(spell, "ThrowAttack") or spellId(spell, "Target_CommandersStrike") or spellId(spell, "Target_Bufotoxin_Frog_Summon") or spellId(spell, "Projectile_ArrowOfSmokepowder")
end

local function parseSpellUseCosts(spell)
    local useCosts = Utils.split(spell.UseCosts, ";")
    local costs = {
        ShortRest = spell.Cooldown == "OncePerShortRest" or spell.Cooldown == "OncePerShortRestPerItem",
        LongRest = spell.Cooldown == "OncePerRest" or spell.Cooldown == "OncePerRestPerItem",
    }
    -- local hitCost = nil -- divine smite only..?
    for _, useCost in ipairs(useCosts) do
        local useCostTable = Utils.split(useCost, ":")
        local useCostLabel = useCostTable[1]:match("^%s*(.-)%s*$")
        local useCostAmount = tonumber(useCostTable[#useCostTable])
        if useCostLabel == "SpellSlotsGroup" then
            -- e.g. SpellSlotsGroup:1:1:2
            -- NB: what are the first two numbers?
            costs.SpellSlot = useCostAmount
        else
            costs[useCostLabel] = useCostAmount
        end
    end
    return costs
end

local function hasUseCosts(spell, targetCost)
    if spell and spell.UseCosts then
        local costs = parseSpellUseCosts(spell)
        if costs then
            for cost, _ in pairs(costs) do
                if cost == targetCost then
                    return true
                end
            end
        end
    end
    return false
end

local function extraAttackCheck(spell)
    return extraAttackSpellCheck(spell) and hasUseCosts(spell, "ActionPoint")
end

local function isSpellOfType(spell, spellType)
    if not spell then
        return false
    end
    local isOfType = spell.VerbalIntent == spellType
    if not isOfType and spellType == "Damage" then
        local spellFlags = spell.SpellFlags
        if spellFlags then
            for _, flag in ipairs(spellFlags) do
                if flag == "IsHarmful" then
                    isOfType = true
                    break
                end
            end
        end
    end
    return isOfType
end

local function getSpellTypeByName(name)
    local spellStats = Ext.Stats.Get(name)
    if spellStats then
        local spellType = spellStats.VerbalIntent
        if spellType == "None" and isSpellOfType(spellStats, "Damage") then
            spellType = "Damage"
        end
        return spellType
    end
end

local function calculateMean(value)
    local numDice, numSides = tostring(value):match("(%d+)d(%d+)")
    if numDice and numSides then
        numDice = tonumber(numDice)
        numSides = tonumber(numSides)
        return numDice*(numSides + 1)/2
    end
    return tonumber(value)
end

local function getCantripDamage(level)
    if level >= 10 then
        return 13.5  -- 3d8
    elseif level >= 5 then
        return 9     -- 2d8
    else
        return 4.5   -- 1d8
    end
end

local function isWeaponOrUnarmed(value)
    local keywords = {
        "MainMeleeWeapon",
        "MainMeleeWeaponDamageType",
        "OffhandMeleeWeapon",
        "OffhandMeleeWeaponDamageType",
        "MainRangedWeapon",
        "MainRangedWeaponDamageType",
        "OffhandRangedWeapon",
        "OffhandRangedWeaponDamageType",
        "UnarmedDamage",
        "MartialArtsUnarmedDamage",
    }
    for _, marker in ipairs(keywords) do
        if value:find(marker) then
            return true
        end
    end
    return false
end

local function parseTooltipDamage(damageString, level)
    damageString = damageString:gsub("LevelMapValue%((%w+)%)", function (variableName)
        if variableName == "D8Cantrip" then
            return tostring(getCantripDamage(level))
        end
    end)
    local isWeaponOrUnarmedDamage = false
    local totalDamage = 0
    for rawArg in damageString:gmatch("DealDamage%(([^%)]+)%)") do
        local damageValue = rawArg:match("([^,]+)")
        if damageValue then
            if isWeaponOrUnarmed(damageValue) then
                isWeaponOrUnarmedDamage = true
            end
            local meanVal = calculateMean(damageValue)
            if meanVal then
                totalDamage = totalDamage + meanVal
            end
        end
    end
    return isWeaponOrUnarmedDamage, totalDamage
end

local function getSpellInfo(spellType, spellName, hostLevel)
    local spell = Ext.Stats.Get(spellName)
    if isSpellOfType(spell, spellType) then
        local outOfCombatOnly = false
        for _, req in ipairs(spell.Requirements) do
            if req.Requirement == "Combat" and req.Not == true then
                outOfCombatOnly = true
            end
        end
        local hasVerbalComponent = false
        for _, flag in ipairs(spell.SpellFlags) do
            if flag == "HasVerbalComponent" then
                hasVerbalComponent = true
            end
        end
        local isWeaponOrUnarmedDamage, averageDamage = parseTooltipDamage(spell.TooltipDamageList, hostLevel)
        local spellInfo = {
            level = spell.Level,
            areaRadius = spell.AreaRadius,
            isSelfOnly = hasTargetCondition(spell.TargetConditions, "Self()"),
            isCharacterOnly = hasTargetCondition(spell.TargetConditions, "Character()"),
            outOfCombatOnly = outOfCombatOnly,
            -- damageType = spell.DamageType,
            isGapCloser = spell.SpellType == "Rush",
            isSpell = spell.SpellSchool ~= "None",
            isEvocation = spell.SpellSchool == "Evocation",
            isSafeAoE = isSafeAoESpell(spellName),
            targetRadius = spell.TargetRadius,
            range = spell.Range,
            costs = parseSpellUseCosts(spell),
            type = spellType,
            hasVerbalComponent = hasVerbalComponent,
            averageDamage = averageDamage,
            isWeaponOrUnarmedDamage = isWeaponOrUnarmedDamage,
            triggersExtraAttack = extraAttackCheck(spell),
        }
        if spellType == "Healing" then
            spellInfo.isDirectHeal = false
            local spellProperties = spell.SpellProperties
            if spellProperties then
                for _, spellProperty in ipairs(spellProperties) do
                    local functors = spellProperty.Functors
                    if functors then
                        for _, functor in ipairs(functors) do
                            if functor.TypeId == "RegainHitPoints" then
                                spellInfo.isDirectHeal = true
                            end
                        end
                    end
                end
            end
        end
        return spellInfo
    end
    return nil
end

local function getAllSpellsOfType(spellType, hostLevel)
    local allSpellsOfType = {}
    for _, spellName in ipairs(Ext.Stats.GetStats("SpellData")) do
        local spell = Ext.Stats.Get(spellName)
        if isSpellOfType(spell, spellType) then
            if spell.ContainerSpells and spell.ContainerSpells ~= "" then
                local containerSpellNames = Utils.split(spell.ContainerSpells, ";")
                for _, containerSpellName in ipairs(containerSpellNames) do
                    allSpellsOfType[containerSpellName] = getSpellInfo(spellType, containerSpellName, hostLevel)
                end
            else
                allSpellsOfType[spellName] = getSpellInfo(spellType, spellName, hostLevel)
                if spell.Requirements and #spell.Requirements ~= 0 then
                    local requirements = spell.Requirements
                    local removeIndex = 0
                    for i, req in ipairs(requirements) do
                        if req.Requirement == "Combat" and req.Not == false then
                            removeIndex = i
                            local removedReq = {Requirement = req.Requirement, Param = req.Param, Not = req.Not, index = i}
                            local modVars = Ext.Vars.GetModVariables(ModuleUUID)
                            modVars.SpellRequirements = modVars.SpellRequirements or {}
                            modVars.SpellRequirements[spellName] = removedReq
                            break
                        end
                    end
                    if removeIndex ~= 0 then
                        table.remove(requirements, removeIndex)
                    end
                    spell.Requirements = requirements
                    spell:Sync()
                end
            end
        end
    end
    return allSpellsOfType
end

local function getArchetype(uuid)
    local archetype
    if Session.Players and Session.Players[uuid] then
        local modVars = Ext.Vars.GetModVariables(ModuleUUID)
        local partyArchetypes = modVars.PartyArchetypes
        if partyArchetypes == nil then
            partyArchetypes = {}
            modVars.PartyArchetypes = partyArchetypes
        else
            archetype = partyArchetypes[uuid]
        end
    end
    if archetype == nil or archetype == "" then
        archetype = Osi.GetActiveArchetype(uuid)
    end
    if not Constants.ARCHETYPE_WEIGHTS[archetype] then
        if archetype == "base" then
            archetype = "melee"
        elseif archetype:find("ranged") ~= nil then
            archetype = "ranged"
        elseif archetype:find("healer") ~= nil then
            archetype = "healer"
        elseif archetype:find("mage") ~= nil then
            archetype = "mage"
        elseif archetype:find("melee_magic") ~= nil then
            archetype = "melee_magic"
        elseif archetype:find("healer_melee") ~= nil then
            archetype = "healer_melee"
        else
            debugPrint("Archetype missing from the list, using melee for now", archetype)
            archetype = "melee"
        end
    end
    return archetype
end

local function checkForDownedOrDeadPlayers()
    local players = Session.Players
    if players then
        for uuid, player in pairs(players) do
            if Osi.IsDead(uuid) == 1 or Utils.isDowned(uuid) then
                Utils.clearOsirisQueue(uuid)
                Osi.LieOnGround(uuid)
            end
        end
    end
end

local function areAnyPlayersBrawling()
    if Session.Players then
        for playerUuid, player in pairs(Session.Players) do
            local level = Osi.GetRegion(playerUuid)
            if level and Session.Brawlers[level] and Session.Brawlers[level][playerUuid] then
                return true
            end
        end
    end
    return false
end

local function getNumEnemiesRemaining(level)
    local numEnemiesRemaining = 0
    for brawlerUuid, brawler in pairs(Session.Brawlers[level]) do
        if Utils.isPugnacious(brawlerUuid) and brawler.isInBrawl then
            numEnemiesRemaining = numEnemiesRemaining + 1
        end
    end
    return numEnemiesRemaining
end

local function isPlayerControllingDirectly(entityUuid)
    return Session.Players[entityUuid] ~= nil and Session.Players[entityUuid].isControllingDirectly == true
end

local function getPlayerByUserId(userId)
    if Session.Players then
        for uuid, player in pairs(Session.Players) do
            if player.userId == userId and player.isControllingDirectly then
                return player
            end
        end
    end
    return nil
end

local function getBrawlerByUuid(uuid)
    local level = Osi.GetRegion(uuid)
    if level and Session.Brawlers[level] then
        return Session.Brawlers[level][uuid]
    end
    return nil
end

local function isPartyInRealTime()
    if Session.Players then
        for uuid, _ in pairs(Session.Players) do
            if Osi.IsInForceTurnBasedMode(uuid) == 1 then
                return false
            end
        end
    end
    return true
end

local function getSpellByName(name)
    if name then
        local spellType = getSpellTypeByName(name)
        if spellType and Session.SpellTable[spellType] then
            return Session.SpellTable[spellType][name]
        end
    end
    return nil
end

local function hasDirectHeal(uuid, preparedSpells, excludeSelfOnly)
    if isSilenced(uuid) then
        return false
    end
    for _, preparedSpell in ipairs(preparedSpells) do
        local spellName = preparedSpell.OriginatorPrototype
        local spell = Session.SpellTable.Healing[spellName]
        local isUsableHeal = (spell ~= nil) and spell.isDirectHeal
        if isUsableHeal and excludeSelfOnly then
            isUsableHeal = isUsableHeal and not spell.isSelfOnly
        end
        if isUsableHeal then
            if Settings.HogwildMode then
                return true
            elseif Resources.hasEnoughToCastSpell(uuid, spellName) then
                return true
            end
        end
    end
    return false
end

local function buildSpellTable()
    local hostLevel = Osi.GetLevel(Osi.GetHostCharacter())
    local spellTable = {}
    for _, spellType in pairs(Constants.ALL_SPELL_TYPES) do
        spellTable[spellType] = getAllSpellsOfType(spellType, hostLevel)
    end
    Session.SpellTable = spellTable
end

local function resetSpellData()
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    if modVars and modVars.SpellRequirements then
        local spellReqs = modVars.SpellRequirements
        for spellName, req in pairs(spellReqs) do
            local spell = Ext.Stats.Get(spellName)
            if spell then
                local requirements = spell.Requirements
                table.insert(requirements, {Requirement = req.Requirement, Param = req.Param, Not = req.Not})
                spell.Requirements = requirements
                spell:Sync()
            end
        end
        modVars.SpellRequirements = nil
    end
end

local function uncapMovementDistance(entityUuid)
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    if modVars.MovementDistances == nil then
        modVars.MovementDistances = {}
    end
    local movementDistances = modVars.MovementDistances
    if Osi.IsCharacter(entityUuid) == 1 and Osi.IsDead(entityUuid) == 0 and movementDistances[entityUuid] == nil then
        -- debugPrint("Uncap movement distance", entityUuid, Constants.UNCAPPED_MOVEMENT_DISTANCE)
        local entity = Ext.Entity.Get(entityUuid)
        local originalMaxAmount = Movement.getMovementDistanceMaxAmount(entity)
        if movementDistances[entityUuid] == nil then
            movementDistances[entityUuid] = {}
        end
        movementDistances[entityUuid].updating = true
        modVars.MovementDistances = movementDistances
        entity.ActionResources.Resources[Constants.ACTION_RESOURCES.Movement][1].MaxAmount = Constants.UNCAPPED_MOVEMENT_DISTANCE
        entity.ActionResources.Resources[Constants.ACTION_RESOURCES.Movement][1].Amount = Constants.UNCAPPED_MOVEMENT_DISTANCE
        entity:Replicate("ActionResources")
        movementDistances = Ext.Vars.GetModVariables(ModuleUUID).MovementDistances
        movementDistances[entityUuid].originalMaxAmount = originalMaxAmount
        modVars.MovementDistances = movementDistances
        _D(movementDistances)
    end
end

local function capMovementDistance(entityUuid)
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    local movementDistances = modVars.MovementDistances
    if movementDistances and movementDistances[entityUuid] ~= nil and Osi.IsCharacter(entityUuid) == 1 then
        -- debugPrint("Cap movement distance", entityUuid)
        -- debugDump(movementDistances[entityUuid])
        local entity = Ext.Entity.Get(entityUuid)
        if movementDistances[entityUuid] == nil then
            movementDistances[entityUuid] = {}
        end
        movementDistances[entityUuid].updating = true
        modVars.MovementDistances = movementDistances
        entity.ActionResources.Resources[Constants.ACTION_RESOURCES.Movement][1].MaxAmount = movementDistances[entityUuid].originalMaxAmount
        entity.ActionResources.Resources[Constants.ACTION_RESOURCES.Movement][1].Amount = movementDistances[entityUuid].originalMaxAmount
        entity:Replicate("ActionResources")
        movementDistances[entityUuid] = nil
        modVars.MovementDistances = movementDistances
        -- debugPrint("Capped distance:", entityUuid, getDisplayName(entityUuid), Movement.getMovementDistanceMaxAmount(entity))
    end
end

local function revertHitpoints(entityUuid)
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    local modifiedHitpoints = modVars.ModifiedHitpoints
    if modifiedHitpoints and modifiedHitpoints[entityUuid] ~= nil and Osi.IsCharacter(entityUuid) == 1 then
        -- debugPrint("Reverting hitpoints", entityUuid)
        -- debugDump(modifiedHitpoints[entityUuid])
        local entity = Ext.Entity.Get(entityUuid)
        local currentMaxHp = entity.Health.MaxHp
        local currentHp = entity.Health.Hp
        local multiplier = modifiedHitpoints[entityUuid].multiplier or Settings.HitpointsMultiplier
        if modifiedHitpoints[entityUuid] == nil then
            modifiedHitpoints[entityUuid] = {}
        end
        modifiedHitpoints[entityUuid].updating = true
        modVars.ModifiedHitpoints = modifiedHitpoints
        entity.Health.MaxHp = math.floor(currentMaxHp/multiplier + 0.5)
        entity.Health.Hp = math.floor(currentHp/multiplier + 0.5)
        entity:Replicate("Health")
        modifiedHitpoints[entityUuid] = nil
        modVars.ModifiedHitpoints = modifiedHitpoints
        -- debugPrint("Reverted hitpoints:", entityUuid, getDisplayName(entityUuid), entity.Health.MaxHp, entity.Health.Hp)
    end
end

local function modifyHitpoints(entityUuid)
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    if modVars.ModifiedHitpoints == nil then
        modVars.ModifiedHitpoints = {}
    end
    local modifiedHitpoints = modVars.ModifiedHitpoints
    if Osi.IsCharacter(entityUuid) == 1 and Osi.IsDead(entityUuid) == 0 and modifiedHitpoints[entityUuid] == nil then
        -- debugPrint("modify hitpoints", entityUuid, Settings.HitpointsMultiplier)
        local entity = Ext.Entity.Get(entityUuid)
        local originalMaxHp = entity.Health.MaxHp
        local originalHp = entity.Health.Hp
        if modifiedHitpoints[entityUuid] == nil then
            modifiedHitpoints[entityUuid] = {}
        end
        modifiedHitpoints[entityUuid].updating = true
        modVars.ModifiedHitpoints = modifiedHitpoints
        entity.Health.MaxHp = math.floor(originalMaxHp*Settings.HitpointsMultiplier + 0.5)
        entity.Health.Hp = math.floor(originalHp*Settings.HitpointsMultiplier + 0.5)
        entity:Replicate("Health")
        modifiedHitpoints = Ext.Vars.GetModVariables(ModuleUUID).ModifiedHitpoints
        modifiedHitpoints[entityUuid].maxHp = entity.Health.MaxHp
        modifiedHitpoints[entityUuid].multiplier = Settings.HitpointsMultiplier
        modVars.ModifiedHitpoints = modifiedHitpoints
        -- debugPrint("Modified hitpoints:", entityUuid, getDisplayName(entityUuid), originalMaxHp, originalHp, entity.Health.MaxHp, entity.Health.Hp)
    end
end

local function uncapPartyMembersMovementDistances()
    for _, partyMember in ipairs(Osi.DB_PartyMembers:Get(nil)) do
        local partyMemberUuid = Osi.GetUUID(partyMember[1])
        capMovementDistance(partyMemberUuid)
        uncapMovementDistance(partyMemberUuid)
        if Session.PartyMembersMovementResourceListeners[partyMemberUuid] ~= nil then
            Ext.Entity.Unsubscribe(Session.PartyMembersMovementResourceListeners[partyMemberUuid])
        end
        Session.PartyMembersMovementResourceListeners[partyMemberUuid] = Ext.Entity.Subscribe("ActionResources", function (entity, _, _)
            local uuid = entity.Uuid.EntityUuid
            -- debugPrint("ActionResources changed", uuid)
            local modVars = Ext.Vars.GetModVariables(ModuleUUID)
            local movementDistances = modVars.MovementDistances
            if movementDistances and movementDistances[uuid] ~= nil and Constants.UNCAPPED_MOVEMENT_DISTANCE ~= Movement.getMovementDistanceMaxAmount(entity) then
                debugDump(movementDistances[uuid])
                if movementDistances[uuid].updating == false then
                    -- External change detected; re-apply modifications
                    -- debugPrint("External MaxAmount movement distance change detected for", uuid, ". Re-uncapping...")
                    movementDistances[uuid] = nil
                    modVars.MovementDistances = movementDistances
                    uncapMovementDistance(uuid)
                end
            end
            modVars = Ext.Vars.GetModVariables(ModuleUUID)
            movementDistances = modVars.MovementDistances
            movementDistances[uuid] = movementDistances[uuid] or {}
            movementDistances[uuid].updating = false
            modVars.MovementDistances = movementDistances
        end, Ext.Entity.Get(partyMemberUuid))
    end
end

local function setupPartyMembersHitpoints()
    for _, partyMember in ipairs(Osi.DB_PartyMembers:Get(nil)) do
        local partyMemberUuid = Osi.GetUUID(partyMember[1])
        revertHitpoints(partyMemberUuid)
        modifyHitpoints(partyMemberUuid)
        if Session.PartyMembersHitpointsListeners[partyMemberUuid] ~= nil then
            Ext.Entity.Unsubscribe(Session.PartyMembersHitpointsListeners[partyMemberUuid])
        end
        Session.PartyMembersHitpointsListeners[partyMemberUuid] = Ext.Entity.Subscribe("Health", function (entity, _, _)
            local uuid = entity.Uuid.EntityUuid
            -- debugPrint("Health changed", uuid)
            local modVars = Ext.Vars.GetModVariables(ModuleUUID)
            local modifiedHitpoints = modVars.ModifiedHitpoints
            if modifiedHitpoints and modifiedHitpoints[uuid] ~= nil and modifiedHitpoints[uuid].maxHp ~= entity.Health.MaxHp then
                debugDump(modifiedHitpoints[uuid])
                if modifiedHitpoints[uuid].updating == false then
                    -- External change detected; re-apply modifications
                    -- debugPrint("External MaxHp change detected for", uuid, ". Re-applying hitpoint modifications.")
                    modifiedHitpoints[uuid] = nil
                    modVars.ModifiedHitpoints = modifiedHitpoints
                    modifyHitpoints(uuid)
                end
            end
            modVars = Ext.Vars.GetModVariables(ModuleUUID)
            modifiedHitpoints = modVars.ModifiedHitpoints
            modifiedHitpoints[uuid] = modifiedHitpoints[uuid] or {}
            modifiedHitpoints[uuid].updating = false
            modVars.ModifiedHitpoints = modifiedHitpoints
        end, Ext.Entity.Get(partyMemberUuid))
    end
end

local function recapPartyMembersMovementDistances()
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    if modVars.MovementDistances and next(modVars.MovementDistances) ~= nil then
        for uuid, _ in pairs(modVars.MovementDistances) do
            capMovementDistance(uuid)
        end
    end
    for _, listener in pairs(Session.PartyMembersMovementResourceListeners) do
        Ext.Entity.Unsubscribe(listener)
    end
end

local function revertAllModifiedHitpoints()
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    if modVars.ModifiedHitpoints and next(modVars.ModifiedHitpoints) ~= nil then
        for uuid, _ in pairs(modVars.ModifiedHitpoints) do
            revertHitpoints(uuid)
        end
    end
    for _, listener in pairs(Session.PartyMembersHitpointsListeners) do
        Ext.Entity.Unsubscribe(listener)
    end
end

local function setMaxPartySize()
    Osi.SetMaxPartySizeOverride(Settings.MaxPartySize)
	Osi.PROC_CheckPartyFull()
end

local function setupPlayer(guid)
    local uuid = Osi.GetUUID(guid)
    if uuid then
        if not Session.Players then
            Session.Players = {}
        end
        Session.Players[uuid] = {
            uuid = uuid,
            guid = guid,
            displayName = getDisplayName(uuid),
            userId = Osi.GetReservedUserID(uuid),
        }
        Osi.SetCanJoinCombat(uuid, 1)
    end
end

local function resetPlayers()
    Session.Players = {}
    for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
        setupPlayer(player[1])
    end
end

local function setIsControllingDirectly()
    if Session.Players ~= nil and next(Session.Players) ~= nil then
        for playerUuid, player in pairs(Session.Players) do
            player.isControllingDirectly = false
        end
        local entities = Ext.Entity.GetAllEntitiesWithComponent("ClientControl")
        for _, entity in ipairs(entities) do
            -- New player (client) just joined: they might not be in the Session.Players table yet
            if Session.Players[entity.Uuid.EntityUuid] == nil then
                resetPlayers()
            end
        end
        for _, entity in ipairs(entities) do
            Session.Players[entity.Uuid.EntityUuid].isControllingDirectly = true
        end
    end
end

return {
    getArchetype = getArchetype,
    checkForDownedOrDeadPlayers = checkForDownedOrDeadPlayers,
    areAnyPlayersBrawling = areAnyPlayersBrawling,
    getNumEnemiesRemaining = getNumEnemiesRemaining,
    isPlayerControllingDirectly = isPlayerControllingDirectly,
    getPlayerByUserId = getPlayerByUserId,
    getBrawlerByUuid = getBrawlerByUuid,
    isPartyInRealTime = isPartyInRealTime,
    getSpellByName = getSpellByName,
    hasDirectHeal = hasDirectHeal,
    buildSpellTable = buildSpellTable,
    resetSpellData = resetSpellData,
    revertHitpoints = revertHitpoints,
    modifyHitpoints = modifyHitpoints,
    setupPartyMembersHitpoints = setupPartyMembersHitpoints,
    revertAllModifiedHitpoints = revertAllModifiedHitpoints,
    uncapPartyMembersMovementDistances = uncapPartyMembersMovementDistances,
    recapPartyMembersMovementDistances = recapPartyMembersMovementDistances,
    setMaxPartySize = setMaxPartySize,
    setupPlayer = setupPlayer,
    resetPlayers = resetPlayers,
    setIsControllingDirectly = setIsControllingDirectly,
    Settings = Settings,
    Session = Session,
}
