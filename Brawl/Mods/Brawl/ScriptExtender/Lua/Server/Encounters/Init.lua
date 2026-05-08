Encounters = Encounters or {}

local debugPrint = Utils.debugPrint

local function getAutoSpawnOnCombatStart()
    return Ext.Vars.GetModVariables(ModuleUUID).AutoSpawnEncounterOnCombatStart == true
end

local function setAutoSpawnOnCombatStart(enabled)
    Ext.Vars.GetModVariables(ModuleUUID).AutoSpawnEncounterOnCombatStart = (enabled == true)
end

local function getHostileToAllEncounter()
    return Ext.Vars.GetModVariables(ModuleUUID).HostileToAllEncounter == true
end

local function setHostileToAllEncounter(enabled)
    Ext.Vars.GetModVariables(ModuleUUID).HostileToAllEncounter = (enabled == true)
end

Encounters.getAutoSpawnOnCombatStart = getAutoSpawnOnCombatStart
Encounters.setAutoSpawnOnCombatStart = setAutoSpawnOnCombatStart
Encounters.getHostileToAllEncounter = getHostileToAllEncounter
Encounters.setHostileToAllEncounter = setHostileToAllEncounter

-- Vanilla "Evil_NPC" faction. Normally applied via applyFactionWhenMerged (deferred to avoid splinter/autopause loop);
-- hostileToAll spawns apply it immediately because the merge wait never resolves and the late SetFaction breaks bystander hostility.
local ENEMY_FACTION = "64321d50-d516-b1b2-cfac-2eb773de1ff6"

local function applyFactionImmediately(guids)
    local applied = 0
    for _, g in ipairs(guids) do
        if Osi.IsDead(g) ~= 1 then
            Osi.SetFaction(g, ENEMY_FACTION)
            applied = applied + 1
        end
    end
    debugPrint(string.format("[Encounters] hostileToAll: SetFaction applied immediately to %d/%d", applied, #guids))
end

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

local ENGAGEMENT_RANGE_M = 7  -- engine's flat engagement range; per-enemy search radius for hostile-to-all pull-in

local function makeHostileToAll(spawnedGuids)
    local spawnedSet = {}
    for _, guid in ipairs(spawnedGuids) do spawnedSet[guid] = true end

    local bystanderSet = {}
    for _, spawnedGuid in ipairs(spawnedGuids) do
        for _, candidateUuid in ipairs(Utils.getNearby(spawnedGuid, ENGAGEMENT_RANGE_M)) do
            if not spawnedSet[candidateUuid]
                    and not bystanderSet[candidateUuid]
                    and Osi.IsPartyMember(candidateUuid, 1) ~= 1
                    and not Utils.isCombatHelper(candidateUuid)
                    and Osi.IsDead(candidateUuid) ~= 1 then
                bystanderSet[candidateUuid] = true
            end
        end
    end

    local bystanderCount = 0
    for _ in pairs(bystanderSet) do bystanderCount = bystanderCount + 1 end

    local engaged = 0
    for bystanderUuid in pairs(bystanderSet) do
        for _, spawnedGuid in ipairs(spawnedGuids) do
            Osi.SetRelationTemporaryHostile(spawnedGuid, bystanderUuid)
            Osi.SetRelationTemporaryHostile(bystanderUuid, spawnedGuid)
            Osi.EnterCombat(spawnedGuid, bystanderUuid)
            Osi.EnterCombat(bystanderUuid, spawnedGuid)
            engaged = engaged + 1
        end
    end
    debugPrint(string.format("[Encounters] hostileToAll: %d bystanders, %d pairs engaged", bystanderCount, engaged))
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

    local anchorCount = opts.anchorCount or math.max(3, #picks)  -- one anchor per pick, no shared spawn positions
    local maxRadius = opts.maxRadius or opts.radius or 11
    local minRadius = opts.minRadius or 5
    local jitterM = opts.jitterM or 0

    debugPrint(string.format("[Encounters] spawnAtPlayer: playerLevel=%d (eff=%d) budget=%d → %d picks hostileToAll=%s",
        playerLevel, effLevel, budget, #picks, tostring(hostileToAll)))

    local anchors = SpawnPoints.ringAround(host, anchorCount, maxRadius, minRadius)
    if #anchors == 0 then
        debugPrint("[Encounters] spawnAtPlayer: no valid anchors generated")
        return
    end

    -- One-shot suppress so the resulting CombatStarted doesn't recursively trigger auto-spawn.
    -- Set after early-returns so failed spawns don't strand the flag. Safety timer auto-clears if no CombatStarted fires
    -- (e.g. user already in combat -> EnterCombat extends existing combat without firing CombatStarted).
    Encounters.SuppressNextAutoSpawn = true
    Ext.Timer.WaitFor(5000, function() Encounters.SuppressNextAutoSpawn = false end)

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

    if hostileToAll and #guids > 0 then
        applyFactionImmediately(guids)
        Ext.Timer.WaitFor(2500, function() makeHostileToAll(guids) end)
    else
        applyFactionWhenMerged(guids, host)
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
    -- MP: spawn at the requesting user's controlled character, not always the host's
    if not opts.host then
        local player = State.getPlayerByUserId(Utils.peerToUserId(userId))
        if player and player.uuid then opts.host = player.uuid end
    end
    Encounters.spawnAtPlayer(opts)
end)

Ext.RegisterNetListener("Encounters.SetAutoSpawnOnCombatStart", function(channel, payload, userId)
    setAutoSpawnOnCombatStart(payload == "true")
    debugPrint(string.format("[Encounters] AutoSpawnOnCombatStart = %s", tostring(getAutoSpawnOnCombatStart())))
end)

Ext.RegisterNetListener("Encounters.RequestAutoSpawnState", function(channel, payload, userId)
    Ext.ServerNet.PostMessageToUser(userId, "Encounters.AutoSpawnState", tostring(getAutoSpawnOnCombatStart()))
end)

Ext.RegisterNetListener("Encounters.SetHostileToAll", function(channel, payload, userId)
    setHostileToAllEncounter(payload == "true")
    debugPrint(string.format("[Encounters] HostileToAllEncounter = %s", tostring(getHostileToAllEncounter())))
end)

Ext.RegisterNetListener("Encounters.RequestHostileToAllState", function(channel, payload, userId)
    Ext.ServerNet.PostMessageToUser(userId, "Encounters.HostileToAllState", tostring(getHostileToAllEncounter()))
end)

-- Auto-spawn on natural fights (skipped for menu-initiated ones via SuppressNextAutoSpawn).
Ext.Osiris.RegisterListener("CombatStarted", 1, "after", function(combatGuid)
    if Encounters.SuppressNextAutoSpawn then
        Encounters.SuppressNextAutoSpawn = false
        return
    end
    if not getAutoSpawnOnCombatStart() then return end
    Encounters.spawnAtPlayer({hostileToAll = getHostileToAllEncounter()})
end)
