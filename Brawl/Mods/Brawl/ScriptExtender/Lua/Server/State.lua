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
    ActionInterval = 6000,
    FullAuto = false,
    HitpointsMultiplier = 1.0,
    CompanionTactics = "Defense",
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
    Settings.FullAuto = MCM.Get("full_auto")
    Settings.HitpointsMultiplier = MCM.Get("hitpoints_multiplier")
    Settings.CompanionTactics = MCM.Get("companion_tactics")
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
    PartyMembersHitpointsListeners = {},
    ActionResourcesListeners = {},
    TurnBasedListeners = {},
    SpellCastMovementListeners = {},
    FTBLockedIn = {},
    LastClickPosition = {},
    ActiveCombatGroups = {},
    AwaitingTarget = {},
    HealRequested = {},
    HealRequestedTimer = {},
    CountdownTimer = {},
    ToTTimer = nil,
    ToTRoundTimer = nil,
    ModStatusMessageTimer = nil,
    MovementSpeedThresholds = MOVEMENT_SPEED_THRESHOLDS.EASY,
}

-- Persistent state
Ext.Vars.RegisterModVariable(ModuleUUID, "SpellRequirements", {Server = true, Client = false, SyncToClient = false})
Ext.Vars.RegisterModVariable(ModuleUUID, "ModifiedHitpoints", {Server = true, Client = false, SyncToClient = false})
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
    for _, safeAoESpell in ipairs(SAFE_AOE_SPELLS) do
        if spellName == safeAoESpell then
            return true
        end
    end
    return false
end

local function getSpellInfo(spellType, spellName)
    local spell = Ext.Stats.Get(spellName)
    if spell and spell.VerbalIntent == spellType then
        local useCosts = Utils.split(spell.UseCosts, ";")
        local costs = {
            ShortRest = spell.Cooldown == "OncePerShortRest" or spell.Cooldown == "OncePerShortRestPerItem",
            LongRest = spell.Cooldown == "OncePerRest" or spell.Cooldown == "OncePerRestPerItem",
        }
        -- local hitCost = nil -- divine smite only..?
        for _, useCost in ipairs(useCosts) do
            local useCostTable = Utils.split(useCost, ":")
            local useCostLabel = useCostTable[1]
            local useCostAmount = tonumber(useCostTable[#useCostTable])
            if useCostLabel == "SpellSlotsGroup" then
                -- e.g. SpellSlotsGroup:1:1:2
                -- NB: what are the first two numbers?
                costs.SpellSlot = useCostAmount
            else
                costs[useCostLabel] = useCostAmount
            end
        end
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
        local spellInfo = {
            level = spell.Level,
            areaRadius = spell.AreaRadius,
            isSelfOnly = hasTargetCondition(spell.TargetConditions, "Self()"),
            isCharacterOnly = hasTargetCondition(spell.TargetConditions, "Character()"),
            outOfCombatOnly = outOfCombatOnly,
            -- damageType = spell.DamageType,
            isSpell = spell.SpellSchool ~= "None",
            isEvocation = spell.SpellSchool == "Evocation",
            isSafeAoE = isSafeAoESpell(spellName),
            targetRadius = spell.TargetRadius,
            costs = costs,
            type = spellType,
            hasVerbalComponent = hasVerbalComponent,
            -- need to parse this, e.g. DealDamage(LevelMapValue(D8Cantrip),Cold), DealDamage(8d6,Fire), etc
            -- damage = spell.TooltipDamageList,
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

local function getAllSpellsOfType(spellType)
    local allSpellsOfType = {}
    for _, spellName in ipairs(Ext.Stats.GetStats("SpellData")) do
        local spell = Ext.Stats.Get(spellName)
        if spell and spell.VerbalIntent == spellType then
            if spell.ContainerSpells and spell.ContainerSpells ~= "" then
                local containerSpellNames = Utils.split(spell.ContainerSpells, ";")
                for _, containerSpellName in ipairs(containerSpellNames) do
                    allSpellsOfType[containerSpellName] = getSpellInfo(spellType, containerSpellName)
                end
            else
                allSpellsOfType[spellName] = getSpellInfo(spellType, spellName)
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
    if not ARCHETYPE_WEIGHTS[archetype] then
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
        local spellStats = Ext.Stats.Get(name)
        if spellStats then
            local spellType = spellStats.VerbalIntent
            if spellType and Session.SpellTable[spellType] then
                return Session.SpellTable[spellType][name]
            end
        end
    end
    return nil
end

local function hasDirectHeal(uuid, preparedSpells)
    if isSilenced(uuid) then
        return false
    end
    for _, preparedSpell in ipairs(preparedSpells) do
        local spellName = preparedSpell.OriginatorPrototype
        if Session.SpellTable.Healing[spellName] ~= nil and Resources.hasEnoughToCastSpell(uuid, spellName) then
            return true
        end
    end
    return false
end

local function buildSpellTable()
    local spellTable = {}
    for _, spellType in pairs(ALL_SPELL_TYPES) do
        spellTable[spellType] = getAllSpellsOfType(spellType)
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

State = {
    getArchetype = getArchetype,
    setMovementSpeedThresholds = setMovementSpeedThresholds,
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
    setMaxPartySize = setMaxPartySize,
    setupPlayer = setupPlayer,
    resetPlayers = resetPlayers,
    setIsControllingDirectly = setIsControllingDirectly,
    Settings = Settings,
    Session = Session,
}
