SpawnPoints = SpawnPoints or {}

function SpawnPoints.ringAround(originUuid, n, radius)
    n = n or 5
    radius = radius or 14
    local ox, oy, oz = Osi.GetPosition(originUuid)
    if not ox then return {} end

    local points = {}
    for i = 1, n do
        local theta = (i - 1) * (2 * math.pi / n)
        local rawX = ox + radius * math.cos(theta)
        local rawZ = oz + radius * math.sin(theta)
        local point = Spawn.findValidNear({rawX, oy, rawZ}, 5, originUuid)
        if point then
            table.insert(points, point)
        else
            print(string.format("[Encounters] anchor %d at (%.1f, %.1f, %.1f) invalid; skipping",
                i, rawX, oy, rawZ))
        end
    end
    return points
end
