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
    for costType, costValue in pairs(spell.costs) do
        if costType == "ShortRest" or costType == "LongRest" then
            if costValue and not M.Resources.checkSpellCharge(casterUuid, spellName) then
                return false
            end
        elseif costType ~= "ActionPoint" and costType ~= "BonusActionPoint" then
            if costType == "SpellSlot" or costType == "WarlockSpellSlot" then
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
    end
    return true
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
                                print("setting Charged to false", spellName, M.Utils.getDisplayName(uuid))
                                entity:Replicate("SpellBook")
                                break
                            end
                        end
                    end
                end
            -- elseif State.Settings.TurnBasedSwarmMode or (costType ~= "ActionPoint" and costType ~= "BonusActionPoint") then
            --     if costType == "SpellSlot" then
            --         if entity.ActionResources and entity.ActionResources.Resources then
            --             local spellSlots = entity.ActionResources.Resources[Constants.ACTION_RESOURCES[costType]]
            --             if spellSlots then
            --                 for _, spellSlot in ipairs(spellSlots) do
            --                     if spellSlot.Level >= costValue and spellSlot.Amount > 0 then
            --                         spellSlot.Amount = spellSlot.Amount - 1
            --                         break
            --                     end
            --                 end
            --             end
            --         end
            --     else
            --         if not Constants.ACTION_RESOURCES[costType] then
            --             debugPrint("unknown costType", costType)
            --         elseif entity.ActionResources and entity.ActionResources.Resources then
            --             local resources = entity.ActionResources.Resources[Constants.ACTION_RESOURCES[costType]]
            --             if resources then
            --                 local resource = resources[1] -- NB: always index 1?
            --                 if resource.Amount ~= nil then
            --                     if resource.Amount >= costValue then
            --                         resource.Amount = resource.Amount - costValue
            --                     else
            --                         resource.Amount = 0
            --                     end
            --                 end
            --             end
            --         end
            --     end
            end
        end
        entity:Replicate("ActionResources")
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
    checkSpellCharge = checkSpellCharge,
    hasEnoughToCastSpell = hasEnoughToCastSpell,
    deductCastedSpell = deductCastedSpell,
}
