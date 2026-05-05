Compositions = Compositions or {}

local debugPrint = Utils.debugPrint
local SOE_MOD_UUID = "a27fdbe3-4d1a-641d-d05f-1ba4ee529da8"

local TIER_VALUE = {
    low = 1, mid = 2, high = 3, ultra = 4, epic = 5,
    legendary = 6, mythical = 7, divine = 8, avatar = 9,
}

-- Total enemy-tier budget for a wave when the host is at this level.  Hand-tuned curve: starts at 3 (one low+one mid),
-- climbs roughly +2 per player level, eases off toward the top.  Composition stays bounded so the user isn't
-- staring at a 40-enemy wave at L13.
local TIER_BUDGET_BY_PLAYER_LEVEL = {
    [1]  = 3,
    [2]  = 4,
    [3]  = 6,
    [4]  = 8,
    [5]  = 10,
    [6]  = 12,
    [7]  = 14,
    [8]  = 16,
    [9]  = 18,
    [10] = 21,
    [11] = 24,
    [12] = 27,
    [13] = 30,
}

local function soeLoaded()
    if Ext.Mod and Ext.Mod.IsModLoaded then
        return Ext.Mod.IsModLoaded(SOE_MOD_UUID)
    end
    return false
end

-- Build a per-tier index of {uuid, tier, name, level, ...} entries.
local function buildIndex()
    local raw = Ext.Require("Server/Encounters/EnemyTemplates.lua") or {}
    local soe = soeLoaded()
    local byTier = {}
    local byUuid = {}
    local kept, skipped = 0, 0
    for _, entry in ipairs(raw) do
        if entry.soe and not soe then
            skipped = skipped + 1
        else
            byTier[entry.tier] = byTier[entry.tier] or {}
            table.insert(byTier[entry.tier], entry)
            byUuid[entry.uuid] = entry
            kept = kept + 1
        end
    end
    debugPrint(string.format("[Encounters] templates loaded: %d (skipped %d SoE-only; SoE detected=%s)",
        kept, skipped, tostring(soe)))
    return byTier, byUuid
end

Compositions.templatesByTier, Compositions.templatesByUuid = buildIndex()

function Compositions.tierValue(tier)
    return TIER_VALUE[tier] or 0
end

function Compositions.entryFor(uuid)
    return Compositions.templatesByUuid[uuid]
end

function Compositions.hostLevel(host)
    host = host or Osi.GetHostCharacter()
    local entity = Ext.Entity.Get(host)
    if entity and entity.EocLevel and entity.EocLevel.Level then
        return entity.EocLevel.Level
    end
    return 1
end

function Compositions.tierBudgetForPlayerLevel(playerLevel)
    if playerLevel <= 1 then return TIER_BUDGET_BY_PLAYER_LEVEL[1] end
    return TIER_BUDGET_BY_PLAYER_LEVEL[playerLevel] or TIER_BUDGET_BY_PLAYER_LEVEL[13]
end

local function pickFromTier(tier)
    local pool = Compositions.templatesByTier[tier]
    if not pool or #pool == 0 then return nil end
    return pool[math.random(#pool)]
end

-- Given a tier budget, pick a sequence of templates whose summed tier values approximate the budget.
-- Strategy: pick a single "boss" of ~40% the budget, then fill with smaller-tier picks until we land within ±1 of budget.
-- Falls back to neighbor tiers if a target tier's bucket is empty.
function Compositions.pickEncounterByTier(budget)
    local TIERS_LOW_TO_HIGH = {"low", "mid", "high", "ultra", "epic", "legendary", "mythical", "divine", "avatar"}
    local function tryPick(targetValue)
        for delta = 0, 4 do
            for sign = -1, 1, 2 do
                local v = targetValue + sign * delta
                if delta == 0 then v = targetValue end
                local tier = TIERS_LOW_TO_HIGH[v]
                if tier then
                    local entry = pickFromTier(tier)
                    if entry then return entry end
                end
                if delta == 0 then break end
            end
        end
        return nil
    end

    local picks = {}
    local remaining = budget
    -- Boss: aim for ~40% of budget, capped to 6 (legendary) so we don't auto-spawn divine/avatar in normal waves
    local bossValue = math.max(1, math.min(6, math.floor(budget * 0.4 + 0.5)))
    local boss = tryPick(bossValue)
    if boss then
        table.insert(picks, boss)
        remaining = remaining - Compositions.tierValue(boss.tier)
    end
    -- Fillers: keep adding picks until budget is roughly filled
    local guard = 0
    while remaining > 0 and guard < 30 do
        guard = guard + 1
        local fillerValue = math.max(1, math.min(remaining, math.random(1, math.max(1, math.min(4, remaining)))))
        local entry = tryPick(fillerValue)
        if not entry then break end
        table.insert(picks, entry)
        remaining = remaining - Compositions.tierValue(entry.tier)
    end
    return picks
end

return Compositions
