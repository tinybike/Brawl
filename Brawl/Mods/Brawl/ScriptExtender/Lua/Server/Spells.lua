local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump

local function buildTagNameToUuid()
    State.Session.TagNameToUuid = {}
    for _, uuid in ipairs(Ext.StaticData.GetAll("Tag")) do
        State.Session.TagNameToUuid[Ext.StaticData.Get(uuid, "Tag").Name] = uuid
    end
end

local function hasCondition(conditionString, condition)
    local parts = {}
    for part in conditionString:gmatch("%S+") do
        table.insert(parts, part)
    end
    for i, p in ipairs(parts) do
        if p == condition then
            if i == 1 or parts[i - 1] ~= "not" then
                return true
            end
        end
    end
    return false
end

local function hasConditionList(conditionString, condition)
    local yesList = {}
    local noList = {}
    local normalized = conditionString:gsub("%s*and%s*", "|"):gsub("[ \t;]+$", "")
    local terms = {}
    local i = 1
    while i <= #normalized do
        local j = normalized:find("|", i, true)
        if not j then
            local term = normalized:sub(i)
            if term ~= "" then
                table.insert(terms, term)
            end
            break
        end
        local term = normalized:sub(i, j - 1)
        if term ~= "" then
            table.insert(terms, term)
        end
        i = j + 1
    end
    local magic = "[%%%.%^%$%(%)%[%]%*%+%-%?]"
    local escaped = condition:gsub(magic, "%%%1")
    local yesPattern = "^%s*" .. escaped .. "%s*%(%s*'([^']*)'%s*%)%s*$"
    local noPattern = "^%s*not%s+" .. escaped .. "%s*%(%s*'([^']*)'%s*%)%s*$"
    for _, term in ipairs(terms) do
        local label = term:match(noPattern)
        if label then
            table.insert(noList, (escaped == "Tagged") and State.Session.TagNameToUuid[label] or label)
        else
            label = term:match(yesPattern)
            if label then
                table.insert(yesList, (escaped == "Tagged") and State.Session.TagNameToUuid[label] or label)
            end
        end
    end
    if not next(yesList) and not next(noList) then
        return nil
    end
    return {["1"] = next(yesList) and yesList or nil, ["0"] = next(noList) and noList or nil}
end

local function isSafeAoESpell(spellName)
    for _, safeAoESpell in ipairs(Constants.SAFE_AOE_SPELLS) do
        if spellName == safeAoESpell then
            return true
        end
    end
    return false
end

local function hasStringInSpellRoll(spell, target)
    if spell and spell.SpellRoll and spell.SpellRoll.Default then
        return string.find(spell.SpellRoll.Default, target, 1, true) ~= nil
    end
    return false
end

local function spellId(spell, spellName)
    return spell.Name == spellName
end

local function extraAttackSpellCheck(spell)
    return hasStringInSpellRoll(spell, "WeaponAttack") or hasStringInSpellRoll(spell, "UnarmedAttack") or hasStringInSpellRoll(spell, "ThrowAttack") or spellId(spell, "Target_CommandersStrike") or spellId(spell, "Target_Bufotoxin_Frog_Summon") or spellId(spell, "Projectile_ArrowOfSmokepowder")
end

local function parseSpellCosts(spell, costType)
    local costs = M.Utils.split(spell[costType], ";")
    local spellCosts = {
        ShortRest = spell.Cooldown == "OncePerShortRest" or spell.Cooldown == "OncePerShortRestPerItem",
        LongRest = spell.Cooldown == "OncePerRest" or spell.Cooldown == "OncePerRestPerItem",
    }
    -- local hitCost = nil -- divine smite only..?
    for _, cost in ipairs(costs) do
        local costTable = M.Utils.split(cost, ":")
        local costLabel = costTable[1]:match("^%s*(.-)%s*$")
        local costAmount = tonumber(costTable[#costTable])
        if costLabel == "SpellSlotsGroup" then
            -- e.g. SpellSlotsGroup:1:1:2
            -- NB: what are the first two numbers?
            spellCosts.SpellSlot = costAmount
        else
            spellCosts[costLabel] = costAmount
        end
    end
    return spellCosts
end

local function hasUseCosts(spell, targetCost)
    if spell and spell.UseCosts then
        local costs = parseSpellCosts(spell, "UseCosts")
        if costs then
            for cost, _ in pairs(costs) do
                if cost == targetCost then
                    return true
                end
            end
        end
    end
    return false
end

local function extraAttackCheck(spell)
    return extraAttackSpellCheck(spell) and hasUseCosts(spell, "ActionPoint")
end

local function isSpellOfType(spell, spellType)
    if not spell then
        return false
    end
    local isOfType = spell.VerbalIntent == spellType
    if not isOfType and spellType == "Damage" then
        if spell.SpellSuccess then
            for j, spellSuccess in ipairs(spell.SpellSuccess) do
                if spellSuccess.Functors then
                    for i, functor in ipairs(spellSuccess.Functors) do
                        if functor.TypeId == "DealDamage" then
                            isOfType = true
                            break
                        end
                    end
                end
            end
        end
    end
    return isOfType
end

local function getSpellTypeByName(name)
    local spellStats = Ext.Stats.Get(name)
    if spellStats then
        local spellType = spellStats.VerbalIntent
        if spellType == "None" and isSpellOfType(spellStats, "Damage") then
            spellType = "Damage"
        end
        return spellType
    end
end

local function getCantripDamage(str, level)
    local sides = tonumber(str)
    local numDice
    if level >= 10 then
        numDice = 3
    elseif level >= 5 then
        numDice = 2
    else
        numDice = 1
    end
    return tostring(numDice*(sides + 1)/2)
end

local function isWeaponOrUnarmed(value)
    local keywords = {
        "MainMeleeWeapon",
        "MainMeleeWeaponDamageType",
        "OffhandMeleeWeapon",
        "OffhandMeleeWeaponDamageType",
        "MainRangedWeapon",
        "MainRangedWeaponDamageType",
        "OffhandRangedWeapon",
        "OffhandRangedWeaponDamageType",
        "UnarmedDamage",
        "MartialArtsUnarmedDamage",
    }
    for _, marker in ipairs(keywords) do
        if value:find(marker) then
            return true
        end
    end
    return false
end

local function calculateMean(value, level)
    local str = tostring(value):gsub("Level", tostring(level))
    local numDice, numSides = str:match("(%d+)d(%d+)")
    local mean = 0
    if numDice and numSides then
        numDice = tonumber(numDice)
        numSides = tonumber(numSides)
        mean = numDice*(numSides + 1)/2
        str = str:gsub("%d+d%d+", tostring(mean))
    end
    local func, err = load("return " .. str)
    if func then
        local ok, result = pcall(func)
        if ok then
            return result
        end
    end
    return tonumber(str) or mean
end

local function parseTooltipDamage(damageString, level)
    damageString = damageString:gsub("LevelMapValue%(([^)]+)%)", function (levelMapValueArg)
        local cantripDieString = levelMapValueArg:match("D(%d+)Cantrip")
        if cantripDieString then
            return tostring(getCantripDamage(cantripDieString, level))
        end
    end)
    local isWeaponOrUnarmedDamage = false
    local totalDamage = 0
    for rawArg in damageString:gmatch("DealDamage%(([^%)]+)%)") do
        local damageValue = rawArg:match("([^,]+)")
        if damageValue then
            if isWeaponOrUnarmed(damageValue) then
                isWeaponOrUnarmedDamage = true
            end
            local meanVal = calculateMean(damageValue, level)
            if meanVal then
                totalDamage = totalDamage + meanVal
            end
        end
    end
    return isWeaponOrUnarmedDamage, totalDamage
end

local function checkForUnarmedDamage(spell)
    if spell and spell.SpellSuccess then
        for j, spellSuccess in ipairs(spell.SpellSuccess) do
            if spellSuccess.Functors then
                for i, functor in ipairs(spellSuccess.Functors) do
                    if functor.TypeId == "DealDamage" and functor.WeaponType == "UnarmedDamage" then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function checkForConcentration(spellFlags)
    if not spellFlags or spellFlags == "" then
        return false
    end
    for _, flag in ipairs(spellFlags) do
        if flag == "IsConcentration" then
            return true
        end
    end
end

local function checkForApplyStatus(spell, applyStatusType)
    if spell and spell[applyStatusType] then
        for j, spellSuccess in ipairs(spell[applyStatusType]) do
            if spellSuccess.Functors then
                for i, functor in ipairs(spellSuccess.Functors) do
                    if functor.TypeId == "ApplyStatus" and functor.StatusId then
                        return functor.StatusId
                    end
                end
            end
        end
    end
    return false
end

-- NB: some weird stuff gets picked up by this, probably need a finer-grained classification
-- (for example Teleportation_Revivify_Deva, Target_TAD_TransfuseHealth, Target_Regenerate all have RegainHitPoints functors -- what other examples are there...?)
local function checkForDirectHeal(spell, level)
    if spell and spell.SpellProperties then
        local spellName = spell.Name
        if spellName == "Teleportation_Revivify_Deva" or spellName == "Target_TAD_TransfuseHealth" or string.find(spellName, "Target_Regenerate", 1, true) == 1 then
            return false
        end
        local spellProperties = spell.SpellProperties
        if spellProperties then
            for _, spellProperty in ipairs(spellProperties) do
                local functors = spellProperty.Functors
                if functors then
                    for _, functor in ipairs(functors) do
                        if functor.TypeId == "RegainHitPoints" then
                            return true, calculateMean(functor.HitPoints.Code, level)
                        end
                    end
                end
            end
        end
    end
    return false, nil
end

local function isAutoPathfinding(spell)
    if spell and spell.Trajectories then
        local trajectories = M.Utils.split(spell.Trajectories, ",")
        for _, trajectory in ipairs(trajectories) do
            if trajectory == Constants.MAGIC_MISSILE_PATHFIND_UUID then
                return true
            end
        end
    end
    return false
end

local function parseRequirementString(str)
    if str ~= "" then
        local reqs = {
            IsTagged = hasConditionList(str, "Tagged"),
            HasActiveStatus = hasConditionList(str, "HasStatus"),
            HasPassive = hasConditionList(str, "HasPassive"),
            IsImmuneToStatus = hasConditionList(str, "IsImmuneToStatus"),
        }
        return next(reqs) ~= nil and reqs or nil
    end
end

local function isSingleSelect(spellName)
    local stats = Ext.Stats.Get(spellName)
    if stats.SpellFlags then
        for _, flag in ipairs(stats.SpellFlags) do
            if flag == "IgnorePreviouslyPickedEntities" then
                return true
            end
        end
    end
    return false
end

local function isShout(spellName)
    return Utils.startsWith(spellName, "Shout_")
end

local function getSpellInfo(spellType, spellName, hostLevel)
    local spell = Ext.Stats.Get(spellName)
    if isSpellOfType(spell, spellType) then
        local outOfCombatOnly = false
        for _, req in ipairs(spell.Requirements) do
            if req.Requirement == "Combat" and req.Not == true then
                outOfCombatOnly = true
            end
        end
        local hasVerbalComponent = false
        for _, flag in ipairs(spell.SpellFlags) do
            if flag == "HasVerbalComponent" then
                hasVerbalComponent = true
            end
        end
        local isWeaponOrUnarmedDamage, averageDamage = parseTooltipDamage(spell.TooltipDamageList, hostLevel)
        local costs = parseSpellCosts(spell, "UseCosts")
        local hitCosts = parseSpellCosts(spell, "HitCosts")
        for hitCost, hitCostAmount in pairs(hitCosts) do
            if hitCost == "LongRest" or hitCost == "ShortRest" then
                costs[hitCost] = costs[hitCost] or hitCostAmount
            else
                -- Exclude weird edge cases, e.g. Projectile_EnsnaringStrike_4, Projectile_Smite_Banishing_7, etc.
                if hitCostAmount and costs[hitCost] then
                    return nil
                end
                costs[hitCost] = hitCostAmount
            end
        end
        local directHeal, averageHealing = checkForDirectHeal(spell, hostLevel)
        local spellInfo = {
            level = spell.Level,
            areaRadius = spell.AreaRadius,
            damageType = spell.DamageType,
            isGapCloser = spell.SpellType == "Rush",
            isSpell = spell.SpellSchool ~= "None",
            isEvocation = spell.SpellSchool == "Evocation",
            targetRadius = spell.TargetRadius,
            range = spell.Range,
            costs = costs,
            type = spellType,
            amountOfTargets = spell.AmountOfTargets ~= "" and tonumber(spell.AmountOfTargets) or nil,
            hasVerbalComponent = hasVerbalComponent,
            averageDamage = averageDamage,
            averageHealing = averageHealing,
            isWeaponOrUnarmedDamage = isWeaponOrUnarmedDamage,
            isUnarmedDamage = checkForUnarmedDamage(spell),
            triggersExtraAttack = extraAttackCheck(spell),
            isDirectHeal = directHeal,
            isBonusAction = costs.BonusActionPoint ~= nil and costs.ActionPoint == nil,
            isSafeAoE = isSafeAoESpell(spellName),
            applyStatusOnSuccess = checkForApplyStatus(spell, "SpellSuccess"),
            applyStatus = checkForApplyStatus(spell, "SpellProperties"),
            isConcentration = checkForConcentration(spell.SpellFlags),
            isSelfOnly = hasCondition(spell.TargetConditions, "Self()"),
            isCharacterOnly = hasCondition(spell.TargetConditions, "Character()"),
            conditions = {
                caster = parseRequirementString(spell.RequirementConditions),
                target = parseRequirementString(spell.TargetConditions),
            },
            outOfCombatOnly = outOfCombatOnly,
            isAutoPathfinding = isAutoPathfinding(spell),
        }
        return spellInfo
    end
    return nil
end

local function deepEqual(a, b)
    if type(a) ~= type(b) then
        return false
    end
    if type(a) ~= "table" then
        return a == b
    end
    for k, v in pairs(a) do
        if not deepEqual(v, b[k]) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

local function removeDuplicates(list)
    local unique = {}
    for _, item in ipairs(list) do
        local isDuplicate = false
        for _, u in ipairs(unique) do
            if deepEqual(item, u) then
                isDuplicate = true
                break
            end
        end
        if not isDuplicate then
            table.insert(unique, item)
        end
    end
    return unique
end

local function getAllSpellsOfType(spellType, hostLevel)
    local allSpellsOfType = {}
    for _, spellName in ipairs(Ext.Stats.GetStats("SpellData")) do
        local spell = Ext.Stats.Get(spellName)
        if isSpellOfType(spell, spellType) then
            if spell.ContainerSpells and spell.ContainerSpells ~= "" then
                local containerSpellNames = M.Utils.split(spell.ContainerSpells, ";")
                for _, containerSpellName in ipairs(containerSpellNames) do
                    allSpellsOfType[containerSpellName] = getSpellInfo(spellType, containerSpellName, hostLevel)
                end
            else
                allSpellsOfType[spellName] = getSpellInfo(spellType, spellName, hostLevel)
                if spell.Requirements and #spell.Requirements ~= 0 then
                    local requirements = removeDuplicates(spell.Requirements)
                    local removeIndex = 0
                    for i, req in ipairs(requirements) do
                        if req.Requirement == "Combat" and req.Not == false then
                            removeIndex = i
                            local removedReq = {Requirement = req.Requirement, Param = req.Param, Not = req.Not, index = i}
                            local modVars = Ext.Vars.GetModVariables(ModuleUUID)
                            modVars.SpellRequirements = modVars.SpellRequirements or {}
                            modVars.SpellRequirements[spellName] = removedReq
                            break
                        end
                    end
                    if removeIndex ~= 0 then
                        table.remove(requirements, removeIndex)
                    end
                    spell.Requirements = requirements
                    spell:Sync()
                end
            end
        end
    end
    return allSpellsOfType
end

local function buildSpellTable()
    local hostLevel = M.Osi.GetLevel(M.Osi.GetHostCharacter())
    local spellTable = {}
    local spellTableByName = {}
    buildTagNameToUuid()
    for _, spellType in ipairs(Constants.ALL_SPELL_TYPES) do
        spellTable[spellType] = getAllSpellsOfType(spellType, hostLevel)
        for spellName, spell in pairs(spellTable[spellType]) do
            spellTableByName[spellName] = spell
        end
    end
    State.Session.SpellTable = spellTable
    State.Session.SpellTableByName = spellTableByName
end

local function resetSpellData()
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    if modVars and modVars.SpellRequirements then
        local spellReqs = modVars.SpellRequirements
        for spellName, req in pairs(spellReqs) do
            local spell = Ext.Stats.Get(spellName)
            if spell then
                local requirements = spell.Requirements
                table.insert(requirements, {Requirement = req.Requirement, Param = req.Param, Not = req.Not})
                spell.Requirements = requirements
                spell:Sync()
            end
        end
        modVars.SpellRequirements = nil
    end
end

local function getAuras(entityUuid)
    local auras = {}
    if entityUuid then
        local entity = Ext.Entity.Get(entityUuid)
        if entity.SpellBookPrepares and entity.SpellBookPrepares.PreparedSpells then
            local preparedSpells = entity.SpellBookPrepares.PreparedSpells
            for _, preparedSpell in ipairs(preparedSpells) do
                local spellName = preparedSpell.OriginatorPrototype
                local stats = Ext.Stats.Get(spellName)
                local spell = M.Spells.getSpellByName(spellName)
                if Utils.startsWith(spellName, "Shout_AuraOf_") and stats.UseCosts == "" and spell.applyStatus and spell.applyStatus ~= "AI_HELPER_BUFF" then
                    table.insert(auras, spellName)
                end
            end
        end
    end
    return auras
end

local function getRageAbility(entityUuid)
    if entityUuid then
        local entity = Ext.Entity.Get(entityUuid)
        if entity.SpellBookPrepares and entity.SpellBookPrepares.PreparedSpells then
            local preparedSpells = entity.SpellBookPrepares.PreparedSpells
            for _, rageAbility in ipairs(Constants.RAGE_ABILITIES) do
                for _, preparedSpell in ipairs(preparedSpells) do
                    local spellName = preparedSpell.OriginatorPrototype
                    if spellName and Utils.startsWith(spellName, rageAbility) then
                        return spellName
                    end
                end
            end
        end
    end
end

local function getSpellByName(name)
    if name then
        return State.Session.SpellTableByName[name]
    end
end

return {
    isSingleSelect = isSingleSelect,
    isShout = isShout,
    buildSpellTable = buildSpellTable,
    resetSpellData = resetSpellData,
    getAuras = getAuras,
    getRageAbility = getRageAbility,
    getSpellByName = getSpellByName,
}
