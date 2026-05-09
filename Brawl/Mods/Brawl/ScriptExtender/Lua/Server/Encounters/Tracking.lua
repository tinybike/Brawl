Encounters = Encounters or {}
Encounters.Tracking = Encounters.Tracking or {}
Encounters.Tracking.spawned = {}             -- { [uuid] = { tier = "..." } }
Encounters.Tracking.pendingPileScore = 0     -- accumulated tier value of slain tracked enemies

local debugPrint = Utils.debugPrint
local trace = function(s) print("[EncTrack] " .. s) end  -- always-on; volume is tiny per encounter

function Encounters.Tracking.add(guid, tier)
    if guid and guid ~= "" then
        Encounters.Tracking.spawned[guid] = { tier = tier }
        trace(string.format("add %s tier=%s count=%d", tostring(guid), tostring(tier), Encounters.Tracking.count()))
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

-- Credit a tracked kill: drop kill-loot, accumulate pile score, drop pile if count -> 0.
-- Idempotent against double-call: returns early if uuid no longer in `spawned`.
local function creditKill(uuid)
    local rec = Encounters.Tracking.spawned[uuid]
    if not rec then return end
    Loot.dropOnKill(uuid)
    Encounters.Tracking.pendingPileScore = Encounters.Tracking.pendingPileScore + Compositions.tierValue(rec.tier)
    Encounters.Tracking.spawned[uuid] = nil
    trace(string.format("kill %s tier=%s pileScore=%d remaining=%d",
        tostring(uuid), tostring(rec.tier), Encounters.Tracking.pendingPileScore, Encounters.Tracking.count()))
    if Encounters.Tracking.count() == 0 then
        local rolls = Encounters.Tracking.pendingPileScore
        Encounters.Tracking.pendingPileScore = 0
        trace(string.format("all down -- pile rolls=%d", rolls))
        Loot.dropEncounterPile(nil, rolls)
    end
end

-- Only purge DEAD entries; alive spawns (fled, mid-fight, just-spawned during a brief combat-end flicker) persist.
-- Credits dead entries as kills so endBrawl racing ahead of the Died event still drops the pile.
function Encounters.Tracking.pruneDead()
    local removed = 0
    local deadUuids = {}
    for uuid, _ in pairs(Encounters.Tracking.spawned) do
        if not uuid or uuid == "" then
            Encounters.Tracking.spawned[uuid] = nil
            removed = removed + 1
        elseif Osi.IsDead(uuid) == 1 then
            deadUuids[#deadUuids + 1] = uuid
        end
    end
    for _, uuid in ipairs(deadUuids) do
        creditKill(uuid)
        removed = removed + 1
    end
    if removed > 0 then
        trace(string.format("pruneDead removed=%d remaining=%d", removed, Encounters.Tracking.count()))
    elseif Encounters.Tracking.count() > 0 then
        trace(string.format("pruneDead noop -- %d still alive in spawned", Encounters.Tracking.count()))
    end
end

-- Remove any surviving Brawl-spawned entities. Called on long rest. NOT on combat-end (would nuke fresh spawns).
function Encounters.Tracking.removeAllSurvivors()
    local removed = 0
    for uuid, _ in pairs(Encounters.Tracking.spawned) do
        if uuid and uuid ~= "" and Osi.IsDead(uuid) == 0 then
            Utils.remove(uuid)
            removed = removed + 1
        end
    end
    if removed > 0 then
        trace(string.format("removeAllSurvivors removed=%d", removed))
    end
    Encounters.Tracking.clear()
end

local function onDied(entityGuid)
    local key = Osi.GetUUID(entityGuid)
    if not key then return end
    creditKill(key)
end

Ext.Osiris.RegisterListener("Died", 1, "after", onDied)
