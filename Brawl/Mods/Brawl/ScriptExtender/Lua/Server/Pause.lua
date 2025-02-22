-- local Utils = require("Server/Utils.lua")
-- local State = require("Server/State.lua")
-- local Movement = require("Server/Movement.lua")

local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump

local function isLocked(entity)
    return entity.TurnBased.CanAct_M and entity.TurnBased.HadTurnInCombat and not entity.TurnBased.IsInCombat_M
end

local function unlock(entity)
    debugPrint("unlock", entity.Uuid.EntityUuid)
    if isLocked(entity) then
        entity.TurnBased.IsInCombat_M = true
        entity:Replicate("TurnBased")
        local uuid = entity.Uuid.EntityUuid
        State.Session.FTBLockedIn[uuid] = false
        if State.Session.MovementQueue[uuid] then
            debugPrint("unloading movement queue for", uuid)
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
    local uuid = entity.Uuid.EntityUuid
    debugPrint("locking", uuid)
    Roster.disableLockedOnTarget(uuid)
    entity.TurnBased.IsInCombat_M = false
    State.Session.FTBLockedIn[uuid] = true
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
    debugPrint("allExitFTB")
    for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
        local uuid = Osi.GetUUID(player[1])
        unlock(Ext.Entity.Get(uuid))
        Osi.ForceTurnBasedMode(uuid, 0)
        stopTruePause(uuid)
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

local function isFTBAllLockedIn()
    debugDump(State.Session.FTBLockedIn)
    for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
        local uuid = Osi.GetUUID(player[1])
        debugPrint("checking ftb for", uuid, Osi.IsInForceTurnBasedMode(uuid))
        if not State.Session.FTBLockedIn[uuid] and Osi.IsDead(uuid) == 0 and not Utils.isDowned(uuid) then
            return false
        end
    end
    return true
end

local function isActionFinalized(entity)
    return entity.SpellCastIsCasting and entity.SpellCastIsCasting.Cast and entity.SpellCastIsCasting.Cast.SpellCastState
end

-- 1. Sometimes pause comes unglued on its own, no idea why -- it's happening thru the onLeftFTB in Listeners.lua -- somehow one character pops out and then everyone does
--    Should this logic all be in Pause.lua instead? can it get triggered incorrectly? (e.g. downed players?)
-- 2. Sometimes the characters aren't at the same "initiative" (turn order) even tho there's no initiative in pause -- is this actually an initiative problem or?
-- 3. Sometimes ClientControl isn't a valid marker and we end up with 2 characters both marked as directly controlled, so things like cancel queue movement break
-- 4. Sometimes spellcast listener triggers when it's not supposed to, use ECSPrinter to see wtf this is about? Hard to tell what's changing. Is this somehow causing it to unpause?
-- 5. Downed players aren't accounted for correctly somehow
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
    debugPrint("startTruePause", entityUuid)
    if Osi.IsPartyMember(entityUuid, 1) == 1 then
        local entity = Ext.Entity.Get(entityUuid)
        debugPrint(entity)
        if State.Session.TurnBasedListeners[entityUuid] ~= nil then
            Ext.Entity.Unsubscribe(State.Session.TurnBasedListeners[entityUuid])
            State.Session.TurnBasedListeners[entityUuid] = nil
        end
        State.Session.TurnBasedListeners[entityUuid] = Ext.Entity.Subscribe("TurnBased", function (caster, _, _)
            -- requested end turn isn't the only thing that can change here
            debugPrint("TurnBased", entityUuid, State.Session.FTBLockedIn[entityUuid], caster.TurnBased.RequestedEndTurn)
            if caster and caster.TurnBased then
                State.Session.FTBLockedIn[entityUuid] = caster.TurnBased.RequestedEndTurn
                if isFTBAllLockedIn() then
                    debugPrint("all locked in, exiting") 
                    allExitFTB()
                end
            end
        end, entity)
        if State.Session.ActionResourcesListeners[entityUuid] ~= nil then
            Ext.Entity.Unsubscribe(State.Session.ActionResourcesListeners[entityUuid])
            State.Session.ActionResourcesListeners[entityUuid] = nil
        end
        State.Session.ActionResourcesListeners[entityUuid] = Ext.Entity.Subscribe("ActionResources", function (movingEntity, _, _)
            if State.Session.RemainingMovement[entityUuid] ~= nil and Movement.getRemainingMovement(movingEntity) < State.Session.RemainingMovement[entityUuid] then
                if entityUuid and isInFTB(movingEntity) then
                    if State.Session.LastClickPosition[entityUuid] and State.Session.LastClickPosition[entityUuid].position then
                        debugPrint("enqueue movement (raw coords)", entityUuid)
                        debugDump(State.Session.LastClickPosition[entityUuid].position)
                        lock(movingEntity)
                        Movement.findPathToPosition(entityUuid, State.Session.LastClickPosition[entityUuid].position, function (err, validPosition)
                            if err then
                                return Utils.showNotification(entityUuid, err, 2)
                            end
                            debugPrint("found path (valid)", validPosition[1], validPosition[2], validPosition[3])
                            State.Session.MovementQueue[entityUuid] = {validPosition[1], validPosition[2], validPosition[3]}
                        end)
                    end
                end
            end
            State.Session.RemainingMovement[entityUuid] = Movement.getRemainingMovement(entity)
        end, entity)
        if State.Session.SpellCastMovementListeners[entityUuid] ~= nil then
            Ext.Entity.Unsubscribe(State.Session.SpellCastMovementListeners[entityUuid])
            State.Session.SpellCastMovementListeners[entityUuid] = nil
        end
        -- NB: can specify only the specific cast entity?
        State.Session.SpellCastMovementListeners[entityUuid] = Ext.Entity.OnCreateDeferred("SpellCastMovement", function (cast, _, _)
            if cast.SpellCastTargetsChangedEvent and cast.SpellCastPreviewEndEvent then
                local caster = cast.SpellCastState.Caster
                if caster.Uuid.EntityUuid == entityUuid then
                    debugPrint("spellcastmovement", entityUuid)
                    if isInFTB(caster) and isActionFinalized(caster) and not isLocked(caster) then
                        debugPrint("midactionlock")
                        midActionLock(caster)
                    end
                end
            end
        end)
    end
end

local function checkTruePauseParty()
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
    allEnterFTB = allEnterFTB,
    allExitFTB = allExitFTB,
    cancelQueuedMovement = cancelQueuedMovement,
    enqueueMovement = enqueueMovement,
    startTruePause = startTruePause,
    checkTruePauseParty = checkTruePauseParty,
}
