Encounters = Encounters or {}
Encounters.Tracking = Encounters.Tracking or {}
Encounters.Tracking.spawned = {}

local debugPrint = Utils.debugPrint

function Encounters.Tracking.add(guid)
    if guid and guid ~= "" then Encounters.Tracking.spawned[guid] = true end
end

function Encounters.Tracking.count()
    local n = 0
    for _ in pairs(Encounters.Tracking.spawned) do n = n + 1 end
    return n
end

function Encounters.Tracking.clear()
    Encounters.Tracking.spawned = {}
end

local function onDied(entityGuid)
    local key = Osi.GetUUID(entityGuid)
    debugPrint(string.format("[Encounters DEBUG] Died: raw=%s key=%s tracked=%s count=%d",
        tostring(entityGuid), tostring(key),
        tostring(key and Encounters.Tracking.spawned[key] ~= nil),
        Encounters.Tracking.count()))
    if not key or not Encounters.Tracking.spawned[key] then return end

    Loot.dropOnKill(key)
    Encounters.Tracking.spawned[key] = nil

    if Encounters.Tracking.count() == 0 then
        debugPrint("[Encounters] all encounter enemies down — dropping bonus pile")
        Loot.dropEncounterPile()
    end
end

Ext.Osiris.RegisterListener("Died", 1, "after", onDied)
