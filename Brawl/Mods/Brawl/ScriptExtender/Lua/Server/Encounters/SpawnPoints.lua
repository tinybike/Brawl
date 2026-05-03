SpawnPoints = SpawnPoints or {}

function SpawnPoints.ringAround(originUuid, n, radius)
    n = n or 5
    radius = radius or 14
    local ox, oy, oz = Osi.GetPosition(originUuid)
    if not ox then return {} end

    local thetaOffset = math.random() * 2 * math.pi
    local attempts = { radius, radius * 0.6, radius * 0.35, radius * 0.2 }

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
            print(string.format("[Encounters] ring: %d/%d anchors at radius %.1fm", #points, n, r))
            return points
        end
    end

    print("[Encounters] ring: no valid anchors at any radius")
    return {}
end
