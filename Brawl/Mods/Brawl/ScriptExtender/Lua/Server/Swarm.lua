local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump
local getDisplayName = Utils.getDisplayName
local isAliveAndCanFight = Utils.isAliveAndCanFight
local isToT = Utils.isToT

local function setTurnComplete(uuid)
    local entity = Ext.Entity.Get(uuid)
    if entity.TurnBased then
        -- print(getDisplayName(uuid), "Setting turn complete", uuid)
        entity.TurnBased.HadTurnInCombat = true
        entity.TurnBased.RequestedEndTurn = true
        entity.TurnBased.TurnActionsCompleted = true
        entity:Replicate("TurnBased")
        State.Session.SwarmTurnComplete[uuid] = true
    end
end

local function unsetTurnComplete(uuid)
    local entity = Ext.Entity.Get(uuid)
    if entity.TurnBased then
        -- print(getDisplayName(uuid), "Unsetting turn complete", uuid)
        entity.TurnBased.HadTurnInCombat = false
        entity.TurnBased.RequestedEndTurn = false
        entity.TurnBased.TurnActionsCompleted = false
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

local function checkSwarmTurnComplete()
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
        local brawlersInLevel = State.Session.Brawlers[level]
        if brawlersInLevel then
            for brawlerUuid, brawler in pairs(brawlersInLevel) do
                if Osi.IsPartyMember(brawlerUuid, 1) == 0 and not State.Session.SwarmTurnComplete[brawlerUuid] then
                    print("swarm turn not complete for", brawlerUuid, Utils.getDisplayName(brawlerUuid))
                    local numActions = Osi.GetActionResourceValuePersonal(brawler.uuid, "ActionPoint", 0)
                    local numBonusActions = Osi.GetActionResourceValuePersonal(brawler.uuid, "BonusActionPoint", 0)
                    print(brawler.displayName, "swarmAction", brawler.uuid, numActions, numBonusActions)
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
                    -- _D(entity.TurnBased)
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
        setTurnComplete(uuid)
        print("completeSwarmTurn", uuid, Utils.getDisplayName(uuid))
        _D(State.Session.SwarmTurnComplete)
        if checkSwarmTurnComplete() then
            resetSwarmTurnComplete()
        end
    end)
end

local function isControlledByDefaultAI(uuid)
    local entity = Ext.Entity.Get(uuid)
    if entity and entity.TurnBased and entity.TurnBased.IsActiveCombatTurn then
        print("entity ACTIVE, using default AI instead...", uuid, Utils.getDisplayName(uuid))
        State.Session.SwarmTurnComplete[uuid] = true
        return true
    end
    return false
end

local function swarmAction(brawler)
    if State.Session.SwarmTurnActive and not isControlledByDefaultAI(brawler.uuid) and not State.Session.SwarmTurnComplete[brawler.uuid] then
        local numActions = Osi.GetActionResourceValuePersonal(brawler.uuid, "ActionPoint", 0) or 0
        local numBonusActions = Osi.GetActionResourceValuePersonal(brawler.uuid, "BonusActionPoint", 0) or 0
        print(brawler.displayName, "swarmAction", brawler.uuid, numActions, numBonusActions)
        if numActions == 0 and numBonusActions == 0 then
            return completeSwarmTurn(brawler.uuid)
        end
        if numActions > 0 then
            local actionResult = AI.pulseAction(brawler)
            print(brawler.displayName, "action result", actionResult)
            if not actionResult and numBonusActions > 0 then
                local bonusActionResult = AI.pulseAction(brawler, true)
                print(brawler.displayName, "bonus action result (1)", bonusActionResult)
                if not bonusActionResult then
                    completeSwarmTurn(brawler.uuid)
                end
            end
        elseif numBonusActions > 0 then
            local bonusActionResult = AI.pulseAction(brawler, true)
            print(brawler.displayName, "bonus action result (2)", bonusActionResult)
            if not bonusActionResult then
                completeSwarmTurn(brawler.uuid)
            end
        end
    end
end

local function singleCharacterTurn(brawler, brawlerIndex)
    debugPrint("singleCharacterTurn", brawler.displayName, brawler.uuid, Utils.canAct(brawler.uuid))
    local hostCharacterUuid = Osi.GetHostCharacter()
    if isToT() and Osi.IsEnemy(brawler.uuid, hostCharacterUuid) == 0 and not Utils.isPlayerOrAlly(brawler.uuid) then
        Osi.SetRelationTemporaryHostile(brawler.uuid, hostCharacterUuid)
    end
    if State.Session.Players[brawler.uuid] or (isToT() and Mods.ToT.PersistentVars.Scenario and brawler.uuid == Mods.ToT.PersistentVars.Scenario.CombatHelper) or not Utils.canAct(brawler.uuid) then
        debugPrint("don't take turn", brawler.uuid, brawler.displayName)
        return false
    end
    if isControlledByDefaultAI(brawler.uuid) or State.Session.SwarmTurnComplete[brawler.uuid] then
        return false
    end
    -- if State.Session.TBSMActionResourceListeners[brawler.uuid] == nil then
    --     State.Session.TBSMActionResourceListeners[brawler.uuid] = Ext.Entity.Subscribe("ActionResources", function (entity, _, _)
    --         Movement.setMovementToMax(entity)
    --     end, Ext.Entity.Get(brawler.uuid))
    -- end
    Ext.Timer.WaitFor(brawlerIndex*25, function ()
        swarmAction(brawler)
    end)
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
                if State.Session.SwarmTurnActive and canActBeforeDelay[brawlerUuid] ~= false and singleCharacterTurn(brawler, brawlerIndex) then
                    brawlerIndex = brawlerIndex + 1
                end
            end
        end
    end
end

local function allBrawlersCanAct()
    local brawlersCanAct = {}
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
        local brawlersInLevel = State.Session.Brawlers[level]
        if brawlersInLevel then
            for brawlerUuid, brawler in pairs(brawlersInLevel) do
                brawlersCanAct[brawlerUuid] = Utils.canAct(brawlerUuid)
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
    State.Session.SwarmTurnActive = true
    Ext.Timer.WaitFor(2500, function () -- delay to allow new enemies to get scooped up
        if isToT() and Mods.ToT.PersistentVars.Scenario and Mods.ToT.PersistentVars.Scenario.Round ~= nil and not State.Session.TBSMToTSkippedPrepRound then
            State.Session.TBSMToTSkippedPrepRound = true
            State.Session.SwarmTurnActive = false
            print("SKIPPING PREP ROUND...")
            return
        end
        startEnemyTurn(canActBeforeDelay)
        if State.Session.SwarmTurnTimer ~= nil then
            Ext.Timer.Cancel(State.Session.SwarmTurnTimer)
            State.Session.SwarmTurnTimer = nil
        end
        State.Session.SwarmTurnTimerCombatRound = Utils.getCurrentCombatRound()
        State.Session.SwarmTurnTimer = Ext.Timer.WaitFor(20000, function ()
            print("current combat round", Utils.getCurrentCombatRound(), State.Session.SwarmTurnTimerCombatRound)
            if Utils.getCurrentCombatRound() == State.Session.SwarmTurnTimerCombatRound then
                print("***************************************************************************************")
                print("************************Swarm turn timer finished - setting all enemy turns complete...")
                print("***************************************************************************************")
                setAllEnemyTurnsComplete()
                State.Session.SwarmTurnTimerCombatRound = nil
                State.Session.SwarmTurnActive = false
            end
        end)
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
    completeSwarmTurn = completeSwarmTurn,
    startSwarmTurn = startSwarmTurn,
    checkAllPlayersFinishedTurns = checkAllPlayersFinishedTurns,
    startEnemyTurn = startEnemyTurn,
    swarmAction = swarmAction,
}
