local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump
local clearOsirisQueue = Utils.clearOsirisQueue
local noop = Utils.noop

local function getActionResource(entity, resourceType)
    if entity and entity.ActionResources and entity.ActionResources.Resources then
        local resources = entity.ActionResources.Resources
        if resources[Constants.ACTION_RESOURCES[resourceType]] and resources[Constants.ACTION_RESOURCES[resourceType]][1] then
            return resources[Constants.ACTION_RESOURCES[resourceType]][1]
        end
    end
end

local function getActionResourceMaxAmount(entity, resourceType)
    return (Resources.getActionResource(entity, resourceType) or {}).MaxAmount
end

local function getActionResourceAmount(entity, resourceType)
    return (Resources.getActionResource(entity, resourceType) or {}).Amount
end

local function restoreSpellSlots(uuid)
    if uuid then
        local entity = Ext.Entity.Get(uuid)
        if entity and entity.ActionResources and entity.ActionResources.Resources then
            local spellSlots = entity.ActionResources.Resources[Constants.ACTION_RESOURCES.SpellSlot]
            if spellSlots then
                print("restoring spell slots", uuid)
                for _, spellSlot in ipairs(spellSlots) do
                    _D(spellSlot)
                    if spellSlot.Amount < spellSlot.MaxAmount then
                        spellSlot.Amount = spellSlot.MaxAmount
                    end
                end
            end
            entity:Replicate("ActionResources")
        end
    end
end

local function restoreActionResource(entity, resourceType)
    local resource = Resources.getActionResource(entity, resourceType)
    if resource and resource.Amount < resource.MaxAmount then
        resource.Amount = resource.MaxAmount
        entity:Replicate("ActionResources")
    end
end

local function decreaseActionResource(uuid, resourceType, amount)
    local entity = Ext.Entity.Get(uuid)
    if entity and entity.ActionResources and entity.ActionResources.Resources then
        local resources = entity.ActionResources.Resources[Constants.ACTION_RESOURCES[resourceType]]
        if resources and resources[1] then
            if resources[1].Amount >= amount then
                resources[1].Amount = resources[1].Amount - amount
            else
                resources[1].Amount = 0.0
            end
        end
    end
    entity:Replicate("ActionResources")
end

local function checkSpellCharge(casterUuid, spellName)
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

local function hasEnoughToCastSpell(casterUuid, spellName, variant, upcastLevel)
    local entity = Ext.Entity.Get(casterUuid)
    local isSpellPrepared = false
    if not entity or not entity.SpellBookPrepares or not entity.SpellBookPrepares.PreparedSpells then
        return false
    end
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
    local spell = State.getSpellByName(spellName)
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
            if costValue and not M.Resources.checkSpellCharge(casterUuid, spellName) then
                return false
            end
        elseif costType ~= "ActionPoint" and costType ~= "BonusActionPoint" then
            if costType == "SpellSlot" then
                local spellLevel = upcastLevel == nil and costValue or upcastLevel
                local availableResourceValue = M.Osi.GetActionResourceValuePersonal(casterUuid, costType, spellLevel)
                if availableResourceValue < 1 then
                    debugPrint("SpellSlot: Needs 1 level", spellLevel, "slot to cast", spellName, ";", availableResourceValue, "slots available")
                    return false
                end
            else
                local availableResourceValue = M.Osi.GetActionResourceValuePersonal(casterUuid, costType, 0)
                if availableResourceValue ~= nil and availableResourceValue < costValue then
                    debugPrint(costType, "Needs", costValue, "to cast", spellName, ";", availableResourceValue, "available")
                    return false
                end
            end
        end
    end
    return true
end

local function completeActionInProgress(uuid, spellName)
    if State.Session.ActionsInProgress[uuid] then
        local foundActionInProgress = false
        local actionsInProgressIndex = nil
        local actionsInProgress = State.Session.ActionsInProgress[uuid]
        for i, actionInProgress in ipairs(actionsInProgress) do
            if actionInProgress.spellName == spellName then
                foundActionInProgress = true
                actionsInProgressIndex = i
                if actionInProgress.callback then actionInProgress.callback() end
                break
            end
        end
        if foundActionInProgress then
            for i = actionsInProgressIndex, 1, -1 do
                debugPrint("remove action in progress", i, M.Utils.getDisplayName(uuid), actionsInProgress[i].spellName)
                table.remove(actionsInProgress, i)
            end
        end
    end
end

local function deductCastedSpell(uuid, spellName)
    local entity = Ext.Entity.Get(uuid)
    local spell = State.getSpellByName(spellName)
    if entity and spell then
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
            elseif State.Settings.TurnBasedSwarmMode or (costType ~= "ActionPoint" and costType ~= "BonusActionPoint") then
                if costType == "SpellSlot" then
                    if entity.ActionResources and entity.ActionResources.Resources then
                        local spellSlots = entity.ActionResources.Resources[Constants.ACTION_RESOURCES[costType]]
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
                    if not Constants.ACTION_RESOURCES[costType] then
                        debugPrint("unknown costType", costType)
                    elseif entity.ActionResources and entity.ActionResources.Resources then
                        local resources = entity.ActionResources.Resources[Constants.ACTION_RESOURCES[costType]]
                        if resources then
                            local resource = resources[1] -- NB: always index 1?
                            if resource.Amount ~= nil then
                                if resource.Amount >= costValue then
                                    resource.Amount = resource.Amount - costValue
                                else
                                    resource.Amount = 0
                                end
                            end
                        end
                    end
                end
            end
        end
        entity:Replicate("ActionResources")
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

local function useSpellAndResources(casterUuid, targetUuid, spellName, variant, upcastLevel, onSubmitted, onCompleted, onFailed)
    onSubmitted = onSubmitted or noop
    onCompleted = onCompleted or noop
    onFailed = onFailed or noop
    debugPrint(M.Utils.getDisplayName(casterUuid), "casting on target", spellName, targetUuid, M.Utils.getDisplayName(targetUuid))
    if targetUuid == nil then
        return onFailed()
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
        return onFailed()
    end
    if spellRange > 2 and M.Osi.HasLineOfSight(casterUuid, targetUuid) == 0 then
        local spell = not State.getSpellByName(spellName)
        if spell and not spell.isAutoPathfinding then
            debugPrint("cast failed, no line of sight", M.Utils.getDisplayName(casterUuid), M.Utils.getDisplayName(targetUuid), spellName)
            return onFailed()
        end
    end
    State.Session.ActionsInProgress[casterUuid] = State.Session.ActionsInProgress[casterUuid] or {}
    table.insert(State.Session.ActionsInProgress[casterUuid], {spellName = spellName, callback = onCompleted})
    queueSpellRequest(casterUuid, spellName, targetUuid)
    onSubmitted()
end

return {
    getActionResource = getActionResource,
    getActionResourceMaxAmount = getActionResourceMaxAmount,
    getActionResourceAmount = getActionResourceAmount,
    restoreSpellSlots = restoreSpellSlots,
    decreaseActionResource = decreaseActionResource,
    checkSpellCharge = checkSpellCharge,
    hasEnoughToCastSpell = hasEnoughToCastSpell,
    removeActionInProgress = removeActionInProgress,
    deductCastedSpell = deductCastedSpell,
    queueSpellRequest = queueSpellRequest,
    useSpellAndResources = useSpellAndResources,
}
