-- local Constants = require("Server/Constants.lua")
-- local State = require("Server/State.lua")

local function debugPrint(...)
    if Constants.DEBUG_LOGGING then
        _P(...)
    end
end

local function debugDump(...)
    if Constants.DEBUG_LOGGING then
        _D(...)
    end
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
    local displayName = Osi.GetDisplayName(entityUuid)
    if displayName ~= nil then
        return Osi.ResolveTranslatedString(displayName)
    end
end

local function isAliveAndCanFight(entityUuid)
    if Constants.IS_TRAINING_DUMMY[entityUuid] == true then
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
                        nearby[#nearby + 1] = uuid
                    end
                end
            end
        end
    end
    return nearby
end

local function checkNearby()
    local nearby = getNearby(Osi.GetHostCharacter(), 50)
    for _, uuid in ipairs(nearby) do
        _P(getDisplayName(uuid), uuid, Osi.CanJoinCombat(uuid))
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

local function isMeleeArchetype(archetype)
    return archetype:find("melee") ~= nil or archetype:find("beast") ~= nil
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
    -- debugPrint("clearOsirisQueue", uuid, getDisplayName(uuid))
    Osi.PurgeOsirisQueue(uuid, 1)
    Osi.FlushOsirisQueue(uuid)
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

local function canAct(uuid)
    if not uuid or isDowned(uuid) or not isAliveAndCanFight(uuid) then
        return false
    end
    for _, noActionStatus in ipairs(Constants.NO_ACTION_STATUSES) do
        if Osi.HasActiveStatus(uuid, noActionStatus) == 1 then
            debugPrint(getDisplayName(uuid), "has a no action status", noActionStatus)
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
    -- NB: not yet in SE release branch
    -- if Ext.Entity.Get(uuid).StatusLoseControl ~= nil then
    --     return true
    -- end
    if entity and entity.ServerCharacter and entity.ServerCharacter.StatusManager and entity.ServerCharacter.StatusManager.Statuses then
        for _, status in ipairs(entity.ServerCharacter.StatusManager.Statuses) do
            local stats = Ext.Stats.Get(status.StatusId, nil, false)
            if stats ~= nil then
                for _, flag in ipairs(stats.StatusPropertyFlags) do
                    if flag == "LoseControl" or flag == "LoseControlFriendly" then
                        return true
                    end
                end
            end
        end
    end
    return false
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

-- thank u focus
---@return Guid
local function createUuid()
    return string.gsub("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx", "[xy]", function (c)
        return string.format("%x", c == "x" and Ext.Math.Random(0, 0xf) or Ext.Math.Random(8, 0xb))
    end)
end

local function getOriginatorPrototype(spellName, stats)
    if not stats or not stats.RootSpellID or stats.RootSpellID == "" then
        return spellName
    end
    return stats.RootSpellID
end

local function timeIt(fn, ...)
    local t0 = Ext.Utils.MonotonicTime()
    fn(...)
    return Ext.Utils.MonotonicTime() - t0
end

local function averageTime(fn, n, ...)
    local sum = 0
    for i = 1, n do
        sum = sum + timeIt(fn, ...)
    end
    return sum / n
end

local function syncLeaderboard(uuid)
    if State.Settings.TurnBasedSwarmMode and State.Settings.LeaderboardEnabled then
        local leaderboardData = Ext.Json.Stringify(State.Session.Leaderboard or {})
        if not uuid then
            Ext.ServerNet.BroadcastMessage("Leaderboard", leaderboardData)
        else
            Ext.ServerNet.PostMessageToClient(uuid, "Leaderboard", leaderboardData)
        end
    end
end

local function updateLeaderboardKills(uuid)
    if State.Settings.TurnBasedSwarmMode and State.Settings.LeaderboardEnabled and Osi.IsCharacter(uuid) == 1 then
        State.Session.Leaderboard[uuid] = State.Session.Leaderboard[uuid] or {}
        State.Session.Leaderboard[uuid].name = State.Session.Leaderboard[uuid].name or (getDisplayName(uuid) or "")
        State.Session.Leaderboard[uuid].kills = State.Session.Leaderboard[uuid].kills or 0
        State.Session.Leaderboard[uuid].kills = State.Session.Leaderboard[uuid].kills + 1
    end
end

local function updateLeaderboardDamage(attackerUuid, defenderUuid, amount)
    if State.Settings.TurnBasedSwarmMode and State.Settings.LeaderboardEnabled and Osi.IsCharacter(defenderUuid) == 1 then
        State.Session.Leaderboard[defenderUuid] = State.Session.Leaderboard[defenderUuid] or {}
        State.Session.Leaderboard[defenderUuid].name = State.Session.Leaderboard[defenderUuid].name or (getDisplayName(defenderUuid) or "")
        State.Session.Leaderboard[defenderUuid].damageTaken = State.Session.Leaderboard[defenderUuid].damageTaken or 0
        State.Session.Leaderboard[defenderUuid].damageTaken = State.Session.Leaderboard[defenderUuid].damageTaken + amount
        State.Session.Leaderboard[attackerUuid] = State.Session.Leaderboard[attackerUuid] or {}
        State.Session.Leaderboard[attackerUuid].name = State.Session.Leaderboard[attackerUuid].name or (getDisplayName(attackerUuid) or "")
        State.Session.Leaderboard[attackerUuid].damageDone = State.Session.Leaderboard[attackerUuid].damageDone or 0
        if Osi.IsEnemy(attackerUuid, defenderUuid) == 0 then
            amount = -amount
        end
        State.Session.Leaderboard[attackerUuid].damageDone = State.Session.Leaderboard[attackerUuid].damageDone + amount
    end
end

local function addNamesToLeaderboard()
    if State.Session.Leaderboard then
        for uuid, stats in pairs(State.Session.Leaderboard) do
            State.Session.Leaderboard[uuid].name = getDisplayName(uuid) or ""
        end
    end
end

local function dumpLeaderboard()
    local nameColWidth, ddW, dtW, kW = 0, #("Damage"), #("Taken"), #("Kills")
    for uuid, stats in pairs(State.Session.Leaderboard) do
        nameColWidth = math.max(nameColWidth, #stats.name)
        ddW = math.max(ddW, #tostring(stats.damageDone or 0))
        dtW = math.max(dtW, #tostring(stats.damageTaken or 0))
        kW = math.max(kW, #tostring(stats.kills or 0))
    end
    local nameFmt = "%-" .. nameColWidth .. "s"
    local ddFmt = "%" .. ddW  .. "d"
    local dtFmt = "%" .. dtW  .. "d"
    local kFmt = "%" .. kW  .. "d"
    local colSep = "  "
    local fmt = table.concat({ nameFmt, ddFmt, dtFmt, kFmt }, colSep)
    local hdrFmt = table.concat({ nameFmt, "%-" .. ddW .. "s", "%-" .. dtW .. "s", "%-" .. kW .. "s" }, colSep)
    local totalWidth = nameColWidth + #colSep + ddW + #colSep + dtW + #colSep + kW
    local function makeSep(title)
        local txt = "| " .. title .. " |"
        local pad = totalWidth - #txt
        local left = math.floor(pad/2)
        local right = pad - left
        return string.rep("=", left) .. txt .. string.rep("=", right)
    end
    local party, enemy = {}, {}
    for uuid, stats in pairs(State.Session.Leaderboard) do
        local row = {
            uuid = uuid,
            name = stats.name,
            damageDone = stats.damageDone or 0,
            damageTaken = stats.damageTaken or 0,
            kills = stats.kills or 0,
        }
        if Osi.IsPartyMember(uuid, 1) == 1 then
            party[#party + 1] = row
        else
            enemy[#enemy + 1] = row
        end
    end
    table.sort(party, function (a, b) return a.damageDone > b.damageDone end)
    table.sort(enemy, function (a, b) return a.damageDone > b.damageDone end)
    _P(makeSep("PARTY TOTALS"))
    _P(string.format(hdrFmt, "Name", "Damage", "Taken", "Kills"))
    for _, e in ipairs(party) do
        _P(string.format(fmt, e.name, e.damageDone, e.damageTaken, e.kills))
    end
    _P(makeSep("ENEMY TOTALS"))
    _P(string.format(hdrFmt, "Name", "Damage", "Taken", "Kills"))
    for _, e in ipairs(enemy) do
        _P(string.format(fmt, e.name, e.damageDone, e.damageTaken, e.kills))
    end
    _P(string.rep("=", totalWidth))
end

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
    canAct = canAct,
    canMove = canMove,
    hasLoseControlStatus = hasLoseControlStatus,
    getCurrentCombatRound = getCurrentCombatRound,
    createUuid = createUuid,
    getOriginatorPrototype = getOriginatorPrototype,
    averageTime = averageTime,
    getPersistentModVars = getPersistentModVars,
    updateLeaderboardKills = updateLeaderboardKills,
    updateLeaderboardDamage = updateLeaderboardDamage,
    dumpLeaderboard = dumpLeaderboard,
    showLeaderboard = showLeaderboard,
    syncLeaderboard = syncLeaderboard,
    addNamesToLeaderboard = addNamesToLeaderboard,
}
