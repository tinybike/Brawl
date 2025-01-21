function setMovementSpeedThresholds()
    MovementSpeedThresholds = MOVEMENT_SPEED_THRESHOLDS[getDifficulty()]
end

function applyAttackMoveTargetVfx(targetUuid)
    -- Osi.ApplyStatus(targetUuid, "HEROES_FEAST_CHEST", 1)
    Osi.ApplyStatus(targetUuid, "END_HIGHHALLINTERIOR_DROPPODTARGET_VFX", 1)
    Osi.ApplyStatus(targetUuid, "MAG_ARCANE_VAMPIRISM_VFX", 1)
end

function applyOnMeTargetVfx(targetUuid)
    Osi.ApplyStatus(targetUuid, "GUIDED_STRIKE", 1)
    Osi.ApplyStatus(targetUuid, "MAG_ARCANE_VAMPIRISM_VFX", 1)
    -- Osi.ApplyStatus(targetUuid, "END_HIGHHALLINTERIOR_DROPPODTARGET_VFX", 1)
    -- Osi.ApplyStatus(targetUuid, "PASSIVE_DISCIPLE_OF_LIFE", 1)
    -- Osi.ApplyStatus(targetUuid, "EPI_SPECTRALVOICEVFX", 1)
end

function setAwaitingTarget(uuid, isAwaitingTarget)
    if uuid ~= nil then
        AwaitingTarget[uuid] = isAwaitingTarget
        Ext.ServerNet.PostMessageToClient(uuid, "AwaitingTarget", (isAwaitingTarget == true) and "1" or "0")
    end
end

function findPathToPosition(playerUuid, position, callback)
    local validX, validY, validZ = Osi.FindValidPosition(position[1], position[2], position[3], 0, playerUuid, 1)
    if validX ~= nil and validY ~= nil and validZ ~= nil then
        local validPosition = {validX, validY, validZ}
        LastClickPosition[playerUuid] = {position = validPosition}
        if MovementQueue[playerUuid] ~= nil or AwaitingTarget[playerUuid] then
            Ext.Level.BeginPathfinding(Ext.Entity.Get(playerUuid), validPosition, function (path)
                if not path or not path.GoalFound then
                    return showNotification(playerUuid, "Can't get there", 2)
                end
                callback(validPosition)
            end)
        end
    end
end

function moveCompanionsToPlayer(playerUuid)
    for uuid, _ in pairs(Players) do
        if not isPlayerControllingDirectly(uuid) then
            Osi.PurgeOsirisQueue(uuid, 1)
            Osi.FlushOsirisQueue(uuid)
            Osi.CharacterMoveTo(uuid, playerUuid, getMovementSpeed(uuid), "")
        end
    end
end

function moveCompanionsToPosition(position)
    for uuid, _ in pairs(Players) do
        if not isPlayerControllingDirectly(uuid) or FullAuto then
            Osi.PurgeOsirisQueue(uuid, 1)
            Osi.FlushOsirisQueue(uuid)
            Osi.CharacterMoveToPosition(uuid, position[1], position[2], position[3], getMovementSpeed(uuid), "")
        end
    end
end

function lockCompanionsOnTarget(level, targetUuid)
    for uuid, _ in pairs(Players) do
        if isAliveAndCanFight(uuid) and (not isPlayerControllingDirectly(uuid) or FullAuto) then
            if not Brawlers[level][uuid] then
                addBrawler(uuid, true)
            end
            if Brawlers[level][uuid] and uuid ~= targetUuid then
                Brawlers[level][uuid].targetUuid = targetUuid
                Brawlers[level][uuid].lockedOnTarget = true
                debugPrint("Set target to", uuid, getDisplayName(uuid), targetUuid, getDisplayName(targetUuid))
            end
        end
    end
end

function moveToDistanceFromTarget(moverUuid, targetUuid, goalDistance)
    local x, y, z = calculateEnRouteCoords(moverUuid, targetUuid, goalDistance)
    if x ~= nil and y ~= nil and z ~= nil then
        Osi.PurgeOsirisQueue(moverUuid, 1)
        Osi.FlushOsirisQueue(moverUuid)
        Osi.CharacterMoveToPosition(moverUuid, x, y, z, getMovementSpeed(moverUuid), "")
    end
end

-- Example monk looping animations (can these be interruptable?)
-- (https://bg3.norbyte.dev/search?iid=Resource.6b05dbcc-19ef-475f-62a2-d18c1e640aa7)
-- animMK = "e85be5a8-6e48-4da4-8486-0d168159df4e"
-- animMK = "7bb52cd4-0b1c-4926-9165-fa92b75876a3"
function holdPosition(entityUuid)
    if not isPlayerOrAlly(entityUuid) then
        Osi.PlayAnimation(entityUuid, LOOPING_COMBAT_ANIMATION_ID, "")
        -- Osi.PlayLoopingAnimation(entityUuid, LOOPING_COMBAT_ANIMATION_ID, LOOPING_COMBAT_ANIMATION_ID, LOOPING_COMBAT_ANIMATION_ID, LOOPING_COMBAT_ANIMATION_ID, LOOPING_COMBAT_ANIMATION_ID, LOOPING_COMBAT_ANIMATION_ID, LOOPING_COMBAT_ANIMATION_ID)
    end
end

function checkSpellCharge(casterUuid, spellName)
    -- debugPrint("checking spell charge", casterUuid, spellName)
    if spellName then
        local entity = Ext.Entity.Get(casterUuid)
        if entity and entity.SpellBook and entity.SpellBook.Spells then
            for i, spell in ipairs(entity.SpellBook.Spells) do
                -- NB: OriginatorPrototype or Prototype?
                if spell.Id.Prototype == spellName then
                    if spell.Charged == false then
                        debugPrint("spell is not charged", spellName, casterUuid)
                        return false
                    end
                end
            end
            return true
        end
    end
    return false
end

function checkSpellResources(casterUuid, spellName, variant, upcastLevel)
    local entity = Ext.Entity.Get(casterUuid)
    local isSpellPrepared = false
    for _, preparedSpell in ipairs(entity.SpellBookPrepares.PreparedSpells) do
        if preparedSpell.OriginatorPrototype == spellName then
            isSpellPrepared = true
            break
        end
    end
    if not isSpellPrepared then
        debugPrint("Caster does not have spell", spellName, "prepared")
        return false
    end
    if variant ~= nil then
        spellName = variant
    end
    local spell = getSpellByName(spellName)
    if not spell then
        debugPrint("Error: spell not found")
        return false
    end
    -- if spell and spell.costs then
    --     debugDump(spell.costs)
    -- end
    if upcastLevel ~= nil then
        debugPrint("Upcasted spell level", upcastLevel)
    end
    for costType, costValue in pairs(spell.costs) do
        if costType == "ShortRest" or costType == "LongRest" then
            if costValue and not checkSpellCharge(casterUuid, spellName) then
                return false
            end
        elseif costType ~= "ActionPoint" and costType ~= "BonusActionPoint" then
            if costType == "SpellSlot" then
                local spellLevel = upcastLevel == nil and costValue or upcastLevel
                local availableResourceValue = Osi.GetActionResourceValuePersonal(casterUuid, costType, spellLevel)
                if availableResourceValue < 1 then
                    debugPrint("SpellSlot: Needs 1 level", spellLevel, "slot to cast", spellName, ";", availableResourceValue, "slots available")
                    return false
                end
            else
                local availableResourceValue = Osi.GetActionResourceValuePersonal(casterUuid, costType, 0)
                if availableResourceValue < costValue then
                    debugPrint(costType, "Needs", costValue, "to cast", spellName, ";", availableResourceValue, "available")
                    return false
                end
            end
        end
    end
    return true
end

function useSpellAndResourcesAtPosition(casterUuid, position, spellName, variant, upcastLevel)
    if not checkSpellResources(casterUuid, spellName, variant, upcastLevel) then
        return false
    end
    if variant ~= nil then
        spellName = variant
    end
    if upcastLevel ~= nil then
        spellName = spellName .. "_" .. tostring(upcastLevel)
    end
    debugPrint("casting at position", spellName, position[1], position[2], position[3])
    Osi.PurgeOsirisQueue(casterUuid, 1)
    Osi.FlushOsirisQueue(casterUuid)
    ActionsInProgress[casterUuid] = ActionsInProgress[casterUuid] or {}
    table.insert(ActionsInProgress[casterUuid], spellName)
    Osi.UseSpellAtPosition(casterUuid, spellName, position[1], position[2], position[3])
    return true
end

function useSpellAndResources(casterUuid, targetUuid, spellName, variant, upcastLevel)
    if targetUuid == nil then
        return false
    end
    if not checkSpellResources(casterUuid, spellName, variant, upcastLevel) then
        return false
    end
    if variant ~= nil then
        spellName = variant
    end
    if upcastLevel ~= nil then
        spellName = spellName .. "_" .. tostring(upcastLevel)
    end
    debugPrint("casting on target", spellName, targetUuid, getDisplayName(targetUuid))
    Osi.PurgeOsirisQueue(casterUuid, 1)
    Osi.FlushOsirisQueue(casterUuid)
    ActionsInProgress[casterUuid] = ActionsInProgress[casterUuid] or {}
    table.insert(ActionsInProgress[casterUuid], spellName)
    Osi.UseSpell(casterUuid, spellName, targetUuid)
    -- for Zone (and projectile, maybe if pressing shift?) spells, shoot in direction of facing
    -- local x, y, z = getPointInFrontOf(casterUuid, 1.0)
    -- Osi.UseSpellAtPosition(casterUuid, spellName, x, y, z, 1)
    return true
end

function useSpellOnClosestEnemyTarget(playerUuid, spellName)
    if spellName then
        local targetUuid = getClosestEnemyBrawler(playerUuid, 40)
        if targetUuid then
            return useSpellAndResources(playerUuid, targetUuid, spellName)
        end
    end
end

function buildClosestEnemyBrawlers(playerUuid)
    if PlayerMarkedTarget[playerUuid] and not isAliveAndCanFight(PlayerMarkedTarget[playerUuid]) then
        PlayerMarkedTarget[playerUuid] = nil
    end
    local playerEntity = Ext.Entity.Get(playerUuid)
    local playerPos = playerEntity.Transform.Transform.Translate
    local playerForwardX, playerForwardY, playerForwardZ = getForwardVector(playerUuid)
    local maxTargets = 10
    local topTargets = {}
    local level = Osi.GetRegion(playerUuid)
    if Brawlers[level] then
        for brawlerUuid, brawler in pairs(Brawlers[level]) do
            if isOnSameLevel(brawlerUuid, playerUuid) and isAliveAndCanFight(brawlerUuid) and isPugnacious(brawlerUuid, playerUuid) then
                local brawlerEntity = Ext.Entity.Get(brawlerUuid)
                if brawlerEntity then
                    local adjustedDistance = getAdjustedDistanceTo(playerPos, brawlerEntity.Transform.Transform.Translate, playerForwardX, playerForwardY, playerForwardZ)
                    if adjustedDistance ~= nil then
                        local inserted = false
                        for i = 1, #topTargets do
                            if adjustedDistance < topTargets[i].adjustedDistance then
                                table.insert(topTargets, i, {uuid = brawlerUuid, adjustedDistance = adjustedDistance})
                                inserted = true
                                break
                            end
                        end
                        if not inserted and #topTargets < maxTargets then
                            table.insert(topTargets, {uuid = brawlerUuid, adjustedDistance = adjustedDistance})
                        end
                        if #topTargets > maxTargets then
                            topTargets[#topTargets] = nil
                        end
                    end
                end
            end
        end
    end
    ClosestEnemyBrawlers[playerUuid] = {}
    for i, target in ipairs(topTargets) do
        ClosestEnemyBrawlers[playerUuid][i] = target.uuid
    end
    if #ClosestEnemyBrawlers[playerUuid] > 0 and PlayerMarkedTarget[playerUuid] == nil then
        PlayerMarkedTarget[playerUuid] = ClosestEnemyBrawlers[playerUuid][1]
    end
    debugPrint("Closest enemy brawlers to player", playerUuid, getDisplayName(playerUuid))
    debugDump(ClosestEnemyBrawlers)
    debugPrint("Current target:", PlayerMarkedTarget[playerUuid])
    Ext.Timer.WaitFor(3000, function ()
        ClosestEnemyBrawlers[playerUuid] = nil
    end)
end

function selectNextEnemyBrawler(playerUuid, isNext)
    local nextTargetIndex = nil
    local nextTargetUuid = nil
    for enemyBrawlerIndex, enemyBrawlerUuid in ipairs(ClosestEnemyBrawlers[playerUuid]) do
        if PlayerMarkedTarget[playerUuid] == enemyBrawlerUuid then
            debugPrint("found current target", PlayerMarkedTarget[playerUuid], enemyBrawlerUuid, enemyBrawlerIndex, ClosestEnemyBrawlers[playerUuid][enemyBrawlerIndex])
            if isNext then
                debugPrint("getting NEXT target")
                if enemyBrawlerIndex < #ClosestEnemyBrawlers[playerUuid] then
                    nextTargetIndex = enemyBrawlerIndex + 1
                else
                    nextTargetIndex = 1
                end
            else
                debugPrint("getting PREVIOUS target")
                if enemyBrawlerIndex > 1 then
                    nextTargetIndex = enemyBrawlerIndex - 1
                else
                    nextTargetIndex = #ClosestEnemyBrawlers[playerUuid]
                end
            end
            debugPrint("target index", nextTargetIndex)
            debugDump(ClosestEnemyBrawlers)
            nextTargetUuid = ClosestEnemyBrawlers[playerUuid][nextTargetIndex]
            debugPrint("target uuid", nextTargetUuid)
            break
        end
    end
    if nextTargetUuid then
        if PlayerMarkedTarget[playerUuid] ~= nil then
            Osi.RemoveStatus(PlayerMarkedTarget[playerUuid], "LOW_HAG_MUSHROOM_VFX")
        end
        debugPrint("pinging next target", nextTargetUuid)
        local x, y, z = Osi.GetPosition(nextTargetUuid)
        Osi.RequestPing(x, y, z, nextTargetUuid, playerUuid)
        Osi.ApplyStatus(nextTargetUuid, "LOW_HAG_MUSHROOM_VFX", -1)
        PlayerMarkedTarget[playerUuid] = nextTargetUuid
    end
end

function moveToTarget(attackerUuid, targetUuid, spellName)
    local range = getSpellRange(spellName)
    local rangeNumber
    Osi.PurgeOsirisQueue(attackerUuid, 1)
    Osi.FlushOsirisQueue(attackerUuid)
    local attackerCanMove = Osi.CanMove(attackerUuid) == 1
    if range == "MeleeMainWeaponRange" then
        Osi.CharacterMoveTo(attackerUuid, targetUuid, getMovementSpeed(attackerUuid), "")
    elseif range == "RangedMainWeaponRange" then
        rangeNumber = 18
    else
        rangeNumber = tonumber(range)
        local distanceToTarget = Osi.GetDistanceTo(attackerUuid, targetUuid)
        if distanceToTarget > rangeNumber and attackerCanMove then
            debugPrint("moveToTarget distance > range, moving to...")
            moveToDistanceFromTarget(attackerUuid, targetUuid, rangeNumber)
        end
    end
    local canSeeTarget = Osi.CanSee(attackerUuid, targetUuid) == 1
    if not canSeeTarget and spellName and not string.match(spellName, "^Projectile_MagicMissile") and attackerCanMove then
        debugPrint("moveToTarget can't see target, moving closer")
        moveToDistanceFromTarget(attackerUuid, targetUuid, targetRadiusNumber or 2)
    end
end

function useSpellOnTarget(attackerUuid, targetUuid, spellName)
    debugPrint("useSpellOnTarget", attackerUuid, targetUuid, spellName, HogwildMode)
    if HogwildMode then
        Osi.UseSpell(attackerUuid, spellName, targetUuid)
    else
        useSpellAndResources(attackerUuid, targetUuid, spellName)
    end
end

function getSpellTypeWeight(spellType)
    if spellType == "Damage" then
        return 7
    elseif spellType == "Healing" then
        return 7
    elseif spellType == "Control" then
        return 3
    elseif spellType == "Buff" then
        return 3
    end
    return 0
end

function getResistanceWeight(spell, entity)
    if entity and entity.Resistances and entity.Resistances.Resistances then
        local resistances = entity.Resistances.Resistances
        if spell.damageType ~= "None" and resistances[DAMAGE_TYPES[spell.damageType]] and resistances[DAMAGE_TYPES[spell.damageType]][1] then
            local resistance = resistances[DAMAGE_TYPES[spell.damageType]][1]
            if resistance == "ImmuneToNonMagical" or resistance == "ImmuneToMagical" then
                return -1000
            elseif resistance == "ResistantToNonMagical" or resistance == "ResistantToMagical" then
                return -5
            elseif resistance == "VulnerableToNonMagical" or resistance == "VulnerableToMagical" then
                return 5
            end
        end
    end
    return 0
end

function getHighestWeightSpell(weightedSpells)
    if next(weightedSpells) == nil then
        return nil
    end
    local maxWeight = nil
    local selectedSpell = nil
    for spellName, weight in pairs(weightedSpells) do
        if (maxWeight == nil) or (weight > maxWeight) then
            maxWeight = weight
            selectedSpell = spellName
        end
    end
    return (selectedSpell ~= "Target_MainHandAttack") and selectedSpell
end

function getSpellWeight(spell, distanceToTarget, archetype, spellType)
    -- Special target radius labels (NB: are there others besides these two?)
    -- Maybe should weight proportional to distance required to get there...?
    local weight = 0
    if spell.targetRadius == "RangedMainWeaponRange" then
        weight = weight + ARCHETYPE_WEIGHTS[archetype].rangedWeapon
        if distanceToTarget > RANGED_RANGE_MIN and distanceToTarget < RANGED_RANGE_MAX then
            weight = weight + ARCHETYPE_WEIGHTS[archetype].rangedWeaponInRange
        else
            weight = weight + ARCHETYPE_WEIGHTS[archetype].rangedWeaponOutOfRange
        end
    elseif spell.targetRadius == "MeleeMainWeaponRange" then
        weight = weight + ARCHETYPE_WEIGHTS[archetype].meleeWeapon
        if distanceToTarget <= MELEE_RANGE then
            weight = weight + ARCHETYPE_WEIGHTS[archetype].meleeWeaponInRange
        end
    else
        local targetRadius = tonumber(spell.targetRadius)
        if targetRadius then
            if distanceToTarget <= targetRadius then
                weight = weight + ARCHETYPE_WEIGHTS[archetype].spellInRange
            end
        else
            debugPrint("Target radius didn't convert to number, what is this?")
            debugPrint(spell.targetRadius)
        end
    end
    -- Favor using spells or non-spells?
    if spell.isSpell then
        weight = weight + ARCHETYPE_WEIGHTS[archetype].isSpell
    end
    -- If this spell has a damage type, favor vulnerable enemies
    -- (NB: this doesn't account for physical weapon damage, which is attached to the weapon itself -- todo)
    -- weight = weight + getResistanceWeight(spell, targetEntity)
    -- Adjust by spell type (damage and healing spells are somewhat favored in general)
    weight = weight + getSpellTypeWeight(spellType)
    -- Adjust by spell level (higher level spells are disfavored, unless we're in hogwild mode)
    -- if not HogwildMode then
    --     weight = weight - spell.level
    -- end
    if HogwildMode then
        weight = weight + spell.level*3
    end
    -- Randomize weight by +/- 30% to keep it interesting
    weight = math.floor(weight*(0.7 + math.random()*0.6) + 0.5)
    return weight
end

-- NB: need to allow healing, buffs, debuffs etc for companions too
function isCompanionSpellAvailable(uuid, spellName, spell, isSilenced, distanceToTarget, targetDistanceToParty, allowAoE)
    -- This should never happen but...
    if spellName == nil or spell == nil then
        return false
    end
    -- If we're silenced, we can't use spells that have a verbal component
    if isSilenced and spell.hasVerbalComponent then
        return false
    end
    -- Exclude AoE and zone-type damage spells for now (even in Hogwild Mode) so the companions don't blow each other up on accident
    if spell.isSafeAoE == false then
        if not allowAoE and spell.type == "Damage" and (spell.areaRadius > 0 or isZoneSpell(spellName)) then
            return false
        end
        if allowAoE and spell.isEvocation == false then
            return false
        end
    end
    -- If it's a healing spell, make sure it's a direct heal
    if spell.type == "Healing" and not spell.isDirectHeal then
        return false
    end
    if spell.isSelfOnly and distanceToTarget ~= 0.0 then
        return false
    end
    if not HogwildMode then
        -- Make sure we're not exceeding the user's specified AI max spell level
        if spell.level > CompanionAIMaxSpellLevel then
            return false
        end
        -- Make sure we have the resources to actually cast what we want to cast
        if not checkSpellResources(uuid, spellName) then
            return false
        end
    end
    -- For defense tactics:
    --  1. Is the target already within range? Then ok to use
    --  2. If the target is out-of-range, can we hit him without moving outside of the perimeter? Then ok to use
    if CompanionTactics == "Defense" then
        local range = convertSpellRangeToNumber(getSpellRange(spellName))
        if distanceToTarget > range and targetDistanceToParty > (range + DEFENSE_TACTICS_MAX_DISTANCE) then
            return false
        end
    end
    return true
end

function isNpcSpellUsable(spell)
    if spell == "Projectile_Jump" then return false end
    if spell == "Shout_Dash_NPC" then return false end
    if spell == "Target_Shove" then return false end
    if spell == "Target_Devour_Ghoul" then return false end
    if spell == "Target_Devour_ShadowMound" then return false end
    if spell == "Target_LOW_RamazithsTower_Nightsong_Globe_1" then return false end
    if spell == "Target_Dip_NPC" then return false end
    if spell == "Projectile_SneakAttack" then return false end
    return true
end

function isEnemySpellAvailable(uuid, spellName, spell, isSilenced)
    if spellName == nil or spell == nil then
        return false
    end
    if isSilenced and spell.hasVerbalComponent then
        return false
    end
    if spell.type == "Healing" and not spell.isDirectHeal then
        return false
    end
    if spell.outOfCombatOnly then
        return false
    end
    if not HogwildMode then
        if not checkSpellResources(uuid, spellName) then
            return false
        end
    end
    return true
end

-- What to do?  In all cases, give extra weight to spells that you're already within range for
-- 1. Check if any players are downed and nearby, if so, help them up.
-- 2? Check if any players are badly wounded and in-range, if so, heal them? (...but this will consume resources...)
-- 3. Attack an enemy.
-- 3a. If primarily a caster class, favor spell attacks (cantrips).
-- 3b. If primarily a ranged class, favor ranged attacks.
-- 3c. If primarily a healer/melee class, favor melee abilities and attacks.
-- 3d. If primarily a melee (or other) class, favor melee attacks.
-- 4. Status effects/buffs (NYI)
function getCompanionWeightedSpells(uuid, preparedSpells, distanceToTarget, archetype, spellTypes, targetDistanceToParty, allowAoE)
    local weightedSpells = {}
    local silenced = isSilenced(uuid)
    for _, preparedSpell in pairs(preparedSpells) do
        local spellName = preparedSpell.OriginatorPrototype
        local spell = nil
        for _, spellType in ipairs(spellTypes) do
            spell = SpellTable[spellType][spellName]
            if spell ~= nil then
                break
            end
        end
        if isCompanionSpellAvailable(uuid, spellName, spell, silenced, distanceToTarget, targetDistanceToParty, allowAoE) then
            weightedSpells[spellName] = getSpellWeight(spell, distanceToTarget, archetype, spellType)
        end
    end
    return weightedSpells
end

-- What to do?  In all cases, give extra weight to spells that you're already within range for
-- 1. Check if any friendlies are badly wounded and in-range, if so, heal them.
-- 2. Attack an enemy.
-- 2a. If primarily a caster class, favor spell attacks (cantrips).
-- 2b. If primarily a ranged class, favor ranged attacks.
-- 2c. If primarily a healer/melee class, favor melee abilities and attacks.
-- 2d. If primarily a melee (or other) class, favor melee attacks.
-- 3. Status effects/buffs/debuffs (NYI)
function getWeightedSpells(uuid, preparedSpells, distanceToTarget, archetype, spellTypes)
    local weightedSpells = {}
    local silenced = isSilenced(uuid)
    for _, preparedSpell in pairs(preparedSpells) do
        local spellName = preparedSpell.OriginatorPrototype
        if isNpcSpellUsable(spellName) then
            local spell = nil
            for _, spellType in ipairs(spellTypes) do
                spell = SpellTable[spellType][spellName]
                if spell ~= nil then
                    break
                end
            end
            if isEnemySpellAvailable(uuid, spellName, spell, silenced) then
                weightedSpells[spellName] = getSpellWeight(spell, distanceToTarget, archetype, spellType)
            end
        end
    end
    return weightedSpells
end

function decideCompanionActionOnTarget(brawler, preparedSpells, distanceToTarget, spellTypes, targetDistanceToParty, allowAoE)
    local weightedSpells = getCompanionWeightedSpells(brawler.uuid, preparedSpells, distanceToTarget, brawler.archetype, spellTypes, targetDistanceToParty, allowAoE)
    debugPrint("companion weighted spells", getDisplayName(brawler.uuid), brawler.archetype, distanceToTarget)
    debugDump(ARCHETYPE_WEIGHTS[brawler.archetype])
    debugDump(weightedSpells)
    return getHighestWeightSpell(weightedSpells)
end

function decideActionOnTarget(brawler, preparedSpells, distanceToTarget, spellTypes)
    local weightedSpells = getWeightedSpells(brawler.uuid, preparedSpells, distanceToTarget, brawler.archetype, spellTypes)
    return getHighestWeightSpell(weightedSpells)
end

function actOnHostileTarget(brawler, target)
    local distanceToTarget = Osi.GetDistanceTo(brawler.uuid, target.uuid)
    if brawler and target then
        -- todo: Utility spells
        local spellTypes = {"Control", "Damage"}
        local actionToTake = nil
        local preparedSpells = Ext.Entity.Get(brawler.uuid).SpellBookPrepares.PreparedSpells
        if Osi.IsPlayer(brawler.uuid) == 1 then
            local allowAoE = Osi.HasPassive(brawler.uuid, "SculptSpells") == 1
            local playerClosestToTarget = Osi.GetClosestAlivePlayer(target.uuid) or brawler.uuid
            local targetDistanceToParty = Osi.GetDistanceTo(target.uuid, playerClosestToTarget)
            debugPrint("target distance to party", targetDistanceToParty, playerClosestToTarget)
            actionToTake = decideCompanionActionOnTarget(brawler, preparedSpells, distanceToTarget, {"Damage"}, targetDistanceToParty, allowAoE)
            debugPrint("Companion action to take on hostile target", actionToTake, brawler.uuid, brawler.displayName, target.uuid, target.displayName)
        else
            actionToTake = decideActionOnTarget(brawler, preparedSpells, distanceToTarget, spellTypes)
            debugPrint("Action to take on hostile target", actionToTake, brawler.uuid, brawler.displayName, target.uuid, target.displayName, brawler.archetype)
        end
        if actionToTake == nil and Osi.IsPlayer(brawler.uuid) == 0 then
            local numUsableSpells = 0
            local usableSpells = {}
            for _, preparedSpell in pairs(preparedSpells) do
                local spellName = preparedSpell.OriginatorPrototype
                if isNpcSpellUsable(spellName) then
                    if SpellTable.Damage[spellName] or SpellTable.Control[spellName] then
                        table.insert(usableSpells, spellName)
                        numUsableSpells = numUsableSpells + 1
                    end
                end
            end
            if numUsableSpells > 1 then
                actionToTake = usableSpells[math.random(1, numUsableSpells)]
            elseif numUsableSpells == 1 then
                actionToTake = usableSpells[1]
            end
            debugPrint("backup ActionToTake", actionToTake, numUsableSpells)
        end
        moveToTarget(brawler.uuid, target.uuid, actionToTake)
        if actionToTake then
            useSpellOnTarget(brawler.uuid, target.uuid, actionToTake)
        else
            Osi.Attack(brawler.uuid, target.uuid, 0)
        end
        return true
    end
    return false
end

function actOnFriendlyTarget(brawler, target)
    local distanceToTarget = Osi.GetDistanceTo(brawler.uuid, target.uuid)
    debugDump(brawler)
    local preparedSpells = Ext.Entity.Get(brawler.uuid).SpellBookPrepares.PreparedSpells
    if preparedSpells ~= nil then
        -- todo: Utility/Buff spells
        debugPrint("acting on friendly target", brawler.uuid, brawler.displayName, getDisplayName(target.uuid))
        local spellTypes = {"Healing"}
        if not hasDirectHeal(brawler.uuid, preparedSpells) then
            debugPrint("No direct heals found")
            return false
        end
        local actionToTake = nil
        if Osi.IsPlayer(brawler.uuid) == 1 then
            actionToTake = decideCompanionActionOnTarget(brawler, preparedSpells, distanceToTarget, spellTypes, 0, true)
        else
            actionToTake = decideActionOnTarget(brawler, preparedSpells, distanceToTarget, spellTypes)
        end
        debugPrint("Action to take on friendly target", actionToTake, brawler.uuid, brawler.displayName)
        if actionToTake ~= nil then
            moveToTarget(brawler.uuid, target.uuid, actionToTake)
            useSpellOnTarget(brawler.uuid, target.uuid, actionToTake)
            return true
        end
        return false
    end
    return false
end

function getOffenseWeightedTarget(distanceToTarget, targetHp, targetHpPct, canSeeTarget, isHealer, isHostile)
    if not isHostile and targetHpPct == 100.0 then
        return nil
    end
    local weightedTarget = 2*distanceToTarget + 0.25*targetHp
    if not canSeeTarget then
        weightedTarget = weightedTarget*1.4
    end
    if isHealer and not isHostile then
        weightedTarget = weightedTarget*0.6
    elseif not isHealer and isHostile then
        weightedTarget = weightedTarget*0.4
    end
    return weightedTarget
end

function getDefenseWeightedTarget(distanceToTarget, targetHp, targetHpPct, canSeeTarget, isHealer, isHostile, attackerUuid, targetUuid, closestAlivePlayer)
    if not isHostile and targetHpPct == 100.0 then
        return nil
    end
    if not closestAlivePlayer then
        return getOffenseWeightedTarget(distanceToTarget, targetHp, canSeeTarget, isHealer, isHostile)
    end
    local weightedTarget
    local targetDistanceToParty = Osi.GetDistanceTo(targetUuid, closestAlivePlayer)
    -- Only include potential targets that are within X meters of the party
    if targetDistanceToParty ~= nil and targetDistanceToParty < DEFENSE_TACTICS_MAX_DISTANCE then
        weightedTarget = 3*distanceToTarget + 0.25*targetHp
        if not canSeeTarget then
            weightedTarget = weightedTarget*1.8
        end
        if isHealer and not isHostile then
            weightedTarget = weightedTarget*0.4
        elseif not isHealer and isHostile then
            weightedTarget = weightedTarget*0.6
        end
    end
    return weightedTarget    
end

-- Attacking targets: prioritize close targets with less remaining HP
-- (Lowest weight = most desireable target)
function getWeightedTargets(brawler, potentialTargets)
    local weightedTargets = {}
    local isHealer = isHealerArchetype(brawler.archetype)
    local closestAlivePlayer
    if CompanionTactics == "Defense" and isPlayerOrAlly(brawler.uuid) then
        closestAlivePlayer = Osi.GetClosestAlivePlayer(brawler.uuid)
    end
    for potentialTargetUuid, _ in pairs(potentialTargets) do
        if brawler.uuid ~= potentialTargetUuid and isVisible(potentialTargetUuid) and isAliveAndCanFight(potentialTargetUuid) then
            local distanceToTarget = Osi.GetDistanceTo(brawler.uuid, potentialTargetUuid)
            local canSeeTarget = Osi.CanSee(brawler.uuid, potentialTargetUuid) == 1
            if (distanceToTarget < 30 and canSeeTarget) or ActiveCombatGroups[brawler.combatGroupId] or IsAttackingOrBeingAttackedByPlayer[potentialTargetUuid] then
                local isHostile = isHostileTarget(brawler.uuid, potentialTargetUuid)
                if isHostile or hasDirectHeal(brawler.uuid, Ext.Entity.Get(brawler.uuid).SpellBookPrepares.PreparedSpells) then
                    local targetHp = Osi.GetHitpoints(potentialTargetUuid)
                    local targetHpPct = Osi.GetHitpointsPercentage(potentialTargetUuid)
                    if not isPlayerOrAlly(brawler.uuid) then
                        weightedTargets[potentialTargetUuid] = getOffenseWeightedTarget(distanceToTarget, targetHp, targetHpPct, canSeeTarget, isHealer, isHostile)
                        ActiveCombatGroups[brawler.combatGroupId] = true
                    else
                        if CompanionTactics == "Offense" then
                            weightedTargets[potentialTargetUuid] = getOffenseWeightedTarget(distanceToTarget, targetHp, targetHpPct, canSeeTarget, isHealer, isHostile)
                        elseif CompanionTactics == "Defense" then
                            weightedTargets[potentialTargetUuid] = getDefenseWeightedTarget(distanceToTarget, targetHp, targetHpPct, canSeeTarget, isHealer, isHostile, brawler.uuid, potentialTargetUuid, closestAlivePlayer)
                        end
                    end
                    -- NB: this is too intense of a request and will crash the game :/
                    -- local concentration = Ext.Entity.Get(potentialTargetUuid).Concentration
                    -- if concentration and concentration.SpellId and concentration.SpellId.OriginatorPrototype ~= "" then
                    --     weightedTargets[potentialTargetUuid] = weightedTargets[potentialTargetUuid] * AI_TARGET_CONCENTRATION_WEIGHT_MULTIPLIER
                    -- end
                end
            end
        end
    end
    return weightedTargets
end

function decideOnTarget(weightedTargets)
    local targetUuid = nil
    local minWeight = nil
    if next(weightedTargets) ~= nil then
        for potentialTargetUuid, targetWeight in pairs(weightedTargets) do
            if minWeight == nil or targetWeight < minWeight then
                minWeight = targetWeight
                targetUuid = potentialTargetUuid
            end
        end
        if targetUuid then
            return targetUuid
        end
    end
    return nil
end

function findTarget(brawler)
    local level = Osi.GetRegion(brawler.uuid)
    if level then
        local brawlersSortedByDistance = getBrawlersSortedByDistance(brawler.uuid)
        -- Healing
        local isPlayer = Osi.IsPlayer(brawler.uuid) == 1
        local wasHealRequested = false
        local userId
        if isPlayer then
            userId = Osi.GetReservedUserID(brawler.uuid)
            wasHealRequested = HealRequested[userId]
        end
        if wasHealRequested then
            if Brawlers[level] then
                local friendlyTargetUuid = whoNeedsHealing(brawler.uuid, level)
                if friendlyTargetUuid and Brawlers[level][friendlyTargetUuid] then
                    debugPrint("actOnFriendlyTarget", brawler.uuid, brawler.displayName, friendlyTargetUuid, getDisplayName(friendlyTargetUuid))
                    if actOnFriendlyTarget(brawler, Brawlers[level][friendlyTargetUuid]) then
                        HealRequested[userId] = false
                        return true
                    end
                    return false
                end
            end
        end
        -- Attacking
        local weightedTargets = getWeightedTargets(brawler, Brawlers[level])
        local targetUuid = decideOnTarget(weightedTargets)
        -- debugDump(weightedTargets)
        -- debugPrint("got target", targetUuid)
        if targetUuid and Brawlers[level][targetUuid] then
            local result
            if isHostileTarget(brawler.uuid, targetUuid) then
                result = actOnHostileTarget(brawler, Brawlers[level][targetUuid])
                -- debugPrint("result (hostile)", result)
                if result == true then
                    brawler.targetUuid = targetUuid
                end
            else
                result = actOnFriendlyTarget(brawler, Brawlers[level][targetUuid])
                -- debugPrint("result (friendly)", result)
            end
            if result == true then
                return true
            end
        end
        -- debugPrint("can't find a target, holding position", brawler.uuid, brawler.displayName)
        holdPosition(brawler.uuid)
        return false
    end
end

function addPlayersInEnterCombatRangeToBrawlers(brawlerUuid)
    for playerUuid, player in pairs(Players) do
        local distanceTo = Osi.GetDistanceTo(brawlerUuid, playerUuid)
        if distanceTo ~= nil and distanceTo < ENTER_COMBAT_RANGE then
            addBrawler(playerUuid)
        end
    end
end

function stopPulseAction(brawler, remainInBrawl)
    if not remainInBrawl then
        brawler.isInBrawl = false
    end
    if PulseActionTimers[brawler.uuid] ~= nil then
        debugPrint("stop pulse action", brawler.displayName, remainInBrawl)
        Ext.Timer.Cancel(PulseActionTimers[brawler.uuid])
        PulseActionTimers[brawler.uuid] = nil
    end
end

-- Brawlers doing dangerous stuff
function pulseAction(brawler)
    -- Brawler is alive and able to fight: let's go!
    if brawler and brawler.uuid then
        if not brawler.isPaused and isAliveAndCanFight(brawler.uuid) and (not isPlayerControllingDirectly(brawler.uuid) or FullAuto) then
            -- NB: if we allow healing spells etc used by companions, roll this code in, instead of special-casing it here...
            if isPlayerOrAlly(brawler.uuid) then
                for playerUuid, player in pairs(Players) do
                    if not player.isBeingHelped and brawler.uuid ~= playerUuid and isDowned(playerUuid) and Osi.GetDistanceTo(playerUuid, brawler.uuid) < HELP_DOWNED_MAX_RANGE then
                        player.isBeingHelped = true
                        brawler.targetUuid = nil
                        debugPrint("Helping target", playerUuid, getDisplayName(playerUuid))
                        moveToTarget(brawler.uuid, playerUuid, "Target_Help")
                        return useSpellOnTarget(brawler.uuid, playerUuid, "Target_Help")
                    end
                end
            else
                addPlayersInEnterCombatRangeToBrawlers(brawler.uuid)
            end
            -- Doesn't currently have an attack target, so let's find one
            if brawler.targetUuid == nil then
                debugPrint("Find target (no current target)", brawler.uuid, brawler.displayName)
                return findTarget(brawler)
            end
            -- We have a target and the target is alive
            local level = Osi.GetRegion(brawler.uuid)
            if level and isOnSameLevel(brawler.uuid, brawler.targetUuid) and Brawlers[level][brawler.targetUuid] and isAliveAndCanFight(brawler.targetUuid) and isVisible(brawler.targetUuid) then
                if Osi.GetDistanceTo(brawler.uuid, brawler.targetUuid) <= 12 or brawler.lockedOnTarget then
                    debugPrint("Attacking", brawler.displayName, brawler.uuid, "->", getDisplayName(brawler.targetUuid))
                    return actOnHostileTarget(brawler, Brawlers[level][brawler.targetUuid])
                end
            end
            -- Has an attack target but it's already dead or unable to fight, so find a new one
            debugPrint("Find target (current target invalid)", brawler.uuid, brawler.displayName)
            brawler.targetUuid = nil
            return findTarget(brawler)
        end
        -- If this brawler is dead or unable to fight, stop this pulse
        stopPulseAction(brawler)
    end
end

function startPulseAction(brawler)
    if Osi.IsPlayer(brawler.uuid) == 1 and not CompanionAIEnabled then
        return false
    end
    if IS_TRAINING_DUMMY[brawler.uuid] then
        return false
    end
    if PulseActionTimers[brawler.uuid] == nil then
        brawler.isInBrawl = true
        local noisedActionInterval = math.floor(ActionInterval*(0.7 + math.random()*0.6) + 0.5)
        debugPrint("Starting pulse action", brawler.displayName, brawler.uuid, noisedActionInterval)
        PulseActionTimers[brawler.uuid] = Ext.Timer.WaitFor(0, function ()
            -- debugPrint("pulse action", brawler.uuid, brawler.displayName)
            pulseAction(brawler)
        end, noisedActionInterval)
    end
end

function setPlayerRunToSprint(entityUuid)
    local entity = Ext.Entity.Get(entityUuid)
    if entity and entity.ServerCharacter then
        if Players[entityUuid].movementSpeedRun == nil then
            Players[entityUuid].movementSpeedRun = entity.ServerCharacter.Template.MovementSpeedRun
        end
        entity.ServerCharacter.Template.MovementSpeedRun = entity.ServerCharacter.Template.MovementSpeedSprint
    end
end

function addBrawler(entityUuid, isInBrawl, replaceExistingBrawler)
    if entityUuid ~= nil then
        local level = Osi.GetRegion(entityUuid)
        local okToAdd = false
        if replaceExistingBrawler then
            okToAdd = level and Brawlers[level] ~= nil and isAliveAndCanFight(entityUuid)
        else
            okToAdd = level and Brawlers[level] ~= nil and Brawlers[level][entityUuid] == nil and isAliveAndCanFight(entityUuid)
        end
        if okToAdd then
            local displayName = getDisplayName(entityUuid)
            debugPrint("Adding Brawler", entityUuid, displayName)
            local brawler = {
                uuid = entityUuid,
                displayName = displayName,
                combatGuid = Osi.CombatGetGuidFor(entityUuid),
                combatGroupId = Osi.GetCombatGroupID(entityUuid),
                isInBrawl = isInBrawl,
                isPaused = Osi.IsInForceTurnBasedMode(entityUuid) == 1,
                archetype = getArchetype(entityUuid),
            }
            local modVars = Ext.Vars.GetModVariables(ModuleUUID)
            modVars.ModifiedHitpoints = modVars.ModifiedHitpoints or {}
            revertHitpoints(entityUuid)
            modifyHitpoints(entityUuid)
            if Osi.IsPlayer(entityUuid) == 0 then
                -- brawler.originalCanJoinCombat = Osi.CanJoinCombat(entityUuid)
                Osi.SetCanJoinCombat(entityUuid, 0)
                -- thank u lunisole/ghostboats
                Osi.PROC_SelfHealing_Disable(entityUuid)
            elseif Players[entityUuid] then
                -- brawler.originalCanJoinCombat = 1
                setPlayerRunToSprint(entityUuid)
                Osi.SetCanJoinCombat(entityUuid, 0)
            end
            Brawlers[level][entityUuid] = brawler
            if isInBrawl and PulseActionTimers[entityUuid] == nil and Osi.IsInForceTurnBasedMode(Osi.GetHostCharacter()) == 0 then
                startPulseAction(brawler)
            end
        end
    end
end

-- NB: This should never be the first thing that happens (brawl should always kick off with an action)
function repositionRelativeToTarget(brawlerUuid, targetUuid)
    local archetype = Osi.GetActiveArchetype(brawlerUuid)
    local distanceToTarget = Osi.GetDistanceTo(brawlerUuid, targetUuid)
    if archetype == "melee" then
        if distanceToTarget > MELEE_RANGE then
            Osi.FlushOsirisQueue(brawlerUuid)
            Osi.CharacterMoveTo(brawlerUuid, targetUuid, getMovementSpeed(brawlerUuid), "")
        else
            holdPosition(brawlerUuid)
        end
    else
        debugPrint("misc bucket reposition", brawlerUuid, getDisplayName(brawlerUuid))
        if distanceToTarget <= MELEE_RANGE then
            holdPosition(brawlerUuid)
        elseif distanceToTarget < RANGED_RANGE_MIN then
            moveToDistanceFromTarget(brawlerUuid, targetUuid, RANGED_RANGE_SWEETSPOT)
        elseif distanceToTarget < RANGED_RANGE_MAX then
            holdPosition(brawlerUuid)
        else
            moveToDistanceFromTarget(brawlerUuid, targetUuid, RANGED_RANGE_SWEETSPOT)
        end
    end
end

function removeBrawler(level, entityUuid)
    local combatGuid = nil
    if Brawlers[level] ~= nil then
        for brawlerUuid, brawler in pairs(Brawlers[level]) do
            if brawler.targetUuid == entityUuid then
                brawler.targetUuid = nil
                brawler.lockedOnTarget = nil
                Osi.PurgeOsirisQueue(brawlerUuid, 1)
                Osi.FlushOsirisQueue(brawlerUuid)
            end
        end
        if Brawlers[level][entityUuid] then
            stopPulseAction(Brawlers[level][entityUuid])
            Brawlers[level][entityUuid] = nil
        end
        Osi.SetCanJoinCombat(entityUuid, 1)
        if Osi.IsPartyMember(entityUuid, 1) == 0 then
            revertHitpoints(entityUuid)
        else
            PlayerCurrentTarget[entityUuid] = nil
            PlayerMarkedTarget[entityUuid] = nil
            IsAttackingOrBeingAttackedByPlayer[entityUuid] = nil
        end
    end
end

function stopBrawlFizzler(level)
    if BrawlFizzler[level] ~= nil then
        -- debugPrint("Something happened, stopping brawl fizzler...")
        Ext.Timer.Cancel(BrawlFizzler[level])
        BrawlFizzler[level] = nil
    end
end

function endBrawl(level)
    if Brawlers[level] then
        for brawlerUuid, brawler in pairs(Brawlers[level]) do
            removeBrawler(level, brawlerUuid)
        end
        debugPrint("Ended brawl")
        debugDump(Brawlers[level])
    end
    for playerUuid, player in pairs(Players) do
        if player.isPaused then
            Osi.ForceTurnBasedMode(playerUuid, 0)
            break
        end
    end
    resetPlayersMovementSpeed()
    ActiveCombatGroups = {}
    Brawlers[level] = {}
    stopBrawlFizzler(level)
end

function startBrawlFizzler(level)
    stopBrawlFizzler(level)
    debugPrint("Starting BrawlFizzler", level)
    BrawlFizzler[level] = Ext.Timer.WaitFor(BRAWL_FIZZLER_TIMEOUT, function ()
        debugPrint("Brawl fizzled", BRAWL_FIZZLER_TIMEOUT)
        endBrawl(level)
    end)
end

-- Enemies are pugnacious jerks and looking for a fight >:(
function checkForBrawlToJoin(brawler)
    local closestPlayerUuid, closestDistance = Osi.GetClosestAlivePlayer(brawler.uuid)
    if closestPlayerUuid ~= nil and closestDistance ~= nil and closestDistance < ENTER_COMBAT_RANGE then
        debugPrint("Closest alive player to", brawler.uuid, brawler.displayName, "is", closestPlayerUuid, closestDistance)
        addBrawler(closestPlayerUuid)
        for playerUuid, player in pairs(Players) do
            if playerUuid ~= closestPlayerUuid then
                local distanceTo = Osi.GetDistanceTo(brawler.uuid, playerUuid)
                if distanceTo < ENTER_COMBAT_RANGE then
                    addBrawler(playerUuid)
                end
            end
        end
        local level = Osi.GetRegion(brawler.uuid)
        if level and BrawlFizzler[level] == nil then
            startBrawlFizzler(level)
        end
        startPulseAction(brawler)
    end
end

function addNearbyToBrawlers(entityUuid, nearbyRadius, combatGuid, replaceExistingBrawler)
    for _, nearby in ipairs(getNearby(entityUuid, nearbyRadius)) do
        if nearby.Entity.IsCharacter and isAliveAndCanFight(nearby.Guid) then
            if combatGuid == nil or Osi.CombatGetGuidFor(nearby.Guid) == combatGuid then
                addBrawler(nearby.Guid, true, replaceExistingBrawler)
            else
                addBrawler(nearby.Guid, false, replaceExistingBrawler)
            end
        end
    end
end

function addNearbyEnemiesToBrawlers(entityUuid, nearbyRadius)
    for _, nearby in ipairs(getNearby(entityUuid, nearbyRadius)) do
        if nearby.Entity.IsCharacter and isAliveAndCanFight(nearby.Guid) and isPugnacious(nearby.Guid) then
            addBrawler(nearby.Guid, false, false)
        end
    end
end

function stopPulseAddNearby(uuid)
    debugPrint("stopPulseAddNearby", uuid, getDisplayName(uuid))
    if PulseAddNearbyTimers[uuid] ~= nil then
        Ext.Timer.Cancel(PulseAddNearbyTimers[uuid])
        PulseAddNearbyTimers[uuid] = nil
    end
end

function pulseAddNearby(uuid)
    addNearbyEnemiesToBrawlers(uuid, 30)
end

function startPulseAddNearby(uuid)
    debugPrint("startPulseAddNearby", uuid, getDisplayName(uuid))
    if PulseAddNearbyTimers[uuid] == nil then
        PulseAddNearbyTimers[uuid] = Ext.Timer.WaitFor(0, function ()
            if not isToT() then
                pulseAddNearby(uuid)
            end
        end, 7500)
    end
end

function stopPulseReposition(level)
    debugPrint("stopPulseReposition", level)
    if PulseRepositionTimers[level] ~= nil then
        Ext.Timer.Cancel(PulseRepositionTimers[level])
        PulseRepositionTimers[level] = nil
    end
end

-- Reposition the NPC relative to the player.  This is the only place that NPCs should enter the brawl.
function pulseReposition(level, skipCompanions)
    checkForDownedOrDeadPlayers()
    if Brawlers[level] then
        for brawlerUuid, brawler in pairs(Brawlers[level]) do
            if not IS_TRAINING_DUMMY[brawlerUuid] then
                if isAliveAndCanFight(brawlerUuid) then
                    -- Enemy units are actively looking for a fight and will attack if you get too close to them
                    if isPugnacious(brawlerUuid) then
                        if brawler.isInBrawl and brawler.targetUuid ~= nil and isAliveAndCanFight(brawler.targetUuid) then
                            debugPrint("Repositioning", brawler.displayName, brawlerUuid, "->", brawler.targetUuid)
                            -- repositionRelativeToTarget(brawlerUuid, brawler.targetUuid)
                            local playerUuid, closestDistance = Osi.GetClosestAlivePlayer(brawlerUuid)
                            if closestDistance > 2*ENTER_COMBAT_RANGE then
                                debugPrint("Too far away, removing brawler", brawlerUuid, getDisplayName(brawlerUuid))
                                removeBrawler(level, brawlerUuid)
                            end
                        else
                            debugPrint("Checking for a brawl to join", brawler.displayName, brawlerUuid)
                            checkForBrawlToJoin(brawler)
                        end
                    -- Player, ally, and neutral units are not actively looking for a fight
                    -- - Companions and allies use the same logic
                    -- - Neutrals just chilling
                    elseif not skipCompanions and areAnyPlayersBrawling() and isPlayerOrAlly(brawlerUuid) and not brawler.isPaused then
                        -- debugPrint("Player or ally", brawlerUuid, Osi.GetHitpoints(brawlerUuid))
                        if Players[brawlerUuid] and (isPlayerControllingDirectly(brawlerUuid) and not FullAuto) then
                            debugPrint("Player is controlling directly: do not take action!")
                            debugDump(brawler)
                            stopPulseAction(brawler, true)
                        else
                            if not brawler.isInBrawl then
                                if Osi.IsPlayer(brawlerUuid) == 0 or CompanionAIEnabled then
                                    -- debugPrint("Not in brawl, starting pulse action for", brawler.displayName)
                                    -- shouldDelay?
                                    startPulseAction(brawler)
                                end
                            elseif isBrawlingWithValidTarget(brawler) and Osi.IsPlayer(brawlerUuid) == 1 and CompanionAIEnabled then
                                holdPosition(brawlerUuid)
                                -- repositionRelativeToTarget(brawlerUuid, brawler.targetUuid)
                            end
                        end
                    end
                elseif Osi.IsDead(brawlerUuid) == 1 or isDowned(brawlerUuid) then
                    Osi.PurgeOsirisQueue(brawlerUuid, 1)
                    Osi.FlushOsirisQueue(brawlerUuid)
                    Osi.LieOnGround(brawlerUuid)
                end
            end
        end
    end
end

-- Reposition if needed every REPOSITION_INTERVAL ms
function startPulseReposition(level, skipCompanions)
    if PulseRepositionTimers[level] == nil then
        debugPrint("startPulseReposition", level, skipCompanions)
        PulseRepositionTimers[level] = Ext.Timer.WaitFor(0, function ()
            pulseReposition(level, skipCompanions)
        end, REPOSITION_INTERVAL)
    end
end

function checkForEndOfBrawl(level)
    local numEnemiesRemaining = getNumEnemiesRemaining(level)
    debugPrint("Number of enemies remaining:", numEnemiesRemaining)
    if numEnemiesRemaining == 0 then
        endBrawl(level)
    end
end

function setupPlayer(guid)
    local uuid = Osi.GetUUID(guid)
    if uuid then
        if not Players then
            Players = {}
        end
        Players[uuid] = {
            uuid = uuid,
            guid = guid,
            displayName = getDisplayName(uuid),
            userId = Osi.GetReservedUserID(uuid),
        }
        Osi.SetCanJoinCombat(uuid, 1)
    end
end

function resetPlayers()
    Players = {}
    for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
        setupPlayer(player[1])
    end
end

function setMaxPartySize()
    Osi.SetMaxPartySizeOverride(MaxPartySize)
	Osi.PROC_CheckPartyFull()
end

function setIsControllingDirectly()
    if Players ~= nil and next(Players) ~= nil then
        for playerUuid, player in pairs(Players) do
            player.isControllingDirectly = false
        end
        local entities = Ext.Entity.GetAllEntitiesWithComponent("ClientControl")
        for _, entity in ipairs(entities) do
            -- New player (client) just joined: they might not be in the Players table yet
            if Players[entity.Uuid.EntityUuid] == nil then
                resetPlayers()
            end
        end
        for _, entity in ipairs(entities) do
            Players[entity.Uuid.EntityUuid].isControllingDirectly = true
        end
    end
end

function stopAllPulseAddNearbyTimers()
    for _, timer in pairs(PulseAddNearbyTimers) do
        Ext.Timer.Cancel(timer)
    end
end

function stopAllPulseRepositionTimers()
    for level, timer in pairs(PulseRepositionTimers) do
        endBrawl(level)
        Ext.Timer.Cancel(timer)
    end
end

function stopAllPulseActionTimers()
    for uuid, timer in pairs(PulseActionTimers) do
        Ext.Timer.Cancel(timer)
    end
end

function stopAllBrawlFizzlers()
    for level, timer in pairs(BrawlFizzler) do
        endBrawl(level)
        Ext.Timer.Cancel(timer)
    end
end

function cleanupAll()
    stopAllPulseAddNearbyTimers()
    stopAllPulseRepositionTimers()
    stopAllPulseActionTimers()
    stopAllBrawlFizzlers()
    local hostCharacter = Osi.GetHostCharacter()
    if hostCharacter then
        local level = Osi.GetRegion(hostCharacter)
        if level then
            endBrawl(level)
        end
    end
    revertAllModifiedHitpoints()
    resetSpellData()
end

function allEnterFTB()
    for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
        local uuid = Osi.GetUUID(player[1])
        Osi.ForceTurnBasedMode(uuid, 1)
    end
end

function cancelQueuedMovement(uuid)
    if MovementQueue[uuid] ~= nil and Osi.IsInForceTurnBasedMode(uuid) == 1 then
        MovementQueue[uuid] = nil
    end
end

function unlock(entity)
    if isLocked(entity) then
        entity.TurnBased.IsInCombat_M = true
        entity:Replicate("TurnBased")
        local uuid = entity.Uuid.EntityUuid
        FTBLockedIn[uuid] = false
        if MovementQueue[uuid] then
            if ActionResourcesListeners[uuid] ~= nil then
                Ext.Entity.Unsubscribe(ActionResourcesListeners[uuid])
                ActionResourcesListeners[uuid] = nil
            end
            local moveTo = MovementQueue[uuid]
            Osi.CharacterMoveToPosition(uuid, moveTo[1], moveTo[2], moveTo[3], getMovementSpeed(uuid), "")
            MovementQueue[uuid] = nil
        end
    end
end

function allExitFTB()
    for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
        local uuid = Osi.GetUUID(player[1])
        unlock(Ext.Entity.Get(uuid))
        Osi.ForceTurnBasedMode(uuid, 0)
        stopTruePause(uuid)
    end
end

function lock(entity)
    entity.TurnBased.IsInCombat_M = false
    FTBLockedIn[entity.Uuid.EntityUuid] = true
end

function midActionLock(entity)
    local spellCastState = entity.SpellCastIsCasting.Cast.SpellCastState
    if spellCastState.Targets then
        local target = spellCastState.Targets[1]
        if target and (target.Position or target.Target) then
            lock(entity)
            MovementQueue[entity.Uuid.EntityUuid] = nil
        end
    end
end

function enqueueMovement(entity)
    local uuid = entity.Uuid.EntityUuid
    if uuid and isInFTB(entity) and (not isLocked(entity) or MovementQueue[uuid]) then
        if LastClickPosition[uuid] and LastClickPosition[uuid].position then
            lock(entity)
            local position = LastClickPosition[uuid].position
            MovementQueue[uuid] = {position[1], position[2], position[3]}
        end
    end
end

function startTruePause(entityUuid)
    -- eoc::ActionResourcesComponent: Replicated
    -- eoc::spell_cast::TargetsChangedEventOneFrameComponent: Created
    -- eoc::spell_cast::PreviewEndEventOneFrameComponent: Created
    -- eoc::TurnBasedComponent: Replicated (all characters)
    -- movement only triggers ActionResources
    --      only pay attention to this if it doesn't occur after a spellcastmovement
    -- move-then-act triggers SpellCastMovement, (TurnBased?), ActionResources
    --      if SpellCastMovement triggered, then ignore the next action resources trigger
    -- act (incl. jump) triggers SpellCastMovement, (TurnBased?)
    if TruePause and Osi.IsPartyMember(entityUuid, 1) == 1 then
        if SpellCastMovementListeners[entityUuid] == nil then
            local entity = Ext.Entity.Get(entityUuid)
            TurnBasedListeners[entityUuid] = Ext.Entity.Subscribe("TurnBased", function (caster, _, _)
                if caster and caster.TurnBased then
                    FTBLockedIn[entityUuid] = caster.TurnBased.RequestedEndTurn
                end
                if isFTBAllLockedIn() then
                    debugPrint("All locked in, auto-exiting FTB...")
                    allExitFTB()
                end
            end, entity)
            ActionResourcesListeners[entityUuid] = Ext.Entity.Subscribe("ActionResources", function (caster, _, _)
                enqueueMovement(caster)
            end, entity)
            -- NB: can specify only the specific cast entity?
            SpellCastMovementListeners[entityUuid] = Ext.Entity.OnCreateDeferred("SpellCastMovement", function (cast, _, _)
                local caster = cast.SpellCastState.Caster
                if caster.Uuid.EntityUuid == entityUuid then
                    if ActionResourcesListeners[entityUuid] ~= nil then
                        Ext.Entity.Unsubscribe(ActionResourcesListeners[entityUuid])
                        ActionResourcesListeners[entityUuid] = nil
                    end
                    if isInFTB(caster) and isActionFinalized(caster) then
                        midActionLock(caster)
                    end
                end
            end)
        end
    end
end

function stopTruePause(entityUuid)
    if Osi.IsPartyMember(entityUuid, 1) == 1 then
        if ActionResourcesListeners[entityUuid] ~= nil then
            Ext.Entity.Unsubscribe(ActionResourcesListeners[entityUuid])
            ActionResourcesListeners[entityUuid] = nil
        end
        if TurnBasedListeners[entityUuid] ~= nil then
            Ext.Entity.Unsubscribe(TurnBasedListeners[entityUuid])
            TurnBasedListeners[entityUuid] = nil
        end
        if SpellCastMovementListeners[entityUuid] ~= nil then
            Ext.Entity.Unsubscribe(SpellCastMovementListeners[entityUuid])
            SpellCastMovementListeners[entityUuid] = nil
        end
    end
end

function checkTruePauseParty()
    if TruePause then
        for uuid, _ in pairs(Players) do
            if Osi.IsInForceTurnBasedMode(uuid) == 1 then
                startTruePause(uuid)
            else
                stopTruePause(uuid)
            end
        end
    else
        for uuid, _ in pairs(Players) do
            stopTruePause(uuid)
            unlock(Ext.Entity.Get(uuid))
        end
    end
end

function onCombatStarted(combatGuid)
    debugPrint("CombatStarted", combatGuid)
    for playerUuid, player in pairs(Players) do
        addBrawler(playerUuid, true)
    end
    debugDump(Brawlers)
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
        debugDump(Brawlers)
        if not isToT() then
            ENTER_COMBAT_RANGE = 20
            startBrawlFizzler(level)
            Ext.Timer.WaitFor(500, function ()
                addNearbyToBrawlers(Osi.GetHostCharacter(), NEARBY_RADIUS, combatGuid)
                Ext.Timer.WaitFor(1500, function ()
                    if Osi.CombatIsActive(combatGuid) then
                        Osi.EndCombat(combatGuid)
                    end
                end)
            end)
        else
            ENTER_COMBAT_RANGE = 150
            startToTTimers()
        end
    end
end

function initBrawlers(level)
    Brawlers[level] = {}
    for playerUuid, player in pairs(Players) do
        if player.isControllingDirectly then
            startPulseAddNearby(playerUuid)
        end
        if Osi.IsInCombat(playerUuid) == 1 then
            onCombatStarted(Osi.CombatGetGuidFor(playerUuid))
            break
        end
    end
    startPulseReposition(level)
end

function onStarted(level)
    debugPrint("onStarted")
    resetSpellData()
    SpellTable = buildSpellTable()
    setMaxPartySize()
    resetPlayers()
    setIsControllingDirectly()
    setMovementSpeedThresholds()
    resetPlayersMovementSpeed()
    setupPartyMembersHitpoints()
    initBrawlers(level)
    checkTruePauseParty()
    debugDump(Players)
    Ext.ServerNet.BroadcastMessage("Started", level)
end

function onResetCompleted()
    debugPrint("ResetCompleted")
    -- Printer:Start()
    -- SpellPrinter:Start()
    onStarted(Osi.GetRegion(Osi.GetHostCharacter()))
end

-- New user joined (multiplayer)
function onUserReservedFor(entity, _, _)
    setIsControllingDirectly()
    local entityUuid = entity.Uuid.EntityUuid
    if Players and Players[entityUuid] then
        local userId = entity.UserReservedFor.UserID
        Players[entityUuid].userId = entity.UserReservedFor.UserID
    end
end

function onLevelGameplayStarted(level, _)
    debugPrint("LevelGameplayStarted", level)
    onStarted(level)
end

function stopToTTimers()
    if ToTRoundTimer ~= nil then
        Ext.Timer.Cancel(ToTRoundTimer)
        ToTRoundTimer = nil
    end
    if ToTTimer ~= nil then
        Ext.Timer.Cancel(ToTTimer)
        ToTTimer = nil
    end
end

function startToTTimers()
    debugPrint("startToTTimers")
    stopToTTimers()
    if not Mods.ToT.Player.InCamp() then
        ToTRoundTimer = Ext.Timer.WaitFor(6000, function ()
            if Mods.ToT.PersistentVars.Scenario and Mods.ToT.PersistentVars.Scenario.Round < #Mods.ToT.PersistentVars.Scenario.Timeline then
                debugPrint("Moving ToT forward")
                Mods.ToT.Scenario.ForwardCombat()
                Ext.Timer.WaitFor(1500, function ()
                    addNearbyToBrawlers(Osi.GetHostCharacter(), 150)
                end)
            end
            startToTTimers()
        end)
        if Mods.ToT.PersistentVars.Scenario then
            local isPrepRound = (Mods.ToT.PersistentVars.Scenario.Round == 0) and (next(Mods.ToT.PersistentVars.Scenario.SpawnedEnemies) == nil)
            if isPrepRound then
                ToTTimer = Ext.Timer.WaitFor(0, function ()
                    debugPrint("adding nearby...")
                    addNearbyToBrawlers(Osi.GetHostCharacter(), 150)
                end, 8500)
            end
        end
    end
end

function onCombatRoundStarted(combatGuid, round)
    debugPrint("CombatRoundStarted", combatGuid, round)
    if not isToT() then
        ENTER_COMBAT_RANGE = 20
        onCombatStarted(combatGuid)
    else
        startToTTimers()
    end
end

function onCombatEnded(combatGuid)
    debugPrint("CombatEnded", combatGuid)
end

function onEnteredCombat(entityGuid, combatGuid)
    debugPrint("EnteredCombat", entityGuid, combatGuid)
    addBrawler(Osi.GetUUID(entityGuid), true)
end

function onEnteredForceTurnBased(entityGuid)
    local entityUuid = Osi.GetUUID(entityGuid)
    local level = Osi.GetRegion(entityGuid)
    if level and entityUuid and Players and Players[entityUuid] then
        debugPrint("EnteredForceTurnBased", entityGuid)
        if Players[entityUuid].isFreshSummon then
            Players[entityUuid].isFreshSummon = false
            return Osi.ForceTurnBasedMode(entityUuid, 0)
        end
        if AwaitingTarget[entityUuid] then
            setAwaitingTarget(entityUuid, false)
        end
        stopCountdownTimer(entityUuid)
        if Brawlers[level] and Brawlers[level][entityUuid] then
            Brawlers[level][entityUuid].isInBrawl = false
        end
        stopPulseAddNearby(entityUuid)
        stopPulseReposition(level)
        stopBrawlFizzler(level)
        if isToT() then
            stopToTTimers()
        end
        startTruePause(entityUuid)
        if Brawlers[level] then
            for brawlerUuid, brawler in pairs(Brawlers[level]) do
                if brawlerUuid ~= entityUuid and not Brawlers[level][brawlerUuid].isPaused then
                    Osi.PurgeOsirisQueue(brawlerUuid, 1)
                    Osi.FlushOsirisQueue(brawlerUuid)
                    stopPulseAction(brawler, true)
                    if Players[brawlerUuid] then
                        Brawlers[level][brawlerUuid].isPaused = true
                        Osi.ForceTurnBasedMode(brawlerUuid, 1)
                    end
                end
            end
        end
    end
end

function onLeftForceTurnBased(entityGuid)
    local entityUuid = Osi.GetUUID(entityGuid)
    local level = Osi.GetRegion(entityGuid)
    if level and entityUuid and Players and Players[entityUuid] then
        debugPrint("LeftForceTurnBased", entityGuid)
        if Players[entityUuid].isFreshSummon then
            Players[entityUuid].isFreshSummon = false
        end
        resumeCountdownTimer(entityUuid)
        if FTBLockedIn[entityUuid] then
            FTBLockedIn[entityUuid] = nil
        end
        if Brawlers[level] and Brawlers[level][entityUuid] then
            Brawlers[level][entityUuid].isInBrawl = true
            if isPlayerControllingDirectly(entityUuid) then
                startPulseAddNearby(entityUuid)
            end
        end
        startPulseReposition(level, true)
        Ext.Timer.WaitFor(1000, function ()
            stopPulseReposition(level)
            startPulseReposition(level)
        end)
        if areAnyPlayersBrawling() then
            startBrawlFizzler(level)
            if isToT() then
                startToTTimers()
            end
            if Brawlers[level] then
                for brawlerUuid, brawler in pairs(Brawlers[level]) do
                    if Players[brawlerUuid] then
                        if not isPlayerControllingDirectly(brawlerUuid) then
                            Ext.Timer.WaitFor(2000, function ()
                                Osi.FlushOsirisQueue(brawlerUuid)
                                startPulseAction(brawler)
                            end)
                        end
                        Brawlers[level][brawlerUuid].isPaused = false
                        if brawlerUuid ~= entityUuid then
                            Osi.ForceTurnBasedMode(brawlerUuid, 0)
                        end
                    else
                        startPulseAction(brawler)
                    end
                end
            end
        end
    end
end

function onTurnEnded(entityGuid)
    -- NB: how's this work for the "environmental turn"?
    debugPrint("TurnEnded", entityGuid)
end

function onDied(entityGuid)
    debugPrint("Died", entityGuid)
    local level = Osi.GetRegion(entityGuid)
    local entityUuid = Osi.GetUUID(entityGuid)
    if level ~= nil and entityUuid ~= nil and Brawlers[level] ~= nil and Brawlers[level][entityUuid] ~= nil then
        -- Sometimes units don't appear dead when killed out-of-combat...
        -- this at least makes them lie prone (and dead-appearing units still appear dead)
        Ext.Timer.WaitFor(LIE_ON_GROUND_TIMEOUT, function ()
            debugPrint("LieOnGround", entityUuid)
            Osi.PurgeOsirisQueue(entityUuid, 1)
            Osi.FlushOsirisQueue(entityUuid)
            Osi.LieOnGround(entityUuid)
        end)
        removeBrawler(level, entityUuid)
        checkForEndOfBrawl(level)
    end
end

-- NB: entity.ClientControl does NOT get reliably updated immediately when this fires
function onGainedControl(targetGuid)
    debugPrint("GainedControl", targetGuid)
    local targetUuid = Osi.GetUUID(targetGuid)
    if targetUuid ~= nil then
        if targetUuid == Osi.GetHostCharacter() then
            local modVars = Ext.Vars.GetModVariables(ModuleUUID)
            local partyArchetypes = modVars.PartyArchetypes
            if partyArchetypes == nil then
                partyArchetypes = {}
                modVars.PartyArchetypes = partyArchetypes
            end
            local archetype = ""
            if partyArchetypes[targetUuid] ~= nil then
                archetype = partyArchetypes[targetUuid]
            end
            local isValidArchetype = false
            for _, validArchetype in ipairs(PLAYER_ARCHETYPES) do
                if archetype == validArchetype then
                    isValidArchetype = true
                    break
                end
            end
            if MCM then
                MCM.Set("active_character_archetype", isValidArchetype and archetype or "")
            end
        end
        Osi.PurgeOsirisQueue(targetUuid, 1)
        Osi.FlushOsirisQueue(targetUuid)
        local targetUserId = Osi.GetReservedUserID(targetUuid)
        if Players[targetUuid] ~= nil and targetUserId ~= nil then
            Players[targetUuid].isControllingDirectly = true
            startPulseAddNearby(targetUuid)
            local level = Osi.GetRegion(targetUuid)
            for playerUuid, player in pairs(Players) do
                if player.userId == targetUserId and playerUuid ~= targetUuid then
                    player.isControllingDirectly = false
                    if level and Brawlers[level] and Brawlers[level][playerUuid] and Brawlers[level][playerUuid].isInBrawl then
                        stopPulseAddNearby(playerUuid)
                        startPulseAction(Brawlers[level][playerUuid])
                    end
                end
            end
            if level and Brawlers[level] and Brawlers[level][targetUuid] and not FullAuto then
                stopPulseAction(Brawlers[level][targetUuid], true)
            end
            debugDump(Players)
            Ext.ServerNet.PostMessageToUser(targetUserId, "GainedControl", targetUuid)
        end
    end
end

function onCharacterJoinedParty(character)
    debugPrint("CharacterJoinedParty", character)
    local uuid = Osi.GetUUID(character)
    if uuid then
        if Players and not Players[uuid] then
            setupPlayer(uuid)
            setupPartyMembersHitpoints()
        end
        if areAnyPlayersBrawling() then
            addBrawler(uuid, true)
        end
        if Osi.IsSummon(uuid) == 1 then
            Players[uuid].isFreshSummon = true
        end
    end
end

function onCharacterLeftParty(character)
    debugPrint("CharacterLeftParty", character)
    local uuid = Osi.GetUUID(character)
    if uuid then
        if Players and Players[uuid] then
            Players[uuid] = nil
        end
        local level = Osi.GetRegion(uuid)
        if Brawlers and Brawlers[level] and Brawlers[level][uuid] then
            Brawlers[level][uuid] = nil
        end
    end
end

function onDownedChanged(character, isDowned)
    local entityUuid = Osi.GetUUID(character)
    debugPrint("DownedChanged", character, isDowned, entityUuid)
    local player = Players[entityUuid]
    local level = Osi.GetRegion(entityUuid)
    if player then
        if isDowned == 1 and AutoPauseOnDowned and player.isControllingDirectly then
            if Brawlers[level] and Brawlers[level][entityUuid] and not Brawlers[level][entityUuid].isPaused then
                Osi.ForceTurnBasedMode(entityUuid, 1)
            end
        end
        if isDowned == 0 then
            player.isBeingHelped = false
        end
    end
end

function onAttackedBy(defenderGuid, attackerGuid, attacker2, damageType, damageAmount, damageCause, storyActionID)
    debugPrint("AttackedBy", defenderGuid, attackerGuid, attacker2, damageType, damageAmount, damageCause, storyActionID)
    local attackerUuid = Osi.GetUUID(attackerGuid)
    local defenderUuid = Osi.GetUUID(defenderGuid)
    if attackerUuid ~= nil and defenderUuid ~= nil and Osi.IsCharacter(attackerUuid) == 1 and Osi.IsCharacter(defenderUuid) == 1 then
        if isToT() then
            addBrawler(attackerUuid, true)
            addBrawler(defenderUuid, true)
        end
        if Osi.IsPlayer(attackerUuid) == 1 then
            PlayerCurrentTarget[attackerUuid] = defenderUuid
            if Osi.IsPlayer(defenderUuid) == 0 and damageAmount > 0 then
                IsAttackingOrBeingAttackedByPlayer[defenderUuid] = attackerUuid
            end
            -- NB: is this needed?
            if isToT() then
                -- addNearbyToBrawlers(attackerUuid, 30, nil, true)
                addNearbyToBrawlers(attackerUuid, 30)
            end
        end
        if Osi.IsPlayer(defenderUuid) == 1 then
            if Osi.IsPlayer(attackerUuid) == 0 and damageAmount > 0 then
                IsAttackingOrBeingAttackedByPlayer[attackerUuid] = defenderUuid
            end
            -- NB: is this needed?
            if isToT() then
                -- addNearbyToBrawlers(defenderUuid, 30, nil, true)
                addNearbyToBrawlers(defenderUuid, 30)
            end
        end
        startBrawlFizzler(Osi.GetRegion(attackerUuid))
    end
end

function doLocalResourceAccounting(uuid, spellName)
    debugPrint("doLocalResourceAccounting", uuid, spellName)
    if ActionsInProgress[uuid] then
        local foundActionInProgress = false
        local actionsInProgressIndex = nil
        for i, actionInProgress in ipairs(ActionsInProgress[uuid]) do
            if actionInProgress == spellName then
                foundActionInProgress = true
                actionsInProgressIndex = i
                break
            end
        end
        if foundActionInProgress then
            for i = actionsInProgressIndex, 1, -1 do
                debugPrint("remove action in progress", i, getDisplayName(uuid), ActionsInProgress[uuid])
                table.remove(ActionsInProgress[uuid], i)
            end
            return true
        end
    end
    return false
end

function onCastedSpell(caster, spellName, spellType, spellElement, storyActionID)
    debugPrint("CastedSpell", caster, spellName, spellType, spellElement, storyActionID)
    local casterUuid = Osi.GetUUID(caster)
    local entity = Ext.Entity.Get(casterUuid)
    debugDump(ActionsInProgress[casterUuid])
    if entity and doLocalResourceAccounting(casterUuid, spellName) then
        local spell = getSpellByName(spellName)
        for costType, costValue in pairs(spell.costs) do
            if costType == "ShortRest" or costType == "LongRest" then
                if costValue then
                    if entity.SpellBook and entity.SpellBook.Spells then
                        for _, spell in ipairs(entity.SpellBook.Spells) do
                            if spell.Id.Prototype == spellName then
                                spell.Charged = false
                                entity:Replicate("SpellBook")
                                break
                            end
                        end
                    end
                end
            elseif costType ~= "ActionPoint" and costType ~= "BonusActionPoint" then
                if costType == "SpellSlot" then
                    if entity.ActionResources and entity.ActionResources.Resources then
                        local spellSlots = entity.ActionResources.Resources[ACTION_RESOURCES[costType]]
                        if spellSlots then
                            for _, spellSlot in ipairs(spellSlots) do
                                if spellSlot.Level >= costValue and spellSlot.Amount > 0 then
                                    spellSlot.Amount = spellSlot.Amount - 1
                                    break
                                end
                            end
                        end
                    end
                else
                    if entity.ActionResources and entity.ActionResources.Resources then
                        local resources = entity.ActionResources.Resources[ACTION_RESOURCES[costType]]
                        if resources then
                            local resource = resources[1] -- NB: always index 1?
                            resource.Amount = resource.Amount - costValue
                        end
                    end
                end
            end
        end
        entity:Replicate("ActionResources")
    end
end

function onDialogStarted(dialog, dialogInstanceId)
    debugPrint("DialogStarted", dialog, dialogInstanceId)
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
        stopPulseReposition(level)
        stopBrawlFizzler(level)
        if Brawlers[level] then
            for brawlerUuid, brawler in pairs(Brawlers[level]) do
                stopPulseAction(brawler, true)
                Osi.PurgeOsirisQueue(brawlerUuid, 1)
                Osi.FlushOsirisQueue(brawlerUuid)
            end
        end
        -- NB: no way to just pause timers, and spinning up a new timer will appear to have a new maximum value...
        -- if dialog == "TUT_Helm_DragonAppears_6ffc2909-a928-4b8b-6901-02d823e68880" then
        --     if CountdownTimer.uuid ~= nil and CountdownTimer.timer ~= nil then
        --         stopCountdownTimer(CountdownTimer.uuid)
        --         questTimerCancel("TUT_Helm_Timer")
        --     end
        -- end
    end
end

function onDialogEnded(dialog, dialogInstanceId)
    debugPrint("DialogEnded", dialog, dialogInstanceId)
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
        startPulseReposition(level)
        if Brawlers[level] then
            for brawlerUuid, brawler in pairs(Brawlers[level]) do
                if brawler.isInBrawl and not isPlayerControllingDirectly(brawlerUuid) then
                    startPulseAction(brawler)
                end
            end
        end
        -- if dialog == "TUT_Helm_DragonAppears_6ffc2909-a928-4b8b-6901-02d823e68880" then
        --     if CountdownTimer.uuid ~= nil and CountdownTimer.timer == nil then
        --         resumeCountdownTimer(CountdownTimer.uuid)
        --         questTimerLaunch("TUT_Helm_Timer", "TUT_Helm_TransponderTimer", CountdownTimer.turnsRemaining)
        --     end
        -- end
    end
end

function onDifficultyChanged(difficulty)
    debugPrint("DifficultyChanged", difficulty)
    setMovementSpeedThresholds()
end

function onTeleportedToCamp(character)
    local entityUuid = Osi.GetUUID(character)
    if entityUuid ~= nil and Brawlers ~= nil then
        for level, brawlersInLevel in pairs(Brawlers) do
            if brawlersInLevel[entityUuid] ~= nil then
                removeBrawler(level, entityUuid)
                checkForEndOfBrawl(level)
            end
        end
    end
end

function onTeleportedFromCamp(character)
    local entityUuid = Osi.GetUUID(character)
    if entityUuid ~= nil and areAnyPlayersBrawling() then
        addBrawler(entityUuid, false)
    end
end

-- thank u focus
function onPROC_Subregion_Entered(characterGuid, _)
    debugPrint("PROC_Subregion_Entered", characterGuid)
    local uuid = Osi.GetUUID(characterGuid)
    local level = Osi.GetRegion(uuid)
    if level and Players and Players[uuid] then
        pulseReposition(level)
    end
end

function onLevelUnloading(level)
    debugPrint("LevelUnloading", level)
    Brawlers[level] = nil
    stopPulseReposition(level)
end

function onObjectTimerFinished(objectGuid, timer)
    debugPrint("ObjectTimerFinished", objectGuid, timer)
    if timer == "TUT_Helm_Timer" then
        nautiloidTransponderCountdownFinished(Osi.GetUUID(objectGuid))
    elseif timer == "HAV_LikesideCombat_CombatRoundTimer" then
        lakesideRitualCountdownFinished(Osi.GetUUID(objectGuid))
    end
end

-- function onSubQuestUpdateUnlocked(character, subQuestID, stateID)
--     debugPrint("SubQuestUpdateUnlocked", character, subQuestID, stateID)
-- end

-- function onQuestUpdateUnlocked(character, topLevelQuestID, stateID)
--     debugPrint("QuestUpdateUnlocked", character, topLevelQuestID, stateID)
-- end

-- function onQuestAccepted(character, questID)
--     debugPrint("QuestAccepted", character, questID)
-- end

-- function onFlagCleared(flag, speaker, dialogInstance)
--     debugPrint("FlagCleared", flag, speaker, dialogInstance)
-- end

-- function onFlagLoadedInPresetEvent(object, flag)
--     debugPrint("FlagLoadedInPresetEvent", object, flag)
-- end

function onFlagSet(flag, speaker, dialogInstance)
    debugPrint("FlagSet", flag, speaker, dialogInstance)
    if flag == "HAV_LiftingTheCurse_State_HalsinInShadowfell_480305fb-7b0b-4267-aab6-0090ddc12322" then
        questTimerLaunch("HAV_LikesideCombat_CombatRoundTimer", "HAV_HalsinPortalTimer", LAKESIDE_RITUAL_COUNTDOWN_TURNS)
        lakesideRitualCountdown(Osi.GetHostCharacter(), LAKESIDE_RITUAL_COUNTDOWN_TURNS)
    elseif flag == "GLO_Halsin_State_PermaDefeated_86bc3df1-08b4-fbc4-b542-6241bcd03df1" then
        questTimerCancel("HAV_LikesideCombat_CombatRoundTimer")
        stopCountdownTimer(Osi.GetHostCharacter())
    elseif flag == "HAV_LiftingTheCurse_Event_HalsinClosesPortal_33aa334a-3127-4be1-ad94-518aa4f24ef4" then
        questTimerCancel("HAV_LikesideCombat_CombatRoundTimer")
        stopCountdownTimer(Osi.GetHostCharacter())
    elseif flag == "TUT_Helm_JoinedMindflayerFight_ec25d7dc-f9d6-47ff-92c9-8921d6e32f54" then
        questTimerLaunch("TUT_Helm_Timer", "TUT_Helm_TransponderTimer", NAUTILOID_TRANSPONDER_COUNTDOWN_TURNS)
        nautiloidTransponderCountdown(Osi.GetHostCharacter(), NAUTILOID_TRANSPONDER_COUNTDOWN_TURNS)
    elseif flag == "TUT_Helm_State_TutorialEnded_55073953-23b9-448c-bee8-4c44d3d67b6b" then
        questTimerCancel("TUT_Helm_Timer")
        stopCountdownTimer(Osi.GetHostCharacter())
    end
end

function stopListeners()
    cleanupAll()
    for _, listener in pairs(Listeners) do
        listener.stop(listener.handle)
    end
end

function startListeners()
    debugPrint("Starting listeners...")
    Listeners.ResetCompleted = {}
    Listeners.ResetCompleted.handle = Ext.Events.ResetCompleted:Subscribe(onResetCompleted)
    Listeners.ResetCompleted.stop = function () Ext.Events.ResetCompleted:Unsubscribe(Listeners.ResetCompleted.handle) end
    Listeners.UserReservedFor = {
        handle = Ext.Entity.Subscribe("UserReservedFor", onUserReservedFor),
        stop = Ext.Entity.Unsubscribe,
    }
    Listeners.LevelGameplayStarted = {
        handle = Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", onLevelGameplayStarted),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.CombatStarted = {
        handle = Ext.Osiris.RegisterListener("CombatStarted", 1, "after", onCombatStarted),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.CombatEnded = {
        handle = Ext.Osiris.RegisterListener("CombatEnded", 1, "after", onCombatEnded),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.CombatRoundStarted = {
        handle = Ext.Osiris.RegisterListener("CombatRoundStarted", 2, "after", onCombatRoundStarted),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.EnteredCombat = {
        handle = Ext.Osiris.RegisterListener("EnteredCombat", 2, "after", onEnteredCombat),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.EnteredForceTurnBased = {
        handle = Ext.Osiris.RegisterListener("EnteredForceTurnBased", 1, "after", onEnteredForceTurnBased),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.LeftForceTurnBased = {
        handle = Ext.Osiris.RegisterListener("LeftForceTurnBased", 1, "after", onLeftForceTurnBased),
        stop = Ext.Osiris.UnregisterListener,
    }
    -- Listeners.TurnEnded = {
    --     handle = Ext.Osiris.RegisterListener("TurnEnded", 1, "after", onTurnEnded),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    Listeners.Died = {
        handle = Ext.Osiris.RegisterListener("Died", 1, "after", onDied),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.GainedControl = {
        handle = Ext.Osiris.RegisterListener("GainedControl", 1, "after", onGainedControl),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.CharacterJoinedParty = {
        handle = Ext.Osiris.RegisterListener("CharacterJoinedParty", 1, "after", onCharacterJoinedParty),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.CharacterLeftParty = {
        handle = Ext.Osiris.RegisterListener("CharacterLeftParty", 1, "after", onCharacterLeftParty),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.DownedChanged = {
        handle = Ext.Osiris.RegisterListener("DownedChanged", 2, "after", onDownedChanged),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.AttackedBy = {
        handle = Ext.Osiris.RegisterListener("AttackedBy", 7, "after", onAttackedBy),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.CastedSpell = {
        handle = Ext.Osiris.RegisterListener("CastedSpell", 5, "after", onCastedSpell),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.DialogStarted = {
        handle = Ext.Osiris.RegisterListener("DialogStarted", 2, "before", onDialogStarted),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.DialogEnded = {
        handle = Ext.Osiris.RegisterListener("DialogEnded", 2, "after", onDialogEnded),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.DifficultyChanged = {
        handle = Ext.Osiris.RegisterListener("DifficultyChanged", 1, "after", onDifficultyChanged),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.TeleportedToCamp = {
        handle = Ext.Osiris.RegisterListener("TeleportedToCamp", 1, "after", onTeleportedToCamp),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.TeleportedFromCamp = {
        handle = Ext.Osiris.RegisterListener("TeleportedFromCamp", 1, "after", onTeleportedFromCamp),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.PROC_Subregion_Entered = {
        handle = Ext.Osiris.RegisterListener("PROC_Subregion_Entered", 2, "after", onPROC_Subregion_Entered),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.LevelUnloading = {
        handle = Ext.Osiris.RegisterListener("LevelUnloading", 1, "after", onLevelUnloading),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.ObjectTimerFinished = {
        handle = Ext.Osiris.RegisterListener("ObjectTimerFinished", 2, "after", onObjectTimerFinished),
        stop = Ext.Osiris.UnregisterListener,
    }
    -- Listeners.SubQuestUpdateUnlocked = {
    --     handle = Ext.Osiris.RegisterListener("SubQuestUpdateUnlocked", 3, "after", onSubQuestUpdateUnlocked),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    -- Listeners.QuestUpdateUnlocked = {
    --     handle = Ext.Osiris.RegisterListener("QuestUpdateUnlocked", 3, "after", onQuestUpdateUnlocked),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    -- Listeners.QuestAccepted = {
    --     handle = Ext.Osiris.RegisterListener("QuestAccepted", 2, "after", onQuestAccepted),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    -- Listeners.FlagCleared = {
    --     handle = Ext.Osiris.RegisterListener("FlagCleared", 3, "after", onFlagCleared),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    -- Listeners.FlagLoadedInPresetEvent = {
    --     handle = Ext.Osiris.RegisterListener("FlagLoadedInPresetEvent", 2, "after", onFlagLoadedInPresetEvent),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    Listeners.FlagSet = {
        handle = Ext.Osiris.RegisterListener("FlagSet", 3, "after", onFlagSet),
        stop = Ext.Osiris.UnregisterListener,
    }
end

function onGameStateChanged(e)
    if e and e.ToState == "UnloadLevel" then
        cleanupAll()
    end
end

function onMCMSettingSaved(payload)
    if payload and payload.modUUID == ModuleUUID and payload.settingId and MCMSettingSaved[payload.settingId] then
        MCMSettingSaved[payload.settingId](payload.value)
    end
end

function onNetMessage(data)
    if NetMessage[data.Channel] then
        NetMessage[data.Channel](data)
    end
end

function onSessionLoaded()
    Ext.Events.NetMessage:Subscribe(onNetMessage)
    if ModEnabled then
        startListeners()
    else
        Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", resetPlayers)
    end
end

Ext.Events.SessionLoaded:Subscribe(onSessionLoaded)
Ext.Events.GameStateChanged:Subscribe(onGameStateChanged)
if MCM then
    Ext.ModEvents.BG3MCM["MCM_Setting_Saved"]:Subscribe(onMCMSettingSaved)
end
