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
            Movement.moveToPosition(uuid, moveTo, false)
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

-- NB: need to either disable the built-in AI or force-pause it during pause
local function allEnterFTB()
    if not State.Settings.TurnBasedSwarmMode then
        debugPrint("allEnterFTB")
        if State.Session.CombatHelper then
            Osi.PauseCombat(M.Osi.CombatGetGuidFor(State.Session.CombatHelper))
        end
        RT.Timers.pauseCombatRoundTimers()
        -- RT.Timers.stopAllPulseActions(true)
        for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
            if player and player[1] then
                local uuid = M.Osi.GetUUID(player[1])
                if uuid then
                    Osi.SetCanJoinCombat(uuid, 0)
                    Osi.ForceTurnBasedMode(uuid, 1)
                end
            end
        end
        for uuid, brawler in pairs(M.Roster.getBrawlers()) do
            RT.Timers.stopPulseAction(brawler, true)
            brawler.isPaused = true
            if M.Osi.IsPlayer(uuid) == 0 then
                Osi.ForceTurnBasedMode(uuid, 1)
                Pause.startTruePause(uuid)
            end
        end
    end
end

-- NB: points timers should never be firing while paused, why is this happening?
local function allExitFTB()
    if not State.Settings.TurnBasedSwarmMode then
        debugPrint("allExitFTB")
        for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
            local uuid = M.Osi.GetUUID(player[1])
            if uuid then
                unlock(Ext.Entity.Get(uuid))
                Osi.ForceTurnBasedMode(uuid, 0)
                Osi.SetCanJoinCombat(uuid, 1)
                stopTruePause(uuid)
            end
        end
        local combatGuid
        for uuid, brawler in pairs(M.Roster.getBrawlers()) do
            if not combatGuid then
                combatGuid = brawler.combatGuid
            end
            if M.Osi.IsPlayer(uuid) == 0 then
                unlock(Ext.Entity.Get(uuid))
                Osi.ForceTurnBasedMode(uuid, 0)
                stopTruePause(uuid)
                Utils.joinCombat(uuid)
            end
        end
        if State.Session.CombatHelper then
            Osi.ResumeCombat(M.Osi.CombatGetGuidFor(State.Session.CombatHelper))
        end
        Utils.setPlayersSwarmGroup()
        Utils.setPlayerTurnsActive()
        if combatGuid then
            RT.Timers.resumeCombatRoundTimer(combatGuid)
        end
        Movement.resumeTimers()
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
    for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
        if player and player[1] then
            local uuid = M.Osi.GetUUID(player[1])
            if uuid and not State.Session.FTBLockedIn[uuid] and M.Osi.IsDead(uuid) == 0 and not M.Utils.isDowned(uuid) then
                return false
            end
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
                    if State.Settings.NoFreezeOnBonusActionsDuringPause and cast.SpellCastState.SpellId and cast.SpellCastState.SpellId.OriginatorPrototype and M.Osi.IsPartyMember(entityUuid, 1) == 1 then
                        local spell = M.Spells.getSpellByName(cast.SpellCastState.SpellId.OriginatorPrototype)
                        if spell and spell.isBonusAction then
                            return
                        end
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
        -- NB: this doesn't always stop NPCs dead in their tracks, why not?
        Utils.clearOsirisQueue(entityUuid)
        startTurnBasedListener(entityUuid)
        startTranslateChangedEventListener(entityUuid)
        startSpellCastPrepareEndEventListener(entityUuid)
        if Osi.IsPartyMember(entityUuid, 1) == 0 and Utils.canAct(entityUuid) and not isLocked(Ext.Entity.Get(entityUuid)) then
            debugPrint("AI acting automatically for NPC", M.Utils.getDisplayName(entityUuid))
            AI.act(M.Roster.getBrawlerByUuid(entityUuid), false, function (request)
                debugPrint(M.Utils.getDisplayName(entityUuid), "submitted", request.Spell.Prototype)
            end, function (spellName)
                debugPrint(M.Utils.getDisplayName(entityUuid), "completed", spellName)
            end, function (err)
                debugPrint(M.Utils.getDisplayName(entityUuid), "failed", err)
            end)
        end
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
    enqueueMovement = enqueueMovement,
    startTruePause = startTruePause,
    queueSingleCompanionAIActions = queueSingleCompanionAIActions,
    queueCompanionAIActions = queueCompanionAIActions,
    isPartyInFTB = isPartyInFTB,
    checkTruePauseParty = checkTruePauseParty,
    midActionLock = midActionLock,
    lock = lock,
    unlock = unlock,
}
