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

local function pickTemplate(tierTemplates, tier)
    local choices = tierTemplates and tierTemplates[tier]
    if not choices or #choices == 0 then return nil end
    return choices[math.random(1, #choices)]
end

function Encounters.spawn(opts)
    if not opts or not opts.composition then
        print("[Encounters] spawn: opts.composition required")
        return
    end
    if not opts.tierTemplates then
        print("[Encounters] spawn: opts.tierTemplates required")
        return
    end

    local host = opts.host or Osi.GetHostCharacter()
    local anchorCount = opts.anchorCount or math.max(3, math.min(#opts.composition, 6))
    local radius = opts.radius or 14
    local jitterM = opts.jitterM or 2

    local anchors = SpawnPoints.ringAround(host, anchorCount, radius)
    if #anchors == 0 then
        print("[Encounters] spawn: no valid anchors generated")
        return
    end

    local guids = {}
    for i, tier in ipairs(opts.composition) do
        local anchorIdx = ((i - 1) % #anchors) + 1
        local anchor = anchors[anchorIdx]
        local jx = anchor[1] + (math.random() * 2 - 1) * jitterM
        local jz = anchor[3] + (math.random() * 2 - 1) * jitterM
        local point = Spawn.findValidNear({jx, anchor[2], jz}, 3, host)
        if not point then
            print(string.format("[Encounters] enemy %d (%s): no valid position; skipping", i, tier))
        else
            local templateUuid = pickTemplate(opts.tierTemplates, tier)
            if not templateUuid then
                print("[Encounters] no template for tier:", tostring(tier))
            else
                local guid = Spawn.enemyAt(templateUuid, point, host, "enemy " .. i)
                if guid then table.insert(guids, guid) end
            end
        end
    end

    print(string.format("[Encounters] spawn: %d/%d enemies spawned", #guids, #opts.composition))
    Spawn.ensureInCombat(guids, host)
    return guids
end
