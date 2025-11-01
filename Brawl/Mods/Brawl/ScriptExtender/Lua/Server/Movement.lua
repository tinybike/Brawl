local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump
local clearOsirisQueue = Utils.clearOsirisQueue
local noop = Utils.noop

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

local function getMovementDistanceAmount(entity)
    if entity and entity.ActionResources and entity.ActionResources.Resources and entity.ActionResources.Resources[Constants.ACTION_RESOURCES.Movement] and entity.ActionResources.Resources[Constants.ACTION_RESOURCES.Movement][1] then
        return entity.ActionResources.Resources[Constants.ACTION_RESOURCES.Movement][1].Amount
    end
    return 0
end

local function getMovementDistanceMaxAmount(entity)
    if entity and entity.ActionResources and entity.ActionResources.Resources and entity.ActionResources.Resources[Constants.ACTION_RESOURCES.Movement] and entity.ActionResources.Resources[Constants.ACTION_RESOURCES.Movement][1] then
        return entity.ActionResources.Resources[Constants.ACTION_RESOURCES.Movement][1].MaxAmount
    end
    return 0
end

local function getMovementSpeed(entityUuid)
    -- local statuses = Ext.Entity.Get(entityUuid).StatusContainer.Statuses
    local entity = Ext.Entity.Get(entityUuid)
    local movementDistance = getMovementDistanceAmount(entity)
    local movementSpeed = M.Utils.isPlayerOrAlly(entityUuid) and playerMovementDistanceToSpeed(movementDistance) or enemyMovementDistanceToSpeed(movementDistance)
    -- debugPrint("getMovementSpeed", entityUuid, movementDistance, movementSpeed)
    return movementSpeed
end

local function setMovementToMax(entity)
    if entity and entity.Uuid and entity.Uuid.EntityUuid and entity.ActionResources and entity.ActionResources.Resources then
        local resources = entity.ActionResources.Resources
        resources[Constants.ACTION_RESOURCES.Movement][1].Amount = resources[Constants.ACTION_RESOURCES.Movement][1].MaxAmount
        resources[Constants.ACTION_RESOURCES.ActionPoint][1].Amount = 1.0
        resources[Constants.ACTION_RESOURCES.BonusActionPoint][1].Amount = 1.0
        entity:Replicate("ActionResources")
    end
end

local function getRemainingMovement(entity)
    if entity and entity.ActionResources and entity.ActionResources.Resources then
        local resources = entity.ActionResources.Resources
        if resources[Constants.ACTION_RESOURCES.Movement] and resources[Constants.ACTION_RESOURCES.Movement][1] then
            return getMovementDistanceAmount(entity)
        end
    end
end

local function findPathToTargetUuid(uuid, targetUuid)
    local x, y, z = M.Osi.GetPosition(targetUuid)
    local validX, validY, validZ = M.Osi.FindValidPosition(x, y, z, 3.0, uuid, 1)
    if validX == nil or validY == nil or validZ == nil then
        return false
    end
    local validPosition = {validX, validY, validZ}
    local path = Ext.Level.BeginPathfindingImmediate(Ext.Entity.Get(uuid), validPosition)
    path.CanUseLadders = true
    -- path.CanUseCombatPortals = true
    -- path.CanUsePortals = true
    -- path.Climbing = true
    local goalFound = Ext.Level.FindPath(path)
    -- _D(path)
    Ext.Level.ReleasePath(path)
    debugPrint("Got valid path to target", M.Utils.getDisplayName(uuid), M.Utils.getDisplayName(targetUuid), validX, validY, validZ, goalFound)
    -- return true
    return goalFound
end

local function findPathToPosition(uuid, position, callback)
    local validX, validY, validZ = M.Osi.FindValidPosition(position[1], position[2], position[3], 0, uuid, 1)
    if validX == nil or validY == nil or validZ == nil then
        return callback("Can't get there", nil)
    end
    local validPosition = {validX, validY, validZ}
    debugPrint("Got valid position", uuid, validX, validY, validZ)
    local path = Ext.Level.BeginPathfindingImmediate(Ext.Entity.Get(uuid), validPosition)
    local goalFound = Ext.Level.FindPath(path)
    Ext.Level.ReleasePath(path)
    if not goalFound then
        return callback("Can't get there", nil)
    end
    callback(nil, validPosition)
end

local function registerActiveMovement(moverUuid, onMovementCompleted)
    local eventUuid = Utils.createUuid()
    State.Session.ActiveMovements[eventUuid] = {moverUuid = moverUuid, onMovementCompleted = onMovementCompleted}
    return eventUuid
end

local function moveToTargetUuid(uuid, targetUuid, override, callback)
    debugPrint("moveToTargetUuid", uuid, targetUuid, override)
    if override then
        clearOsirisQueue(uuid)
    end
    Osi.CharacterMoveTo(uuid, targetUuid, getMovementSpeed(uuid), registerActiveMovement(uuid, callback))
    return true
end

local function moveToPosition(uuid, position, override, callback)
    -- print("moveToPosition", uuid, override, position[1], position[2], position[3])
    if override then
        clearOsirisQueue(uuid)
    end
    Osi.CharacterMoveToPosition(uuid, position[1], position[2], position[3], getMovementSpeed(uuid), registerActiveMovement(uuid, callback))
    return true
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
    local xMover, yMover, zMover = M.Osi.GetPosition(moverUuid)
    local xTarget, yTarget, zTarget = M.Osi.GetPosition(targetUuid)
    local dx = xMover - xTarget
    local dy = yMover - yTarget
    local dz = zMover - zTarget
    local fracDistance = goalDistance / math.sqrt(dx*dx + dy*dy + dz*dz)
    -- return M.Osi.FindValidPosition(xTarget + dx*fracDistance, yTarget + dy*fracDistance, zTarget + dz*fracDistance, 0, moverUuid, 1)
    return M.Osi.FindValidPosition(xTarget + dx*fracDistance, yTarget + dy*fracDistance, zTarget + dz*fracDistance, 2.0, moverUuid, 1)
end

local function moveToDistanceFromTarget(moverUuid, targetUuid, goalDistance, callback)
    local x, y, z = calculateEnRouteCoords(moverUuid, targetUuid, goalDistance)
    if x ~= nil and y ~= nil and z ~= nil then
        return moveToPosition(moverUuid, {x, y, z}, not State.Settings.TurnBasedSwarmMode, callback)
    end
    debugPrint(M.Utils.getDisplayName(moverUuid), "Failed to get en route coordinates", M.Utils.getDisplayName(targetUuid), x, y, z, goalDistance)
    if callback ~= nil then
        callback()
    end
    return false
end

local function holdPosition(entityUuid)
    if not M.Utils.isPlayerOrAlly(entityUuid) then
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
    local distanceToTarget = M.Osi.GetDistanceTo(brawlerUuid, targetUuid)
    if archetype == "melee" then
        if distanceToTarget > Constants.MELEE_RANGE then
            Osi.FlushOsirisQueue(brawlerUuid)
            moveToTargetUuid(brawlerUuid, targetUuid, false)
        else
            holdPosition(brawlerUuid)
        end
    else
        debugPrint("misc bucket reposition", brawlerUuid, M.Utils.getDisplayName(brawlerUuid))
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

-- Jump has a base range of 4.5 m / 15 ft and is increased by 1 m / 3 ft for 2 points of Strength above 10
local function calculateJumpDistance(uuid)
    local entity = Ext.Entity.Get(uuid)
    local strength = M.Utils.getAbility(entity) or 10
    local jumpDistance = 4.5 + math.max(0, math.floor((strength - 10)/2))
    if M.Utils.hasPassive(entity, "UnarmoredMovement_DifficultTerrain") then
        jumpDistance = jumpDistance + 6
    end
    if M.Utils.hasPassive(entity, "RemarkableAthlete_Jump") then
        jumpDistance = jumpDistance + 3
    end
    if M.Utils.hasStatus(entity, "LONG_JUMP") then
        jumpDistance = jumpDistance*3
    end
    if M.Utils.hasPassive(entity, "Athlete_StandUp") then
        jumpDistance = jumpDistance*1.5
    end
    if M.Utils.hasStatus(entity, "RAGE_TOTEM_TIGER") then
        jumpDistance = jumpDistance*1.5
    end
    if M.Utils.hasStatus(entity, "ENCUMBERED_LIGHT") then
        jumpDistance = jumpDistance*0.5
    end
    return jumpDistance
end

local function selectBonusActionDash(uuid)
    for _, bonusActionDash in ipairs(Constants.BONUS_ACTION_DASH) do
        if Resources.hasEnoughToCastSpell(uuid, bonusActionDash) then
            return bonusActionDash
        end
    end
end

local function selectDash(uuid, bonusActionOnly)
    local bonusActionDash = selectBonusActionDash(uuid)
    if bonusActionDash then
        return bonusActionDash
    end
    if not bonusActionOnly then
        return "Shout_Dash"
    end
end

local function selectTeleport(uuid)
    for _, teleport in ipairs(Constants.TELEPORTS) do
        if Resources.hasEnoughToCastSpell(uuid, teleport) then
            return teleport
        end
    end
end

local function getRemainingMovementByUuid(uuid)
    return getRemainingMovement(Ext.Entity.Get(uuid))
end

local function moveIntoPositionForSpell(uuid, targetUuid, spellName, bonusActionOnly, onSuccess, onFailed)
    onSuccess = onSuccess or noop
    onFailed = onFailed or noop
    debugPrint(M.Utils.getDisplayName(uuid), "moveIntoPositionForSpell", M.Utils.getDisplayName(targetUuid), spellName, bonusActionOnly)
    local swarmTurnActiveInitial = State.Session.SwarmTurnActive
    local spellRange = M.Utils.convertSpellRangeToNumber(M.Utils.getSpellRange(spellName))
    -- if unit can’t move at all (sentinel foe etc)
    if not M.Utils.canMove(uuid) then
        if M.Osi.GetDistanceTo(uuid, targetUuid) - spellRange > 0 then
            return onFailed("can't move")
        end
    end
    local baseMove = getRemainingMovementByUuid(uuid)
    local numActions = Resources.getActionPointsRemaining(uuid)
    local numBonusActions = Resources.getBonusActionPointsRemaining(uuid)
    local override = not State.Settings.TurnBasedSwarmMode
    debugPrint(M.Utils.getDisplayName(uuid), "starting movement and points", baseMove, numActions, numBonusActions)
    local function tryMove(allowedDistance, isDashAvailable, isBonusDashOnly)
        debugPrint(M.Utils.getDisplayName(uuid), "tryMove", allowedDistance)
        local tx, ty, tz = M.Osi.GetPosition(targetUuid)
        local distToTarget = M.Osi.GetDistanceTo(uuid, targetUuid)
        local need = distToTarget - spellRange
        -- already in range?
        if need <= 0 then
            return onSuccess()
        end
        -- dash if we need more than base move
        if isDashAvailable and need > allowedDistance then
            debugPrint(M.Utils.getDisplayName(uuid), "need to dash")
            local dashSpellName
            if isBonusDashOnly then
                dashSpellName = selectBonusActionDash(uuid)
            else
                dashSpellName = selectDash(uuid, bonusActionOnly)
            end
            if not dashSpellName then
                debugPrint(M.Utils.getDisplayName(uuid), "no dash..")
                return tryMove(getRemainingMovementByUuid(uuid), false, false)
            end
            debugPrint(M.Utils.getDisplayName(uuid), "dashing")
            return Actions.useSpellOnTarget(uuid, uuid, dashSpellName, true, function (request)
                debugPrint(M.Utils.getDisplayName(uuid), "dash request submitted", dashSpellName)
                local swarmActors
                if swarmTurnActiveInitial then
                    swarmActors = State.Session.SwarmActors
                end
                Swarm.startActionSequenceFailsafeTimer(M.Roster.getBrawlerByUuid(uuid), request, swarmTurnActiveInitial, swarmActors, onFailed)
            end, function (spellName)
                debugPrint(M.Utils.getDisplayName(uuid), "dash ok", spellName)
                Ext.Timer.WaitFor(Constants.TIME_BETWEEN_ACTIONS, function ()
                    -- if this is an NPC acting during Swarm Turn, make sure the swarm turn is still active now
                    if State.Session.TurnBasedSwarmMode and swarmTurnActiveInitial and not State.Session.SwarmTurnActive then
                        return onFailed("swarm turn expired (dash)")
                    end
                    tryMove(getRemainingMovementByUuid(uuid), Resources.getBonusActionPointsRemaining(uuid) > 0, true)
                end)
            end, onFailed)
        end
        -- find a valid point just outside the target
        local gx, gy, gz = M.Osi.FindValidPosition(tx, ty, tz, 3.0, uuid, 1)
        if not gx then
            return onFailed("no valid points")
        end
        if need > 0 and allowedDistance == 0 then
            -- TODO maybe teleport?
            return onFailed("out of movement")
        end
        -- queue pathfinding
        local goalPos = {gx, gy, gz}
        local path = Ext.Level.BeginPathfinding(Ext.Entity.Get(uuid), goalPos, function (path)
            if not path or not path.GoalFound or #path.Nodes == 0 then
                -- if no path, try teleporting if we have one available
                local teleportSpellName = selectTeleport(uuid)
                if not teleportSpellName then
                    return onFailed("path not found")
                end
                return Actions.useSpellOnTarget(uuid, targetUuid, teleportSpellName, false, function (request)
                    debugPrint(M.Utils.getDisplayName(uuid), "teleport request submitted", teleportSpellName)
                    -- NB: need to do this for RT also for RIC?
                    if State.Session.TurnBasedSwarmMode then
                        local swarmActors
                        if swarmTurnActiveInitial then
                            swarmActors = State.Session.SwarmActors
                        end
                        Swarm.startActionSequenceFailsafeTimer(M.Roster.getBrawlerByUuid(uuid), request, swarmTurnActiveInitial, swarmActors, onFailed)
                    end
                end, function (spellName)
                    debugPrint(M.Utils.getDisplayName(uuid), "teleport ok", spellName)
                    Ext.Timer.WaitFor(Constants.TIME_BETWEEN_ACTIONS, function ()
                        if State.Session.TurnBasedSwarmMode and swarmTurnActiveInitial and not State.Session.SwarmTurnActive then
                            return onFailed("swarm turn expired (teleport)")
                        end
                        tryMove(getRemainingMovementByUuid(uuid), isDashAvailable, isBonusDashOnly)
                    end)
                end, onFailed)
            end
            -- scan for best in‑range node and fallback
            local bestPos, bestDist = nil, -1
            local farPos, farDist = nil, -1
            local nextPos, nextDist = nil, nil
            for _, n in ipairs(path.Nodes) do
                local d = n.Distance
                -- furthest reachable
                if d <= allowedDistance and d > farDist then
                    farPos, farDist = {n.Position[1], n.Position[2], n.Position[3]}, d
                    debugPrint(M.Utils.getDisplayName(uuid), "furthest reachable", n.Position[1], n.Position[2], n.Position[3], d)
                end
                -- first node beyond base move (for interpolation)
                if not nextPos and d > allowedDistance then
                    nextPos, nextDist = {n.Position[1], n.Position[2], n.Position[3]}, d
                    debugPrint(M.Utils.getDisplayName(uuid), "next reachable node", n.Position[1], n.Position[2], n.Position[3], d)
                end
                -- in spell range?
                local px, py, pz = n.Position[1], n.Position[2], n.Position[3]
                local eu = math.sqrt((px - tx)^2 + (py - ty)^2 + (pz - tz)^2)
                if eu <= spellRange and d > bestDist then
                    bestPos, bestDist = {px, py, pz}, d
                    debugPrint(M.Utils.getDisplayName(uuid), "in spell range", px, py, pz, d)
                end
            end
            -- 1) if bestPos is within baseMove, move there
            if bestPos and bestDist <= allowedDistance then
                debugPrint(M.Utils.getDisplayName(uuid), "best within range, moving to")
                return moveToPosition(uuid, bestPos, override, onSuccess)
            end
            -- 2) interpolation fallback if farDist < baseMove
            if farPos and nextPos and farDist < allowedDistance then
                local origFrac = (allowedDistance - farDist)/(nextDist - farDist)
                local frac = origFrac
                local valid = false
                for attempt = 1, 10 do
                    local ix = farPos[1] + (nextPos[1] - farPos[1])*frac
                    local iy = farPos[2] + (nextPos[2] - farPos[2])*frac
                    local iz = farPos[3] + (nextPos[3] - farPos[3])*frac
                    local vx, vy, vz = M.Osi.FindValidPosition(ix, iy, iz, 0, uuid, 1)
                    if vx then
                        farPos = {vx, vy, vz}
                        valid = true
                        break
                    end
                    frac = origFrac*((10 - attempt)/10)
                end
                debugPrint(M.Utils.getDisplayName(uuid), "interpolation result")
                debugDump(farPos)
                if not valid then
                    return onFailed("interpolation")
                end
            end
            if not farPos then
                return onFailed("nodes")
            end
            -- 3) final fallback move
            debugPrint("final fallback move")
            moveToPosition(uuid, farPos, override, onSuccess)
        end)
        if path then
            path.CanUseLadders = true
        end
    end
    tryMove(baseMove, State.Settings.TurnBasedSwarmMode, bonusActionOnly)
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
    State.Session.MovementSpeedThresholds = Constants.MOVEMENT_SPEED_THRESHOLDS[M.Utils.getDifficulty()]
end

return {
    playerMovementDistanceToSpeed = playerMovementDistanceToSpeed,
    enemyMovementDistanceToSpeed = enemyMovementDistanceToSpeed,
    getMovementSpeed = getMovementSpeed,
    getMovementDistanceAmount = getMovementDistanceAmount,
    getMovementDistanceMaxAmount = getMovementDistanceMaxAmount,
    getRemainingMovement = getRemainingMovement,
    setMovementToMax = setMovementToMax,
    moveToTargetUuid = moveToTargetUuid,
    moveToPosition = moveToPosition,
    findPathToTargetUuid = findPathToTargetUuid,
    findPathToPosition = findPathToPosition,
    moveCompanionsToPlayer = moveCompanionsToPlayer,
    moveCompanionsToPosition = moveCompanionsToPosition,
    calculateEnRouteCoords = calculateEnRouteCoords,
    moveToDistanceFromTarget = moveToDistanceFromTarget,
    calculateJumpDistance = calculateJumpDistance,
    moveIntoPositionForSpell = moveIntoPositionForSpell,
    holdPosition = holdPosition,
    repositionRelativeToTarget = repositionRelativeToTarget,
    setPlayerRunToSprint = setPlayerRunToSprint,
    resetPlayersMovementSpeed = resetPlayersMovementSpeed,
    setMovementSpeedThresholds = setMovementSpeedThresholds,
    selectDash = selectDash,
    selectBonusActionDash = selectBonusActionDash,
    selectTeleport = selectTeleport,
}
