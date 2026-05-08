Encounters = Encounters or {}
Encounters.Tracking = Encounters.Tracking or {}
Encounters.Tracking.spawned = {}             -- { [uuid] = { tier = "..." } }
Encounters.Tracking.pendingPileScore = 0     -- accumulated tier value of slain tracked enemies

local debugPrint = Utils.debugPrint

function Encounters.Tracking.add(guid, tier)
    if guid and guid ~= "" then
        Encounters.Tracking.spawned[guid] = { tier = tier }
    end
end

function Encounters.Tracking.count()
    local n = 0
    for _ in pairs(Encounters.Tracking.spawned) do n = n + 1 end
    return n
end

function Encounters.Tracking.clear()
    Encounters.Tracking.spawned = {}
    Encounters.Tracking.pendingPileScore = 0
end

-- On combat end: remove any surviving Brawl-spawned entities and clear tracking. Prevents corpse/survivor
-- buildup from repeated spawns. Loot from kills already dropped in onDied; survivors (player fled) get culled.
function Encounters.Tracking.removeSurvivorsAndClear()
    local removed = 0
    for uuid, _ in pairs(Encounters.Tracking.spawned) do
        if uuid and uuid ~= "" and Osi.IsDead(uuid) ~= 1 then
            Utils.remove(uuid)
            removed = removed + 1
        end
    end
    if removed > 0 then
        debugPrint(string.format("[Encounters] removeSurvivorsAndClear: removed %d surviving spawned entities", removed))
    end
    Encounters.Tracking.clear()
end

local function onDied(entityGuid)
    local key = Osi.GetUUID(entityGuid)
    if not key then return end
    local rec = Encounters.Tracking.spawned[key]
    if not rec then return end

    Loot.dropOnKill(key)
    Encounters.Tracking.pendingPileScore = Encounters.Tracking.pendingPileScore + Compositions.tierValue(rec.tier)
    Encounters.Tracking.spawned[key] = nil
    debugPrint(string.format("[Encounters] tracked kill: %s tier=%s pileScore=%d remaining=%d",
        tostring(key), tostring(rec.tier), Encounters.Tracking.pendingPileScore, Encounters.Tracking.count()))

    if Encounters.Tracking.count() == 0 then
        local rolls = Encounters.Tracking.pendingPileScore
        Encounters.Tracking.pendingPileScore = 0
        debugPrint(string.format("[Encounters] all encounter enemies down — pile rolls=%d", rolls))
        Loot.dropEncounterPile(nil, rolls)
    end
end

Ext.Osiris.RegisterListener("Died", 1, "after", onDied)
