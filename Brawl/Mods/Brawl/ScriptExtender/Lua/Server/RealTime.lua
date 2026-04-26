local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump

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
        if not Utils.canAct(brawler.uuid) or brawler.isPaused or (State.isPlayerControllingDirectly(brawler.uuid) and not State.Settings.FullAuto) then
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
    print("[SwitchTrace] nextCombatRound fired at " .. tostring(Ext.Utils.MonotonicTime()))
    State.Session.IsNextCombatRoundQueued = false
    if State.areAnyPlayersTargeting() then
        State.Session.IsNextCombatRoundQueued = true
    elseif not Pause.isPartyInFTB() then
        -- Snapshot the currently-controlled character before the round turnover
        -- mutations. Prefer a live ClientControl lookup over the cached
        -- LastControlledUuid: the cache may be stale if setIsControllingDirectly
        -- hasn't been called recently enough (e.g., after a prior unwanted
        -- switch it'd point at the wrong char).
        local intendedControlled
        local controlEntities = Ext.Entity.GetAllEntitiesWithComponent("ClientControl")
        if controlEntities and controlEntities[1] and controlEntities[1].Uuid then
            intendedControlled = controlEntities[1].Uuid.EntityUuid
        end
        if not intendedControlled then
            intendedControlled = State.Session.LastControlledUuid
        end
        print("[SwitchRedirect] nextCombatRound snapshot intended=" .. tostring(intendedControlled))
        -- Pre-emptive: re-affirm SelectCharacter for the intended character
        -- right before the round-turnover mutations. If this lands before the
        -- engine cycles, the client may stay locked on the intended char and
        -- skip the visible flicker. (May or may not help depending on engine
        -- ordering — testing.)
        if intendedControlled then
            print(string.format("[Probe T=%s] nextCombatRound BroadcastMessage SelectCharacter -> %s",
                tostring(Ext.Utils.MonotonicTime()),
                tostring(M.Utils.getDisplayName(intendedControlled))))
            Ext.ServerNet.BroadcastMessage("SelectCharacter", intendedControlled)
        end
        Ext.ServerNet.BroadcastMessage("NextCombatRound", "")
        local replicatedCount = 0
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
                replicatedCount = replicatedCount + 1
            end
        end
        print(string.format("[Probe T=%s] nextCombatRound TurnBased replicate loop done, count=%d",
            tostring(Ext.Utils.MonotonicTime()), replicatedCount))
        -- Redirect window disabled for now — testing whether initiative jacking
        -- alone prevents the engine's round-turnover switch (and whether the
        -- redirect itself was the source of the visible flicker).
        -- if intendedControlled then
        --     State.Session.RoundTransitionIntent = intendedControlled
        --     State.Session.RoundTransitionExpiresAt = Ext.Utils.MonotonicTime() + 300
        -- end
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
    -- TEMP: deterministic dump for control-switch investigation.
    Commands.dumpFullState("onCombatStarted " .. tostring(combatGuid))
    -- Probe: subscribe to every TurnOrder change on the combat entity for the duration of this fight. Logs only — does not unsubscribe itself.
    local combatEntity = Utils.getCombatEntity()
    if combatEntity then
        if State.Session.ProbeTurnOrderListener then
            Ext.Entity.Unsubscribe(State.Session.ProbeTurnOrderListener)
            State.Session.ProbeTurnOrderListener = nil
        end
        State.Session.ProbeTurnOrderListener = Ext.Entity.Subscribe("TurnOrder", function (entity, _, _)
            local groupCount = 0
            local firstName = "<nil>"
            if entity and entity.TurnOrder and entity.TurnOrder.Groups then
                groupCount = #entity.TurnOrder.Groups
                local g1 = entity.TurnOrder.Groups[1]
                if g1 and g1.Members and g1.Members[1] and g1.Members[1].Entity
                        and g1.Members[1].Entity.Uuid then
                    firstName = M.Utils.getDisplayName(g1.Members[1].Entity.Uuid.EntityUuid)
                end
            end
            print(string.format("[Probe T=%s] TurnOrder changed: groups=%d firstMember=%s",
                tostring(Ext.Utils.MonotonicTime()), groupCount, tostring(firstName)))
        end, combatEntity)
    end
end

local function onCombatRoundStarted(combatGuid, round)
    -- TEMP: dump BEFORE our setPlayerTurnsActive re-runs, to see what the engine produced at round advance vs what we re-mangle into.
    Commands.dumpFullState("onCombatRoundStarted round=" .. tostring(round) .. " PRE")
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
    local crsReplicatedCount = 0
    for uuid, _ in pairs(State.Session.Players) do
        local entity = Ext.Entity.Get(uuid)
        if entity and entity.TurnBased then
            entity.TurnBased.RequestedEndTurn = false
            -- Same rationale as in nextCombatRound: clear HadTurn so the engine doesn't skip the controlled character's Groups entries.
            entity.TurnBased.HadTurnInCombat = false
            entity:Replicate("TurnBased")
            crsReplicatedCount = crsReplicatedCount + 1
        end
    end
    print(string.format("[Probe T=%s] onCombatRoundStarted TurnBased replicate loop done, count=%d",
        tostring(Ext.Utils.MonotonicTime()), crsReplicatedCount))
    startCombatRoundTimer(combatGuid)
    if State.Settings.AutoPauseOnCombatStart and round == 1 then
        Pause.allEnterFTB()
    end
    -- Re-mangle TurnOrder.Groups to maintain the persistent-active-turns state and keep the currently-controlled character at the front of the topbar
    TurnOrder.setPartyInitiativeRollToMean()
    TurnOrder.bumpDirectlyControlledInitiativeRolls()
    TurnOrder.reorderByInitiativeRoll(true)
    TurnOrder.setPlayerTurnsActive()
    Commands.dumpFullState("onCombatRoundStarted round=" .. tostring(round) .. " POST")
end

local function onCombatEnded(combatGuid)
    cancelCombatRoundTimer(combatGuid)
    TurnOrder.stopListeners(combatGuid)
    if State.Session.ProbeTurnOrderListener then
        Ext.Entity.Unsubscribe(State.Session.ProbeTurnOrderListener)
        State.Session.ProbeTurnOrderListener = nil
    end
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
    -- Round-turnover redirect: if we're inside the post-nextCombatRound window and the engine drifted control to a different character than
    -- the snapshotted intent, broadcast SelectCharacter to restore.
    if State.Session.RoundTransitionIntent
            and uuid ~= State.Session.RoundTransitionIntent
            and State.Session.RoundTransitionExpiresAt
            and Ext.Utils.MonotonicTime() < State.Session.RoundTransitionExpiresAt then
        local intended = State.Session.RoundTransitionIntent
        print(string.format("[SwitchRedirect] drift %s -> %s, restoring",
            tostring(M.Utils.getDisplayName(uuid)),
            tostring(M.Utils.getDisplayName(intended))))
        print(string.format("[Probe T=%s] SwitchRedirect BroadcastMessage SelectCharacter -> %s",
            tostring(Ext.Utils.MonotonicTime()),
            tostring(M.Utils.getDisplayName(intended))))
        Ext.ServerNet.BroadcastMessage("SelectCharacter", intended)
    end
    -- FTB-entry confirmation window: when we entered FTB and broadcast SelectCharacter for the pre-pause controlled char, the engine often
    -- defaults to the host character anyway. Re-assert until the engine confirms our intended char (or the window expires).
    if State.Session.ExpectedControlledOnFTB
            and State.Session.ExpectedControlledOnFTBExpiresAt
            and Ext.Utils.MonotonicTime() < State.Session.ExpectedControlledOnFTBExpiresAt then
        if uuid ~= State.Session.ExpectedControlledOnFTB then
            local intended = State.Session.ExpectedControlledOnFTB
            print(string.format("[Probe T=%s] FTB redirect: GainedControl %s != intended %s, re-asserting",
                tostring(Ext.Utils.MonotonicTime()),
                tostring(M.Utils.getDisplayName(uuid)),
                tostring(M.Utils.getDisplayName(intended))))
            TurnOrder.bumpInitiativeRollsFor(intended)
            local intendedUserId = State.Session.Players[intended] and State.Session.Players[intended].userId
            if intendedUserId then
                Ext.ServerNet.PostMessageToUser(intendedUserId, "SelectCharacter", intended)
            else
                Ext.ServerNet.BroadcastMessage("SelectCharacter", intended)
            end
        else
            -- Right character confirmed; close the window.
            print(string.format("[Probe T=%s] FTB redirect: confirmed %s, closing window",
                tostring(Ext.Utils.MonotonicTime()),
                tostring(M.Utils.getDisplayName(uuid))))
            State.Session.ExpectedControlledOnFTB = nil
            State.Session.ExpectedControlledOnFTBExpiresAt = nil
        end
    end
    -- TEMP: log control-switch for unwanted-switch investigation.
    do
        local now = Ext.Utils.MonotonicTime()
        local prevUuid
        if State.Session.Players then
            for u, p in pairs(State.Session.Players) do
                if p.isControllingDirectly and u ~= uuid then
                    prevUuid = u
                    break
                end
            end
        end
        local newName = M.Utils.getDisplayName(uuid)
        local prevName = prevUuid and M.Utils.getDisplayName(prevUuid) or "<nil>"
        print(string.format("[SwitchTrace] onGainedControl at %s: %s -> %s",
            tostring(now), tostring(prevName), tostring(newName)))
        if State.Session.Players then
            for playerUuid, _ in pairs(State.Session.Players) do
                local entity = Ext.Entity.Get(playerUuid)
                if entity and entity.TurnBased then
                    local tb = entity.TurnBased
                    local castSpell
                    if entity.SpellCastIsCasting and entity.SpellCastIsCasting.Cast
                            and entity.SpellCastIsCasting.Cast.SpellCastState
                            and entity.SpellCastIsCasting.Cast.SpellCastState.SpellId then
                        castSpell = entity.SpellCastIsCasting.Cast.SpellCastState.SpellId.OriginatorPrototype
                    end
                    print(string.format("[SwitchTrace]   %s: IsActive=%s ReqEnd=%s HadTurn=%s TurnDone=%s cast=%s",
                        M.Utils.getDisplayName(playerUuid),
                        tostring(tb.IsActiveCombatTurn), tostring(tb.RequestedEndTurn),
                        tostring(tb.HadTurnInCombat), tostring(tb.TurnActionsCompleted),
                        tostring(castSpell or "<nil>")))
                end
            end
        end
    end
    if not State.Settings.FullAuto then
        stopPulseAction(Roster.getBrawlerByUuid(uuid))
    end
    -- If we have a pending post-unpause selection and the wrong character got control, override it
    if State.Session.PendingSelectCharOnLeftFTB and uuid ~= State.Session.PendingSelectCharOnLeftFTB then
        local selectedUuid = State.Session.PendingSelectCharOnLeftFTB
        State.Session.PendingSelectCharOnLeftFTB = nil
        debugPrint("Wrong char gained control, sending SelectCharacter for", M.Utils.getDisplayName(selectedUuid))
        print(string.format("[Probe T=%s] PendingSelectCharOnLeftFTB BroadcastMessage SelectCharacter -> %s",
            tostring(Ext.Utils.MonotonicTime()),
            tostring(M.Utils.getDisplayName(selectedUuid))))
        Ext.ServerNet.BroadcastMessage("SelectCharacter", selectedUuid)
    elseif State.Session.PendingSelectCharOnLeftFTB and uuid == State.Session.PendingSelectCharOnLeftFTB then
        State.Session.PendingSelectCharOnLeftFTB = nil
        debugPrint("Correct char gained control", M.Utils.getDisplayName(uuid))
    end
    local userId = Osi.GetReservedUserID(uuid)
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
    print(string.format("[Probe T=%s] onGainedControl pre-bump (uuid=%s)",
        tostring(Ext.Utils.MonotonicTime()),
        tostring(M.Utils.getDisplayName(uuid))))
    TurnOrder.bumpDirectlyControlledInitiativeRolls()
    print(string.format("[Probe T=%s] onGainedControl pre-reorder",
        tostring(Ext.Utils.MonotonicTime())))
    TurnOrder.reorderByInitiativeRoll(true)
    print(string.format("[Probe T=%s] onGainedControl pre-setPlayerTurnsActive",
        tostring(Ext.Utils.MonotonicTime())))
    TurnOrder.setPlayerTurnsActive()
    print(string.format("[Probe T=%s] onGainedControl handler done",
        tostring(Ext.Utils.MonotonicTime())))
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
    pauseCombatRoundTimers()
    for uuid, brawler in pairs(M.Roster.getBrawlers()) do
        stopPulseAction(brawler)
        Utils.clearOsirisQueue(uuid)
    end
end

local function onDialogEnded()
    debugPrint("DialogEnded")
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
    Movement.resumeTimers()
    if uuid and M.Osi.IsPartyMember(uuid, 1) == 1 and isAutoTriggered == 0 then
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
    if State.Session.PendingSelectCharOnFTB then
        local selectedUuid = State.Session.PendingSelectCharOnFTB
        State.Session.PendingSelectCharOnFTB = nil
        -- Probe: log every party member's init at the moment the FTB-ready handler runs, before we touch anything.  The engine wipes init to
        -- -100 during FTB processing; this shows whether the wipe has already happened by the time we get here.
        for partyUuid, _ in pairs(State.Session.Players) do
            local entity = Ext.Entity.Get(partyUuid)
            if entity and entity.CombatParticipant then
                local userIdStr = "<no-component>"
                if entity.UserReservedFor then
                    userIdStr = tostring(entity.UserReservedFor.UserID)
                end
                print(string.format("[Probe T=%s] FTBready %s init=%s userReservedFor=%s",
                    tostring(Ext.Utils.MonotonicTime()),
                    tostring(M.Utils.getDisplayName(partyUuid)),
                    tostring(entity.CombatParticipant.InitiativeRoll),
                    userIdStr))
            end
        end
        -- Pre-emptively bump init for the intended controlled char before the engine picks.  If the engine's FTB-entry control assignment
        -- uses initiative as a tiebreaker, jacking the right char's init here may steer the engine to pick correctly the first time.
        TurnOrder.bumpInitiativeRollsFor(selectedUuid)
        debugPrint("FTB ready, sending SelectCharacter for", M.Utils.getDisplayName(selectedUuid))
        local targetUserId = State.Session.Players[selectedUuid] and State.Session.Players[selectedUuid].userId
        if targetUserId then
            print(string.format("[Probe T=%s] PendingSelectCharOnFTB PostMessageToUser(user=%s) SelectCharacter -> %s",
                tostring(Ext.Utils.MonotonicTime()),
                tostring(targetUserId),
                tostring(M.Utils.getDisplayName(selectedUuid))))
            Ext.ServerNet.PostMessageToUser(targetUserId, "SelectCharacter", selectedUuid)
        else
            print(string.format("[Probe T=%s] PendingSelectCharOnFTB no cached userId for %s, falling back to broadcast",
                tostring(Ext.Utils.MonotonicTime()),
                tostring(M.Utils.getDisplayName(selectedUuid))))
            Ext.ServerNet.BroadcastMessage("SelectCharacter", selectedUuid)
        end
        -- Open a confirmation window: until the engine fires GainedControl for this character (or the window expires), any GainedControl for
        -- a different character is treated as the engine's wrong default pick and we re-assert.
        State.Session.ExpectedControlledOnFTB = selectedUuid
        State.Session.ExpectedControlledOnFTBExpiresAt = Ext.Utils.MonotonicTime() + 500
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
