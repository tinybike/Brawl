local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump

local function isLocked(entity)
    debugPrint(entity.TurnBased.CanActInCombat, entity.TurnBased.HadTurnInCombat, entity.TurnBased.IsActiveCombatTurn)
    return entity.TurnBased.CanActInCombat and entity.TurnBased.HadTurnInCombat and not entity.TurnBased.IsActiveCombatTurn
end

local function unlock(entity)
    if entity and entity.Uuid then
        debugPrint("unlock", entity.Uuid.EntityUuid, isLocked(entity))
        -- debugDump(entity.TurnBased)
        entity.TurnBased.IsActiveCombatTurn = true
        entity:Replicate("TurnBased")
        local uuid = entity.Uuid.EntityUuid
        State.Session.FTBLockedIn[uuid] = false
        if State.Session.MovementQueue[uuid] then
            debugPrint("unloading movement queue for", uuid)
            if State.Session.TranslateChangedEventListeners[uuid] ~= nil then
                Ext.Entity.Unsubscribe(State.Session.TranslateChangedEventListeners[uuid])
                State.Session.TranslateChangedEventListeners[uuid] = nil
            end
            local moveTo = State.Session.MovementQueue[uuid]
            debugDump(moveTo)
            Movement.moveToPosition(uuid, moveTo, false, function ()
                debugPrint(M.Utils.getDisplayName(uuid), "queued movement completed, starting pulse action")
                local brawler = M.Roster.getBrawlerByUuid(uuid)
                if brawler and not State.isPlayerControllingDirectly(uuid) then
                    RT.Timers.startPulseAction(brawler)
                end
            end)
            State.Session.MovementQueue[uuid] = nil
        end
    end
end

local function lock(entity)
    if entity and entity.Uuid then
        local uuid = entity.Uuid.EntityUuid
        debugPrint("locking", uuid)
        Roster.disableLockedOnTarget(uuid)
        entity.TurnBased.IsActiveCombatTurn = false
        State.Session.FTBLockedIn[uuid] = true
    end
end

local function stopTruePause(entityUuid)
    if State.Session.TranslateChangedEventListeners[entityUuid] ~= nil then
        Ext.Entity.Unsubscribe(State.Session.TranslateChangedEventListeners[entityUuid])
        State.Session.TranslateChangedEventListeners[entityUuid] = nil
    end
    if State.Session.TurnBasedListeners[entityUuid] ~= nil then
        Ext.Entity.Unsubscribe(State.Session.TurnBasedListeners[entityUuid])
        State.Session.TurnBasedListeners[entityUuid] = nil
    end
    if State.Session.SpellCastPrepareEndEventListeners[entityUuid] ~= nil then
        Ext.Entity.Unsubscribe(State.Session.SpellCastPrepareEndEventListeners[entityUuid])
        State.Session.SpellCastPrepareEndEventListeners[entityUuid] = nil
    end
end

local function allEnterFTB()
    if State.Settings.TurnBasedSwarmMode then
        return
    end
    debugPrint("allEnterFTB called")
    debugPrint("allEnterFTB")
    -- Out of combat: minimal FTB on party members, no pause machinery. Players
    -- can move around freely and the game's native FTB handles everything.
    if next(M.Roster.getBrawlers()) == nil then
        for uuid, _ in pairs(State.Session.Players) do
            if M.Osi.IsDead(uuid) == 0 and not M.Utils.isDowned(uuid) then
                Osi.ForceTurnBasedMode(uuid, 1)
            end
        end
        return
    end
    -- Capture the currently controlled character per user BEFORE pulling anyone out of combat
    -- (leaving combat triggers GainedControl which resets the selection).  In MP each user has
    -- their own isControllingDirectly char; we want to restore each one independently.
    local selectedBeforePause = {}  -- {[userId] = uuid}
    for uuid, player in pairs(State.Session.Players) do
        if player.isControllingDirectly and player.userId then
            selectedBeforePause[player.userId] = uuid
        end
    end
    local narrativeCombatLabel
    if State.Session.CombatHelper then
        local combatGuid = M.Osi.CombatGetGuidFor(State.Session.CombatHelper)
        if combatGuid then
            narrativeCombatLabel = Utils.getNarrativeCombatLabel(combatGuid)
            Osi.PauseCombat(combatGuid)
        end
    end
    RT.Timers.pauseCombatRoundTimers()
    -- Stop pulse actions and pause resource refill timers for ALL brawlers
    for uuid, brawler in pairs(M.Roster.getBrawlers()) do
        RT.Timers.stopPulseAction(brawler)
        brawler.isPaused = true
        Utils.clearOsirisQueue(uuid)
        Resources.pauseActionResourcesRefillTimers(brawler)
        if State.Session.Players[uuid] and State.Session.AwaitingTarget[uuid] then
            Commands.setAwaitingTarget(uuid, false)
        end
        if M.Osi.IsPlayer(uuid) == 0 then
            Osi.ForceTurnBasedMode(uuid, 1)
            if State.Settings.TruePause then
                Pause.startTruePause(uuid)
            end
        end
    end
    -- Put all party members into FTB; skip dead/downed.
    local pauseEntryExpiry = Ext.Utils.MonotonicTime() + 2000
    for uuid, _ in pairs(State.Session.Players) do
        if M.Osi.IsDead(uuid) == 0 and not M.Utils.isDowned(uuid) then
            if narrativeCombatLabel then
                Osi.PROC_GLO_NarrativeCombat_LeaveCombat(narrativeCombatLabel, uuid)
            end
            Osi.SetCanJoinCombat(uuid, 0)
            Osi.ForceTurnBasedMode(uuid, 1)
            -- Proactively unlock so stale IsActiveCombatTurn=false from a prior midActionLock doesn't leave the character greyed-out on re-pause.
            local entity = Ext.Entity.Get(uuid)
            unlock(entity)
            -- Clear RequestedEndTurn: nextCombatRound sets it true on all party members at round-end (and onCombatRoundStarted clears it at the
            -- next round).  If pause lands in that window, the TurnBased listener will read it true -> flag all as FTB-ready -> engine shows End Turn
            -- popup / greys out players.
            if entity and entity.TurnBased and entity.TurnBased.RequestedEndTurn then
                entity.TurnBased.RequestedEndTurn = false
                entity:Replicate("TurnBased")
            end
            -- Clear any pending REACTION status: when pause interrupts a reaction-trigger event (e.g. ally takes a hit and offers a
            -- Shield reaction), the engine's reaction-prompt state gets stuck and greys out the character's hotbar.
            Osi.RemoveStatus(uuid, "REACTION")
            -- Flag every party member for the 2s skip window, not just those where SpellCastIsCasting.Cast is already present: some casts
            -- haven't materialized into Cast yet at pause entry (pre-prepare phase), but still fire SpellCastPrepareEndEvent during FTB and
            -- lock the character. Also covers reactions (e.g. Divine Allegiance) that the engine auto-fires post-pause.
            State.Session.PreExistingCastAtPause[uuid] = pauseEntryExpiry
            if State.Settings.TruePause then
                Pause.startTruePause(uuid)
            end
        end
    end
    -- Restore each user's pre-pause selection once FTB is ready (consumed in
    -- RT.onEnteredForceTurnBased).  Stored as {[userId] = uuid}.
    if next(selectedBeforePause) then
        State.Session.PendingSelectCharOnFTB = selectedBeforePause
        local entries = {}
        for uid, u in pairs(selectedBeforePause) do
            table.insert(entries, string.format("%s→%s", tostring(uid), M.Utils.getDisplayName(u) or u))
        end
        debugPrint(string.format("PendingSelectCharOnFTB SET in allEnterFTB: %s", table.concat(entries, ", ")))
    end
end

local function allExitFTB()
    if State.Settings.TurnBasedSwarmMode then
        return
    end
    debugPrint("allExitFTB")
    State.Session.PreExistingCastAtPause = {}
    -- Don't reset APoCSScheduled here. Manual unpause doesn't mean the fight is over — the engine often
    -- spawns a fresh combat GUID mid-fight, which would re-trigger APoCS if we cleared the flag now.
    -- Reset is handled in RT.onCombatEnded once all party members are confirmed out of combat for a few seconds.
    -- Out of combat: minimal FTB exit on party members, mirroring allEnterFTB.
    if next(M.Roster.getBrawlers()) == nil then
        for uuid, _ in pairs(State.Session.Players) do
            if M.Osi.IsDead(uuid) == 0 and not M.Utils.isDowned(uuid) then
                Osi.ForceTurnBasedMode(uuid, 0)
            end
        end
        return
    end
    -- Capture per-user selection BEFORE exiting FTB (leaving FTB reassigns control).
    -- {[userId] = uuid} — restored individually per user in RT.onGainedControl.
    local selectedDuringPause = {}
    for uuid, player in pairs(State.Session.Players) do
        if player.isControllingDirectly and player.userId then
            selectedDuringPause[player.userId] = uuid
        end
    end
    -- Track which characters have queued movements before we start unpausing
    local hasQueuedMovement = {}
    for uuid, _ in pairs(State.Session.MovementQueue) do
        hasQueuedMovement[uuid] = true
    end
    local combatGuid, narrativeCombatLabel
    -- Unpause NPC brawlers
    for uuid, brawler in pairs(M.Roster.getBrawlers()) do
        if not combatGuid then
            combatGuid = brawler.combatGuid
            narrativeCombatLabel = Utils.getNarrativeCombatLabel(combatGuid)
        end
        if M.Osi.IsPlayer(uuid) == 0 then
            brawler.isPaused = false
            Resources.resumeActionResourcesRefillTimers(brawler)
            unlock(Ext.Entity.Get(uuid))
            Osi.ForceTurnBasedMode(uuid, 0)
            stopTruePause(uuid)
            RT.joinCombat(uuid)
            if narrativeCombatLabel then
                Osi.PROC_GLO_NarrativeCombat_JoinCombat(narrativeCombatLabel, uuid)
            end
            local entity = Ext.Entity.Get(uuid)
            if entity and entity.TurnBased then
                entity.TurnBased.HadTurnInCombat = true
                entity.TurnBased.RequestedEndTurn = true
                entity.TurnBased.TurnActionsCompleted = true
                entity:Replicate("TurnBased")
            end
            RT.Timers.startPulseAction(brawler, 0)
        end
    end
    -- Unpause all party members (skip dead/downed — they never entered FTB via allEnterFTB)
    for uuid, _ in pairs(State.Session.Players) do
        if M.Osi.IsDead(uuid) == 0 and not M.Utils.isDowned(uuid) then
            unlock(Ext.Entity.Get(uuid))
            Osi.ForceTurnBasedMode(uuid, 0)
            Osi.SetCanJoinCombat(uuid, 1)
            stopTruePause(uuid)
            if narrativeCombatLabel then
                Osi.PROC_GLO_NarrativeCombat_JoinCombat(narrativeCombatLabel, uuid)
            end
            local entity = Ext.Entity.Get(uuid)
            if entity and entity.TurnBased then
                entity.TurnBased.IsActiveCombatTurn = true
                entity.TurnBased.HadTurnInCombat = false
                entity.TurnBased.RequestedEndTurn = false
                entity.TurnBased.TurnActionsCompleted = false
                entity:Replicate("TurnBased")
            end
            local brawler = Roster.getBrawlerByUuid(uuid)
            if brawler then
                brawler.isPaused = false
                Resources.resumeActionResourcesRefillTimers(brawler)
                if not State.isPlayerControllingDirectly(uuid) or State.Settings.FullAuto then
                    if not hasQueuedMovement[uuid] then
                        RT.Timers.startPulseAction(brawler, 0)
                    else
                        debugPrint(M.Utils.getDisplayName(uuid), "delaying pulse action for queued movement")
                    end
                end
            end
        end
    end
    -- Resume underlying combat. Helper may have lost its combat (e.g. during APoCS-induced combat churn);
    -- skip in that case rather than crashing on Osi.ResumeCombat(nil).
    if State.Session.CombatHelper then
        local helperCombat = M.Osi.CombatGetGuidFor(State.Session.CombatHelper)
        if helperCombat then
            Osi.ResumeCombat(helperCombat)
        end
    end
    TurnOrder.setPlayersSwarmGroup()
    if next(selectedDuringPause) then
        State.Session.PendingSelectCharOnLeftFTB = selectedDuringPause
    end
    if not combatGuid and State.Session.CombatHelper then
        combatGuid = M.Osi.CombatGetGuidFor(State.Session.CombatHelper)
    end
    if combatGuid then
        RT.Timers.resumeCombatRoundTimer(combatGuid)
    end
    Movement.resumeTimers()
    -- Process any deferred left-combat removals from during FTB
    if State.Session.PendingLeftCombat and next(State.Session.PendingLeftCombat) then
        local level = M.Osi.GetRegion(M.Osi.GetHostCharacter())
        for uuid, _ in pairs(State.Session.PendingLeftCombat) do
            if M.Roster.getBrawlerByUuid(uuid) then
                Roster.removeBrawler(level, uuid)
            end
        end
        State.Session.PendingLeftCombat = {}
        Roster.checkForEndOfBrawl(level)
    end
end

local function cancelQueuedMovement(uuid)
    if State.Session.MovementQueue[uuid] ~= nil and Osi.IsInForceTurnBasedMode(uuid) == 1 then
        local entity = Ext.Entity.Get(uuid)
        if entity and entity.TurnBased then
            State.Session.FTBLockedIn[uuid] = entity.TurnBased.RequestedEndTurn
        end
        State.Session.MovementQueue[uuid] = nil
        Movement.resumeTimers()
        Swarm.resumeTimers()
    end
end

local function midActionLock(entity)
    if entity and entity.Uuid and entity.Uuid.EntityUuid then
        debugPrint("midActionLock", M.Utils.getDisplayName(entity.Uuid.EntityUuid))
        if entity.SpellCastIsCasting and entity.SpellCastIsCasting.Cast then
            local spellCastState = entity.SpellCastIsCasting.Cast.SpellCastState
            debugPrint("got spellcast state")
            if spellCastState and spellCastState.Targets then
                local target = spellCastState.Targets[1]
                if target and (target.Position or target.Target) then
                    lock(entity)
                    State.Session.MovementQueue[entity.Uuid.EntityUuid] = nil
                    Movement.pauseTimers()
                    Swarm.pauseTimers()
                end
            end
        end
    end
end

local function isInFTB(entity)
    return entity.FTBParticipant and entity.FTBParticipant.field_18 ~= nil
end

local function isFTBAllLockedIn()
    for uuid, _ in pairs(State.Session.Players) do
        if not State.Session.FTBLockedIn[uuid] and M.Osi.IsDead(uuid) == 0 and not M.Utils.isDowned(uuid) then
            return false
        end
    end
    return true
end

local function isActionFinalized(entity)
    return entity.SpellCastIsCasting and entity.SpellCastIsCasting.Cast and entity.SpellCastIsCasting.Cast.SpellCastState
end

local function startTurnBasedListener(entityUuid)
    if State.Session.TurnBasedListeners[entityUuid] ~= nil then
        Ext.Entity.Unsubscribe(State.Session.TurnBasedListeners[entityUuid])
        State.Session.TurnBasedListeners[entityUuid] = nil
    end
    State.Session.TurnBasedListeners[entityUuid] = Ext.Entity.Subscribe("TurnBased", function (caster, _, _)
        -- NB: requested end turn isn't the only thing that can change here...
        if caster and caster.TurnBased then
            State.Session.FTBLockedIn[entityUuid] = caster.TurnBased.RequestedEndTurn
            if isFTBAllLockedIn() then
                allExitFTB()
            end
        end
    end, Ext.Entity.Get(entityUuid))
end

local function startTranslateChangedEventListener(entityUuid)
    if State.Session.TranslateChangedEventListeners[entityUuid] ~= nil then
        Ext.Entity.Unsubscribe(State.Session.TranslateChangedEventListeners[entityUuid])
        State.Session.TranslateChangedEventListeners[entityUuid] = nil
    end
    -- NB: need to account for already-in-motion NPCs also
    State.Session.TranslateChangedEventListeners[entityUuid] = Ext.Entity.OnCreateDeferred("TranslateChangedEvent", function (movingEntity, _, _)
        if movingEntity.Uuid and movingEntity.Uuid.EntityUuid and isInFTB(movingEntity) then
            local uuid = movingEntity.Uuid.EntityUuid
            debugPrint(M.Utils.getDisplayName(uuid), "movement while paused")
            local activeMovement = Movement.getActiveMovement(uuid)
            debugPrint(M.Utils.getDisplayName(uuid), "ActiveMovement")
            debugDump(activeMovement)
            debugPrint(M.Utils.getDisplayName(uuid), "LastClickPosition")
            debugDump(State.Session.LastClickPosition[uuid])
            local goalPosition
            if activeMovement and activeMovement.goalPosition then
                goalPosition = activeMovement.goalPosition
            elseif State.Session.LastClickPosition[uuid] and State.Session.LastClickPosition[uuid].position then
                goalPosition = State.Session.LastClickPosition[uuid].position
            end
            if goalPosition then
                lock(movingEntity)
                Movement.findPathToPosition(uuid, goalPosition, function (err, validPosition)
                    if err then
                        return Utils.showNotification(uuid, err)
                    end
                    debugPrint("found path (valid)", validPosition[1], validPosition[2], validPosition[3])
                    State.Session.MovementQueue[uuid] = {validPosition[1], validPosition[2], validPosition[3]}
                end)
            end
        end
    end, Ext.Entity.Get(entityUuid))
end

local function startSpellCastPrepareEndEventListener(entityUuid)
    if State.Session.SpellCastPrepareEndEventListeners[entityUuid] ~= nil then
        Ext.Entity.Unsubscribe(State.Session.SpellCastPrepareEndEventListeners[entityUuid])
        State.Session.SpellCastPrepareEndEventListeners[entityUuid] = nil
    end
    State.Session.SpellCastPrepareEndEventListeners[entityUuid] = Ext.Entity.OnCreateDeferred("SpellCastPrepareEndEvent", function (cast, _, _)
        if cast.SpellCastState and cast.SpellCastState.Caster then
            local caster = cast.SpellCastState.Caster
            if caster.Uuid.EntityUuid == entityUuid then
                debugPrint("***************SpellCastPrepareEndEvent", entityUuid)
                if isInFTB(caster) and isActionFinalized(caster) and not isLocked(caster) then
                    local spellName = cast.SpellCastState.SpellId and cast.SpellCastState.SpellId.OriginatorPrototype
                    local spell = spellName and M.Spells.getSpellByName(spellName)
                    -- Fallback reaction detection: some reaction spells (e.g.
                    -- Target_DivineAllegiance) have empty UseCosts so our
                    -- isReaction flag is false for them. The engine applies
                    -- the REACTION status to the caster while the reaction is
                    -- resolving; treat that as a reaction cast and skip lock.
                    local hasReactionStatus = false
                    if caster.ServerCharacter and caster.ServerCharacter.StatusManager
                            and caster.ServerCharacter.StatusManager.Statuses then
                        for _, status in ipairs(caster.ServerCharacter.StatusManager.Statuses) do
                            if status.StatusId == "REACTION" then
                                hasReactionStatus = true
                                break
                            end
                        end
                    end
                    debugPrint(string.format("[ReactionCheck] uuid=%s spell=%s inTable=%s isReaction=%s isBonusAction=%s hasReactionStatus=%s",
                        tostring(entityUuid), tostring(spellName),
                        tostring(spell ~= nil),
                        tostring(spell and spell.isReaction),
                        tostring(spell and spell.isBonusAction),
                        tostring(hasReactionStatus)))
                    -- Reactions (e.g. Divine Allegiance, Shield) can be engine-fired automatically; locking can strand the character greyed-out mid-reaction.
                    if (spell and spell.isReaction) or hasReactionStatus then
                        debugPrint("[ReactionCheck]   -> skipping midActionLock")
                        return
                    end
                    if State.Settings.NoFreezeOnBonusActionsDuringPause and spell and spell.isBonusAction and M.Osi.IsPartyMember(entityUuid, 1) == 1 then
                        return
                    end
                    -- If this is the tail-end of a cast that was already in flight when pause hit (flagged in allEnterFTB), let it
                    -- complete without locking. 2s expiry handles the case where the event never fires for this cast.
                    local expiry = State.Session.PreExistingCastAtPause[entityUuid]
                    if expiry and Ext.Utils.MonotonicTime() < expiry then
                        State.Session.PreExistingCastAtPause[entityUuid] = nil
                        return
                    end
                    midActionLock(caster)
                end
            end
        end
    end)
end

-- NB: sometimes ClientControl isn't a valid marker and we end up with 2 characters both marked as directly controlled, so things like cancel queue movement break
local function startTruePause(entityUuid)
    -- eoc::ActionResourcesComponent: Replicated
    -- eoc::spell_cast::TargetsChangedEventOneFrameComponent: Created
    -- eoc::spell_cast::PreviewEndEventOneFrameComponent: Created
    -- eoc::TurnBasedComponent: Replicated (all characters)
    -- movement only triggers ActionResources
    --      only pay attention to this if it doesn't occur after a spellcastmovement
    -- move-then-act triggers SpellCastMovement, (TurnBased?), ActionResources
    --      if SpellCastMovement triggered, then ignore the next action resources trigger
    -- act (incl. jump) triggers SpellCastMovement, (TurnBased?)
    if M.Utils.isAliveAndCanFight(entityUuid) then
        debugPrint("startTruePause", entityUuid, M.Utils.getDisplayName(entityUuid))
        Utils.clearOsirisQueue(entityUuid)
        startTurnBasedListener(entityUuid)
        startTranslateChangedEventListener(entityUuid)
        startSpellCastPrepareEndEventListener(entityUuid)
    end
end

local function queueSingleCompanionAIActions(uuid)
    if State.Settings.CompanionAIEnabled and State.Session.Players and State.Session.Players[uuid] then
        debugPrint(M.Utils.getDisplayName(uuid), "queueSingleCompanionAIActions")
        local player = State.Session.Players[uuid]
        local brawler = M.Roster.getBrawlerByUuid(uuid)
        if brawler and M.Utils.isAliveAndCanFight(uuid) and (not player.isControllingDirectly or State.Settings.FullAuto) and M.Utils.canAct(uuid) then
            local entity = Ext.Entity.Get(uuid)
            if State.Settings.TurnBasedSwarmMode then
                if entity and entity.TurnBased and entity.TurnBased.IsActiveCombatTurn and not entity.TurnBased.RequestedEndTurn then
                    State.Session.QueuedCompanionAIAction[uuid] = true
                    debugPrint(player.displayName, "queue action (swarm)")
                    Swarm.swarmAction(brawler)
                end
            else
                debugPrint(player.displayName, "queue action (ftb)", isInFTB(entity), not isLocked(entity))
                if isInFTB(entity) and not isLocked(entity) then
                    AI.act(brawler, false, _D, _D, _D)
                end
            end
        end
    end
end

local function queueCompanionAIActions()
    if State.Settings.CompanionAIEnabled and State.Session.Players then
        debugPrint("queueCompanionAIActions")
        for uuid, _ in pairs(State.Session.Players) do
            queueSingleCompanionAIActions(uuid)
        end
    end
end

local function isPartyInFTB()
    if State.Session.Players then
        for uuid, _ in pairs(State.Session.Players) do
            if M.Osi.IsInForceTurnBasedMode(uuid) == 1 then
                return true
            end
        end
    end
    return false
end

local function checkTruePauseParty()
    debugPrint("checkTruePauseParty")
    local players = State.Session.Players
    if players then
        if State.Settings.TruePause then
            for uuid, _ in pairs(players) do
                if Osi.IsInForceTurnBasedMode(uuid) == 1 then
                    startTruePause(uuid)
                else
                    stopTruePause(uuid)
                end
            end
        else
            for uuid, _ in pairs(players) do
                stopTruePause(uuid)
                unlock(Ext.Entity.Get(uuid))
            end
        end
    end
end

return {
    isInFTB = isInFTB,
    isLocked = isLocked,
    allEnterFTB = allEnterFTB,
    allExitFTB = allExitFTB,
    cancelQueuedMovement = cancelQueuedMovement,
    startTruePause = startTruePause,
    queueSingleCompanionAIActions = queueSingleCompanionAIActions,
    queueCompanionAIActions = queueCompanionAIActions,
    isPartyInFTB = isPartyInFTB,
    checkTruePauseParty = checkTruePauseParty,
    midActionLock = midActionLock,
    lock = lock,
    unlock = unlock,
}
