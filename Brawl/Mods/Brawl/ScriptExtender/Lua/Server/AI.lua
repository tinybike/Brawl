-- local Constants = require("Server/Constants.lua")
-- local Utils = require("Server/Utils.lua")
-- local State = require("Server/State.lua")
-- local Resources = require("Server/Resources.lua")
-- local Movement = require("Server/Movement.lua")
-- local Roster = require("Server/Roster.lua")

local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump
local getDisplayName = Utils.getDisplayName
local isOnSameLevel = Utils.isOnSameLevel
local isDowned = Utils.isDowned
local isPugnacious = Utils.isPugnacious
local isAliveAndCanFight = Utils.isAliveAndCanFight
local isVisible = Utils.isVisible
local convertSpellRangeToNumber = Utils.convertSpellRangeToNumber
local getSpellRange = Utils.getSpellRange
local isZoneSpell = Utils.isZoneSpell
local isPlayerOrAlly = Utils.isPlayerOrAlly
local isHealerArchetype = Utils.isHealerArchetype
local isBrawlingWithValidTarget = Utils.isBrawlingWithValidTarget
local isSilenced = Utils.isSilenced
local isPlayerControllingDirectly = State.isPlayerControllingDirectly
local clearOsirisQueue = Utils.clearOsirisQueue

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

local function getResistanceWeight(spell, entity)
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
    -- print("selected spell", selectedSpell, maxWeight)
    return (selectedSpell ~= "Target_MainHandAttack") and selectedSpell
end

-- should account for damage range
local function getSpellWeight(spell, distanceToTarget, archetype, spellType, numExtraAttacks)
    -- Special target radius labels (NB: are there others besides these two?)
    -- Maybe should weight proportional to distance required to get there...?
    local archetypeWeights = Constants.ARCHETYPE_WEIGHTS[archetype]
    local weight = 0
    -- NB: factor in amount of healing for healing spells also?
    if spellType == "Damage" then
        if spell.triggersExtraAttack and numExtraAttacks > 0 then
            weight = numExtraAttacks*archetypeWeights.triggersExtraAttack
        end
        if spell.isWeaponOrUnarmedDamage then
            weight = weight + archetypeWeights.weaponOrUnarmedDamage
        end
        weight = weight + archetypeWeights.spellDamage*spell.averageDamage
    end
    if spell.isGapCloser then
        if distanceToTarget > Constants.GAP_CLOSER_DISTANCE then
            weight = weight + archetypeWeights.gapCloser
        else
            weight = weight - archetypeWeights.gapCloser
        end
    end
    if spell.targetRadius == "RangedMainWeaponRange" then
        weight = weight + archetypeWeights.rangedWeapon
        if distanceToTarget > Constants.RANGED_RANGE_MIN and distanceToTarget < Constants.RANGED_RANGE_MAX then
            weight = weight + archetypeWeights.rangedWeaponInRange
        else
            weight = weight + archetypeWeights.rangedWeaponOutOfRange
        end
    elseif spell.targetRadius == "MeleeMainWeaponRange" then
        weight = weight + archetypeWeights.meleeWeapon
        if distanceToTarget <= Constants.MELEE_RANGE then
            weight = weight + archetypeWeights.meleeWeaponInRange
        end
    else
        local targetRadius = tonumber(spell.targetRadius)
        if targetRadius then
            if distanceToTarget <= targetRadius then
                weight = weight + archetypeWeights.spellInRange
            end
        else
            debugPrint("Target radius didn't convert to number, what is this?")
            debugPrint(spell.targetRadius)
        end
    end
    -- Favor using spells or non-spells?
    if spell.isSpell then
        weight = weight + archetypeWeights.isSpell
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

-- NB need to allow healing, buffs, debuffs etc for companions too
local function isCompanionSpellAvailable(uuid, spellName, spell, isSilenced, distanceToTarget, targetDistanceToParty, allowAoE)
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
        if distanceToTarget > range and targetDistanceToParty > (range + State.Settings.DefensiveTacticsMaxDistance) then
            return false
        end
    end
    return true
end

local function isNpcSpellUsable(spell)
    if spell == "Projectile_Jump" then return false end
    if spell == "Shout_Dash_NPC" then return false end
    if spell == "Target_Shove" then return false end
    if spell == "Target_Devour_Ghoul" then return false end
    if spell == "Target_Devour_ShadowMound" then return false end
    if spell == "Target_LOW_RamazithsTower_Nightsong_Globe_1" then return false end
    if spell == "Target_Dip_NPC" then return false end
    if spell == "Projectile_SneakAttack" then return false end
    if spell == "Rush_Charger_Push" then return false end
    return true
end

local function isEnemySpellAvailable(uuid, spellName, spell, isSilenced)
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
    if not State.Settings.HogwildMode then
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
local function getCompanionWeightedSpells(uuid, preparedSpells, distanceToTarget, archetype, spellTypes, numExtraAttacks, targetDistanceToParty, allowAoE)
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
            if isCompanionSpellAvailable(uuid, spellName, spell, silenced, distanceToTarget, targetDistanceToParty, allowAoE) then
                -- print("get spell weight for", uuid, spellName, spell, distanceToTarget, archetype, spellType, numExtraAttacks)
                weightedSpells[spellName] = getSpellWeight(spell, distanceToTarget, archetype, spellType, numExtraAttacks)
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
local function getWeightedSpells(uuid, preparedSpells, distanceToTarget, archetype, spellTypes, numExtraAttacks)
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
                weightedSpells[spellName] = getSpellWeight(spell, distanceToTarget, archetype, spellType, numExtraAttacks)
            end
        end
    end
    return weightedSpells
end

local function decideCompanionActionOnTarget(brawler, preparedSpells, distanceToTarget, spellTypes, targetDistanceToParty, allowAoE)
    local weightedSpells = getCompanionWeightedSpells(brawler.uuid, preparedSpells, distanceToTarget, brawler.archetype, spellTypes, brawler.numExtraAttacks, targetDistanceToParty, allowAoE)
    debugPrint("companion weighted spells", getDisplayName(brawler.uuid), brawler.archetype, distanceToTarget)
    debugDump(Constants.ARCHETYPE_WEIGHTS[brawler.archetype])
    debugDump(weightedSpells)
    return getHighestWeightSpell(weightedSpells)
end

local function decideActionOnTarget(brawler, preparedSpells, distanceToTarget, spellTypes)
    local weightedSpells = getWeightedSpells(brawler.uuid, preparedSpells, distanceToTarget, brawler.archetype, spellTypes, brawler.numExtraAttacks)
    return getHighestWeightSpell(weightedSpells)
end

local function useSpellOnTarget(attackerUuid, targetUuid, spellName)
    debugPrint("useSpellOnTarget", attackerUuid, targetUuid, spellName)
    if State.Settings.HogwildMode then
        Osi.UseSpell(attackerUuid, spellName, targetUuid)
    else
        Resources.useSpellAndResources(attackerUuid, targetUuid, spellName)
    end
end

local function actOnHostileTarget(brawler, target)
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
        if not actionToTake and Osi.IsPlayer(brawler.uuid) == 0 then
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
        Movement.moveIntoPositionForSpell(brawler.uuid, target.uuid, actionToTake)
        if actionToTake then
            useSpellOnTarget(brawler.uuid, target.uuid, actionToTake)
        else
            Osi.Attack(brawler.uuid, target.uuid, 0)
        end
        return true
    end
    return false
end

local function actOnFriendlyTarget(brawler, target)
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
        if actionToTake then
            Movement.moveIntoPositionForSpell(brawler.uuid, target.uuid, actionToTake)
            useSpellOnTarget(brawler.uuid, target.uuid, actionToTake)
            return true
        end
        return false
    end
    return false
end

local function getOffenseWeightedTarget(distanceToTarget, targetHp, targetHpPct, canSeeTarget, isHealer, isHostile)
    if not isHostile and targetHpPct == 100.0 then
        return nil
    -- else
    --     return nil
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

local function getBalancedWeightedTarget(distanceToTarget, targetHp, targetHpPct, canSeeTarget, isHealer, isHostile, attackerUuid, targetUuid, anchorCharacterUuid)
    if not isHostile and targetHpPct == 100.0 then
        return nil
    end
    if not anchorCharacterUuid then
        debugPrint("(Balanced) Anchor character not found, reverting to Offense weighting")
        return getOffenseWeightedTarget(distanceToTarget, targetHp, canSeeTarget, isHealer, isHostile)
    end
    local weightedTarget
    local targetDistanceToParty = Osi.GetDistanceTo(targetUuid, anchorCharacterUuid)
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
    end
    return weightedTarget
end

local function getDefenseWeightedTarget(distanceToTarget, targetHp, targetHpPct, canSeeTarget, isHealer, isHostile, attackerUuid, targetUuid, anchorCharacterUuid)
    if not isHostile and targetHpPct == 100.0 then
        return nil
    end
    if not anchorCharacterUuid then
        debugPrint("(Defense) Anchor character not found, reverting to Offense weighting")
        return getOffenseWeightedTarget(distanceToTarget, targetHp, canSeeTarget, isHealer, isHostile)
    end
    local weightedTarget
    local targetDistanceToAnchor = Osi.GetDistanceTo(targetUuid, anchorCharacterUuid)
    -- Only include potential targets that are within X meters of the player
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
    end
    return weightedTarget
end

local function isHostileTarget(uuid, targetUuid)
    local isBrawlerPlayerOrAlly = isPlayerOrAlly(uuid)
    local isPotentialTargetPlayerOrAlly = isPlayerOrAlly(targetUuid)
    local isHostile = false
    if isBrawlerPlayerOrAlly and isPotentialTargetPlayerOrAlly then
        isHostile = false
    elseif isBrawlerPlayerOrAlly and not isPotentialTargetPlayerOrAlly then
        isHostile = Osi.IsEnemy(uuid, targetUuid) == 1 or State.Session.IsAttackingOrBeingAttackedByPlayer[targetUuid] ~= nil
    elseif not isBrawlerPlayerOrAlly and isPotentialTargetPlayerOrAlly then
        isHostile = Osi.IsEnemy(uuid, targetUuid) == 1 or State.Session.IsAttackingOrBeingAttackedByPlayer[uuid] ~= nil
    elseif not isBrawlerPlayerOrAlly and not isPotentialTargetPlayerOrAlly then
        isHostile = Osi.IsEnemy(uuid, targetUuid) == 1
    else
        debugPrint("isHostileTarget: what happened here?", uuid, targetUuid, getDisplayName(uuid), getDisplayName(targetUuid))
    end
    return isHostile
end

local function whoNeedsHealing(uuid, level)
    local minTargetHpPct = 100.0
    local friendlyTargetUuid = nil
    local brawlersInLevel = State.Session.Brawlers[level]
    for targetUuid, target in pairs(brawlersInLevel) do
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

-- Attacking targets: prioritize close targets with less remaining HP
-- (Lowest weight = most desireable target)
local function getWeightedTargets(brawler, potentialTargets)
    local weightedTargets = {}
    local isHealer = isHealerArchetype(brawler.archetype)
    local anchorCharacterUuid
    if isPlayerOrAlly(brawler.uuid) then
        if State.Settings.CompanionTactics == "Balanced" then
            anchorCharacterUuid = Osi.GetClosestAlivePlayer(brawler.uuid)
            if anchorCharacterUuid == nil then
                anchorCharacterUuid = Osi.GetHostCharacter()
            end
        elseif State.Settings.CompanionTactics == "Defense" then
            if State.Session.Players and State.Session.Players[brawler.uuid] and State.Session.Players[brawler.uuid].userId then
                local player = State.getPlayerByUserId(State.Session.Players[brawler.uuid].userId)
                if player then
                    anchorCharacterUuid = player.uuid
                end
            end
            if anchorCharacterUuid == nil then
                anchorCharacterUuid = Osi.GetHostCharacter()
            end
        end
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
                            weightedTargets[potentialTargetUuid] = getDefenseWeightedTarget(distanceToTarget, targetHp, targetHpPct, canSeeTarget, isHealer, isHostile, brawler.uuid, potentialTargetUuid, anchorCharacterUuid)
                        else
                            weightedTargets[potentialTargetUuid] = getBalancedWeightedTarget(distanceToTarget, targetHp, targetHpPct, canSeeTarget, isHealer, isHostile, brawler.uuid, potentialTargetUuid, anchorCharacterUuid)
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

local function getBrawlersSortedByDistance(entityUuid)
    local brawlersSortedByDistance = {}
    local level = Osi.GetRegion(entityUuid)
    local brawlersInLevel = State.Session.Brawlers[level]
    if brawlersInLevel then
        for brawlerUuid, brawler in pairs(brawlersInLevel) do
            if isOnSameLevel(brawlerUuid, entityUuid) and isAliveAndCanFight(brawlerUuid) then
                table.insert(brawlersSortedByDistance, {brawlerUuid, Osi.GetDistanceTo(entityUuid, brawlerUuid)})
            end
        end
        table.sort(brawlersSortedByDistance, function (a, b) return a[2] < b[2] end)
    end
    return brawlersSortedByDistance
end

local function findTarget(brawler)
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
                debugPrint("result (hostile)", result)
                if result == true then
                    brawler.targetUuid = targetUuid
                end
            else
                result = actOnFriendlyTarget(brawler, State.Session.Brawlers[level][targetUuid])
                debugPrint("result (friendly)", result)
            end
            if result == true then
                return true
            end
        end
        debugPrint("can't find a target, holding position", brawler.uuid, brawler.displayName)
        Movement.holdPosition(brawler.uuid)
        return false
    end
end

-- Enemies are pugnacious jerks and looking for a fight >:(
local function checkForBrawlToJoin(brawler)
    local closestPlayerUuid, closestDistance = Osi.GetClosestAlivePlayer(brawler.uuid)
    if closestPlayerUuid ~= nil and closestDistance ~= nil and closestDistance < Constants.ENTER_COMBAT_RANGE then
        debugPrint("Closest alive player to", brawler.uuid, brawler.displayName, "is", closestPlayerUuid, closestDistance)
        Roster.addBrawler(closestPlayerUuid)
        local players = State.Session.Players
        for playerUuid, player in pairs(players) do
            if playerUuid ~= closestPlayerUuid then
                local distanceTo = Osi.GetDistanceTo(brawler.uuid, playerUuid)
                if distanceTo < Constants.ENTER_COMBAT_RANGE then
                    Roster.addBrawler(playerUuid)
                end
            end
        end
        local level = Osi.GetRegion(brawler.uuid)
        -- if level and State.Session.BrawlFizzler[level] == nil then
        --     print("check for brawl to join: start fizz")
        --     startBrawlFizzler(level)
        -- end
        startPulseAction(brawler)
    end
end

-- Brawlers doing dangerous stuff
local function pulseAction(brawler)
    -- Brawler is alive and able to fight: let's go!
    if brawler and brawler.uuid then
        local level = Osi.GetRegion(brawler.uuid)
        if level and not brawler.isPaused and isAliveAndCanFight(brawler.uuid) and (not isPlayerControllingDirectly(brawler.uuid) or State.Settings.FullAuto) then
            -- NB: if we allow healing spells etc used by companions, roll this code in, instead of special-casing it here...
            if isPlayerOrAlly(brawler.uuid) then
                local players = State.Session.Players
                for playerUuid, player in pairs(players) do
                    if not player.isBeingHelped and brawler.uuid ~= playerUuid and isDowned(playerUuid) and Osi.GetDistanceTo(playerUuid, brawler.uuid) < Constants.HELP_DOWNED_MAX_RANGE then
                        player.isBeingHelped = true
                        brawler.targetUuid = nil
                        debugPrint("Helping target", playerUuid, getDisplayName(playerUuid))
                        Movement.moveIntoPositionForSpell(brawler.uuid, playerUuid, "Target_Help")
                        return useSpellOnTarget(brawler.uuid, playerUuid, "Target_Help")
                    end
                end
            else
                Roster.addPlayersInEnterCombatRangeToBrawlers(brawler.uuid)
            end
            -- Doesn't currently have an attack target, so let's find one
            if brawler.targetUuid == nil then
                debugPrint("Find target (no current target)", brawler.uuid, brawler.displayName)
                return findTarget(brawler)
            end
            -- We have a target and the target is alive
            local brawlersInLevel = State.Session.Brawlers[level]
            if brawlersInLevel and isOnSameLevel(brawler.uuid, brawler.targetUuid) and brawlersInLevel[brawler.targetUuid] and isAliveAndCanFight(brawler.targetUuid) and isVisible(brawler.targetUuid) then
                if brawler.lockedOnTarget then
                    debugPrint("Locked-on target, attacking", brawler.displayName, brawler.uuid, "->", getDisplayName(brawler.targetUuid))
                    return actOnHostileTarget(brawler, brawlersInLevel[brawler.targetUuid])
                end
                if isPlayerOrAlly(brawler.uuid) and State.Settings.CompanionTactics == "Defense" then
                    debugPrint("Find target (defense tactics)", brawler.uuid, brawler.displayName)
                    return findTarget(brawler)
                end
                if Osi.GetDistanceTo(brawler.uuid, brawler.targetUuid) <= 12 then
                    debugPrint("Remaining on target, attacking", brawler.displayName, brawler.uuid, "->", getDisplayName(brawler.targetUuid))
                    return actOnHostileTarget(brawler, brawlersInLevel[brawler.targetUuid])
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

-- Reposition the NPC relative to the player.  This is the only place that NPCs should enter the brawl.
local function pulseReposition(level, skipCompanions)
    State.checkForDownedOrDeadPlayers()
    if State.Session.Brawlers[level] then
        local brawlersInLevel = State.Session.Brawlers[level]
        for brawlerUuid, brawler in pairs(brawlersInLevel) do
            if not Constants.IS_TRAINING_DUMMY[brawlerUuid] then
                if isAliveAndCanFight(brawlerUuid) then
                    -- Enemy units are actively looking for a fight and will attack if you get too close to them
                    if isPugnacious(brawlerUuid) then
                        if brawler.isInBrawl and brawler.targetUuid ~= nil and isAliveAndCanFight(brawler.targetUuid) then
                            debugPrint("Repositioning", brawler.displayName, brawlerUuid, "->", brawler.targetUuid)
                            -- Movement.repositionRelativeToTarget(brawlerUuid, brawler.targetUuid)
                            local playerUuid, closestDistance = Osi.GetClosestAlivePlayer(brawlerUuid)
                            if closestDistance > 2*Constants.ENTER_COMBAT_RANGE then
                                debugPrint("Too far away, removing brawler", brawlerUuid, getDisplayName(brawlerUuid))
                                Roster.removeBrawler(level, brawlerUuid)
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
                        if State.Session.Players[brawlerUuid] and (isPlayerControllingDirectly(brawlerUuid) and not State.Settings.FullAuto) then
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
                                -- Movement.repositionRelativeToTarget(brawlerUuid, brawler.targetUuid)
                            end
                        end
                    end
                elseif Osi.IsDead(brawlerUuid) == 1 or isDowned(brawlerUuid) then
                    clearOsirisQueue(brawlerUuid)
                    Osi.LieOnGround(brawlerUuid)
                end
            end
        end
    end
end

local function pulseAddNearby(uuid)
    Roster.addNearbyEnemiesToBrawlers(uuid, 30)
end

return {
    actOnHostileTarget = actOnHostileTarget,
    actOnFriendlyTarget = actOnFriendlyTarget,
    findTarget = findTarget,
    pulseAction = pulseAction,
    pulseReposition = pulseReposition,
    pulseAddNearby = pulseAddNearby,
}
