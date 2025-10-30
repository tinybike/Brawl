local function getBasename(path)
    path = path:gsub("\\", "/")
    local name = path:match(".*/([^/]+)$") or path
    return name:match("(.+)%..+$") or name
end

local function debugDisplay(fn, src, ...)
    if not Constants.DEBUG_LOGGING then
        return
    elseif Constants.DEBUG_LOGGING == true or (src and Constants.DEBUG_LOGGING[getBasename(src)]) then
        fn(...)
    end
end

local function debugPrint(...)
    debugDisplay(_P, (debug.getinfo(2, "S") or {}).short_src, ...)
end

local function debugDump(...)
    debugDisplay(_D, (debug.getinfo(2, "S") or {}).short_src, ...)
end

local function dumpAllEntityKeys(entity)
    local components = entity:GetAllComponents()
    local keys = {}
    for k, _ in pairs(components) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function (a, b) return a < b end)
    for _, k in ipairs(keys) do
        _P(k)
    end
end

local function dumpEntityToFile(entityUuid)
    Ext.IO.SaveFile(entityUuid .. ".json", Ext.DumpExport(Ext.Entity.Get(entityUuid):GetAllComponents()))
end

local function getDisplayName(entityUuid)
    local displayName = M.Osi.GetDisplayName(entityUuid)
    if displayName ~= nil then
        return M.Osi.ResolveTranslatedString(displayName)
    end
end

local function isAliveAndCanFight(entityUuid)
    if Constants.IS_TRAINING_DUMMY[entityUuid] == true then
        return true
    end
    local isDead = M.Osi.IsDead(entityUuid)
    if isDead == nil then
        return false
    end
    if isDead == 1 then
        return false
    end
    local hitpoints = M.Osi.GetHitpoints(entityUuid)
    if hitpoints == nil then
        return false
    end
    if hitpoints == 0 then
        return false
    end
    local canFight = M.Osi.CanFight(entityUuid)
    if canFight == nil then
        return false
    end
    if canFight == 0 then
        return false
    end
    return true
end

-- thank u hippo (modified from hippo0o/bg3-mods & AtilioA/BG3-volition-cabinet)
local function getNearby(source, radius)
    local entity = Ext.Entity.Get(source)
    local nearby = {}
    if entity and entity.Transform then
        local sourcePosition = entity.Transform.Transform.Translate
        local sqrt = math.sqrt
        local entities = Ext.Entity.GetAllEntitiesWithComponent("Uuid")
        for _, e in ipairs(entities) do
            if e and e.Transform and e.Transform.Transform then
                local position = e.Transform.Transform.Translate
                local dx = sourcePosition[1] - position[1]
                local dy = sourcePosition[2] - position[2]
                local dz = sourcePosition[3] - position[3]
                local distance = sqrt(dx*dx + dy*dy + dz*dz)
                if distance <= radius and e.IsCharacter and e.Uuid then
                    local uuid = e.Uuid.EntityUuid
                    if uuid and M.Utils.isAliveAndCanFight(uuid) then
                        nearby[#nearby + 1] = uuid
                    end
                end
            end
        end
    end
    return nearby
end

local function checkNearby()
    local nearby = M.Utils.getNearby(M.Osi.GetHostCharacter(), 50)
    for _, uuid in ipairs(nearby) do
        _P(M.Utils.getDisplayName(uuid), uuid, M.Osi.CanJoinCombat(uuid))
    end
end

local function isDowned(entityUuid)
    return M.Osi.IsDead(entityUuid) == 0 and M.Osi.GetHitpoints(entityUuid) == 0
end

local function isPlayerOrAlly(entityUuid)
    return M.Osi.IsPlayer(entityUuid) == 1 or M.Osi.IsAlly(M.Osi.GetHostCharacter(), entityUuid) == 1
end

local function isPugnacious(potentialEnemyUuid, uuid)
    if uuid == nil then
        uuid = M.Osi.GetHostCharacter()
        if uuid == nil then
            return nil
        end
    end
    return M.Osi.IsEnemy(uuid, potentialEnemyUuid) == 1 or State.Session.IsAttackingOrBeingAttackedByPlayer[potentialEnemyUuid] ~= nil
end

-- from https://github.com/Norbyte/bg3se/blob/main/Docs/API.md#helper-functions
local function peerToUserId(peerId)
    return (peerId & 0xffff0000) | 0x0001
end

local function userToPeerId(userId)
    return (userId & 0xffff0000) | ((userId & 0x0000ffff) - 1)
end

-- thank u focus
---@return "EASY"|"MEDIUM"|"HARD"|"HONOUR"
local function getDifficulty()
    local difficulty = M.Osi.GetRulesetModifierString("cac2d8bd-c197-4a84-9df1-f86f54ad4521")
    if difficulty == "HARD" and M.Osi.GetRulesetModifierBool("338450d9-d77d-4950-9e1e-0e7f12210bb3") == 1 then
        return "HONOUR"
    end
    return difficulty
end

local function split(inputstr, sep)
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

local function isZoneSpell(spellName)
    return M.Utils.split(spellName, "_")[1] == "Zone"
end

local function isProjectileSpell(spellName)
    return M.Utils.split(spellName, "_")[1] == "Projectile"
end

local function convertSpellRangeToNumber(range)
    if range == "RangedMainWeaponRange" or range == "ThrownObjectRange" then
        return 18
    elseif range == "MeleeMainWeaponRange" then
        return 2
    else
        return tonumber(range)
    end
end

local function getPersistentModVars(label)
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    if label ~= nil then
        return modVars[label]
    end
    return modVars
end

local function getSpellRange(spellName)
    if not spellName then
        return "MeleeMainWeaponRange"
    end
    local spell = Ext.Stats.Get(spellName)
    if M.Utils.isZoneSpell(spellName) then
        return spell.Range
    elseif spell.TargetRadius ~= "" then
        return spell.TargetRadius
    elseif spell.AreaRadius ~= "" then
        return spell.AreaRadius
    else
        return "MeleeMainWeaponRange"
    end
end

local function isVisible(uuid, targetUuid)
    if M.Osi.HasActiveStatus(uuid, "TRUESIGHT") == 1 or M.Osi.HasActiveStatus(uuid, "MOD_Generic_Truesight") == 1 then
        return true
    end
    local hasSeeInvisibility = M.Osi.HasActiveStatus(uuid, "SEE_INVISIBILITY") == 1 or M.Osi.HasActiveStatus(uuid, "MAG_SEE_INVISIBILITY_HIDDEN_IGNORE_RESTING") == 1
    if hasSeeInvisibility and M.Osi.GetDistanceTo(uuid, targetUuid) <= 9 then
        return true
    end
    return M.Osi.IsInvisible(targetUuid) == 0 and M.Osi.HasActiveStatus(targetUuid, "SNEAKING") == 0
end

local function isMeleeArchetype(archetype)
    return archetype:find("melee") ~= nil or archetype:find("beast") ~= nil
end

local function isHealerArchetype(archetype)
    return archetype:find("healer") ~= nil
end

local function isBrawlingWithValidTarget(brawler)
    return brawler.isInBrawl and brawler.targetUuid ~= nil and M.Utils.isAliveAndCanFight(brawler.targetUuid)
end

local function isOnSameLevel(uuid1, uuid2)
    local level1 = M.Osi.GetRegion(uuid1)
    local level2 = M.Osi.GetRegion(uuid2)
    return level1 ~= nil and level2 ~= nil and level1 == level2
end

local function getForwardVector(entityUuid)
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

local function getPointInFrontOf(entityUuid, distance)
    local forwardX, forwardY, forwardZ = M.Utils.getForwardVector(entityUuid)
    local translate = entity.Transform.Transform.Translate
    return translate[1] + forwardX*distance, translate[2] + forwardY*distance, translate[3] + forwardZ*distance
end

local function isCounterspell(spellName)
    for _, counterspell in ipairs(Constants.COUNTERSPELLS) do
        if spellName == counterspell then
            return true
        end
    end
    return false
end

local function removeNegativeStatuses(uuid)
    -- Osi.RemoveStatusesWithGroup(uuid, "SG_Charmed")
    -- Osi.RemoveStatusesWithGroup(uuid, "SG_Petrified")
    -- Osi.RemoveStatusesWithGroup(uuid, "SG_Cursed")
    -- Osi.RemoveStatusesWithGroup(uuid, "SG_Stunned")
    -- Osi.RemoveStatusesWithGroup(uuid, "SG_Incapacitated")
    -- Osi.RemoveStatusesWithGroup(uuid, "SG_Blinded")
    -- Osi.RemoveStatusesWithGroup(uuid, "SG_Polymorph")
    -- Osi.RemoveStatusesWithGroup(uuid, "SG_Condition")
    -- Osi.RemoveStatusesWithGroup(uuid, "SG_Prone")
    -- Osi.RemoveStatusesWithGroup(uuid, "SG_Surface")
    -- Osi.RemoveStatusesWithGroup(uuid, "SG_Dominated")
    -- Osi.RemoveStatus(uuid, "SILENCED")
    Osi.RemoveStatus(uuid, "ATT_FEEBLEMIND", "")
    Osi.RemoveStatus(uuid, "ATT_TIMECOMPRESSION", "")
end

local function clearOsirisQueue(uuid)
    -- print("clearOsirisQueue", uuid, M.Utils.getDisplayName(uuid))
    Osi.PurgeOsirisQueue(uuid, 1)
    Osi.FlushOsirisQueue(uuid)
end

local function isToT()
    return Mods.ToT ~= nil and Mods.ToT.IsActive()
end

local function isSilenced(uuid)
    -- nb: what other labels can silences have? :/
    if M.Osi.HasActiveStatus(uuid, "SILENCED") == 1 then
        return true
    elseif M.Osi.HasActiveStatus(uuid, "SHA_SILENTLIBRARY_LIBRARIANSILENCE_STATUS") == 1 then
        return true
    end
    return false
end

local function createDummyObject(position)
    local dummyUuid = Osi.CreateAt(Constants.INVISIBLE_TEMPLATE_UUID, position[1], position[2], position[3], 0, 0, "")
    local dummyEntity = Ext.Entity.Get(dummyUuid)
    dummyEntity.GameObjectVisual.Scale = 0.0
    dummyEntity:Replicate("GameObjectVisual")
    Ext.Timer.WaitFor(1000, function ()
        Osi.RequestDelete(dummyUuid)
    end)
    return dummyUuid
end

local function showNotification(uuid, text, duration)
    Ext.ServerNet.PostMessageToClient(uuid, "Notification", Ext.Json.Stringify({text = text, duration = duration}))
end

local function applyAttackMoveTargetVfx(targetUuid)
    -- Osi.ApplyStatus(targetUuid, "HEROES_FEAST_CHEST", 1)
    Osi.ApplyStatus(targetUuid, "END_HIGHHALLINTERIOR_DROPPODTARGET_VFX", 1)
    Osi.ApplyStatus(targetUuid, "MAG_ARCANE_VAMPIRISM_VFX", 1)
end

local function applyOnMeTargetVfx(targetUuid)
    Osi.ApplyStatus(targetUuid, "GUIDED_STRIKE", 1)
    Osi.ApplyStatus(targetUuid, "MAG_ARCANE_VAMPIRISM_VFX", 1)
    -- Osi.ApplyStatus(targetUuid, "END_HIGHHALLINTERIOR_DROPPODTARGET_VFX", 1)
    -- Osi.ApplyStatus(targetUuid, "PASSIVE_DISCIPLE_OF_LIFE", 1)
    -- Osi.ApplyStatus(targetUuid, "EPI_SPECTRALVOICEVFX", 1)
end

local function isPlayerTurnEnded(uuid)
    local entity = Ext.Entity.Get(uuid)
    if entity and entity.TurnBased and entity.TurnBased.RequestedEndTurn == false then
        return false
    end
    return true
end

local function getTrackingDistance()
    return State.Settings.TurnBasedSwarmMode and Constants.TRACKING_DISTANCE_TBSM or Constants.TRACKING_DISTANCE_RT
end

local function canAct(uuid)
    if not uuid or M.Utils.isDowned(uuid) or not M.Utils.isAliveAndCanFight(uuid) then
        return false
    end
    for _, noActionStatus in ipairs(Constants.NO_ACTION_STATUSES) do
        if M.Osi.HasActiveStatus(uuid, noActionStatus) == 1 then
            debugPrint(M.Utils.getDisplayName(uuid), "has a no action status", noActionStatus)
            return false
        end
    end
    return true
end

local function canMove(uuid)
    local entity = Ext.Entity.Get(uuid)
    if entity and entity.CanMove and entity.CanMove.Flags then
        for _, flag in ipairs(entity.CanMove.Flags) do
            if flag == "CanMove" then
                return true
            end
        end
    end
    return false
end

-- Thanks Focus
local function hasLoseControlStatus(uuid)
    local entity = Ext.Entity.Get(uuid)
    if entity and entity.StatusLoseControl ~= nil then
        return true
    end
    return false
end

local function isHostileTarget(uuid, targetUuid)
    local isBrawlerPlayerOrAlly = M.Utils.isPlayerOrAlly(uuid)
    local isPotentialTargetPlayerOrAlly = M.Utils.isPlayerOrAlly(targetUuid)
    local isHostile = false
    if isBrawlerPlayerOrAlly and isPotentialTargetPlayerOrAlly then
        isHostile = false
    elseif isBrawlerPlayerOrAlly and not isPotentialTargetPlayerOrAlly then
        isHostile = M.Osi.IsEnemy(uuid, targetUuid) == 1 or State.Session.IsAttackingOrBeingAttackedByPlayer[targetUuid] ~= nil
    elseif not isBrawlerPlayerOrAlly and isPotentialTargetPlayerOrAlly then
        isHostile = M.Osi.IsEnemy(uuid, targetUuid) == 1 or State.Session.IsAttackingOrBeingAttackedByPlayer[uuid] ~= nil
    elseif not isBrawlerPlayerOrAlly and not isPotentialTargetPlayerOrAlly then
        isHostile = M.Osi.IsEnemy(uuid, targetUuid) == 1
    else
        debugPrint(M.Utils.getDisplayName(uuid), "isHostileTarget: what happened here?", uuid, targetUuid, M.Utils.getDisplayName(targetUuid))
    end
    return isHostile
end

local function getCombatEntity()
    local serverEnterRequestEntities = Ext.Entity.GetAllEntitiesWithComponent("ServerEnterRequest")
    if serverEnterRequestEntities and serverEnterRequestEntities[1] then
        return serverEnterRequestEntities[1]
    end
end

local function joinCombat(uuid)
    local combatEntity = getCombatEntity()
    if combatEntity and combatEntity.ServerEnterRequest and combatEntity.ServerEnterRequest.EnterRequests then
        local entity = Ext.Entity.Get(uuid)
        if entity and M.Osi.CanJoinCombat(uuid) == 1 and M.Osi.IsInCombat(uuid) == 0 then
            combatEntity.ServerEnterRequest.EnterRequests[entity] = true
        end
    end
end

local function setPlayersSwarmGroup()
    local players = State.Session.Players
    if players then
        for uuid, _ in pairs(players) do
            Osi.RequestSetSwarmGroup(uuid, "PLAYER_SWARM_GROUP")
        end
    end
end

local function showTurnOrderGroups(groups)
    for i, group in ipairs(groups) do
        if group.Members then
            local groupStr = ""
            if group.IsPlayer then
                groupStr = groupStr .. "    "
            end
            groupStr = groupStr .. tostring(i)
            for j, member in ipairs(group.Members) do
                if member.Entity and member.Entity.Uuid and member.Entity.Uuid.EntityUuid then
                    if j > 1 then
                        groupStr = groupStr .. " +"
                    end
                    groupStr = groupStr .. " " .. M.Utils.getDisplayName(member.Entity.Uuid.EntityUuid)
                end
            end
            print(groupStr)
        end
    end
end

local function setPlayerTurnsActive()
    local combatEntity = getCombatEntity()
    if combatEntity and combatEntity.TurnOrder and combatEntity.TurnOrder.Groups then
        print("********init***********")
        showTurnOrderGroups(combatEntity.TurnOrder.Groups)
        local groupsPlayers = {}
        local groupsEnemies = {}
        for _, info in ipairs(combatEntity.TurnOrder.Groups) do
            if info.IsPlayer then
                table.insert(groupsPlayers, info)
            else
                table.insert(groupsEnemies, info)
            end
        end
        local numPlayerGroups = #groupsPlayers
        for i = 1, numPlayerGroups do
            combatEntity.TurnOrder.Groups[i] = groupsPlayers[i]
        end
        for i = 1, #groupsEnemies do
            combatEntity.TurnOrder.Groups[i + numPlayerGroups] = groupsEnemies[i]
        end
        print("********after*********")
        showTurnOrderGroups(combatEntity.TurnOrder.Groups)
    end
end

local function getCurrentCombatRound()
    local serverEnterRequestEntities = Ext.Entity.GetAllEntitiesWithComponent("ServerEnterRequest")
    if serverEnterRequestEntities then
        local combatEntity = serverEnterRequestEntities[1]
        if combatEntity and combatEntity.TurnOrder and combatEntity.TurnOrder.field_40 then
            return combatEntity.TurnOrder.field_40
        end
    end
end

local function hasStatus(entity, targetStatus)
    if entity and entity.StatusContainer and entity.StatusContainer.Statuses then
        for _, status in pairs(entity.StatusContainer.Statuses) do
            if status == targetStatus then
                return true
            end
        end
    end
    return false
end

local function hasPassive(entity, targetPassive)
    if entity and entity.PassiveContainer and entity.PassiveContainer.Passives then
        for _, passiveEntity in ipairs(entity.PassiveContainer.Passives) do
            if passiveEntity.Passive and passiveEntity.Passive.PassiveId == targetPassive then
                return true
            end
        end
    end
    return false
end

local function getAbility(entity, ability)
    if entity and entity.Stats and entity.Stats.Abilities and Constants.ABILITIES[ability] then
        return entity.Stats.Abilities[Constants.ABILITIES[ability]]
    end
end

local function isConcentrating(uuid)
    local entity = Ext.Entity.Get(uuid)
    if entity then
        local concentration = entity.Concentration
        if concentration and concentration.SpellId and concentration.SpellId.OriginatorPrototype ~= "" then
            return true
        end
    end
    return false
end

local function isValidHostileTarget(uuid, targetUuid)
    if not M.Utils.isVisible(uuid, targetUuid) then
        return false
    elseif not M.Utils.isAliveAndCanFight(targetUuid) and not M.Utils.isDowned(targetUuid) then
        return false
    else
        local entity = Ext.Entity.Get(targetUuid)
        if entity then
            if M.Utils.hasStatus(entity, "SANCTUARY") then
                return false
            elseif M.Utils.hasStatus(entity, "INVULNERABLE") then
                return false
            end
        end
    end
    return true
end

local function checkDivineIntervention(spellName, casterUuid)
    if spellName == "Shout_DivineIntervention_Healing" or spellName == "Shout_DivineIntervention_Healing_Improvement" then
        local areaRadius = Ext.Stats.Get(spellName).AreaRadius
        for uuid, _ in pairs(State.Session.Players) do
            if M.Osi.GetDistanceTo(uuid, casterUuid) <= areaRadius then
                removeNegativeStatuses(uuid)
                Resources.restoreAllActionResources(uuid)
                -- Resources.restoreSpellSlots(uuid)
            end
        end
    end
end

local function getSpellNameBySlot(uuid, slot)
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

-- thank u focus
---@return Guid
local function createUuid()
    return string.gsub("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx", "[xy]", function (c)
        return string.format("%x", c == "x" and Ext.Math.Random(0, 0xf) or Ext.Math.Random(8, 0xb))
    end)
end

local function getCurrentRegion()
    local uuid = M.Osi.GetHostCharacter()
    if uuid then
        return M.Osi.GetRegion(uuid)
    end
end

local function getOriginatorPrototype(spellName, stats)
    if not stats or not stats.RootSpellID or stats.RootSpellID == "" then
        return spellName
    end
    return stats.RootSpellID
end

local function startsWith(str, prefix)
    return str:sub(1, #prefix) == prefix
end

local function timeIt(fn, ...)
    local t0 = Ext.Utils.MonotonicTime()
    fn(...)
    return Ext.Utils.MonotonicTime() - t0
end

local function totalTime(fn, n, ...)
    local sum = 0
    for i = 1, n do
        sum = sum + timeIt(fn, ...)
    end
    return sum
end

local function averageTime(fn, n, ...)
    return totalTime(fn, n, ...) / n
end

local function noop() end

return {
    debugPrint = debugPrint,
    debugDump = debugDump,
    dumpAllEntityKeys = dumpAllEntityKeys,
    dumpEntityToFile = dumpEntityToFile,
    checkNearby = checkNearby,
    getDisplayName = getDisplayName,
    isDowned = isDowned,
    isAliveAndCanFight = isAliveAndCanFight,
    isPlayerOrAlly = isPlayerOrAlly,
    isPugnacious = isPugnacious,
    peerToUserId = peerToUserId,
    userToPeerId = userToPeerId,
    getDifficulty = getDifficulty,
    split = split,
    convertSpellRangeToNumber = convertSpellRangeToNumber,
    getSpellRange = getSpellRange,
    isZoneSpell = isZoneSpell,
    isProjectileSpell = isProjectileSpell,
    isVisible = isVisible,
    isHealerArchetype = isHealerArchetype,
    isMeleeArchetype = isMeleeArchetype,
    isBrawlingWithValidTarget = isBrawlingWithValidTarget,
    getNearby = getNearby,
    isOnSameLevel = isOnSameLevel,
    getForwardVector = getForwardVector,
    getPointInFrontOf = getPointInFrontOf,
    clearOsirisQueue = clearOsirisQueue,
    isToT = isToT,
    isSilenced = isSilenced,
    createDummyObject = createDummyObject,
    showNotification = showNotification,
    applyAttackMoveTargetVfx = applyAttackMoveTargetVfx,
    applyOnMeTargetVfx = applyOnMeTargetVfx,
    isPlayerTurnEnded = isPlayerTurnEnded,
    getTrackingDistance = getTrackingDistance,
    canAct = canAct,
    canMove = canMove,
    hasLoseControlStatus = hasLoseControlStatus,
    isHostileTarget = isHostileTarget,
    getCombatEntity = getCombatEntity,
    showTurnOrderGroups = showTurnOrderGroups,
    setPlayersSwarmGroup = setPlayersSwarmGroup,
    setPlayerTurnsActive = setPlayerTurnsActive,
    getCurrentCombatRound = getCurrentCombatRound,
    hasStatus = hasStatus,
    hasPassive = hasPassive,
    getAbility = getAbility,
    isConcentrating = isConcentrating,
    isValidHostileTarget = isValidHostileTarget,
    checkDivineIntervention = checkDivineIntervention,
    getSpellNameBySlot = getSpellNameBySlot,
    getCurrentRegion = getCurrentRegion,
    createUuid = createUuid,
    isCounterspell = isCounterspell,
    removeNegativeStatuses = removeNegativeStatuses,
    getOriginatorPrototype = getOriginatorPrototype,
    startsWith = startsWith,
    averageTime = averageTime,
    totalTime = totalTime,
    getPersistentModVars = getPersistentModVars,
    noop = noop,
}
