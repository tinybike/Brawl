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
            if costValue and not checkSpellCharge(casterUuid, spellName) then
                return false
            end
        elseif costType ~= "ActionPoint" and costType ~= "BonusActionPoint" then
            if costType == "SpellSlot" then
                local spellLevel = upcastLevel == nil and costValue or upcastLevel
                local availableResourceValue = Osi.GetActionResourceValuePersonal(casterUuid, costType, spellLevel)
                if availableResourceValue < 1 then
                    debugPrint("SpellSlot: Needs 1 level", spellLevel, "slot to cast", spellName, ";", availableResourceValue, "slots available")
                    return false
                end
            else
                local availableResourceValue = Osi.GetActionResourceValuePersonal(casterUuid, costType, 0)
                if availableResourceValue < costValue then
                    debugPrint(costType, "Needs", costValue, "to cast", spellName, ";", availableResourceValue, "available")
                    return false
                end
            end
        end
    end
    return true
end
local function removeActionInProgress(uuid, spellName)
    debugPrint("removeActionInProgress", uuid, spellName)
    if State.Session.ActionsInProgress[uuid] then
        local foundActionInProgress = false
        local actionsInProgressIndex = nil
        for i, actionInProgress in ipairs(State.Session.ActionsInProgress[uuid]) do
            if actionInProgress == spellName then
                foundActionInProgress = true
                actionsInProgressIndex = i
                break
            end
        end
        if foundActionInProgress then
            for i = actionsInProgressIndex, 1, -1 do
                debugPrint("remove action in progress", i, getDisplayName(uuid), State.Session.ActionsInProgress[uuid])
                table.remove(State.Session.ActionsInProgress[uuid], i)
            end
            return true
        end
    end
    return false
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
            elseif costType ~= "ActionPoint" and costType ~= "BonusActionPoint" then
                if costType == "SpellSlot" then
                    if entity.ActionResources and entity.ActionResources.Resources then
                        local spellSlots = entity.ActionResources.Resources[ACTION_RESOURCES[costType]]
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
                    if entity.ActionResources and entity.ActionResources.Resources then
                        local resources = entity.ActionResources.Resources[ACTION_RESOURCES[costType]]
                        if resources then
                            local resource = resources[1] -- NB: always index 1?
                            resource.Amount = resource.Amount - costValue
                        end
                    end
                end
            end
        end
        entity:Replicate("ActionResources")
    end
end

Resources = {
    hasEnoughToCastSpell = hasEnoughToCastSpell,
    removeActionInProgress = removeActionInProgress,
    deductCastedSpell = deductCastedSpell,
}
