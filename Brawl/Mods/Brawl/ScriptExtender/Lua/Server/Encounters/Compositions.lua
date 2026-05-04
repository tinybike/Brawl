Compositions = Compositions or {}

local debugPrint = Utils.debugPrint
local SOE_MOD_UUID = "a27fdbe3-4d1a-641d-d05f-1ba4ee529da8"

local function soeLoaded()
    if Ext.Mod and Ext.Mod.IsModLoaded then
        return Ext.Mod.IsModLoaded(SOE_MOD_UUID)
    end
    return false
end

local function buildTemplatesByLevel()
    local raw = Ext.Require("Server/Encounters/EnemyTemplates.lua") or {}
    local soe = soeLoaded()
    local byLevel = {}
    local kept, skipped = 0, 0
    for _, entry in ipairs(raw) do
        if entry.soe and not soe then
            skipped = skipped + 1
        else
            byLevel[entry.level] = byLevel[entry.level] or {}
            table.insert(byLevel[entry.level], entry.uuid)
            kept = kept + 1
        end
    end
    debugPrint(string.format("[Encounters] templates loaded: %d (skipped %d SoE-only; SoE detected=%s)",
        kept, skipped, tostring(soe)))
    return byLevel
end

Compositions.templatesByLevel = buildTemplatesByLevel()

function Compositions.templatesInRange(minLevel, maxLevel)
    local results = {}
    for L, list in pairs(Compositions.templatesByLevel) do
        if L >= minLevel and L <= maxLevel then
            for _, uuid in ipairs(list) do
                table.insert(results, uuid)
            end
        end
    end
    return results
end

function Compositions.pickFromRange(minLevel, maxLevel)
    local pool = Compositions.templatesInRange(minLevel, maxLevel)
    if #pool == 0 then return nil end
    return pool[math.random(1, #pool)]
end

function Compositions.pickBossForLevel(level)
    return Compositions.pickFromRange(level - 2, level + 1)
        or Compositions.pickFromRange(math.max(1, level - 4), level + 3)
end

function Compositions.pickFillerForLevel(level)
    return Compositions.pickFromRange(math.max(1, level - 5), math.max(1, level - 2))
        or Compositions.pickFromRange(1, math.max(1, level - 1))
end

function Compositions.countForLevel(level)
    local n = 3
    if level >= 8 then n = n + 1 end
    if level >= 14 then n = n + 1 end
    return n
end

function Compositions.hostLevel(host)
    host = host or Osi.GetHostCharacter()
    local entity = Ext.Entity.Get(host)
    if entity and entity.EocLevel and entity.EocLevel.Level then
        return entity.EocLevel.Level
    end
    return 1
end
