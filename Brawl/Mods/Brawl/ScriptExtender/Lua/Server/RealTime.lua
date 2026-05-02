local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump

-- Send a SelectCharacter NetMessage to whichever user owns this character.
-- Falls back to broadcast if we don't have a cached userId. Multiplayer-safe:
-- avoids broadcasting a "select X" message to all clients (which would tell
-- other users' clients to switch their own selection too).
local function sendSelectCharacter(uuid)
    if not uuid then
        return
    end
    local userId = State.Session.Players[uuid] and State.Session.Players[uuid].userId
    if userId then
        Ext.ServerNet.PostMessageToUser(userId, "SelectCharacter", uuid)
    else
        Ext.ServerNet.BroadcastMessage("SelectCharacter", uuid)
    end
end

local function getCombatRoundDuration()
    return State.Settings.CombatRoundDuration*1000
end

local function stopPulseAction(brawler)
    if brawler and brawler.uuid then
        if State.Session.PulseActionTimers[brawler.uuid] ~= nil then
            debugPrint("stop pulse action", brawler.displayName)
            Ext.Timer.Cancel(State.Session.PulseActionTimers[brawler.uuid])
            State.Session.PulseActionTimers[brawler.uuid] = nil
        end
    end
end

local function stopAllPulseActions()
    local uuids = {}
    for uuid, _ in pairs(State.Session.PulseActionTimers) do
        table.insert(uuids, uuid)
    end
    for _, uuid in ipairs(uuids) do
        stopPulseAction(M.Roster.getBrawlerByUuid(uuid))
    end
end

local function pulseAction(brawler)
    if brawler and brawler.uuid then
        -- If a "strict move" is happening (e.g., On Me, Move Party) then the pulse must not engage while a user-issued strict move is in flight.
        -- Clears once the movement exits ActiveMovements (natural arrival, timeout, or force-clear).
        if brawler.suppressPulseEventUuid then
            if State.Session.ActiveMovements[brawler.suppressPulseEventUuid] then
                return
            end
            brawler.suppressPulseEventUuid = nil
        end
        if not Utils.canAct(brawler.uuid) or brawler.isPaused or (State.isPlayerControllingDirectly(brawler.uuid) and not State.Settings.FullAuto) then
            return
        end
        -- Debug toggle: skip pulse actions for non-player brawlers when DisableEnemyAI is set.  Useful for status-tick testing without dying.
        if State.Settings.DisableEnemyAI and M.Osi.IsPlayer(brawler.uuid) == 0 then
            return
        end
        -- NPC brawlers in the table should always be in combat with the combat helper. Safety net against stale brawlers.
        -- Players go out of IsInCombat during FTB/pause, so this gate is NPC-only.
        if M.Osi.IsPlayer(brawler.uuid) == 0 and M.Osi.IsInCombat(brawler.uuid) == 0 then
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
        debugPrint("Starting pulse action", brawler.displayName, brawler.uuid, brawler.actionInterval)
        State.Session.PulseActionTimers[brawler.uuid] = Ext.Timer.WaitFor(initialDelay or 0, function ()
            pulseAction(brawler)
        end, brawler.actionInterval)
    end
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
    State.Session.IsNextCombatRoundQueued = false
    if State.areAnyPlayersTargeting() then
        State.Session.IsNextCombatRoundQueued = true
    elseif not Pause.isPartyInFTB() then
        -- Snapshot per-user currently-controlled chars before the round-turnover mutations.  Prefer live ClientControl entities; fall back to
        -- the LastControlledUuid map for any user whose ClientControl is mid-flux.  Stored as {[userId] = uuid}.
        local intendedByUser = {}
        local controlEntities = Ext.Entity.GetAllEntitiesWithComponent("ClientControl")
        for _, entity in ipairs(controlEntities or {}) do
            local userId = entity.UserReservedFor and entity.UserReservedFor.UserID
            local entityUuid = entity.Uuid and entity.Uuid.EntityUuid
            if userId and entityUuid then
                intendedByUser[userId] = entityUuid
            end
        end
        if State.Session.LastControlledUuid then
            for userId, uuid in pairs(State.Session.LastControlledUuid) do
                if not intendedByUser[userId] then
                    intendedByUser[userId] = uuid
                end
            end
        end
        -- Pre-emptive: re-affirm SelectCharacter for each user's intended char right before the round-turnover mutations.
        for _, intendedUuid in pairs(intendedByUser) do
            sendSelectCharacter(intendedUuid)
        end
        Ext.ServerNet.BroadcastMessage("NextCombatRound", "")
        for uuid, _ in pairs(M.Roster.getBrawlers()) do
            local entity = Ext.Entity.Get(uuid)
            if entity and entity.TurnBased then
                if M.Osi.IsPartyMember(uuid, 1) == 0 then
                    entity.TurnBased.HadTurnInCombat = true
                    entity.TurnBased.RequestedEndTurn = true
                    entity.TurnBased.TurnActionsCompleted = true
                else
                    entity.TurnBased.HadTurnInCombat = false
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
        -- If enemies are already in the combat participants list (normal case), initialize immediately.  Otherwise, onEnteredCombat will handle it.
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
            -- Same rationale as in nextCombatRound: clear HadTurn so the engine doesn't skip the controlled character's Groups entries.
            entity.TurnBased.HadTurnInCombat = false
            entity:Replicate("TurnBased")
        end
    end
    startCombatRoundTimer(combatGuid)
    if State.Settings.AutoPauseOnCombatStart and round == 1 then
        Pause.allEnterFTB()
    end
    -- Re-mangle TurnOrder.Groups to maintain the persistent-active-turns state and keep the currently-controlled character at the front of the topbar
    TurnOrder.setPartyInitiativeRollToMean()
    TurnOrder.bumpDirectlyControlledInitiativeRolls()
    TurnOrder.reorderByInitiativeRoll(true)
    TurnOrder.setPlayerTurnsActive()
    -- Engine doesn't fire TurnStarted on enemies in RT mode, so any status whose tick-source is an enemy never ticks. Manually decrement
    -- CurrentLifeTime by one round's worth on each such status. See Spells.tickStatusDurations for the full target/caster/TWS matrix.
    Spells.tickStatusDurations()
end

local function onCombatEnded(combatGuid)
    cancelCombatRoundTimer(combatGuid)
    TurnOrder.stopListeners(combatGuid)
    -- Defer stopping pulse actions + endBrawls together: the game may fire CombatEnded spuriously (e.g. during NPC-vs-NPC fights).
    -- If isInCombat is still true after the delay, the fight is ongoing and we leave pulses alone.
    Ext.Timer.WaitFor(1500, function()
        if not State.isInCombat() then
            stopAllPulseActions()
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
    -- Keep party init above enemies as new combatants join. For a new player, invalidate the cached mean so it's recomputed from the new lineup. For
    -- non-player non-helper entrants, just re-bump using current max enemy init (which now includes the joiner if their roll is higher).
    if State.Session.Players[uuid] then
        State.Session.MeanInitiativeRoll = nil
        TurnOrder.setPartyInitiativeRollToMean()
        TurnOrder.bumpDirectlyControlledInitiativeRolls()
    elseif not M.Utils.isCombatHelper(uuid) then
        TurnOrder.bumpDirectlyControlledInitiativeRolls()
    end
end

local function onGainedControl(uuid)
    debugPrint("onGainedControl", M.Utils.getDisplayName(uuid))
    if not State.Settings.FullAuto then
        stopPulseAction(Roster.getBrawlerByUuid(uuid))
    end
    local userId = Osi.GetReservedUserID(uuid)
    -- If we have a pending post-unpause selection for THIS user and the wrong char got control, override it.  Per-user map: {[userId] = uuid}.
    if State.Session.PendingSelectCharOnLeftFTB and userId then
        local pendingUuid = State.Session.PendingSelectCharOnLeftFTB[userId]
        if pendingUuid then
            if uuid ~= pendingUuid then
                debugPrint("Wrong char gained control, sending SelectCharacter for", M.Utils.getDisplayName(pendingUuid))
                sendSelectCharacter(pendingUuid)
            else
                debugPrint("Correct char gained control", M.Utils.getDisplayName(uuid))
            end
            State.Session.PendingSelectCharOnLeftFTB[userId] = nil
            if not next(State.Session.PendingSelectCharOnLeftFTB) then
                State.Session.PendingSelectCharOnLeftFTB = nil
            end
        end
    end
    for playerUuid, player in pairs(State.Session.Players) do
        if player.userId == userId and playerUuid ~= uuid then
            local brawler = Roster.getBrawlerByUuid(playerUuid)
            if brawler then
                startPulseAction(brawler)
            end
        end
    end
    if not State.Session.MeanInitiativeRoll then
       TurnOrder.setPartyInitiativeRollToMean()
    end
    TurnOrder.bumpDirectlyControlledInitiativeRolls()
    TurnOrder.reorderByInitiativeRoll(true)
    TurnOrder.setPlayerTurnsActive()
    -- Refresh the user's loadout HUD with the newly-controlled char's data.  Cheap to send even if HUD is closed (client just stashes it).
    if userId then
        Commands.postLoadoutsToUser(userId)
    end
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
    State.Session.IsInDialog = true
    pauseCombatRoundTimers()
    for uuid, brawler in pairs(M.Roster.getBrawlers()) do
        stopPulseAction(brawler)
        Utils.clearOsirisQueue(uuid)
    end
end

local function onDialogEnded()
    debugPrint("DialogEnded")
    State.Session.IsInDialog = false
    resumeCombatRoundTimers()
    for uuid, brawler in pairs(M.Roster.getBrawlers()) do
        if not State.isPlayerControllingDirectly(uuid) then
            startPulseAction(brawler, Constants.INITIAL_PULSE_ACTION_DELAY)
        end
    end
end

local function onDied(uuid)
    Roster.handleDeath(M.Osi.GetRegion(uuid), uuid)
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
    Movement.pauseTimers()
    if uuid and M.Osi.IsPartyMember(uuid, 1) == 1 then
        pauseCombatRoundTimers()
    end
end

local function onReactionInterruptUsed(uuid, isAutoTriggered)
    -- pause/resume only pair with player-chosen interrupts; auto-triggered ones never paused, so don't resume
    if isAutoTriggered ~= 0 then
        return
    end
    Movement.resumeTimers()
    if uuid and M.Osi.IsPartyMember(uuid, 1) == 1 then
        resumeCombatRoundTimers()
    end
end

-- thank u focus
local function onServerInterruptDecision()
    Movement.resumeTimers()
    if Ext.System.ServerInterruptDecision and Ext.System.ServerInterruptDecision.Decisions then
        for _, _ in pairs(Ext.System.ServerInterruptDecision.Decisions) do
            resumeCombatRoundTimers()
            return
        end
    end
end

local function onEnteredForceTurnBased(uuid)
    if State.Session.PendingSelectCharOnFTB and next(State.Session.PendingSelectCharOnFTB) then
        local selectedByUser = State.Session.PendingSelectCharOnFTB
        State.Session.PendingSelectCharOnFTB = nil
        -- Build the set of intended controlled chars across all users (one per user)
        -- and bump their init pre-emptively.  The set form lets bumpInitiativeRollsFor
        -- mark every per-user intended char as "controlled" in one pass.
        local intendedSet = {}
        for _, intendedUuid in pairs(selectedByUser) do
            intendedSet[intendedUuid] = true
        end
        TurnOrder.bumpInitiativeRollsFor(intendedSet)
        -- Send each user their own SelectCharacter and open a confirmation window so
        -- if the engine's FTB-entry pick fires GainedControl for a different char
        -- for that user, our redirect re-asserts.
        local expiresAt = Ext.Utils.MonotonicTime() + 500
        local expectedByUser = {}
        for userId, intendedUuid in pairs(selectedByUser) do
            debugPrint("FTB ready, sending SelectCharacter for", M.Utils.getDisplayName(intendedUuid))
            sendSelectCharacter(intendedUuid)
            expectedByUser[userId] = intendedUuid
        end
        State.Session.ExpectedControlled = expectedByUser
        State.Session.ExpectedControlledExpiresAt = expiresAt
    end
end

local function onLeftForceTurnBased(uuid)
    -- Clear stuck RequestedEndTurn on party members leaving FTB.  The engine can strand this flag (e.g. from an offered reaction prompt or a
    -- nextCombatRound that raced with pause) which triggers the End Turn popup and greys the hotbar in subsequent RT combat.
    if M.Osi.IsPartyMember(uuid, 1) == 1 then
        local entity = Ext.Entity.Get(uuid)
        if entity and entity.TurnBased and entity.TurnBased.RequestedEndTurn then
            entity.TurnBased.RequestedEndTurn = false
            entity:Replicate("TurnBased")
        end
    end
end

local function onStatusApplied(targetGuid, statusId)
    if Movement.isSpeedBoostStatus(statusId) then
        local uuid = M.Osi.GetUUID(targetGuid)
        if uuid and M.Roster.getBrawlerByUuid(uuid) then
            Movement.updateSpeedBoost(uuid)
        end
    end
end

local function onStatusRemoved(targetGuid, statusId)
    if Movement.isSpeedBoostStatus(statusId) then
        local uuid = M.Osi.GetUUID(targetGuid)
        if uuid then
            Movement.updateSpeedBoost(uuid)
        end
    end
end

return {
    joinCombat = joinCombat,
    nextCombatRound = nextCombatRound,
    sendSelectCharacter = sendSelectCharacter,
    Timers = {
        stopPulseAction = stopPulseAction,
        stopAllPulseActions = stopAllPulseActions,
        startPulseAction = startPulseAction,
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
        onDied = onDied,
        onTeleportedToCamp = onTeleportedToCamp,
        onFlagSet = onFlagSet,
        onReactionInterruptActionNeeded = onReactionInterruptActionNeeded,
        onReactionInterruptUsed = onReactionInterruptUsed,
        onServerInterruptDecision = onServerInterruptDecision,
        onEnteredForceTurnBased = onEnteredForceTurnBased,
        onLeftForceTurnBased = onLeftForceTurnBased,
        onStatusApplied = onStatusApplied,
        onStatusRemoved = onStatusRemoved,
    },
}
