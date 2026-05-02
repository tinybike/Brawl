Spawn = Spawn or {}

local ENEMY_FACTION = "64321d50-d516-b1b2-cfac-2eb773de1ff6"

function Spawn.enemyAt(templateUuid, point, host, label)
    if not templateUuid or templateUuid == "" then return nil end
    local guid = Osi.CreateAt(templateUuid, point[1], point[2], point[3], 0, 1, "")
    if not guid or guid == "" then
        print("[Encounters] CreateAt failed at", label or "?")
        return nil
    end
    Osi.SetFaction(guid, ENEMY_FACTION)
    Osi.SetCanJoinCombat(guid, 1)
    Osi.SetCanFight(guid, 1)
    if host then
        Osi.EnterCombat(host, guid)
        Osi.EnterCombat(guid, host)
    end
    print(string.format("[Encounters] Spawned %s at %s (%.1f, %.1f, %.1f)",
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
        local hostFaction = Osi.GetFaction(host)
        if not hostFaction or hostFaction == "" then return end

        local stillNotInCombat = {}
        for _, guid in ipairs(guids) do
            if Osi.IsDead(guid) ~= 1 and Osi.IsInCombat(guid) ~= 1 then
                Osi.SetVisible(guid, 1)
                Osi.SetHostileAndEnterCombat(ENEMY_FACTION, hostFaction, guid, host)
                table.insert(stillNotInCombat, guid)
            end
        end

        if #stillNotInCombat == 0 then return end

        if retriesLeft > 0 then
            Spawn.ensureInCombat(stillNotInCombat, host, retriesLeft - 1, delayMs)
        else
            print(string.format("[Encounters] %d enemies remained out of combat after retries", #stillNotInCombat))
        end
    end)
end
