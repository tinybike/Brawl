local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump

local function getNumExtraAttacks(entityUuid)
    if M.Osi.HasPassive(entityUuid, "ExtraAttack_3") == 1 or M.Osi.HasPassive(entityUuid, "WildStrike_3") == 1 or M.Osi.HasPassive(entityUuid, "Slayer_ExtraAttack_3") == 1 then
        return 3
    elseif M.Osi.HasPassive(entityUuid, "ExtraAttack_2") == 1 or M.Osi.HasPassive(entityUuid, "WildStrike_2") == 1 or M.Osi.HasPassive(entityUuid, "Slayer_ExtraAttack_2") == 1 then
        return 2
    elseif M.Osi.HasPassive(entityUuid, "ExtraAttack") == 1 or M.Osi.HasPassive(entityUuid, "WildStrike") == 1 or M.Osi.HasPassive(entityUuid, "Slayer_ExtraAttack") == 1 then
        return 1
    end
    return 0
end

local function addBrawler(entityUuid, isInBrawl, replaceExistingBrawler)
    if entityUuid ~= nil then
        local level = M.Osi.GetRegion(entityUuid)
        local okToAdd = false
        if replaceExistingBrawler then
            okToAdd = level and State.Session.Brawlers[level] ~= nil and M.Utils.isAliveAndCanFight(entityUuid)
        else
            okToAdd = level and State.Session.Brawlers[level] ~= nil and State.Session.Brawlers[level][entityUuid] == nil and M.Utils.isAliveAndCanFight(entityUuid)
        end
        if State.Settings.TurnBasedSwarmMode and M.Utils.isToT() and Mods.ToT.PersistentVars.Scenario and entityUuid == Mods.ToT.PersistentVars.Scenario.CombatHelper then
            okToAdd = true
        end
        if okToAdd then
            local displayName = M.Utils.getDisplayName(entityUuid)
            local brawler = {
                uuid = entityUuid,
                displayName = displayName,
                combatGuid = M.Osi.CombatGetGuidFor(entityUuid),
                combatGroupId = M.Osi.GetCombatGroupID(entityUuid),
                isInBrawl = isInBrawl,
                isPaused = M.Osi.IsInForceTurnBasedMode(entityUuid) == 1,
                archetype = State.getArchetype(entityUuid),
                numExtraAttacks = getNumExtraAttacks(entityUuid),
                actionInterval = TurnOrder.calculateActionInterval(TurnOrder.getInitiativeRoll(entityUuid)),
                auras = Spells.getAuras(entityUuid),
            }
            local entity = Ext.Entity.Get(entityUuid)
            local existingBrawler = State.Session.Brawlers[level][entityUuid]
            if existingBrawler and existingBrawler.actionResources then
                brawler.actionResources = existingBrawler.actionResources
            else
                -- does this work for entities that get pulled out of the brawl and then re-entered?
                brawler.actionResources = {}
                for _, resourceType in ipairs(Constants.PER_TURN_ACTION_RESOURCES) do
                    brawler.actionResources[resourceType] = {amount = M.Resources.getActionResourceAmount(entity, resourceType), refillQueue = {}}
                end
                brawler.actionResources.listener = Ext.Entity.Subscribe("ActionResources", Resources.actionResourcesCallback, entity)
            end
            if State.getArchetype(entityUuid) == "barbarian" then
                brawler.rage = Spells.getRageAbility(entityUuid)
                debugPrint(displayName, "barbarian archetype, setting rage", brawler.rage)
            end
            debugPrint(displayName, "Adding Brawler", entityUuid, brawler.actionInterval)
            local modVars = Ext.Vars.GetModVariables(ModuleUUID)
            modVars.ModifiedHitpoints = modVars.ModifiedHitpoints or {}
            State.revertHitpoints(entityUuid)
            State.modifyHitpoints(entityUuid)
            Osi.SetCanJoinCombat(entityUuid, 1)
            if State.Settings.TurnBasedSwarmMode then
                State.Session.Brawlers[level][entityUuid] = brawler
                if M.Osi.IsPartyMember(entityUuid, 1) ~= 1 then
                    State.Session.SwarmTurnComplete[entityUuid] = false
                    Osi.PROC_SelfHealing_Disable(entityUuid)
                elseif State.Session.TurnBasedSwarmModePlayerTurnEnded[entityUuid] == nil then
                    State.Session.TurnBasedSwarmModePlayerTurnEnded[entityUuid] = M.Utils.isPlayerTurnEnded(entityUuid)
                end
            else
                if Osi.IsPlayer(entityUuid) == 0 then
                    -- thank u lunisole/ghostboats
                    Osi.PROC_SelfHealing_Disable(entityUuid)
                end
                State.Session.Brawlers[level][entityUuid] = brawler
                if M.Osi.IsInForceTurnBasedMode(M.Osi.GetHostCharacter()) == 0 then
                    if State.Session.PulseActionTimers[entityUuid] == nil then
                        RT.Timers.startPulseAction(brawler, Constants.INITIAL_PULSE_ACTION_DELAY)
                    end
                else
                    Utils.clearOsirisQueue(entityUuid)
                    RT.Timers.stopPulseAction(brawler)
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
            for _, resourceType in ipairs(Constants.PER_TURN_ACTION_RESOURCES) do
                local actionResources = brawlersInLevel[entityUuid].actionResources
                if actionResources then
                    if actionResources[resourceType] then
                        if actionResources[resourceType].refillQueue then
                            for _, actionResourceTimer in ipairs(actionResources[resourceType].refillQueue) do
                                Ext.Timer.Cancel(actionResourceTimer)
                            end
                        end
                    end
                    if actionResources.listener then
                        Ext.Entity.Unsubscribe(actionResources.listener)
                    end
                end
            end
            RT.Timers.stopPulseAction(brawlersInLevel[entityUuid])
            brawlersInLevel[entityUuid] = nil
        end
        Osi.SetCanJoinCombat(entityUuid, 1)
        if M.Osi.IsPartyMember(entityUuid, 1) == 0 then
            State.revertHitpoints(entityUuid)
        else
            State.Session.PlayerCurrentTarget[entityUuid] = nil
            State.Session.PlayerMarkedTarget[entityUuid] = nil
            State.Session.IsAttackingOrBeingAttackedByPlayer[entityUuid] = nil
        end
        if State.Session.SwarmTurnComplete[entityUuid] ~= nil then
            State.Session.SwarmTurnComplete[entityUuid] = nil
        end
        if State.Session.ResurrectedPlayer[entityUuid] ~= nil then
            State.Session.ResurrectedPlayer[entityUuid] = nil
        end
    end
end

local function addCombatParticipantsToBrawlers()
    local combatEntity = Utils.getCombatEntity()
    if combatEntity and combatEntity.CombatState and combatEntity.CombatState.Participants then
        for _, participant in ipairs(combatEntity.CombatState.Participants) do
            debugPrint(M.Utils.getDisplayName(participant.Uuid.EntityUuid), "adding to brawlers")
            addBrawler(participant.Uuid.EntityUuid, true)
        end
    end
end

local function endBrawl(level)
    debugPrint("endBrawl", level)
    local brawlersInLevel = State.Session.Brawlers[level]
    if brawlersInLevel then
        for brawlerUuid, brawler in pairs(brawlersInLevel) do
            local combatGuid = M.Osi.CombatGetGuidFor(brawlerUuid)
            removeBrawler(level, brawlerUuid)
            if combatGuid then
                Osi.EndCombat(combatGuid)
            end
        end
        debugDump(brawlersInLevel)
    end
    if State.Session.CombatHelper then
        Utils.remove(State.Session.CombatHelper)
        State.Session.CombatHelper = nil
    end
    Movement.resetPlayersMovementSpeed()
    State.Session.ActiveCombatGroups = {}
    State.Session.Brawlers[level] = {}
    State.Session.StoryActionIDs = {}
    State.Session.SwarmTurnComplete = {}
    if State.Settings.TurnBasedSwarmMode then
        Swarm.cancelTimers()
    end
end

local function getBrawlerByUuid(uuid)
    local level = M.Osi.GetRegion(uuid)
    if level and State.Session.Brawlers[level] then
        return State.Session.Brawlers[level][uuid]
    end
    return nil
end

local function getBrawlerByName(name)
    local hostCharacter = M.Osi.GetHostCharacter()
    if hostCharacter then
        local level = M.Osi.GetRegion(hostCharacter)
        if level and State.Session.Brawlers then
            local brawlersInLevel = State.Session.Brawlers[level]
            if brawlersInLevel then
                for uuid, brawler in pairs(brawlersInLevel) do
                    if brawler.displayName == name then
                        return brawler
                    end
                end
            end
        end
    end
end

local function getBrawlersSortedByDistance(entityUuid)
    local brawlersSortedByDistance = {}
    local level = M.Osi.GetRegion(entityUuid)
    local brawlersInLevel = State.Session.Brawlers[level]
    if brawlersInLevel then
        for brawlerUuid, brawler in pairs(brawlersInLevel) do
            if M.Utils.isOnSameLevel(brawlerUuid, entityUuid) and M.Utils.isAliveAndCanFight(brawlerUuid) then
                table.insert(brawlersSortedByDistance, {brawlerUuid, M.Osi.GetDistanceTo(entityUuid, brawlerUuid)})
            end
        end
        table.sort(brawlersSortedByDistance, function (a, b) return a[2] < b[2] end)
    end
    return brawlersSortedByDistance
end

local function addNearbyToBrawlers(entityUuid, nearbyRadius, combatGuid, replaceExistingBrawler)
    local nearby = M.Utils.getNearby(entityUuid, nearbyRadius)
    for _, uuid in ipairs(nearby) do
        if combatGuid == nil or M.Osi.CombatGetGuidFor(uuid) == combatGuid then
            addBrawler(uuid, true, replaceExistingBrawler)
        else
            addBrawler(uuid, false, replaceExistingBrawler)
        end
    end
end

local function addNearbyEnemiesToBrawlers(entityUuid, nearbyRadius)
    local nearby = M.Utils.getNearby(entityUuid, nearbyRadius)
    for _, uuid in ipairs(nearby) do
        if M.Utils.isPugnacious(uuid) then
            addBrawler(uuid)
        end
    end
end

local function addPlayersInEnterCombatRangeToBrawlers(brawlerUuid)
    local players = State.Session.Players
    for playerUuid, _ in pairs(players) do
        local distanceTo = M.Osi.GetDistanceTo(brawlerUuid, playerUuid)
        if distanceTo ~= nil and distanceTo < Constants.ENTER_COMBAT_RANGE then
            addBrawler(playerUuid)
        end
    end
end

local function disableLockedOnTarget(uuid)
    local level = M.Osi.GetRegion(uuid)
    if level and M.Utils.isAliveAndCanFight(uuid) then
        local brawlersInLevel = State.Session.Brawlers[level]
        if brawlersInLevel[uuid] then
            brawlersInLevel[uuid].lockedOnTarget = false
        end
    end
end

local function checkForEndOfBrawl(level)
    local numEnemiesRemaining = M.State.getNumEnemiesRemaining(level)
    print("Number of enemies remaining:", numEnemiesRemaining)
    if numEnemiesRemaining == 0 then
        endBrawl(level)
    end
end

local function initBrawlers(level)
    State.Session.Brawlers[level] = {}
    local players = State.Session.Players
    for playerUuid, player in pairs(players) do
        if not State.Settings.TurnBasedSwarmMode and player.isControllingDirectly then
            RT.Timers.startPulseAddNearby(playerUuid)
        end
        if Osi.IsInCombat(playerUuid) == 1 then
            Listeners.onCombatStarted(M.Osi.CombatGetGuidFor(playerUuid))
            break
        end
    end
end

local function getBrawlers()
    if not State.Session.Brawlers then
        return {}
    end
    local region = M.Utils.getCurrentRegion()
    if not State.Session.Brawlers[region] then
        return {}
    end
    return State.Session.Brawlers[region]
end

local function setExcludedFromAI(uuid, isExcluded)
    State.Session.ExcludedFromAI[uuid] = isExcluded
end

local function isExcludedFromAI(uuid)
    return State.Session.ExcludedFromAI[uuid]
end

return {
    getBrawlerByUuid = getBrawlerByUuid,
    getBrawlerByName = getBrawlerByName,
    addBrawler = addBrawler,
    removeBrawler = removeBrawler,
    addCombatParticipantsToBrawlers = addCombatParticipantsToBrawlers,
    endBrawl = endBrawl,
    getBrawlersSortedByDistance = getBrawlersSortedByDistance,
    addNearbyToBrawlers = addNearbyToBrawlers,
    addNearbyEnemiesToBrawlers = addNearbyEnemiesToBrawlers,
    addPlayersInEnterCombatRangeToBrawlers = addPlayersInEnterCombatRangeToBrawlers,
    disableLockedOnTarget = disableLockedOnTarget,
    checkForEndOfBrawl = checkForEndOfBrawl,
    initBrawlers = initBrawlers,
    getBrawlers = getBrawlers,
    setExcludedFromAI = setExcludedFromAI,
    isExcludedFromAI = isExcludedFromAI,
}
