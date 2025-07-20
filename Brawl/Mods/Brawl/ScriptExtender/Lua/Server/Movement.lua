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
    local movementSpeed = isPlayerOrAlly(entityUuid) and playerMovementDistanceToSpeed(movementDistance) or enemyMovementDistanceToSpeed(movementDistance)
    -- debugPrint("getMovementSpeed", entityUuid, movementDistance, movementSpeed)
    return movementSpeed
end

local function setMovementToMax(entity)
    if entity and entity.Uuid and entity.Uuid.EntityUuid and entity.ActionResources and entity.ActionResources.Resources then
        local resources = entity.ActionResources.Resources
        -- if resources[Constants.ACTION_RESOURCES.Movement] and resources[Constants.ACTION_RESOURCES.Movement][1] and resources[Constants.ACTION_RESOURCES.Movement][1].Amount == 0.0 then
        --     local uuid = entity.Uuid.EntityUuid
        --     if State.Session.TBSMActionResourceListeners[uuid] ~= nil then
        --         Ext.Entity.Unsubscribe(State.Session.TBSMActionResourceListeners[uuid])
        --         State.Session.TBSMActionResourceListeners[uuid] = nil
        --     end
            resources[Constants.ACTION_RESOURCES.Movement][1].Amount = resources[Constants.ACTION_RESOURCES.Movement][1].MaxAmount
            resources[Constants.ACTION_RESOURCES.ActionPoint][1].Amount = 1.0
            entity:Replicate("ActionResources")
            -- AI.queueSpellRequest(uuid, "Shout_Dash", uuid, nil, true)
        -- end
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
    local x, y, z = Osi.GetPosition(targetUuid)
    local validX, validY, validZ = Osi.FindValidPosition(x, y, z, 3.0, uuid, 1)
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
    debugPrint("Got valid path to target", Utils.getDisplayName(uuid), Utils.getDisplayName(targetUuid), validX, validY, validZ, goalFound)
    -- return true
    return goalFound
end

local function findPathToPosition(uuid, position, callback)
    local validX, validY, validZ = Osi.FindValidPosition(position[1], position[2], position[3], 0, uuid, 1)
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
    debugPrint("moveToPosition", uuid, override, position[1], position[2], position[3])
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
    local xMover, yMover, zMover = Osi.GetPosition(moverUuid)
    local xTarget, yTarget, zTarget = Osi.GetPosition(targetUuid)
    local dx = xMover - xTarget
    local dy = yMover - yTarget
    local dz = zMover - zTarget
    local fracDistance = goalDistance / math.sqrt(dx*dx + dy*dy + dz*dz)
    -- return Osi.FindValidPosition(xTarget + dx*fracDistance, yTarget + dy*fracDistance, zTarget + dz*fracDistance, 0, moverUuid, 1)
    return Osi.FindValidPosition(xTarget + dx*fracDistance, yTarget + dy*fracDistance, zTarget + dz*fracDistance, 2.0, moverUuid, 1)
end

local function moveToDistanceFromTarget(moverUuid, targetUuid, goalDistance, callback)
    local x, y, z = calculateEnRouteCoords(moverUuid, targetUuid, goalDistance)
    if x ~= nil and y ~= nil and z ~= nil then
        return moveToPosition(moverUuid, {x, y, z}, not State.Settings.TurnBasedSwarmMode, callback)
    end
    debugPrint(Utils.getDisplayName(moverUuid), "Failed to get en route coordinates", Utils.getDisplayName(targetUuid), x, y, z, goalDistance)
    if callback ~= nil then
        callback()
    end
    return false
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

local function moveIntoPositionForSpell(attackerUuid, targetUuid, spellName, bonusActionOnly, callback)
    local spellRange = Utils.convertSpellRangeToNumber(Utils.getSpellRange(spellName))
    local baseMove = Osi.GetActionResourceValuePersonal(attackerUuid, "Movement", 0)
    local dashed = false
    local override = not State.Settings.TurnBasedSwarmMode
    local dashAvailable = State.Settings.TurnBasedSwarmMode
    -- if unit can’t move or has zero movement, just callback and exit
    if baseMove <= 0 or not Utils.canMove(attackerUuid) then
        if callback then callback() end
        return true
    end
    local function tryMove(allowedDistance)
        -- print("tryMove", allowedDistance)
        local tx, ty, tz = Osi.GetPosition(targetUuid)
        local distToTarget = Osi.GetDistanceTo(attackerUuid, targetUuid)
        local need = distToTarget - spellRange
        -- already in range?
        if need <= 0 then
            if callback then callback() end
            return true
        end
        -- dash if we need more than base move
        if dashAvailable and need > allowedDistance and not bonusActionOnly and not dashed and Osi.HasActiveStatus(attackerUuid, "DASH") == 0 then
            AI.useSpellOnTarget(attackerUuid, attackerUuid, "Shout_Dash_NPC")
            dashed = true
            return tryMove(baseMove*2)
        end
        -- find a valid point just outside the target
        local gx, gy, gz = Osi.FindValidPosition(tx, ty, tz, 3.0, attackerUuid, 1)
        if not gx then
            return false
        end
        -- queue pathfinding
        local goalPos = {gx, gy, gz}
        local dashAllow = baseMove*2
        local path = Ext.Level.BeginPathfinding(Ext.Entity.Get(attackerUuid), goalPos, function(path)
            if not path or not path.GoalFound or #path.Nodes == 0 then
                return
            end
            -- scan for best in‑range node and fallback
            local bestPos, bestDist = nil, -1
            local farPos, farDist = nil, -1
            local nextPos, nextDist = nil, nil
            for _, n in ipairs(path.Nodes) do
                local d = n.Distance
                -- furthest reachable without dash
                if d <= allowedDistance and d > farDist then
                    farPos, farDist = {n.Position[1], n.Position[2], n.Position[3]}, d
                end
                -- first node beyond base move (for interpolation)
                if not nextPos and d > allowedDistance then
                    nextPos, nextDist = {n.Position[1], n.Position[2], n.Position[3]}, d
                end
                -- is this node in spell range (using dash max)?
                if d <= dashAllow then
                    local px, py, pz = n.Position[1], n.Position[2], n.Position[3]
                    local eu = math.sqrt((px - tx)^2 + (py - ty)^2 + (pz - tz)^2)
                    if eu <= spellRange and d > bestDist then
                        bestPos, bestDist = {px, py, pz}, d
                    end
                end
            end
            -- 1) if bestPos is within baseMove, move there
            if bestPos and bestDist <= allowedDistance then
                moveToPosition(attackerUuid, bestPos, override, callback)
                return
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
                    local vx, vy, vz = Osi.FindValidPosition(ix, iy, iz, 0, attackerUuid, 1)
                    if vx then
                        farPos = {vx, vy, vz}
                        valid = true
                        break
                    end
                    frac = origFrac*((10 - attempt)/10)
                end
                if not valid then
                    return
                end
            end
            -- 3) final fallback move
            if farPos then
                moveToPosition(attackerUuid, farPos, override, callback)
            end
        end)
        path.CanUseLadders = true
        return true
    end
    return tryMove(baseMove)
end

-- local function moveIntoPositionForSpell(attackerUuid, targetUuid, spellName, bonusActionOnly, callback)
--     local spellRange = Utils.convertSpellRangeToNumber(Utils.getSpellRange(spellName))
--     local baseMove = Osi.GetActionResourceValuePersonal(attackerUuid, "Movement", 0)
--     local dashed = false
--     local override = not State.Settings.TurnBasedSwarmMode
--     local dashAvailable = not State.Settings.TurnBasedSwarmMode
--     -- if unit can’t move or has zero movement, just callback and exit
--     if baseMove <= 0 or not Utils.canMove(attackerUuid) then
--         if callback then callback() end
--         return true
--     end
--     local function tryMove(allowedDistance)
--         print("tryMove", allowedDistance)
--         local tx, ty, tz = Osi.GetPosition(targetUuid)
--         local distToTarget = Osi.GetDistanceTo(attackerUuid, targetUuid)
--         local need = distToTarget - spellRange
--         -- already in range?
--         if need <= 0 then
--             print("in range already")
--             if callback then callback() end
--             return true
--         end
--         -- dash if we need more than base move
--         if dashAvailable and need > allowedDistance and not bonusActionOnly and not dashed and Osi.HasActiveStatus(attackerUuid, "DASH") == 0 then
--             AI.useSpellOnTarget(attackerUuid, attackerUuid, "Shout_Dash_NPC")
--             dashed = true
--             return tryMove(baseMove*2)
--         end
--         -- build path attacker -> just outside target
--         local gx, gy, gz = Osi.FindValidPosition(tx, ty, tz, 3.0, attackerUuid, 1)
--         if not gx then
--             return false
--         end
--         local path = Ext.Level.BeginPathfindingImmediate(Ext.Entity.Get(attackerUuid), {gx, gy, gz})
--         path.CanUseLadders = true
--         if not Ext.Level.FindPath(path) or #path.Nodes == 0 then
--             return false
--         end
--         -- scan for best in‑range node and fallback
--         local dashAllow = baseMove*2
--         local bestPos, bestDist = nil, -1
--         local farPos, farDist = nil, -1
--         local nextPos, nextDist = nil, nil
--         for _, n in ipairs(path.Nodes) do
--             local d = n.Distance
--             -- furthest reachable without dash
--             if d <= allowedDistance and d > farDist then
--                 farPos, farDist = {n.Position[1], n.Position[2], n.Position[3]}, d
--             end
--             -- first node beyond base move (for interpolation)
--             if not nextPos and d > allowedDistance then
--                 nextPos, nextDist = {n.Position[1], n.Position[2], n.Position[3]}, d
--             end
--             -- is this node actually in spell‑range (using dash max)?
--             if d <= dashAllow then
--                 local px, py, pz = n.Position[1], n.Position[2], n.Position[3]
--                 local eu = math.sqrt((px - tx)^2 + (py - ty)^2 + (pz - tz)^2)
--                 if eu <= spellRange and d > bestDist then
--                     bestPos, bestDist = {px, py, pz}, d
--                 end
--             end
--         end
--         -- 1) if bestPos is within baseMove, move there
--         if bestPos and bestDist <= allowedDistance then
--             moveToPosition(attackerUuid, bestPos, override, callback)
--             return true
--         end
--         -- 2) interpolation fallback if farDist < baseMove
--         if farPos and nextPos and farDist < allowedDistance then
--             local origFrac = (allowedDistance - farDist)/(nextDist - farDist)
--             local frac = origFrac
--             local valid = false
--             for attempt = 1, 10 do
--                 local ix = farPos[1] + (nextPos[1] - farPos[1])*frac
--                 local iy = farPos[2] + (nextPos[2] - farPos[2])*frac
--                 local iz = farPos[3] + (nextPos[3] - farPos[3])*frac
--                 print("interp try", attempt, "frac", frac, "pos", ix, iy, iz)
--                 local vx, vy, vz = Osi.FindValidPosition(ix, iy, iz, 0, attackerUuid, 1)
--                 if vx then
--                     farPos = {vx, vy, vz}
--                     print("interp valid pos", vx, vy, vz)
--                     valid = true
--                     break
--                 end
--                 frac = origFrac*((10 - attempt)/10)
--             end
--             if not valid then
--                 print("interp failed, abort")
--                 return false
--             end
--         end
--         -- 3) final fallback move
--         if farPos then
--             print("farpos, moving", attackerUuid, farPos[1], farPos[2], farPos[3])
--             moveToPosition(attackerUuid, farPos, override, callback)
--             return true
--         end
--         return false
--     end
--     return tryMove(baseMove)
-- end

-- local function moveIntoPositionForSpell(attackerUuid, targetUuid, spellName, bonusActionOnly, callback)
--     local range = getSpellRange(spellName)
--     local rangeNumber = Utils.convertSpellRangeToNumber(range)
--     -- clearOsirisQueue(attackerUuid)
--     local attackerCanMove = Osi.CanMove(attackerUuid) == 1
--     if rangeNumber <= 2 then
--         debugPrint("************moving into position for melee attack", Utils.getDisplayName(attackerUuid), Utils.getDisplayName(targetUuid), spellName)
--         return moveToTargetUuid(attackerUuid, targetUuid, not State.Settings.TurnBasedSwarmMode, callback)
--     else
--         local distanceToTarget = Osi.GetDistanceTo(attackerUuid, targetUuid)
--         local canSeeTarget = Osi.CanSee(attackerUuid, targetUuid) == 1
--         if rangeNumber ~= nil and distanceToTarget ~= nil and distanceToTarget > rangeNumber and attackerCanMove then
--             debugPrint("******moveIntoPositionForSpell distance > range, moving to...", attackerUuid, targetUuid, rangeNumber, callback)
--             return moveToDistanceFromTarget(attackerUuid, targetUuid, rangeNumber, callback)
--         elseif not canSeeTarget and spellName and not string.match(spellName, "^Projectile_MagicMissile") and attackerCanMove then
--             debugPrint("moveIntoPositionForSpell can't see target, moving closer", attackerUuid, targetUuid, rangeNumber, callback)
--             return moveToDistanceFromTarget(attackerUuid, targetUuid, rangeNumber or 2, callback)
--         elseif callback ~= nil then
--             callback()
--             return true
--         end
--     end
-- end

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
    getMovementDistanceMaxAmount = getMovementDistanceMaxAmount,
    getRemainingMovement = getRemainingMovement,
    setMovementToMax = setMovementToMax,
    moveToTargetUuid = moveToTargetUuid,
    moveToPosition = moveToPosition,
    findPathToTargetUuid = findPathToTargetUuid,
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
