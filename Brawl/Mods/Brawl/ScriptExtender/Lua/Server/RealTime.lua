local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump

-- Send a SelectCharacter NetMessage to whichever user owns this character.
-- Falls back to broadcast if we don't have a cached userId. Multiplayer-safe:
-- avoids broadcasting a "select X" message to all clients (which would tell
-- other users' clients to switch their own selection too).
local function sendSelectCharacter(uuid, reason)
    if not uuid then
        return
    end
    if Osi.IsDead(uuid) == 1 then
        debugPrint(string.format("sendSelectCharacter SKIPPED (target dead) target=%s reason=%s",
            M.Utils.getDisplayName(uuid) or tostring(uuid), reason or "?"))
        return
    end
    local userId = State.Session.Players[uuid] and State.Session.Players[uuid].userId
    debugPrint(string.format("sendSelectCharacter target=%s userId=%s reason=%s",
        M.Utils.getDisplayName(uuid) or tostring(uuid), tostring(userId), reason or "?"))
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
    debugPrint(string.format("pauseCombatRoundTimer combatGuid=%s timerWasSet=%s",
        tostring(combatGuid),
        tostring(State.Session.CombatRoundTimer and State.Session.CombatRoundTimer[combatGuid] ~= nil)))
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
    debugPrint(string.format("cancelCombatRoundTimer combatGuid=%s timerWasSet=%s",
        tostring(combatGuid),
        tostring(State.Session.CombatRoundTimer and State.Session.CombatRoundTimer[combatGuid] ~= nil)))
    State.Session.IsNextCombatRoundQueued = false
    if State.Session.CombatRoundTimer and State.Session.CombatRoundTimer[combatGuid] then
        Ext.Timer.Cancel(State.Session.CombatRoundTimer[combatGuid])
        State.Session.CombatRoundTimer[combatGuid] = nil
    end
end

local function pauseCombatRoundTimers()
    debugPrint("pauseCombatRoundTimers (all)")
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
local function dumpInitsForLog(tag)
    local entries = {}
    for uuid, _ in pairs(State.Session.Players or {}) do
        local entity = Ext.Entity.Get(uuid)
        local roll = entity and entity.CombatParticipant and entity.CombatParticipant.InitiativeRoll
        local rollMap
        if entity and entity.CombatParticipant and entity.CombatParticipant.CombatHandle
                and entity.CombatParticipant.CombatHandle.CombatState
                and entity.CombatParticipant.CombatHandle.CombatState.Initiatives then
            rollMap = entity.CombatParticipant.CombatHandle.CombatState.Initiatives[entity]
        end
        local tb = entity and entity.TurnBased
        local req = tb and tb.RequestedEndTurn
        local had = tb and tb.HadTurnInCombat
        local act = tb and tb.IsActiveCombatTurn
        local done = tb and tb.TurnActionsCompleted
        local name = M.Utils.getDisplayName(uuid) or uuid
        table.insert(entries, string.format("%s init=%s/%s ReqEndTurn=%s HadTurn=%s ActiveTurn=%s ActionsDone=%s",
            name, tostring(roll), tostring(rollMap),
            tostring(req), tostring(had), tostring(act), tostring(done)))
    end
    debugPrint(string.format("%s | %s", tag, table.concat(entries, " ; ")))
end

local function nextCombatRound()
    State.Session.IsNextCombatRoundQueued = false
    local targeting = State.areAnyPlayersTargeting()
    local casting = State.isAnyDirectlyControlledCasting()
    local inFTB = Pause.isPartyInFTB()
    debugPrint(string.format("nextCombatRound called: targeting=%s casting=%s inFTB=%s",
        tostring(targeting), tostring(casting), tostring(inFTB)))
    if targeting or casting then
        debugPrint(string.format("  -> queued (%s)", targeting and "targeting" or "committed cast in flight"))
        State.Session.IsNextCombatRoundQueued = true
    elseif not inFTB then
        dumpInitsForLog("nextCombatRound START")
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
        -- Pre-emptive: re-affirm SelectCharacter for each user's intended char right before the round-turnover mutations.  Skip for users with a
        -- recent GainedControl (within RECENT_CLICK_WINDOW_MS) — their click is fresh and we shouldn't override it; let the engine settle naturally.
        local now = Ext.Utils.MonotonicTime()
        local RECENT_CLICK_WINDOW_MS = 500
        for userId, intendedUuid in pairs(intendedByUser) do
            local lastClickAt = State.Session.LastGainedControlAt and State.Session.LastGainedControlAt[userId]
            if lastClickAt and (now - lastClickAt) < RECENT_CLICK_WINDOW_MS then
                debugPrint(string.format("preRoundTurnover SKIP userId=%s (recent click %dms ago)",
                    tostring(userId), now - lastClickAt))
            else
                sendSelectCharacter(intendedUuid, "RT.preRoundTurnover")
            end
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
        dumpInitsForLog("nextCombatRound END")
    end
end

-- NB: pause timer during interrupts
local function startCombatRoundTimer(combatGuid)
    -- if not State.isInCombat() then
    --     Osi.PauseCombat(combatGuid)
    -- end
    debugPrint(string.format("startCombatRoundTimer combatGuid=%s duration=%dms", tostring(combatGuid), getCombatRoundDuration()))
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
    -- Cancel any pending APoCS reset timer — a fresh combat-start within the 10s reset window means we're
    -- mid-fight (combat-GUID flicker), not at the genuine end of the fight. Keep the flag set so we don't
    -- re-fire APoCS on this new combat's round 1.
    if State.Session.APoCSResetTimer then
        Ext.Timer.Cancel(State.Session.APoCSResetTimer)
        State.Session.APoCSResetTimer = nil
    end
    if not Utils.isToT() then
        State.uncapMovementDistances()
        -- If enemies are already in the combat participants list (normal case), initialize immediately.  Otherwise, onEnteredCombat will handle it.
        if hasEnemyBrawlers() then
            initializeCombat(combatGuid)
        end
    end
end

-- Fire APoCS now: cleanup pending debounce timer and pause the party. Idempotent — safe to call multiple times.
-- Driven by either the 5s safety timer (set in onCombatRoundStarted) OR the client's APoCSCameraReady net message
-- (which fires when the ecl::camera::CombatTargetComponent entity is created — the engine's "combat fully settled"
-- moment, a few frames after the unsheath::CombatJoining components are destroyed).
local function fireAPoCSNow()
    local elapsed = State.Session.APoCSStartMs and (Ext.Utils.MonotonicTime() - State.Session.APoCSStartMs) or 0
    if State.Session.APoCSDebounceTimer then
        Ext.Timer.Cancel(State.Session.APoCSDebounceTimer)
        State.Session.APoCSDebounceTimer = nil
    end
    if not Pause.isPartyInFTB() then
        debugPrint(string.format("[+%dms] APoCS firing -> allEnterFTB", elapsed))
        Pause.allEnterFTB()
    end
end

-- Net-message handler for the client's camera-ready signal. The client (Client/Main.lua) subscribes to
-- CameraArriveWatcher OnCreateDeferred and pings the server whenever it fires. We only act if APoCS is
-- currently waiting (debounce timer pending) — once fired, the timer is nil and subsequent signals (e.g.
-- camera-arrival on cinematic moves, mid-fight target switches) are harmless no-ops.
local function onAPoCSCameraReady()
    if State.Session.APoCSDebounceTimer then
        fireAPoCSNow()
    end
end

local function onCombatRoundStarted(combatGuid, round)
    if Pause.isPartyInFTB() then
        print("party is in FTB, pausing underlying combat", combatGuid, round)
        return Osi.PauseCombat(combatGuid)
    end
    dumpInitsForLog(string.format("RT.onCombatRoundStarted START round=%d", round or -1))
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
    -- APoCS at round==1 fires too early — engine isn't done (characters still drawing weapons / finalizing
    -- combat entry; allEnterFTB at this stage kills the underlying combat). Wait for the engine's stream of
    -- CombatJoining component destroys to quiet down (per-character weapon-draw / combat-entry finalization).
    -- 500ms debounce after the last destroy. APoCSScheduled flag stays true after firing — only the genuine
    -- end-of-fight reset in onCombatEnded clears it (prevents see-saw across new combat GUIDs).
    -- APoCS fires on the Combat Helper's first BoostChangedEvent post-round-1. Empirically this fires right
    -- at the engine's "combat startup is done" moment — characters have finished joining, weapons drawn,
    -- helper's boosts have been finalized. OnCreateDeferred fires on the tick AFTER the event is created,
    -- which puts us safely past the settling chaos. Scoped to the combat helper entity so we don't catch
    -- random boost changes from spells/buffs elsewhere. 5s safety fallback in case the event never fires.
    if State.Settings.AutoPauseOnCombatStart and round == 1 and not State.Session.APoCSScheduled then
        State.Session.APoCSScheduled = true
        State.Session.APoCSStartMs = Ext.Utils.MonotonicTime()
        debugPrint("[+0ms] APoCS scheduled at round 1, waiting for client camera-ready signal")
        -- 5s safety fallback in case the client camera signal never arrives.
        State.Session.APoCSDebounceTimer = Ext.Timer.WaitFor(5000, fireAPoCSNow)
        -- 1s cap on the addBrawler pre-pause: in normal fights APoCS fires within ~500ms (camera signal) so
        -- pre-paused NPCs barely sit idle. In pathological NPC-on-NPC late-joins we hit the 5s safety, and
        -- pre-paused NPCs would stand frozen for the full 5s — looks silly in dungeons full of warring NPC
        -- factions. Unfreeze and start pulses for any pre-paused NPCs after 1s if APoCS still hasn't fired.
        Ext.Timer.WaitFor(1000, function()
            if Pause.isPartyInFTB() or State.Session.IsInDialog then return end
            for uuid, brawler in pairs(M.Roster.getBrawlers()) do
                if brawler.isPaused and not State.Session.Players[uuid] then
                    brawler.isPaused = false
                    startPulseAction(brawler, 0)
                end
            end
        end)
    end
    -- Re-mangle TurnOrder.Groups to maintain the persistent-active-turns state and keep the currently-controlled character at the front of the topbar
    TurnOrder.setPartyInitiativeRollToMean()
    TurnOrder.bumpDirectlyControlledInitiativeRolls()
    TurnOrder.reorderByInitiativeRoll(true)
    TurnOrder.setPlayerTurnsActive()
    dumpInitsForLog(string.format("RT.onCombatRoundStarted POST-bump round=%d", round or -1))
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
    -- APoCS flag reset: schedule a 10s timer. If a new CombatStarted fires before it expires (combat-GUID
    -- flicker mid-fight), onCombatStarted cancels the timer. We deliberately do NOT gate the reset on
    -- State.isInCombat() at expiry — that gate breaks the late-join NPC-on-NPC scenario where the engine
    -- churns combat GUIDs (see-saw) and host's IsInCombat stays true through the transition. cancel-on-
    -- CombatStarted alone is sufficient protection against mid-fight flicker (the new GUID's CombatStarted
    -- fires sub-second after the old one's CombatEnded, well within the 10s window).
    if State.Session.APoCSResetTimer then
        Ext.Timer.Cancel(State.Session.APoCSResetTimer)
    end
    State.Session.APoCSResetTimer = Ext.Timer.WaitFor(10000, function()
        State.Session.APoCSResetTimer = nil
        State.Session.APoCSScheduled = false
        if State.Session.APoCSDebounceTimer then
            Ext.Timer.Cancel(State.Session.APoCSDebounceTimer)
            State.Session.APoCSDebounceTimer = nil
        end
        State.Session.APoCSStartMs = nil
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
                sendSelectCharacter(pendingUuid, "RT.onGainedControl-pendingFTB-mismatch")
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

local TARGETING_REACTION_LOCK_BOOST = "ActionResourceBlock(ReactionActionPoint)"
local TARGETING_REACTION_LOCK_REASON = "BRAWL_TARGETING_REACTION_LOCK"

local function onSpellSyncTargeting(spellCastState)
    if spellCastState and spellCastState.Caster and spellCastState.Caster.Uuid.EntityUuid then
        local uuid = spellCastState.Caster.Uuid.EntityUuid
        State.Session.PlayerTargetingSpellCast[uuid] = true
        Osi.AddBoosts(uuid, TARGETING_REACTION_LOCK_BOOST, TARGETING_REACTION_LOCK_REASON, uuid)
    end
end

local function onDestroySpellSyncTargeting(spellCastState)
    if spellCastState and spellCastState.Caster and spellCastState.Caster.Uuid.EntityUuid then
        local uuid = spellCastState.Caster.Uuid.EntityUuid
        State.Session.PlayerTargetingSpellCast[uuid] = nil
        Osi.RemoveBoosts(uuid, TARGETING_REACTION_LOCK_BOOST, 0, TARGETING_REACTION_LOCK_REASON, uuid)
        if State.Session.IsNextCombatRoundQueued then
            -- Defer one tick.  If targeting destroyed because of a click-to-commit, SpellCastState is created
            -- right after; the deferred retry then sees the casting gate and re-queues correctly.  If it was
            -- a cancel (right-click), no SpellCastState appears and the retry proceeds.
            Ext.Timer.WaitFor(0, function ()
                if State.Session.IsNextCombatRoundQueued then
                    nextCombatRound()
                end
            end)
        end
    end
end

-- SpellCastState lifecycle covers the full commit-to-completion span of a cast (including the engine's
-- move-into-range phase before a melee attack).  Track it per directly-controlled char so we can defer
-- round turnover -- at turnover, RequestedEndTurn=true flushes pending action queues, which would
-- otherwise cancel a queued attack mid-walk and not resume.
local function onSpellCastStateCreated(spellCastState)
    if spellCastState and spellCastState.Caster and spellCastState.Caster.Uuid.EntityUuid then
        local uuid = spellCastState.Caster.Uuid.EntityUuid
        if State.isPlayerControllingDirectly(uuid) then
            State.Session.PlayerCommittedCast[uuid] = true
        end
    end
end

local function onSpellCastStateDestroyed(spellCastState)
    if spellCastState and spellCastState.Caster and spellCastState.Caster.Uuid.EntityUuid then
        local uuid = spellCastState.Caster.Uuid.EntityUuid
        if State.Session.PlayerCommittedCast[uuid] then
            State.Session.PlayerCommittedCast[uuid] = nil
            if State.Session.IsNextCombatRoundQueued then
                nextCombatRound()
            end
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
    -- onReactionInterruptActionNeeded pauses unconditionally for any party-member reaction prompt
    -- (including auto-triggered ones — it has no isAutoTriggered signal at that point), so we MUST
    -- resume unconditionally here. Skipping resume for auto-triggered reactions left the round
    -- timer permanently paused, which prevented nextCombatRound from firing and caused unwanted
    -- control switches at the next round-start (engine picks wrong group when ReqEndTurn flags
    -- aren't set up by nextCombatRound's mutations). Bisected 2026-05-04.
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
    debugPrint(string.format("onEnteredForceTurnBased: entity=%s pendingSet=%s",
        M.Utils.getDisplayName(uuid) or tostring(uuid),
        tostring(State.Session.PendingSelectCharOnFTB and next(State.Session.PendingSelectCharOnFTB) ~= nil)))
    -- Fix mid-round-cycle TurnBased state on party members entering FTB. If pause hits mid-round (some
    -- party members already finished their turn-segment, others mid-flight), the engine carries that
    -- partial state into FTB: HadTurnInCombat=true on chars who acted, IsActiveCombatTurn=true on
    -- chars still mid-turn. Engine then can't cleanly transition party-turn → env-turn and stalls in
    -- the rare "stuck environmental turn" pathology. Forcing all party to {IsActive=true, HadTurn=false,
    -- ReqEndTurn=false} at FTB-entry time gives the engine a clean party-active state to layer FTB on,
    -- and matches the visual intent (all 4 portraits "larged" during pause).
    -- Run AFTER the engine's FTB transition (via this listener) rather than synchronously inside
    -- allEnterFTB — engine-side mutations during Osi.ForceTurnBasedMode would overwrite our pre-writes.
    if M.Osi.IsPartyMember(uuid, 1) == 1 then
        local entity = Ext.Entity.Get(uuid)
        if entity and entity.TurnBased then
            entity.TurnBased.IsActiveCombatTurn = true
            entity.TurnBased.HadTurnInCombat = false
            entity.TurnBased.RequestedEndTurn = false
            entity:Replicate("TurnBased")
        end
    end
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
            sendSelectCharacter(intendedUuid, "RT.FTBReady")
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
    onAPoCSCameraReady = onAPoCSCameraReady,
    Listeners = {
        onStarted = onStarted,
        onCombatStarted = onCombatStarted,
        onCombatRoundStarted = onCombatRoundStarted,
        onCombatEnded = onCombatEnded,
        onEnteredCombat = onEnteredCombat,
        onGainedControl = onGainedControl,
        onSpellSyncTargeting = onSpellSyncTargeting,
        onDestroySpellSyncTargeting = onDestroySpellSyncTargeting,
        onSpellCastStateCreated = onSpellCastStateCreated,
        onSpellCastStateDestroyed = onSpellCastStateDestroyed,
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
