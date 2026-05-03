Tracking = Tracking or {}
Tracking.spawned = {}

function Tracking.add(guid)
    if guid and guid ~= "" then Tracking.spawned[guid] = true end
end

function Tracking.count()
    local n = 0
    for _ in pairs(Tracking.spawned) do n = n + 1 end
    return n
end

function Tracking.clear()
    Tracking.spawned = {}
end

local function onDied(entityGuid)
    local key = Osi.GetUUID(entityGuid)
    print(string.format("[Encounters DEBUG] Died: raw=%s key=%s tracked=%s count=%d",
        tostring(entityGuid), tostring(key),
        tostring(key and Tracking.spawned[key] ~= nil),
        Tracking.count()))
    if not key or not Tracking.spawned[key] then return end

    Loot.dropOnKill(key)
    Tracking.spawned[key] = nil

    if Tracking.count() == 0 then
        print("[Encounters] all encounter enemies down — dropping bonus pile")
        Loot.dropEncounterPile()
    end
end

Ext.Osiris.RegisterListener("Died", 1, "after", onDied)
