local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump

local function stopPulseAction(brawler, remainInBrawl)
    if brawler and brawler.uuid then
        debugPrint("Stop Pulse Action for brawler", brawler.uuid, brawler.displayName)
        if not remainInBrawl then
            brawler.isInBrawl = false
        end
        if State.Session.PulseActionTimers[brawler.uuid] ~= nil then
            debugPrint("stop pulse action", brawler.displayName, remainInBrawl)
            Ext.Timer.Cancel(State.Session.PulseActionTimers[brawler.uuid])
            State.Session.PulseActionTimers[brawler.uuid] = nil
        end
    end
end

local function stopAllPulseActions(remainInBrawl)
    for uuid, timer in pairs(State.Session.PulseActionTimers) do
        stopPulseAction(M.Roster.getBrawlerByUuid(uuid), remainInBrawl)
    end
end

local function pulseAction(brawler)
    if brawler and brawler.uuid then
        -- debugPrint("pulseAction", brawler.displayName, bonusActionOnly)
        if not Utils.canAct(brawler.uuid) or brawler.isPaused or State.isPlayerControllingDirectly(brawler.uuid) and not State.Settings.FullAuto then
            return stopPulseAction(brawler)
        end
        if not State.Settings.TurnBasedSwarmMode then
            Roster.addPlayersInEnterCombatRangeToBrawlers(brawler.uuid)
        end
        AI.act(brawler)
    end
end

-- NB: get rid of this...?
local function pulseReposition(level)
    State.checkForDownedOrDeadPlayers()
    if not State.Settings.TurnBasedSwarmMode then
        for uuid, _ in pairs(M.Roster.getBrawlers()) do
            if not Constants.IS_TRAINING_DUMMY[uuid] then
                if M.Osi.IsDead(uuid) == 1 or M.Utils.isDowned(uuid) then
                    Utils.clearOsirisQueue(uuid)
                    Osi.LieOnGround(uuid)
                end
            end
        end
    end
end

local function startPulseAction(brawler)
    if M.Osi.IsPlayer(brawler.uuid) == 1 and not State.Settings.CompanionAIEnabled then
        return false
    end
    if Constants.IS_TRAINING_DUMMY[brawler.uuid] then
        return false
    end
    if State.Session.PulseActionTimers[brawler.uuid] == nil then
        brawler.isInBrawl = true
        debugPrint("Starting pulse action", brawler.displayName, brawler.uuid, brawler.actionInterval)
        State.Session.PulseActionTimers[brawler.uuid] = Ext.Timer.WaitFor(0, function ()
            pulseAction(brawler)
        end, brawler.actionInterval)
    end
end

local function stopPulseAddNearby(uuid)
    debugPrint("stopPulseAddNearby", uuid, M.Utils.getDisplayName(uuid))
    if State.Session.PulseAddNearbyTimers[uuid] ~= nil then
        Ext.Timer.Cancel(State.Session.PulseAddNearbyTimers[uuid])
        State.Session.PulseAddNearbyTimers[uuid] = nil
    end
end

local function startPulseAddNearby(uuid)
    debugPrint("startPulseAddNearby", uuid, Utils.getDisplayName(uuid))
    if State.Session.PulseAddNearbyTimers[uuid] == nil then
        State.Session.PulseAddNearbyTimers[uuid] = Ext.Timer.WaitFor(0, function ()
            Roster.addNearbyEnemiesToBrawlers(uuid, 30)
        end, 7500)
    end
end

local function stopPulseReposition()
    debugPrint("stopPulseReposition")
    for level, timer in pairs(State.Session.PulseRepositionTimers) do
        Ext.Timer.Cancel(timer)
        State.Session.PulseRepositionTimers[level] = nil
    end
end

local function startPulseReposition(level)
    if State.Session.PulseRepositionTimers[level] == nil then
        debugPrint("startPulseReposition", level)
        State.Session.PulseRepositionTimers[level] = Ext.Timer.WaitFor(0, function ()
            pulseReposition(level)
        end, Constants.REPOSITION_INTERVAL)
    end
end

local function stopAllPulseAddNearbyTimers()
    local pulseAddNearbyTimers = State.Session.PulseAddNearbyTimers
    for _, timer in pairs(pulseAddNearbyTimers) do
        Ext.Timer.Cancel(timer)
    end
    -- State.Session.PulseAddNearbyTimers = {}
end

local function stopAllPulseRepositionTimers()
    local pulseRepositionTimers = State.Session.PulseRepositionTimers
    for _, timer in pairs(pulseRepositionTimers) do
        Ext.Timer.Cancel(timer)
    end
    -- State.Session.PulseRepositionTimers = {}
end

local function stopAllPulseActionTimers()
    local pulseActionTimers = State.Session.PulseActionTimers
    for _, timer in pairs(pulseActionTimers) do
        Ext.Timer.Cancel(timer)
    end
    -- State.Session.PulseActionTimers = {}
end

local function pauseCombatRoundTimer(combatGuid)
    if State.Session.CombatRoundTimer and State.Session.CombatRoundTimer[combatGuid] then
        Ext.Timer.Pause(State.Session.CombatRoundTimer[combatGuid])
    end
end

local function resumeCombatRoundTimer(combatGuid)
    if State.Session.CombatRoundTimer and State.Session.CombatRoundTimer[combatGuid] then
        Ext.Timer.Resume(State.Session.CombatRoundTimer[combatGuid])
    end
end

local function cancelCombatRoundTimer(combatGuid)
    if State.Session.CombatRoundTimer and State.Session.CombatRoundTimer[combatGuid] then
        Ext.Timer.Cancel(State.Session.CombatRoundTimer[combatGuid])
        State.Session.CombatRoundTimer[combatGuid] = nil
    end
end

local function pauseCombatRoundTimers()
    if State.Session.CombatRoundTimer and next(State.Session.CombatRoundTimer) then
        for combatGuid, timer in pairs(State.Session.CombatRoundTimer) do
            Ext.Timer.Pause(timer)
        end
    end
end

local function resumeCombatRoundTimers()
    if State.Session.CombatRoundTimer and next(State.Session.CombatRoundTimer) then
        for combatGuid, timer in pairs(State.Session.CombatRoundTimer) do
            Ext.Timer.Resume(timer)
        end
    end
end

local function cancelCombatRoundTimers()
    if State.Session.CombatRoundTimer and next(State.Session.CombatRoundTimer) then
        for combatGuid, timer in pairs(State.Session.CombatRoundTimer) do
            Ext.Timer.Cancel(timer)
            State.Session.CombatRoundTimer[combatGuid] = nil
        end
    end
end

local function joinCombat(uuid)
    local combatEntity = Utils.getCombatEntity()
    if combatEntity and combatEntity.ServerEnterRequest and combatEntity.ServerEnterRequest.EnterRequests then
        local entity = Ext.Entity.Get(uuid)
        if entity and M.Osi.CanJoinCombat(uuid) == 1 and M.Osi.IsInCombat(uuid) == 0 then
            combatEntity.ServerEnterRequest.EnterRequests[entity] = true
        end
    end
end

-- NB: is the wrapping timer getting paused correctly during pause?
local function nextCombatRound()
    print("nextCombatRound")
    State.Session.IsNextCombatRoundQueued = false
    if State.areAnyPlayersTargeting() then
        State.Session.IsNextCombatRoundQueued = true
    elseif not Pause.isPartyInFTB() then
        Ext.ServerNet.BroadcastMessage("NextCombatRound", "")
        for uuid, _ in pairs(M.Roster.getBrawlers()) do
            local entity = Ext.Entity.Get(uuid)
            if entity and entity.TurnBased then
                if M.Osi.IsPartyMember(uuid, 1) == 0 then
                    entity.TurnBased.HadTurnInCombat = true
                    entity.TurnBased.TurnActionsCompleted = true
                end
                entity.TurnBased.RequestedEndTurn = true
                entity:Replicate("TurnBased")
            end
        end
    end
end

local function startCombatRoundTimer(combatGuid)
    -- if not State.isInCombat() then
    --     Osi.PauseCombat(combatGuid)
    -- end
    local turnDuration = State.Settings.ActionInterval*1000
    if not Utils.isToT() then
        State.Session.CombatRoundTimer[combatGuid] = Ext.Timer.WaitFor(turnDuration, nextCombatRound)
    else
        State.Session.CombatRoundTimer[combatGuid] = Ext.Timer.WaitFor(turnDuration, function ()
            nextCombatRound()
            if Mods.ToT.PersistentVars.Scenario and Mods.ToT.PersistentVars.Scenario.Round < #Mods.ToT.PersistentVars.Scenario.Timeline then
                debugPrint("ToT advancing scenario", Mods.ToT.PersistentVars.Scenario.Round, #Mods.ToT.PersistentVars.Scenario.Timeline)
                Mods.ToT.Scenario.ForwardCombat()
            end
        end)
    end
end

local function onStarted()
    State.disableDynamicCombatCamera()
    State.uncapPartyMembersMovementDistances()
    Pause.checkTruePauseParty()
end

local function onCombatStarted(combatGuid)
    if not Utils.isToT() then
        TurnOrder.spawnCombatHelper(combatGuid)
        if State.Settings.AutoPauseOnCombatStart then
            Pause.allEnterFTB()
        end
        TurnOrder.setPlayersSwarmGroup()
        TurnOrder.setPartyInitiativeRollToMean()
        TurnOrder.bumpDirectlyControlledInitiativeRolls()
        TurnOrder.reorderByInitiativeRoll(true)
        TurnOrder.setPlayerTurnsActive()
    end
end

local function onCombatRoundStarted(combatGuid, round)
    if Pause.isPartyInFTB() then
        print("party is in FTB, pausing underlying combat", combatGuid, round)
        return Osi.PauseCombat(combatGuid)
    end
    Ext.ServerNet.BroadcastMessage("CombatRoundStarted", "")
    if not State.Session.CombatHelper then
        print("ERROR No combat helper found, what happened?")
        TurnOrder.spawnCombatHelper(combatGuid)
    end
    for faction, enemyUuid in pairs(Utils.getEnemyFactions()) do
        print("combat helper set hostile to enemy faction", faction, enemyUuid, M.Utils.getDisplayName(enemyUuid))
        Osi.SetHostileAndEnterCombat(Constants.COMBAT_HELPER.faction, faction, State.Session.CombatHelper, enemyUuid)
    end
    Ext.Timer.WaitFor(1000, function ()
        if State.Session.CombatHelper then
            Osi.EndTurn(State.Session.CombatHelper)
        end
    end)
    startCombatRoundTimer(combatGuid)
    -- NB: remove this?? check if needed for ToT endround
    -- if M.Utils.isToT() then
    --     startToTTimers(combatGuid)
    --     local helperUuid = State.getToTCombatHelper()
    --     if helperUuid then
    --         local helperEntity = Ext.Entity.Get(helperUuid)
    --         if helperEntity and helperEntity.TurnBased then
    --             helperEntity.TurnBased.HadTurnInCombat = true
    --             helperEntity.TurnBased.RequestedEndTurn = true
    --             helperEntity.TurnBased.TurnActionsCompleted = true
    --             helperEntity:Replicate("TurnBased")
    --         end
    --     end
    -- else
    --     onCombatStarted(combatGuid)
    -- end
end

local function onCombatEnded(combatGuid)
    cancelCombatRoundTimer(combatGuid)
    local host = M.Osi.GetHostCharacter()
    if host then
        local level = M.Osi.GetRegion(host)
        if level then
            Roster.endBrawl(level)
        end
    end
end

local function onEnteredCombat(uuid)
    local combatEntity = Utils.getCombatEntity()
    if combatEntity and combatEntity.CombatState and combatEntity.CombatState.Participants then
        for _, participant in ipairs(combatEntity.CombatState.Participants) do
            local entity = Ext.Entity.Get(uuid)
            if entity and entity.TurnBased then
                if State.Session.Players[participant.Uuid.EntityUuid] then
                    entity.TurnBased.IsActiveCombatTurn = true
                else
                    entity.TurnBased.IsActiveCombatTurn = false
                end
                entity:Replicate("TurnBased")
            end
        end
    end
end

local function onEnteredForceTurnBased(entityUuid)
    if entityUuid then
        debugPrint("EnteredForceTurnBased", M.Utils.getDisplayName(entityUuid))
        local level = M.Osi.GetRegion(entityUuid)
        if level then
            local brawler = Roster.getBrawlerByUuid(entityUuid)
            if brawler then
                Resources.pauseActionResourcesRefillTimers(brawler)
            end
            local isPlayer = State.Session.Players and State.Session.Players[entityUuid]
            if isPlayer then
                local isHostCharacter = entityUuid == M.Osi.GetHostCharacter()
                if State.Session.Players[entityUuid].isFreshSummon then
                    State.Session.Players[entityUuid].isFreshSummon = false
                    return Osi.ForceTurnBasedMode(entityUuid, 0)
                end
                if State.Session.AwaitingTarget[entityUuid] then
                    Commands.setAwaitingTarget(entityUuid, false)
                end
                Quests.stopCountdownTimer(entityUuid)
                if brawler then
                    brawler.isInBrawl = false
                end
                stopPulseAddNearby(entityUuid)
                if isHostCharacter then
                    stopPulseReposition(level)
                    if brawler and brawler.combatGuid then
                        pauseCombatRoundTimer(brawler.combatGuid)
                    end
                end
            end
            if M.Utils.isAliveAndCanFight(entityUuid) then
                Utils.clearOsirisQueue(entityUuid)
                if State.Settings.TruePause then
                    Pause.startTruePause(entityUuid)
                end
            end
            if isPlayer then
                for brawlerUuid, b in pairs(M.Roster.getBrawlers()) do
                    if not b.isPaused then
                        debugPrint("stopping pulse for", b.uuid, b.displayName)
                        stopPulseAction(b, true)
                        b.isPaused = true
                        Osi.ForceTurnBasedMode(brawlerUuid, 1)
                    end
                end
            end
        end
    end
end

local function onLeftForceTurnBased(entityUuid)
    if entityUuid then
        debugPrint("LeftForceTurnBased", M.Utils.getDisplayName(entityUuid))
        local level = M.Osi.GetRegion(entityUuid)
        if level then
            local brawler = Roster.getBrawlerByUuid(entityUuid)
            if brawler then
                Resources.resumeActionResourcesRefillTimers(brawler)
                joinCombat(entityUuid)
            end
            if State.Session.Players and State.Session.Players[entityUuid] then
                if State.Session.Players[entityUuid].isFreshSummon then
                    State.Session.Players[entityUuid].isFreshSummon = false
                end
                Quests.resumeCountdownTimer(entityUuid)
                if State.Session.FTBLockedIn[entityUuid] ~= nil then
                    State.Session.FTBLockedIn[entityUuid] = nil
                end
                State.Session.RemainingMovement[entityUuid] = nil
                if brawler then
                    brawler.isInBrawl = false
                    if State.isPlayerControllingDirectly(entityUuid) then
                        startPulseAddNearby(entityUuid)
                    end
                end
                local isHostCharacter = entityUuid == M.Osi.GetHostCharacter()
                if isHostCharacter then
                    startPulseReposition(level)
                end
                -- NB: should this logic all be in Pause.lua instead? can it get triggered incorrectly? (e.g. downed players?)
                if State.areAnyPlayersBrawling() then
                    if isHostCharacter and brawler and brawler.combatGuid then
                        resumeCombatRoundTimer(brawler.combatGuid)
                    end
                    for brawlerUuid, b in pairs(M.Roster.getBrawlers()) do
                        if State.Session.Players[brawlerUuid] then
                            if not State.isPlayerControllingDirectly(brawlerUuid) or State.Settings.FullAuto then
                                startPulseAction(b)
                            end
                            b.isPaused = false
                            if brawlerUuid ~= entityUuid then
                                debugPrint("setting fTB to 0 for", brawlerUuid, entityUuid)
                                Osi.ForceTurnBasedMode(brawlerUuid, 0)
                            end
                        else
                            startPulseAction(brawler)
                        end
                    end
                end
                local entity = Ext.Entity.Get(entityUuid)
                if entity and entity.TurnBased then
                    entity.TurnBased.IsActiveCombatTurn = true
                    entity.TurnBased.HadTurnInCombat = false
                    entity.TurnBased.RequestedEndTurn = false
                    entity.TurnBased.TurnActionsCompleted = false
                    entity:Replicate("TurnBased")
                end
            else
                local entity = Ext.Entity.Get(entityUuid)
                if entity and entity.TurnBased then
                    entity.TurnBased.IsActiveCombatTurn = false
                    entity.TurnBased.HadTurnInCombat = true
                    entity.TurnBased.RequestedEndTurn = true
                    entity.TurnBased.TurnActionsCompleted = true
                    entity:Replicate("TurnBased")
                end
            end
        end
    end
end

local function onGainedControl(uuid)
    startPulseAddNearby(uuid)
    local userId = Osi.GetReservedUserID(uuid)
    for playerUuid, player in pairs(State.Session.Players) do
        if player.userId == userId and playerUuid ~= uuid then
            stopPulseAddNearby(playerUuid)
            local brawler = Roster.getBrawlerByUuid(playerUuid)
            if brawler and brawler.isInBrawl then
                startPulseAction(brawler)
            end
        end
    end
    TurnOrder.setPartyInitiativeRollToMean()
    TurnOrder.bumpDirectlyControlledInitiativeRolls()
    TurnOrder.reorderByInitiativeRoll(true)
    TurnOrder.setPlayerTurnsActive()
end

local function onSpellSyncTargeting(spellCastState)
    if spellCastState and spellCastState.Caster and spellCastState.Caster.Uuid.EntityUuid then
        State.Session.PlayerTargetingSpellCast[spellCastState.Caster.Uuid.EntityUuid] = true
    end
end

local function onDestroySpellSyncTargeting(spellCastState)
    if spellCastState and spellCastState.Caster and spellCastState.Caster.Uuid.EntityUuid then
        State.Session.PlayerTargetingSpellCast[spellCastState.Caster.Uuid.EntityUuid] = nil
        if State.Session.IsNextCombatRoundQueued then
            nextCombatRound()
        end
    end
end

local function onDialogStarted()
    debugPrint("DialogStarted")
    local level = M.Osi.GetRegion(M.Osi.GetHostCharacter())
    if level then
        stopPulseReposition(level)
    end
    for uuid, brawler in pairs(M.Roster.getBrawlers()) do
        stopPulseAction(brawler, true)
        Utils.clearOsirisQueue(uuid)
    end
end

local function onDialogEnded()
    debugPrint("DialogEnded")
    local level = M.Osi.GetRegion(M.Osi.GetHostCharacter())
    if level then
        startPulseReposition(level)
    end
    for uuid, brawler in pairs(M.Roster.getBrawlers()) do
        if brawler.isInBrawl and not State.isPlayerControllingDirectly(uuid) then
            startPulseAction(brawler)
        end
    end
end

-- NB: fix this, shouldn't remove all, don't need to iterate over levels
local function onTeleportedToCamp(uuid)
    if uuid ~= nil and State.Session.Brawlers ~= nil then
        for level, brawlersInLevel in pairs(State.Session.Brawlers) do
            if brawlersInLevel[uuid] ~= nil then
                Roster.removeBrawler(level, uuid)
                Roster.checkForEndOfBrawl(level)
            end
        end
    end
end

-- thank u focus
-- NB: can get rid of this??
local function onPROC_Subregion_Entered(uuid)
    if uuid then
        debugPrint("PROC_Subregion_Entered", M.Utils.getDisplayName(uuid))
        local level = M.Osi.GetRegion(uuid)
        if level and uuid and State.Session.Players and State.Session.Players[uuid] then
            pulseReposition(level)
        end
    end
end

return {
    joinCombat = joinCombat,
    nextCombatRound = nextCombatRound,
    Timers = {
        stopPulseAction = stopPulseAction,
        stopAllPulseActions = stopAllPulseActions,
        startPulseAction = startPulseAction,
        stopPulseAddNearby = stopPulseAddNearby,
        startPulseAddNearby = startPulseAddNearby,
        stopPulseReposition = stopPulseReposition,
        startPulseReposition = startPulseReposition,
        stopAllPulseAddNearbyTimers = stopAllPulseAddNearbyTimers,
        stopAllPulseRepositionTimers = stopAllPulseRepositionTimers,
        stopAllPulseActionTimers = stopAllPulseActionTimers,
        pauseCombatRoundTimer = pauseCombatRoundTimer,
        resumeCombatRoundTimer = resumeCombatRoundTimer,
        cancelCombatRoundTimer = cancelCombatRoundTimer,
        pauseCombatRoundTimers = pauseCombatRoundTimers,
        resumeCombatRoundTimers = resumeCombatRoundTimers,
        cancelCombatRoundTimers = cancelCombatRoundTimers,
        startCombatRoundTimer = startCombatRoundTimer,
    },
    Listeners = {
        onStarted = onStarted,
        onCombatStarted = onCombatStarted,
        onCombatRoundStarted = onCombatRoundStarted,
        onCombatEnded = onCombatEnded,
        onEnteredCombat = onEnteredCombat,
        onEnteredForceTurnBased = onEnteredForceTurnBased,
        onLeftForceTurnBased = onLeftForceTurnBased,
        onGainedControl = onGainedControl,
        onSpellSyncTargeting = onSpellSyncTargeting,
        onDestroySpellSyncTargeting = onDestroySpellSyncTargeting,
        onDialogStarted = onDialogStarted,
        onDialogEnded = onDialogEnded,
        onTeleportedToCamp = onTeleportedToCamp,
        onPROC_Subregion_Entered = onPROC_Subregion_Entered,
    },
}
