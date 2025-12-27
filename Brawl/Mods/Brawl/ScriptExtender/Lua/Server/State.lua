local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump

-- Settings
local Settings = {
    ModEnabled = true,
    CompanionAIEnabled = true,
    TruePause = true,
    AutoPauseOnDowned = true,
    AutoPauseOnCombatStart = false,
    ActionInterval = 6.0,
    FullAuto = false,
    HitpointsMultiplier = 1.0,
    CompanionTactics = "Balanced",
    DefensiveTacticsMaxDistance = 15,
    CompanionAIMaxSpellLevel = 0,
    HogwildMode = false,
    MaxPartySize = 4,
    TurnBasedSwarmMode = true,
    LeaderboardEnabled = true,
    NoFreezeOnBonusActionsDuringPause = false,
    PlayersGoFirst = false,
    SwarmTurnTimeout = 30.0,
    SwarmChunkSize = 20,
    AutotriggerSwarmModeCompanionAI = false,
    ExcludeEnemyTiers = nil,
}
if MCM then
    Settings.ModEnabled = MCM.Get("mod_enabled")
    Settings.CompanionAIEnabled = MCM.Get("companion_ai_enabled")
    Settings.TruePause = MCM.Get("true_pause")
    Settings.AutoPauseOnDowned = MCM.Get("auto_pause_on_downed")
    Settings.AutoPauseOnCombatStart = MCM.Get("auto_pause_on_combat_start")
    Settings.ActionInterval = MCM.Get("action_interval")
    Settings.FullAuto = MCM.Get("full_auto")
    Settings.HitpointsMultiplier = MCM.Get("hitpoints_multiplier")
    Settings.CompanionTactics = MCM.Get("companion_tactics")
    Settings.DefensiveTacticsMaxDistance = MCM.Get("defensive_tactics_max_distance")
    Settings.CompanionAIMaxSpellLevel = MCM.Get("companion_ai_max_spell_level")
    Settings.HogwildMode = MCM.Get("hogwild_mode")
    Settings.MaxPartySize = MCM.Get("max_party_size")
    Settings.TurnBasedSwarmMode = MCM.Get("turn_based_swarm_mode")
    Settings.LeaderboardEnabled = MCM.Get("leaderboard_enabled")
    Settings.NoFreezeOnBonusActionsDuringPause = MCM.Get("no_freeze_on_bonus_actions_during_pause")
    Settings.PlayersGoFirst = MCM.Get("players_go_first")
    Settings.SwarmTurnTimeout = MCM.Get("swarm_turn_timeout")
    Settings.SwarmChunkSize = MCM.Get("swarm_chunk_size")
    Settings.AutotriggerSwarmModeCompanionAI = MCM.Get("autotrigger_swarm_mode_companion_ai")
    Settings.ExcludeEnemyTiers = MCM.Get("exclude_enemy_tiers")
end

-- Session state
local Session = {
    SpellTable = {},
    SpellTableByName = {},
    Listeners = {},
    Brawlers = {},
    Players = {},
    PulseAddNearbyTimers = {},
    PulseActionTimers = {},
    IsAttackingOrBeingAttackedByPlayer = {},
    ClosestEnemyBrawlers = {},
    PlayerMarkedTarget = {},
    PlayerCurrentTarget = {},
    ActionsInProgress = {},
    PlayerTargetingSpellCast = {},
    IsNextCombatRoundQueued = false,
    MovementQueue = {},
    PartyMembersMovementResourceListeners = {},
    PartyMembersHitpointsListeners = {},
    TurnBasedListeners = {},
    TranslateChangedEventListeners = {},
    SpellCastPrepareEndEventListeners = {},
    FTBLockedIn = {},
    TurnOrderListener = {},
    BoostChangedEventListener = {},
    RefresherCombatHelper = {},
    LastClickPosition = {},
    ActiveCombatGroups = {},
    AwaitingTarget = {},
    RemainingMovement = {},
    HealRequested = {},
    HealRequestedTimer = {},
    CountdownTimer = {},
    ExtraAttacksRemaining = {},
    StoryActionIDs = {},
    TagNameToUuid = {},
    ExcludedFromAI = {},
    ToTTimer = nil,
    ToTRoundAddNearbyTimer = nil,
    ModStatusMessageTimer = nil,
    ActiveMovements = {},
    TurnBasedSwarmModePlayerTurnEnded = {},
    TBSMToTSkippedPrepRound = false,
    SwarmTurnComplete = {},
    ResurrectedPlayer = {},
    SwarmActors = nil,
    ActionSequenceFailsafeTimer = {},
    SwarmTurnActive = nil,
    SwarmBrawlerIndexDelay = {},
    Leaderboard = {},
    LeaderboardUpdateTimer = nil,
    LeaderboardPendingUpdateOnly = nil,
    BrawlerChunks = {},
    CurrentChunkIndex = nil,
    ChunkInProgress = nil,
    CurrentChunkTimer = nil,
    QueuedCompanionAIAction = {},
    CombatRoundTimer = {},
    MovementSpeedThresholds = Constants.MOVEMENT_SPEED_THRESHOLDS.EASY,
    MeanInitiativeRoll = nil,
    SwarmTurnIsBeforePlayer = nil,
    ExcludeEnemyTierIndex = Utils.getTierIndex(Settings.ExcludeEnemyTiers),
    CombatHelper = nil,
}

-- Persistent state
Ext.Vars.RegisterModVariable(ModuleUUID, "SpellRequirements", {Server = true, Client = false, SyncToClient = false})
Ext.Vars.RegisterModVariable(ModuleUUID, "ModifiedHitpoints", {Server = true, Client = false, SyncToClient = false})
Ext.Vars.RegisterModVariable(ModuleUUID, "MovementDistances", {Server = true, Client = false, SyncToClient = false})
Ext.Vars.RegisterModVariable(ModuleUUID, "PartyArchetypes", {Server = true, Client = false, SyncToClient = false})

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
        archetype = M.Osi.GetActiveArchetype(uuid)
    end
    if not Constants.ARCHETYPE_WEIGHTS[archetype] then
        if archetype == nil or archetype == "base" then
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
            archetype = "melee"
        end
    end
    return archetype
end

local function areAnyPlayersTargeting()
    for uuid, _ in pairs(Session.Players) do
        if Session.PlayerTargetingSpellCast[uuid] then
            return true
        end
    end
end

local function checkForDownedOrDeadPlayers()
    local players = Session.Players
    if players then
        for uuid, player in pairs(players) do
            if M.Osi.IsDead(uuid) == 1 or M.Utils.isDowned(uuid) then
                Utils.clearOsirisQueue(uuid)
                Osi.LieOnGround(uuid)
            end
        end
    end
end

local function isInCombat(uuid)
    return M.Osi.IsInCombat(uuid or M.Osi.GetHostCharacter()) == 1
end

local function areAnyPlayersBrawling()
    if Session.Players then
        for playerUuid, player in pairs(Session.Players) do
            local level = M.Osi.GetRegion(playerUuid)
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
        if M.Utils.isPugnacious(brawlerUuid) and brawler.isInBrawl and M.Osi.IsInCombat(brawlerUuid) == 1 then
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

local function isPartyInRealTime()
    if Session.Players then
        for uuid, _ in pairs(Session.Players) do
            if M.Osi.IsInForceTurnBasedMode(uuid) == 1 then
                return false
            end
        end
    end
    return true
end

local function getToTCombatHelper()
    if Utils.isToT() and Mods.ToT.PersistentVars.Scenario then
        return Mods.ToT.PersistentVars.Scenario.CombatHelper
    end
end

local function isToTCombatHelper(uuid)
    return Utils.isToT() and Mods.ToT.PersistentVars.Scenario and uuid == Mods.ToT.PersistentVars.Scenario.CombatHelper
end

local function disableDynamicCombatCamera()
    Ext.ServerNet.BroadcastMessage("DisableDynamicCombatCamera", "")
end

local function hasDirectHeal(uuid, preparedSpells, excludeSelfOnly, bonusActionOnly)
    if M.Utils.isSilenced(uuid) then
        return false
    end
    for _, preparedSpell in ipairs(preparedSpells) do
        local spellName = preparedSpell.OriginatorPrototype
        local spell = Session.SpellTable.Healing[spellName]
        local isUsableHeal = (spell ~= nil) and spell.isDirectHeal
        if isUsableHeal and excludeSelfOnly then
            isUsableHeal = isUsableHeal and not spell.isSelfOnly
        end
        if bonusActionOnly then
            isUsableHeal = isUsableHeal and spell.isBonusAction
        end
        if isUsableHeal then
            if Settings.HogwildMode then
                return true
            elseif M.Resources.hasEnoughToCastSpell(uuid, spellName) then
                return true
            end
        end
    end
    return false
end

local function uncapMovementDistance(entityUuid)
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    if modVars.MovementDistances == nil then
        modVars.MovementDistances = {}
    end
    local movementDistances = modVars.MovementDistances
    if M.Osi.IsCharacter(entityUuid) == 1 and M.Osi.IsDead(entityUuid) == 0 and movementDistances[entityUuid] == nil then
        debugPrint("Uncap movement distance", entityUuid, Constants.UNCAPPED_MOVEMENT_DISTANCE)
        local entity = Ext.Entity.Get(entityUuid)
        if entity and entity.ActionResources and entity.ActionResources.Resources and entity.ActionResources.Resources[Constants.ACTION_RESOURCES.Movement] then
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
            -- _D(movementDistances)
        end
    end
end

local function capMovementDistance(entityUuid)
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    local movementDistances = modVars.MovementDistances
    if movementDistances and movementDistances[entityUuid] ~= nil and M.Osi.IsCharacter(entityUuid) == 1 then
        -- debugPrint("Cap movement distance", entityUuid)
        -- debugDump(movementDistances[entityUuid])
        local entity = Ext.Entity.Get(entityUuid)
        if entity and entity.ActionResources and entity.ActionResources.Resources and entity.ActionResources.Resources[Constants.ACTION_RESOURCES.Movement] then
            if movementDistances[entityUuid] == nil then
                movementDistances[entityUuid] = {}
            end
            movementDistances[entityUuid].updating = true
            modVars.MovementDistances = movementDistances
            if movementDistances[entityUuid] and movementDistances[entityUuid].originalMaxAmount then
                entity.ActionResources.Resources[Constants.ACTION_RESOURCES.Movement][1].MaxAmount = movementDistances[entityUuid].originalMaxAmount
                entity.ActionResources.Resources[Constants.ACTION_RESOURCES.Movement][1].Amount = movementDistances[entityUuid].originalMaxAmount
                entity:Replicate("ActionResources")
            end
            movementDistances[entityUuid] = nil
            modVars.MovementDistances = movementDistances
            -- debugPrint("Capped distance:", entityUuid, M.Utils.getDisplayName(entityUuid), Movement.getMovementDistanceMaxAmount(entity))
        end
    end
end

local function revertHitpoints(entityUuid)
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    local modifiedHitpoints = modVars.ModifiedHitpoints
    if modifiedHitpoints and modifiedHitpoints[entityUuid] ~= nil and M.Osi.IsCharacter(entityUuid) == 1 then
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
        -- debugPrint("Reverted hitpoints:", entityUuid, M.Utils.getDisplayName(entityUuid), entity.Health.MaxHp, entity.Health.Hp)
    end
end

local function modifyHitpoints(entityUuid)
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    if modVars.ModifiedHitpoints == nil then
        modVars.ModifiedHitpoints = {}
    end
    local modifiedHitpoints = modVars.ModifiedHitpoints
    if M.Osi.IsCharacter(entityUuid) == 1 and M.Osi.IsDead(entityUuid) == 0 and modifiedHitpoints[entityUuid] == nil then
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
        -- debugPrint("Modified hitpoints:", entityUuid, M.Utils.getDisplayName(entityUuid), originalMaxHp, originalHp, entity.Health.MaxHp, entity.Health.Hp)
    end
end

local function uncapPartyMembersMovementDistances()
    for _, partyMember in ipairs(Osi.DB_PartyMembers:Get(nil)) do
        local partyMemberUuid = M.Osi.GetUUID(partyMember[1])
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
        local partyMemberUuid = M.Osi.GetUUID(partyMember[1])
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
    local uuid = M.Osi.GetUUID(guid)
    if uuid then
        if not Session.Players then
            Session.Players = {}
        end
        Session.Players[uuid] = {
            uuid = uuid,
            guid = guid,
            displayName = Utils.getDisplayName(uuid),
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

local function removeBoostPlayerInitiatives()
    local players = Session.Players
    if players then
        for uuid, _ in pairs(players) do
            Osi.RemoveBoosts(uuid, Constants.PLAYER_INITIATIVE_BOOST, 0, "BRAWL_TURN_BASED_SWARM_INITIATIVE_BOOST", uuid)
        end
    end
end

local function boostPlayerInitiative(uuid)
    debugPrint("Boosting player initiative", uuid)
    Osi.AddBoosts(uuid, Constants.PLAYER_INITIATIVE_BOOST, "BRAWL_TURN_BASED_SWARM_INITIATIVE_BOOST", uuid)
end

local function removeBoostAllyInitiative(uuid)
    debugPrint("Removing boost ally initiative", uuid)
    Osi.RemoveBoosts(uuid, Constants.ALLY_INITIATIVE_BOOST, 0, "BRAWL_TURN_BASED_SWARM_INITIATIVE_BOOST", uuid)
end

local function boostAllyInitiative(uuid)
    debugPrint("Boosting ally initiative", uuid)
    Osi.AddBoosts(uuid, Constants.ALLY_INITIATIVE_BOOST, "BRAWL_TURN_BASED_SWARM_INITIATIVE_BOOST", uuid)
end

local function boostPlayerInitiatives()
    -- removeBoostPlayerInitiatives()
    local players = Session.Players
    -- Players always go first, should this be a setting instead or...?
    if players then
        for playerUuid, _ in pairs(players) do
            boostPlayerInitiative(playerUuid)
        end
    end
end

local function endBrawls()
    print("END BRAWLS")
    local hostCharacter = M.Osi.GetHostCharacter()
    if hostCharacter then
        local level = M.Osi.GetRegion(hostCharacter)
        if level then
            print("ending brawl in", level)
            Roster.endBrawl(level)
        end
    end
end

return {
    getArchetype = getArchetype,
    areAnyPlayersTargeting = areAnyPlayersTargeting,
    checkForDownedOrDeadPlayers = checkForDownedOrDeadPlayers,
    isInCombat = isInCombat,
    areAnyPlayersBrawling = areAnyPlayersBrawling,
    getNumEnemiesRemaining = getNumEnemiesRemaining,
    isPlayerControllingDirectly = isPlayerControllingDirectly,
    getPlayerByUserId = getPlayerByUserId,
    getToTCombatHelper = getToTCombatHelper,
    isToTCombatHelper = isToTCombatHelper,
    disableDynamicCombatCamera = disableDynamicCombatCamera,
    isPartyInRealTime = isPartyInRealTime,
    hasDirectHeal = hasDirectHeal,
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
    removeBoostPlayerInitiatives = removeBoostPlayerInitiatives,
    boostPlayerInitiatives = boostPlayerInitiatives,
    boostPlayerInitiative = boostPlayerInitiative,
    removeBoostAllyInitiative = removeBoostAllyInitiative,
    boostAllyInitiative = boostAllyInitiative,
    endBrawls = endBrawls,
    Settings = Settings,
    Session = Session,
}
