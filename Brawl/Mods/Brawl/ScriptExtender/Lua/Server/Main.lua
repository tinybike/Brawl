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

function lockCompanionsOnTarget(level, targetUuid)
    for uuid, _ in pairs(State.Session.Players) do
        if isAliveAndCanFight(uuid) and (not State.isPlayerControllingDirectly(uuid) or State.Settings.FullAuto) then
            if not State.Session.Brawlers[level][uuid] then
                addBrawler(uuid, true)
            end
            if State.Session.Brawlers[level][uuid] and uuid ~= targetUuid then
                State.Session.Brawlers[level][uuid].targetUuid = targetUuid
                State.Session.Brawlers[level][uuid].lockedOnTarget = true
                debugPrint("Set target to", uuid, getDisplayName(uuid), targetUuid, getDisplayName(targetUuid))
            end
        end
    end
end

function useSpellAndResourcesAtPosition(casterUuid, position, spellName, variant, upcastLevel)
    if not Resources.hasEnoughToCastSpell(casterUuid, spellName, variant, upcastLevel) then
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
    State.Session.ActionsInProgress[casterUuid] = State.Session.ActionsInProgress[casterUuid] or {}
    table.insert(State.Session.ActionsInProgress[casterUuid], spellName)
    Osi.UseSpellAtPosition(casterUuid, spellName, position[1], position[2], position[3])
    return true
end

function useSpellAndResources(casterUuid, targetUuid, spellName, variant, upcastLevel)
    if targetUuid == nil then
        return false
    end
    if not Resources.hasEnoughToCastSpell(casterUuid, spellName, variant, upcastLevel) then
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
    State.Session.ActionsInProgress[casterUuid] = State.Session.ActionsInProgress[casterUuid] or {}
    table.insert(State.Session.ActionsInProgress[casterUuid], spellName)
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
    if State.Session.PlayerMarkedTarget[playerUuid] and not isAliveAndCanFight(State.Session.PlayerMarkedTarget[playerUuid]) then
        State.Session.PlayerMarkedTarget[playerUuid] = nil
    end
    local playerEntity = Ext.Entity.Get(playerUuid)
    local playerPos = playerEntity.Transform.Transform.Translate
    local playerForwardX, playerForwardY, playerForwardZ = getForwardVector(playerUuid)
    local maxTargets = 10
    local topTargets = {}
    local level = Osi.GetRegion(playerUuid)
    if State.Session.Brawlers[level] then
        for brawlerUuid, brawler in pairs(State.Session.Brawlers[level]) do
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
    State.Session.ClosestEnemyBrawlers[playerUuid] = {}
    for i, target in ipairs(topTargets) do
        State.Session.ClosestEnemyBrawlers[playerUuid][i] = target.uuid
    end
    if #State.Session.ClosestEnemyBrawlers[playerUuid] > 0 and State.Session.PlayerMarkedTarget[playerUuid] == nil then
        State.Session.PlayerMarkedTarget[playerUuid] = State.Session.ClosestEnemyBrawlers[playerUuid][1]
    end
    debugPrint("Closest enemy brawlers to player", playerUuid, getDisplayName(playerUuid))
    debugDump(State.Session.ClosestEnemyBrawlers)
    debugPrint("Current target:", State.Session.PlayerMarkedTarget[playerUuid])
    Ext.Timer.WaitFor(3000, function ()
        State.Session.ClosestEnemyBrawlers[playerUuid] = nil
    end)
end

function selectNextEnemyBrawler(playerUuid, isNext)
    local nextTargetIndex = nil
    local nextTargetUuid = nil
    for enemyBrawlerIndex, enemyBrawlerUuid in ipairs(State.Session.ClosestEnemyBrawlers[playerUuid]) do
        if State.Session.PlayerMarkedTarget[playerUuid] == enemyBrawlerUuid then
            debugPrint("found current target", State.Session.PlayerMarkedTarget[playerUuid], enemyBrawlerUuid, enemyBrawlerIndex, State.Session.ClosestEnemyBrawlers[playerUuid][enemyBrawlerIndex])
            if isNext then
                debugPrint("getting NEXT target")
                if enemyBrawlerIndex < #State.Session.ClosestEnemyBrawlers[playerUuid] then
                    nextTargetIndex = enemyBrawlerIndex + 1
                else
                    nextTargetIndex = 1
                end
            else
                debugPrint("getting PREVIOUS target")
                if enemyBrawlerIndex > 1 then
                    nextTargetIndex = enemyBrawlerIndex - 1
                else
                    nextTargetIndex = #State.Session.ClosestEnemyBrawlers[playerUuid]
                end
            end
            debugPrint("target index", nextTargetIndex)
            debugDump(State.Session.ClosestEnemyBrawlers)
            nextTargetUuid = State.Session.ClosestEnemyBrawlers[playerUuid][nextTargetIndex]
            debugPrint("target uuid", nextTargetUuid)
            break
        end
    end
    if nextTargetUuid then
        if State.Session.PlayerMarkedTarget[playerUuid] ~= nil then
            Osi.RemoveStatus(State.Session.PlayerMarkedTarget[playerUuid], "LOW_HAG_MUSHROOM_VFX")
        end
        debugPrint("pinging next target", nextTargetUuid)
        local x, y, z = Osi.GetPosition(nextTargetUuid)
        Osi.RequestPing(x, y, z, nextTargetUuid, playerUuid)
        Osi.ApplyStatus(nextTargetUuid, "LOW_HAG_MUSHROOM_VFX", -1)
        State.Session.PlayerMarkedTarget[playerUuid] = nextTargetUuid
    end
end

function moveToTarget(attackerUuid, targetUuid, spellName)
    local range = getSpellRange(spellName)
    local rangeNumber
    Osi.PurgeOsirisQueue(attackerUuid, 1)
    Osi.FlushOsirisQueue(attackerUuid)
    local attackerCanMove = Osi.CanMove(attackerUuid) == 1
    if range == "MeleeMainWeaponRange" then
        Movement.moveToTargetUuid(attackerUuid, targetUuid)
    elseif range == "RangedMainWeaponRange" then
        rangeNumber = 18
    else
        rangeNumber = tonumber(range)
        local distanceToTarget = Osi.GetDistanceTo(attackerUuid, targetUuid)
        if distanceToTarget > rangeNumber and attackerCanMove then
            debugPrint("moveToTarget distance > range, moving to...")
            Movement.moveToDistanceFromTarget(attackerUuid, targetUuid, rangeNumber)
        end
    end
    local canSeeTarget = Osi.CanSee(attackerUuid, targetUuid) == 1
    if not canSeeTarget and spellName and not string.match(spellName, "^Projectile_MagicMissile") and attackerCanMove then
        debugPrint("moveToTarget can't see target, moving closer")
        Movement.moveToDistanceFromTarget(attackerUuid, targetUuid, targetRadiusNumber or 2)
    end
end

function useSpellOnTarget(attackerUuid, targetUuid, spellName)
    debugPrint("useSpellOnTarget", attackerUuid, targetUuid, spellName, State.Settings.HogwildMode)
    if State.Settings.HogwildMode then
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
    -- if not State.Settings.HogwildMode then
    --     weight = weight - spell.level
    -- end
    if State.Settings.HogwildMode then
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
    if not State.Settings.HogwildMode then
        -- Make sure we're not exceeding the user's specified AI max spell level
        if spell.level > State.Settings.CompanionAIMaxSpellLevel then
            return false
        end
        -- Make sure we have the resources to actually cast what we want to cast
        if not Resources.hasEnoughToCastSpell(uuid, spellName) then
            return false
        end
    end
    -- For defense tactics:
    --  1. Is the target already within range? Then ok to use
    --  2. If the target is out-of-range, can we hit him without moving outside of the perimeter? Then ok to use
    if State.Settings.CompanionTactics == "Defense" then
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
        if not Resources.hasEnoughToCastSpell(uuid, spellName) then
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
            spell = State.Session.SpellTable[spellType][spellName]
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
                spell = State.Session.SpellTable[spellType][spellName]
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
                    if State.Session.SpellTable.Damage[spellName] or State.Session.SpellTable.Control[spellName] then
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
        if not State.hasDirectHeal(brawler.uuid, preparedSpells) then
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
    if State.Settings.CompanionTactics == "Defense" and isPlayerOrAlly(brawler.uuid) then
        closestAlivePlayer = Osi.GetClosestAlivePlayer(brawler.uuid)
    end
    for potentialTargetUuid, _ in pairs(potentialTargets) do
        if brawler.uuid ~= potentialTargetUuid and isVisible(potentialTargetUuid) and isAliveAndCanFight(potentialTargetUuid) then
            local distanceToTarget = Osi.GetDistanceTo(brawler.uuid, potentialTargetUuid)
            local canSeeTarget = Osi.CanSee(brawler.uuid, potentialTargetUuid) == 1
            if (distanceToTarget < 30 and canSeeTarget) or State.Session.ActiveCombatGroups[brawler.combatGroupId] or State.Session.IsAttackingOrBeingAttackedByPlayer[potentialTargetUuid] then
                local isHostile = isHostileTarget(brawler.uuid, potentialTargetUuid)
                if isHostile or State.hasDirectHeal(brawler.uuid, Ext.Entity.Get(brawler.uuid).SpellBookPrepares.PreparedSpells) then
                    local targetHp = Osi.GetHitpoints(potentialTargetUuid)
                    local targetHpPct = Osi.GetHitpointsPercentage(potentialTargetUuid)
                    if not isPlayerOrAlly(brawler.uuid) then
                        weightedTargets[potentialTargetUuid] = getOffenseWeightedTarget(distanceToTarget, targetHp, targetHpPct, canSeeTarget, isHealer, isHostile)
                        State.Session.ActiveCombatGroups[brawler.combatGroupId] = true
                    else
                        if State.Settings.CompanionTactics == "Offense" then
                            weightedTargets[potentialTargetUuid] = getOffenseWeightedTarget(distanceToTarget, targetHp, targetHpPct, canSeeTarget, isHealer, isHostile)
                        elseif State.Settings.CompanionTactics == "Defense" then
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
            wasHealRequested = State.Session.HealRequested[userId]
        end
        if wasHealRequested then
            if State.Session.Brawlers[level] then
                local friendlyTargetUuid = whoNeedsHealing(brawler.uuid, level)
                if friendlyTargetUuid and State.Session.Brawlers[level][friendlyTargetUuid] then
                    debugPrint("actOnFriendlyTarget", brawler.uuid, brawler.displayName, friendlyTargetUuid, getDisplayName(friendlyTargetUuid))
                    if actOnFriendlyTarget(brawler, State.Session.Brawlers[level][friendlyTargetUuid]) then
                        State.Session.HealRequested[userId] = false
                        return true
                    end
                    return false
                end
            end
        end
        -- Attacking
        local weightedTargets = getWeightedTargets(brawler, State.Session.Brawlers[level])
        local targetUuid = decideOnTarget(weightedTargets)
        -- debugDump(weightedTargets)
        -- debugPrint("got target", targetUuid)
        if targetUuid and State.Session.Brawlers[level][targetUuid] then
            local result
            if isHostileTarget(brawler.uuid, targetUuid) then
                result = actOnHostileTarget(brawler, State.Session.Brawlers[level][targetUuid])
                -- debugPrint("result (hostile)", result)
                if result == true then
                    brawler.targetUuid = targetUuid
                end
            else
                result = actOnFriendlyTarget(brawler, State.Session.Brawlers[level][targetUuid])
                -- debugPrint("result (friendly)", result)
            end
            if result == true then
                return true
            end
        end
        -- debugPrint("can't find a target, holding position", brawler.uuid, brawler.displayName)
        Movement.holdPosition(brawler.uuid)
        return false
    end
end

function addPlayersInEnterCombatRangeToBrawlers(brawlerUuid)
    for playerUuid, player in pairs(State.Session.Players) do
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
    if State.Session.PulseActionTimers[brawler.uuid] ~= nil then
        debugPrint("stop pulse action", brawler.displayName, remainInBrawl)
        Ext.Timer.Cancel(State.Session.PulseActionTimers[brawler.uuid])
        State.Session.PulseActionTimers[brawler.uuid] = nil
    end
end

-- Brawlers doing dangerous stuff
function pulseAction(brawler)
    -- Brawler is alive and able to fight: let's go!
    if brawler and brawler.uuid then
        if not brawler.isPaused and isAliveAndCanFight(brawler.uuid) and (not State.isPlayerControllingDirectly(brawler.uuid) or State.Settings.FullAuto) then
            -- NB: if we allow healing spells etc used by companions, roll this code in, instead of special-casing it here...
            if isPlayerOrAlly(brawler.uuid) then
                for playerUuid, player in pairs(State.Session.Players) do
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
            if level and isOnSameLevel(brawler.uuid, brawler.targetUuid) and State.Session.Brawlers[level][brawler.targetUuid] and isAliveAndCanFight(brawler.targetUuid) and isVisible(brawler.targetUuid) then
                if Osi.GetDistanceTo(brawler.uuid, brawler.targetUuid) <= 12 or brawler.lockedOnTarget then
                    debugPrint("Attacking", brawler.displayName, brawler.uuid, "->", getDisplayName(brawler.targetUuid))
                    return actOnHostileTarget(brawler, State.Session.Brawlers[level][brawler.targetUuid])
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
    if Osi.IsPlayer(brawler.uuid) == 1 and not State.Settings.CompanionAIEnabled then
        return false
    end
    if IS_TRAINING_DUMMY[brawler.uuid] then
        return false
    end
    if State.Session.PulseActionTimers[brawler.uuid] == nil then
        brawler.isInBrawl = true
        local noisedActionInterval = math.floor(State.Settings.ActionInterval*(0.7 + math.random()*0.6) + 0.5)
        debugPrint("Starting pulse action", brawler.displayName, brawler.uuid, noisedActionInterval)
        State.Session.PulseActionTimers[brawler.uuid] = Ext.Timer.WaitFor(0, function ()
            -- debugPrint("pulse action", brawler.uuid, brawler.displayName)
            pulseAction(brawler)
        end, noisedActionInterval)
    end
end

function setPlayerRunToSprint(entityUuid)
    local entity = Ext.Entity.Get(entityUuid)
    if entity and entity.ServerCharacter then
        if State.Session.Players[entityUuid].movementSpeedRun == nil then
            State.Session.Players[entityUuid].movementSpeedRun = entity.ServerCharacter.Template.MovementSpeedRun
        end
        entity.ServerCharacter.Template.MovementSpeedRun = entity.ServerCharacter.Template.MovementSpeedSprint
    end
end

function addBrawler(entityUuid, isInBrawl, replaceExistingBrawler)
    if entityUuid ~= nil then
        local level = Osi.GetRegion(entityUuid)
        local okToAdd = false
        if replaceExistingBrawler then
            okToAdd = level and State.Session.Brawlers[level] ~= nil and isAliveAndCanFight(entityUuid)
        else
            okToAdd = level and State.Session.Brawlers[level] ~= nil and State.Session.Brawlers[level][entityUuid] == nil and isAliveAndCanFight(entityUuid)
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
                archetype = State.getArchetype(entityUuid),
            }
            local modVars = Ext.Vars.GetModVariables(ModuleUUID)
            modVars.ModifiedHitpoints = modVars.ModifiedHitpoints or {}
            State.revertHitpoints(entityUuid)
            State.modifyHitpoints(entityUuid)
            if Osi.IsPlayer(entityUuid) == 0 then
                -- brawler.originalCanJoinCombat = Osi.CanJoinCombat(entityUuid)
                Osi.SetCanJoinCombat(entityUuid, 0)
                -- thank u lunisole/ghostboats
                Osi.PROC_SelfHealing_Disable(entityUuid)
            elseif State.Session.Players[entityUuid] then
                -- brawler.originalCanJoinCombat = 1
                setPlayerRunToSprint(entityUuid)
                Osi.SetCanJoinCombat(entityUuid, 0)
            end
            State.Session.Brawlers[level][entityUuid] = brawler
            if isInBrawl and State.Session.PulseActionTimers[entityUuid] == nil and Osi.IsInForceTurnBasedMode(Osi.GetHostCharacter()) == 0 then
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
            Movement.moveToTargetUuid(brawlerUuid, targetUuid, false)
        else
            Movement.holdPosition(brawlerUuid)
        end
    else
        debugPrint("misc bucket reposition", brawlerUuid, getDisplayName(brawlerUuid))
        if distanceToTarget <= MELEE_RANGE then
            Movement.holdPosition(brawlerUuid)
        elseif distanceToTarget < RANGED_RANGE_MIN then
            Movement.moveToDistanceFromTarget(brawlerUuid, targetUuid, RANGED_RANGE_SWEETSPOT)
        elseif distanceToTarget < RANGED_RANGE_MAX then
            Movement.holdPosition(brawlerUuid)
        else
            Movement.moveToDistanceFromTarget(brawlerUuid, targetUuid, RANGED_RANGE_SWEETSPOT)
        end
    end
end

function removeBrawler(level, entityUuid)
    local combatGuid = nil
    if State.Session.Brawlers[level] ~= nil then
        for brawlerUuid, brawler in pairs(State.Session.Brawlers[level]) do
            if brawler.targetUuid == entityUuid then
                brawler.targetUuid = nil
                brawler.lockedOnTarget = nil
                Osi.PurgeOsirisQueue(brawlerUuid, 1)
                Osi.FlushOsirisQueue(brawlerUuid)
            end
        end
        if State.Session.Brawlers[level][entityUuid] then
            stopPulseAction(State.Session.Brawlers[level][entityUuid])
            State.Session.Brawlers[level][entityUuid] = nil
        end
        Osi.SetCanJoinCombat(entityUuid, 1)
        if Osi.IsPartyMember(entityUuid, 1) == 0 then
            State.revertHitpoints(entityUuid)
        else
            State.Session.PlayerCurrentTarget[entityUuid] = nil
            State.Session.PlayerMarkedTarget[entityUuid] = nil
            State.Session.IsAttackingOrBeingAttackedByPlayer[entityUuid] = nil
        end
    end
end

function stopBrawlFizzler(level)
    if State.Session.BrawlFizzler[level] ~= nil then
        -- debugPrint("Something happened, stopping brawl fizzler...")
        Ext.Timer.Cancel(State.Session.BrawlFizzler[level])
        State.Session.BrawlFizzler[level] = nil
    end
end

function endBrawl(level)
    if State.Session.Brawlers[level] then
        for brawlerUuid, brawler in pairs(State.Session.Brawlers[level]) do
            removeBrawler(level, brawlerUuid)
        end
        debugPrint("Ended brawl")
        debugDump(State.Session.Brawlers[level])
    end
    for playerUuid, player in pairs(State.Session.Players) do
        if player.isPaused then
            Osi.ForceTurnBasedMode(playerUuid, 0)
            break
        end
    end
    State.resetPlayersMovementSpeed()
    State.Session.ActiveCombatGroups = {}
    State.Session.Brawlers[level] = {}
    stopBrawlFizzler(level)
end

function startBrawlFizzler(level)
    stopBrawlFizzler(level)
    debugPrint("Starting BrawlFizzler", level)
    State.Session.BrawlFizzler[level] = Ext.Timer.WaitFor(BRAWL_FIZZLER_TIMEOUT, function ()
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
        for playerUuid, player in pairs(State.Session.Players) do
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
    if State.Session.PulseAddNearbyTimers[uuid] ~= nil then
        Ext.Timer.Cancel(State.Session.PulseAddNearbyTimers[uuid])
        State.Session.PulseAddNearbyTimers[uuid] = nil
    end
end

function pulseAddNearby(uuid)
    addNearbyEnemiesToBrawlers(uuid, 30)
end

function startPulseAddNearby(uuid)
    debugPrint("startPulseAddNearby", uuid, getDisplayName(uuid))
    if State.Session.PulseAddNearbyTimers[uuid] == nil then
        State.Session.PulseAddNearbyTimers[uuid] = Ext.Timer.WaitFor(0, function ()
            if not isToT() then
                pulseAddNearby(uuid)
            end
        end, 7500)
    end
end

function stopPulseReposition(level)
    debugPrint("stopPulseReposition", level)
    if State.Session.PulseRepositionTimers[level] ~= nil then
        Ext.Timer.Cancel(State.Session.PulseRepositionTimers[level])
        State.Session.PulseRepositionTimers[level] = nil
    end
end

-- Reposition the NPC relative to the player.  This is the only place that NPCs should enter the brawl.
function pulseReposition(level, skipCompanions)
    State.checkForDownedOrDeadPlayers()
    if State.Session.Brawlers[level] then
        for brawlerUuid, brawler in pairs(State.Session.Brawlers[level]) do
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
                    elseif not skipCompanions and State.areAnyPlayersBrawling() and isPlayerOrAlly(brawlerUuid) and not brawler.isPaused then
                        -- debugPrint("Player or ally", brawlerUuid, Osi.GetHitpoints(brawlerUuid))
                        if State.Session.Players[brawlerUuid] and (State.isPlayerControllingDirectly(brawlerUuid) and not State.Settings.FullAuto) then
                            debugPrint("Player is controlling directly: do not take action!")
                            debugDump(brawler)
                            stopPulseAction(brawler, true)
                        else
                            if not brawler.isInBrawl then
                                if Osi.IsPlayer(brawlerUuid) == 0 or State.Settings.CompanionAIEnabled then
                                    -- debugPrint("Not in brawl, starting pulse action for", brawler.displayName)
                                    -- shouldDelay?
                                    startPulseAction(brawler)
                                end
                            elseif isBrawlingWithValidTarget(brawler) and Osi.IsPlayer(brawlerUuid) == 1 and State.Settings.CompanionAIEnabled then
                                Movement.holdPosition(brawlerUuid)
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
    if State.Session.PulseRepositionTimers[level] == nil then
        debugPrint("startPulseReposition", level, skipCompanions)
        State.Session.PulseRepositionTimers[level] = Ext.Timer.WaitFor(0, function ()
            pulseReposition(level, skipCompanions)
        end, REPOSITION_INTERVAL)
    end
end

function checkForEndOfBrawl(level)
    local numEnemiesRemaining = State.getNumEnemiesRemaining(level)
    debugPrint("Number of enemies remaining:", numEnemiesRemaining)
    if numEnemiesRemaining == 0 then
        endBrawl(level)
    end
end

function stopAllPulseAddNearbyTimers()
    for _, timer in pairs(State.Session.PulseAddNearbyTimers) do
        Ext.Timer.Cancel(timer)
    end
end

function stopAllPulseRepositionTimers()
    for level, timer in pairs(State.Session.PulseRepositionTimers) do
        endBrawl(level)
        Ext.Timer.Cancel(timer)
    end
end

function stopAllPulseActionTimers()
    for uuid, timer in pairs(State.Session.PulseActionTimers) do
        Ext.Timer.Cancel(timer)
    end
end

function stopAllBrawlFizzlers()
    for level, timer in pairs(State.Session.BrawlFizzler) do
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
    State.revertAllModifiedHitpoints()
    State.resetSpellData()
end

function onCombatStarted(combatGuid)
    debugPrint("CombatStarted", combatGuid)
    for playerUuid, player in pairs(State.Session.Players) do
        addBrawler(playerUuid, true)
    end
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
        -- debugDump(State.Session.Brawlers)
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
    State.Session.Brawlers[level] = {}
    for playerUuid, player in pairs(State.Session.Players) do
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
    State.resetSpellData()
    State.buildSpellTable()
    State.setMaxPartySize()
    State.resetPlayers()
    State.setIsControllingDirectly()
    setMovementSpeedThresholds()
    State.resetPlayersMovementSpeed()
    State.setupPartyMembersHitpoints()
    initBrawlers(level)
    Pause.checkTruePauseParty()
    debugDump(State.Session.Players)
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
    State.setIsControllingDirectly()
    local entityUuid = entity.Uuid.EntityUuid
    if State.Session.Players and State.Session.Players[entityUuid] then
        local userId = entity.UserReservedFor.UserID
        State.Session.Players[entityUuid].userId = entity.UserReservedFor.UserID
    end
end

function onLevelGameplayStarted(level, _)
    debugPrint("LevelGameplayStarted", level)
    onStarted(level)
end

function stopToTTimers()
    if State.Session.ToTRoundTimer ~= nil then
        Ext.Timer.Cancel(State.Session.ToTRoundTimer)
        State.Session.ToTRoundTimer = nil
    end
    if State.Session.ToTTimer ~= nil then
        Ext.Timer.Cancel(State.Session.ToTTimer)
        State.Session.ToTTimer = nil
    end
end

function startToTTimers()
    debugPrint("startToTTimers")
    stopToTTimers()
    if not Mods.ToT.Player.InCamp() then
        State.Session.ToTRoundTimer = Ext.Timer.WaitFor(6000, function ()
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
                State.Session.ToTTimer = Ext.Timer.WaitFor(0, function ()
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
    if level and entityUuid and State.Session.Players and State.Session.Players[entityUuid] then
        debugPrint("EnteredForceTurnBased", entityGuid)
        if State.Session.Players[entityUuid].isFreshSummon then
            State.Session.Players[entityUuid].isFreshSummon = false
            return Osi.ForceTurnBasedMode(entityUuid, 0)
        end
        if State.Session.AwaitingTarget[entityUuid] then
            Commands.setAwaitingTarget(entityUuid, false)
        end
        Quests.stopCountdownTimer(entityUuid)
        if State.Session.Brawlers[level] and State.Session.Brawlers[level][entityUuid] then
            State.Session.Brawlers[level][entityUuid].isInBrawl = false
        end
        stopPulseAddNearby(entityUuid)
        stopPulseReposition(level)
        stopBrawlFizzler(level)
        if isToT() then
            stopToTTimers()
        end
        if State.Settings.TruePause then
            Pause.startTruePause(entityUuid)
        end
        if State.Session.Brawlers[level] then
            for brawlerUuid, brawler in pairs(State.Session.Brawlers[level]) do
                if brawlerUuid ~= entityUuid and not State.Session.Brawlers[level][brawlerUuid].isPaused then
                    Osi.PurgeOsirisQueue(brawlerUuid, 1)
                    Osi.FlushOsirisQueue(brawlerUuid)
                    stopPulseAction(brawler, true)
                    if State.Session.Players[brawlerUuid] then
                        State.Session.Brawlers[level][brawlerUuid].isPaused = true
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
    if level and entityUuid and State.Session.Players and State.Session.Players[entityUuid] then
        debugPrint("LeftForceTurnBased", entityGuid)
        if State.Session.Players[entityUuid].isFreshSummon then
            State.Session.Players[entityUuid].isFreshSummon = false
        end
        Quests.resumeCountdownTimer(entityUuid)
        if State.Session.FTBLockedIn[entityUuid] then
            State.Session.FTBLockedIn[entityUuid] = nil
        end
        if State.Session.Brawlers[level] and State.Session.Brawlers[level][entityUuid] then
            State.Session.Brawlers[level][entityUuid].isInBrawl = true
            if State.isPlayerControllingDirectly(entityUuid) then
                startPulseAddNearby(entityUuid)
            end
        end
        startPulseReposition(level, true)
        Ext.Timer.WaitFor(1000, function ()
            stopPulseReposition(level)
            startPulseReposition(level)
        end)
        if State.areAnyPlayersBrawling() then
            startBrawlFizzler(level)
            if isToT() then
                startToTTimers()
            end
            if State.Session.Brawlers[level] then
                for brawlerUuid, brawler in pairs(State.Session.Brawlers[level]) do
                    if State.Session.Players[brawlerUuid] then
                        if not State.isPlayerControllingDirectly(brawlerUuid) then
                            Ext.Timer.WaitFor(2000, function ()
                                Osi.FlushOsirisQueue(brawlerUuid)
                                startPulseAction(brawler)
                            end)
                        end
                        State.Session.Brawlers[level][brawlerUuid].isPaused = false
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
    if level ~= nil and entityUuid ~= nil and State.Session.Brawlers[level] ~= nil and State.Session.Brawlers[level][entityUuid] ~= nil then
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
        if State.Session.Players[targetUuid] ~= nil and targetUserId ~= nil then
            State.Session.Players[targetUuid].isControllingDirectly = true
            startPulseAddNearby(targetUuid)
            local level = Osi.GetRegion(targetUuid)
            for playerUuid, player in pairs(State.Session.Players) do
                if player.userId == targetUserId and playerUuid ~= targetUuid then
                    player.isControllingDirectly = false
                    if level and State.Session.Brawlers[level] and State.Session.Brawlers[level][playerUuid] and State.Session.Brawlers[level][playerUuid].isInBrawl then
                        stopPulseAddNearby(playerUuid)
                        startPulseAction(State.Session.Brawlers[level][playerUuid])
                    end
                end
            end
            if level and State.Session.Brawlers[level] and State.Session.Brawlers[level][targetUuid] and not State.Settings.FullAuto then
                stopPulseAction(State.Session.Brawlers[level][targetUuid], true)
            end
            -- debugDump(State.Session.Players)
            Ext.ServerNet.PostMessageToUser(targetUserId, "GainedControl", targetUuid)
        end
    end
end

function onCharacterJoinedParty(character)
    debugPrint("CharacterJoinedParty", character)
    local uuid = Osi.GetUUID(character)
    if uuid then
        if State.Session.Players and not State.Session.Players[uuid] then
            State.setupPlayer(uuid)
            State.setupPartyMembersHitpoints()
        end
        if State.areAnyPlayersBrawling() then
            addBrawler(uuid, true)
        end
        if Osi.IsSummon(uuid) == 1 then
            State.Session.Players[uuid].isFreshSummon = true
        end
    end
end

function onCharacterLeftParty(character)
    debugPrint("CharacterLeftParty", character)
    local uuid = Osi.GetUUID(character)
    if uuid then
        if State.Session.Players and State.Session.Players[uuid] then
            State.Session.Players[uuid] = nil
        end
        local level = Osi.GetRegion(uuid)
        if State.Session.Brawlers and State.Session.Brawlers[level] and State.Session.Brawlers[level][uuid] then
            State.Session.Brawlers[level][uuid] = nil
        end
    end
end

function onDownedChanged(character, isDowned)
    local entityUuid = Osi.GetUUID(character)
    debugPrint("DownedChanged", character, isDowned, entityUuid)
    local player = State.Session.Players[entityUuid]
    local level = Osi.GetRegion(entityUuid)
    if player then
        if isDowned == 1 and State.Settings.AutoPauseOnDowned and player.isControllingDirectly then
            if State.Session.Brawlers[level] and State.Session.Brawlers[level][entityUuid] and not State.Session.Brawlers[level][entityUuid].isPaused then
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
            State.Session.PlayerCurrentTarget[attackerUuid] = defenderUuid
            if Osi.IsPlayer(defenderUuid) == 0 and damageAmount > 0 then
                State.Session.IsAttackingOrBeingAttackedByPlayer[defenderUuid] = attackerUuid
            end
            -- NB: is this needed?
            if isToT() then
                -- addNearbyToBrawlers(attackerUuid, 30, nil, true)
                addNearbyToBrawlers(attackerUuid, 30)
            end
        end
        if Osi.IsPlayer(defenderUuid) == 1 then
            if Osi.IsPlayer(attackerUuid) == 0 and damageAmount > 0 then
                State.Session.IsAttackingOrBeingAttackedByPlayer[attackerUuid] = defenderUuid
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

function onCastedSpell(casterGuid, spellName, _, _, _)
    debugPrint("CastedSpell", casterGuid, spellName, _, _, _)
    local casterUuid = Osi.GetUUID(casterGuid)
    debugDump(State.Session.ActionsInProgress[casterUuid])
    if Resources.removeActionInProgress(casterUuid, spellName) then
        Resources.deductCastedSpell(casterUuid, spellName)
    end
end

function onDialogStarted(dialog, dialogInstanceId)
    debugPrint("DialogStarted", dialog, dialogInstanceId)
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
        stopPulseReposition(level)
        stopBrawlFizzler(level)
        if State.Session.Brawlers[level] then
            for brawlerUuid, brawler in pairs(State.Session.Brawlers[level]) do
                stopPulseAction(brawler, true)
                Osi.PurgeOsirisQueue(brawlerUuid, 1)
                Osi.FlushOsirisQueue(brawlerUuid)
            end
        end
        -- NB: no way to just pause timers, and spinning up a new timer will appear to have a new maximum value...
        -- if dialog == "TUT_Helm_DragonAppears_6ffc2909-a928-4b8b-6901-02d823e68880" then
        --     if State.Session.CountdownTimer.uuid ~= nil and State.Session.CountdownTimer.timer ~= nil then
        --         Quests.stopCountdownTimer(State.Session.CountdownTimer.uuid)
        --         Quests.questTimerCancel("TUT_Helm_Timer")
        --     end
        -- end
    end
end

function onDialogEnded(dialog, dialogInstanceId)
    debugPrint("DialogEnded", dialog, dialogInstanceId)
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
        startPulseReposition(level)
        if State.Session.Brawlers[level] then
            for brawlerUuid, brawler in pairs(State.Session.Brawlers[level]) do
                if brawler.isInBrawl and not State.isPlayerControllingDirectly(brawlerUuid) then
                    startPulseAction(brawler)
                end
            end
        end
        -- if dialog == "TUT_Helm_DragonAppears_6ffc2909-a928-4b8b-6901-02d823e68880" then
        --     if State.Session.CountdownTimer.uuid ~= nil and State.Session.CountdownTimer.timer == nil then
        --         Quests.resumeCountdownTimer(State.Session.CountdownTimer.uuid)
        --         Quests.questTimerLaunch("TUT_Helm_Timer", "TUT_Helm_TransponderTimer", State.Session.CountdownTimer.turnsRemaining)
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
    if entityUuid ~= nil and State.Session.Brawlers ~= nil then
        for level, brawlersInLevel in pairs(State.Session.Brawlers) do
            if brawlersInLevel[entityUuid] ~= nil then
                removeBrawler(level, entityUuid)
                checkForEndOfBrawl(level)
            end
        end
    end
end

function onTeleportedFromCamp(character)
    local entityUuid = Osi.GetUUID(character)
    if entityUuid ~= nil and State.areAnyPlayersBrawling() then
        addBrawler(entityUuid, false)
    end
end

-- thank u focus
function onPROC_Subregion_Entered(characterGuid, _)
    debugPrint("PROC_Subregion_Entered", characterGuid)
    local uuid = Osi.GetUUID(characterGuid)
    local level = Osi.GetRegion(uuid)
    if level and State.Session.Players and State.Session.Players[uuid] then
        pulseReposition(level)
    end
end

function onLevelUnloading(level)
    debugPrint("LevelUnloading", level)
    State.Session.Brawlers[level] = nil
    stopPulseReposition(level)
end

function onObjectTimerFinished(objectGuid, timer)
    debugPrint("ObjectTimerFinished", objectGuid, timer)
    if timer == "TUT_Helm_Timer" then
        Quests.nautiloidTransponderCountdownFinished(Osi.GetUUID(objectGuid))
    elseif timer == "HAV_LikesideCombat_CombatRoundTimer" then
        Quests.lakesideRitualCountdownFinished(Osi.GetUUID(objectGuid))
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
        Quests.questTimerLaunch("HAV_LikesideCombat_CombatRoundTimer", "HAV_HalsinPortalTimer", LAKESIDE_RITUAL_COUNTDOWN_TURNS)
        Quests.lakesideRitualCountdown(Osi.GetHostCharacter(), LAKESIDE_RITUAL_COUNTDOWN_TURNS)
    elseif flag == "GLO_Halsin_State_PermaDefeated_86bc3df1-08b4-fbc4-b542-6241bcd03df1" then
        Quests.questTimerCancel("HAV_LikesideCombat_CombatRoundTimer")
        Quests.stopCountdownTimer(Osi.GetHostCharacter())
    elseif flag == "HAV_LiftingTheCurse_Event_HalsinClosesPortal_33aa334a-3127-4be1-ad94-518aa4f24ef4" then
        Quests.questTimerCancel("HAV_LikesideCombat_CombatRoundTimer")
        Quests.stopCountdownTimer(Osi.GetHostCharacter())
    elseif flag == "TUT_Helm_JoinedMindflayerFight_ec25d7dc-f9d6-47ff-92c9-8921d6e32f54" then
        Quests.questTimerLaunch("TUT_Helm_Timer", "TUT_Helm_TransponderTimer", NAUTILOID_TRANSPONDER_COUNTDOWN_TURNS)
        Quests.nautiloidTransponderCountdown(Osi.GetHostCharacter(), NAUTILOID_TRANSPONDER_COUNTDOWN_TURNS)
    elseif flag == "TUT_Helm_State_TutorialEnded_55073953-23b9-448c-bee8-4c44d3d67b6b" then
        Quests.questTimerCancel("TUT_Helm_Timer")
        Quests.stopCountdownTimer(Osi.GetHostCharacter())
    end
end

function stopListeners()
    cleanupAll()
    for _, listener in pairs(State.Session.Listeners) do
        listener.stop(listener.handle)
    end
end

function startListeners()
    debugPrint("Starting listeners...")
    State.Session.Listeners.ResetCompleted = {}
    State.Session.Listeners.ResetCompleted.handle = Ext.Events.ResetCompleted:Subscribe(onResetCompleted)
    State.Session.Listeners.ResetCompleted.stop = function ()
        Ext.Events.ResetCompleted:Unsubscribe(State.Session.Listeners.ResetCompleted.handle)
    end
    State.Session.Listeners.UserReservedFor = {
        handle = Ext.Entity.Subscribe("UserReservedFor", onUserReservedFor),
        stop = Ext.Entity.Unsubscribe,
    }
    State.Session.Listeners.LevelGameplayStarted = {
        handle = Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", onLevelGameplayStarted),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.CombatStarted = {
        handle = Ext.Osiris.RegisterListener("CombatStarted", 1, "after", onCombatStarted),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.CombatEnded = {
        handle = Ext.Osiris.RegisterListener("CombatEnded", 1, "after", onCombatEnded),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.CombatRoundStarted = {
        handle = Ext.Osiris.RegisterListener("CombatRoundStarted", 2, "after", onCombatRoundStarted),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.EnteredCombat = {
        handle = Ext.Osiris.RegisterListener("EnteredCombat", 2, "after", onEnteredCombat),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.EnteredForceTurnBased = {
        handle = Ext.Osiris.RegisterListener("EnteredForceTurnBased", 1, "after", onEnteredForceTurnBased),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.LeftForceTurnBased = {
        handle = Ext.Osiris.RegisterListener("LeftForceTurnBased", 1, "after", onLeftForceTurnBased),
        stop = Ext.Osiris.UnregisterListener,
    }
    -- State.Session.Listeners.TurnEnded = {
    --     handle = Ext.Osiris.RegisterListener("TurnEnded", 1, "after", onTurnEnded),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    State.Session.Listeners.Died = {
        handle = Ext.Osiris.RegisterListener("Died", 1, "after", onDied),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.GainedControl = {
        handle = Ext.Osiris.RegisterListener("GainedControl", 1, "after", onGainedControl),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.CharacterJoinedParty = {
        handle = Ext.Osiris.RegisterListener("CharacterJoinedParty", 1, "after", onCharacterJoinedParty),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.CharacterLeftParty = {
        handle = Ext.Osiris.RegisterListener("CharacterLeftParty", 1, "after", onCharacterLeftParty),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.DownedChanged = {
        handle = Ext.Osiris.RegisterListener("DownedChanged", 2, "after", onDownedChanged),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.AttackedBy = {
        handle = Ext.Osiris.RegisterListener("AttackedBy", 7, "after", onAttackedBy),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.CastedSpell = {
        handle = Ext.Osiris.RegisterListener("CastedSpell", 5, "after", onCastedSpell),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.DialogStarted = {
        handle = Ext.Osiris.RegisterListener("DialogStarted", 2, "before", onDialogStarted),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.DialogEnded = {
        handle = Ext.Osiris.RegisterListener("DialogEnded", 2, "after", onDialogEnded),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.DifficultyChanged = {
        handle = Ext.Osiris.RegisterListener("DifficultyChanged", 1, "after", onDifficultyChanged),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.TeleportedToCamp = {
        handle = Ext.Osiris.RegisterListener("TeleportedToCamp", 1, "after", onTeleportedToCamp),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.TeleportedFromCamp = {
        handle = Ext.Osiris.RegisterListener("TeleportedFromCamp", 1, "after", onTeleportedFromCamp),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.PROC_Subregion_Entered = {
        handle = Ext.Osiris.RegisterListener("PROC_Subregion_Entered", 2, "after", onPROC_Subregion_Entered),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.LevelUnloading = {
        handle = Ext.Osiris.RegisterListener("LevelUnloading", 1, "after", onLevelUnloading),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.ObjectTimerFinished = {
        handle = Ext.Osiris.RegisterListener("ObjectTimerFinished", 2, "after", onObjectTimerFinished),
        stop = Ext.Osiris.UnregisterListener,
    }
    -- State.Session.Listeners.SubQuestUpdateUnlocked = {
    --     handle = Ext.Osiris.RegisterListener("SubQuestUpdateUnlocked", 3, "after", onSubQuestUpdateUnlocked),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    -- State.Session.Listeners.QuestUpdateUnlocked = {
    --     handle = Ext.Osiris.RegisterListener("QuestUpdateUnlocked", 3, "after", onQuestUpdateUnlocked),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    -- State.Session.Listeners.QuestAccepted = {
    --     handle = Ext.Osiris.RegisterListener("QuestAccepted", 2, "after", onQuestAccepted),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    -- State.Session.Listeners.FlagCleared = {
    --     handle = Ext.Osiris.RegisterListener("FlagCleared", 3, "after", onFlagCleared),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    -- State.Session.Listeners.FlagLoadedInPresetEvent = {
    --     handle = Ext.Osiris.RegisterListener("FlagLoadedInPresetEvent", 2, "after", onFlagLoadedInPresetEvent),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    State.Session.Listeners.FlagSet = {
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
    if payload and payload.modUUID == ModuleUUID and payload.settingId and Commands.MCMSettingSaved[payload.settingId] then
        Commands.MCMSettingSaved[payload.settingId](payload.value)
    end
end

function onNetMessage(data)
    if Commands.NetMessage[data.Channel] then
        Commands.NetMessage[data.Channel](data)
    end
end

function onSessionLoaded()
    Ext.Events.NetMessage:Subscribe(onNetMessage)
    if State.Settings.ModEnabled then
        startListeners()
    else
        Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", State.resetPlayers)
    end
end

Ext.Events.SessionLoaded:Subscribe(onSessionLoaded)
Ext.Events.GameStateChanged:Subscribe(onGameStateChanged)
if MCM then
    Ext.ModEvents.BG3MCM["MCM_Setting_Saved"]:Subscribe(onMCMSettingSaved)
end
