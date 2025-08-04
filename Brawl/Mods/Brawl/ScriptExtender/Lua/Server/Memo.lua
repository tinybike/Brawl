local M = {}
local Cache = {}
local VAL = {}

local Memoizable = {
    Osi = {
        "CanFight",
        "CanJoinCombat",
        "CanSee",
        "CombatIsActive",
        "FindValidPosition",
        "GetActionResourceValuePersonal",
        "GetActiveArchetype",
        "GetClosestAlivePlayer",
        "GetDisplayName",
        "GetDistanceTo",
        "GetHitpoints",
        "GetHitpointsPercentage",
        "GetHostCharacter",
        "GetPosition",
        "GetRegion",
        "GetRulesetModifierBool",
        "GetRulesetModifierString",
        "GetUUID",
        "HasActiveStatus",
        "HasLineOfSight",
        "IsAlly",
        "IsCharacter",
        "IsDead",
        "IsEnemy",
        "IsInCombat",
        "IsInForceTurnBasedMode",
        "IsInvisible",
        "IsPartyMember",
        "IsPlayer",
        "ResolveTranslatedString",
    },
    Utils = {
        "getDisplayName",
        "isAliveAndCanFight",
        "getNearby",
        "isDowned",
        "isPlayerOrAlly",
        "isPugnacious",
        "getDifficulty",
        "split",
        "isZoneSpell",
        "isProjectileSpell",
        "convertSpellRangeToNumber",
        "getSpellRange",
        "isVisible",
        "isMeleeArchetype",
        "isHealerArchetype",
        "isBrawlingWithValidTarget",
        "isOnSameLevel",
        "getForwardVector",
        "getPointInFrontOf",
        "isCounterspell",
        "isSilenced",
        "isPlayerTurnEnded",
        "canAct",
        "canMove",
        "hasLoseControlStatus",
        "isHostileTarget",
        "isValidHostileTarget",
        "getSpellNameBySlot",
        "getCurrentCombatRound",
        "hasStatus",
        "hasPassive",
        "getAbility",
        "isConcentrating",
        "getOriginatorPrototype",
    },
    State = {
        "areAnyPlayersBrawling",
        "getNumEnemiesRemaining",
        "isPartyInRealTime",
        "hasDirectHeal",
    },
    AI = {
        "getResistanceWeight",
    },
    Roster = {
        "getBrawlerByUuid",
        "getBrawlerByName",
        "getBrawlersSortedByDistance",
    },
    Resources = {
        "checkSpellCharge",
        "hasEnoughToCastSpell",
    },
    Movement = {
        "playerMovementDistanceToSpeed",
        "enemyMovementDistanceToSpeed",
        "getMovementDistanceAmount",
        "getMovementDistanceMaxAmount",
        "getMovementSpeed",
        "getRemainingMovement",
        "findPathToTargetUuid",
        "findPathToPosition",
        "calculateEnRouteCoords",
        "calculateJumpDistance",
    },
    Leaderboard = {
        "isExcludedHeal",
    },
}

local function memoize(fn, bucket)
    return function (...)
        local sub = bucket
        for i = 1, select("#", ...) do
            local k = select(i, ...)
            sub[k] = sub[k] or {}
            sub = sub[k]
        end
        if sub[VAL] == nil then
            sub[VAL] = table.pack(fn(...))
        end
        return table.unpack(sub[VAL], 1, sub[VAL].n)
    end
end

M.Osi = Osi

M.memoizeAll = function ()
    for moduleName, fns in pairs(Memoizable) do
        M[moduleName] = {}
        Cache[moduleName] = {}
        for _, name in ipairs(fns) do
            local ref = moduleName == "Osi" and Osi or Mods.Brawl[moduleName]
            local bucket = {}
            Cache[moduleName][name] = bucket
            M[moduleName][name] = memoize(ref[name], bucket)
        end
    end
end

M.clear = function ()
    for bucketName, _ in next, Cache do
        Cache[bucketName] = {}
    end
end

return M
