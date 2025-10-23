local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump
local isPlayerControllingDirectly = State.isPlayerControllingDirectly
local clearOsirisQueue = Utils.clearOsirisQueue
local isToT = Utils.isToT

-- thank u focus and mazzle
-- cache values so we don't have to get from stats
local function queueSpellRequest(casterUuid, spellName, targetUuid, castOptions, insertAtFront)
    local stats = Ext.Stats.Get(spellName)
    if not castOptions then
        castOptions = {"IgnoreHasSpell", "ShowPrepareAnimation", "AvoidDangerousAuras", "IgnoreTargetChecks"}
        if State.Settings.TurnBasedSwarmMode then
            table.insert(castOptions, "NoMovement")
        end
    end
    local casterEntity = Ext.Entity.Get(casterUuid)
    local request = {
        CastOptions = castOptions,
        CastPosition = nil,
        Item = nil,
        Caster = casterEntity,
        NetGuid = "",
        Originator = {
            ActionGuid = Constants.NULL_UUID,
            CanApplyConcentration = true,
            InterruptId = "",
            PassiveId = "",
            Statusid = "",
        },
        RequestGuid = Utils.createUuid(),
        Spell = {
            OriginatorPrototype = M.Utils.getOriginatorPrototype(spellName, stats),
            ProgressionSource = Constants.NULL_UUID,
            Prototype = spellName,
            Source = Constants.NULL_UUID,
            SourceType = "Osiris",
        },
        StoryActionId = 0,
        Targets = {{
            Position = nil,
            Target = Ext.Entity.Get(targetUuid),
            Target2 = nil,
            TargetProxy = nil,
            TargetingType = stats.SpellType,
        }},
        field_70 = nil,
        field_A8 = 1,
    }
    local queuedRequests = Ext.System.ServerCastRequest.OsirisCastRequests
    local isPausedRequest = State.Settings.TruePause and Pause.isInFTB(casterEntity)
    if insertAtFront or isPausedRequest then
        for i = #queuedRequests, 1, -1 do
            queuedRequests[i + 1] = queuedRequests[i]
        end
        queuedRequests[1] = request
    else
        queuedRequests[#queuedRequests + 1] = request
    end
    -- print(M.Utils.getDisplayName(casterUuid), "insert cast request", #queuedRequests, spellName, M.Utils.getDisplayName(targetUuid), isPausedRequest, Pause.isLocked(casterEntity))
    return request.RequestGuid
end

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
local function getSpellWeight(spellName, spell, distanceToTarget, hasLineOfSight, archetype, spellType, numExtraAttacks, targetUuid)
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
        local resistanceWeight = M.AI.getResistanceWeight(spell, targetUuid)
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
        if spell.hasApplyStatus then
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
        if distanceToTarget <= Constants.MELEE_RANGE then
            weight = weight + archetypeWeights.meleeWeaponInRange
        end
    else
        if spell.targetRadius == "RangedMainWeaponRange" then
            weight = weight + archetypeWeights.rangedWeapon
            if distanceToTarget > Constants.RANGED_RANGE_MIN and distanceToTarget < Constants.RANGED_RANGE_MAX then
                weight = weight + archetypeWeights.rangedWeaponInRange
            else
                weight = weight + archetypeWeights.rangedWeaponOutOfRange
            end
        -- NB: should the weights be different from ranged and thrown (e.g. tavern brawler spec)?
        elseif spell.targetRadius == "ThrownObjectRange" then
            weight = weight + archetypeWeights.rangedWeapon
            if distanceToTarget > Constants.THROWN_RANGE_MIN and distanceToTarget < Constants.THROWN_RANGE_MAX then
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

-- NB need to allow healing, buffs, debuffs etc for companions too
local function isCompanionSpellAvailable(uuid, targetUuid, spellName, spell, isSilenced, distanceToTarget, targetDistanceToParty, allowAoE, bonusActionOnly)
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
        if not allowAoE and spell.type == "Damage" and (spell.areaRadius > 0 or M.Utils.isZoneSpell(spellName)) then
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
        local range = M.Utils.convertSpellRangeToNumber(M.Utils.getSpellRange(spellName))
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

local function isEnemySpellAvailable(uuid, targetUuid, spellName, spell, isSilenced, bonusActionOnly)
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
local function getCompanionWeightedSpells(uuid, targetUuid, preparedSpells, distanceToTarget, archetype, spellTypes, numExtraAttacks, targetDistanceToParty, allowAoE, bonusActionOnly)
    local weightedSpells = {}
    local silenced = M.Utils.isSilenced(uuid)
    local hasLineOfSight = M.Osi.HasLineOfSight(uuid, targetUuid) == 1
    for _, preparedSpell in pairs(preparedSpells) do
        local spellName = preparedSpell.OriginatorPrototype
        if M.AI.isNpcSpellUsable(spellName) then
            local spell = nil
            for _, spellType in ipairs(spellTypes) do
                spell = State.Session.SpellTable[spellType][spellName]
                if spell ~= nil then
                    break
                end
            end
            if isCompanionSpellAvailable(uuid, targetUuid, spellName, spell, silenced, distanceToTarget, targetDistanceToParty, allowAoE, bonusActionOnly) then
                debugPrint("Companion get spell weight for", spellName, distanceToTarget, archetype, spell.type, numExtraAttacks)
                weightedSpells[spellName] = getSpellWeight(spellName, spell, distanceToTarget, hasLineOfSight, archetype, spell.type, numExtraAttacks, targetUuid)
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
local function getWeightedSpells(uuid, targetUuid, preparedSpells, distanceToTarget, archetype, spellTypes, numExtraAttacks, bonusActionOnly)
    local weightedSpells = {}
    local silenced = M.Utils.isSilenced(uuid)
    local hasLineOfSight = M.Osi.HasLineOfSight(uuid, targetUuid) == 1
    for _, preparedSpell in pairs(preparedSpells) do
        local spellName = preparedSpell.OriginatorPrototype
        if M.AI.isNpcSpellUsable(spellName) then
            local spell = nil
            for _, spellType in ipairs(spellTypes) do
                spell = State.Session.SpellTable[spellType][spellName]
                if spell ~= nil then
                    break
                end
            end
            if isEnemySpellAvailable(uuid, targetUuid, spellName, spell, silenced, bonusActionOnly) then
                weightedSpells[spellName] = getSpellWeight(spellName, spell, distanceToTarget, hasLineOfSight, archetype, spell.type, numExtraAttacks, targetUuid)
            end
        end
    end
    return weightedSpells
end

local function decideCompanionActionOnTarget(brawler, targetUuid, preparedSpells, distanceToTarget, spellTypes, targetDistanceToParty, allowAoE, bonusActionOnly)
    local weightedSpells = getCompanionWeightedSpells(brawler.uuid, targetUuid, preparedSpells, distanceToTarget, brawler.archetype, spellTypes, brawler.numExtraAttacks, targetDistanceToParty, allowAoE, bonusActionOnly)
    debugPrint(brawler.displayName, "companion weighted spells", brawler.uuid, brawler.archetype, distanceToTarget, bonusActionOnly)
    -- debugDump(Constants.ARCHETYPE_WEIGHTS[brawler.archetype])
    debugDump(weightedSpells)
    return getHighestWeightSpell(weightedSpells)
end

local function decideActionOnTarget(brawler, targetUuid, preparedSpells, distanceToTarget, spellTypes, bonusActionOnly)
    local weightedSpells = getWeightedSpells(brawler.uuid, targetUuid, preparedSpells, distanceToTarget, brawler.archetype, spellTypes, brawler.numExtraAttacks, bonusActionOnly)
    debugPrint(brawler.displayName, "enemy weighted spells", brawler.uuid, brawler.archetype, distanceToTarget, bonusActionOnly)
    debugDump(weightedSpells)
    return getHighestWeightSpell(weightedSpells)
end

local function useSpellOnTarget(attackerUuid, targetUuid, spellName, onSuccess, onFailed)
    debugPrint(M.Utils.getDisplayName(attackerUuid), "useSpellOnTarget", attackerUuid, targetUuid, spellName)
    -- TODO callbacks
    if State.Settings.HogwildMode then
        Osi.UseSpell(attackerUuid, spellName, targetUuid)
        return true
    end
    return Resources.useSpellAndResources(attackerUuid, targetUuid, spellName, onSuccess, onFailed)
end

local function actOnHostileTarget(brawler, target, bonusActionOnly, onSuccess, onFailed)
    local distanceToTarget = M.Osi.GetDistanceTo(brawler.uuid, target.uuid)
    if brawler and target then
        local actionToTake = nil
        local spellTypes = {"Control", "Damage"}
        local preparedSpells = Ext.Entity.Get(brawler.uuid).SpellBookPrepares.PreparedSpells
        if M.Osi.IsPlayer(brawler.uuid) == 1 then
            local allowAoE = M.Osi.HasPassive(brawler.uuid, "SculptSpells") == 1
            local playerClosestToTarget = M.Osi.GetClosestAlivePlayer(target.uuid) or brawler.uuid
            local targetDistanceToParty = M.Osi.GetDistanceTo(target.uuid, playerClosestToTarget)
            -- debugPrint("target distance to party", targetDistanceToParty, playerClosestToTarget)
            actionToTake = decideCompanionActionOnTarget(brawler, target.uuid, preparedSpells, distanceToTarget, {"Damage"}, targetDistanceToParty, allowAoE, bonusActionOnly)
            debugPrint(brawler.displayName, "Companion action to take on hostile target", actionToTake, brawler.uuid, target.uuid, target.displayName, bonusActionOnly)
        else
            actionToTake = decideActionOnTarget(brawler, target.uuid, preparedSpells, distanceToTarget, spellTypes, bonusActionOnly)
            debugPrint(brawler.displayName, "Action to take on hostile target", actionToTake, brawler.uuid, target.uuid, target.displayName, brawler.archetype, bonusActionOnly)
        end
        if not actionToTake then
            debugPrint("No hostile actions available for", brawler.uuid, brawler.displayName, bonusActionOnly)
            if M.Osi.IsPlayer(brawler.uuid) == 0 and not State.Settings.TurnBasedSwarmMode then
                local numUsableSpells = 0
                local usableSpells = {}
                for _, preparedSpell in pairs(preparedSpells) do
                    local spellName = preparedSpell.OriginatorPrototype
                    if M.AI.isNpcSpellUsable(spellName) then
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
                debugPrint(brawler.displayName, "backup ActionToTake", actionToTake, numUsableSpells)
            else
                return onFailed()
            end
        end
        Movement.moveIntoPositionForSpell(brawler.uuid, target.uuid, actionToTake, bonusActionOnly, function ()
            debugPrint(brawler.displayName, "onMovementCompleted", target.displayName, actionToTake)
            useSpellOnTarget(brawler.uuid, target.uuid, actionToTake, function ()
                print(brawler.displayName, "success (hostile)", bonusActionOnly)
                if not bonusActionOnly then
                    brawler.targetUuid = targetUuid
                end
                onSuccess()
            end, onFailed)
        end)
        return onSuccess()
    end
    return onFailed()
end

local function actOnFriendlyTarget(brawler, target, bonusActionOnly, onSuccess, onFailed)
    local distanceToTarget = M.Osi.GetDistanceTo(brawler.uuid, target.uuid)
    local preparedSpells = Ext.Entity.Get(brawler.uuid).SpellBookPrepares.PreparedSpells
    if preparedSpells ~= nil then
        -- todo: Utility/Buff spells
        debugPrint(brawler.displayName, "acting on friendly target", brawler.uuid, target.displayName, bonusActionOnly)
        local spellTypes = {"Healing"}
        if brawler.uuid == target.uuid and not M.State.hasDirectHeal(brawler.uuid, preparedSpells, false, bonusActionOnly) then
            debugPrint(brawler.displayName, "No direct heals found (self)", bonusActionOnly)
            return onFailed()
            -- return false
        end
        if brawler.uuid ~= target.uuid and not M.State.hasDirectHeal(brawler.uuid, preparedSpells, true, bonusActionOnly) then
            debugPrint(brawler.displayName, "No direct heals found (other)", bonusActionOnly)
            return onFailed()
            -- return false
        end
        local actionToTake = nil
        if M.Osi.IsPlayer(brawler.uuid) == 1 then
            actionToTake = decideCompanionActionOnTarget(brawler, target.uuid, preparedSpells, distanceToTarget, spellTypes, 0, true, bonusActionOnly)
        else
            actionToTake = decideActionOnTarget(brawler, target.uuid, preparedSpells, distanceToTarget, spellTypes, bonusActionOnly)
        end
        debugPrint(brawler.displayName, "Action to take on friendly target", actionToTake, brawler.uuid, bonusActionOnly)
        if actionToTake then
            Movement.moveIntoPositionForSpell(brawler.uuid, target.uuid, actionToTake, bonusActionOnly, function ()
                useSpellOnTarget(brawler.uuid, target.uuid, actionToTake, function ()
                    print(brawler.displayName, "success (friendly)", bonusActionOnly)
                    onSuccess()
                end, onFailed)
            end)
            -- return true
        elseif bonusActionOnly then
            debugPrint(brawler.displayName, "No friendly bonus actions available for", brawler.uuid, bonusActionOnly)
            -- return true
            return onSuccess()
        end
        return onFailed()
        -- return false
    end
    return onFailed()
end

local function getOffenseWeightedTarget(distanceToTarget, targetHp, targetHpPct, canSeeTarget, isHealer, isHostile, isMelee, hasPathToTarget)
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
        if M.Utils.isOnSameLevel(uuid, targetUuid) and M.Osi.IsAlly(uuid, targetUuid) == 1 then
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
local function getWeightedTargets(brawler, potentialTargets, bonusActionOnly)
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
            if M.Utils.isAliveAndCanFight(potentialTargetUuid) or M.Utils.isDowned(potentialTargetUuid) then
                if brawler.uuid == potentialTargetUuid then
                    local preparedSpells = Ext.Entity.Get(brawler.uuid).SpellBookPrepares.PreparedSpells
                    if M.State.hasDirectHeal(brawler.uuid, preparedSpells, false, bonusActionOnly) then
                        local targetHp = M.Osi.GetHitpoints(potentialTargetUuid)
                        local targetHpPct = M.Osi.GetHitpointsPercentage(potentialTargetUuid)
                        if State.Settings.CompanionTactics == "Offense" then
                            weightedTarget = getOffenseWeightedTarget(0, targetHp, targetHpPct, true, isHealer, false, nil, nil)
                        elseif State.Settings.CompanionTactics == "Defense" then
                            weightedTarget = getDefenseWeightedTarget(0, targetHp, targetHpPct, true, isHealer, false, nil, nil, brawler.uuid, potentialTargetUuid, anchorCharacterUuid)
                        else
                            weightedTarget = getBalancedWeightedTarget(0, targetHp, targetHpPct, true, isHealer, false, nil, nil, brawler.uuid, potentialTargetUuid, anchorCharacterUuid)
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
                    print(ableToTarget, State.Session.ActiveCombatGroups[brawler.combatGroupId], State.Session.IsAttackingOrBeingAttackedByPlayer[potentialTargetUuid])
                    if isToT() or ableToTarget or State.Session.ActiveCombatGroups[brawler.combatGroupId] or State.Session.IsAttackingOrBeingAttackedByPlayer[potentialTargetUuid] then
                        local hasPathToTarget = nil
                        if (isHostile and M.Utils.isValidHostileTarget(brawler.uuid, potentialTargetUuid)) or (M.State.hasDirectHeal(brawler.uuid, Ext.Entity.Get(brawler.uuid).SpellBookPrepares.PreparedSpells, true, bonusActionOnly)) then
                            if isMelee and isHostile then
                                hasPathToTarget = M.Movement.findPathToTargetUuid(brawler.uuid, potentialTargetUuid)
                            end
                            debugPrint(brawler.displayName, "Is Hostile Target, Is Melee, has path to target?", isHostile, isMelee, hasPathToTarget, M.Utils.isPlayerOrAlly(brawler.uuid))
                            local targetHp = M.Osi.GetHitpoints(potentialTargetUuid)
                            local targetHpPct = M.Osi.GetHitpointsPercentage(potentialTargetUuid)
                            if not M.Utils.isPlayerOrAlly(brawler.uuid) then --or State.Settings.TurnBasedSwarmMode then
                                weightedTarget = getOffenseWeightedTarget(distanceToTarget, targetHp, targetHpPct, canSeeTarget, isHealer, isHostile, isMelee, hasPathToTarget)
                                debugPrint(brawler.displayName, "Got offense weighted target", M.Utils.getDisplayName(potentialTargetUuid), weightedTarget)
                                if brawler.combatGroupId ~= nil then
                                    State.Session.ActiveCombatGroups[brawler.combatGroupId] = true
                                end
                            else
                                if State.Settings.CompanionTactics == "Offense" then
                                    weightedTarget = getOffenseWeightedTarget(distanceToTarget, targetHp, targetHpPct, canSeeTarget, isHealer, isHostile, isMelee, hasPathToTarget)
                                elseif State.Settings.CompanionTactics == "Defense" then
                                    weightedTarget = getDefenseWeightedTarget(distanceToTarget, targetHp, targetHpPct, canSeeTarget, isHealer, isHostile, isMelee, hasPathToTarget, brawler.uuid, potentialTargetUuid, anchorCharacterUuid)
                                else
                                    weightedTarget = getBalancedWeightedTarget(distanceToTarget, targetHp, targetHpPct, canSeeTarget, isHealer, isHostile, isMelee, hasPathToTarget, brawler.uuid, potentialTargetUuid, anchorCharacterUuid)
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

local function findTarget(brawler, bonusActionOnly, onSuccess, onFailed)
    local level = M.Osi.GetRegion(brawler.uuid)
    if level then
        local brawlersSortedByDistance = M.Roster.getBrawlersSortedByDistance(brawler.uuid)
        -- Healing
        local isPlayer = M.Osi.IsPlayer(brawler.uuid) == 1
        local wasHealRequested = false
        local userId
        if isPlayer then
            userId = Osi.GetReservedUserID(brawler.uuid)
            wasHealRequested = State.Session.HealRequested[userId]
        end
        local brawlersInLevel = State.Session.Brawlers[level]
        if wasHealRequested then
            if brawlersInLevel then
                local friendlyTargetUuid = M.AI.whoNeedsHealing(brawler.uuid, level)
                if friendlyTargetUuid and brawlersInLevel[friendlyTargetUuid] then
                    debugPrint(brawler.displayName, "actOnFriendlyTarget", brawler.uuid, friendlyTargetUuid, M.Utils.getDisplayName(friendlyTargetUuid), bonusActionOnly)
                    actOnFriendlyTarget(brawler, brawlersInLevel[friendlyTargetUuid], bonusActionOnly, function ()
                        State.Session.HealRequested[userId] = false
                        onSuccess()
                    end, onFailed)
                end
            end
        end
        if brawlersInLevel then
            local weightedTargets = getWeightedTargets(brawler, brawlersInLevel)
            local targetUuid = decideOnTarget(weightedTargets)
            if targetUuid then
                local targetBrawler = brawlersInLevel[targetUuid]
                if targetBrawler then
                    local result
                    if M.Utils.isHostileTarget(brawler.uuid, targetUuid) then
                        actOnHostileTarget(brawler, targetBrawler, bonusActionOnly, onSuccess, onFailed)
                    else
                        actOnFriendlyTarget(brawler, targetBrawler, bonusActionOnly, onSuccess, onFailed)
                    end
                    -- if result == true then
                    --     return true
                    -- end
                end
            end
            debugDump(weightedTargets)
        end
        if not bonusActionOnly then
            print(brawler.displayName, "can't find a target, holding position", brawler.uuid, bonusActionOnly)
            Movement.holdPosition(brawler.uuid)
        end
        -- return false
        return onFailed()
    end
end

-- Enemies are pugnacious jerks and looking for a fight >:(
local function checkForBrawlToJoin(brawler)
    local closestPlayerUuid, closestDistance = M.Osi.GetClosestAlivePlayer(brawler.uuid)
    local enterCombatRange = Constants.ENTER_COMBAT_RANGE
    if State.Settings.TurnBasedSwarmMode then
        enterCombatRange = 30
    end
    if closestPlayerUuid ~= nil and closestDistance ~= nil and closestDistance < enterCombatRange then
        debugPrint(brawler.displayName, "Closest alive player to", brawler.uuid, "is", closestPlayerUuid, closestDistance)
        Roster.addBrawler(closestPlayerUuid)
        local players = State.Session.Players
        for playerUuid, player in pairs(players) do
            if playerUuid ~= closestPlayerUuid then
                local distanceTo = M.Osi.GetDistanceTo(brawler.uuid, playerUuid)
                if distanceTo < enterCombatRange then
                    Roster.addBrawler(playerUuid)
                end
            end
        end
        -- local level = M.Osi.GetRegion(brawler.uuid)
        -- if level and State.Session.BrawlFizzler[level] == nil then
        --     debugPrint("check for brawl to join: start fizz")
        --     startBrawlFizzler(level)
        -- end
        debugPrint("check for", brawler.uuid, brawler.displayName)
        startPulseAction(brawler)
    end
end

local function act(brawler, bonusActionOnly, onSuccess, onFailed)
    if brawler and brawler.uuid then
        -- NB: should this change depending on offensive/defensive tactics? should this be a setting to enable disable?
        --     should this generally be handled by the healing logic, instead of special-casing it here?
        if M.Utils.isPlayerOrAlly(brawler.uuid) and not bonusActionOnly then
            local players = State.Session.Players
            for playerUuid, player in pairs(players) do
                if not player.isBeingHelped and brawler.uuid ~= playerUuid and M.Utils.isDowned(playerUuid) and M.Osi.GetDistanceTo(playerUuid, brawler.uuid) < Constants.HELP_DOWNED_MAX_RANGE then
                    player.isBeingHelped = true
                    brawler.targetUuid = nil
                    debugPrint(brawler.displayName, "Helping target", playerUuid, M.Utils.getDisplayName(playerUuid))
                    return Movement.moveIntoPositionForSpell(brawler.uuid, playerUuid, "Target_Help", bonusActionOnly, function ()
                        useSpellOnTarget(brawler.uuid, playerUuid, "Target_Help", onSuccess, onFailed)
                    end)
                end
            end
        end
        -- Doesn't currently have an attack target, so let's find one
        if brawler.targetUuid == nil then
            debugPrint(brawler.displayName, "Find target (no current target)", brawler.uuid, bonusActionOnly)
            return findTarget(brawler, bonusActionOnly, onSuccess, onFailed)
        end
        -- We have a target and the target is alive
        local brawlersInLevel = State.Session.Brawlers[M.Osi.GetRegion(brawler.uuid)]
        if brawlersInLevel and brawlersInLevel[brawler.targetUuid] and M.Utils.isAliveAndCanFight(brawler.targetUuid) and M.Utils.isVisible(brawler.uuid, brawler.targetUuid) then
            if not State.Settings.TurnBasedSwarmMode or M.Movement.findPathToTargetUuid(brawler.uuid, brawler.targetUuid) then
                if brawler.lockedOnTarget and M.Utils.isValidHostileTarget(brawler.uuid, brawler.targetUuid) then
                    debugPrint(brawler.displayName, "Locked-on target, attacking", M.Utils.getDisplayName(brawler.targetUuid), bonusActionOnly)
                    return actOnHostileTarget(brawler, brawlersInLevel[brawler.targetUuid], bonusActionOnly, onSuccess, onFailed)
                end
                if M.Utils.isPlayerOrAlly(brawler.uuid) and State.Settings.CompanionTactics == "Defense" then
                    debugPrint(brawler.displayName, "Find target (defense tactics)", brawler.uuid, bonusActionOnly)
                    return findTarget(brawler, bonusActionOnly, onSuccess, onFailed)
                end
                if M.Utils.isValidHostileTarget(brawler.uuid, brawler.targetUuid) and M.Osi.GetDistanceTo(brawler.uuid, brawler.targetUuid) <= M.Utils.getTrackingDistance() then
                    debugPrint(brawler.displayName, "Remaining on target, attacking", M.Utils.getDisplayName(brawler.targetUuid), bonusActionOnly)
                    return actOnHostileTarget(brawler, brawlersInLevel[brawler.targetUuid], bonusActionOnly, onSuccess, onFailed)
                end
            end
        end
        -- Has an attack target but it's already dead or unable to fight, so find a new one
        debugPrint(brawler.displayName, "Find target (current target invalid)", brawler.uuid, bonusActionOnly)
        brawler.targetUuid = nil
        return findTarget(brawler, bonusActionOnly, onSuccess, onFailed)
    end
end

-- Brawlers doing dangerous stuff
-- TODO this needs to be restructured to use callbacks instead of returning
local function pulseAction(brawler, bonusActionOnly, onSuccess, onFailed)
    -- Brawler is alive and able to fight: let's go!
    if brawler and brawler.uuid and M.Utils.canAct(brawler.uuid) then
        if not brawler.isPaused and (not isPlayerControllingDirectly(brawler.uuid) or State.Settings.FullAuto) then
            if not State.Settings.TurnBasedSwarmMode then
                Roster.addPlayersInEnterCombatRangeToBrawlers(brawler.uuid)
            end
            return act(brawler, bonusActionOnly, onSuccess, onFailed)
        end
        -- If this brawler is dead or unable to fight, stop this pulse
        return stopPulseAction(brawler)
    end
end

-- Reposition the NPC relative to the player.  This is the only place that NPCs should enter the brawl.
local function pulseReposition(level)
    State.checkForDownedOrDeadPlayers()
    local brawlersInLevel = State.Session.Brawlers[level]
    if brawlersInLevel and not State.Settings.TurnBasedSwarmMode then
        for brawlerUuid, brawler in pairs(brawlersInLevel) do
            if not Constants.IS_TRAINING_DUMMY[brawlerUuid] then
                if M.Utils.isAliveAndCanFight(brawlerUuid) and M.Utils.canMove(brawlerUuid) then
                    -- Enemy units are actively looking for a fight and will attack if you get too close to them
                    if M.Utils.isPugnacious(brawlerUuid) then
                        if brawler.isInBrawl and brawler.targetUuid ~= nil and M.Utils.isAliveAndCanFight(brawler.targetUuid) then
                            local _, closestDistance = M.Osi.GetClosestAlivePlayer(brawlerUuid)
                            if closestDistance > 2*Constants.ENTER_COMBAT_RANGE then
                                debugPrint(brawler.displayName, "Too far away, removing brawler", brawlerUuid)
                                Roster.removeBrawler(level, brawlerUuid)
                            else
                                debugPrint(brawler.displayName, "Repositioning", brawlerUuid, "->", brawler.targetUuid)
                                -- Movement.repositionRelativeToTarget(brawlerUuid, brawler.targetUuid)
                            end
                        else
                            -- debugPrint(brawler.displayName, "Checking for a brawl to join", brawlerUuid)
                            checkForBrawlToJoin(brawler)
                        end
                    -- Player, ally, and neutral units are not actively looking for a fight
                    -- - Companions and allies use the same logic
                    -- - Neutrals just chilling
                    elseif M.State.areAnyPlayersBrawling() and M.Utils.isPlayerOrAlly(brawlerUuid) and not brawler.isPaused then
                        -- debugPrint(brawler.displayName, "Player or ally", brawlerUuid, M.Osi.GetHitpoints(brawlerUuid))
                        if State.Session.Players[brawlerUuid] and (isPlayerControllingDirectly(brawlerUuid) and not State.Settings.FullAuto) then
                            debugPrint(brawler.displayName, "Player is controlling directly: do not take action!")
                            -- debugDump(brawler)
                            stopPulseAction(brawler, true)
                        else
                            if not brawler.isInBrawl then
                                if M.Osi.IsPlayer(brawlerUuid) == 0 or State.Settings.CompanionAIEnabled then
                                    debugPrint(brawler.displayName, "Not in brawl, starting pulse action for")
                                    startPulseAction(brawler)
                                end
                            elseif M.Utils.isBrawlingWithValidTarget(brawler) and M.Osi.IsPlayer(brawlerUuid) == 1 and State.Settings.CompanionAIEnabled then
                                Movement.holdPosition(brawlerUuid)
                                -- Movement.repositionRelativeToTarget(brawlerUuid, brawler.targetUuid)
                            end
                        end
                    end
                elseif M.Osi.IsDead(brawlerUuid) == 1 or M.Utils.isDowned(brawlerUuid) then
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
    getResistanceWeight = getResistanceWeight,
    getSpellWeight = getSpellWeight,
    isNpcSpellUsable = isNpcSpellUsable,
    actOnHostileTarget = actOnHostileTarget,
    actOnFriendlyTarget = actOnFriendlyTarget,
    whoNeedsHealing = whoNeedsHealing,
    useSpellOnTarget = useSpellOnTarget,
    findTarget = findTarget,
    act = act,
    pulseAction = pulseAction,
    pulseReposition = pulseReposition,
    pulseAddNearby = pulseAddNearby,
    queueSpellRequest = queueSpellRequest,
}
