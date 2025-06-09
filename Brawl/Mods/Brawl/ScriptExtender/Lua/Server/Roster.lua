-- local Constants = require("Server/Constants.lua")
-- local Utils = require("Server/Utils.lua")
-- local State = require("Server/State.lua")
-- local Movement = require("Server/Movement.lua")
-- local Listeners = require("Server/Listeners.lua")

local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump
local getDisplayName = Utils.getDisplayName
local isAliveAndCanFight = Utils.isAliveAndCanFight

local function getNumExtraAttacks(entityUuid)
    if Osi.HasPassive(entityUuid, "ExtraAttack_3") == 1 or Osi.HasPassive(entityUuid, "WildStrike_3") == 1 or Osi.HasPassive(entityUuid, "Slayer_ExtraAttack_3") == 1 then
        return 3
    elseif Osi.HasPassive(entityUuid, "ExtraAttack_2") == 1 or Osi.HasPassive(entityUuid, "WildStrike_2") == 1 or Osi.HasPassive(entityUuid, "Slayer_ExtraAttack_2") == 1 then
        return 2
    elseif Osi.HasPassive(entityUuid, "ExtraAttack") == 1 or Osi.HasPassive(entityUuid, "WildStrike") == 1 or Osi.HasPassive(entityUuid, "Slayer_ExtraAttack") == 1 then
        return 1
    end
    return 0
end

local function calculateActionInterval(initiative)
    local r = Constants.ACTION_INTERVAL_RESCALING
    local scale = 1 + r - 4*r*initiative/(2*initiative + State.Settings.InitiativeDie + 1)
    return math.max(Constants.MINIMUM_ACTION_INTERVAL, math.floor(1000*State.Settings.ActionInterval*scale + 0.5))
end

-- NB: is there a way to look up the initative die instead of defining it in the mod...?
local function rollForInitiative(uuid)
    local initiative = math.random(1, State.Settings.InitiativeDie)
    local entity = Ext.Entity.Get(uuid)
    if entity and entity.Stats and entity.Stats.InitiativeBonus ~= nil then
        initiative = initiative + entity.Stats.InitiativeBonus
    end
    return initiative
end

-- local function getRageAbility(entityUuid)
--     local preparedSpells = Ext.Entity.Get(entityUuid).SpellBookPrepares.PreparedSpells
--     for _, preparedSpell in ipairs(preparedSpells) do
--         if preparedSpell.OriginatorPrototype == "Shout_Rage" or preparedSpell.OriginatorPrototype == "Shout_Rage_Frenzy" or preparedSpell.OriginatorPrototype == "Shout_Rage_Giant" or preparedSpell.OriginatorPrototype == "Shout_Rage_WildMagic" then
--             return preparedSpell.OriginatorPrototype
--         end
--     end
--     return nil
-- end

-- NB: need to account for summons here too! adjust their initiatives etc
local function checkAllPlayersFinishedTurns()
    local players = State.Session.Players
    if players then
        debugDump(State.Session.TurnBasedSwarmModePlayerTurnEnded)
        for playerUuid, _ in pairs(players) do
            if not State.Session.TurnBasedSwarmModePlayerTurnEnded[playerUuid] then
                return false
            end
        end
        return true
    end
    return nil
end

local function allSetCanJoinCombat(canJoinCombat, shouldTakeAction)
    debugPrint("allSetCanJoinCombat", canJoinCombat, shouldTakeAction)
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
        local brawlersInLevel = State.Session.Brawlers[level]
        if brawlersInLevel then
            for brawlerUuid, brawler in pairs(brawlersInLevel) do
                Osi.SetCanJoinCombat(brawlerUuid, canJoinCombat)
                if shouldTakeAction and Osi.IsPartyMember(brawlerUuid, 1) == 0 then
                    debugPrint("AI.pulseAction once", brawler.uuid, brawler.displayName)
                    AI.pulseAction(brawler)
                    Ext.Timer.WaitFor(3000, function ()
                        AI.pulseAction(brawler, true)
                    end)
                end
            end
        end
    end
end

local function addBrawler(entityUuid, isInBrawl, replaceExistingBrawler)
    if entityUuid ~= nil then
        local level = Osi.GetRegion(entityUuid)
        local okToAdd = false
        if replaceExistingBrawler then
            okToAdd = level and State.Session.Brawlers[level] ~= nil and isAliveAndCanFight(entityUuid)
        else
            okToAdd = level and State.Session.Brawlers[level] ~= nil and State.Session.Brawlers[level][entityUuid] == nil and isAliveAndCanFight(entityUuid)
        end
        if okToAdd then
            local displayName = getDisplayName(entityUuid)
            local brawler = {
                uuid = entityUuid,
                displayName = displayName,
                combatGuid = Osi.CombatGetGuidFor(entityUuid),
                combatGroupId = Osi.GetCombatGroupID(entityUuid),
                isInBrawl = isInBrawl,
                isPaused = Osi.IsInForceTurnBasedMode(entityUuid) == 1,
                archetype = State.getArchetype(entityUuid),
                numExtraAttacks = getNumExtraAttacks(entityUuid),
                actionInterval = calculateActionInterval(rollForInitiative(entityUuid)),
            }
            -- if State.getArchetype(entityUuid) == "barbarian" then
            --     brawler.rage = getRageAbility(entityUuid)
            -- end
            debugPrint("Adding Brawler", entityUuid, displayName, brawler.actionInterval)
            local modVars = Ext.Vars.GetModVariables(ModuleUUID)
            modVars.ModifiedHitpoints = modVars.ModifiedHitpoints or {}
            State.revertHitpoints(entityUuid)
            State.modifyHitpoints(entityUuid)
            -- If in turn-based swarm mode, then during the player's turn, SetCanJoinCombat=1 for everyone
            -- and during the enemy turn SetCanJoinCombat=0 for everyone.
            -- There are no circumstances where the settings should be different for players vs enemies, BUT
            -- the trigger to change the setting should be the players' turns start/enemy turns starting.
            -- Players must be LOCKED during enemy turns to avoid RT combat!
            -- All players should be set to have identical initiatives for this.
            -- Pause/True Pause should NOT do anything in this mode.
            -- Maybe just have players always go first?
            if State.Settings.TurnBasedSwarmMode then
                State.Session.Brawlers[level][entityUuid] = brawler
                if Osi.IsPlayer(entityUuid) == 0 then
                    Osi.PROC_SelfHealing_Disable(entityUuid)
                end
            else
                if Osi.IsPlayer(entityUuid) == 0 then
                    -- brawler.originalCanJoinCombat = Osi.CanJoinCombat(entityUuid)
                    Osi.SetCanJoinCombat(entityUuid, 0)
                    -- thank u lunisole/ghostboats
                    Osi.PROC_SelfHealing_Disable(entityUuid)
                elseif State.Session.Players[entityUuid] then
                    -- brawler.originalCanJoinCombat = 1
                    Movement.setPlayerRunToSprint(entityUuid)
                    Osi.SetCanJoinCombat(entityUuid, 0)
                end
                State.Session.Brawlers[level][entityUuid] = brawler
                -- if isInBrawl and Osi.IsInForceTurnBasedMode(Osi.GetHostCharacter()) == 0 then
                if Osi.IsInForceTurnBasedMode(Osi.GetHostCharacter()) == 0 then
                    if State.Session.PulseActionTimers[entityUuid] == nil then
                        startPulseAction(brawler)
                    end
                    if State.Session.BrawlFizzler[level] == nil then
                        startBrawlFizzler(level)
                    end
                else
                    debugPrint("ADDING TO ROSTER DURING FTB...")
                    Utils.clearOsirisQueue(entityUuid)
                    stopPulseAction(brawler)
                    Osi.ForceTurnBasedMode(entityUuid, 1)
                    if not State.Session.Players[entityUuid] then
                        brawler.isPaused = true
                        if State.Settings.TruePause then
                            Pause.startTruePause(entityUuid)
                            Pause.lock(Ext.Entity.Get(entityUuid))
                        end
                    end
                end
            end
        end
    end
end

local function removeBrawler(level, entityUuid)
    local combatGuid = nil
    local brawlersInLevel = State.Session.Brawlers[level]
    if brawlersInLevel then
        for brawlerUuid, brawler in pairs(brawlersInLevel) do
            if brawler.targetUuid == entityUuid then
                brawler.targetUuid = nil
                brawler.lockedOnTarget = nil
                Utils.clearOsirisQueue(brawlerUuid)
            end
        end
        if brawlersInLevel[entityUuid] then
            stopPulseAction(brawlersInLevel[entityUuid])
            brawlersInLevel[entityUuid] = nil
        end
        Osi.SetCanJoinCombat(entityUuid, 1)
        if Osi.IsPartyMember(entityUuid, 1) == 0 then
            State.revertHitpoints(entityUuid)
        else
            State.Session.PlayerCurrentTarget[entityUuid] = nil
            State.Session.PlayerMarkedTarget[entityUuid] = nil
            State.Session.IsAttackingOrBeingAttackedByPlayer[entityUuid] = nil
        end
    end
end

local function endBrawl(level)
    debugPrint("endBrawl", level)
    local brawlersInLevel = State.Session.Brawlers[level]
    if brawlersInLevel then
        for brawlerUuid, brawler in pairs(brawlersInLevel) do
            removeBrawler(level, brawlerUuid)
        end
        debugDump(brawlersInLevel)
    end
    Movement.resetPlayersMovementSpeed()
    State.Session.ActiveCombatGroups = {}
    State.Session.Brawlers[level] = {}
    -- stopPulseReposition(level)
    stopBrawlFizzler(level)
end

local function addNearbyToBrawlers(entityUuid, nearbyRadius, combatGuid, replaceExistingBrawler)
    local nearby = Utils.getNearby(entityUuid, nearbyRadius)
    for _, uuid in ipairs(nearby) do
        if combatGuid == nil or Osi.CombatGetGuidFor(uuid) == combatGuid then
            addBrawler(uuid, true, replaceExistingBrawler)
        else
            addBrawler(uuid, false, replaceExistingBrawler)
        end
    end
end

local function addNearbyEnemiesToBrawlers(entityUuid, nearbyRadius)
    local nearby = Utils.getNearby(entityUuid, nearbyRadius)
    for _, uuid in ipairs(nearby) do
        if Utils.isPugnacious(uuid) then
            addBrawler(uuid)
        end
    end
end

local function addPlayersInEnterCombatRangeToBrawlers(brawlerUuid)
    local players = State.Session.Players
    for playerUuid, _ in pairs(players) do
        local distanceTo = Osi.GetDistanceTo(brawlerUuid, playerUuid)
        if distanceTo ~= nil and distanceTo < Constants.ENTER_COMBAT_RANGE then
            addBrawler(playerUuid)
        end
    end
end

local function disableLockedOnTarget(uuid)
    local level = Osi.GetRegion(uuid)
    if level and isAliveAndCanFight(uuid) then
        local brawlersInLevel = State.Session.Brawlers[level]
        if brawlersInLevel[uuid] then
            brawlersInLevel[uuid].lockedOnTarget = false
        end
    end
end

local function checkForEndOfBrawl(level)
    local numEnemiesRemaining = State.getNumEnemiesRemaining(level)
    debugPrint("Number of enemies remaining:", numEnemiesRemaining)
    if numEnemiesRemaining == 0 then
        endBrawl(level)
    end
end

local function initBrawlers(level)
    State.Session.Brawlers[level] = {}
    local players = State.Session.Players
    for playerUuid, player in pairs(players) do
        if player.isControllingDirectly then
            startPulseAddNearby(playerUuid)
        end
        if Osi.IsInCombat(playerUuid) == 1 then
            Listeners.onCombatStarted(Osi.CombatGetGuidFor(playerUuid))
            break
        end
    end
    startPulseReposition(level)
end

return {
    addBrawler = addBrawler,
    removeBrawler = removeBrawler,
    endBrawl = endBrawl,
    addNearbyToBrawlers = addNearbyToBrawlers,
    addNearbyEnemiesToBrawlers = addNearbyEnemiesToBrawlers,
    addPlayersInEnterCombatRangeToBrawlers = addPlayersInEnterCombatRangeToBrawlers,
    disableLockedOnTarget = disableLockedOnTarget,
    checkForEndOfBrawl = checkForEndOfBrawl,
    initBrawlers = initBrawlers,
    allSetCanJoinCombat = allSetCanJoinCombat,
    checkAllPlayersFinishedTurns = checkAllPlayersFinishedTurns,
}
