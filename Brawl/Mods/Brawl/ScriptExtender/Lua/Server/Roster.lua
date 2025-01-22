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
            debugPrint("Adding Brawler", entityUuid, displayName)
            local brawler = {
                uuid = entityUuid,
                displayName = displayName,
                combatGuid = Osi.CombatGetGuidFor(entityUuid),
                combatGroupId = Osi.GetCombatGroupID(entityUuid),
                isInBrawl = isInBrawl,
                isPaused = Osi.IsInForceTurnBasedMode(entityUuid) == 1,
                archetype = State.getArchetype(entityUuid),
            }
            local modVars = Ext.Vars.GetModVariables(ModuleUUID)
            modVars.ModifiedHitpoints = modVars.ModifiedHitpoints or {}
            State.revertHitpoints(entityUuid)
            State.modifyHitpoints(entityUuid)
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
            if isInBrawl and State.Session.PulseActionTimers[entityUuid] == nil and Osi.IsInForceTurnBasedMode(Osi.GetHostCharacter()) == 0 then
                startPulseAction(brawler)
            end
        end
    end
end

local function removeBrawler(level, entityUuid)
    local combatGuid = nil
    if State.Session.Brawlers[level] ~= nil then
        for brawlerUuid, brawler in pairs(State.Session.Brawlers[level]) do
            if brawler.targetUuid == entityUuid then
                brawler.targetUuid = nil
                brawler.lockedOnTarget = nil
                clearOsirisQueue(brawlerUuid)
            end
        end
        if State.Session.Brawlers[level][entityUuid] then
            stopPulseAction(State.Session.Brawlers[level][entityUuid])
            State.Session.Brawlers[level][entityUuid] = nil
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
    if State.Session.Brawlers[level] then
        for brawlerUuid, brawler in pairs(State.Session.Brawlers[level]) do
            removeBrawler(level, brawlerUuid)
        end
        debugPrint("Ended brawl")
        debugDump(State.Session.Brawlers[level])
    end
    for playerUuid, player in pairs(State.Session.Players) do
        if player.isPaused then
            Osi.ForceTurnBasedMode(playerUuid, 0)
            break
        end
    end
    Movement.resetPlayersMovementSpeed()
    State.Session.ActiveCombatGroups = {}
    State.Session.Brawlers[level] = {}
    stopBrawlFizzler(level)
end

local function addNearbyToBrawlers(entityUuid, nearbyRadius, combatGuid, replaceExistingBrawler)
    for _, nearby in ipairs(getNearby(entityUuid, nearbyRadius)) do
        if nearby.Entity.IsCharacter and isAliveAndCanFight(nearby.Guid) then
            if combatGuid == nil or Osi.CombatGetGuidFor(nearby.Guid) == combatGuid then
                addBrawler(nearby.Guid, true, replaceExistingBrawler)
            else
                addBrawler(nearby.Guid, false, replaceExistingBrawler)
            end
        end
    end
end

local function addNearbyEnemiesToBrawlers(entityUuid, nearbyRadius)
    for _, nearby in ipairs(getNearby(entityUuid, nearbyRadius)) do
        if nearby.Entity.IsCharacter and isAliveAndCanFight(nearby.Guid) and isPugnacious(nearby.Guid) then
            addBrawler(nearby.Guid, false, false)
        end
    end
end

local function addPlayersInEnterCombatRangeToBrawlers(brawlerUuid)
    for playerUuid, _ in pairs(State.Session.Players) do
        local distanceTo = Osi.GetDistanceTo(brawlerUuid, playerUuid)
        if distanceTo ~= nil and distanceTo < ENTER_COMBAT_RANGE then
            addBrawler(playerUuid)
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
    for playerUuid, player in pairs(State.Session.Players) do
        if player.isControllingDirectly then
            startPulseAddNearby(playerUuid)
        end
        if Osi.IsInCombat(playerUuid) == 1 then
            onCombatStarted(Osi.CombatGetGuidFor(playerUuid))
            break
        end
    end
    startPulseReposition(level)
end

Roster = {
    addBrawler = addBrawler,
    removeBrawler = removeBrawler,
    endBrawl = endBrawl,
    addNearbyToBrawlers = addNearbyToBrawlers,
    addNearbyEnemiesToBrawlers = addNearbyEnemiesToBrawlers,
    addPlayersInEnterCombatRangeToBrawlers = addPlayersInEnterCombatRangeToBrawlers,
    checkForEndOfBrawl = checkForEndOfBrawl,
    initBrawlers = initBrawlers,
}
