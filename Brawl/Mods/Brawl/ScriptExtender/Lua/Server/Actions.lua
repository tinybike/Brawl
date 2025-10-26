local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump
local noop = Utils.noop

local function getActionInProgress(casterUuid, requestUuid)
    local actionsInProgress = State.Session.ActionsInProgress[casterUuid]
    if actionsInProgress and next(actionsInProgress) then
        for _, actionInProgress in ipairs(actionsInProgress) do
            print("checking action", actionInProgress.requestUuid, requestUuid)
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
            print("checking action by name", actionInProgress.spellName, spellName)
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

-- thank u focus and mazzle
local function queueSpellRequest(casterUuid, spellName, targetUuid, requestUuid, castOptions, insertAtFront)
    local stats = Ext.Stats.Get(spellName)
    if not castOptions then
        if State.Settings.HogwildMode then
            castOptions = {"IgnoreHasSpell", "ShowPrepareAnimation", "AvoidDangerousAuras", "IgnoreSpellRolls", "IgnoreCastChecks", "IgnoreTargetChecks"}
        else
            castOptions = {"IgnoreHasSpell", "ShowPrepareAnimation", "AvoidDangerousAuras", "IgnoreTargetChecks"}
        end
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
        RequestGuid = requestUuid or Utils.createUuid(),
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
    print(M.Utils.getDisplayName(casterUuid), "insert cast request", #queuedRequests, spellName, M.Utils.getDisplayName(targetUuid), isPausedRequest, Pause.isLocked(casterEntity), request.RequestGuid)
    return request.RequestGuid
end

local function useSpell(casterUuid, targetUuid, spellName, variant, upcastLevel, onSubmitted, onCompleted, onFailed)
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
        local spell = not State.getSpellByName(spellName)
        if spell and not spell.isAutoPathfinding then
            debugPrint("cast failed, no line of sight", M.Utils.getDisplayName(casterUuid), M.Utils.getDisplayName(targetUuid), spellName)
            return onFailed("no line of sight")
        end
    end
    local requestUuid = Utils.createUuid()
    registerActionInProgress(casterUuid, spellName, requestUuid, onCompleted, onFailed)
    queueSpellRequest(casterUuid, spellName, targetUuid, requestUuid)
    onSubmitted(spellName, targetUuid, requestUuid)
end

local function useSpellOnTarget(attackerUuid, targetUuid, spellName, onSubmitted, onCompleted, onFailed)
    debugPrint(M.Utils.getDisplayName(attackerUuid), "useSpellOnTarget", attackerUuid, targetUuid, spellName)
    return useSpell(attackerUuid, targetUuid, spellName, nil, nil, onSubmitted, onCompleted, onFailed)
end

return {
    getActionInProgress = getActionInProgress,
    getActionInProgressByName = getActionInProgressByName,
    registerActionInProgress = registerActionInProgress,
    removeActionInProgress = removeActionInProgress,
    queueSpellRequest = queueSpellRequest,
    useSpell = useSpell,
    useSpellOnTarget = useSpellOnTarget,
}
