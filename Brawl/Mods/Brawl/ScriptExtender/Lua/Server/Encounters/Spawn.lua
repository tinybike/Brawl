Spawn = Spawn or {}

local debugPrint = Utils.debugPrint

local function setHostileToParty(spawnedGuid)
    for _, pm in pairs(Osi.DB_PartyMembers:Get(nil)) do
        local pmUuid = pm[1]
        if pmUuid then
            Osi.SetRelationTemporaryHostile(spawnedGuid, pmUuid)
            Osi.SetRelationTemporaryHostile(pmUuid, spawnedGuid)
        end
    end
end

function Spawn.enemyAt(templateUuid, point, host, label)
    if not templateUuid or templateUuid == "" then return nil end
    local guid = Osi.CreateAt(templateUuid, point[1], point[2], point[3], 0, 1, "")
    if not guid or guid == "" then
        local tmpl = Ext.Template and Ext.Template.GetTemplate and Ext.Template.GetTemplate(templateUuid)
        if tmpl then
            debugPrint(string.format("[Encounters] CreateAt failed at %s template=%s name=%s stats=%s parent=%s equip=%s",
                label or "?", tostring(templateUuid),
                tostring(tmpl.Name), tostring(tmpl.Stats),
                tostring(tmpl.ParentTemplateId), tostring(tmpl.Equipment ~= "" and tmpl.Equipment or "(empty)")))
        else
            debugPrint(string.format("[Encounters] CreateAt failed at %s template=%s (Ext.Template.GetTemplate returned nil — template not registered)",
                label or "?", tostring(templateUuid)))
        end
        return nil
    end
    Osi.SetCanJoinCombat(guid, 1)
    Osi.SetCanFight(guid, 1)
    setHostileToParty(guid)
    if host then
        Osi.EnterCombat(host, guid)
        Osi.EnterCombat(guid, host)
    end
    debugPrint(string.format("[Encounters] Spawned %s at %s (%.1f, %.1f, %.1f)",
        guid, label or "?", point[1], point[2], point[3]))
    return guid
end

function Spawn.findValidNear(point, radius, anchorUuid)
    local vx, vy, vz = Osi.FindValidPosition(point[1], point[2], point[3], radius or 5, anchorUuid, 1)
    if not vx then return nil end
    local cx = Osi.FindValidPosition(vx, vy, vz, 0, anchorUuid, 1)
    if not cx then return nil end
    return {vx, vy, vz}
end

function Spawn.ensureInCombat(guids, host, retriesLeft, delayMs)
    if not guids or #guids == 0 or not host then return end
    retriesLeft = retriesLeft or 2
    delayMs = delayMs or 2000

    Ext.Timer.WaitFor(delayMs, function()
        local stillNotInCombat = {}
        for _, guid in ipairs(guids) do
            if Osi.IsDead(guid) ~= 1 and Osi.IsInCombat(guid) ~= 1 then
                Osi.SetVisible(guid, 1)
                setHostileToParty(guid)
                Osi.EnterCombat(host, guid)
                Osi.EnterCombat(guid, host)
                table.insert(stillNotInCombat, guid)
            end
        end

        if #stillNotInCombat == 0 then return end

        if retriesLeft > 0 then
            Spawn.ensureInCombat(stillNotInCombat, host, retriesLeft - 1, delayMs)
        else
            debugPrint(string.format("[Encounters] %d enemies remained out of combat after retries", #stillNotInCombat))
        end
    end)
end
