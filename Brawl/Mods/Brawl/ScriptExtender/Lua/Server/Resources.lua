local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump

local function getActionResource(entity, resourceType)
    if entity and entity.ActionResources and entity.ActionResources.Resources then
        local resources = entity.ActionResources.Resources
        if resources[Constants.ACTION_RESOURCES[resourceType]] and resources[Constants.ACTION_RESOURCES[resourceType]][1] then
            return resources[Constants.ACTION_RESOURCES[resourceType]][1]
        end
    end
end

local function getActionResourceMaxAmount(entity, resourceType)
    return (getActionResource(entity, resourceType) or {}).MaxAmount
end

local function getActionResourceAmount(entity, resourceType)
    return (getActionResource(entity, resourceType) or {}).Amount
end

local function getActionPointsRemaining(uuid)
    return getActionResourceAmount(Ext.Entity.Get(uuid), "ActionPoint") or 0
end

local function getBonusActionPointsRemaining(uuid)
    return getActionResourceAmount(Ext.Entity.Get(uuid), "BonusActionPoint") or 0
end

local function restoreSpellSlots(uuid)
    if uuid then
        local entity = Ext.Entity.Get(uuid)
        if entity and entity.ActionResources and entity.ActionResources.Resources then
            local spellSlots = entity.ActionResources.Resources[Constants.ACTION_RESOURCES.SpellSlot]
            if spellSlots then
                for _, spellSlot in ipairs(spellSlots) do
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
    local resource = getActionResource(entity, resourceType)
    if resource and resource.Amount < resource.MaxAmount then
        resource.Amount = resource.MaxAmount
        entity:Replicate("ActionResources")
    end
end

local function getActionResourceInfo(uuid)
    return Ext.StaticData.Get(uuid, "ActionResource")
end

local function getActionResourceName(uuid)
    local actionResourceInfo = getActionResourceInfo(uuid)
    if actionResourceInfo then
        return actionResourceInfo.Name
    end
end

-- thank u celerev and hippo0o
local function restoreAllActionResources(entityUuid)
    local entity = Ext.Entity.Get(entityUuid)
    if entity and entity.ActionResources and entity.ActionResources.Resources then
        for resourceUuid, resourceList in pairs(entity.ActionResources.Resources) do
            for _, resource in pairs(resourceList) do
                local actionResourceInfo = M.Resources.getActionResourceInfo(resource.ResourceUUID)
                if actionResourceInfo and actionResourceInfo.Name and not actionResourceInfo.IsSpellResource then
                    debugPrint("restoring resource", M.Utils.getDisplayName(entityUuid), actionResourceInfo.Name)
                    resource.Amount = resource.MaxAmount
                end
            end
        end
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

local function refillTimerComplete(brawler, resourceType)
    if brawler and brawler.uuid and brawler.actionResources and brawler.actionResources[resourceType] then
        local entity = Ext.Entity.Get(brawler.uuid)
        if entity then
            local uuid = brawler.uuid
            local resource = Resources.getActionResource(entity, resourceType)
            if resource then
                local updatedAmount = math.min(resource.MaxAmount, resource.Amount + 1)
                resource.Amount = updatedAmount
                brawler.actionResources[resourceType].amount = updatedAmount
                print("refillTimerComplete", brawler.displayName, resourceType, updatedAmount)
                entity:Replicate("ActionResources")
            end
        end
    end
end

local function actionResourcesCallback(entity, _, _)
    if not State.Settings.TurnBasedSwarmMode and entity and entity.Uuid and entity.Uuid.EntityUuid then
        if Pause.isInFTB(entity) then
            return restoreActionResource(entity, "Movement")
        end
        local uuid = entity.Uuid.EntityUuid
        local brawler = Roster.getBrawlerByUuid(uuid)
        if brawler then
            for _, resourceType in ipairs(Constants.PER_TURN_ACTION_RESOURCES) do
                local savedActionResource = brawler.actionResources[resourceType]
                if savedActionResource and savedActionResource.amount then
                    local resource = getActionResource(entity, resourceType)
                    if resource and resource.Amount then
                        -- was this a decrease? if so, create timer for refilling 1 point
                        -- just compare to max amount? does that work for things like Haste?
                        -- print("Resource comparison:", resource.Amount, savedActionResource.amount, resource.Amount < savedActionResource.amount, resource.MaxAmount)
                        if resource.Amount < savedActionResource.amount then
                            table.insert(savedActionResource.refillQueue, Ext.Timer.WaitFor(brawler.actionInterval, function ()
                                refillTimerComplete(brawler, resourceType)
                            end))
                        end
                        savedActionResource.amount = resource.Amount
                    end
                end
            end
        end
    end
end

local function pauseActionResourcesRefillTimers(brawler)
    if brawler and brawler.actionResources then
        for _, resourceType in ipairs(Constants.PER_TURN_ACTION_RESOURCES) do
            if brawler.actionResources[resourceType] then
                local refillQueue = brawler.actionResources[resourceType].refillQueue
                if refillQueue then
                    for _, refillTimer in ipairs(refillQueue) do
                        Ext.Timer.Pause(refillTimer)
                    end
                end
            end
        end
    end
end

local function resumeActionResourcesRefillTimers(brawler)
    if brawler and brawler.actionResources then
        for _, resourceType in ipairs(Constants.PER_TURN_ACTION_RESOURCES) do
            if brawler.actionResources[resourceType] then
                local refillQueue = brawler.actionResources[resourceType].refillQueue
                if refillQueue then
                    for _, refillTimer in ipairs(refillQueue) do
                        print(brawler.displayName, "resume timer for", resourceType)
                        Ext.Timer.Resume(refillTimer)
                    end
                end
            end
        end
    end
end

local function isSpellPrepared(uuid, spellName)
    local entity = Ext.Entity.Get(uuid)
    if entity and entity.SpellBookPrepares and entity.SpellBookPrepares.PreparedSpells then
        for _, preparedSpell in ipairs(entity.SpellBookPrepares.PreparedSpells) do
            if preparedSpell.OriginatorPrototype == spellName then
                return true
            end
        end
    end
end

local function isSpellOnCooldown(uuid, spellName)
    if not spellName or not uuid then
        return false
    end
    local entity = Ext.Entity.Get(uuid)
    if not entity then
        return false
    end
    if entity.SpellBookCooldowns and entity.SpellBookCooldowns.Cooldowns then
        for _, cooldown in ipairs(entity.SpellBookCooldowns.Cooldowns) do
            if cooldown.SpellId.OriginatorPrototype ~= cooldown.SpellId.Prototype then
                print(M.Utils.getDisplayName(uuid), "OriginatorPrototype and Prototype don't match, what is this?")
                _D(cooldown)
            end
            if cooldown.SpellId and cooldown.SpellId.OriginatorPrototype == spellName then
                debugPrint(M.Utils.getDisplayName(uuid), "spell on cooldown", spellName, uuid)
                return false
            end
        end
    end
    return true
end

local function hasEnoughToCastSpell(casterUuid, spellName, variant, upcastLevel)
    if not M.Resources.isSpellPrepared(casterUuid, spellName) then
        debugPrint("Caster does not have spell", spellName, "prepared")
        return false
    end
    if variant ~= nil then
        spellName = variant
    end
    local spell = M.Spells.getSpellByName(spellName)
    if not spell then
        debugPrint("Error: spell not found")
        return false
    end
    for costType, costValue in pairs(spell.costs) do
        if costType == "LongRest" or costType == "ShortRest" then
            if costValue and not M.Resources.isSpellOnCooldown(casterUuid, spellName) then
                return false
            end
        elseif costType == "SpellSlot" or costType == "WarlockSpellSlot" then
            local spellLevel = upcastLevel == nil and costValue or upcastLevel
            local availableResourceValue = M.Osi.GetActionResourceValuePersonal(casterUuid, costType, spellLevel)
            if availableResourceValue < 1 then
                debugPrint(costType, "Needs 1 level", spellLevel, "slot to cast", spellName, ";", availableResourceValue, "slots available")
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
    return true
end

local function getPreparedSpell(entity, spellName)
    if entity and entity.SpellBookPrepares and entity.SpellBookPrepares.PreparedSpells then
        for _, preparedSpell in ipairs(entity.SpellBookPrepares.PreparedSpells) do
            if preparedSpell.OriginatorPrototype == spellName then
                return preparedSpell
            end
        end
    end
end

return {
    getActionResource = getActionResource,
    getActionResourceMaxAmount = getActionResourceMaxAmount,
    getActionResourceAmount = getActionResourceAmount,
    getActionResourceInfo = getActionResourceInfo,
    getActionResourceName = getActionResourceName,
    getActionPointsRemaining = getActionPointsRemaining,
    getBonusActionPointsRemaining = getBonusActionPointsRemaining,
    restoreAllActionResources = restoreAllActionResources,
    restoreActionResource = restoreActionResource,
    restoreSpellSlots = restoreSpellSlots,
    decreaseActionResource = decreaseActionResource,
    actionResourcesCallback = actionResourcesCallback,
    pauseActionResourcesRefillTimers = pauseActionResourcesRefillTimers,
    resumeActionResourcesRefillTimers = resumeActionResourcesRefillTimers,
    isSpellPrepared = isSpellPrepared,
    isSpellOnCooldown = isSpellOnCooldown,
    hasEnoughToCastSpell = hasEnoughToCastSpell,
}
