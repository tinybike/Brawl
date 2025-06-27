-- local Utils = require("Server/Utils.lua")
-- local State = require("Server/State.lua")
-- local Movement = require("Server/Movement.lua")

local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump
local getDisplayName = Utils.getDisplayName
local isPlayerOrAlly = Utils.isPlayerOrAlly
local isAliveAndCanFight = Utils.isAliveAndCanFight
local isOnSameLevel = Utils.isOnSameLevel
local isVisible = Utils.isVisible

local function isLocked(entity)
    debugPrint(entity.TurnBased.CanActInCombat, entity.TurnBased.HadTurnInCombat, entity.TurnBased.IsActiveCombatTurn)
    return entity.TurnBased.CanActInCombat and entity.TurnBased.HadTurnInCombat and not entity.TurnBased.IsActiveCombatTurn
end

local function unlock(entity)
    debugPrint("unlock", entity.Uuid.EntityUuid, isLocked(entity))
    -- debugDump(entity.TurnBased)
    entity.TurnBased.IsActiveCombatTurn = true
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

local function lock(entity)
    local uuid = entity.Uuid.EntityUuid
    debugPrint("locking", uuid)
    Roster.disableLockedOnTarget(uuid)
    entity.TurnBased.IsActiveCombatTurn = false
    State.Session.FTBLockedIn[uuid] = true
end

local function isPlayerFrozen(uuid)
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    if modVars.FrozenPlayerResources == nil then
        return false
    end
    if not modVars.FrozenPlayerResources[uuid] then
        return false
    end
    return true
end

local function freezePlayer(uuid)
    local entity = Ext.Entity.Get(uuid)
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    if modVars.FrozenPlayerResources == nil then
        modVars.FrozenPlayerResources = {}
    end
    local frozenPlayerResources = modVars.FrozenPlayerResources
    if not frozenPlayerResources[uuid] then
        frozenPlayerResources[uuid] = {}
        if entity.ActionResources and entity.ActionResources.Resources then
            local actionPoints = entity.ActionResources.Resources[Constants.ACTION_RESOURCES.ActionPoint]
            if actionPoints and actionPoints[1] and actionPoints[1].Amount ~= nil then
                frozenPlayerResources[uuid].ActionPoint = actionPoints[1].Amount
            end
            local bonusActionPoints = entity.ActionResources.Resources[Constants.ACTION_RESOURCES.BonusActionPoint]
            if bonusActionPoints and bonusActionPoints[1] and bonusActionPoints[1].Amount ~= nil then
                frozenPlayerResources[uuid].BonusActionPoint = bonusActionPoints[1].Amount
            end
        end
        if entity.CanMove and entity.CanMove.Flags ~= nil then
            frozenPlayerResources[uuid].CanMoveFlags = {}
            for _, flag in ipairs(entity.CanMove.Flags) do
               table.insert(frozenPlayerResources[uuid].CanMoveFlags, flag)
            end
        end
        modVars.FrozenPlayerResources[uuid] = frozenPlayerResources[uuid]
    end
    debugPrint("FREEZE: FROZEN PLAYER RESOURCES")
    debugDump(frozenPlayerResources)
    entity.ActionResources.Resources[Constants.ACTION_RESOURCES.ActionPoint][1].Amount = 0
    entity.ActionResources.Resources[Constants.ACTION_RESOURCES.BonusActionPoint][1].Amount = 0
    entity.CanMove.Flags = {}
    entity:Replicate("ActionResources")
    entity:Replicate("CanMove")
end

local function unfreezePlayer(uuid)
    local entity = Ext.Entity.Get(uuid)
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    if modVars.FrozenPlayerResources == nil then
        modVars.FrozenPlayerResources = {}
    end
    local frozenPlayerResources = modVars.FrozenPlayerResources
    debugPrint("UNFREEZE: FROZEN PLAYER RESOURCES")
    debugDump(frozenPlayerResources)
    if frozenPlayerResources[uuid] then
        if entity.ActionResources and entity.ActionResources.Resources then
            local actionPoints = entity.ActionResources.Resources[Constants.ACTION_RESOURCES.ActionPoint]
            if actionPoints and actionPoints[1] and frozenPlayerResources[uuid].ActionPoint ~= nil then
                entity.ActionResources.Resources[Constants.ACTION_RESOURCES.ActionPoint][1].Amount = frozenPlayerResources[uuid].ActionPoint
            end
            local bonusActionPoints = entity.ActionResources.Resources[Constants.ACTION_RESOURCES.BonusActionPoint]
            if bonusActionPoints and bonusActionPoints[1] and frozenPlayerResources[uuid].BonusActionPoint ~= nil then
                entity.ActionResources.Resources[Constants.ACTION_RESOURCES.BonusActionPoint][1].Amount = frozenPlayerResources[uuid].BonusActionPoint
            end
        end
        if entity.CanMove and frozenPlayerResources[uuid].CanMoveFlags ~= nil then
            entity.CanMove.Flags = frozenPlayerResources[uuid].CanMoveFlags
        end
        frozenPlayerResources[uuid] = nil
    end
    entity:Replicate("ActionResources")
    entity:Replicate("CanMove")
    modVars.FrozenPlayerResources = frozenPlayerResources
end

local function freezeAllPlayers(shouldFreezePlayers)
    debugPrint("freezeAllPlayers")
    debugDump(shouldFreezePlayers)
    local players = State.Session.Players
    if players then
        for playerUuid, _ in pairs(players) do
            Osi.SetCanJoinCombat(playerUuid, 0)
            Ext.Timer.WaitFor(200, function ()
                if shouldFreezePlayers[playerUuid] then
                    debugPrint(Utils.getDisplayName(playerUuid), "freezing player", playerUuid)
                    freezePlayer(playerUuid)
                end
            end)
        end
    end
end

local function unfreezeAllPlayers()
    local players = State.Session.Players
    if players then
        for playerUuid, _ in pairs(players) do
            Osi.SetCanJoinCombat(playerUuid, 1)
            Ext.Timer.WaitFor(200, function ()
                unfreezePlayer(playerUuid)
            end)
        end
    end
end

local function stopTruePause(entityUuid)
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

local function allEnterFTB()
    debugPrint("allEnterFTB")
    if Utils.isToT() then
        stopToTTimers()
    end
    for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
        local uuid = Osi.GetUUID(player[1])
        Osi.ForceTurnBasedMode(uuid, 1)
    end
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    local brawlersInLevel = State.Session.Brawlers[level]
    if brawlersInLevel then
        for brawlerUuid, _ in pairs(brawlersInLevel) do
            if Osi.IsPlayer(brawlerUuid) == 0 then
                Osi.ForceTurnBasedMode(brawlerUuid, 1)
                Pause.startTruePause(brawlerUuid)
            end
        end
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
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    local brawlersInLevel = State.Session.Brawlers[level]
    if brawlersInLevel then
        for brawlerUuid, _ in pairs(brawlersInLevel) do
            if Osi.IsPlayer(brawlerUuid) == 0 then
                unlock(Ext.Entity.Get(brawlerUuid))
                Osi.ForceTurnBasedMode(brawlerUuid, 0)
                stopTruePause(brawlerUuid)
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
    debugPrint("midActionLock", entity.Uuid.EntityUuid)
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
    -- debugDump(State.Session.FTBLockedIn)
    for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
        local uuid = Osi.GetUUID(player[1])
        -- debugPrint("checking ftb for", uuid, Osi.IsInForceTurnBasedMode(uuid))
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
    if isAliveAndCanFight(entityUuid) then
        debugPrint("startTruePause", entityUuid, getDisplayName(entityUuid))
        -- if Osi.IsPartyMember(entityUuid, 1) == 1 then
        Utils.clearOsirisQueue(entityUuid)
        local entity = Ext.Entity.Get(entityUuid)
        if State.Session.TurnBasedListeners[entityUuid] ~= nil then
            Ext.Entity.Unsubscribe(State.Session.TurnBasedListeners[entityUuid])
            State.Session.TurnBasedListeners[entityUuid] = nil
        end
        State.Session.TurnBasedListeners[entityUuid] = Ext.Entity.Subscribe("TurnBased", function (caster, _, _)
            -- requested end turn isn't the only thing that can change here
            -- debugPrint("TurnBased", entityUuid, State.Session.FTBLockedIn[entityUuid], caster.TurnBased.RequestedEndTurn)
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
                        debugPrint("******************MOVEMENT LOCK enqueue movement (raw coords)", entityUuid)
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
                    debugPrint("***************SpellCastMovement", entityUuid)
                    if isInFTB(caster) and isActionFinalized(caster) and not isLocked(caster) then
                        midActionLock(caster)
                    end
                end
            end
        end)
        -- end
        -- Enqueue actions/movements for non-party NPCs
        if Osi.IsPartyMember(entityUuid, 1) == 0 and not isLocked(Ext.Entity.Get(entityUuid)) then
            local brawler = State.getBrawlerByUuid(entityUuid)
            if brawler and brawler.uuid then
                -- PulseAction stuff.....
                debugPrint("*****PULSEACTION STUFF WHILE PAUSED*****", brawler.uuid, brawler.displayName)
                local level = Osi.GetRegion(entityUuid)
                -- Doesn't currently have an attack target, so let's find one
                if brawler.targetUuid == nil then
                    debugPrint("Find target (no current target)", entityUuid, brawler.displayName)
                    return AI.findTarget(brawler)
                end
                -- We have a target and the target is alive
                local brawlersInLevel = State.Session.Brawlers[level]
                if brawlersInLevel and isOnSameLevel(entityUuid, brawler.targetUuid) and brawlersInLevel[brawler.targetUuid] and isAliveAndCanFight(brawler.targetUuid) and isVisible(brawler.targetUuid) then
                    if brawler.lockedOnTarget then
                        debugPrint("Locked-on target, attacking", brawler.displayName, entityUuid, "->", getDisplayName(brawler.targetUuid))
                        return AI.actOnHostileTarget(brawler, brawlersInLevel[brawler.targetUuid])
                    end
                    if Osi.GetDistanceTo(entityUuid, brawler.targetUuid) <= 12 then
                        debugPrint("Remaining on target, attacking", brawler.displayName, entityUuid, "->", getDisplayName(brawler.targetUuid))
                        return AI.actOnHostileTarget(brawler, brawlersInLevel[brawler.targetUuid])
                    end
                end
                -- Has an attack target but it's already dead or unable to fight, so find a new one
                debugPrint("Find target (current target invalid)", entityUuid, brawler.displayName)
                brawler.targetUuid = nil
                return AI.findTarget(brawler)
            end
        end
    end
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
    isLocked = isLocked,
    allEnterFTB = allEnterFTB,
    allExitFTB = allExitFTB,
    cancelQueuedMovement = cancelQueuedMovement,
    enqueueMovement = enqueueMovement,
    startTruePause = startTruePause,
    checkTruePauseParty = checkTruePauseParty,
    midActionLock = midActionLock,
    lock = lock,
    unlock = unlock,
    freezePlayer = freezePlayer,
    unfreezePlayer = unfreezePlayer,
    freezeAllPlayers = freezeAllPlayers,
    unfreezeAllPlayers = unfreezeAllPlayers,
    isPlayerFrozen = isPlayerFrozen,
}
