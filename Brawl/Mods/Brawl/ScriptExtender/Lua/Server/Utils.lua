function debugPrint(...)
    if DEBUG_LOGGING then
        print(...)
    end
end

function debugDump(...)
    if DEBUG_LOGGING then
        _D(...)
    end
end

function dumpAllEntityKeys()
    local uuid = GetHostCharacter()
    local entity = Ext.Entity.Get(uuid)
    for k, _ in pairs(entity:GetAllComponents()) do
        print(k)
    end
end

function dumpEntityToFile(entityUuid)
    Ext.IO.SaveFile(entityUuid .. ".json", Ext.DumpExport(Ext.Entity.Get(entityUuid):GetAllComponents()))
end

function checkNearby()
    for _, nearby in ipairs(getNearby(Osi.GetHostCharacter(), 50)) do
        if nearby.Entity.IsCharacter then
            local uuid = nearby.Guid
            print(getDisplayName(uuid), uuid, Osi.CanJoinCombat(uuid))
        end
    end
end

function getDisplayName(entityUuid)
    return Osi.ResolveTranslatedString(Osi.GetDisplayName(entityUuid))
end

function isDowned(entityUuid)
    return Osi.IsDead(entityUuid) == 0 and Osi.GetHitpoints(entityUuid) == 0
end

function isAliveAndCanFight(entityUuid)
    if IS_TRAINING_DUMMY[entityUuid] == true then
        return true
    end
    local isDead = Osi.IsDead(entityUuid)
    if isDead == nil then
        return false
    end
    if isDead == 1 then
        return false
    end
    local hitpoints = Osi.GetHitpoints(entityUuid)
    if hitpoints == nil then
        return false
    end
    if hitpoints == 0 then
        return false
    end
    local canFight = Osi.CanFight(entityUuid)
    if canFight == nil then
        return false
    end
    if canFight == 0 then
        return false
    end
    return true
end

function isPlayerOrAlly(entityUuid)
    return Osi.IsPlayer(entityUuid) == 1 or Osi.IsAlly(Osi.GetHostCharacter(), entityUuid) == 1
end

function isPugnacious(potentialEnemyUuid, uuid)
    if uuid == nil then
        uuid = Osi.GetHostCharacter()
        if uuid == nil then
            return nil
        end
    end
    -- if MurderhoboMode and not isAllyOrPlayer(potentialEnemyUuid) then
    --     Osi.SetRelationTemporaryHostile(uuid, potentialEnemyUuid)
    -- end
    return Osi.IsEnemy(uuid, potentialEnemyUuid) == 1 or IsAttackingOrBeingAttackedByPlayer[potentialEnemyUuid] ~= nil
end

function getPlayerByUserId(userId)
    if Players then
        for uuid, player in pairs(Players) do
            if player.userId == userId and player.isControllingDirectly then
                return player
            end
        end
    end
    return nil
end

function getBrawlerByUuid(uuid)
    local level = Osi.GetRegion(uuid)
    if level and Brawlers[level] then
        return Brawlers[level][uuid]
    end
    return nil
end

-- from https://github.com/Norbyte/bg3se/blob/main/Docs/API.md#helper-functions
function peerToUserId(peerId)
    return (peerId & 0xffff0000) | 0x0001
end

-- thank u focus
---@return "EASY"|"MEDIUM"|"HARD"|"HONOUR"
function getDifficulty()
    local difficulty = Osi.GetRulesetModifierString("cac2d8bd-c197-4a84-9df1-f86f54ad4521")
    if difficulty == "HARD" and Osi.GetRulesetModifierBool("338450d9-d77d-4950-9e1e-0e7f12210bb3") == 1 then
        return "HONOUR"
    end
    return difficulty
end

function split(inputstr, sep)
    if sep == nil then
        sep = "%s" -- whitespace
    else
        sep = string.gsub(sep, "([^%w])", "%%%1")
    end
    local t = {}
    for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
        table.insert(t, str)
    end
    return t
end

function enemyMovementDistanceToSpeed(movementDistance)
    if movementDistance > MovementSpeedThresholds.Sprint then
        return "Sprint"
    elseif movementDistance > MovementSpeedThresholds.Run then
        return "Run"
    elseif movementDistance > MovementSpeedThresholds.Walk then
        return "Walk"
    else
        return "Stroll"
    end
end

function playerMovementDistanceToSpeed(movementDistance)
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

function isZoneSpell(spellName)
    return split(spellName, "_")[1] == "Zone"
end

function isProjectileSpell(spellName)
    return split(spellName, "_")[1] == "Projectile"
end

function isVisible(entityUuid)
    return Osi.IsInvisible(entityUuid) == 0 and Osi.HasActiveStatus(entityUuid, "SNEAKING") == 0
end

function isHealerArchetype(archetype)
    return archetype:find("healer") ~= nil
end

function isPlayerControllingDirectly(entityUuid)
    return Players[entityUuid] ~= nil and Players[entityUuid].isControllingDirectly == true
end

function isBrawlingWithValidTarget(brawler)
    return brawler.isInBrawl and brawler.targetUuid ~= nil and isAliveAndCanFight(brawler.targetUuid)
end

---@class EntityDistance
---@field Entity EntityHandle
---@field Guid string GUID
---@field Distance number
---@param source string GUID
---@param radius number|nil
---@param ignoreHeight boolean|nil
---@param withComponent ExtComponentType|nil
---@return EntityDistance[]
-- thank u hippo (from hippo0o/bg3-mods & AtilioA/BG3-volition-cabinet)
function getNearby(source, radius, ignoreHeight, withComponent)
    radius = radius or 1
    withComponent = withComponent or "Uuid"

    ---@param entity string|EntityHandle GUID
    ---@return number[]|nil {x, y, z}
    local function entityPos(entity)
        entity = type(entity) == "string" and Ext.Entity.Get(entity) or entity
        local ok, pos = pcall(function ()
            return entity.Transform.Transform.Translate
        end)
        if ok then
            return {pos[1], pos[2], pos[3]}
        end
        return nil
    end

    local sourcePos = entityPos(source)
    if not sourcePos then
        return {}
    end

    ---@param target number[] {x, y, z}
    ---@return number
    local function calcDisance(target)
        return math.sqrt(
            (sourcePos[1] - target[1]) ^ 2
                + (not ignoreHeight and (sourcePos[2] - target[2]) ^ 2 or 0)
                + (sourcePos[3] - target[3]) ^ 2
        )
    end

    local nearby = {}
    for _, entity in ipairs(Ext.Entity.GetAllEntitiesWithComponent(withComponent)) do
        local pos = entityPos(entity)
        if pos then
            local distance = calcDisance(pos)
            if distance <= radius then
                table.insert(nearby, {
                    Entity = entity,
                    Guid = entity.Uuid and entity.Uuid.EntityUuid,
                    Distance = distance,
                })
            end
        end
    end
    table.sort(nearby, function (a, b) return a.Distance < b.Distance end)
    return nearby
end

function modStatusMessage(message)
    Osi.QuestMessageHide("ModStatusMessage")
    if ModStatusMessageTimer ~= nil then
        Ext.Timer.Cancel(ModStatusMessageTimer)
        ModStatusMessageTimer = nil
    end
    Ext.Timer.WaitFor(50, function ()
        Osi.QuestMessageShow("ModStatusMessage", message)
        ModStatusMessageTimer = Ext.Timer.WaitFor(MOD_STATUS_MESSAGE_DURATION, function ()
            Osi.QuestMessageHide("ModStatusMessage")
        end)
    end)
end

function getMovementSpeed(entityUuid)
    -- local statuses = Ext.Entity.Get(entityUuid).StatusContainer.Statuses
    local entity = Ext.Entity.Get(entityUuid)
    local movementDistance = entity.ActionResources.Resources[MOVEMENT_DISTANCE_UUID][1].Amount
    local movementSpeed = isPlayerOrAlly(entityUuid) and playerMovementDistanceToSpeed(movementDistance) or enemyMovementDistanceToSpeed(movementDistance)
    -- debugPrint("getMovementSpeed", entityUuid, movementDistance, movementSpeed)
    return movementSpeed
end

function isOnSameLevel(uuid1, uuid2)
    local level1 = Osi.GetRegion(uuid1)
    local level2 = Osi.GetRegion(uuid2)
    return level1 ~= nil and level2 ~= nil and level1 == level2
end

function getSpellNameBySlot(uuid, slot)
    local entity = Ext.Entity.Get(uuid)
    -- NB: is this always index 6?
    if entity and entity.HotbarContainer and entity.HotbarContainer.Containers and entity.HotbarContainer.Containers.DefaultBarContainer then
        local customBar = entity.HotbarContainer.Containers.DefaultBarContainer[6]
        local spellName = nil
        for _, element in ipairs(customBar.Elements) do
            if element.Slot == slot then
                if element.SpellId then
                    return element.SpellId.OriginatorPrototype
                else
                    return nil
                end
            end
        end
    end
end

function getSpellByName(name)
    if name then
        local spellStats = Ext.Stats.Get(name)
        if spellStats then
            local spellType = spellStats.VerbalIntent
            if spellType and SpellTable[spellType] then
                return SpellTable[spellType][name]
            end
        end
    end
    return nil
end

function getForwardVector(entityUuid)
    local entity = Ext.Entity.Get(entityUuid)
    local rotationQuat = entity.Transform.Transform.RotationQuat
    local x = rotationQuat[1]
    local y = rotationQuat[2]
    local z = rotationQuat[3]
    local w = rotationQuat[4]
    local forwardX = 2*(x*z - w*y)
    local forwardY = 2*(y*z + w*x)
    local forwardZ = w*w - x*x - y*y + z*z
    local magnitude = math.sqrt(forwardX^2 + forwardY^2 + forwardZ^2)
    return forwardX/magnitude, forwardY/magnitude, forwardZ/magnitude
end

function getPointInFrontOf(entityUuid, distance)
    local forwardX, forwardY, forwardZ = getForwardVector(entityUuid)
    local translate = entity.Transform.Transform.Translate
    return translate[1] + forwardX*distance, translate[2] + forwardY*distance, translate[3] + forwardZ*distance
end

function getBrawlersSortedByDistance(entityUuid)
    local brawlersSortedByDistance = {}
    local level = Osi.GetRegion(entityUuid)
    if Brawlers[level] then
        for brawlerUuid, brawler in pairs(Brawlers[level]) do
            if isOnSameLevel(brawlerUuid, entityUuid) and isAliveAndCanFight(brawlerUuid) then
                table.insert(brawlersSortedByDistance, {brawlerUuid, Osi.GetDistanceTo(entityUuid, brawlerUuid)})
            end
        end
        table.sort(brawlersSortedByDistance, function (a, b) return a[2] < b[2] end)
    end
    return brawlersSortedByDistance
end

function calculateEnRouteCoords(moverUuid, targetUuid, goalDistance)
    local xMover, yMover, zMover = Osi.GetPosition(moverUuid)
    local xTarget, yTarget, zTarget = Osi.GetPosition(targetUuid)
    local dx = xMover - xTarget
    local dy = yMover - yTarget
    local dz = zMover - zTarget
    local fracDistance = goalDistance / math.sqrt(dx*dx + dy*dy + dz*dz)
    return Osi.FindValidPosition(xTarget + dx*fracDistance, yTarget + dy*fracDistance, zTarget + dz*fracDistance, 0, moverUuid, 1)
end

function getClosestEnemyBrawler(brawlerUuid, maxDistance)
    for _, target in ipairs(getBrawlersSortedByDistance(brawlerUuid)) do
        local targetUuid, distance = target[1], target[2]
        if Osi.IsEnemy(brawlerUuid, targetUuid) == 1 and distance < maxDistance then
            return targetUuid
        end
    end
    return nil
end

function getAdjustedDistanceTo(sourcePos, targetPos, sourceForwardX, sourceForwardY, sourceForwardZ)
    local deltaX = targetPos[1] - sourcePos[1]
    local deltaY = targetPos[2] - sourcePos[2]
    local deltaZ = targetPos[3] - sourcePos[3]
    local squaredDistance = deltaX*deltaX + deltaY*deltaY + deltaZ*deltaZ
    if squaredDistance < 1600 then -- 40^2 = 1600
        local distance = math.sqrt(squaredDistance)
        local vecToTargetX = deltaX/distance
        local vecToTargetY = deltaY/distance
        local vecToTargetZ = deltaZ/distance
        local dotProduct = sourceForwardX*vecToTargetX + sourceForwardY*vecToTargetY + sourceForwardZ*vecToTargetZ
        local weight = 0.5 -- on (0, 1)
        local adjustedDistance = distance*(1 + dotProduct*weight)
        if adjustedDistance < 0 then
            adjustedDistance = 0
        end
        debugPrint("Raw distance", distance, "dotProduct", dotProduct, "adjustedDistance", adjustedDistance)
        return adjustedDistance
    end
    return nil
end

function convertSpellRangeToNumber(range)
    if range == "RangedMainWeaponRange" then
        return 18
    elseif range == "MeleeMainWeaponRange" then
        return 2
    else
        return tonumber(range)
    end
end

function getSpellRange(spellName)
    if not spellName then
        return "MeleeMainWeaponRange"
    end
    local spell = Ext.Stats.Get(spellName)
    if isZoneSpell(spellName) then
        return spell.Range
    elseif spell.TargetRadius ~= "" then
        return spell.TargetRadius
    elseif spell.AreaRadius ~= "" then
        return spell.AreaRadius
    else
        return "MeleeMainWeaponRange"
    end
end

function isVisible(entityUuid)
    return Osi.IsInvisible(entityUuid) == 0 and Osi.HasActiveStatus(entityUuid, "SNEAKING") == 0
end

function isHealerArchetype(archetype)
    return archetype:find("healer") ~= nil
end

function isPlayerControllingDirectly(entityUuid)
    return Players[entityUuid] ~= nil and Players[entityUuid].isControllingDirectly == true
end

function isToT()
    return Mods.ToT ~= nil and Mods.ToT.IsActive()
end

function checkForDownedOrDeadPlayers()
    if Players then
        for uuid, player in pairs(Players) do
            if Osi.IsDead(uuid) == 1 or isDowned(uuid) then
                Osi.PurgeOsirisQueue(uuid, 1)
                Osi.FlushOsirisQueue(uuid)
                Osi.LieOnGround(uuid)
            end
        end
    end
end

function areAnyPlayersBrawling()
    if Players then
        for playerUuid, player in pairs(Players) do
            local level = Osi.GetRegion(playerUuid)
            if level and Brawlers[level] and Brawlers[level][playerUuid] then
                return true
            end
        end
    end
    return false
end

function getNumEnemiesRemaining(level)
    local numEnemiesRemaining = 0
    for brawlerUuid, brawler in pairs(Brawlers[level]) do
        if isPugnacious(brawlerUuid) and brawler.isInBrawl then
            numEnemiesRemaining = numEnemiesRemaining + 1
        end
    end
    return numEnemiesRemaining
end

function isSilenced(uuid)
    -- nb: what other labels can silences have? :/
    if Osi.HasActiveStatus(uuid, "SILENCED") == 1 then
        return true
    elseif Osi.HasActiveStatus(uuid, "SHA_SILENTLIBRARY_LIBRARIANSILENCE_STATUS") == 1 then
        return true
    end
    return false
end

function getArchetype(uuid)
    local archetype
    if Players and Players[uuid] then
        local modVars = Ext.Vars.GetModVariables(ModuleUUID)
        local partyArchetypes = modVars.PartyArchetypes
        if partyArchetypes == nil then
            partyArchetypes = {}
            modVars.PartyArchetypes = partyArchetypes
        else
            archetype = partyArchetypes[uuid]
        end
    end
    if archetype == nil or archetype == "" then
        archetype = Osi.GetActiveArchetype(uuid)
    end
    if not ARCHETYPE_WEIGHTS[archetype] then
        if archetype == "base" then
            archetype = "melee"
        elseif archetype:find("ranged") ~= nil then
            archetype = "ranged"
        elseif archetype:find("healer") ~= nil then
            archetype = "healer"
        elseif archetype:find("mage") ~= nil then
            archetype = "mage"
        elseif archetype:find("melee_magic") ~= nil then
            archetype = "melee_magic"
        elseif archetype:find("healer_melee") ~= nil then
            archetype = "healer_melee"
        else
            debugPrint("Archetype missing from the list, using melee for now", archetype)
            archetype = "melee"
        end
    end
    return archetype
end

function hasDirectHeal(uuid, preparedSpells)
    if isSilenced(uuid) then
        return false
    end
    for _, preparedSpell in ipairs(preparedSpells) do
        local spellName = preparedSpell.OriginatorPrototype
        if SpellTable.Healing[spellName] ~= nil and checkSpellResources(uuid, spellName) then
            return true
        end
    end
    return false
end

function isHostileTarget(uuid, targetUuid)
    local isBrawlerPlayerOrAlly = isPlayerOrAlly(uuid)
    local isPotentialTargetPlayerOrAlly = isPlayerOrAlly(targetUuid)
    local isHostile = false
    if isBrawlerPlayerOrAlly and isPotentialTargetPlayerOrAlly then
        isHostile = false
    elseif isBrawlerPlayerOrAlly and not isPotentialTargetPlayerOrAlly then
        isHostile = Osi.IsEnemy(uuid, targetUuid) == 1 or IsAttackingOrBeingAttackedByPlayer[targetUuid] ~= nil
    elseif not isBrawlerPlayerOrAlly and isPotentialTargetPlayerOrAlly then
        isHostile = Osi.IsEnemy(uuid, targetUuid) == 1 or IsAttackingOrBeingAttackedByPlayer[uuid] ~= nil
    elseif not isBrawlerPlayerOrAlly and not isPotentialTargetPlayerOrAlly then
        isHostile = Osi.IsEnemy(uuid, targetUuid) == 1
    else
        debugPrint("getWeightedTargets: what happened here?", uuid, targetUuid, getDisplayName(uuid), getDisplayName(targetUuid))
    end
    return isHostile
end

function whoNeedsHealing(uuid, level)
    local minTargetHpPct = 100.0
    local friendlyTargetUuid = nil
    for targetUuid, target in pairs(Brawlers[level]) do
        if isOnSameLevel(uuid, targetUuid) and Osi.IsAlly(uuid, targetUuid) == 1 then
            local targetHpPct = Osi.GetHitpointsPercentage(targetUuid)
            if targetHpPct ~= nil and targetHpPct > 0 and targetHpPct < minTargetHpPct then
                minTargetHpPct = targetHpPct
                friendlyTargetUuid = targetUuid
            end
        end
    end
    return friendlyTargetUuid
end

function isFTBAllLockedIn()
    for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
        local uuid = Osi.GetUUID(player[1])
        if not FTBLockedIn[uuid] and Osi.IsDead(uuid) == 0 and not isDowned(uuid) then
            return false
        end
    end
    return true
end

function isLocked(entity)
    return entity.TurnBased.CanAct_M and entity.TurnBased.HadTurnInCombat and not entity.TurnBased.IsInCombat_M
end

function isInFTB(entity)
    return entity.FTBParticipant and entity.FTBParticipant.field_18 ~= nil
end

function isPartyInRealTime()
    if Players then
        for uuid, _ in pairs(Players) do
            if Osi.IsInForceTurnBasedMode(uuid) == 1 then
                return false
            end
        end
    end
    return true
end

function isActionFinalized(entity)
    return entity.SpellCastIsCasting and entity.SpellCastIsCasting.Cast and entity.SpellCastIsCasting.Cast.SpellCastState
end

function createDummyObject(position)
    local dummyUuid = Osi.CreateAt(INVISIBLE_TEMPLATE_UUID, position[1], position[2], position[3], 0, 0, "")
    local dummyEntity = Ext.Entity.Get(dummyUuid)
    dummyEntity.GameObjectVisual.Scale = 0.0
    dummyEntity:Replicate("GameObjectVisual")
    Ext.Timer.WaitFor(1000, function ()
        Osi.RequestDelete(dummyUuid)
    end)
    return dummyUuid
end

function showNotification(uuid, text, duration)
    Ext.ServerNet.PostMessageToClient(uuid, "Notification", Ext.Json.Stringify({text = text, duration = duration}))
end
