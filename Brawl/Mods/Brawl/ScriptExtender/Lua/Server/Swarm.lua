local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump
local getDisplayName = Utils.getDisplayName
local isAliveAndCanFight = Utils.isAliveAndCanFight
local isToT = Utils.isToT

local function setTurnComplete(uuid)
    local entity = Ext.Entity.Get(uuid)
    if entity.TurnBased and not entity.TurnBased.TurnActionsCompleted then
        print(getDisplayName(uuid), "Setting turn complete", uuid)
        entity.TurnBased.HadTurnInCombat = true
        entity.TurnBased.RequestedEndTurn = true
        entity.TurnBased.TurnActionsCompleted = true
        -- entity.TurnBased.CanActInCombat = false
        entity:Replicate("TurnBased")
        State.Session.SwarmTurnComplete[uuid] = true
    end
end

local function unsetTurnComplete(uuid)
    local entity = Ext.Entity.Get(uuid)
    if entity.TurnBased then
        print(getDisplayName(uuid), "Unsetting turn complete", uuid)
        entity.TurnBased.HadTurnInCombat = false
        entity.TurnBased.RequestedEndTurn = false
        entity.TurnBased.TurnActionsCompleted = false
        -- entity.TurnBased.CanActInCombat = false
        entity:Replicate("TurnBased")
        State.Session.SwarmTurnComplete[uuid] = false
    end
end

local function setAllEnemyTurnsComplete()
    print("setAllEnemyTurnsComplete")
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
        local brawlersInLevel = State.Session.Brawlers[level]
        if brawlersInLevel then
            for brawlerUuid, _ in pairs(brawlersInLevel) do
                if Osi.IsPartyMember(brawlerUuid, 1) == 0 then
                    setTurnComplete(brawlerUuid)
                end
            end
        end
    end
end

local function unsetAllEnemyTurnsComplete()
    print("unsetAllEnemyTurnsComplete")
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
        local brawlersInLevel = State.Session.Brawlers[level]
        if brawlersInLevel then
            for brawlerUuid, _ in pairs(brawlersInLevel) do
                if Osi.IsPartyMember(brawlerUuid, 1) == 0 then
                    unsetTurnComplete(brawlerUuid)
                end
            end
        end
    end
end

local function isFrozen(uuid)
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    if modVars.FrozenResources == nil then
        return false
    end
    if not modVars.FrozenResources[uuid] then
        return false
    end
    return true
end

local function checkSwarmTurnComplete()
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
        local brawlersInLevel = State.Session.Brawlers[level]
        if brawlersInLevel then
            for brawlerUuid, _ in pairs(brawlersInLevel) do
                if Osi.IsPartyMember(brawlerUuid, 1) == 0 and not State.Session.SwarmTurnComplete[brawlerUuid] then
                    print("swarm turn not complete for", brawlerUuid, Utils.getDisplayName(brawlerUuid))
                    return false
                end
            end
        end
    end
    return true
end

local function resetSwarmTurnComplete()
    print("resetSwarmTurnComplete")
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
        local brawlersInLevel = State.Session.Brawlers[level]
        if brawlersInLevel then
            for brawlerUuid, _ in pairs(brawlersInLevel) do
                if Osi.IsPartyMember(brawlerUuid, 1) == 0 then
                    print("setting turn complete for", brawlerUuid, Utils.getDisplayName(brawlerUuid))
                    local entity = Ext.Entity.Get(brawlerUuid)
                    _D(entity.TurnBased)
                    if entity and entity.TurnBased and not entity.TurnBased.HadTurnInCombat then
                        setTurnComplete(brawlerUuid)
                    end
                    State.Session.SwarmTurnComplete[brawlerUuid] = false
                end
            end
        end
    end
end

local function completeSwarmTurn(uuid)
    Ext.Timer.WaitFor(Constants.SWARM_TURN_DURATION/2, function ()
        State.Session.SwarmTurnComplete[uuid] = true
        print("checkSwarmTurnComplete", uuid, Utils.getDisplayName(uuid))
        _D(State.Session.SwarmTurnComplete)
        if checkSwarmTurnComplete() then
            resetSwarmTurnComplete()
        end
    end)
end

local function isControlledByDefaultAI(uuid)
    local entity = Ext.Entity.Get(uuid)
    -- do we need to flag an enemy for active status?
    if entity and entity.TurnBased and entity.TurnBased.IsActiveCombatTurn then
        print("entity ACTIVE, using default AI instead...", uuid, Utils.getDisplayName(uuid))
        State.Session.SwarmTurnComplete[uuid] = true
        -- completeSwarmTurn(uuid)
        return true
    end
    return false
end

local function singleCharacterTurn(brawler, brawlerIndex)
    local hostCharacterUuid = Osi.GetHostCharacter()
    debugPrint("singleCharacterTurn", brawler.displayName, brawler.uuid, Utils.canAct(brawler.uuid))
    -- is this ok for non-ToT?
    if isToT() and Osi.IsEnemy(brawler.uuid, hostCharacterUuid) == 0 and not Utils.isPlayerOrAlly(brawler.uuid) then
        Osi.SetRelationTemporaryHostile(brawler.uuid, hostCharacterUuid)
    end
    if State.Session.Players[brawler.uuid] or (isToT() and Mods.ToT.PersistentVars.Scenario and brawler.uuid == Mods.ToT.PersistentVars.Scenario.CombatHelper) or not Utils.canAct(brawler.uuid) then
        debugPrint("don't take turn", brawler.uuid, brawler.displayName)
        -- State.Session.SwarmTurnComplete[brawler.uuid] = true
        return false
    end
    if isControlledByDefaultAI(brawler.uuid) or State.Session.SwarmTurnComplete[brawler.uuid] then
        return false
    end
    debugPrint(brawler.displayName, "AI.pulseAction (bonus)", brawler.uuid, brawlerIndex)
    if State.Session.TBSMActionResourceListeners[brawler.uuid] == nil then
        State.Session.TBSMActionResourceListeners[brawler.uuid] = Ext.Entity.Subscribe("ActionResources", function (entity, _, _)
            Movement.setMovementToMax(entity)
        end, Ext.Entity.Get(brawler.uuid))
    end
    -- Ext.Timer.WaitFor(brawlerIndex*10, function ()
    if not isControlledByDefaultAI(brawler.uuid) and not State.Session.SwarmTurnComplete[brawler.uuid] then
        if not AI.pulseAction(brawler, true) then
            debugPrint(brawler.displayName, "bonus action not found, immediate AI.pulseAction", brawler.uuid)
            AI.pulseAction(brawler)
            completeSwarmTurn(brawler.uuid)
        else
            Ext.Timer.WaitFor(Constants.SWARM_TURN_DURATION/2, function ()
                if not isControlledByDefaultAI(brawler.uuid) and not State.Session.SwarmTurnComplete[brawler.uuid] then
                    debugPrint(brawler.displayName, "AI.pulseAction", brawler.uuid)
                    AI.pulseAction(brawler)
                    completeSwarmTurn(brawler.uuid)
                end
            end)
        end
    end
    -- end)
    return true
end

-- NB: stay in combat, adjust movement speed as needed
--     when there's only 3 or 4 enemies auto-disables
local function startEnemyTurn(canActBeforeDelay)
    debugPrint("startEnemyTurn")
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
        local brawlersInLevel = State.Session.Brawlers[level]
        if brawlersInLevel then
            local brawlerIndex = 0
            for brawlerUuid, brawler in pairs(brawlersInLevel) do
                if canActBeforeDelay[brawlerUuid] ~= false and singleCharacterTurn(brawler, brawlerIndex) then
                    brawlerIndex = brawlerIndex + 1
                end
            end
        end
    end
end

-- local function checkPlayerRejoinCombat(playerUuid)
--     if isAliveAndCanFight(playerUuid) then
--         local playerBrawler = State.getBrawlerByUuid(playerUuid)
--         if not playerBrawler and isToT() then
--             Roster.addBrawler(playerUuid, true)
--             playerBrawler = State.getBrawlerByUuid(playerUuid)
--         end
--         if playerBrawler and Osi.IsInCombat(playerUuid) == 0 then
--             debugPrint("checkPlayerRejoinCombat", playerUuid)
--             local level = Osi.GetRegion(playerUuid)
--             local brawlersInLevel = State.Session.Brawlers[level]
--             if brawlersInLevel then
--                 for brawlerUuid, _ in pairs(brawlersInLevel) do
--                     if Utils.isPugnacious(brawlerUuid, playerUuid) and isAliveAndCanFight(brawlerUuid) and Osi.GetDistanceTo(brawlerUuid, playerUuid) < 20 then
--                         debugPrint("re-entering combat", playerUuid, brawlerUuid, getDisplayName(playerUuid), getDisplayName(brawlerUuid))
--                         -- Osi.EnterCombat(playerUuid, brawlerUuid)
--                         Osi.SetRelationTemporaryHostile(playerUuid, brawlerUuid)
--                         -- NB: alternative method from Focus
--                         -- local combat = Ext.Entity.GetAllEntitiesWithComponent("ServerEnterRequest")[1]
--                         -- combat.ServerEnterRequest.EnterRequests[_C()] = true
--                         -- NB: alternative from Norb
--                         -- Ext.System.ServerCombat.JoinCombat[_C()] = combatEntity
--                         return true
--                     end
--                 end
--             end
--         end
--     end
--     return false
-- end

-- local function checkPlayersRejoinCombat()
--     local players = State.Session.Players
--     if players then
--         for playerUuid, _ in pairs(players) do
--             checkPlayerRejoinCombat(playerUuid)
--         end
--     end
-- end

local function allBrawlersCanAct()
    local brawlersCanAct = {}
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
        local brawlersInLevel = State.Session.Brawlers[level]
        if brawlersInLevel then
            for brawlerUuid, brawler in pairs(brawlersInLevel) do
                brawlersCanAct[brawlerUuid] = Utils.canAct(brawlerUuid)
                -- brawlersCanAct[brawlerUuid] = true
            end
        end
    end
    return brawlersCanAct
end

-- the FIRST enemy to go uses the built-in AI and takes its turn normally, this keeps the turn open
-- all other enemies go at the same time, using the Brawl AI
-- possible for the first enemy's turn to end early, and then it bleeds over into the player turn, but unusual
local function startSwarmTurn()
    local shouldFreezePlayers = {}
    for uuid, _ in pairs(State.Session.Players) do
        shouldFreezePlayers[uuid] = Utils.isToT() or Osi.IsInCombat(uuid) == 1
    end
    State.Session.TurnBasedSwarmModePlayerTurnEnded = {}
    local canActBeforeDelay = allBrawlersCanAct()
    Ext.Timer.WaitFor(2500, function () -- delay to allow new enemies to get scooped up
        if isToT() and Mods.ToT.PersistentVars.Scenario and Mods.ToT.PersistentVars.Scenario.Round ~= nil and not State.Session.TBSMToTSkippedPrepRound then
            State.Session.TBSMToTSkippedPrepRound = true
            print("SKIPPING PREP ROUND...")
            return
        end
        startEnemyTurn(canActBeforeDelay)
    end)
end

local function checkAllPlayersFinishedTurns()
    local players = State.Session.Players
    if players then
        debugDump(State.Session.TurnBasedSwarmModePlayerTurnEnded)
        for playerUuid, _ in pairs(players) do
            local isUncontrolled = Utils.hasLoseControlStatus(playerUuid)
            debugPrint("Checking finished turns", playerUuid, State.Session.TurnBasedSwarmModePlayerTurnEnded[playerUuid], isAliveAndCanFight(playerUuid), isUncontrolled)
            if isAliveAndCanFight(playerUuid) and not isUncontrolled and not State.Session.TurnBasedSwarmModePlayerTurnEnded[playerUuid] then
                return false
            end
        end
        return true
    end
    return nil
end

return {
    setTurnComplete = setTurnComplete,
    unsetTurnComplete = unsetTurnComplete,
    setAllEnemyTurnsComplete = setAllEnemyTurnsComplete,
    unsetAllEnemyTurnsComplete = unsetAllEnemyTurnsComplete,
    startSwarmTurn = startSwarmTurn,
    checkAllPlayersFinishedTurns = checkAllPlayersFinishedTurns,
    startEnemyTurn = startEnemyTurn,
}
