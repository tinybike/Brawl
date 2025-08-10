local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump

local function isLocked(entity)
    print(M.Utils.getDisplayName(entity.Uuid.EntityUuid), "isLocked", entity.TurnBased.CanActInCombat, entity.TurnBased.HadTurnInCombat, entity.TurnBased.IsActiveCombatTurn)
    return entity.TurnBased.CanActInCombat and entity.TurnBased.HadTurnInCombat and not entity.TurnBased.IsActiveCombatTurn
end

local function unlock(entity)
    if entity and entity.Uuid then
        print("unlock", entity.Uuid.EntityUuid, isLocked(entity))
        -- debugDump(entity.TurnBased)
        entity.TurnBased.IsActiveCombatTurn = true
        entity:Replicate("TurnBased")
        local uuid = entity.Uuid.EntityUuid
        State.Session.FTBLockedIn[uuid] = false
        if State.Session.MovementQueue[uuid] then
            print("unloading movement queue for", uuid)
            if State.Session.ActionResourcesListeners[uuid] ~= nil then
                Ext.Entity.Unsubscribe(State.Session.ActionResourcesListeners[uuid])
                State.Session.ActionResourcesListeners[uuid] = nil
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
        print("locking", uuid)
        Roster.disableLockedOnTarget(uuid)
        entity.TurnBased.IsActiveCombatTurn = false
        State.Session.FTBLockedIn[uuid] = true
    end
end

local function stopTruePause(entityUuid)
    local entity = Ext.Entity.Get(entityUuid)
    if entity and entity.Vars then
        entity.Vars.IsPaused = false
    end
    if State.Session.ActionResourcesListeners[entityUuid] ~= nil then
        Ext.Entity.Unsubscribe(State.Session.ActionResourcesListeners[entityUuid])
        State.Session.ActionResourcesListeners[entityUuid] = nil
    end
    if State.Session.TurnBasedListeners[entityUuid] ~= nil then
        Ext.Entity.Unsubscribe(State.Session.TurnBasedListeners[entityUuid])
        State.Session.TurnBasedListeners[entityUuid] = nil
    end
    if State.Session.SpellCastPrepareEndEvent[entityUuid] ~= nil then
        Ext.Entity.Unsubscribe(State.Session.SpellCastPrepareEndEvent[entityUuid])
        State.Session.SpellCastPrepareEndEvent[entityUuid] = nil
    end
end

local function allEnterFTB()
    if not State.Settings.TurnBasedSwarmMode then
        print("allEnterFTB")
        Utils.pinNotification("PAUSED")
        if Utils.isToT() then
            stopToTTimers()
        end
        for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
            local uuid = M.Osi.GetUUID(player[1])
            -- Osi.SetCanJoinCombat(uuid, 0)
            -- Osi.ForceTurnBasedMode(uuid, 1)
            Listeners.onEnteredForceTurnBased(uuid)
        end
        local host = M.Osi.GetHostCharacter()
        if host then
            local level = M.Osi.GetRegion(host)
            if level then
                local brawlersInLevel = State.Session.Brawlers[level]
                if brawlersInLevel then
                    for brawlerUuid, brawler in pairs(brawlersInLevel) do
                        stopPulseAction(brawler, true)
                        brawler.isPaused = true
                        if M.Osi.IsPlayer(brawlerUuid) == 0 then
                            -- Osi.ForceTurnBasedMode(brawlerUuid, 1)
                            Listeners.onEnteredForceTurnBased(brawlerUuid)
                            Pause.startTruePause(brawlerUuid)
                        end
                    end
                end
            end
        end
    end
end

local function allExitFTB()
    if not State.Settings.TurnBasedSwarmMode then
        Utils.clearNotification()
        print("allExitFTB")
        State.Session.IsPaused = false
        for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
            local uuid = M.Osi.GetUUID(player[1])
            unlock(Ext.Entity.Get(uuid))
            -- Osi.ForceTurnBasedMode(uuid, 0)
            -- Osi.SetCanJoinCombat(uuid, 1)
            Listeners.onLeftForceTurnBased(uuid)
            stopTruePause(uuid)
        end
        local host = M.Osi.GetHostCharacter()
        if host then
            local level = M.Osi.GetRegion(host)
            if level then
                local brawlersInLevel = State.Session.Brawlers[level]
                if brawlersInLevel then
                    for brawlerUuid, brawler in pairs(brawlersInLevel) do
                        if (not State.isPlayerControllingDirectly(brawlerUuid) or State.Settings.FullAuto) and M.Utils.isAliveAndCanFight(brawlerUuid) then
                            startPulseAction(brawler)
                        end
                        brawler.isPaused = false
                        if M.Osi.IsPlayer(brawlerUuid) == 0 then
                            unlock(Ext.Entity.Get(brawlerUuid))
                            Listeners.onLeftForceTurnBased(brawlerUuid)
                            -- Osi.ForceTurnBasedMode(brawlerUuid, 0)
                            stopTruePause(brawlerUuid)
                        end
                    end
                end
            end
        end
    end
end

local function cancelQueuedMovement(uuid)
    if State.Session.MovementQueue[uuid] ~= nil and Osi.IsInForceTurnBasedMode(uuid) == 1 then
        local entity = Ext.Entity.Get(uuid)
        if entity and entity.TurnBased then
            State.Session.FTBLockedIn[uuid] = entity.TurnBased.RequestedEndTurn
        end
        State.Session.MovementQueue[uuid] = nil
    end
end

local function midActionLock(entity)
    if entity and entity.Uuid and entity.Uuid.EntityUuid then
        print("midActionLock", M.Utils.getDisplayName(entity.Uuid.EntityUuid))
        if entity.SpellCastIsCasting and entity.SpellCastIsCasting.Cast then
            local spellCastState = entity.SpellCastIsCasting.Cast.SpellCastState
            print("got spellcast state")
            if spellCastState and spellCastState.Targets then
                local target = spellCastState.Targets[1]
                if target and (target.Position or target.Target) then
                    lock(entity)
                    State.Session.MovementQueue[entity.Uuid.EntityUuid] = nil
                end
            end
        end
    end
end

local function isInFTB(entity)
    return entity.Vars.IsPaused
    -- return entity.FTBParticipant and entity.FTBParticipant.field_18 ~= nil
end

local function isFTBAllLockedIn()
    -- debugDump(State.Session.FTBLockedIn)
    for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
        local uuid = M.Osi.GetUUID(player[1])
        -- print("checking ftb for", uuid, Osi.IsInForceTurnBasedMode(uuid))
        if not State.Session.FTBLockedIn[uuid] and M.Osi.IsDead(uuid) == 0 and not M.Utils.isDowned(uuid) then
            return false
        end
    end
    return true
end

local function isActionFinalized(entity)
    print("isActionFinalized", entity.SpellCastIsCasting, entity.SpellCastIsCasting.Cast, entity.SpellCastIsCasting.Cast.SpellCastState)
    return entity.SpellCastIsCasting and entity.SpellCastIsCasting.Cast and entity.SpellCastIsCasting.Cast.SpellCastState
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
        print("startTruePause", entityUuid, M.Utils.getDisplayName(entityUuid))
        Utils.clearOsirisQueue(entityUuid)
        local entity = Ext.Entity.Get(entityUuid)
        if entity and entity.Vars then
            entity.Vars.IsPaused = true
        end
        if State.Session.TurnBasedListeners[entityUuid] ~= nil then
            Ext.Entity.Unsubscribe(State.Session.TurnBasedListeners[entityUuid])
            State.Session.TurnBasedListeners[entityUuid] = nil
        end
        State.Session.TurnBasedListeners[entityUuid] = Ext.Entity.Subscribe("TurnBased", function (caster, _, _)
            -- requested end turn isn't the only thing that can change here
            -- print("TurnBased", entityUuid, State.Session.FTBLockedIn[entityUuid], caster.TurnBased.RequestedEndTurn)
            if caster and caster.TurnBased then
                State.Session.FTBLockedIn[entityUuid] = caster.TurnBased.RequestedEndTurn
                if State.Session.FTBLockedIn[entityUuid] then
                    print("TurnBased", entityUuid, State.Session.FTBLockedIn[entityUuid], caster.TurnBased.RequestedEndTurn)
                end
                if isFTBAllLockedIn() then
                    print("all locked in, exiting") 
                    allExitFTB()
                end
            end
        end, entity)
        if State.Session.ActionResourcesListeners[entityUuid] ~= nil then
            Ext.Entity.Unsubscribe(State.Session.ActionResourcesListeners[entityUuid])
            State.Session.ActionResourcesListeners[entityUuid] = nil
        end
        State.Session.ActionResourcesListeners[entityUuid] = Ext.Entity.Subscribe("ActionResources", function (movingEntity, _, _)
            if State.Session.RemainingMovement[entityUuid] ~= nil and M.Movement.getRemainingMovement(movingEntity) < State.Session.RemainingMovement[entityUuid] then
                if entityUuid and isInFTB(movingEntity) then
                    if State.Session.LastClickPosition[entityUuid] and State.Session.LastClickPosition[entityUuid].position then
                        print("******************MOVEMENT LOCK enqueue movement (raw coords)", entityUuid)
                        debugDump(State.Session.LastClickPosition[entityUuid].position)
                        lock(movingEntity)
                        M.Movement.findPathToPosition(entityUuid, State.Session.LastClickPosition[entityUuid].position, function (err, validPosition)
                            if err then
                                return Utils.showNotification(entityUuid, err, 2)
                            end
                            print("found path (valid)", validPosition[1], validPosition[2], validPosition[3])
                            State.Session.MovementQueue[entityUuid] = {validPosition[1], validPosition[2], validPosition[3]}
                        end)
                    end
                end
            end
            State.Session.RemainingMovement[entityUuid] = M.Movement.getRemainingMovement(entity)
        end, entity)
        if State.Session.SpellCastPrepareEndEvent[entityUuid] ~= nil then
            Ext.Entity.Unsubscribe(State.Session.SpellCastPrepareEndEvent[entityUuid])
            State.Session.SpellCastPrepareEndEvent[entityUuid] = nil
        end
        State.Session.SpellCastPrepareEndEvent[entityUuid] = Ext.Entity.OnCreateDeferred("SpellCastPrepareEndEvent", function (cast, _, _)
            print("SpellCastPrepareEndEvent", M.Utils.getDisplayName(cast.SpellCastState.Caster.Uuid.EntityUuid))
            local caster = cast.SpellCastState.Caster
            if caster.Uuid.EntityUuid == entityUuid then
                print("***************SpellCastPrepareEndEvent", entityUuid, isInFTB(caster), isActionFinalized(caster), not isLocked(caster))
                if isInFTB(caster) and isActionFinalized(caster) then --and not isLocked(caster) then
                    midActionLock(caster)
                end
            end
        end)
        -- Enqueue actions/movements for non-party NPCs
        if M.Osi.IsPartyMember(entityUuid, 1) == 0 and M.Utils.canAct(entityUuid) and not isLocked(entity) then
            AI.act(M.Roster.getBrawlerByUuid(entityUuid))
        end
    end
end

local function queueCompanionAIActions()
    print("queueCompanionAIActions")
    if State.Settings.CompanionAIEnabled then
        local players = State.Session.Players
        if players then
            for uuid, player in pairs(players) do
                if M.Utils.isAliveAndCanFight(uuid) and (not player.isControllingDirectly or State.Settings.FullAuto) and M.Utils.canAct(uuid) then
                    local entity = Ext.Entity.Get(uuid)
                    if State.Settings.TurnBasedSwarmMode then
                        if entity and entity.TurnBased and entity.TurnBased.IsActiveCombatTurn and not entity.TurnBased.RequestedEndTurn then
                            State.Session.QueuedCompanionAIAction[uuid] = true
                            print("queue action (swarm)", player.displayName)
                            Swarm.swarmAction(M.Roster.getBrawlerByUuid(uuid))
                        end
                    else
                        print("queue action (ftb)", player.displayName, isInFTB(entity), not isLocked(entity))
                        if isInFTB(entity) and not isLocked(entity) then
                            AI.act(M.Roster.getBrawlerByUuid(uuid))
                        end
                    end
                end
            end
        end
    end
end

local function checkTruePauseParty()
    print("checkTruePauseParty")
    if State.Session.Players then
        for uuid, _ in pairs(State.Session.Players) do
            if Osi.IsInForceTurnBasedMode(uuid) == 1 then
                startTruePause(uuid)
            else
                stopTruePause(uuid)
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
    queueCompanionAIActions = queueCompanionAIActions,
    checkTruePauseParty = checkTruePauseParty,
    midActionLock = midActionLock,
    lock = lock,
    unlock = unlock,
}
