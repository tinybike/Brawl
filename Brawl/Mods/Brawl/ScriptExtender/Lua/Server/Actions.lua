local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump
local noop = Utils.noop

local function getActionInProgress(casterUuid, requestUuid)
    local actionsInProgress = State.Session.ActionsInProgress[casterUuid]
    if actionsInProgress and next(actionsInProgress) then
        for _, actionInProgress in ipairs(actionsInProgress) do
            -- debugPrint("checking action", actionInProgress.requestUuid, requestUuid)
            if actionInProgress.requestUuid == requestUuid then
                return actionInProgress
            end
        end
    end
end

local function getActionInProgressByName(casterUuid, spellName)
    local actionsInProgress = State.Session.ActionsInProgress[casterUuid]
    if actionsInProgress and next(actionsInProgress) then
        for _, actionInProgress in ipairs(actionsInProgress) do
            -- debugPrint("checking action by name", actionInProgress.spellName, spellName)
            if actionInProgress.spellName == spellName then
                return actionInProgress
            end
        end
    end
end

local function registerActionInProgress(casterUuid, spellName, requestUuid, onCompleted, onFailed)
    State.Session.ActionsInProgress[casterUuid] = State.Session.ActionsInProgress[casterUuid] or {}
    table.insert(State.Session.ActionsInProgress[casterUuid], {
        spellName = spellName,
        requestUuid = requestUuid,
        onCompleted = onCompleted or noop,
        onFailed = onFailed or noop,
    })
end

local function removeActionInProgress(casterUuid, requestUuid)
    if State.Session.ActionsInProgress[casterUuid] then
        local foundActionInProgress = false
        local actionsInProgressIndex = nil
        local actionsInProgress = State.Session.ActionsInProgress[casterUuid]
        for i, actionInProgress in ipairs(actionsInProgress) do
            if actionInProgress.requestUuid == requestUuid then
                foundActionInProgress = true
                actionsInProgressIndex = i
                break
            end
        end
        if foundActionInProgress then
            for i = actionsInProgressIndex, 1, -1 do
                debugPrint("complete action in progress", i, M.Utils.getDisplayName(casterUuid), actionsInProgress[i].spellName)
                table.remove(actionsInProgress, i)
            end
        end
    end
end

local function removeActionsInProgress(casterUuid)
    if State.Session.ActionsInProgress[casterUuid] and next(State.Session.ActionsInProgress[casterUuid]) then
        for _, actionInProgress in ipairs(State.Session.ActionsInProgress[casterUuid]) do
            removeActionInProgress(casterUuid, actionInProgress.requestUuid)
        end
    end
end

local function playAttackSound(attackerUuid, defenderUuid, damageType)
    if damageType == "Slashing" then
        Osi.PlaySound(attackerUuid, "Action_Cast_Slash")
        Osi.PlaySound(defenderUuid, "Action_Impact_Slash")
    elseif damageType == "Piercing" then
        Osi.PlaySound(attackerUuid, "Action_Cast_PiercingThrust")
        Osi.PlaySound(defenderUuid, "Action_Impact_PiercingThrust")
    else
        Osi.PlaySound(attackerUuid, "Action_Cast_Smash")
        Osi.PlaySound(defenderUuid, "Action_Impact_Smash")
    end
end

local function hasExtraAttacksRemaining(uuid)
    return State.Session.ExtraAttacksRemaining[uuid] ~= nil and State.Session.ExtraAttacksRemaining[uuid] > 0
end

local function checkExtraAttacksReady(attackerUuid, defenderUuid)
    return hasExtraAttacksRemaining(attackerUuid) and M.Utils.isAliveAndCanFight(attackerUuid) and M.Utils.isAliveAndCanFight(defenderUuid)
end

local function reapplyAttackDamage(attackerUuid, defenderUuid, damageAmount, damageType)
    Ext.Timer.WaitFor(150, function ()
        if checkExtraAttacksReady(attackerUuid, defenderUuid) then
            playAttackSound(attackerUuid, defenderUuid, damageType)
            Ext.Timer.WaitFor(150, function ()
                if checkExtraAttacksReady(attackerUuid, defenderUuid) then
                    State.Session.ExtraAttacksRemaining[attackerUuid] = State.Session.ExtraAttacksRemaining[attackerUuid] - 1
                    debugPrint("Applying damage", defenderUuid, damageAmount, damageType)
                    Osi.ApplyDamage(defenderUuid, damageAmount, damageType, "")
                    Osi.ApplyStatus(defenderUuid, "INTERRUPT_RIPOSTE", 1)
                    Leaderboard.updateDamage(attackerUuid, defenderUuid, damageAmount)
                    reapplyAttackDamage(attackerUuid, defenderUuid, damageAmount, damageType)
                else
                    State.Session.ExtraAttacksRemaining[attackerUuid] = nil
                end
            end)
        else
            State.Session.ExtraAttacksRemaining[attackerUuid] = nil
        end
    end)
end

local function useActionPointSurplus(uuid, resourceType)
    local pointSurplus = math.floor(M.Osi.GetActionResourceValuePersonal(uuid, resourceType, 0) - 1)
    if pointSurplus > 0 then
        Resources.decreaseActionResource(uuid, resourceType, pointSurplus)
    end
    return pointSurplus
end

local function useBonusAttacks(uuid)
    local numBonusAttacks = 0
    if M.Osi.GetEquippedWeapon(uuid) ~= nil then
        if M.Osi.HasActiveStatus(uuid, "GREAT_WEAPON_MASTER_BONUS_ATTACK") == 1 then
            Osi.RemoveStatus(uuid, "GREAT_WEAPON_MASTER_BONUS_ATTACK", "")
            numBonusAttacks = numBonusAttacks + 1
        end
        if M.Osi.HasActiveStatus(uuid, "POLEARM_MASTER_BONUS_ATTACK") == 1 then
            Osi.RemoveStatus(uuid, "POLEARM_MASTER_BONUS_ATTACK", "")
            numBonusAttacks = numBonusAttacks + 1
        end
    else
        if M.Osi.HasActiveStatus(uuid, "MARTIAL_ARTS_BONUS_UNARMED_STRIKE") == 1 then
            Osi.RemoveStatus(uuid, "MARTIAL_ARTS_BONUS_UNARMED_STRIKE", "")
            numBonusAttacks = numBonusAttacks + 1
        end
    end
    if not State.Settings.TurnBasedSwarmMode then
        numBonusAttacks = numBonusAttacks + useActionPointSurplus(uuid, "ActionPoint")
        numBonusAttacks = numBonusAttacks + useActionPointSurplus(uuid, "BonusActionPoint")
    end
    return numBonusAttacks
end

local function handleExtraAttacks(attackerUuid, defenderUuid, storyActionID, damageType, damageAmount)
    if State.Settings.TurnBasedSwarmMode and not State.Session.SwarmTurnActive then
        return
    end
    if attackerUuid ~= nil and defenderUuid ~= nil and storyActionID ~= nil and damageAmount ~= nil and damageAmount > 0 then
        if not State.Settings.TurnBasedSwarmMode or M.Utils.isPugnacious(attackerUuid) then
            if State.Session.StoryActionIDs[storyActionID] and State.Session.StoryActionIDs[storyActionID].spellName then
                debugPrint("Handle extra attacks", spellName, attackerUuid, defenderUuid, storyActionID, damageType, damageAmount)
                State.Session.StoryActionIDs[storyActionID] = nil
                local spell = Spells.getSpellByName(spellName)
                if spell ~= nil and spell.triggersExtraAttack == true then
                    if State.Settings.TurnBasedSwarmMode and M.Utils.isPugnacious(attackerUuid) and spell.isBonusAction then
                        return nil
                    end
                    if State.Session.ExtraAttacksRemaining[attackerUuid] == nil then
                        local brawler = M.Roster.getBrawlerByUuid(attackerUuid)
                        if brawler and M.Utils.isAliveAndCanFight(attackerUuid) and M.Utils.isAliveAndCanFight(defenderUuid) then
                            local numBonusAttacks = useBonusAttacks(attackerUuid)
                            debugPrint("Initiating extra attacks", attackerUuid, spellName, storyActionID, brawler.numExtraAttacks, numBonusAttacks)
                            State.Session.ExtraAttacksRemaining[attackerUuid] = brawler.numExtraAttacks + numBonusAttacks
                            reapplyAttackDamage(attackerUuid, defenderUuid, damageAmount, damageType)
                        end
                    end
                end
            end
        end
    end
end

local function buildTarget(uuid, targetingType)
    return {Target = Ext.Entity.Get(uuid), TargetingType = targetingType}
end

local function buildTargets(casterUuid, spellName, targetUuid, targetingType, isFriendlyTarget)
    local targets = {}
    table.insert(targets, buildTarget(targetUuid, targetingType))
    if isFriendlyTarget then
        local spell = M.Spells.getSpellByName(spellName)
        local spellRange = M.Utils.convertSpellRangeToNumber(M.Utils.getSpellRange(spellName), casterUuid)
        local level = M.Osi.GetRegion(casterUuid)
        local brawlersInLevel = State.Session.Brawlers[level]
        if brawlersInLevel and spell.amountOfTargets and spell.amountOfTargets > 1 then
            local singleSelect = M.Spells.isSingleSelect(spellName)
            local counter = 0
            while #targets < spell.amountOfTargets and counter < 25 do
                counter = counter + 1
                for extraTargetUuid, _ in pairs(brawlersInLevel) do
                    if not singleSelect or extraTargetUuid ~= targetUuid then
                        if M.Osi.IsAlly(casterUuid, extraTargetUuid) == 1 and M.Osi.GetDistanceTo(casterUuid, extraTargetUuid) <= spellRange then
                            table.insert(targets, buildTarget(extraTargetUuid, targetingType))
                            if #targets >= spell.amountOfTargets then
                                break
                            end
                        end
                    end
                end
                if singleSelect then
                    break
                end
            end
        end
    end
    return targets
end

local function buildSpell(entity, spellName, stats)
    local originatorPrototype = M.Utils.getOriginatorPrototype(spellName, stats)
    if State.Settings.HogwildMode or not State.Settings.TurnBasedSwarmMode then
        return {
            OriginatorPrototype = originatorPrototype,
            ProgressionSource = Constants.NULL_UUID,
            Prototype = spellName,
            Source = Constants.NULL_UUID,
            SourceType = "Osiris",
        }
    end
    if entity.SpellBookPrepares and entity.SpellBookPrepares.PreparedSpells then
        for _, preparedSpell in ipairs(entity.SpellBookPrepares.PreparedSpells) do
            if preparedSpell.OriginatorPrototype == originatorPrototype then
                return {
                    OriginatorPrototype = originatorPrototype,
                    ProgressionSource = preparedSpell.ProgressionSource,
                    Prototype = spellName,
                    Source = preparedSpell.Source,
                    SourceType = preparedSpell.SourceType,
                }
            end
        end
    end
end

local function submitSpellRequest(request, insertAtFront)
    local queuedRequests = Ext.System.ServerCastRequest.OsirisCastRequests
    local isPausedRequest = State.Settings.TruePause and Pause.isInFTB(request.Caster)
    if insertAtFront or isPausedRequest then
        for i = #queuedRequests, 1, -1 do
            queuedRequests[i + 1] = queuedRequests[i]
        end
        queuedRequests[1] = request
    else
        queuedRequests[#queuedRequests + 1] = request
    end
    debugPrint(M.Utils.getDisplayName(request.Caster.Uuid.EntityUuid), "inserted cast request", #queuedRequests, request.Spell.Prototype, isPausedRequest, request.RequestGuid)
end

local function getCastOptions()
    if State.Settings.TurnBasedSwarmMode then
        if State.Settings.HogwildMode then
            return {"IgnoreHasSpell", "ShowPrepareAnimation", "IgnoreSpellRolls", "IgnoreTargetChecks", "IgnoreCastChecks", "NoMovement"}
        else
            return {"FromClient", "ShowPrepareAnimation", "AvoidDangerousAuras", "NoMovement"}
        end
    else
        if State.Settings.HogwildMode then
            return {"IgnoreHasSpell", "ShowPrepareAnimation", "IgnoreSpellRolls", "IgnoreTargetChecks", "IgnoreCastChecks"}
        else
            return {"IgnoreHasSpell", "ShowPrepareAnimation", "AvoidDangerousAuras", "IgnoreTargetChecks"}
        end
    end
end

-- thank u focus and mazzle
local function queueSpellRequest(casterUuid, spellName, targetUuid, requestUuid, isFriendlyTarget, castOptions, insertAtFront)
    local stats = Ext.Stats.Get(spellName)
    if not castOptions then
        castOptions = getCastOptions()
    end
    local targets = buildTargets(casterUuid, spellName, targetUuid, stats.SpellType, isFriendlyTarget)
    local casterEntity = Ext.Entity.Get(casterUuid)
    local spell = buildSpell(casterEntity, spellName, stats)
    if not spell then
        return false
    end
    local request = {
        CastOptions = castOptions,
        Caster = casterEntity,
        RequestGuid = requestUuid or Utils.createUuid(),
        Spell = spell,
        -- StoryActionId = 0,
        Targets = targets,
        field_A8 = 1,
    }
    -- debugDump(request)
    submitSpellRequest(request, insertAtFront)
    return request
end

local function useSpell(casterUuid, targetUuid, spellName, isFriendlyTarget, variant, upcastLevel, onSubmitted, onCompleted, onFailed)
    onSubmitted = onSubmitted or noop
    onCompleted = onCompleted or noop
    onFailed = onFailed or noop
    debugPrint(M.Utils.getDisplayName(casterUuid), "casting on target", spellName, targetUuid, M.Utils.getDisplayName(targetUuid))
    if targetUuid == nil then
        return onFailed("no target")
    end
    if variant ~= nil then
        spellName = variant
    end
    if upcastLevel ~= nil then
        spellName = spellName .. "_" .. tostring(upcastLevel)
    end
    if State.Settings.TurnBasedSwarmMode then
        local spellRange = M.Utils.convertSpellRangeToNumber(M.Utils.getSpellRange(spellName), casterUuid)
        local distanceTo = M.Osi.GetDistanceTo(casterUuid, targetUuid)
        if distanceTo ~= nil and math.floor(distanceTo) > spellRange then
            local err = "cast failed, out of range" .. M.Utils.getDisplayName(casterUuid) .. " " .. M.Utils.getDisplayName(targetUuid) .. " " .. tostring(distanceTo) .. " " .. tostring(spellRange) .. " " .. spellName
            debugPrint(err)
            return onFailed(err)
        end
        if spellRange > 2 and M.Osi.HasLineOfSight(casterUuid, targetUuid) == 0 then
            local spell = Spells.getSpellByName(spellName)
            if spell and not spell.isAutoPathfinding then
                local err = "cast failed, no line of sight" .. M.Utils.getDisplayName(casterUuid) .. " " .. M.Utils.getDisplayName(targetUuid) .. " " .. spellName
                debugPrint(err)
                return onFailed(err)
            end
        end
    end
    local requestUuid = Utils.createUuid()
    registerActionInProgress(casterUuid, spellName, requestUuid, onCompleted, onFailed)
    local request = queueSpellRequest(casterUuid, spellName, targetUuid, requestUuid, isFriendlyTarget)
    if not request then
        local err = "spell construction error"
        debugPrint(err)
        return onFailed(err)
    end
    onSubmitted(request)
end

local function useSpellOnTarget(attackerUuid, targetUuid, spellName, isFriendlyTarget, onSubmitted, onCompleted, onFailed)
    debugPrint(M.Utils.getDisplayName(attackerUuid), "useSpellOnTarget", attackerUuid, targetUuid, spellName)
    return useSpell(attackerUuid, targetUuid, spellName, isFriendlyTarget, nil, nil, onSubmitted, onCompleted, onFailed)
end

local function startRage(uuid, rage, onSubmitted, onCompleted, onFailed)
    Actions.useSpellOnTarget(uuid, uuid, rage, true, onSubmitted, function (spellName)
        if not Utils.startsWith(spellName, "Shout_Rage_Giant") then
            return onCompleted(spellName)
        end
        Swarm.cancelActionSequenceFailsafeTimer(uuid)
        Ext.Timer.WaitFor(Constants.TIME_BETWEEN_ACTIONS, function ()
            Actions.useSpellOnTarget(uuid, uuid, "Shout_ElementalCleaver_Thunder", true, onSubmitted, onCompleted, onFailed)
        end)
    end, onFailed)
end

local function startAuras(uuid, auras, onSubmitted, onCompleted, onFailed)
    debugPrint(M.Utils.getDisplayName(uuid), "startAuras", #auras)
    local function startAura(index)
        if index > #auras then
            return onCompleted(auras[#auras])
        end
        local aura = auras[index]
        if not M.Pick.checkConditions({caster = uuid, target = uuid}, M.Spells.getSpellByName(aura)) then
            debugPrint(M.Utils.getDisplayName(uuid), aura, "aura checkCondition failed, going to next aura...")
            return startAura(index + 1)
        end
        Actions.useSpellOnTarget(uuid, uuid, aura, true, onSubmitted, function (spellName)
            debugPrint(M.Utils.getDisplayName(uuid), spellName, "aura successfully activated")
            Swarm.cancelActionSequenceFailsafeTimer(uuid)
            Ext.Timer.WaitFor(Constants.TIME_BETWEEN_ACTIONS, function ()
                startAura(index + 1)
            end)
        end, onFailed)
    end
    startAura(1)
end

return {
    getActionInProgress = getActionInProgress,
    getActionInProgressByName = getActionInProgressByName,
    removeActionInProgress = removeActionInProgress,
    removeActionsInProgress = removeActionsInProgress,
    handleExtraAttacks = handleExtraAttacks,
    submitSpellRequest = submitSpellRequest,
    queueSpellRequest = queueSpellRequest,
    useSpell = useSpell,
    useSpellOnTarget = useSpellOnTarget,
    startRage = startRage,
    startAuras = startAuras,
}
