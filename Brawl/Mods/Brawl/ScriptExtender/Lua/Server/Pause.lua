local function isLocked(entity)
    return entity.TurnBased.CanAct_M and entity.TurnBased.HadTurnInCombat and not entity.TurnBased.IsInCombat_M
end
local function unlock(entity)
    if isLocked(entity) then
        entity.TurnBased.IsInCombat_M = true
        entity:Replicate("TurnBased")
        local uuid = entity.Uuid.EntityUuid
        State.Session.FTBLockedIn[uuid] = false
        if State.Session.MovementQueue[uuid] then
            if State.Session.ActionResourcesListeners[uuid] ~= nil then
                Ext.Entity.Unsubscribe(State.Session.ActionResourcesListeners[uuid])
                State.Session.ActionResourcesListeners[uuid] = nil
            end
            local moveTo = State.Session.MovementQueue[uuid]
            Movement.moveToPosition(uuid, moveTo,)
            State.Session.MovementQueue[uuid] = nil
        end
    end
end
local function lock(entity)
    entity.TurnBased.IsInCombat_M = false
    State.Session.FTBLockedIn[entity.Uuid.EntityUuid] = true
end
local function stopTruePause(entityUuid)
    if Osi.IsPartyMember(entityUuid, 1) == 1 then
        if State.Session.ActionResourcesListeners[entityUuid] ~= nil then
            Ext.Entity.Unsubscribe(State.Session.ActionResourcesListeners[entityUuid])
            State.Session.ActionResourcesListeners[entityUuid] = nil
        end
        if State.Session.TurnBasedListeners[entityUuid] ~= nil then
            Ext.Entity.Unsubscribe(State.Session.TurnBasedListeners[entityUuid])
            State.Session.TurnBasedListeners[entityUuid] = nil
        end
        if State.Session.SpellCastMovementListeners[entityUuid] ~= nil then
            Ext.Entity.Unsubscribe(State.Session.SpellCastMovementListeners[entityUuid])
            State.Session.SpellCastMovementListeners[entityUuid] = nil
        end
    end
end
local function allEnterFTB()
    for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
        local uuid = Osi.GetUUID(player[1])
        Osi.ForceTurnBasedMode(uuid, 1)
    end
end
local function allExitFTB()
    for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
        local uuid = Osi.GetUUID(player[1])
        unlock(Ext.Entity.Get(uuid))
        Osi.ForceTurnBasedMode(uuid, 0)
        stopTruePause(uuid)
    end
end
local function cancelQueuedMovement(uuid)
    if State.Session.MovementQueue[uuid] ~= nil and Osi.IsInForceTurnBasedMode(uuid) == 1 then
        State.Session.MovementQueue[uuid] = nil
    end
end
local function midActionLock(entity)
    local spellCastState = entity.SpellCastIsCasting.Cast.SpellCastState
    if spellCastState.Targets then
        local target = spellCastState.Targets[1]
        if target and (target.Position or target.Target) then
            lock(entity)
            State.Session.MovementQueue[entity.Uuid.EntityUuid] = nil
        end
    end
end
local function isInFTB(entity)
    return entity.FTBParticipant and entity.FTBParticipant.field_18 ~= nil
end
local function enqueueMovement(entity)
    local uuid = entity.Uuid.EntityUuid
    if uuid and isInFTB(entity) and (not isLocked(entity) or State.Session.MovementQueue[uuid]) then
        if State.Session.LastClickPosition[uuid] and State.Session.LastClickPosition[uuid].position then
            lock(entity)
            local position = State.Session.LastClickPosition[uuid].position
            State.Session.MovementQueue[uuid] = {position[1], position[2], position[3]}
        end
    end
end
local function isFTBAllLockedIn()
    for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
        local uuid = Osi.GetUUID(player[1])
        if not State.Session.FTBLockedIn[uuid] and Osi.IsDead(uuid) == 0 and not isDowned(uuid) then
            return false
        end
    end
    return true
end
local function isActionFinalized(entity)
    return entity.SpellCastIsCasting and entity.SpellCastIsCasting.Cast and entity.SpellCastIsCasting.Cast.SpellCastState
end
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
    if Osi.IsPartyMember(entityUuid, 1) == 1 then
        if State.Session.SpellCastMovementListeners[entityUuid] == nil then
            local entity = Ext.Entity.Get(entityUuid)
            State.Session.TurnBasedListeners[entityUuid] = Ext.Entity.Subscribe("TurnBased", function (caster, _, _)
                if caster and caster.TurnBased then
                    State.Session.FTBLockedIn[entityUuid] = caster.TurnBased.RequestedEndTurn
                end
                if isFTBAllLockedIn() then
                    debugPrint("All locked in, auto-exiting FTB...")
                    allExitFTB()
                end
            end, entity)
            State.Session.ActionResourcesListeners[entityUuid] = Ext.Entity.Subscribe("ActionResources", function (caster, _, _)
                enqueueMovement(caster)
            end, entity)
            -- NB: can specify only the specific cast entity?
            State.Session.SpellCastMovementListeners[entityUuid] = Ext.Entity.OnCreateDeferred("SpellCastMovement", function (cast, _, _)
                local caster = cast.SpellCastState.Caster
                if caster.Uuid.EntityUuid == entityUuid then
                    if State.Session.ActionResourcesListeners[entityUuid] ~= nil then
                        Ext.Entity.Unsubscribe(State.Session.ActionResourcesListeners[entityUuid])
                        State.Session.ActionResourcesListeners[entityUuid] = nil
                    end
                    if isInFTB(caster) and isActionFinalized(caster) then
                        midActionLock(caster)
                    end
                end
            end)
        end
    end
end
local function checkTruePauseParty()
    if State.Settings.TruePause then
        for uuid, _ in pairs(State.Session.Players) do
            if Osi.IsInForceTurnBasedMode(uuid) == 1 then
                startTruePause(uuid)
            else
                stopTruePause(uuid)
            end
        end
    else
        for uuid, _ in pairs(State.Session.Players) do
            stopTruePause(uuid)
            unlock(Ext.Entity.Get(uuid))
        end
    end
end

Pause = {
    allEnterFTB = allEnterFTB,
    allExitFTB = allExitFTB,
    cancelQueuedMovement = cancelQueuedMovement,
    enqueueMovement = enqueueMovement,
    startTruePause = startTruePause,
    checkTruePauseParty = checkTruePauseParty,
}
