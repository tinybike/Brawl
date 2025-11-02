local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump
local isToT = Utils.isToT

local function getSpellTypeWeight(spellType)
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

local function getResistanceWeight(spell, uuid)
    local entity = Ext.Entity.Get(uuid)
    if entity and entity.Resistances and entity.Resistances.Resistances then
        local resistances = entity.Resistances.Resistances
        if spell.damageType ~= "None" and resistances[Constants.DAMAGE_TYPES[spell.damageType]] and resistances[Constants.DAMAGE_TYPES[spell.damageType]][1] then
            local resistance = resistances[Constants.DAMAGE_TYPES[spell.damageType]][1]
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

local function getHighestWeightSpell(weightedSpells)
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
    -- debugPrint("selected spell", selectedSpell, maxWeight)
    return selectedSpell
end

-- should account for damage range
local function getSpellWeight(uuid, spellName, spell, distanceToTarget, hasLineOfSight, archetype, spellType, numExtraAttacks, targetUuid)
    -- Special target radius labels (NB: are there others besides these two?)
    -- Maybe should weight proportional to distance required to get there...?
    local archetypeWeights = Constants.ARCHETYPE_WEIGHTS[archetype]
    local weight = 0
    -- Favor using spells or non-spells?
    if spell.isSpell then
        weight = weight + archetypeWeights.isSpell
    end
    -- If this spell has a damage type, favor vulnerable enemies
    -- (NB: this doesn't account for physical weapon damage, which is attached to the weapon itself -- todo)
    if State.Settings.TurnBasedSwarmMode and spell.damageType ~= nil and spell.damageType ~= "None" then
        local resistanceWeight = M.Pick.getResistanceWeight(spell, targetUuid)
        weight = weight + resistanceWeight
    end
    -- Adjust by spell type (damage and healing spells are somewhat favored in general)
    weight = weight + getSpellTypeWeight(spellType)
    -- Adjust by spell level, if we're in hogwild mode
    if State.Settings.HogwildMode then
        weight = weight + spell.level*2
    end
    -- NB: factor in amount of healing for healing spells also?
    if spellType == "Damage" then
        if spell.triggersExtraAttack and numExtraAttacks > 0 then
            weight = numExtraAttacks*archetypeWeights.triggersExtraAttack
        end
        if spell.isWeaponOrUnarmedDamage then
            weight = weight + archetypeWeights.weaponOrUnarmedDamage
        end
        weight = weight + archetypeWeights.spellDamage*spell.averageDamage
        if spell.isSafeAoE and spell.areaRadius > 1 then
            weight = weight + 3*spell.areaRadius
        end
        if spell.applyStatusOnSuccess then
            weight = weight + archetypeWeights.applyDebuff
        end
        -- If this spell is available at all, that means the target is resonating, so you probably want to go ahead and detonate it!
        if spellName == "Target_KiResonation_Blast" then
            weight = weight + 50
        end
    end
    if spell.isGapCloser then
        if distanceToTarget > Constants.GAP_CLOSER_DISTANCE then
            weight = weight + archetypeWeights.gapCloser
        else
            weight = weight - archetypeWeights.gapCloser
        end
    end
    if spell.targetRadius == "MeleeMainWeaponRange" then
        weight = weight + archetypeWeights.meleeWeapon
        if distanceToTarget <= M.Utils.getMeleeWeaponRange(uuid) then
            weight = weight + archetypeWeights.meleeWeaponInRange
        end
    else
        if spell.targetRadius == "RangedMainWeaponRange" then
            weight = weight + archetypeWeights.rangedWeapon
            if distanceToTarget < M.Utils.getRangedWeaponRange(uuid) then
                weight = weight + archetypeWeights.rangedWeaponInRange
            else
                weight = weight + archetypeWeights.rangedWeaponOutOfRange
            end
        -- NB: should the weights be different from ranged and thrown (e.g. tavern brawler spec)? should we do a lookup for throwing range?
        elseif spell.targetRadius == "ThrownObjectRange" then
            weight = weight + archetypeWeights.rangedWeapon
            if distanceToTarget < Constants.THROWN_RANGE_MAX then
                weight = weight + archetypeWeights.rangedWeaponInRange
            else
                weight = weight + archetypeWeights.rangedWeaponOutOfRange
            end
        else
            local targetRadius = tonumber(spell.targetRadius)
            if targetRadius then
                if distanceToTarget <= targetRadius then
                    weight = weight + archetypeWeights.spellInRange
                end
            else
                local range = tonumber(spell.range)
                if range then
                    if distanceToTarget <= range then
                        weight = weight + archetypeWeights.spellInRange
                    end
                else
                    print("Target radius and range didn't convert to number, what is this?")
                    _D(spell)
                end
            end
        end
        -- Disfavor non-seeking ranged abilities unless we have line-of-sight
        if not spell.isAutoPathfinding and not hasLineOfSight then
            weight = weight/2
        end
    end
    -- Randomize weight by +/- 30% to keep it interesting
    weight = math.floor(weight*(0.7 + math.random()*0.6) + 0.5)
    return weight
end

local function isSpellExcluded(spellName, excludedSpells)
    if excludedSpells then
        for _, excludedSpellName in ipairs(excludedSpells) do
            if spellName == excludedSpellName then
                return true
            end
        end
    end
    return false
end

-- NB need to allow healing, buffs, debuffs etc for companions too
local function isCompanionSpellAvailable(uuid, targetUuid, spellName, spell, isSilenced, isConcentrating, excludedSpells, distanceToTarget, targetDistanceToParty, allowAoE, bonusActionOnly)
    if spellName == nil or spell == nil then
        return false
    end
    if isSpellExcluded(spellName, excludedSpells) then
        return false
    end
    -- If we're silenced, we can't use spells that have a verbal component
    if isSilenced and spell.hasVerbalComponent then
        return false
    end
    -- If we're already concentrating, don't use another concentration spell
    if isConcentrating and spell.isConcentration then
        return false
    end
    -- Exclude AoE and zone-type damage spells for now (even in Hogwild Mode) so the companions don't blow each other up on accident
    if (spell.areaRadius > 0 or M.Utils.isZoneSpell(spellName)) and not spell.isSafeAoE then
        if not allowAoE and spell.type == "Damage" then
            return false
        end
        if allowAoE and not spell.isEvocation then
            return false
        end
    end
    -- If it's a healing spell, make sure it's a direct heal
    if spell.type == "Healing" and not spell.isDirectHeal then
        return false
    end
    if bonusActionOnly and not spell.isBonusAction then
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
        if not M.Resources.hasEnoughToCastSpell(uuid, spellName) then
            return false
        end
    end
    if spellName == "Target_KiResonation_Blast" and M.Osi.HasActiveStatus(targetUuid, "KI_RESONATION") == 0 then
        return false
    end
    -- For defense tactics:
    --  1. Is the target already within range? Then ok to use
    --  2. If the target is out-of-range, can we hit him without moving outside of the perimeter? Then ok to use
    if State.Settings.CompanionTactics == "Defense" then
        local range = M.Utils.convertSpellRangeToNumber(M.Utils.getSpellRange(spellName), uuid)
        if distanceToTarget > range and targetDistanceToParty > (range + State.Settings.DefensiveTacticsMaxDistance) then
            return false
        end
    end
    return true
end

local function isNpcSpellUsable(spellName)
    for _, unusableSpell in ipairs(Constants.UNUSABLE_NPC_SPELLS) do
        if spellName == unusableSpell then
            return false
        end
    end
    return true
end

local function isEnemySpellAvailable(uuid, targetUuid, spellName, spell, isSilenced, isConcentrating, excludedSpells, bonusActionOnly)
    if spellName == nil or spell == nil then
        return false
    end
    if isSpellExcluded(spellName, excludedSpells) then
        return false
    end
    if isSilenced and spell.hasVerbalComponent then
        return false
    end
    if isConcentrating and spell.isConcentration then
        return false
    end
    if spell.type == "Healing" and not spell.isDirectHeal then
        return false
    end
    if spell.outOfCombatOnly then
        return false
    end
    if bonusActionOnly and not spell.isBonusAction then
        return false
    end
    if spellName == "Target_KiResonation_Blast" and M.Osi.HasActiveStatus(targetUuid, "KI_RESONATION") == 0 then
        return false
    end
    if State.Settings.TurnBasedSwarmMode or not State.Settings.HogwildMode then
        if not M.Resources.hasEnoughToCastSpell(uuid, spellName) then
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
local function getCompanionWeightedSpells(uuid, targetUuid, preparedSpells, excludedSpells, distanceToTarget, archetype, spellTypes, numExtraAttacks, targetDistanceToParty, allowAoE, bonusActionOnly)
    local weightedSpells = {}
    local isSilenced = M.Utils.isSilenced(uuid)
    local isConcentrating = M.Utils.isConcentrating(uuid)
    local hasLineOfSight = M.Osi.HasLineOfSight(uuid, targetUuid) == 1
    for _, preparedSpell in pairs(preparedSpells) do
        local spellName = preparedSpell.OriginatorPrototype
        if M.Pick.isNpcSpellUsable(spellName) then
            local spell = nil
            for _, spellType in ipairs(spellTypes) do
                spell = State.Session.SpellTable[spellType][spellName]
                if spell ~= nil then
                    break
                end
            end
            if M.Pick.isCompanionSpellAvailable(uuid, targetUuid, spellName, spell, isSilenced, isConcentrating, excludedSpells, distanceToTarget, targetDistanceToParty, allowAoE, bonusActionOnly) then
                weightedSpells[spellName] = M.Pick.getSpellWeight(uuid, spellName, spell, distanceToTarget, hasLineOfSight, archetype, spell.type, numExtraAttacks, targetUuid)
            end
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
local function getWeightedSpells(uuid, targetUuid, preparedSpells, excludedSpells, distanceToTarget, archetype, spellTypes, numExtraAttacks, bonusActionOnly)
    local weightedSpells = {}
    local isSilenced = M.Utils.isSilenced(uuid)
    local isConcentrating = M.Utils.isConcentrating(uuid)
    local hasLineOfSight = M.Osi.HasLineOfSight(uuid, targetUuid) == 1
    for _, preparedSpell in pairs(preparedSpells) do
        local spellName = preparedSpell.OriginatorPrototype
        if M.Pick.isNpcSpellUsable(spellName) then
            local spell = nil
            for _, spellType in ipairs(spellTypes) do
                spell = State.Session.SpellTable[spellType][spellName]
                if spell ~= nil then
                    break
                end
            end
            if M.Pick.isEnemySpellAvailable(uuid, targetUuid, spellName, spell, isSilenced, isConcentrating, excludedSpells, bonusActionOnly) then
                weightedSpells[spellName] = M.Pick.getSpellWeight(uuid, spellName, spell, distanceToTarget, hasLineOfSight, archetype, spell.type, numExtraAttacks, targetUuid)
            end
        end
    end
    return weightedSpells
end

local function decideCompanionActionOnTarget(brawler, targetUuid, preparedSpells, excludedSpells, distanceToTarget, spellTypes, targetDistanceToParty, allowAoE, bonusActionOnly)
    local weightedSpells = getCompanionWeightedSpells(brawler.uuid, targetUuid, preparedSpells, excludedSpells, distanceToTarget, brawler.archetype, spellTypes, brawler.numExtraAttacks, targetDistanceToParty, allowAoE, bonusActionOnly)
    debugPrint(brawler.displayName, "companion weighted spells", brawler.uuid, brawler.archetype, distanceToTarget, bonusActionOnly)
    -- debugDump(Constants.ARCHETYPE_WEIGHTS[brawler.archetype])
    debugDump(weightedSpells)
    return getHighestWeightSpell(weightedSpells)
end

local function decideActionOnTarget(brawler, targetUuid, preparedSpells, excludedSpells, distanceToTarget, spellTypes, bonusActionOnly)
    local weightedSpells = getWeightedSpells(brawler.uuid, targetUuid, preparedSpells, excludedSpells, distanceToTarget, brawler.archetype, spellTypes, brawler.numExtraAttacks, bonusActionOnly)
    debugPrint(brawler.displayName, "enemy weighted spells", brawler.uuid, brawler.archetype, distanceToTarget, bonusActionOnly)
    debugDump(weightedSpells)
    return getHighestWeightSpell(weightedSpells)
end

local function checkEntityConditions(uuid, conditions)
    for fn, conditionPair in pairs(conditions) do
        for req, condition in pairs(conditionPair) do
            for _, label in ipairs(condition) do
                local res
                if fn == "IsImmuneToStatus" then
                    res = M.Osi[fn](uuid, label, "")
                elseif fn == "HasActiveStatus" and Utils.startsWith(label, "SG_") then
                    res = M.Osi.HasActiveStatusWithGroup(uuid, label)
                else
                    res = M.Osi[fn](uuid, label)
                end
                if res ~= tonumber(req) then
                    return false
                end
            end
        end
    end
    return true
end

local function checkConditions(uuids, spell)
    if not spell.conditions or not next(spell.conditions) then
        return true
    end
    for k, conditions in pairs(spell.conditions) do
        if not checkEntityConditions(uuids[k], conditions) then
            return false
        end
    end
    return true
end

local function selectRandomSpell(preparedSpells)
    local numUsableSpells = 0
    local usableSpells = {}
    for _, preparedSpell in pairs(preparedSpells) do
        local spellName = preparedSpell.OriginatorPrototype
        if M.Pick.isNpcSpellUsable(spellName) then
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
    return actionToTake
end

local function getOffenseWeightedTarget(distanceToTarget, targetHp, targetHpPct, canSeeTarget, isHealer, isHostile, isMelee, hasPathToTarget)
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
    if isMelee and not hasPathToTarget then
        weightedTarget = weightedTarget*3
    end
    return weightedTarget
end

local function getBalancedWeightedTarget(distanceToTarget, targetHp, targetHpPct, canSeeTarget, isHealer, isHostile, isMelee, hasPathToTarget, attackerUuid, targetUuid, anchorCharacterUuid)
    if not isHostile and targetHpPct == 100.0 then
        return nil
    end
    if not anchorCharacterUuid then
        debugPrint("(Balanced) Anchor character not found, reverting to Offense weighting")
        return getOffenseWeightedTarget(distanceToTarget, targetHp, canSeeTarget, isHealer, isHostile, isMelee, hasPathToTarget)
    end
    local weightedTarget
    local targetDistanceToParty = M.Osi.GetDistanceTo(targetUuid, anchorCharacterUuid)
    -- Only include potential targets that are within X meters of the party
    if targetDistanceToParty ~= nil and targetDistanceToParty < State.Settings.DefensiveTacticsMaxDistance then
        weightedTarget = 3*distanceToTarget + 0.25*targetHp
        if not canSeeTarget then
            weightedTarget = weightedTarget*1.8
        end
        if isHealer and not isHostile then
            weightedTarget = weightedTarget*0.4
        elseif not isHealer and isHostile then
            weightedTarget = weightedTarget*0.6
        end
        if isMelee and not hasPathToTarget then
            weightedTarget = weightedTarget*3
        end
    end
    return weightedTarget
end

local function getDefenseWeightedTarget(distanceToTarget, targetHp, targetHpPct, canSeeTarget, isHealer, isHostile, isMelee, hasPathToTarget, attackerUuid, targetUuid, anchorCharacterUuid)
    if not isHostile and targetHpPct == 100.0 then
        return nil
    end
    if not anchorCharacterUuid then
        debugPrint("(Defense) Anchor character not found, reverting to Offense weighting")
        return getOffenseWeightedTarget(distanceToTarget, targetHp, canSeeTarget, isHealer, isHostile, isMelee, hasPathToTarget)
    end
    local weightedTarget
    local targetDistanceToAnchor = M.Osi.GetDistanceTo(targetUuid, anchorCharacterUuid)
    -- Only include potential targets that are within X meters of the player
    debugPrint("def", anchorCharacterUuid, targetDistanceToAnchor, State.Settings.DefensiveTacticsMaxDistance)
    if targetDistanceToAnchor ~= nil and targetDistanceToAnchor < State.Settings.DefensiveTacticsMaxDistance then
        weightedTarget = 3*distanceToTarget + 0.25*targetHp
        if not canSeeTarget then
            weightedTarget = weightedTarget*1.8
        end
        if isHealer and not isHostile then
            weightedTarget = weightedTarget*0.4
        elseif not isHealer and isHostile then
            weightedTarget = weightedTarget*0.6
        end
        if isMelee and not hasPathToTarget then
            weightedTarget = weightedTarget*3
        end
    end
    return weightedTarget
end

local function whoNeedsHealing(uuid, level)
    local minTargetHpPct = 100.0
    local friendlyTargetUuid = nil
    local brawlersInLevel = State.Session.Brawlers[level]
    for targetUuid, target in pairs(brawlersInLevel) do
        if M.Osi.IsAlly(uuid, targetUuid) == 1 then
            local targetHpPct = M.Osi.GetHitpointsPercentage(targetUuid)
            if targetHpPct ~= nil and targetHpPct > 0 and targetHpPct < minTargetHpPct then
                minTargetHpPct = targetHpPct
                friendlyTargetUuid = targetUuid
            end
        end
    end
    return friendlyTargetUuid
end

-- Attacking targets: prioritize close targets with less remaining HP
-- (Lowest weight = most desireable target)
local function getWeightedTargets(brawler, potentialTargets, bonusActionOnly, healingNeeded)
    -- print("GETTING WEIGHTED TARGETS -- is healing needed????????", healingNeeded)
    local weightedTargets = {}
    local isHealer = M.Utils.isHealerArchetype(brawler.archetype)
    local isMelee = nil
    if State.Settings.TurnBasedSwarmMode then
        isMelee = M.Utils.isMeleeArchetype(brawler.archetype)
    end
    local anchorCharacterUuid
    if M.Utils.isPlayerOrAlly(brawler.uuid) then
        if State.Settings.CompanionTactics == "Balanced" then
            anchorCharacterUuid = M.Osi.GetClosestAlivePlayer(brawler.uuid)
            if anchorCharacterUuid == nil then
                anchorCharacterUuid = M.Osi.GetHostCharacter()
            end
        elseif State.Settings.CompanionTactics == "Defense" then
            if State.Session.Players and State.Session.Players[brawler.uuid] and State.Session.Players[brawler.uuid].userId then
                local player = State.getPlayerByUserId(State.Session.Players[brawler.uuid].userId)
                if player then
                    anchorCharacterUuid = player.uuid
                end
            end
            if anchorCharacterUuid == nil then
                anchorCharacterUuid = M.Osi.GetHostCharacter()
            end
        end
    end
    for potentialTargetUuid, _ in pairs(potentialTargets) do
        if not isToT() or (Mods.ToT.PersistentVars.Scenario and potentialTargetUuid ~= Mods.ToT.PersistentVars.Scenario.CombatHelper) then
            debugPrint(brawler.displayName, "checking potential target", M.Utils.getDisplayName(potentialTargetUuid), potentialTargetUuid)
            local weightedTarget
            if (M.Utils.isAliveAndCanFight(potentialTargetUuid) or M.Utils.isDowned(potentialTargetUuid)) and (healingNeeded or M.Osi.IsAlly(brawler.uuid, potentialTargetUuid) == 0) then
                if brawler.uuid == potentialTargetUuid then
                    local preparedSpells = Ext.Entity.Get(brawler.uuid).SpellBookPrepares.PreparedSpells
                    debugPrint("has direct heal?", M.State.hasDirectHeal(brawler.uuid, preparedSpells, false, bonusActionOnly))
                    if M.State.hasDirectHeal(brawler.uuid, preparedSpells, false, bonusActionOnly) then
                        local targetHp = M.Osi.GetHitpoints(potentialTargetUuid)
                        local targetHpPct = M.Osi.GetHitpointsPercentage(potentialTargetUuid)
                        if State.Settings.CompanionTactics == "Offense" then
                            weightedTarget = M.Pick.getOffenseWeightedTarget(0, targetHp, targetHpPct, true, isHealer, false, nil, nil)
                        elseif State.Settings.CompanionTactics == "Defense" then
                            weightedTarget = M.Pick.getDefenseWeightedTarget(0, targetHp, targetHpPct, true, isHealer, false, nil, nil, brawler.uuid, potentialTargetUuid, anchorCharacterUuid)
                        else
                            weightedTarget = M.Pick.getBalancedWeightedTarget(0, targetHp, targetHpPct, true, isHealer, false, nil, nil, brawler.uuid, potentialTargetUuid, anchorCharacterUuid)
                        end
                    end
                else
                    local distanceToTarget = M.Osi.GetDistanceTo(brawler.uuid, potentialTargetUuid)
                    local canSeeTarget = M.Osi.CanSee(brawler.uuid, potentialTargetUuid) == 1
                    debugPrint(brawler.displayName, "distanceToTarget", distanceToTarget, canSeeTarget, State.Session.ActiveCombatGroups[brawler.combatGroupId], State.Session.IsAttackingOrBeingAttackedByPlayer[potentialTargetUuid], isHealer, isMelee)
                    local ableToTarget = true
                    local isHostile = M.Utils.isHostileTarget(brawler.uuid, potentialTargetUuid)
                    if not State.Settings.TurnBasedSwarmMode and (distanceToTarget > 30 or (isHostile and not canSeeTarget)) then
                        ableToTarget = false
                    end
                    debugPrint(ableToTarget, State.Session.ActiveCombatGroups[brawler.combatGroupId], State.Session.IsAttackingOrBeingAttackedByPlayer[potentialTargetUuid])
                    if isToT() or ableToTarget or State.Session.ActiveCombatGroups[brawler.combatGroupId] or State.Session.IsAttackingOrBeingAttackedByPlayer[potentialTargetUuid] then
                        local hasPathToTarget = nil
                        if (isHostile and M.Utils.isValidHostileTarget(brawler.uuid, potentialTargetUuid)) or (M.State.hasDirectHeal(brawler.uuid, Ext.Entity.Get(brawler.uuid).SpellBookPrepares.PreparedSpells, true, bonusActionOnly)) then
                            if isMelee and isHostile then
                                hasPathToTarget = M.Movement.findPathToTargetUuid(brawler.uuid, potentialTargetUuid)
                            end
                            debugPrint(brawler.displayName, "Is Hostile Target, Is Melee, has path to target?", isHostile, isMelee, hasPathToTarget, M.Utils.isPlayerOrAlly(brawler.uuid))
                            local targetHp = M.Osi.GetHitpoints(potentialTargetUuid)
                            local targetHpPct = M.Osi.GetHitpointsPercentage(potentialTargetUuid)
                            if not M.Utils.isPlayerOrAlly(brawler.uuid) then
                                weightedTarget = M.Pick.getOffenseWeightedTarget(distanceToTarget, targetHp, targetHpPct, canSeeTarget, isHealer, isHostile, isMelee, hasPathToTarget)
                                debugPrint(brawler.displayName, "Got offense weighted target", M.Utils.getDisplayName(potentialTargetUuid), weightedTarget)
                                if brawler.combatGroupId ~= nil then
                                    State.Session.ActiveCombatGroups[brawler.combatGroupId] = true
                                end
                            else
                                if State.Settings.CompanionTactics == "Offense" then
                                    weightedTarget = M.Pick.getOffenseWeightedTarget(distanceToTarget, targetHp, targetHpPct, canSeeTarget, isHealer, isHostile, isMelee, hasPathToTarget)
                                elseif State.Settings.CompanionTactics == "Defense" then
                                    weightedTarget = M.Pick.getDefenseWeightedTarget(distanceToTarget, targetHp, targetHpPct, canSeeTarget, isHealer, isHostile, isMelee, hasPathToTarget, brawler.uuid, potentialTargetUuid, anchorCharacterUuid)
                                else
                                    weightedTarget = M.Pick.getBalancedWeightedTarget(distanceToTarget, targetHp, targetHpPct, canSeeTarget, isHealer, isHostile, isMelee, hasPathToTarget, brawler.uuid, potentialTargetUuid, anchorCharacterUuid)
                                end
                            end
                            debugPrint(brawler.displayName, "weighted target", M.Utils.getDisplayName(potentialTargetUuid), weightedTarget)
                            if State.Settings.TurnBasedSwarmMode and weightedTarget ~= nil and M.Utils.isConcentrating(potentialTargetUuid) then
                                weightedTarget = weightedTarget / Constants.AI_TARGET_CONCENTRATION_WEIGHT_FACTOR
                            end
                        end
                    end
                end
            end
            if weightedTarget ~= nil then
                weightedTargets[potentialTargetUuid] = weightedTarget
            end
        end
    end
    debugDump(weightedTargets)
    return weightedTargets
end

local function decideOnTarget(weightedTargets)
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

local function shouldRage(uuid, rage)
    return rage and checkConditions({caster = uuid, target = uuid}, M.Spells.getSpellByName(rage))
end

local function shouldUseAuras(uuid, auras)
    if auras and next(auras) then
        for _, aura in ipairs(auras) do
            if M.Pick.checkConditions({caster = uuid, target = uuid}, M.Spells.getSpellByName(aura)) then
                return true
            end
        end
    end
    return false
end

return {
    getResistanceWeight = getResistanceWeight,
    getSpellWeight = getSpellWeight,
    isNpcSpellUsable = isNpcSpellUsable,
    isCompanionSpellAvailable = isCompanionSpellAvailable,
    isEnemySpellAvailable = isEnemySpellAvailable,
    checkConditions = checkConditions,
    selectRandomSpell = selectRandomSpell,
    decideCompanionActionOnTarget = decideCompanionActionOnTarget,
    decideActionOnTarget = decideActionOnTarget,
    getOffenseWeightedTarget = getOffenseWeightedTarget,
    getBalancedWeightedTarget = getBalancedWeightedTarget,
    getDefenseWeightedTarget = getDefenseWeightedTarget,
    whoNeedsHealing = whoNeedsHealing,
    getWeightedTargets = getWeightedTargets,
    decideOnTarget = decideOnTarget,
    shouldRage = shouldRage,
    shouldUseAuras = shouldUseAuras,
}
