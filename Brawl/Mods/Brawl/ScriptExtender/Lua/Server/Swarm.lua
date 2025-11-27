local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump
local noop = Utils.noop
local startChunk
local singleCharacterTurn
local useRemainingActions

local function isToTExcludedEnemyTier(uuid)
    return (M.Utils.isToT() and State.Settings.ExcludeEnemyTiers and M.Utils.contains(State.Settings.ExcludeEnemyTiers, M.Utils.getToTEnemyTier(uuid)))
end

local function isExcludedFromSwarmAI(uuid)
    return (M.Osi.GetActiveArchetype(uuid) == "dragon") or isToTExcludedEnemyTier(uuid)
end

local function isControlledByDefaultAI(uuid)
    if M.Swarm.isExcludedFromSwarmAI(uuid) or M.Utils.isActiveCombatTurn(uuid) then
        debugPrint(M.Utils.getDisplayName(uuid), "entity using default AI", M.Swarm.isExcludedFromSwarmAI(uuid), M.Utils.isActiveCombatTurn(uuid))
        return true
    end
    return false
end

local function getNumExcluded(swarmActors)
    local numExcluded = 0
    for _, uuid in ipairs(swarmActors) do
        if M.Swarm.isExcludedFromSwarmAI(uuid) then
            numExcluded = numExcluded + 1
            debugPrint(M.Utils.getDisplayName(uuid), "excluded from swarm AI", numExcluded)
        end
    end
    return numExcluded
end

local function getChunkTimeout(swarmActors)
    return math.floor(State.Settings.SwarmTurnTimeout*1000) + getNumExcluded(swarmActors)*Constants.EXCLUDED_ENEMY_TIMEOUT
end

local function getInitiativeRoll(uuid)
    local entity = Ext.Entity.Get(uuid)
    if entity and entity.CombatParticipant then
        return entity.CombatParticipant.InitiativeRoll
    end
end

local function calculateMeanInitiativeRoll()
    debugPrint("Calculating mean initiative roll")
    local totalInitiativeRoll = 0
    local numInitiativeRolls = 0
    for uuid, player in pairs(State.Session.Players) do
        local entity = Ext.Entity.Get(uuid)
        if entity and entity.CombatParticipant and entity.CombatParticipant.InitiativeRoll then
            totalInitiativeRoll = totalInitiativeRoll + entity.CombatParticipant.InitiativeRoll
            numInitiativeRolls = numInitiativeRolls + 1
        end
    end
    local meanInitiativeRoll = math.floor(totalInitiativeRoll/numInitiativeRolls + 0.5)
    debugPrint("Mean initiative roll:", meanInitiativeRoll)
    return meanInitiativeRoll
end

local function setInitiativeRoll(uuid, roll)
    local entity = Ext.Entity.Get(uuid)
    if entity.CombatParticipant and entity.CombatParticipant.InitiativeRoll then
        entity.CombatParticipant.InitiativeRoll = roll
        if entity.CombatParticipant.CombatHandle and entity.CombatParticipant.CombatHandle.CombatState and entity.CombatParticipant.CombatHandle.CombatState.Initiatives then
            entity.CombatParticipant.CombatHandle.CombatState.Initiatives[entity] = roll
            entity.CombatParticipant.CombatHandle:Replicate("CombatState")
        end
        entity:Replicate("CombatParticipant")
    end
end

local function setPartyInitiativeRollToMean()
    State.Session.MeanInitiativeRoll = calculateMeanInitiativeRoll()
    for uuid, player in pairs(State.Session.Players) do
        setInitiativeRoll(uuid, State.Session.MeanInitiativeRoll)
    end
end

local function bumpNpcInitiativeRoll(uuid)
    local entity = Ext.Entity.Get(uuid)
    local initiativeRoll = getInitiativeRoll(uuid)
    local bumpedInitiativeRoll = math.random() > 0.5 and initiativeRoll + 1 or initiativeRoll - 1
    debugPrint(M.Utils.getDisplayName(uuid), "might split group, bumping roll", initiativeRoll, "->", bumpedInitiativeRoll)
    setInitiativeRoll(uuid, bumpedInitiativeRoll)
end

local function bumpNpcInitiativeRolls()
    if State.Session.MeanInitiativeRoll ~= -100 then
        for uuid, _ in pairs(M.Roster.getBrawlers()) do
            if not State.Session.Players[uuid] and getInitiativeRoll(uuid) == State.Session.MeanInitiativeRoll then
                bumpNpcInitiativeRoll(uuid)
            end
        end
    end
end

local function cancelActionTimers(swarmActors)
    debugPrint("cancelActionTimers", swarmActors)
    if swarmActors then debugDump(swarmActors) end
    if State.Settings.TurnBasedSwarmMode and State.Session.ActionSequenceFailsafeTimer and next(State.Session.ActionSequenceFailsafeTimer) then
        if swarmActors then
            for _, uuid in ipairs(swarmActors) do
                local failsafe = State.Session.ActionSequenceFailsafeTimer[uuid]
                if failsafe and failsafe.timer then
                    Ext.Timer.Cancel(failsafe.timer)
                    failsafe.timer = nil
                end
                Actions.removeActionsInProgress(uuid)
            end
        else
            for uuid, failsafe in pairs(State.Session.ActionSequenceFailsafeTimer) do
                if failsafe.timer then
                    Ext.Timer.Cancel(failsafe.timer)
                    failsafe.timer = nil
                end
            end
            State.Session.ActionsInProgress = {}
        end
    end
end

local function cancelTimers(swarmActors)
    debugPrint("cancelTimers", swarmActors)
    if swarmActors then debugDump(swarmActors) end
    if State.Settings.TurnBasedSwarmMode then
        if State.Session.CurrentChunkTimer ~= nil then
            Ext.Timer.Cancel(State.Session.CurrentChunkTimer)
            State.Session.CurrentChunkTimer = nil
        end
        cancelActionTimers(swarmActors)
    end
end

local function resumeTimers()
    if State.Settings.TurnBasedSwarmMode then
        if State.Session.CurrentChunkTimer ~= nil then
            Ext.Timer.Resume(State.Session.CurrentChunkTimer)
        end
        if State.Session.ActionSequenceFailsafeTimer and next(State.Session.ActionSequenceFailsafeTimer) then
            for _, failsafe in pairs(State.Session.ActionSequenceFailsafeTimer) do
                if failsafe.timer then
                    Ext.Timer.Resume(failsafe.timer)
                end
            end
        end
    end
end

local function pauseTimers()
    if State.Settings.TurnBasedSwarmMode then
        if State.Session.CurrentChunkTimer ~= nil then
            Ext.Timer.Pause(State.Session.CurrentChunkTimer)
        end
        if State.Session.ActionSequenceFailsafeTimer and next(State.Session.ActionSequenceFailsafeTimer) then
            for _, failsafe in pairs(State.Session.ActionSequenceFailsafeTimer) do
                if failsafe.timer then
                    Ext.Timer.Pause(failsafe.timer)
                end
            end
        end
    end
end

local function setTurnComplete(uuid)
    if State.Session.QueuedCompanionAIAction[uuid] then
        State.Session.QueuedCompanionAIAction[uuid] = false
    end
    local entity = Ext.Entity.Get(uuid)
    if entity and entity.TurnBased then
        debugPrint(M.Utils.getDisplayName(uuid), "Setting turn complete", uuid)
        entity.TurnBased.RequestedEndTurn = true
        if M.Osi.IsPartyMember(uuid, 1) == 0 then
            entity.TurnBased.HadTurnInCombat = true
            entity.TurnBased.TurnActionsCompleted = true
            entity.TurnBased.ActedThisRoundInCombat = true
        end
        entity:Replicate("TurnBased")
    end
    if M.Osi.IsPartyMember(uuid, 1) == 0 then
        State.Session.SwarmTurnComplete[uuid] = true
        if State.Session.SwarmBrawlerIndexDelay[uuid] ~= nil then
            Ext.Timer.Cancel(State.Session.SwarmBrawlerIndexDelay[uuid])
            State.Session.SwarmBrawlerIndexDelay[uuid] = nil
        end
    end
    cancelActionTimers({uuid})
end

local function unsetTurnComplete(uuid)
    local entity = Ext.Entity.Get(uuid)
    if entity and entity.TurnBased then
        debugPrint(M.Utils.getDisplayName(uuid), "Unsetting turn complete", uuid)
        entity.TurnBased.RequestedEndTurn = false
        entity.TurnBased.HadTurnInCombat = false
        entity.TurnBased.TurnActionsCompleted = false
        entity.TurnBased.ActedThisRoundInCombat = false
        entity:Replicate("TurnBased")
        if M.Osi.IsPartyMember(uuid, 1) == 0 then
            State.Session.SwarmTurnComplete[uuid] = false
        end
        -- Resources.restoreActionResource(entity, "Movement")
    end
end

local function getEnemyList(isBeforePlayer)
    if isBeforePlayer and State.Settings.PlayersGoFirst then
        return {}
    end
    local enemyList = {}
    local excludedEnemyList = {}
    local combatEntity = Utils.getCombatEntity()
    if combatEntity and combatEntity.TurnOrder and combatEntity.TurnOrder.Groups then
        local playerGroupFound = false
        for i, group in ipairs(combatEntity.TurnOrder.Groups) do
            if group.IsPlayer then
                debugPrint("got to player group", i)
                playerGroupFound = true
            elseif group.Members and #group.Members > 0 and group.Initiative > -20 then
                for _, member in ipairs(group.Members) do
                    if member.Entity and member.Entity.Uuid and member.Entity.Uuid.EntityUuid then
                        if isBeforePlayer then
                            if playerGroupFound then
                                table.insert(excludedEnemyList, member.Entity.Uuid.EntityUuid)
                            else
                                table.insert(enemyList, member.Entity.Uuid.EntityUuid)
                            end
                        else
                            if playerGroupFound then
                                table.insert(enemyList, member.Entity.Uuid.EntityUuid)
                            else
                                table.insert(excludedEnemyList, member.Entity.Uuid.EntityUuid)
                            end
                        end
                    end
                end
            end
        end
    end
    debugPrint("got enemy list", isBeforePlayer)
    for i, uuid in ipairs(enemyList) do
        debugPrint(i, uuid, M.Utils.getDisplayName(uuid))
    end
    debugPrint("got excluded enemy list", isBeforePlayer)
    for i, uuid in ipairs(excludedEnemyList) do
        debugPrint(i, uuid, M.Utils.getDisplayName(uuid))
    end
    -- debugDump(enemyList)
    return enemyList, excludedEnemyList
end

local function resetChunkState()
    State.Session.ChunkInProgress = nil
    State.Session.CurrentChunkIndex = nil
    if State.Session.CurrentChunkTimer then
        Ext.Timer.Cancel(State.Session.CurrentChunkTimer)
        State.Session.CurrentChunkTimer = nil
    end
end

local function setAllPlayerTurnsComplete()
    debugPrint("setAllPlayerTurnsComplete")
    for uuid, _ in pairs(State.Session.Players) do
        setTurnComplete(uuid)
    end
end

local function setAllEnemyTurnsComplete()
    debugPrint("setAllEnemyTurnsComplete")
    if State.Session.SwarmTurnActive then
        for uuid, _ in pairs(M.Roster.getBrawlers()) do
            if M.Osi.IsPartyMember(uuid, 1) == 0 then
                setTurnComplete(uuid)
            end
        end
    end
    resetChunkState()
end

local function unsetAllEnemyTurnsComplete()
    debugPrint("unsetAllEnemyTurnsComplete")
    for uuid, _ in pairs(M.Roster.getBrawlers()) do
        if M.Osi.IsPartyMember(uuid, 1) == 0 then
            unsetTurnComplete(uuid)
        end
    end
    resetChunkState()
end

local function setEnemyTurnsComplete(uuids)
    debugPrint("setEnemyTurnsComplete")
    for _, uuid in ipairs(uuids) do
        setTurnComplete(uuid)
    end
    resetChunkState()
end

local function unsetEnemyTurnsComplete(uuids)
    debugPrint("unsetEnemyTurnsComplete")
    for _, uuid in ipairs(uuids) do
        unsetTurnComplete(uuid)
    end
    resetChunkState()
end

local function allBrawlersCanAct()
    local brawlersCanAct = {}
    for uuid, _ in pairs(M.Roster.getBrawlers()) do
        brawlersCanAct[uuid] = M.Utils.canAct(uuid)
    end
    return brawlersCanAct
end

local function checkSwarmTurnComplete(swarmActors)
    if swarmActors then
        for _, uuid in ipairs(swarmActors) do
            if not State.Session.SwarmTurnComplete[uuid] then
                debugPrint(M.Utils.getDisplayName(uuid), "swarm turn not complete", uuid)
                return false
            end
        end
    end
    return true
end

local function resetSwarmTurnComplete(swarmActors)
    debugPrint("resetSwarmTurnComplete", swarmActors)
    if swarmActors then
        for _, uuid in ipairs(swarmActors) do
            debugPrint(M.Utils.getDisplayName(uuid), "resetSwarmTurnComplete", uuid)
            -- local entity = Ext.Entity.Get(uuid)
            -- if entity and entity.TurnBased and not entity.TurnBased.HadTurnInCombat then
            --     setTurnComplete(uuid)
            -- end
            State.Session.SwarmTurnComplete[uuid] = false
        end
    end
    cancelTimers(swarmActors)
    State.Session.SwarmTurnActive = false
    State.SwarmActors = nil
end

local function isChunkDone(chunkIndex)
    if not State.Session.BrawlerChunks[chunkIndex] then
        debugPrint("error, chunk not found", chunkIndex)
        debugDump(State.Session.BrawlerChunks)
    end
    for uuid in pairs(State.Session.BrawlerChunks[chunkIndex]) do
        if not State.Session.SwarmTurnComplete[uuid] then
            return false
        end
    end
    return true
end

local function completeSwarmTurn(uuid, swarmActors)
    if State.Session.SwarmTurnActive then
        local chunkIndex = State.Session.CurrentChunkIndex or 1
        debugPrint(M.Utils.getDisplayName(uuid), "completeSwarmTurn", chunkIndex, State.Session.ChunkInProgress, State.Session.CurrentChunkIndex)
        local chunkDone = isChunkDone(chunkIndex)
        debugPrint("chunkDone?", chunkDone)
        if chunkIndex and chunkDone then
            if State.Session.ChunkInProgress == chunkIndex then
                State.Session.ChunkInProgress = nil
                if State.Session.CurrentChunkTimer then
                    Ext.Timer.Cancel(State.Session.CurrentChunkTimer)
                    State.Session.CurrentChunkTimer = nil
                end
                debugPrint("completeSwarmTurn advance to next chunk", chunkIndex + 1, #swarmActors)
                startChunk(chunkIndex + 1, swarmActors)
            end
        end
        if not M.Swarm.isControlledByDefaultAI(uuid) then
            if M.Osi.IsPartyMember(uuid, 1) == 0 then
                State.Session.SwarmTurnComplete[uuid] = true
                if State.Session.SwarmBrawlerIndexDelay[uuid] ~= nil then
                    Ext.Timer.Cancel(State.Session.SwarmBrawlerIndexDelay[uuid])
                    State.Session.SwarmBrawlerIndexDelay[uuid] = nil
                end
            end
            cancelActionTimers({uuid})
        end
    end
    debugPrint(M.Utils.getDisplayName(uuid), "completeSwarmTurn", uuid)
    if checkSwarmTurnComplete(swarmActors) then
        resetSwarmTurnComplete(swarmActors)
    end
end

local function forceCompleteChunk(chunkIndex, swarmActors)
    for uuid in pairs(State.Session.BrawlerChunks[chunkIndex]) do
        if not State.Session.SwarmTurnComplete[uuid] then
            completeSwarmTurn(uuid, swarmActors)
        end
    end
end

startChunk = function (chunkIndex, swarmActors)
    if State.Session.ChunkInProgress ~= chunkIndex then
        State.Session.ChunkInProgress = chunkIndex
        local chunk = State.Session.BrawlerChunks[chunkIndex]
        if not chunk then
            State.Session.ChunkInProgress = nil
            return
        end
        debugPrint("startChunk", chunkIndex, State.Session.ChunkInProgress)
        State.Session.CurrentChunkIndex = chunkIndex
        if State.Session.CurrentChunkTimer then
            Ext.Timer.Cancel(State.Session.CurrentChunkTimer)
            State.Session.CurrentChunkTimer = nil
        end
        local idx = 0
        for uuid, brawler in pairs(chunk) do
            State.Session.SwarmTurnComplete[uuid] = false
            if State.Session.SwarmTurnActive and State.Session.CanActBeforeDelay[uuid] ~= false then
                singleCharacterTurn(brawler, idx, swarmActors)
                idx = idx + 1
            end
        end
        State.Session.CurrentChunkTimer = Ext.Timer.WaitFor(getChunkTimeout(swarmActors), function ()
            debugPrint("chunk timer expired", State.Session.ChunkInProgress, chunkIndex)
            if State.Session.ChunkInProgress == chunkIndex then
                State.Session.ChunkInProgress = nil
                forceCompleteChunk(chunkIndex, swarmActors)
                startChunk(chunkIndex + 1, swarmActors)
            end
        end)
    end
end

local function terminateActionSequence(uuid, swarmTurnActiveInitial, swarmActors, callback)
    if swarmTurnActiveInitial and not State.Session.SwarmTurnActive then
        return callback(uuid, swarmActors)
    end
    -- NB: is this needed?
    setTurnComplete(uuid)
    callback(uuid, swarmActors)
end

local function cancelActionSequenceFailsafeTimer(uuid)
    if State.Session.ActionSequenceFailsafeTimer and State.Session.ActionSequenceFailsafeTimer[uuid] and State.Session.ActionSequenceFailsafeTimer[uuid].timer then
        Ext.Timer.Cancel(State.Session.ActionSequenceFailsafeTimer[uuid].timer)
        State.Session.ActionSequenceFailsafeTimer[uuid].timer = nil
    end
end

local function startActionSequenceFailsafeTimer(brawler, request, swarmTurnActiveInitial, swarmActors, callback, count)
    count = count or 0
    local uuid = brawler.uuid
    debugPrint(brawler.displayName, "startActionSequenceFailsafeTimer", request.Spell.Prototype, swarmTurnActiveInitial, count)
    local isRetry = false
    local currentCombatRound = M.Utils.getCurrentCombatRound()
    if State.Session.ActionSequenceFailsafeTimer[uuid] then
        cancelActionSequenceFailsafeTimer(uuid)
        isRetry = true
    end
    State.Session.ActionSequenceFailsafeTimer[uuid] = {}
    State.Session.ActionSequenceFailsafeTimer[uuid].timer = Ext.Timer.WaitFor(Constants.ACTION_MAX_TIME, function ()
        debugPrint(brawler.displayName, "failsafe timer expired for", swarmTurnActiveInitial, request.Spell.Prototype)
        State.Session.ActionSequenceFailsafeTimer[uuid] = nil
        if swarmTurnActiveInitial and not State.Session.SwarmTurnActive then
            return callback(uuid)
        end
        if Actions.getActionInProgress(uuid, request.RequestGuid) and currentCombatRound == M.Utils.getCurrentCombatRound() then
            debugPrint(brawler.displayName, "action timed out", request.Spell.Prototype, isRetry)
            Actions.removeActionInProgress(uuid, request.RequestGuid)
            if not isRetry then
                return terminateActionSequence(uuid, swarmTurnActiveInitial, swarmActors, callback)
            end
            useRemainingActions(brawler, swarmTurnActiveInitial, swarmActors, callback, count + 1)
        end
    end)
end

local function requestedEndTurn(uuid)
    local entity = Ext.Entity.Get(uuid)
    debugPrint("Requested end turn?", M.Utils.getDisplayName(uuid), entity.TurnBased.RequestedEndTurn)
    if entity and entity.TurnBased then
        return entity.TurnBased.RequestedEndTurn
    end
    return false
end

useRemainingActions = function (brawler, swarmTurnActiveInitial, swarmActors, callback, count)
    callback = callback or noop
    if brawler and brawler.uuid then
        if swarmTurnActiveInitial then
            if not State.Session.SwarmTurnActive then
                debugPrint(brawler.displayName, "swarm turn global timed out")
                return callback(brawler.uuid, swarmActors)
            elseif M.Swarm.isControlledByDefaultAI(brawler.uuid) then
                debugPrint(brawler.displayName, "controlled by default AI, skipping")
                State.Session.SwarmTurnComplete[brawler.uuid] = true
                return callback(brawler.uuid, swarmActors)
            elseif State.Session.SwarmTurnComplete[brawler.uuid] then
                debugPrint(brawler.displayName, "swarm turn already complete, skipping")
                return callback(brawler.uuid, swarmActors)
            end
        end
        count = count or 0
        local numActions = Resources.getActionPointsRemaining(brawler.uuid)
        local numBonusActions = Resources.getBonusActionPointsRemaining(brawler.uuid)
        debugPrint(brawler.displayName, "useRemainingActions", count, numActions, numBonusActions, swarmTurnActiveInitial, swarmActors)
        if (numActions == 0 and numBonusActions == 0) or count > Constants.ACTION_ATTEMPT_LIMIT then
            if count > Constants.ACTION_ATTEMPT_LIMIT then
                debugPrint(brawler.displayName, count, "counter limit reached, what happened here??")
            end
            setTurnComplete(brawler.uuid)
            return callback(brawler.uuid, swarmActors)
        end
        if numActions == 0 then
            return AI.pulseAction(brawler, true, function (request)
                debugPrint(brawler.displayName, "bonus action SUBMITTED", request.Spell.Prototype, request.RequestGuid)
                if requestedEndTurn(brawler.uuid) then
                    return callback(brawler.uuid, swarmActors)
                end
                startActionSequenceFailsafeTimer(brawler, request, swarmTurnActiveInitial, swarmActors, callback, count)
            end, function (spellName)
                debugPrint(brawler.displayName, "bonus action COMPLETED", spellName)
                cancelActionSequenceFailsafeTimer(brawler.uuid)
                if requestedEndTurn(brawler.uuid) then
                    return callback(brawler.uuid, swarmActors)
                end
                Ext.Timer.WaitFor(Constants.TIME_BETWEEN_ACTIONS, function ()
                    useRemainingActions(brawler, swarmTurnActiveInitial, swarmActors, callback, count)
                end)
            end, function (err)
                debugPrint(brawler.displayName, "bonus action FAILED", err)
                cancelActionSequenceFailsafeTimer(brawler.uuid)
                terminateActionSequence(brawler.uuid, swarmTurnActiveInitial, swarmActors, callback)
            end)
        end
        -- if State.Session.ActionsInProgress[brawler.uuid] and next(State.Session.ActionsInProgress[brawler.uuid]) then
        --     print(brawler.displayName)
        --     _D(State.Session.ActionsInProgress[brawler.uuid])
        --     error("we have a current AIP, what is this????")
        -- end
        AI.pulseAction(brawler, false, function (request)
            debugPrint(brawler.displayName, "action SUBMITTED", request.Spell.Prototype, request.RequestGuid)
            if requestedEndTurn(brawler.uuid) then
                return callback(brawler.uuid, swarmActors)
            end
            startActionSequenceFailsafeTimer(brawler, request, swarmTurnActiveInitial, swarmActors, callback, count)
        end, function (spellName)
            debugPrint(brawler.displayName, "action COMPLETED", spellName)
            cancelActionSequenceFailsafeTimer(brawler.uuid)
            if requestedEndTurn(brawler.uuid) then
                return callback(brawler.uuid, swarmActors)
            end
            Ext.Timer.WaitFor(Constants.TIME_BETWEEN_ACTIONS, function ()
                useRemainingActions(brawler, swarmTurnActiveInitial, swarmActors, callback, count)
            end)
        end, function (err)
            debugPrint(brawler.displayName, "action FAILED", err)
            cancelActionSequenceFailsafeTimer(brawler.uuid)
            if requestedEndTurn(brawler.uuid) then
                return callback(brawler.uuid, swarmActors)
            end
            if Resources.getBonusActionPointsRemaining(brawler.uuid) == 0 or err == "can't find target" then
                return terminateActionSequence(brawler.uuid, swarmTurnActiveInitial, swarmActors, callback)
            end
            useRemainingActions(brawler, swarmTurnActiveInitial, swarmActors, callback, count + 1)
        end)
    end
end

local function swarmAction(brawler, swarmActors)
    debugPrint(brawler.displayName, "swarmAction")
    if State.Session.SwarmTurnActive and M.Osi.IsPartyMember(brawler.uuid, 1) == 0 then
        useRemainingActions(brawler, true, swarmActors, completeSwarmTurn)
    elseif State.Session.QueuedCompanionAIAction[brawler.uuid] then
        useRemainingActions(brawler, false)
    end
end

singleCharacterTurn = function (brawler, brawlerIndex, swarmActors)
    debugPrint("singleCharacterTurn", brawler.displayName, brawler.uuid, M.Utils.canAct(brawler.uuid), brawlerIndex*25)
    debugPrint("remaining movement", Movement.getMovementDistanceAmount(Ext.Entity.Get(brawler.uuid)))
    local hostCharacterUuid = M.Osi.GetHostCharacter()
    if M.Utils.isToT() and M.Osi.IsEnemy(brawler.uuid, hostCharacterUuid) == 0 and not M.Utils.isPlayerOrAlly(brawler.uuid) then
        debugPrint("setting temporary hostile", brawler.displayName, brawler.uuid, hostCharacterUuid)
        Osi.SetRelationTemporaryHostile(brawler.uuid, hostCharacterUuid)
    end
    if State.Session.Players[brawler.uuid] or (M.Utils.isToT() and Mods.ToT.PersistentVars.Scenario and brawler.uuid == Mods.ToT.PersistentVars.Scenario.CombatHelper) or not M.Utils.canAct(brawler.uuid) then
        debugPrint("don't take turn", brawler.uuid, brawler.displayName)
        return false
    end
    if M.Swarm.isControlledByDefaultAI(brawler.uuid) then
        debugPrint(brawler.displayName, "singleCharacterTurn, is controlled by default AI")
        State.Session.SwarmTurnComplete[brawler.uuid] = true
        return false
    end
    if State.Session.SwarmTurnComplete[brawler.uuid] then
        debugPrint(brawler.displayName, "singleCharacterTurn, swarm turn already complete")
        return false
    end
    State.Session.SwarmBrawlerIndexDelay[brawler.uuid] = Ext.Timer.WaitFor(brawlerIndex*200, function ()
        State.Session.SwarmBrawlerIndexDelay[brawler.uuid] = nil
        if State.Session.SwarmTurnActive then
            debugPrint("initiating swarm action for brawler", brawler.displayName, brawler.uuid, brawlerIndex*200)
            swarmAction(brawler, swarmActors)
        end
    end)
    return true
end

local function startEnemyTurn(swarmActors)
    debugPrint("startEnemyTurn")
    State.Session.BrawlerChunks = {}
    local chunkIndex, brawlersInChunk = 1, 0
    for _, uuid in ipairs(swarmActors) do
        debugPrint("chunk", chunkIndex, M.Utils.getDisplayName(uuid))
        State.Session.BrawlerChunks[chunkIndex] = State.Session.BrawlerChunks[chunkIndex] or {}
        State.Session.BrawlerChunks[chunkIndex][uuid] = M.Roster.getBrawlerByUuid(uuid)
        brawlersInChunk = brawlersInChunk + 1
        if brawlersInChunk >= State.Settings.SwarmChunkSize then
            chunkIndex = chunkIndex + 1
            brawlersInChunk = 0
        end
    end
    startChunk(1, swarmActors)
    -- return chunkIndex
end

-- the FIRST enemy to go uses the built-in AI and takes its turn normally, this keeps the turn open
-- all other enemies go at the same time, using the Brawl AI
-- possible for the first enemy's turn to end early, and then it bleeds over into the player turn, but unusual
local function startSwarmTurn(swarmActors, nonSwarmActors, isBeforePlayer)
    if M.Utils.isToT() and Mods.ToT.PersistentVars.Scenario and Mods.ToT.PersistentVars.Scenario.Round ~= nil and not State.Session.TBSMToTSkippedPrepRound then
        debugPrint("skipping ToT prep round")
        State.Session.TBSMToTSkippedPrepRound = true
        State.Session.SwarmTurnActive = false
        return
    end
    if nonSwarmActors and next(nonSwarmActors) then
        unsetEnemyTurnsComplete(nonSwarmActors)
    end
    if swarmActors and next(swarmActors) then
        debugPrint("startSwarmTurn", isBeforePlayer, #swarmActors)
        for _, uuid in ipairs(swarmActors) do
            debugPrint(M.Utils.getDisplayName(uuid), uuid)
        end
        State.Session.TurnBasedSwarmModePlayerTurnEnded = {}
        State.Session.CanActBeforeDelay = allBrawlersCanAct()
        State.Session.SwarmTurnActive = true
        State.Session.SwarmActors = swarmActors
        State.Session.SwarmTurnIsBeforePlayer = isBeforePlayer
        startEnemyTurn(swarmActors)
    end
end

local function checkAllPlayersFinishedTurns()
    local players = State.Session.Players
    if players then
        for uuid, player in pairs(players) do
            if Utils.hasLoseControlStatus(uuid) then
                State.Session.TurnBasedSwarmModePlayerTurnEnded[uuid] = true
            end
            if player.isFreshSummon then
                player.isFreshSummon = false
                local entity = Ext.Entity.Get(uuid)
                if entity and entity.TurnBased and not entity.TurnBased.IsActiveCombatTurn then
                    State.Session.TurnBasedSwarmModePlayerTurnEnded[uuid] = true
                end
            end
            debugPrint("Checking finished turns", uuid, M.Utils.getDisplayName(uuid), State.Session.TurnBasedSwarmModePlayerTurnEnded[uuid], Utils.isAliveAndCanFight(uuid), Utils.hasLoseControlStatus(uuid))
            if Utils.isAliveAndCanFight(uuid) and not State.Session.TurnBasedSwarmModePlayerTurnEnded[uuid] then
                return false
            end
        end
        return true
    end
    return nil
end

local function getNewInitiativeRolls(groups)
    local newInitiativeRolls = {}
    for _, info in ipairs(groups) do
        if info.Members and info.Members[1] and info.Members[1].Entity then
            table.insert(newInitiativeRolls, getInitiativeRoll(info.Members[1].Entity.Uuid.EntityUuid))
        end
    end
    return newInitiativeRolls
end

local function reorderByInitiativeRoll()
    local combatEntity = Utils.getCombatEntity()
    if combatEntity and combatEntity.TurnOrder and combatEntity.TurnOrder.Groups then
        local reorderedGroups = {}
        for i, newInitiative in ipairs(getNewInitiativeRolls(combatEntity.TurnOrder.Groups)) do
            local group = combatEntity.TurnOrder.Groups[i]
            local members = {}
            for _, member in ipairs(group.Members) do
                table.insert(members, {Entity = member.Entity, Initiative = member.Initiative})
            end
            table.insert(reorderedGroups, {
                Initiative = newInitiative,
                IsPlayer = group.IsPlayer,
                Round = group.Round,
                Team = group.Team,
                Members = members,
            })
        end
        table.sort(reorderedGroups, function (a, b) return a.Initiative > b.Initiative end)
        combatEntity.TurnOrder.Groups = reorderedGroups
        combatEntity:Replicate("TurnOrder")
        -- Utils.forceRefreshTopbar()
    end
end

local function onCombatRoundStarted(round)
    debugPrint("onCombatRoundStarted", round)
    cancelTimers()
    State.Session.SwarmTurnActive = false
    State.Session.QueuedCompanionAIAction = {}
    -- State.Session.ActionsInProgress = {}
    unsetAllEnemyTurnsComplete()
    if not State.Settings.PlayersGoFirst then
        Utils.showAllInitiativeRolls()
        debugPrint("*****onCombatRoundStarted original turn order")
        Utils.showTurnOrderGroups()
        setPartyInitiativeRollToMean()
        bumpNpcInitiativeRolls()
        reorderByInitiativeRoll()
        debugPrint("*****onCombatRoundStarted updated turn order")
        Utils.showTurnOrderGroups()
    end
    local enemyList, excludedEnemyList = getEnemyList(true)
    startSwarmTurn(enemyList, excludedEnemyList, true)
end

local function onCombatEnded()
    State.Session.StoryActionIDs = {}
    State.Session.SwarmTurnComplete = {}
    State.Session.MeanInitiativeRoll = nil
    cancelTimers()
    Leaderboard.dumpToConsole()
    Leaderboard.postDataToClients()
end

local function onEnteredCombat(uuid)
    if uuid and State.Session.Players and State.Session.Players[uuid] then
        debugPrint("initiative roll", getInitiativeRoll(uuid))
        if State.Session.ResurrectedPlayer[uuid] then
            State.Session.ResurrectedPlayer[uuid] = nil
            setInitiativeRoll(uuid, Roster.rollForInitiative(uuid))
            debugPrint("updated initiative roll for resurrected player", getInitiativeRoll(uuid))
            setPartyInitiativeRollToMean()
        end
    end
end

local function onTurnStarted(uuid)
    debugPrint("ON TURN STARTED**********************************", M.Utils.getDisplayName(uuid))
    if uuid and M.Osi.IsPartyMember(uuid, 1) == 1 then
        State.Session.TurnBasedSwarmModePlayerTurnEnded[uuid] = false
        -- unsetTurnComplete(uuid)
        if State.Settings.AutotriggerSwarmModeCompanionAI then
            cancelActionTimers({uuid})
            Pause.queueSingleCompanionAIActions(uuid)
        end
    end
end

local function onTurnEnded(uuid)
    if uuid then
        cancelActionSequenceFailsafeTimer(uuid)
        if State.Session.ActionsInProgress[uuid] and next(State.Session.ActionsInProgress[uuid]) then
            debugPrint(M.Utils.getDisplayName(uuid), "leftover ActionsInProgress", #State.Session.ActionsInProgress[uuid])
            setTurnComplete(uuid)
            State.Session.ActionsInProgress[uuid] = {}
        end
        if M.Roster.getBrawlerByUuid(uuid) then
            if M.Osi.IsPartyMember(uuid, 1) == 1 then
                State.Session.TurnBasedSwarmModePlayerTurnEnded[uuid] = true
                if checkAllPlayersFinishedTurns() then
                    local enemyList, excludedEnemyList = getEnemyList(false)
                    unsetEnemyTurnsComplete(enemyList)
                    startSwarmTurn(enemyList, excludedEnemyList, false)
                end
            else
                debugPrint(M.Utils.getDisplayName(uuid), "onTurnEnded complete swarm turn?")
                -- NB: do we need this???
                -- completeSwarmTurn(uuid, State.Session.SwarmActors)
            end
        end
    end
end

local function onDied(uuid)
    if uuid then
        if State.Session.SwarmTurnComplete[uuid] ~= nil then
            State.Session.SwarmTurnComplete[uuid] = nil
        end
        cancelActionSequenceFailsafeTimer(uuid)
    end
end

local function onResurrected(uuid)
    if uuid and State.Session.Players and State.Session.Players[uuid] then
        State.Session.ResurrectedPlayer[uuid] = true
        State.Session.TurnBasedSwarmModePlayerTurnEnded[uuid] = true
    end
end

local function onCharacterJoinedParty(uuid)
    if uuid then
        if State.Settings.PlayersGoFirst then
            State.boostPlayerInitiative(uuid)
        end
        State.recapPartyMembersMovementDistances()
        State.Session.TurnBasedSwarmModePlayerTurnEnded[uuid] = M.Utils.isPlayerTurnEnded(uuid)
    end
end

local function onTeleportedToCamp(uuid)
    if uuid then
        local level = M.Osi.GetRegion(uuid)
        local brawler = M.Roster.getBrawlerByUuid(uuid)
        if level and brawler then
            Roster.removeBrawler(level, uuid)
            Roster.checkForEndOfBrawl(level)
        end
    end
end

local function onReactionInterruptActionNeeded(uuid)
    if uuid and M.Osi.IsPartyMember(uuid, 1) == 1 then
        pauseTimers()
    end
end

local function onServerInterruptUsed(entity, label, component)
    if component and component.Interrupts then
        for _, interrupt in pairs(component.Interrupts) do
            for interruptEvent, interruptInfo in pairs(interrupt) do
                if interruptEvent.Target and interruptEvent.Target.Uuid and interruptEvent.Target.Uuid.EntityUuid then
                    local targetUuid = interruptEvent.Target.Uuid.EntityUuid
                    debugPrint("interrupted:", M.Utils.getDisplayName(targetUuid), targetUuid)
                    if State.Session.ActionsInProgress[targetUuid] then
                        local brawler = M.Roster.getBrawlerByUuid(targetUuid)
                        if brawler then
                            swarmAction(brawler, State.Session.SwarmActors)
                        end
                    end
                end
            end
        end
    end
end

local function onReactionInterruptUsed(uuid, isAutoTriggered)
    if uuid and M.Osi.IsPartyMember(uuid, 1) == 1 and isAutoTriggered == 0 then
        resumeTimers()
    end
end

-- thank u focus
local function onServerInterruptDecision()
    if Ext.System.ServerInterruptDecision and Ext.System.ServerInterruptDecision.Decisions then
        for _, _ in pairs(Ext.System.ServerInterruptDecision.Decisions) do
            resumeTimers()
        end
    end
end

return {
    getEnemyList = getEnemyList,
    getInitiativeRoll = getInitiativeRoll,
    cancelTimers = cancelTimers,
    resumeTimers = resumeTimers,
    pauseTimers = pauseTimers,
    resetChunkState = resetChunkState,
    setTurnComplete = setTurnComplete,
    unsetTurnComplete = unsetTurnComplete,
    setAllPlayerTurnsComplete = setAllPlayerTurnsComplete,
    setAllEnemyTurnsComplete = setAllEnemyTurnsComplete,
    unsetAllEnemyTurnsComplete = unsetAllEnemyTurnsComplete,
    isExcludedFromSwarmAI = isExcludedFromSwarmAI,
    isControlledByDefaultAI = isControlledByDefaultAI,
    completeSwarmTurn = completeSwarmTurn,
    startSwarmTurn = startSwarmTurn,
    startActionSequenceFailsafeTimer = startActionSequenceFailsafeTimer,
    cancelActionSequenceFailsafeTimer = cancelActionSequenceFailsafeTimer,
    checkAllPlayersFinishedTurns = checkAllPlayersFinishedTurns,
    startEnemyTurn = startEnemyTurn,
    useRemainingActions = useRemainingActions,
    swarmAction = swarmAction,
    Listeners = {
        onCombatRoundStarted = onCombatRoundStarted,
        onCombatEnded = onCombatEnded,
        onEnteredCombat = onEnteredCombat,
        onTurnStarted = onTurnStarted,
        onTurnEnded = onTurnEnded,
        onDied = onDied,
        onResurrected = onResurrected,
        onCharacterJoinedParty = onCharacterJoinedParty,
        onTeleportedToCamp = onTeleportedToCamp,
        onReactionInterruptActionNeeded = onReactionInterruptActionNeeded,
        onServerInterruptUsed = onServerInterruptUsed,
        onReactionInterruptUsed = onReactionInterruptUsed,
        onServerInterruptDecision = onServerInterruptDecision,
    },
}
