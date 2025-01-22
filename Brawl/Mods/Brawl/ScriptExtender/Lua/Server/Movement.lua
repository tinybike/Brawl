local function getMovementSpeed(entityUuid)
    -- local statuses = Ext.Entity.Get(entityUuid).StatusContainer.Statuses
    local entity = Ext.Entity.Get(entityUuid)
    local movementDistance = entity.ActionResources.Resources[MOVEMENT_DISTANCE_UUID][1].Amount
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
                    return showNotification(playerUuid, "Can't get there", 2)
                end
                callback(validPosition)
            end)
        end
    end
end
local function moveToTargetUuid(uuid, targetUuid, clearQueue)
    if clearQueue then
        Osi.PurgeOsirisQueue(uuid, 1)
        Osi.FlushOsirisQueue(uuid)
    end
    Osi.CharacterMoveTo(uuid, targetUuid, getMovementSpeed(uuid), "")
end
local function moveToPosition(uuid, position, clearQueue)
    if clearQueue then
        Osi.PurgeOsirisQueue(uuid, 1)
        Osi.FlushOsirisQueue(uuid)
    end
    Osi.CharacterMoveToPosition(uuid, position[1], position[2], position[3], getMovementSpeed(uuid), "")
end
local function moveCompanionsToPlayer(playerUuid)
    for uuid, _ in pairs(State.Session.Players) do
        if not State.isPlayerControllingDirectly(uuid) then
            moveToTargetUuid(uuid, playerUuid, true)
        end
    end
end
local function moveCompanionsToPosition(position)
    for uuid, _ in pairs(State.Session.Players) do
        if not State.isPlayerControllingDirectly(uuid) or State.Settings.FullAuto then
            moveToPosition(uuid, position, true)
        end
    end
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
        Osi.PlayAnimation(entityUuid, LOOPING_COMBAT_ANIMATION_ID, "")
        -- Osi.PlayLoopingAnimation(entityUuid, LOOPING_COMBAT_ANIMATION_ID, LOOPING_COMBAT_ANIMATION_ID, LOOPING_COMBAT_ANIMATION_ID, LOOPING_COMBAT_ANIMATION_ID, LOOPING_COMBAT_ANIMATION_ID, LOOPING_COMBAT_ANIMATION_ID, LOOPING_COMBAT_ANIMATION_ID)
    end
end

Movement = {
    getMovementSpeed = getMovementSpeed,
    moveToTargetUuid = moveToTargetUuid,
    moveToPosition = moveToPosition,
    findPathToPosition = findPathToPosition,
    moveCompanionsToPlayer = moveCompanionsToPlayer,
    moveCompanionsToPosition = moveCompanionsToPosition,
    moveToDistanceFromTarget = moveToDistanceFromTarget,
    holdPosition = holdPosition,
}
