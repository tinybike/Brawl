Encounters = Encounters or {}

function Encounters.testSpawn(templateUuid, distance)
    if not templateUuid or templateUuid == "" then
        print("[Encounters] testSpawn: templateUuid required")
        return
    end
    distance = distance or 5

    local host = Osi.GetHostCharacter()
    local px, py, pz = Osi.GetPosition(host)
    local point = Spawn.findValidNear({px + distance, py, pz + distance}, 5, host)
    if not point then
        print("[Encounters] testSpawn: no valid position found near host")
        return
    end
    return Spawn.enemyAt(templateUuid, point, host, "test")
end

function Encounters.spawnWave(templateUuid, count, radius)
    if not templateUuid or templateUuid == "" then
        print("[Encounters] spawnWave: templateUuid required")
        return
    end
    count = count or 5
    radius = radius or 14

    local host = Osi.GetHostCharacter()
    local points = SpawnPoints.ringAround(host, count, radius)
    if #points == 0 then
        print("[Encounters] spawnWave: no valid spawn points generated")
        return
    end

    local guids = {}
    for i, point in ipairs(points) do
        local guid = Spawn.enemyAt(templateUuid, point, host, "anchor " .. i)
        if guid then table.insert(guids, guid) end
    end
    print(string.format("[Encounters] spawnWave: spawned %d/%d enemies", #guids, count))
    Spawn.ensureInCombat(guids, host)
    return guids
end

local function pickForSlot(level, slot)
    if slot == 1 then return Compositions.pickBossForLevel(level) end
    return Compositions.pickFillerForLevel(level)
end

function Encounters.spawnAtPlayer(opts)
    opts = opts or {}
    local host = opts.host or Osi.GetHostCharacter()
    local level = opts.levelOverride or Compositions.hostLevel(host)
    local difficultyOffset = opts.difficultyOffset or 0
    local effLevel = math.max(1, level + difficultyOffset)
    local count = opts.count or Compositions.countForLevel(effLevel)
    local anchorCount = opts.anchorCount or math.max(3, math.min(count, 6))
    local radius = opts.radius or 14
    local jitterM = opts.jitterM or 2

    print(string.format("[Encounters] spawnAtPlayer: level %d (eff %d) → %d slots",
        level, effLevel, count))

    local anchors = SpawnPoints.ringAround(host, anchorCount, radius)
    if #anchors == 0 then
        print("[Encounters] spawnAtPlayer: no valid anchors generated")
        return
    end

    local guids = {}
    for slot = 1, count do
        local anchorIdx = ((slot - 1) % #anchors) + 1
        local anchor = anchors[anchorIdx]
        local jx = anchor[1] + (math.random() * 2 - 1) * jitterM
        local jz = anchor[3] + (math.random() * 2 - 1) * jitterM
        local point = Spawn.findValidNear({jx, anchor[2], jz}, 3, host) or anchor

        local templateUuid = pickForSlot(effLevel, slot)
        if not templateUuid then
            print(string.format("[Encounters] slot %d: pool empty", slot))
        else
            local guid = Spawn.enemyAt(templateUuid, point, host, "enemy " .. slot)
            if guid then
                table.insert(guids, guid)
                Tracking.add(guid)
            end
        end
    end

    print(string.format("[Encounters] spawn: %d/%d enemies spawned", #guids, count))
    Spawn.ensureInCombat(guids, host)
    return guids
end

Ext.RegisterNetListener("Encounters.SpawnAtPlayer", function(channel, payload, userId)
    local difficultyOffset = tonumber(payload) or 0
    Encounters.spawnAtPlayer({difficultyOffset = difficultyOffset})
end)
