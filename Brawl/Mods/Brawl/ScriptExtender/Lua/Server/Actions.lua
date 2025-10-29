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

local function buildTarget(uuid, targetingType)
    return {Target = Ext.Entity.Get(uuid), TargetingType = targetingType}
end

local function buildTargets(casterUuid, spellName, targetUuid, targetingType, isFriendlyTarget)
    local targets = {}
    table.insert(targets, buildTarget(targetUuid, targetingType))
    if isFriendlyTarget then
        local spell = M.Spells.getSpellByName(spellName)
        local spellRange = M.Utils.convertSpellRangeToNumber(M.Utils.getSpellRange(spellName))
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
    if State.Settings.HogwildMode then
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

-- thank u focus and mazzle
local function queueSpellRequest(casterUuid, spellName, targetUuid, requestUuid, isFriendlyTarget, castOptions, insertAtFront)
    local stats = Ext.Stats.Get(spellName)
    if not castOptions then
        if State.Settings.HogwildMode then
            castOptions = {"IgnoreHasSpell", "ShowPrepareAnimation", "AvoidDangerousAuras", "IgnoreSpellRolls"}
        else
            castOptions = {"FromClient", "ShowPrepareAnimation", "AvoidDangerousAuras"}
        end
        if State.Settings.TurnBasedSwarmMode then
            table.insert(castOptions, "NoMovement")
        end
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
    local spellRange = M.Utils.convertSpellRangeToNumber(M.Utils.getSpellRange(spellName))
    local distanceTo = M.Osi.GetDistanceTo(casterUuid, targetUuid)
    if distanceTo ~= nil and math.floor(distanceTo) > spellRange then
        debugPrint("cast failed, out of range", M.Utils.getDisplayName(casterUuid), M.Utils.getDisplayName(targetUuid), distanceTo, spellRange, spellName)
        return onFailed("out of range")
    end
    if spellRange > 2 and M.Osi.HasLineOfSight(casterUuid, targetUuid) == 0 then
        local spell = not Spells.getSpellByName(spellName)
        if spell and not spell.isAutoPathfinding then
            debugPrint("cast failed, no line of sight", M.Utils.getDisplayName(casterUuid), M.Utils.getDisplayName(targetUuid), spellName)
            return onFailed("no line of sight")
        end
    end
    local requestUuid = Utils.createUuid()
    registerActionInProgress(casterUuid, spellName, requestUuid, onCompleted, onFailed)
    local request = queueSpellRequest(casterUuid, spellName, targetUuid, requestUuid, isFriendlyTarget)
    if not request then
        return onFailed("spell construction error")
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
        -- NB: should this onSubmitted just be a noop?  can execute 2x
        Ext.Timer.WaitFor(Constants.TIME_BETWEEN_ACTIONS, function ()
            Actions.useSpellOnTarget(uuid, uuid, "Shout_ElementalCleaver_Thunder", true, onSubmitted, onCompleted, onFailed)
        end)
    end, onFailed)
end

return {
    getActionInProgress = getActionInProgress,
    getActionInProgressByName = getActionInProgressByName,
    registerActionInProgress = registerActionInProgress,
    removeActionInProgress = removeActionInProgress,
    submitSpellRequest = submitSpellRequest,
    queueSpellRequest = queueSpellRequest,
    useSpell = useSpell,
    useSpellOnTarget = useSpellOnTarget,
    startRage = startRage,
}
