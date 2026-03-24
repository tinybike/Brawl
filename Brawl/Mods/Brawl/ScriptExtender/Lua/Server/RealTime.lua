local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump

local function getCombatRoundDuration()
    return State.Settings.CombatRoundDuration*1000
end

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
    local uuids = {}
    for uuid, _ in pairs(State.Session.PulseActionTimers) do
        table.insert(uuids, uuid)
    end
    for _, uuid in ipairs(uuids) do
        stopPulseAction(M.Roster.getBrawlerByUuid(uuid), remainInBrawl)
    end
end

local function pulseAction(brawler)
    if brawler and brawler.uuid then
        if not Utils.canAct(brawler.uuid) or brawler.isPaused or (State.isPlayerControllingDirectly(brawler.uuid) and not State.Settings.FullAuto) then
            return
        end
        if not State.Settings.TurnBasedSwarmMode then
            Roster.addPlayersInEnterCombatRangeToBrawlers(brawler.uuid)
        end
        AI.act(brawler)
    end
end

local function startPulseAction(brawler, initialDelay)
    if State.Session.Players[brawler.uuid] and not State.Settings.CompanionAIEnabled then
        return false
    end
    if Constants.IS_TRAINING_DUMMY[brawler.uuid] then
        return false
    end
    if State.Session.PulseActionTimers[brawler.uuid] == nil then
        brawler.isInBrawl = true
        debugPrint("Starting pulse action", brawler.displayName, brawler.uuid, brawler.actionInterval)
        State.Session.PulseActionTimers[brawler.uuid] = Ext.Timer.WaitFor(initialDelay or 0, function ()
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

local function stopAllPulseAddNearbyTimers()
    for _, timer in pairs(State.Session.PulseAddNearbyTimers) do
        Ext.Timer.Cancel(timer)
    end
    State.Session.PulseAddNearbyTimers = {}
end

local function stopAllPulseActionTimers()
    for _, timer in pairs(State.Session.PulseActionTimers) do
        Ext.Timer.Cancel(timer)
    end
    State.Session.PulseActionTimers = {}
end

local function pauseCombatRoundTimer(combatGuid)
    State.Session.IsNextCombatRoundQueued = false
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
    State.Session.IsNextCombatRoundQueued = false
    if State.Session.CombatRoundTimer and State.Session.CombatRoundTimer[combatGuid] then
        Ext.Timer.Cancel(State.Session.CombatRoundTimer[combatGuid])
        State.Session.CombatRoundTimer[combatGuid] = nil
    end
end

local function pauseCombatRoundTimers()
    State.Session.IsNextCombatRoundQueued = false
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
    State.Session.IsNextCombatRoundQueued = false
    if State.Session.CombatRoundTimer and next(State.Session.CombatRoundTimer) then
        for combatGuid, timer in pairs(State.Session.CombatRoundTimer) do
            Ext.Timer.Cancel(timer)
        end
        State.Session.CombatRoundTimer = {}
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
    debugPrint("nextCombatRound")
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
                    entity.TurnBased.RequestedEndTurn = true
                    entity.TurnBased.TurnActionsCompleted = true
                else
                    entity.TurnBased.RequestedEndTurn = true
                    if Utils.canAct(uuid) then
                        entity.TurnBased.IsActiveCombatTurn = true
                    end
                end
                entity:Replicate("TurnBased")
            end
        end
    end
end

-- NB: pause timer during interrupts
local function startCombatRoundTimer(combatGuid)
    -- if not State.isInCombat() then
    --     Osi.PauseCombat(combatGuid)
    -- end
    cancelCombatRoundTimer(combatGuid)
    if not Utils.isToT() then
        State.Session.CombatRoundTimer[combatGuid] = Ext.Timer.WaitFor(getCombatRoundDuration(), nextCombatRound)
    else
        State.Session.CombatRoundTimer[combatGuid] = Ext.Timer.WaitFor(getCombatRoundDuration(), function ()
            nextCombatRound()
            if Mods.ToT.PersistentVars.Scenario and Mods.ToT.PersistentVars.Scenario.Round < #Mods.ToT.PersistentVars.Scenario.Timeline then
                debugPrint("ToT advancing scenario", Mods.ToT.PersistentVars.Scenario.Round, #Mods.ToT.PersistentVars.Scenario.Timeline)
                Mods.ToT.Scenario.ForwardCombat()
            end
        end)
    end
end

local function hasEnemyBrawlers()
    for uuid, brawler in pairs(M.Roster.getBrawlers()) do
        if M.Osi.IsPlayer(uuid) == 0 and M.Utils.isPugnacious(uuid) then
            return true
        end
    end
    return false
end

local function initializeCombat(combatGuid)
    if not State.Session.CombatHelper then
        debugPrint("initializeCombat: enemies present, spawning combat helper")
        TurnOrder.spawnCombatHelper(combatGuid)
        TurnOrder.setPlayersSwarmGroup()
        TurnOrder.setPartyInitiativeRollToMean()
        TurnOrder.bumpDirectlyControlledInitiativeRolls()
        TurnOrder.reorderByInitiativeRoll(true)
        TurnOrder.setPlayerTurnsActive()
    end
end

local function onStarted()
    State.disableDynamicCombatCamera()
    State.uncapMovementDistances()
    Pause.checkTruePauseParty()
end

local function onCombatStarted(combatGuid)
    if not Utils.isToT() then
        State.uncapMovementDistances()
        -- If enemies are already in the combat participants list (normal case),
        -- initialize immediately.  Otherwise, onEnteredCombat will handle it.
        if hasEnemyBrawlers() then
            initializeCombat(combatGuid)
        end
    end
end

local function onCombatRoundStarted(combatGuid, round)
    if Pause.isPartyInFTB() then
        print("party is in FTB, pausing underlying combat", combatGuid, round)
        return Osi.PauseCombat(combatGuid)
    end
    Ext.ServerNet.BroadcastMessage("CombatRoundStarted", "")
    if not M.Utils.isToT() then
        if not State.Session.CombatHelper then
            print("No combat helper found, what happened?")
            -- TurnOrder.spawnCombatHelper(combatGuid)
        end
        for faction, enemyUuid in pairs(Utils.getEnemyFactions()) do
            debugPrint("combat helper set hostile to enemy faction", faction, enemyUuid, M.Utils.getDisplayName(enemyUuid))
            if enemyUuid and faction and State.Session.CombatHelper then
                Osi.SetHostileAndEnterCombat(Constants.COMBAT_HELPER.faction, faction, State.Session.CombatHelper, enemyUuid)
            end
        end
        Ext.Timer.WaitFor(1000, function ()
            if State.Session.CombatHelper then
                Osi.EndTurn(State.Session.CombatHelper)
            end
        end)
    end
    for uuid, _ in pairs(M.Roster.getBrawlers()) do
        Swarm.unsetTurnComplete(uuid)
    end
    for uuid, _ in pairs(State.Session.Players) do
        local entity = Ext.Entity.Get(uuid)
        if entity and entity.TurnBased then
            entity.TurnBased.RequestedEndTurn = false
            entity:Replicate("TurnBased")
        end
    end
    startCombatRoundTimer(combatGuid)
    if State.Settings.AutoPauseOnCombatStart and round == 1 then
        Pause.allEnterFTB()
    end
end

local function onCombatEnded(combatGuid)
    cancelCombatRoundTimer(combatGuid)
    TurnOrder.stopListeners(combatGuid)
    Ext.Timer.WaitFor(1500, function()
        if not State.isInCombat() then
            State.endBrawls()
        end
    end)
end

local function onEnteredCombat(uuid)
    local entity = Ext.Entity.Get(uuid)
    if entity and entity.TurnBased then
        if State.Session.Players[uuid] then
            entity.TurnBased.IsActiveCombatTurn = true
        else
            entity.TurnBased.RequestedEndTurn = true
        end
        entity:Replicate("TurnBased")
    end
    State.uncapMovementDistance(uuid)
    -- Deferred combat helper spawn: if this is the first enemy entering combat and we haven't initialized yet, do it now
    if not State.Session.CombatHelper and M.Osi.IsPlayer(uuid) == 0 and M.Utils.isPugnacious(uuid) then
        local combatGuid = M.Osi.CombatGetGuidFor(uuid)
        if combatGuid then
            initializeCombat(combatGuid)
        end
    end
end

local function onGainedControl(uuid)
    debugPrint("onGainedControl", M.Utils.getDisplayName(uuid))
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
    startPulseAddNearby(uuid)
    if not State.Session.MeanInitiativeRoll then
       TurnOrder.setPartyInitiativeRollToMean()
    end
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
    for uuid, brawler in pairs(M.Roster.getBrawlers()) do
        stopPulseAction(brawler, true)
        Utils.clearOsirisQueue(uuid)
    end
end

local function onDialogEnded()
    debugPrint("DialogEnded")
    for uuid, brawler in pairs(M.Roster.getBrawlers()) do
        if brawler.isInBrawl and not State.isPlayerControllingDirectly(uuid) then
            startPulseAction(brawler, Constants.INITIAL_PULSE_ACTION_DELAY)
        end
    end
end

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

local function onFlagSet(flag)
    debugPrint("FlagSet", flag)
    if flag == "HAV_LiftingTheCurse_State_HalsinInShadowfell_480305fb-7b0b-4267-aab6-0090ddc12322" then
        Quests.halsinPortalEvent()
    elseif flag == "HAG_Hag_State_ReadyForLair_658c4d09-b278-42dd-8f72-b98ec3efd0d5" then
        Quests.hagTeahouseEvent()
    elseif flag == "TUT_Helm_JoinedMindflayerFight_ec25d7dc-f9d6-47ff-92c9-8921d6e32f54" then
        Quests.nautiloidTransponderEvent()
    elseif flag == "TUT_Helm_State_TutorialEnded_55073953-23b9-448c-bee8-4c44d3d67b6b" then
        State.endBrawls()
    elseif flag == "DEN_RaidingParty_Event_GateIsOpened_735e0e81-bd67-eb67-87ac-40da4c3e6c49" then
        State.endBrawls()
    end
end

local function onReactionInterruptActionNeeded(uuid)
    if uuid and M.Osi.IsPartyMember(uuid, 1) == 1 then
        pauseCombatRoundTimers()
        -- pausePulseActions()
    end
end

local function onReactionInterruptUsed(uuid, isAutoTriggered)
    if uuid and M.Osi.IsPartyMember(uuid, 1) == 1 and isAutoTriggered == 0 then
        resumeCombatRoundTimers()
        -- resumePulseActions()
    end
end

-- thank u focus
local function onServerInterruptDecision()
    if Ext.System.ServerInterruptDecision and Ext.System.ServerInterruptDecision.Decisions then
        for _, _ in pairs(Ext.System.ServerInterruptDecision.Decisions) do
            resumeCombatRoundTimers()
            -- resumePulseActions()
            return
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
        stopAllPulseAddNearbyTimers = stopAllPulseAddNearbyTimers,
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
        onGainedControl = onGainedControl,
        onSpellSyncTargeting = onSpellSyncTargeting,
        onDestroySpellSyncTargeting = onDestroySpellSyncTargeting,
        onDialogStarted = onDialogStarted,
        onDialogEnded = onDialogEnded,
        onTeleportedToCamp = onTeleportedToCamp,
        onFlagSet = onFlagSet,
        onReactionInterruptActionNeeded = onReactionInterruptActionNeeded,
        onReactionInterruptUsed = onReactionInterruptUsed,
        onServerInterruptDecision = onServerInterruptDecision,
    },
}
