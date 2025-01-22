local function debugPrint(...)
    if DEBUG_LOGGING then
        print(...)
    end
end

local function debugDump(...)
    if DEBUG_LOGGING then
        _D(...)
    end
end

local function dumpAllEntityKeys()
    local uuid = GetHostCharacter()
    local entity = Ext.Entity.Get(uuid)
    for k, _ in pairs(entity:GetAllComponents()) do
        print(k)
    end
end

local function dumpEntityToFile(entityUuid)
    Ext.IO.SaveFile(entityUuid .. ".json", Ext.DumpExport(Ext.Entity.Get(entityUuid):GetAllComponents()))
end

local function getDisplayName(entityUuid)
    return Osi.ResolveTranslatedString(Osi.GetDisplayName(entityUuid))
end

local function isAliveAndCanFight(entityUuid)
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
                    if uuid and isAliveAndCanFight(uuid) then
                        nearby[#nearby + 1] = {uuid = uuid, distance = distance}
                    end
                end
            end
        end
        table.sort(nearby, function (a, b) return a.distance < b.distance end)
    end
    return nearby
end

local function checkNearby()
    local nearbyUnits = getNearby(Osi.GetHostCharacter(), 50)
    for _, nearby in ipairs(nearbyUnits) do
        local uuid = nearby.uuid
        print(getDisplayName(uuid), uuid, Osi.CanJoinCombat(uuid))
    end
end

local function isDowned(entityUuid)
    return Osi.IsDead(entityUuid) == 0 and Osi.GetHitpoints(entityUuid) == 0
end

local function isPlayerOrAlly(entityUuid)
    return Osi.IsPlayer(entityUuid) == 1 or Osi.IsAlly(Osi.GetHostCharacter(), entityUuid) == 1
end

local function isPugnacious(potentialEnemyUuid, uuid)
    if uuid == nil then
        uuid = Osi.GetHostCharacter()
        if uuid == nil then
            return nil
        end
    end
    -- if State.Settings.MurderhoboMode and not isAllyOrPlayer(potentialEnemyUuid) then
    --     Osi.SetRelationTemporaryHostile(uuid, potentialEnemyUuid)
    -- end
    return Osi.IsEnemy(uuid, potentialEnemyUuid) == 1 or State.Session.IsAttackingOrBeingAttackedByPlayer[potentialEnemyUuid] ~= nil
end

-- from https://github.com/Norbyte/bg3se/blob/main/Docs/API.md#helper-functions
local function peerToUserId(peerId)
    return (peerId & 0xffff0000) | 0x0001
end

-- thank u focus
---@return "EASY"|"MEDIUM"|"HARD"|"HONOUR"
local function getDifficulty()
    local difficulty = Osi.GetRulesetModifierString("cac2d8bd-c197-4a84-9df1-f86f54ad4521")
    if difficulty == "HARD" and Osi.GetRulesetModifierBool("338450d9-d77d-4950-9e1e-0e7f12210bb3") == 1 then
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
    return split(spellName, "_")[1] == "Zone"
end

local function isProjectileSpell(spellName)
    return split(spellName, "_")[1] == "Projectile"
end

local function convertSpellRangeToNumber(range)
    if range == "RangedMainWeaponRange" then
        return 18
    elseif range == "MeleeMainWeaponRange" then
        return 2
    else
        return tonumber(range)
    end
end

local function getSpellRange(spellName)
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

local function isVisible(entityUuid)
    return Osi.IsInvisible(entityUuid) == 0 and Osi.HasActiveStatus(entityUuid, "SNEAKING") == 0
end

local function isHealerArchetype(archetype)
    return archetype:find("healer") ~= nil
end

local function isBrawlingWithValidTarget(brawler)
    return brawler.isInBrawl and brawler.targetUuid ~= nil and isAliveAndCanFight(brawler.targetUuid)
end

local function isOnSameLevel(uuid1, uuid2)
    local level1 = Osi.GetRegion(uuid1)
    local level2 = Osi.GetRegion(uuid2)
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
    local forwardX, forwardY, forwardZ = getForwardVector(entityUuid)
    local translate = entity.Transform.Transform.Translate
    return translate[1] + forwardX*distance, translate[2] + forwardY*distance, translate[3] + forwardZ*distance
end

local function clearOsirisQueue(uuid)
    Osi.PurgeOsirisQueue(uuid, 1)
    Osi.FlushOsirisQueue(uuid)
end

local function isVisible(entityUuid)
    return Osi.IsInvisible(entityUuid) == 0 and Osi.HasActiveStatus(entityUuid, "SNEAKING") == 0
end

local function isHealerArchetype(archetype)
    return archetype:find("healer") ~= nil
end

local function isToT()
    return Mods.ToT ~= nil and Mods.ToT.IsActive()
end

local function isSilenced(uuid)
    -- nb: what other labels can silences have? :/
    if Osi.HasActiveStatus(uuid, "SILENCED") == 1 then
        return true
    elseif Osi.HasActiveStatus(uuid, "SHA_SILENTLIBRARY_LIBRARIANSILENCE_STATUS") == 1 then
        return true
    end
    return false
end

local function createDummyObject(position)
    local dummyUuid = Osi.CreateAt(INVISIBLE_TEMPLATE_UUID, position[1], position[2], position[3], 0, 0, "")
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

Utils = {
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
    getDifficulty = getDifficulty,
    split = split,
    convertSpellRangeToNumber = convertSpellRangeToNumber,
    getSpellRange = getSpellRange,
    isZoneSpell = isZoneSpell,
    isProjectileSpell = isProjectileSpell,
    isVisible = isVisible,
    isHealerArchetype = isHealerArchetype,
    isBrawlingWithValidTarget = isBrawlingWithValidTarget,
    getNearby = getNearby,
    isOnSameLevel = isOnSameLevel,
    getForwardVector = getForwardVector,
    getPointInFrontOf = getPointInFrontOf,
    clearOsirisQueue = clearOsirisQueue,
    isVisible = isVisible,
    isHealerArchetype = isHealerArchetype,
    isToT = isToT,
    isSilenced = isSilenced,
    createDummyObject = createDummyObject,
    showNotification = showNotification,
    applyAttackMoveTargetVfx = applyAttackMoveTargetVfx,
    applyOnMeTargetVfx = applyOnMeTargetVfx,
}
