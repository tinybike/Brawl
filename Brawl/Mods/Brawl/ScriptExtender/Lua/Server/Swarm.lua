local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump
local isToT = Utils.isToT
local startChunk
local singleCharacterTurn

local function cancelTimers()
    if State.Settings.TurnBasedSwarmMode then
        if State.Session.SwarmTurnTimer ~= nil then
            Ext.Timer.Cancel(State.Session.SwarmTurnTimer)
            State.Session.SwarmTurnTimer = nil
        end
        if State.Session.CurrentChunkTimer ~= nil then
            Ext.Timer.Cancel(State.Session.CurrentChunkTimer)
            State.Session.CurrentChunkTimer = nil
        end
    end
end

local function resumeTimers()
    if State.Settings.TurnBasedSwarmMode then
        if State.Session.SwarmTurnTimer ~= nil then
            Ext.Timer.Resume(State.Session.SwarmTurnTimer)
        end
        if State.Session.CurrentChunkTimer ~= nil then
            Ext.Timer.Resume(State.Session.CurrentChunkTimer)
        end
    end
end

local function pauseTimers()
    if State.Settings.TurnBasedSwarmMode then
        if State.Session.SwarmTurnTimer ~= nil then
            Ext.Timer.Pause(State.Session.SwarmTurnTimer)
        end
        if State.Session.CurrentChunkTimer ~= nil then
            Ext.Timer.Pause(State.Session.CurrentChunkTimer)
        end
    end
end

local function setTurnComplete(uuid)
    if State.Session.SwarmTurnActive then
        local entity = Ext.Entity.Get(uuid)
        if entity.TurnBased then
            -- print(M.Utils.getDisplayName(uuid), "Setting turn complete", uuid)
            entity.TurnBased.HadTurnInCombat = true
            entity.TurnBased.RequestedEndTurn = true
            entity.TurnBased.TurnActionsCompleted = true
            entity:Replicate("TurnBased")
            State.Session.SwarmTurnComplete[uuid] = true
        end
    end
end

local function unsetTurnComplete(uuid)
    local entity = Ext.Entity.Get(uuid)
    if entity.TurnBased then
        -- print(M.Utils.getDisplayName(uuid), "Unsetting turn complete", uuid)
        entity.TurnBased.HadTurnInCombat = false
        entity.TurnBased.RequestedEndTurn = false
        entity.TurnBased.TurnActionsCompleted = false
        entity:Replicate("TurnBased")
        State.Session.SwarmTurnComplete[uuid] = false
    end
end

local function setAllEnemyTurnsComplete()
    debugPrint("setAllEnemyTurnsComplete")
    local level = M.Osi.GetRegion(M.Osi.GetHostCharacter())
    if level then
        local brawlersInLevel = State.Session.Brawlers[level]
        if brawlersInLevel then
            for brawlerUuid, _ in pairs(brawlersInLevel) do
                if M.Osi.IsPartyMember(brawlerUuid, 1) == 0 then
                    setTurnComplete(brawlerUuid)
                end
            end
        end
    end
end

local function unsetAllEnemyTurnsComplete()
    debugPrint("unsetAllEnemyTurnsComplete")
    local level = M.Osi.GetRegion(M.Osi.GetHostCharacter())
    if level then
        local brawlersInLevel = State.Session.Brawlers[level]
        if brawlersInLevel then
            for brawlerUuid, _ in pairs(brawlersInLevel) do
                if M.Osi.IsPartyMember(brawlerUuid, 1) == 0 then
                    unsetTurnComplete(brawlerUuid)
                end
            end
        end
    end
end

local function allBrawlersCanAct()
    local brawlersCanAct = {}
    local level = M.Osi.GetRegion(M.Osi.GetHostCharacter())
    if level then
        local brawlersInLevel = State.Session.Brawlers[level]
        if brawlersInLevel then
            for brawlerUuid, brawler in pairs(brawlersInLevel) do
                brawlersCanAct[brawlerUuid] = M.Utils.canAct(brawlerUuid)
            end
        end
    end
    return brawlersCanAct
end

local function checkSwarmTurnComplete()
    local level = M.Osi.GetRegion(M.Osi.GetHostCharacter())
    if level then
        local brawlersInLevel = State.Session.Brawlers[level]
        if brawlersInLevel then
            for uuid, brawler in pairs(brawlersInLevel) do
                if M.Osi.IsPartyMember(uuid, 1) == 0 and not State.Session.SwarmTurnComplete[uuid] then
                    debugPrint(brawler.displayName, "swarm turn not complete for", uuid, Osi.GetActionResourceValuePersonal(uuid, "ActionPoint", 0), Osi.GetActionResourceValuePersonal(uuid, "BonusActionPoint", 0))
                    return false
                end
            end
        end
    end
    return true
end

local function resetSwarmTurnComplete()
    debugPrint("resetSwarmTurnComplete")
    local level = M.Osi.GetRegion(M.Osi.GetHostCharacter())
    if level then
        local brawlersInLevel = State.Session.Brawlers[level]
        if brawlersInLevel then
            for uuid, _ in pairs(brawlersInLevel) do
                if M.Osi.IsPartyMember(uuid, 1) == 0 then
                    debugPrint("setting turn complete for", uuid, M.Utils.getDisplayName(uuid))
                    local entity = Ext.Entity.Get(uuid)
                    if entity and entity.TurnBased and not entity.TurnBased.HadTurnInCombat then
                        setTurnComplete(uuid)
                    end
                    State.Session.SwarmTurnComplete[uuid] = false
                end
            end
        end
    end
end

local function isChunkDone(chunkIndex)
    for uuid in pairs(State.Session.BrawlerChunks[chunkIndex]) do
        if not State.Session.SwarmTurnComplete[uuid] then
            return false
        end
    end
    return true
end

local function completeSwarmTurn(uuid)
    if State.Session.SwarmTurnActive then
        local chunkIndex = State.Session.CurrentChunkIndex
        if chunkIndex and isChunkDone(chunkIndex) then
            if State.Session.ChunkInProgress == chunkIndex then
                State.Session.ChunkInProgress = nil
                if State.Session.CurrentChunkTimer then
                    Ext.Timer.Cancel(State.Session.CurrentChunkTimer)
                    State.Session.CurrentChunkTimer = nil
                end
                startChunk(chunkIndex + 1)
            end
        end
    end
    setTurnComplete(uuid)
    debugPrint(M.Utils.getDisplayName(uuid), "completeSwarmTurn", uuid)
    -- _D(State.Session.SwarmTurnComplete)
    if checkSwarmTurnComplete() then
        resetSwarmTurnComplete()
    end
end

local function forceCompleteChunk(chunkIndex)
    print("FORCE COMPLETE CHUNK", chunkIndex)
    for uuid in pairs(State.Session.BrawlerChunks[chunkIndex]) do
        if not State.Session.SwarmTurnComplete[uuid] then
            completeSwarmTurn(uuid)
        end
    end
end

startChunk = function (chunkIndex)
    if State.Session.ChunkInProgress ~= chunkIndex then
        State.Session.ChunkInProgress = chunkIndex
        print("****************startChunk", chunkIndex)
        local chunk = State.Session.BrawlerChunks[chunkIndex]
        if not chunk then
            State.Session.ChunkInProgress = nil
            return
        end
        State.Session.CurrentChunkIndex = chunkIndex
        if State.Session.CurrentChunkTimer then
            Ext.Timer.Cancel(State.Session.CurrentChunkTimer)
            State.Session.CurrentChunkTimer = nil
        end
        local idx = 0
        for uuid, brawler in pairs(chunk) do
            State.Session.SwarmTurnComplete[uuid] = false
            if State.Session.SwarmTurnActive and State.Session.CanActBeforeDelay[uuid] ~= false then
                singleCharacterTurn(brawler, idx)
                idx = idx + 1
            end
        end
        State.Session.CurrentChunkTimer = Ext.Timer.WaitFor(Constants.SWARM_TURN_TIMEOUT, function ()
            if State.Session.ChunkInProgress == chunkIndex then
                State.Session.ChunkInProgress = nil
                forceCompleteChunk(chunkIndex)
                startChunk(chunkIndex + 1)
            end
        end)
    end
end

local function isControlledByDefaultAI(uuid)
    local entity = Ext.Entity.Get(uuid)
    if entity and entity.TurnBased and entity.TurnBased.IsActiveCombatTurn then
        debugPrint("entity ACTIVE, using default AI instead...", uuid, M.Utils.getDisplayName(uuid))
        State.Session.SwarmTurnComplete[uuid] = true
        return true
    end
    return false
end

local function useRemainingActions(brawler, callback)
    if brawler and brawler.uuid then
        local numActions = M.Osi.GetActionResourceValuePersonal(brawler.uuid, "ActionPoint", 0) or 0
        local numBonusActions = M.Osi.GetActionResourceValuePersonal(brawler.uuid, "BonusActionPoint", 0) or 0
        -- print(brawler.displayName, "useRemainingActions", brawler.uuid, numActions, numBonusActions)
        if numActions == 0 and numBonusActions == 0 then
            if State.Session.QueuedCompanionAIAction[brawler.uuid] then
                State.Session.QueuedCompanionAIAction[brawler.uuid] = false
                local entity = Ext.Entity.Get(brawler.uuid)
                if entity and entity.TurnBased then
                    entity.TurnBased.RequestedEndTurn = true
                    entity:Replicate("TurnBased")
                end
            end
            if callback then callback(brawler.uuid) end
        else
            if numActions > 0 then
                local actionResult = AI.pulseAction(brawler)
                -- print(brawler.displayName, "action result", actionResult)
                if not actionResult and numBonusActions > 0 then
                    local bonusActionResult = AI.pulseAction(brawler, true)
                    -- print(brawler.displayName, "bonus action result (1)", bonusActionResult)
                    if not bonusActionResult then
                        -- should this call completeSwarmTurn?
                        if callback then callback(brawler.uuid) end
                    end
                end
            elseif numBonusActions > 0 then
                local bonusActionResult = AI.pulseAction(brawler, true)
                -- print(brawler.displayName, "bonus action result (2)", bonusActionResult)
                if not bonusActionResult then
                    if callback then callback(brawler.uuid) end
                end
            end
        end
    end
end

local function swarmAction(brawler)
    -- print(brawler.displayName, "swarmAction")
    if State.Session.SwarmTurnActive and not isControlledByDefaultAI(brawler.uuid) and not State.Session.SwarmTurnComplete[brawler.uuid] then
        useRemainingActions(brawler, completeSwarmTurn)
    elseif State.Session.QueuedCompanionAIAction[brawler.uuid] then
        useRemainingActions(brawler)
    end
end

singleCharacterTurn = function (brawler, brawlerIndex)
    debugPrint("singleCharacterTurn", brawler.displayName, brawler.uuid, M.Utils.canAct(brawler.uuid))
    local hostCharacterUuid = M.Osi.GetHostCharacter()
    if isToT() and M.Osi.IsEnemy(brawler.uuid, hostCharacterUuid) == 0 and not M.Utils.isPlayerOrAlly(brawler.uuid) then
        print("setting temporary hostile", brawler.displayName, brawler.uuid, hostCharacterUuid)
        Osi.SetRelationTemporaryHostile(brawler.uuid, hostCharacterUuid)
    end
    if State.Session.Players[brawler.uuid] or (isToT() and Mods.ToT.PersistentVars.Scenario and brawler.uuid == Mods.ToT.PersistentVars.Scenario.CombatHelper) or not M.Utils.canAct(brawler.uuid) then
        debugPrint("don't take turn", brawler.uuid, brawler.displayName)
        return false
    end
    if isControlledByDefaultAI(brawler.uuid) or State.Session.SwarmTurnComplete[brawler.uuid] then
        return false
    end
    Ext.Timer.WaitFor(brawlerIndex*25, function ()
        swarmAction(brawler)
    end)
    return true
end

local function startEnemyTurn()
    debugPrint("startEnemyTurn")
    local level = M.Osi.GetRegion(M.Osi.GetHostCharacter())
    if level then
        local brawlersInLevel = State.Session.Brawlers[level]
        if brawlersInLevel then
            State.Session.BrawlerChunks = {}
            local chunkIndex, brawlersInChunk = 1, 0
            for brawlerUuid, brawler in pairs(brawlersInLevel) do
                if M.Osi.IsPartyMember(brawlerUuid, 1) == 0 then
                    State.Session.BrawlerChunks[chunkIndex] = State.Session.BrawlerChunks[chunkIndex] or {}
                    State.Session.BrawlerChunks[chunkIndex][brawlerUuid] = brawler
                    print("CHUNK", chunkIndex, brawlersInChunk, brawler.displayName)
                    brawlersInChunk = brawlersInChunk + 1
                    if brawlersInChunk >= Constants.SWARM_CHUNK_SIZE then
                        chunkIndex = chunkIndex + 1
                        print("")
                        brawlersInChunk = 0
                    end
                end
            end
            startChunk(1)
            return chunkIndex
        end
    end
end

-- the FIRST enemy to go uses the built-in AI and takes its turn normally, this keeps the turn open
-- all other enemies go at the same time, using the Brawl AI
-- possible for the first enemy's turn to end early, and then it bleeds over into the player turn, but unusual
local function startSwarmTurn()
    local shouldFreezePlayers = {}
    for uuid, _ in pairs(State.Session.Players) do
        shouldFreezePlayers[uuid] = Utils.isToT() or M.Osi.IsInCombat(uuid) == 1
    end
    State.Session.TurnBasedSwarmModePlayerTurnEnded = {}
    State.Session.CanActBeforeDelay = allBrawlersCanAct()
    State.Session.SwarmTurnActive = true
    Ext.Timer.WaitFor(1000, function () -- delay to allow new enemies to get scooped up
        if isToT() and Mods.ToT.PersistentVars.Scenario and Mods.ToT.PersistentVars.Scenario.Round ~= nil and not State.Session.TBSMToTSkippedPrepRound then
            State.Session.TBSMToTSkippedPrepRound = true
            State.Session.SwarmTurnActive = false
            debugPrint("SKIPPING PREP ROUND...")
            return
        end
        local numChunks = startEnemyTurn()
        if numChunks ~= nil then
            print("NUMBER OF CHUNKS TOTAL", numChunks)
            if State.Session.SwarmTurnTimer ~= nil then
                Ext.Timer.Cancel(State.Session.SwarmTurnTimer)
                State.Session.SwarmTurnTimer = nil
            end
            State.Session.SwarmTurnTimerCombatRound = M.Utils.getCurrentCombatRound()
            State.Session.SwarmTurnTimer = Ext.Timer.WaitFor(numChunks*Constants.SWARM_TURN_TIMEOUT, function ()
                if M.Utils.getCurrentCombatRound() == State.Session.SwarmTurnTimerCombatRound then
                    print("************************Swarm turn timer finished - setting all enemy turns complete...")
                    setAllEnemyTurnsComplete()
                    State.Session.SwarmTurnTimerCombatRound = nil
                    State.Session.SwarmTurnActive = false
                end
            end)
        end
    end)
end

local function checkAllPlayersFinishedTurns()
    local players = State.Session.Players
    if players then
        for playerUuid, player in pairs(players) do
            local isUncontrolled = M.Utils.hasLoseControlStatus(playerUuid)
            print("Checking finished turns", playerUuid, State.Session.TurnBasedSwarmModePlayerTurnEnded[playerUuid], M.Utils.isAliveAndCanFight(playerUuid), isUncontrolled, player.isFreshSummon)
            if player.isFreshSummon then
                player.isFreshSummon = false
                if not isUncontrolled then
                    local entity = Ext.Entity.Get(playerUuid)
                    entity.TurnBased.RequestedEndTurn = true
                    entity:Replicate("TurnBased")
                end
                State.Session.TurnBasedSwarmModePlayerTurnEnded[playerUuid] = true
            elseif M.Utils.isAliveAndCanFight(playerUuid) and not isUncontrolled and not State.Session.TurnBasedSwarmModePlayerTurnEnded[playerUuid] then
                return false
            end
        end
        return true
    end
    return nil
end

return {
    cancelTimers = cancelTimers,
    resumeTimers = resumeTimers,
    pauseTimers = pauseTimers,
    setTurnComplete = setTurnComplete,
    unsetTurnComplete = unsetTurnComplete,
    setAllEnemyTurnsComplete = setAllEnemyTurnsComplete,
    unsetAllEnemyTurnsComplete = unsetAllEnemyTurnsComplete,
    completeSwarmTurn = completeSwarmTurn,
    startSwarmTurn = startSwarmTurn,
    checkAllPlayersFinishedTurns = checkAllPlayersFinishedTurns,
    startEnemyTurn = startEnemyTurn,
    useRemainingActions = useRemainingActions,
    swarmAction = swarmAction,
}
