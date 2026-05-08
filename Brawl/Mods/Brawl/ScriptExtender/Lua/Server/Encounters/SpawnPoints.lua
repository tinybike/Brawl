SpawnPoints = SpawnPoints or {}

local debugPrint = Utils.debugPrint

-- If minRadius is provided, each anchor's radius is randomized in [minRadius, maxRadius] so the encounter
-- isn't all on one ring. Otherwise behaves as a fixed-radius ring with fallback shrink attempts.
function SpawnPoints.ringAround(originUuid, n, maxRadius, minRadius)
    n = n or 5
    maxRadius = maxRadius or 14
    local ox, oy, oz = Osi.GetPosition(originUuid)
    if not ox then return {} end

    local thetaOffset = math.random() * 2 * math.pi

    if minRadius then
        local points = {}
        for i = 1, n do
            local theta = thetaOffset + (i - 1) * (2 * math.pi / n)
            local r = minRadius + math.random() * (maxRadius - minRadius)
            local rawX = ox + r * math.cos(theta)
            local rawZ = oz + r * math.sin(theta)
            local point = Spawn.findValidNear({rawX, oy, rawZ}, 5, originUuid)
            if point then table.insert(points, point) end
        end
        debugPrint(string.format("[Encounters] ring: %d/%d anchors in [%.1fm, %.1fm]", #points, n, minRadius, maxRadius))
        return points
    end

    local attempts = { maxRadius, maxRadius * 0.6, maxRadius * 0.35, maxRadius * 0.2 }
    for _, r in ipairs(attempts) do
        local points = {}
        for i = 1, n do
            local theta = thetaOffset + (i - 1) * (2 * math.pi / n)
            local rawX = ox + r * math.cos(theta)
            local rawZ = oz + r * math.sin(theta)
            local point = Spawn.findValidNear({rawX, oy, rawZ}, 5, originUuid)
            if point then table.insert(points, point) end
        end
        if #points > 0 then
            debugPrint(string.format("[Encounters] ring: %d/%d anchors at radius %.1fm", #points, n, r))
            return points
        end
    end

    debugPrint("[Encounters] ring: no valid anchors at any radius")
    return {}
end
