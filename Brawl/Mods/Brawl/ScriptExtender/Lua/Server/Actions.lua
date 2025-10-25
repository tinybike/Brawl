local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump
local noop = Utils.noop

local function registerAction(uuid, spellName, callback)
    State.Session.ActionsInProgress[uuid] = State.Session.ActionsInProgress[uuid] or {}
    table.insert(State.Session.ActionsInProgress[uuid], {spellName = spellName, callback = callback})
end

local function completeAction(uuid, spellName)
    if State.Session.ActionsInProgress[uuid] then
        local foundActionInProgress = false
        local actionsInProgressIndex = nil
        local actionsInProgress = State.Session.ActionsInProgress[uuid]
        for i, actionInProgress in ipairs(actionsInProgress) do
            if actionInProgress.spellName == spellName then
                foundActionInProgress = true
                actionsInProgressIndex = i
                if actionInProgress.callback then
                    actionInProgress.callback()
                end
                break
            end
        end
        if foundActionInProgress then
            for i = actionsInProgressIndex, 1, -1 do
                debugPrint("complete action in progress", i, M.Utils.getDisplayName(uuid), actionsInProgress[i].spellName)
                table.remove(actionsInProgress, i)
            end
        end
    end
end

-- thank u focus and mazzle
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
    registerAction(casterUuid, spellName, onCompleted)
    queueSpellRequest(casterUuid, spellName, targetUuid)
    onSubmitted()
end

local function useSpellOnTarget(attackerUuid, targetUuid, spellName, onSubmitted, onCompleted, onFailed)
    debugPrint(M.Utils.getDisplayName(attackerUuid), "useSpellOnTarget", attackerUuid, targetUuid, spellName)
    if State.Settings.HogwildMode then
        Osi.UseSpell(attackerUuid, spellName, targetUuid)
        registerAction(attackerUuid, spellName, onCompleted)
        return onSubmitted()
    end
    return useSpell(attackerUuid, targetUuid, spellName, nil, nil, onSubmitted, onCompleted, onFailed)
end

return {
    registerAction = registerAction,
    completeAction = completeAction,
    queueSpellRequest = queueSpellRequest,
    useSpell = useSpell,
    useSpellOnTarget = useSpellOnTarget,
}
