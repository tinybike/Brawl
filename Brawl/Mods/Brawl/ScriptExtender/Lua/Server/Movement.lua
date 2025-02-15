-- local Constants = require("Server/Constants.lua")
-- local Utils = require("Server/Utils.lua")
-- local State = require("Server/State.lua")

local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump
local getDisplayName = Utils.getDisplayName
local isPlayerOrAlly = Utils.isPlayerOrAlly
local clearOsirisQueue = Utils.clearOsirisQueue
local getSpellRange = Utils.getSpellRange

local function playerMovementDistanceToSpeed(movementDistance)
    if movementDistance > 10 then
        return "Sprint"
    elseif movementDistance > 6 then
        return "Run"
    elseif movementDistance > 3 then
        return "Walk"
    else
        return "Stroll"
    end
end

local function enemyMovementDistanceToSpeed(movementDistance)
    if movementDistance > State.Session.MovementSpeedThresholds.Sprint then
        return "Sprint"
    elseif movementDistance > State.Session.MovementSpeedThresholds.Run then
        return "Run"
    elseif movementDistance > State.Session.MovementSpeedThresholds.Walk then
        return "Walk"
    else
        return "Stroll"
    end
end

local function getMovementSpeed(entityUuid)
    -- local statuses = Ext.Entity.Get(entityUuid).StatusContainer.Statuses
    local entity = Ext.Entity.Get(entityUuid)
    local movementDistance = entity.ActionResources.Resources[Constants.MOVEMENT_DISTANCE_UUID][1].Amount
    local movementSpeed = isPlayerOrAlly(entityUuid) and playerMovementDistanceToSpeed(movementDistance) or enemyMovementDistanceToSpeed(movementDistance)
    -- debugPrint("getMovementSpeed", entityUuid, movementDistance, movementSpeed)
    return movementSpeed
end

local function findPathToPosition(playerUuid, position, callback)
    local validX, validY, validZ = Osi.FindValidPosition(position[1], position[2], position[3], 0, playerUuid, 1)
    if validX ~= nil and validY ~= nil and validZ ~= nil then
        local validPosition = {validX, validY, validZ}
        State.Session.LastClickPosition[playerUuid] = {position = validPosition}
        if State.Session.MovementQueue[playerUuid] ~= nil or State.Session.AwaitingTarget[playerUuid] then
            Ext.Level.BeginPathfinding(Ext.Entity.Get(playerUuid), validPosition, function (path)
                if not path or not path.GoalFound then
                    return Utils.showNotification(playerUuid, "Can't get there", 2)
                end
                callback(validPosition)
            end)
        end
    end
end

local function moveToTargetUuid(uuid, targetUuid, override)
    if override then
        clearOsirisQueue(uuid)
    end
    Osi.CharacterMoveTo(uuid, targetUuid, getMovementSpeed(uuid), "")
end

local function moveToPosition(uuid, position, override)
    if override then
        clearOsirisQueue(uuid)
    end
    Osi.CharacterMoveToPosition(uuid, position[1], position[2], position[3], getMovementSpeed(uuid), "")
end

local function moveCompanionsToPlayer(playerUuid)
    local players = State.Session.Players
    for uuid, _ in pairs(players) do
        if not State.isPlayerControllingDirectly(uuid) then
            moveToTargetUuid(uuid, playerUuid, true)
        end
    end
end

local function moveCompanionsToPosition(position)
    local players = State.Session.Players
    for uuid, _ in pairs(players) do
        if not State.isPlayerControllingDirectly(uuid) or State.Settings.FullAuto then
            moveToPosition(uuid, position, true)
        end
    end
end

local function calculateEnRouteCoords(moverUuid, targetUuid, goalDistance)
    local xMover, yMover, zMover = Osi.GetPosition(moverUuid)
    local xTarget, yTarget, zTarget = Osi.GetPosition(targetUuid)
    local dx = xMover - xTarget
    local dy = yMover - yTarget
    local dz = zMover - zTarget
    local fracDistance = goalDistance / math.sqrt(dx*dx + dy*dy + dz*dz)
    return Osi.FindValidPosition(xTarget + dx*fracDistance, yTarget + dy*fracDistance, zTarget + dz*fracDistance, 0, moverUuid, 1)
end

local function moveToDistanceFromTarget(moverUuid, targetUuid, goalDistance)
    local x, y, z = calculateEnRouteCoords(moverUuid, targetUuid, goalDistance)
    if x ~= nil and y ~= nil and z ~= nil then
        moveToPosition(moverUuid, {x, y, z}, true)
    end
end

local function holdPosition(entityUuid)
    if not isPlayerOrAlly(entityUuid) then
        -- Example monk looping animations (can these be interruptable?)
        -- (https://bg3.norbyte.dev/search?iid=Resource.6b05dbcc-19ef-475f-62a2-d18c1e640aa7)
        -- animMK = "e85be5a8-6e48-4da4-8486-0d168159df4e"
        -- animMK = "7bb52cd4-0b1c-4926-9165-fa92b75876a3"
        Osi.PlayAnimation(entityUuid, Constants.LOOPING_COMBAT_ANIMATION_ID, "")
        -- Osi.PlayLoopingAnimation(entityUuid, Constants.LOOPING_COMBAT_ANIMATION_ID, Constants.LOOPING_COMBAT_ANIMATION_ID, Constants.LOOPING_COMBAT_ANIMATION_ID, Constants.LOOPING_COMBAT_ANIMATION_ID, Constants.LOOPING_COMBAT_ANIMATION_ID, Constants.LOOPING_COMBAT_ANIMATION_ID, Constants.LOOPING_COMBAT_ANIMATION_ID)
    end
end

local function repositionRelativeToTarget(brawlerUuid, targetUuid)
    local archetype = Osi.GetActiveArchetype(brawlerUuid)
    local distanceToTarget = Osi.GetDistanceTo(brawlerUuid, targetUuid)
    if archetype == "melee" then
        if distanceToTarget > Constants.MELEE_RANGE then
            Osi.FlushOsirisQueue(brawlerUuid)
            moveToTargetUuid(brawlerUuid, targetUuid, false)
        else
            holdPosition(brawlerUuid)
        end
    else
        debugPrint("misc bucket reposition", brawlerUuid, getDisplayName(brawlerUuid))
        if distanceToTarget <= Constants.MELEE_RANGE then
            holdPosition(brawlerUuid)
        elseif distanceToTarget < Constants.RANGED_RANGE_MIN then
            moveToDistanceFromTarget(brawlerUuid, targetUuid, Constants.RANGED_RANGE_SWEETSPOT)
        elseif distanceToTarget < Constants.RANGED_RANGE_MAX then
            holdPosition(brawlerUuid)
        else
            moveToDistanceFromTarget(brawlerUuid, targetUuid, Constants.RANGED_RANGE_SWEETSPOT)
        end
    end
end

local function moveIntoPositionForSpell(attackerUuid, targetUuid, spellName)
    local range = getSpellRange(spellName)
    local rangeNumber
    -- clearOsirisQueue(attackerUuid)
    local attackerCanMove = Osi.CanMove(attackerUuid) == 1
    if range == "MeleeMainWeaponRange" then
        moveToTargetUuid(attackerUuid, targetUuid, true)
    elseif range == "RangedMainWeaponRange" or range == "ThrownObjectRange" then
        rangeNumber = 18
    else
        rangeNumber = tonumber(range)
        local distanceToTarget = Osi.GetDistanceTo(attackerUuid, targetUuid)
        if rangeNumber == nil then
            print("Couldn't parse range, what is this?", range, rangeNumber, distanceToTarget, attackerUuid, targetUuid)
        end
        if rangeNumber ~= nil and distanceToTarget ~= nil and distanceToTarget > rangeNumber and attackerCanMove then
            debugPrint("moveIntoPositionForSpell distance > range, moving to...")
            moveToDistanceFromTarget(attackerUuid, targetUuid, rangeNumber)
        end
    end
    local canSeeTarget = Osi.CanSee(attackerUuid, targetUuid) == 1
    if not canSeeTarget and spellName and not string.match(spellName, "^Projectile_MagicMissile") and attackerCanMove then
        debugPrint("moveIntoPositionForSpell can't see target, moving closer")
        moveToDistanceFromTarget(attackerUuid, targetUuid, rangeNumber or 2)
    end
end

local function setPlayerRunToSprint(entityUuid)
    local entity = Ext.Entity.Get(entityUuid)
    if entity and entity.ServerCharacter then
        if State.Session.Players[entityUuid].movementSpeedRun == nil then
            State.Session.Players[entityUuid].movementSpeedRun = entity.ServerCharacter.Template.MovementSpeedRun
        end
        entity.ServerCharacter.Template.MovementSpeedRun = entity.ServerCharacter.Template.MovementSpeedSprint
    end
end

local function resetPlayersMovementSpeed()
    local players = State.Session.Players
    for playerUuid, player in pairs(players) do
        local entity = Ext.Entity.Get(playerUuid)
        if player.movementSpeedRun ~= nil and entity and entity.ServerCharacter then
            entity.ServerCharacter.Template.MovementSpeedRun = player.movementSpeedRun
            player.movementSpeedRun = nil
        end
    end
end

local function setMovementSpeedThresholds()
    State.Session.MovementSpeedThresholds = Constants.MOVEMENT_SPEED_THRESHOLDS[Utils.getDifficulty()]
end

return {
    getMovementSpeed = getMovementSpeed,
    moveToTargetUuid = moveToTargetUuid,
    moveToPosition = moveToPosition,
    findPathToPosition = findPathToPosition,
    moveCompanionsToPlayer = moveCompanionsToPlayer,
    moveCompanionsToPosition = moveCompanionsToPosition,
    moveToDistanceFromTarget = moveToDistanceFromTarget,
    moveIntoPositionForSpell = moveIntoPositionForSpell,
    holdPosition = holdPosition,
    repositionRelativeToTarget = repositionRelativeToTarget,
    setPlayerRunToSprint = setPlayerRunToSprint,
    resetPlayersMovementSpeed = resetPlayersMovementSpeed,
    setMovementSpeedThresholds = setMovementSpeedThresholds,
}
