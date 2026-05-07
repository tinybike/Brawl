Encounters = Encounters or {}

local debugPrint = Utils.debugPrint

-- Vanilla "Evil_NPC" faction. Applied AFTER the engine has merged the spawn-time splinter combats into the host's combat
-- (see applyFactionWhenMerged). Applying it earlier triggers proximity-aggro that splinters combat groups, which causes a
-- start/stop loop under AutoPauseOnCombatStart. Persistent faction is what keeps spawned enemies hostile across camp/rest.
local ENEMY_FACTION = "64321d50-d516-b1b2-cfac-2eb773de1ff6"

local function applyFactionWhenMerged(guids, host)
    if not guids or #guids == 0 or not host then return end

    local done = false
    local handle = nil

    local function applyFaction()
        local applied = 0
        for _, g in ipairs(guids) do
            if Osi.IsDead(g) ~= 1 then
                Osi.SetFaction(g, ENEMY_FACTION)
                applied = applied + 1
            end
        end
        debugPrint(string.format("[Encounters] SetFaction applied to %d/%d spawned enemies", applied, #guids))
    end

    local function isMerged()
        local hostCombat = Osi.CombatGetGuidFor(host)
        if not hostCombat or hostCombat == "" then return false end
        for _, g in ipairs(guids) do
            if Osi.IsDead(g) ~= 1 and Osi.CombatGetGuidFor(g) ~= hostCombat then
                return false
            end
        end
        return true
    end

    local function tryFinish()
        if done then return end
        if isMerged() then
            done = true
            if handle then Ext.Osiris.UnregisterListener(handle); handle = nil end
            applyFaction()
        end
    end

    tryFinish()
    if done then return end

    handle = Ext.Osiris.RegisterListener("CombatEnded", 1, "after", tryFinish)

    -- Safety cap: 30s. Apply anyway so persistent hostility still kicks in even if the engine never merged
    -- (e.g. genuine multi-combat scenario). At worst we re-trigger a tiny splinter, which by then is harmless.
    Ext.Timer.WaitFor(30000, function()
        if done then return end
        done = true
        if handle then Ext.Osiris.UnregisterListener(handle); handle = nil end
        debugPrint("[Encounters] applyFactionWhenMerged timeout (30s) — applying anyway")
        applyFaction()
    end)
end

function Encounters.testSpawn(templateUuid, distance, peaceful)
    if not templateUuid or templateUuid == "" then
        debugPrint("[Encounters] testSpawn: templateUuid required")
        return
    end
    distance = distance or 5

    local host = Osi.GetHostCharacter()
    local px, py, pz = Osi.GetPosition(host)
    local point = Spawn.findValidNear({px + distance, py, pz + distance}, 5, host)
    if not point then
        debugPrint("[Encounters] testSpawn: no valid position found near host")
        return
    end
    if peaceful then
        local guid = Osi.CreateAt(templateUuid, point[1], point[2], point[3], 0, 1, "")
        if guid and guid ~= "" then
            Osi.SetCanJoinCombat(guid, 1)
            Osi.SetCanFight(guid, 1)
        end
        return guid
    end
    return Spawn.enemyAt(templateUuid, point, host, "test")
end

function Encounters.spawnWave(templateUuid, count, radius)
    if not templateUuid or templateUuid == "" then
        debugPrint("[Encounters] spawnWave: templateUuid required")
        return
    end
    count = count or 5
    radius = radius or 14

    local host = Osi.GetHostCharacter()
    local points = SpawnPoints.ringAround(host, count, radius)
    if #points == 0 then
        debugPrint("[Encounters] spawnWave: no valid spawn points generated")
        return
    end

    local guids = {}
    for i, point in ipairs(points) do
        local guid = Spawn.enemyAt(templateUuid, point, host, "anchor " .. i)
        if guid then table.insert(guids, guid) end
    end
    debugPrint(string.format("[Encounters] spawnWave: spawned %d/%d enemies", #guids, count))
    Spawn.ensureInCombat(guids, host)
    return guids
end

local function makeHostileToAll(spawnedGuids, hostUuid, radius)
    radius = radius or 50
    local spawnedSet = {}
    for _, guid in ipairs(spawnedGuids) do spawnedSet[guid] = true end

    local nearby = Utils.getNearby(hostUuid, radius)
    local engaged = 0
    for _, nearbyUuid in ipairs(nearby) do
        if not spawnedSet[nearbyUuid]
                and Osi.IsPartyMember(nearbyUuid, 1) ~= 1
                and not Utils.isCombatHelper(nearbyUuid)
                and Osi.IsDead(nearbyUuid) ~= 1 then
            for _, spawnedGuid in ipairs(spawnedGuids) do
                Osi.SetRelationTemporaryHostile(spawnedGuid, nearbyUuid)
                Osi.SetRelationTemporaryHostile(nearbyUuid, spawnedGuid)
                Osi.EnterCombat(spawnedGuid, nearbyUuid)
                Osi.EnterCombat(nearbyUuid, spawnedGuid)
                engaged = engaged + 1
            end
        end
    end
    debugPrint(string.format("[Encounters] hostileToAll: engaged %d pairs (%dm radius)", engaged, radius))
end

function Encounters.spawnAtPlayer(opts)
    opts = opts or {}
    local host = opts.host or Osi.GetHostCharacter()
    local playerLevel = opts.levelOverride or Compositions.hostLevel(host)
    local difficultyOffset = opts.difficultyOffset or 0
    local effLevel = math.max(1, playerLevel + difficultyOffset)
    local budget = opts.budget or Compositions.tierBudgetForPlayerLevel(effLevel)
    local hostileToAll = opts.hostileToAll == true

    local picks = Compositions.pickEncounterByTier(budget)
    if #picks == 0 then
        debugPrint("[Encounters] spawnAtPlayer: pickEncounterByTier returned no picks")
        return
    end

    local anchorCount = opts.anchorCount or math.max(3, math.min(#picks, 6))
    local radius = opts.radius or 14
    local jitterM = opts.jitterM or 2

    debugPrint(string.format("[Encounters] spawnAtPlayer: playerLevel=%d (eff=%d) budget=%d → %d picks hostileToAll=%s",
        playerLevel, effLevel, budget, #picks, tostring(hostileToAll)))

    local anchors = SpawnPoints.ringAround(host, anchorCount, radius)
    if #anchors == 0 then
        debugPrint("[Encounters] spawnAtPlayer: no valid anchors generated")
        return
    end

    local guids = {}
    for slot, entry in ipairs(picks) do
        local anchorIdx = ((slot - 1) % #anchors) + 1
        local anchor = anchors[anchorIdx]
        local jx = anchor[1] + (math.random() * 2 - 1) * jitterM
        local jz = anchor[3] + (math.random() * 2 - 1) * jitterM
        local point = Spawn.findValidNear({jx, anchor[2], jz}, 3, host) or anchor

        local guid = Spawn.enemyAt(entry.uuid, point, host, string.format("enemy %d (%s)", slot, entry.tier))
        if guid then
            table.insert(guids, guid)
            Encounters.Tracking.add(guid, entry.tier)
        end
    end

    debugPrint(string.format("[Encounters] spawn: %d/%d enemies spawned", #guids, #picks))
    Spawn.ensureInCombat(guids, host)
    applyFactionWhenMerged(guids, host)

    if hostileToAll and #guids > 0 then
        Ext.Timer.WaitFor(2500, function() makeHostileToAll(guids, host) end)
    end

    return guids
end

Ext.RegisterNetListener("Encounters.SpawnAtPlayer", function(channel, payload, userId)
    local opts = {}
    if payload and payload ~= "" then
        local ok, parsed = pcall(Ext.Json.Parse, payload)
        if ok and type(parsed) == "table" then
            opts = parsed
        else
            -- Legacy/fallback: numeric payload was previously the difficultyOffset
            opts = {difficultyOffset = tonumber(payload) or 0}
        end
    end
    Encounters.spawnAtPlayer(opts)
end)
