local M = {}
local Cache = {}
local Memoizable = {
    Osi = {
        "CanFight",
        "CanJoinCombat",
        "CanSee",
        "CombatIsActive",
        "CombatGetGuidFor",
        "CombatGetInvolvedPlayer",
        "FindValidPosition",
        "GetActionResourceValuePersonal",
        "GetActiveArchetype",
        "GetClosestAlivePlayer",
        "GetCombatGroupID",
        "GetDisplayName",
        "GetDistanceTo",
        "GetEquippedWeapon",
        "GetHitpoints",
        "GetHitpointsPercentage",
        "GetHostCharacter",
        "GetLevel",
        "GetMaxHitpoints",
        "GetPosition",
        "GetRegion",
        "GetRulesetModifierBool",
        "GetRulesetModifierString",
        "GetUUID",
        "HasActiveStatus",
        "HasActiveStatusWithGroup",
        "HasPassive",
        "HasLineOfSight",
        "IsAlly",
        "IsCharacter",
        "IsDead",
        "IsEnemy",
        "IsImmuneToStatus",
        "IsInCombat",
        "IsInForceTurnBasedMode",
        "IsInvisible",
        "IsPartyMember",
        "IsPlayer",
        "IsSummon",
        "IsTagged",
        "ResolveTranslatedString",
    },
    Utils = {
        "getDisplayName",
        "getMeleeWeaponRange",
        "getRangedWeaponRange",
        "isAliveAndCanFight",
        "getNearby",
        "isDowned",
        "isPlayerOrAlly",
        "isPugnacious",
        "getDifficulty",
        "isToT",
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
        "getToTEnemyTier",
        "isActiveCombatTurn",
        "getTrackingDistance",
        "getForwardVector",
        "getPointInFrontOf",
        "isCounterspell",
        "isSilenced",
        "isBlinded",
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
        "getCurrentRegion",
        "contains",
        "startsWith",
    },
    Swarm = {
        "isExcludedFromSwarmAI",
        "isControlledByDefaultAI",
    },
    State = {
        "areAnyPlayersBrawling",
        "getNumEnemiesRemaining",
        "isPartyInRealTime",
        "hasDirectHeal",
        "isToTCombatHelper",
    },
    Spells = {
        "getRageAbility",
        "getSpellByName",
        "isSingleSelect",
        "isShout",
        "isCooldown",
    },
    Pick = {
        "checkConditions",
        "getHealingOrDamageAmountWeight",
        "getResistanceWeight",
        "isNpcSpellUsable",
        "isCompanionSpellAvailable",
        "isEnemySpellAvailable",
        "getSpellWeight",
        "getOffenseWeightedTarget",
        "getBalancedWeightedTarget",
        "getDefenseWeightedTarget",
        "getWeightedTargets",
        "decideOnTarget",
        "whoNeedsHealing",
    },
    Roster = {
        "getBrawlerByUuid",
        "getBrawlerByName",
        "getBrawlersSortedByDistance",
        "getBrawlers",
    },
    Resources = {
        "getActionResource",
        "getActionResourceAmount",
        "getActionResourceInfo",
        "getActionResourceName",
        "isSpellPrepared",
        "isSpellOnCooldown",
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

local VAL, NIL = {}, {}

local function memoize(fn, bucket)
    return function (...)
        local sub = bucket
        for i = 1, select("#", ...) do
            local k = select(i, ...)
            local key = (k == nil) and NIL or k
            sub[key] = sub[key] or {}
            sub = sub[key]
        end
        if sub[VAL] == nil then
            sub[VAL] = table.pack(fn(...))
        end
        return table.unpack(sub[VAL], 1, sub[VAL].n)
    end
end

M.Osi = Osi
M.Utils = Utils

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
    for _, bucketGroup in next, Cache do
        for _, bucket in next, bucketGroup do
            for k in next, bucket do
                bucket[k] = nil
            end
        end
    end
end

return M
