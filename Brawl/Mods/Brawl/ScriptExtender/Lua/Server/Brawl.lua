-- Ext.Require("Server/ECSPrinter.lua")

-- MCM Settings
local ModEnabled = true
local CompanionAIEnabled = true
local TruePause = true
local AutoPauseOnDowned = true
local ActionInterval = 6000
local FullAuto = false
local HitpointsMultiplier = 1.0
local TavArchetype = "melee"
local CompanionTactics = "Offense"
local CompanionAIMaxSpellLevel = 0
local HogwildMode = false
if MCM then
    ModEnabled = MCM.Get("mod_enabled")
    CompanionAIEnabled = MCM.Get("companion_ai_enabled")
    TruePause = MCM.Get("true_pause")
    AutoPauseOnDowned = MCM.Get("auto_pause_on_downed")
    ActionInterval = MCM.Get("action_interval")
    FullAuto = MCM.Get("full_auto")
    HitpointsMultiplier = MCM.Get("hitpoints_multiplier")
    TavArchetype = string.lower(MCM.Get("tav_archetype"))
    CompanionTactics = MCM.Get("companion_tactics")
    CompanionAIMaxSpellLevel = MCM.Get("companion_ai_max_spell_level")
    HogwildMode = MCM.Get("hogwild_mode")
end

-- Constants
local DEBUG_LOGGING = true
local REPOSITION_INTERVAL = 2500
local BRAWL_FIZZLER_TIMEOUT = 30000 -- if 30 seconds elapse with no attacks or pauses, end the brawl
local LIE_ON_GROUND_TIMEOUT = 3500
local ENTER_COMBAT_RANGE = 20
local NEARBY_RADIUS = 35
local MELEE_RANGE = 1.5
local RANGED_RANGE_MAX = 25
local RANGED_RANGE_SWEETSPOT = 10
local RANGED_RANGE_MIN = 10
local HELP_DOWNED_MAX_RANGE = 20
local MUST_BE_AN_ERROR_MAX_DISTANCE_FROM_PLAYER = 100
local AI_HEALTH_PERCENTAGE_HEALING_THRESHOLD = 20.0
local AI_TARGET_CONCENTRATION_WEIGHT_MULTIPLIER = 3
local DEFENSE_TACTICS_MAX_DISTANCE = 15
local MOVEMENT_DISTANCE_UUID = "d6b2369d-84f0-4ca4-a3a7-62d2d192a185"
local LOOPING_COMBAT_ANIMATION_ID = "7bb52cd4-0b1c-4926-9165-fa92b75876a3" -- monk animation, should prob be a lookup?
local ACTION_RESOURCES = {
    ActionPoint = "734cbcfb-8922-4b6d-8330-b2a7e4c14b6a",
    BonusActionPoint = "420c8df5-45c2-4253-93c2-7ec44e127930",
    ReactionActionPoint = "45ff0f48-b210-4024-972f-b64a44dc6985",
    SpellSlot = "d136c5d9-0ff0-43da-acce-a74a07f8d6bf",
    ChannelDivinity = "028304ef-e4b7-4dfb-a7ec-cd87865cdb16",
    ChannelOath = "c0503ecf-c3cd-4719-9cfd-05460a1db95a",
    KiPoint = "46d3d228-04e0-4a43-9a2e-78137e858c14",
    DeflectMissiles_Charge = "2b8021f4-99ac-42d4-87ce-96a7c5505aee",
    SneakAttack_Charge = "1531b6ec-4ba8-4b0d-8411-422d8f51855f",
    Movement = "d6b2369d-84f0-4ca4-a3a7-62d2d192a185",
}
local ALL_SPELL_TYPES = {
    "Buff",
    "Debuff",
    "Control",
    "Damage",
    "Healing",
    "Summon",
    "Utility",
}
local ARCHETYPE_WEIGHTS = {
    caster = {
        rangedWeapon = -5,
        rangedWeaponInRange = 5,
        rangedWeaponOutOfRange = -5,
        meleeWeapon = -5,
        meleeWeaponInRange = 5,
        isSpell = 10,
        spellInRange = 10,
    },
    ranged = {
        rangedWeapon = 10,
        rangedWeaponInRange = 10,
        rangedWeaponOutOfRange = 5,
        meleeWeapon = -2,
        meleeWeaponInRange = 5,
        isSpell = -5,
        spellInRange = 5,
    },
    healer_melee = {
        rangedWeapon = -5,
        rangedWeaponInRange = 5,
        rangedWeaponOutOfRange = -5,
        meleeWeapon = 2,
        meleeWeaponInRange = 8,
        isSpell = 4,
        spellInRange = 8,
    },
    melee = {
        rangedWeapon = -5,
        rangedWeaponInRange = 5,
        rangedWeaponOutOfRange = -5,
        meleeWeapon = 5,
        meleeWeaponInRange = 10,
        isSpell = -10,
        spellInRange = 5,
    },
}
ARCHETYPE_WEIGHTS.beast = ARCHETYPE_WEIGHTS.melee
ARCHETYPE_WEIGHTS.goblin_melee = ARCHETYPE_WEIGHTS.melee
ARCHETYPE_WEIGHTS.goblin_ranged = ARCHETYPE_WEIGHTS.ranged
ARCHETYPE_WEIGHTS.mage = ARCHETYPE_WEIGHTS.caster
ARCHETYPE_WEIGHTS.koboldinventor_drunk = ARCHETYPE_WEIGHTS.melee
ARCHETYPE_WEIGHTS.ranged_stupid = ARCHETYPE_WEIGHTS.ranged
ARCHETYPE_WEIGHTS.melee_magic_smart = ARCHETYPE_WEIGHTS.melee
ARCHETYPE_WEIGHTS.merregon = ARCHETYPE_WEIGHTS.melee
ARCHETYPE_WEIGHTS.act3_LOW_ghost_nurse = ARCHETYPE_WEIGHTS.melee
ARCHETYPE_WEIGHTS.melee_magic = ARCHETYPE_WEIGHTS.melee
ARCHETYPE_WEIGHTS.ogre_melee = ARCHETYPE_WEIGHTS.melee
ARCHETYPE_WEIGHTS.beholder = ARCHETYPE_WEIGHTS.melee
ARCHETYPE_WEIGHTS.minotaur = ARCHETYPE_WEIGHTS.melee
ARCHETYPE_WEIGHTS.steel_watcher_biped = ARCHETYPE_WEIGHTS.melee
local DAMAGE_TYPES = {
    Slashing = 2,
    Piercing = 3,
    Bludgeoning = 4,
    Acid = 5,
    Thunder = 6,
    Necrotic = 7,
    Fire = 8,
    Lightning = 9,
    Cold = 10,
    Psychic = 11,
    Poison = 12,
    Radiant = 13,
    Force = 14,
}
-- NB: Is "Dash" different from "Sprint"?
local PLAYER_MOVEMENT_SPEED_DEFAULT = {Dash = 6.0, Sprint = 6.0, Run = 3.75, Walk = 2.0, Stroll = 1.4}
local MOVEMENT_SPEED_THRESHOLDS = {
    HONOUR = {Sprint = 5, Run = 2, Walk = 1},
    HARD = {Sprint = 6, Run = 4, Walk = 2},
    MEDIUM = {Sprint = 8, Run = 5, Walk = 3},
    EASY = {Sprint = 12, Run = 9, Walk = 6},
}
local ACTION_BUTTON_TO_SLOT = {0, 2, 4, 6, 8, 10, 12, 14, 16}

-- Session state
SpellTable = {}
Listeners = {}
Brawlers = {}
Players = {}
PulseAddNearbyTimers = {}
PulseRepositionTimers = {}
PulseActionTimers = {}
BrawlFizzler = {}
IsAttackingOrBeingAttackedByPlayer = {}
ClosestEnemyBrawlers = {}
PlayerMarkedTarget = {}
PlayerCurrentTarget = {}
ActionsInProgress = {}
MovementQueue = {}
PartyMembersHitpointsListeners = {}
ActionResourcesListeners = {}
TurnBasedListeners = {}
SpellCastMovementListeners = {}
FTBLockedIn = {}
LastClickPosition = {}
ActiveCombatGroups = {}
AwaitingTarget = {}
ToTTimer = nil
ToTRoundTimer = nil
FinalToTChargeTimer = nil
MovementSpeedThresholds = MOVEMENT_SPEED_THRESHOLDS.EASY

-- Persistent state
Ext.Vars.RegisterModVariable(ModuleUUID, "SpellRequirements", {Server = true, Client = false, SyncToClient = false})
Ext.Vars.RegisterModVariable(ModuleUUID, "ModifiedHitpoints", {Server = true, Client = false, SyncToClient = false})

local function debugPrint(...)
    if DEBUG_LOGGING then
        print(...)
    end
end

local function debugDump(...)
    if DEBUG_LOGGING then
        _D(...)
    end
end

function dumpAllEntityKeys()
    local uuid = GetHostCharacter()
    local entity = Ext.Entity.Get(uuid)
    for k, _ in pairs(entity:GetAllComponents()) do
        print(k)
    end
end

function dumpEntityToFile(entityUuid)
    Ext.IO.SaveFile(entityUuid .. ".json", Ext.DumpExport(Ext.Entity.Get(entityUuid):GetAllComponents()))
end

function checkNearby()
    for _, nearby in ipairs(getNearby(Osi.GetHostCharacter(), 50)) do
        if nearby.Entity.IsCharacter then
            local uuid = nearby.Guid
            print(getDisplayName(uuid), uuid, Osi.CanJoinCombat(uuid))
        end
    end
end

function getDisplayName(entityUuid)
    return Osi.ResolveTranslatedString(Osi.GetDisplayName(entityUuid))
end

local function isDowned(entityUuid)
    return Osi.IsDead(entityUuid) == 0 and Osi.GetHitpoints(entityUuid) == 0
end

local function isAliveAndCanFight(entityUuid)
    return Osi.IsDead(entityUuid) == 0 and Osi.GetHitpoints(entityUuid) > 0 and Osi.CanFight(entityUuid) == 1
end

local function isPlayerOrAlly(entityUuid)
    return Osi.IsPlayer(entityUuid) == 1 or Osi.IsAlly(Osi.GetHostCharacter(), entityUuid) == 1
end

local function isPugnacious(potentialEnemyUuid, uuid)
    uuid = uuid or Osi.GetHostCharacter()
    return Osi.IsEnemy(uuid, potentialEnemyUuid) == 1 or IsAttackingOrBeingAttackedByPlayer[potentialEnemyUuid] ~= nil
end

local function getPlayerByUserId(userId)
    if Players then
        for uuid, player in pairs(Players) do
            if player.userId == userId and player.isControllingDirectly then
                return player
            end
        end
    end
    return nil
end

local function getBrawlerByUuid(uuid)
    local level = Osi.GetRegion(uuid)
    if level and Brawlers[level] then
        return Brawlers[level][uuid]
    end
    return nil
end

-- from https://github.com/Norbyte/bg3se/blob/main/Docs/API.md#helper-functions
local function peerToUserId(peerId)
    return (peerId & 0xffff0000) | 0x0001
end

-- thank u focus
---@return "EASY"|"MEDIUM"|"HARD"|"HONOUR"
local function getDifficulty()
    local difficulty = Osi.GetRulesetModifierString("cac2d8bd-c197-4a84-9df1-f86f54ad4521")
    if difficulty == "HARD" and Osi.GetRulesetModifierBool("338450d9-d77d-4950-9e1e-0e7f12210bb3") == 1 then
        return "HONOUR"
    end
    return difficulty
end

local function setMovementSpeedThresholds()
    MovementSpeedThresholds = MOVEMENT_SPEED_THRESHOLDS[getDifficulty()]
end

local function enemyMovementDistanceToSpeed(movementDistance)
    if movementDistance > MovementSpeedThresholds.Sprint then
        return "Sprint"
    elseif movementDistance > MovementSpeedThresholds.Run then
        return "Run"
    elseif movementDistance > MovementSpeedThresholds.Walk then
        return "Walk"
    else
        return "Stroll"
    end
end

local function playerMovementDistanceToSpeed(movementDistance)
    if movementDistance > 10 then
        return "Sprint"
    elseif movementDistance > 6 then
        return "Run"
    elseif movementDistance > 3 then
        return "Walk"
    else
        return "Stroll"
    end
end

local function isNpcSpellUsable(spell, archetype)
    if spell == "Projectile_Jump" then return false end
    if spell == "Shout_Dash_NPC" then return false end
    if spell == "Target_Shove" then return false end
    if spell == "Target_Devour_Ghoul" then return false end
    if spell == "Target_Devour_ShadowMound" then return false end
    if spell == "Target_LOW_RamazithsTower_Nightsong_Globe_1" then return false end
    if archetype == "melee" then
        if spell == "Target_Dip_NPC" then return false end
        if spell == "Projectile_SneakAttack" then return false end
    elseif archetype == "ranged" then
        if spell == "Target_Dip_NPC" then return false end
        if spell == "Projectile_SneakAttack" then return false end
    elseif archetype == "mage" then
        if spell == "Target_Dip_NPC" then return false end
    end
    return true
end

local function split(inputstr, sep)
    if sep == nil then
        sep = "%s" -- whitespace
    else
        sep = string.gsub(sep, "([^%w])", "%%%1")
    end
    local t = {}
    for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
        table.insert(t, str)
    end
    return t
end

local function getMovementSpeed(entityUuid)
    -- local statuses = Ext.Entity.Get(entityUuid).StatusContainer.Statuses
    local entity = Ext.Entity.Get(entityUuid)
    local movementDistance = entity.ActionResources.Resources[MOVEMENT_DISTANCE_UUID][1].Amount
    local movementSpeed = isPlayerOrAlly(entityUuid) and playerMovementDistanceToSpeed(movementDistance) or enemyMovementDistanceToSpeed(movementDistance)
    -- debugPrint("getMovementSpeed", entityUuid, movementDistance, movementSpeed)
    return movementSpeed
end

local function calculateEnRouteCoords(moverUuid, targetUuid, goalDistance)
    local xMover, yMover, zMover = Osi.GetPosition(moverUuid)
    local xTarget, yTarget, zTarget = Osi.GetPosition(targetUuid)
    local dx = xMover - xTarget
    local dy = yMover - yTarget
    local dz = zMover - zTarget
    local fracDistance = goalDistance / math.sqrt(dx*dx + dy*dy + dz*dz)
    return Osi.FindValidPosition(xTarget + dx*fracDistance, yTarget + dy*fracDistance, zTarget + dz*fracDistance, 0, moverUuid, 1)
end

local function moveToDistanceFromTarget(moverUuid, targetUuid, goalDistance)
    local x, y, z = calculateEnRouteCoords(moverUuid, targetUuid, goalDistance)
    if x ~= nil and y ~= nil and z ~= nil then
        Osi.PurgeOsirisQueue(moverUuid, 1)
        Osi.FlushOsirisQueue(moverUuid)
        Osi.CharacterMoveToPosition(moverUuid, x, y, z, getMovementSpeed(moverUuid), "")
    end
end

-- Example monk looping animations (can these be interruptable?)
-- (https://bg3.norbyte.dev/search?iid=Resource.6b05dbcc-19ef-475f-62a2-d18c1e640aa7)
-- animMK = "e85be5a8-6e48-4da4-8486-0d168159df4e"
-- animMK = "7bb52cd4-0b1c-4926-9165-fa92b75876a3"
function holdPosition(entityUuid)
    if not isPlayerOrAlly(entityUuid) then
        Osi.PlayAnimation(entityUuid, LOOPING_COMBAT_ANIMATION_ID, "")
        -- Osi.PlayLoopingAnimation(entityUuid, LOOPING_COMBAT_ANIMATION_ID, LOOPING_COMBAT_ANIMATION_ID, LOOPING_COMBAT_ANIMATION_ID, LOOPING_COMBAT_ANIMATION_ID, LOOPING_COMBAT_ANIMATION_ID, LOOPING_COMBAT_ANIMATION_ID, LOOPING_COMBAT_ANIMATION_ID)
    end
end

local function isOnSameLevel(uuid1, uuid2)
    local level1 = Osi.GetRegion(uuid1)
    local level2 = Osi.GetRegion(uuid2)
    return level1 ~= nil and level2 ~= nil and level1 == level2
end

local function getBrawlersSortedByDistance(entityUuid)
    local brawlersSortedByDistance = {}
    local level = Osi.GetRegion(entityUuid)
    if Brawlers[level] then
        for brawlerUuid, brawler in pairs(Brawlers[level]) do
            if isOnSameLevel(brawlerUuid, entityUuid) and isAliveAndCanFight(brawlerUuid) then
                table.insert(brawlersSortedByDistance, {brawlerUuid, Osi.GetDistanceTo(entityUuid, brawlerUuid)})
            end
        end
        table.sort(brawlersSortedByDistance, function (a, b) return a[2] < b[2] end)
    end
    return brawlersSortedByDistance
end

local function getForwardVector(entityUuid)
    local entity = Ext.Entity.Get(entityUuid)
    local rotationQuat = entity.Transform.Transform.RotationQuat
    local x = rotationQuat[1]
    local y = rotationQuat[2]
    local z = rotationQuat[3]
    local w = rotationQuat[4]
    local forwardX = 2*(x*z - w*y)
    local forwardY = 2*(y*z + w*x)
    local forwardZ = w*w - x*x - y*y + z*z
    local magnitude = math.sqrt(forwardX^2 + forwardY^2 + forwardZ^2)
    return forwardX/magnitude, forwardY/magnitude, forwardZ/magnitude
end

local function getPointInFrontOf(entityUuid, distance)
    local forwardX, forwardY, forwardZ = getForwardVector(entityUuid)
    local translate = entity.Transform.Transform.Translate
    return translate[1] + forwardX*distance, translate[2] + forwardY*distance, translate[3] + forwardZ*distance
end

local function isZoneSpell(spellName)
    return split(spellName, "_")[1] == "Zone"
end

local function isProjectileSpell(spellName)
    return split(spellName, "_")[1] == "Projectile"
end

local function getSpellNameBySlot(uuid, slot)
    local entity = Ext.Entity.Get(uuid)
    -- NB: is this always index 6?
    if entity and entity.HotbarContainer and entity.HotbarContainer.Containers and entity.HotbarContainer.Containers.DefaultBarContainer then
        local customBar = entity.HotbarContainer.Containers.DefaultBarContainer[6]
        local spellName = nil
        for _, element in ipairs(customBar.Elements) do
            if element.Slot == slot then
                if element.SpellId then
                    return element.SpellId.OriginatorPrototype
                else
                    return nil
                end
            end
        end
    end
end

local function getSpellByName(name)
    if name then
        local spellStats = Ext.Stats.Get(name)
        if spellStats then
            local spellType = spellStats.VerbalIntent
            if spellType and SpellTable[spellType] then
                return SpellTable[spellType][name]
            end
        end
    end
    return nil
end

local function checkSpellCharge(casterUuid, spellName)
    debugPrint("checking spell charge", casterUuid, spellName)
    if spellName then
        local entity = Ext.Entity.Get(casterUuid)
        if entity and entity.SpellBook and entity.SpellBook.Spells then
            for i, spell in ipairs(entity.SpellBook.Spells) do
                -- NB: OriginatorPrototype or Prototype?
                if spell.Id.Prototype == spellName then
                    if spell.Charged == false then
                        debugPrint("spell is not charged", spellName, casterUuid)
                        return false
                    end
                end
            end
            return true
        end
    end
    return false
end

local function checkSpellResources(casterUuid, spellName, variant, upcastLevel)
    local entity = Ext.Entity.Get(casterUuid)
    local isSpellPrepared = false
    for _, preparedSpell in ipairs(entity.SpellBookPrepares.PreparedSpells) do
        if preparedSpell.OriginatorPrototype == spellName then
            isSpellPrepared = true
            break
        end
    end
    if not isSpellPrepared then
        debugPrint("Caster does not have spell", spellName, "prepared")
        return false
    end
    if variant ~= nil then
        spellName = variant
    end
    local spell = getSpellByName(spellName)
    if not spell then
        debugPrint("Error: spell not found")
        return false
    end
    debugPrint(casterUuid, getDisplayName(casterUuid), "wants to cast", spellName)
    if spell and spell.costs then
        debugDump(spell.costs)
    end
    if upcastLevel ~= nil then
        debugPrint("Upcasted spell level", upcastLevel)
    end
    for costType, costValue in pairs(spell.costs) do
        if costType == "ShortRest" or costType == "LongRest" then
            if costValue and not checkSpellCharge(casterUuid, spellName) then
                return false
            end
        elseif costType ~= "ActionPoint" and costType ~= "BonusActionPoint" then
            if costType == "SpellSlot" then
                local spellLevel = upcastLevel == nil and costValue or upcastLevel
                local availableResourceValue = Osi.GetActionResourceValuePersonal(casterUuid, costType, spellLevel)
                debugPrint("SpellSlot: Needs 1 level", spellLevel, "slot to cast", spellName, ";", availableResourceValue, "slots available")
                if availableResourceValue < 1 then
                    debugPrint("Insufficient resources", costType)
                    return false
                end
            else
                local availableResourceValue = Osi.GetActionResourceValuePersonal(casterUuid, costType, 0)
                debugPrint(costType, "Needs", costValue, "to cast", spellName, ";", availableResourceValue, "available")
                if availableResourceValue < costValue then
                    debugPrint("Insufficient resources", costType)
                    return false
                end
            end
        end
    end
    return true
end

local function useSpellAndResourcesAtPosition(casterUuid, position, spellName, variant, upcastLevel)
    if not checkSpellResources(casterUuid, spellName, variant, upcastLevel) then
        return false
    end
    if variant ~= nil then
        spellName = variant
    end
    if upcastLevel ~= nil then
        spellName = spellName .. "_" .. tostring(upcastLevel)
    end
    debugPrint("casting at position", spellName, position[1], position[2], position[3])
    Osi.PurgeOsirisQueue(casterUuid, 1)
    Osi.FlushOsirisQueue(casterUuid)
    ActionsInProgress[casterUuid] = ActionsInProgress[casterUuid] or {}
    table.insert(ActionsInProgress[casterUuid], spellName)
    Osi.UseSpellAtPosition(casterUuid, spellName, position[1], position[2], position[3])
    return true
end

local function useSpellAndResources(casterUuid, targetUuid, spellName, variant, upcastLevel)
    if targetUuid == nil then
        return false
    end
    if not checkSpellResources(casterUuid, spellName, variant, upcastLevel) then
        return false
    end
    if variant ~= nil then
        spellName = variant
    end
    if upcastLevel ~= nil then
        spellName = spellName .. "_" .. tostring(upcastLevel)
    end
    debugPrint("casting on target", spellName, targetUuid, getDisplayName(targetUuid))
    Osi.PurgeOsirisQueue(casterUuid, 1)
    Osi.FlushOsirisQueue(casterUuid)
    ActionsInProgress[casterUuid] = ActionsInProgress[casterUuid] or {}
    table.insert(ActionsInProgress[casterUuid], spellName)
    Osi.UseSpell(casterUuid, spellName, targetUuid)
    -- for Zone (and projectile, maybe if pressing shift?) spells, shoot in direction of facing
    -- local x, y, z = getPointInFrontOf(casterUuid, 1.0)
    -- Osi.UseSpellAtPosition(casterUuid, spellName, x, y, z, 1)
    return true
end

local function getClosestEnemyBrawler(brawlerUuid, maxDistance)
    for _, target in ipairs(getBrawlersSortedByDistance(brawlerUuid)) do
        local targetUuid, distance = target[1], target[2]
        if Osi.IsEnemy(brawlerUuid, targetUuid) == 1 and distance < maxDistance then
            return targetUuid
        end
    end
    return nil
end

local function useSpellOnClosestEnemyTarget(playerUuid, spellName)
    if spellName then
        local targetUuid = getClosestEnemyBrawler(playerUuid, 40)
        if targetUuid then
            return useSpellAndResources(playerUuid, targetUuid, spellName)
        end
    end
end

local function getAdjustedDistanceTo(sourcePos, targetPos, sourceForwardX, sourceForwardY, sourceForwardZ)
    local deltaX = targetPos[1] - sourcePos[1]
    local deltaY = targetPos[2] - sourcePos[2]
    local deltaZ = targetPos[3] - sourcePos[3]
    local squaredDistance = deltaX*deltaX + deltaY*deltaY + deltaZ*deltaZ
    if squaredDistance < 1600 then -- 40^2 = 1600
        local distance = math.sqrt(squaredDistance)
        local vecToTargetX = deltaX/distance
        local vecToTargetY = deltaY/distance
        local vecToTargetZ = deltaZ/distance
        local dotProduct = sourceForwardX*vecToTargetX + sourceForwardY*vecToTargetY + sourceForwardZ*vecToTargetZ
        local weight = 0.5 -- on (0, 1)
        local adjustedDistance = distance*(1 + dotProduct*weight)
        if adjustedDistance < 0 then
            adjustedDistance = 0
        end
        debugPrint("Raw distance", distance, "dotProduct", dotProduct, "adjustedDistance", adjustedDistance)
        return adjustedDistance
    end
    return nil
end

local function buildClosestEnemyBrawlers(playerUuid)
    if PlayerMarkedTarget[playerUuid] and not isAliveAndCanFight(PlayerMarkedTarget[playerUuid]) then
        PlayerMarkedTarget[playerUuid] = nil
    end
    local playerEntity = Ext.Entity.Get(playerUuid)
    local playerPos = playerEntity.Transform.Transform.Translate
    local playerForwardX, playerForwardY, playerForwardZ = getForwardVector(playerUuid)
    local maxTargets = 10
    local topTargets = {}
    local level = Osi.GetRegion(playerUuid)
    if Brawlers[level] then
        for brawlerUuid, brawler in pairs(Brawlers[level]) do
            if isOnSameLevel(brawlerUuid, playerUuid) and isAliveAndCanFight(brawlerUuid) and isPugnacious(brawlerUuid, playerUuid) then
                local brawlerEntity = Ext.Entity.Get(brawlerUuid)
                if brawlerEntity then
                    local adjustedDistance = getAdjustedDistanceTo(playerPos, brawlerEntity.Transform.Transform.Translate, playerForwardX, playerForwardY, playerForwardZ)
                    if adjustedDistance ~= nil then
                        local inserted = false
                        for i = 1, #topTargets do
                            if adjustedDistance < topTargets[i].adjustedDistance then
                                table.insert(topTargets, i, {uuid = brawlerUuid, adjustedDistance = adjustedDistance})
                                inserted = true
                                break
                            end
                        end
                        if not inserted and #topTargets < maxTargets then
                            table.insert(topTargets, {uuid = brawlerUuid, adjustedDistance = adjustedDistance})
                        end
                        if #topTargets > maxTargets then
                            topTargets[#topTargets] = nil
                        end
                    end
                end
            end
        end
    end
    ClosestEnemyBrawlers[playerUuid] = {}
    for i, target in ipairs(topTargets) do
        ClosestEnemyBrawlers[playerUuid][i] = target.uuid
    end
    if #ClosestEnemyBrawlers[playerUuid] > 0 and PlayerMarkedTarget[playerUuid] == nil then
        PlayerMarkedTarget[playerUuid] = ClosestEnemyBrawlers[playerUuid][1]
    end
    debugPrint("Closest enemy brawlers to player", playerUuid, getDisplayName(playerUuid))
    debugDump(ClosestEnemyBrawlers)
    debugPrint("Current target:", PlayerMarkedTarget[playerUuid])
    Ext.Timer.WaitFor(3000, function ()
        ClosestEnemyBrawlers[playerUuid] = nil
    end)
end

local function selectNextEnemyBrawler(playerUuid, isNext)
    local nextTargetIndex = nil
    local nextTargetUuid = nil
    for enemyBrawlerIndex, enemyBrawlerUuid in ipairs(ClosestEnemyBrawlers[playerUuid]) do
        if PlayerMarkedTarget[playerUuid] == enemyBrawlerUuid then
            debugPrint("found current target", PlayerMarkedTarget[playerUuid], enemyBrawlerUuid, enemyBrawlerIndex, ClosestEnemyBrawlers[playerUuid][enemyBrawlerIndex])
            if isNext then
                debugPrint("getting NEXT target")
                if enemyBrawlerIndex < #ClosestEnemyBrawlers[playerUuid] then
                    nextTargetIndex = enemyBrawlerIndex + 1
                else
                    nextTargetIndex = 1
                end
            else
                debugPrint("getting PREVIOUS target")
                if enemyBrawlerIndex > 1 then
                    nextTargetIndex = enemyBrawlerIndex - 1
                else
                    nextTargetIndex = #ClosestEnemyBrawlers[playerUuid]
                end
            end
            debugPrint("target index", nextTargetIndex)
            debugDump(ClosestEnemyBrawlers)
            nextTargetUuid = ClosestEnemyBrawlers[playerUuid][nextTargetIndex]
            debugPrint("target uuid", nextTargetUuid)
            break
        end
    end
    if nextTargetUuid then
        if PlayerMarkedTarget[playerUuid] ~= nil then
            Osi.RemoveStatus(PlayerMarkedTarget[playerUuid], "LOW_HAG_MUSHROOM_VFX")
        end
        debugPrint("pinging next target", nextTargetUuid)
        local x, y, z = Osi.GetPosition(nextTargetUuid)
        Osi.RequestPing(x, y, z, nextTargetUuid, playerUuid)
        Osi.ApplyStatus(nextTargetUuid, "LOW_HAG_MUSHROOM_VFX", -1)
        PlayerMarkedTarget[playerUuid] = nextTargetUuid
    end
end

local function getSpellRange(spellName)
    if not spellName then
        return "MeleeMainWeaponRange"
    end
    local spell = Ext.Stats.Get(spellName)
    return isZoneSpell(spellName) and spell.Range or spell.TargetRadius
end

local function moveToTarget(attackerUuid, targetUuid, spellName)
    local range = getSpellRange(spellName)
    local rangeNumber
    Osi.PurgeOsirisQueue(attackerUuid, 1)
    Osi.FlushOsirisQueue(attackerUuid)
    local attackerCanMove = Osi.CanMove(attackerUuid) == 1
    if range == "MeleeMainWeaponRange" then
        Osi.CharacterMoveTo(attackerUuid, targetUuid, getMovementSpeed(attackerUuid), "")
    elseif range == "RangedMainWeaponRange" then
        rangeNumber = 18
    else
        rangeNumber = tonumber(range)
        local distanceToTarget = Osi.GetDistanceTo(attackerUuid, targetUuid)
        if distanceToTarget > rangeNumber and attackerCanMove then
            debugPrint("moveToTarget distance > range, moving to...")
            moveToDistanceFromTarget(attackerUuid, targetUuid, rangeNumber)
        end
    end
    local canSeeTarget = Osi.CanSee(attackerUuid, targetUuid) == 1
    if not canSeeTarget and spellName and not string.match(spellName, "^Projectile_MagicMissile") and attackerCanMove then
        debugPrint("moveToTarget can't see target, moving closer")
        moveToDistanceFromTarget(attackerUuid, targetUuid, targetRadiusNumber or 2)
    end
end

local function useSpellOnTarget(attackerUuid, targetUuid, spellName)
    debugPrint("useSpellOnTarget", attackerUuid, targetUuid, spellName, HogwildMode)
    if HogwildMode then
        Osi.UseSpell(attackerUuid, spellName, targetUuid)
    else
        useSpellAndResources(attackerUuid, targetUuid, spellName)
    end
end

local function getSpellTypeWeight(spellType)
    if spellType == "Damage" then
        return 7
    elseif spellType == "Healing" then
        return 7
    elseif spellType == "Control" then
        return 3
    elseif spellType == "Buff" then
        return 3
    end
    return 0
end

local function getResistanceWeight(spell, entity)
    if entity and entity.Resistances and entity.Resistances.Resistances then
        local resistances = entity.Resistances.Resistances
        if spell.damageType ~= "None" and resistances[DAMAGE_TYPES[spell.damageType]] and resistances[DAMAGE_TYPES[spell.damageType]][1] then
            local resistance = resistances[DAMAGE_TYPES[spell.damageType]][1]
            if resistance == "ImmuneToNonMagical" or resistance == "ImmuneToMagical" then
                return -1000
            elseif resistance == "ResistantToNonMagical" or resistance == "ResistantToMagical" then
                return -5
            elseif resistance == "VulnerableToNonMagical" or resistance == "VulnerableToMagical" then
                return 5
            end
        end
    end
    return 0
end

local function getHighestWeightSpell(weightedSpells)
    if next(weightedSpells) == nil then
        return nil
    end
    local maxWeight = nil
    local selectedSpell = nil
    for spellName, weight in pairs(weightedSpells) do
        if (maxWeight == nil) or (weight > maxWeight) then
            maxWeight = weight
            selectedSpell = spellName
        end
    end
    return (selectedSpell ~= "Target_MainHandAttack") and selectedSpell
end

local function getSpellWeight(spell, distanceToTarget, archetype, spellType)
    -- Special target radius labels (NB: are there others besides these two?)
    -- Maybe should weight proportional to distance required to get there...?
    local weight = 0
    if spell.targetRadius == "RangedMainWeaponRange" then
        weight = weight + ARCHETYPE_WEIGHTS[archetype].rangedWeapon
        if distanceToTarget > RANGED_RANGE_MIN and distanceToTarget < RANGED_RANGE_MAX then
            weight = weight + ARCHETYPE_WEIGHTS[archetype].rangedWeaponInRange
        else
            weight = weight + ARCHETYPE_WEIGHTS[archetype].rangedWeaponOutOfRange
        end
    elseif spell.targetRadius == "MeleeMainWeaponRange" then
        weight = weight + ARCHETYPE_WEIGHTS[archetype].meleeWeapon
        if distanceToTarget <= MELEE_RANGE then
            weight = weight + ARCHETYPE_WEIGHTS[archetype].meleeWeaponInRange
        end
    else
        local targetRadius = tonumber(spell.targetRadius)
        if targetRadius then
            if distanceToTarget <= targetRadius then
                weight = weight + ARCHETYPE_WEIGHTS[archetype].spellInRange
            end
        else
            debugPrint("Target radius didn't convert to number, what is this?", spell.targetRadius)
        end
    end
    -- Favor using spells or non-spells?
    if spell.isSpell then
        weight = weight + ARCHETYPE_WEIGHTS[archetype].isSpell
    end
    -- If this spell has a damage type, favor vulnerable enemies
    -- (NB: this doesn't account for physical weapon damage, which is attached to the weapon itself -- todo)
    -- weight = weight + getResistanceWeight(spell, targetEntity)
    -- Adjust by spell type (damage and healing spells are somewhat favored in general)
    weight = weight + getSpellTypeWeight(spellType)
    -- Adjust by spell level (higher level spells are disfavored, unless we're in hogwild mode)
    -- if not HogwildMode then
    --     weight = weight - spell.level
    -- end
    if HogwildMode then
        weight = weight + spell.level*3
    end
    -- Randomize weight by +/- 30% to keep it interesting
    weight = math.floor(weight*(0.7 + math.random()*0.6) + 0.5)
    return weight
end

local function convertSpellRangeToNumber(range)
    if range == "RangedMainWeaponRange" then
        return 18
    elseif range == "MeleeMainWeaponRange" then
        return 2
    else
        return tonumber(range)
    end
end

-- NB: need to allow healing, buffs, debuffs etc for companions too
local function isCompanionSpellAvailable(uuid, spellName, spell, distanceToTarget, targetDistanceToParty, allowAoE)
    -- This should never happen but...
    if spellName == nil or spell == nil then
        return false
    end
    -- Exclude AoE and zone-type damage spells for now (even in Hogwild Mode) so the companions don't blow each other up on accident
    if not allowAoE and spell.type == "Damage" and (spell.areaRadius > 0 or isZoneSpell(spellName)) then
        return false
    end
    -- If it's a healing spell, make sure it's a direct heal
    if spell.type == "Healing" and not spell.isDirectHeal then
        return false
    end
    if not HogwildMode then
        -- Make sure we're not exceeding the user's specified AI max spell level
        if spell.level > CompanionAIMaxSpellLevel then
            return false
        end
        -- Make sure we have the resources to actually cast what we want to cast
        if not checkSpellResources(uuid, spellName) then
            return false
        end
    end
    -- For defense tactics:
    --  1. Is the target already within range? Then ok to use
    --  2. If the target is out-of-range, can we hit him without moving outside of the perimeter? Then ok to use
    if CompanionTactics == "Defense" then
        local range = convertSpellRangeToNumber(getSpellRange(spellName))
        if distanceToTarget > range and targetDistanceToParty > (range + DEFENSE_TACTICS_MAX_DISTANCE) then
            return false
        end
    end
    return true
end

-- What to do?  In all cases, give extra weight to spells that you're already within range for
-- 1. Check if any players are downed and nearby, if so, help them up.
-- 2? Check if any players are badly wounded and in-range, if so, heal them? (...but this will consume resources...)
-- 3. Attack an enemy.
-- 3a. If primarily a caster class, favor spell attacks (cantrips).
-- 3b. If primarily a ranged class, favor ranged attacks.
-- 3c. If primarily a healer/melee class, favor melee abilities and attacks.
-- 3d. If primarily a melee (or other) class, favor melee attacks.
-- 4. Status effects/buffs (NYI)
local function getCompanionWeightedSpells(uuid, preparedSpells, distanceToTarget, archetype, spellTypes, targetDistanceToParty, allowAoE)
    local weightedSpells = {}
    for _, preparedSpell in pairs(preparedSpells) do
        local spellName = preparedSpell.OriginatorPrototype
        local spell = nil
        for _, spellType in ipairs(spellTypes) do
            spell = SpellTable[spellType][spellName]
            if spell ~= nil then
                break
            end
        end
        if isCompanionSpellAvailable(uuid, spellName, spell, distanceToTarget, targetDistanceToParty, allowAoE) then
            weightedSpells[spellName] = getSpellWeight(spell, distanceToTarget, archetype, spellType)
        end
    end
    return weightedSpells
end

-- What to do?  In all cases, give extra weight to spells that you're already within range for
-- 1. Check if any friendlies are badly wounded and in-range, if so, heal them.
-- 2. Attack an enemy.
-- 2a. If primarily a caster class, favor spell attacks (cantrips).
-- 2b. If primarily a ranged class, favor ranged attacks.
-- 2c. If primarily a healer/melee class, favor melee abilities and attacks.
-- 2d. If primarily a melee (or other) class, favor melee attacks.
-- 3. Status effects/buffs/debuffs (NYI)
local function getWeightedSpells(uuid, preparedSpells, distanceToTarget, archetype, spellTypes)
    local weightedSpells = {}
    for _, preparedSpell in pairs(preparedSpells) do
        local spellName = preparedSpell.OriginatorPrototype
        if isNpcSpellUsable(spellName, archetype) then
            local spell = nil
            for _, spellType in ipairs(spellTypes) do
                spell = SpellTable[spellType][spellName]
                if spell ~= nil then
                    break
                end
            end
            if spell and (spellType ~= "Healing" or spell.isDirectHeal) then
                weightedSpells[spellName] = getSpellWeight(spell, distanceToTarget, archetype, spellType)
            end
        end
    end
    return weightedSpells
end

local function decideCompanionActionOnTarget(uuid, preparedSpells, distanceToTarget, archetype, spellTypes, targetDistanceToParty, allowAoE)
    if not ARCHETYPE_WEIGHTS[archetype] then
        debugPrint("Archetype missing from the list, using melee for now", archetype)
        archetype = archetype == "base" and TavArchetype or "melee"
    end
    local weightedSpells = getCompanionWeightedSpells(uuid, preparedSpells, distanceToTarget, archetype, spellTypes, targetDistanceToParty, allowAoE)
    debugPrint("companion weighted spells", getDisplayName(uuid), archetype, distanceToTarget)
    debugDump(ARCHETYPE_WEIGHTS[archetype])
    debugDump(weightedSpells)
    return getHighestWeightSpell(weightedSpells)
end

local function decideActionOnTarget(uuid, preparedSpells, distanceToTarget, archetype, spellTypes)
    if not ARCHETYPE_WEIGHTS[archetype] then
        debugPrint("Archetype missing from the list, using melee for now", archetype)
        archetype = "melee"
    end
    local weightedSpells = getWeightedSpells(uuid, preparedSpells, distanceToTarget, archetype, spellTypes)
    return getHighestWeightSpell(weightedSpells)
end

local function actOnHostileTarget(brawler, target)
    local archetype = Osi.GetActiveArchetype(brawler.uuid)
    local distanceToTarget = Osi.GetDistanceTo(brawler.uuid, target.uuid)
    if brawler and target then
        -- todo: Utility spells
        local spellTypes = {"Control", "Damage"}
        local actionToTake = nil
        local preparedSpells = Ext.Entity.Get(brawler.uuid).SpellBookPrepares.PreparedSpells
        if Osi.IsPlayer(brawler.uuid) == 1 then
            local allowAoE = Osi.HasPassive(brawler.uuid, "SculptSpells") == 1
            local playerClosestToTarget = Osi.GetClosestAlivePlayer(target.uuid) or brawler.uuid
            local targetDistanceToParty = Osi.GetDistanceTo(target.uuid, playerClosestToTarget)
            debugPrint("target distance to party", targetDistanceToParty, playerClosestToTarget)
            actionToTake = decideCompanionActionOnTarget(brawler.uuid, preparedSpells, distanceToTarget, archetype, {"Damage"}, targetDistanceToParty, allowAoE)
            debugPrint("Companion action to take on hostile target", actionToTake, brawler.uuid, brawler.displayName, target.uuid, target.displayName)
        else
            actionToTake = decideActionOnTarget(brawler.uuid, preparedSpells, distanceToTarget, archetype, spellTypes)
            debugPrint("Action to take on hostile target", actionToTake, brawler.uuid, brawler.displayName, target.uuid, target.displayName)
        end
        if actionToTake == nil and Osi.IsPlayer(brawler.uuid) == 0 then
            local numUsableSpells = 0
            local usableSpells = {}
            for _, preparedSpell in pairs(preparedSpells) do
                local spellName = preparedSpell.OriginatorPrototype
                if isNpcSpellUsable(spellName, archetype) then
                    if SpellTable.Damage[spellName] or SpellTable.Control[spellName] then
                        table.insert(usableSpells, spellName)
                        numUsableSpells = numUsableSpells + 1
                    end
                end
            end
            if numUsableSpells > 1 then
                actionToTake = usableSpells[math.random(1, numUsableSpells)]
            elseif numUsableSpells == 1 then
                actionToTake = usableSpells[1]
            end
            debugPrint("backup ActionToTake", actionToTake, numUsableSpells)
        end
        moveToTarget(brawler.uuid, target.uuid, actionToTake)
        if actionToTake then
            useSpellOnTarget(brawler.uuid, target.uuid, actionToTake)
        else
            Osi.Attack(brawler.uuid, target.uuid, 0)
        end
        return true
    end
    return false
end

local function actOnFriendlyTarget(brawler, target)
    local archetype = Osi.GetActiveArchetype(brawler.uuid)
    local distanceToTarget = Osi.GetDistanceTo(brawler.uuid, target.uuid)
    if brawler.preparedSpells ~= nil then
        -- todo: Utility/Buff spells
        local spellTypes = {"Healing"}
        debugPrint("acting on friendly target", brawler.uuid, brawler.displayName, archetype, getDisplayName(target.uuid))
        local actionToTake = decideActionOnTarget(brawler.preparedSpells, distanceToTarget, archetype, spellTypes)
        debugPrint("Action to take on friendly target", actionToTake, brawler.uuid, brawler.displayName)
        if actionToTake ~= nil then
            moveToTarget(brawler.uuid, target.uuid, actionToTake)
            useSpellOnTarget(brawler.uuid, target.uuid, actionToTake)
            return true
        end
        return false
    end
    return false
end

local function isVisible(entityUuid)
    return Osi.IsInvisible(entityUuid) == 0 and Osi.HasActiveStatus(entityUuid, "SNEAKING") == 0
end

local function getOffenseWeightedTarget(distanceToTarget, targetHp, canSeeTarget)
    local weightedTarget = 2*distanceToTarget + 0.25*targetHp
    if not canSeeTarget then
        weightedTarget = weightedTarget*1.4
    end
    return weightedTarget
end

local function getDefenseWeightedTarget(distanceToTarget, targetHp, canSeeTarget, attackerUuid, targetUuid)
    local weightedTarget
    local closestAlivePlayer = Osi.GetClosestAlivePlayer(attackerUuid)
    if closestAlivePlayer then
        local targetDistanceToParty = Osi.GetDistanceTo(targetUuid, closestAlivePlayer)
        -- Only include potential targets that are within X meters of the party
        if targetDistanceToParty ~= nil and targetDistanceToParty < DEFENSE_TACTICS_MAX_DISTANCE then
            weightedTarget = 3*distanceToTarget + 0.25*targetHp
            if not canSeeTarget then
                weightedTarget = weightedTarget*1.8
            end
        end
    end
    return weightedTarget
end

-- Attacking targets: prioritize close targets with less remaining HP
-- (Lowest weight = most desireable target)
local function getHostileWeightedTargets(brawler, potentialTargets)
    local weightedTargets = {}
    for potentialTargetUuid, _ in pairs(potentialTargets) do
        if brawler.uuid ~= potentialTargetUuid then
            local isBrawlerPlayerOrAlly = isPlayerOrAlly(brawler.uuid)
            local isPotentialTargetPlayerOrAlly = isPlayerOrAlly(potentialTargetUuid)
            local isHostile = false
            if isBrawlerPlayerOrAlly and isPotentialTargetPlayerOrAlly then
                isHostile = false
            elseif isBrawlerPlayerOrAlly and not isPotentialTargetPlayerOrAlly then
                isHostile = Osi.IsEnemy(brawler.uuid, potentialTargetUuid) == 1 or IsAttackingOrBeingAttackedByPlayer[potentialTargetUuid] ~= nil
            elseif not isBrawlerPlayerOrAlly and isPotentialTargetPlayerOrAlly then
                isHostile = Osi.IsEnemy(brawler.uuid, potentialTargetUuid) == 1 or IsAttackingOrBeingAttackedByPlayer[brawler.uuid] ~= nil
            elseif not isBrawlerPlayerOrAlly and not isPotentialTargetPlayerOrAlly then
                isHostile = Osi.IsEnemy(brawler.uuid, potentialTargetUuid) == 1
            else
                debugPrint("getHostileWeightedTargets: what happened here?", brawler.uuid, potentialTargetUuid, brawler.displayName, getDisplayName(potentialTargetUuid))
            end
            if isHostile and isVisible(potentialTargetUuid) and isAliveAndCanFight(potentialTargetUuid) then
                local distanceToTarget = Osi.GetDistanceTo(brawler.uuid, potentialTargetUuid)
                local canSeeTarget = Osi.CanSee(brawler.uuid, potentialTargetUuid) == 1
                if (distanceToTarget < 30 and canSeeTarget) or ActiveCombatGroups[brawler.combatGroupId] or IsAttackingOrBeingAttackedByPlayer[potentialTargetUuid] then
                    local targetHp = Osi.GetHitpoints(potentialTargetUuid)
                    if not isPlayerOrAlly(brawler.uuid) then
                        weightedTargets[potentialTargetUuid] = getOffenseWeightedTarget(distanceToTarget, targetHp, canSeeTarget)
                        ActiveCombatGroups[brawler.combatGroupId] = true
                    else
                        if CompanionTactics == "Offense" then
                            weightedTargets[potentialTargetUuid] = getOffenseWeightedTarget(distanceToTarget, targetHp, canSeeTarget)
                        elseif CompanionTactics == "Defense" then
                            weightedTargets[potentialTargetUuid] = getDefenseWeightedTarget(distanceToTarget, targetHp, canSeeTarget, brawler.uuid, potentialTargetUuid)
                        end
                    end
                    -- NB: this is too intense of a request and will crash the game :/
                    -- local concentration = Ext.Entity.Get(potentialTargetUuid).Concentration
                    -- if concentration and concentration.SpellId and concentration.SpellId.OriginatorPrototype ~= "" then
                    --     weightedTargets[potentialTargetUuid] = weightedTargets[potentialTargetUuid] * AI_TARGET_CONCENTRATION_WEIGHT_MULTIPLIER
                    -- end
                end
            end
        end
    end
    return weightedTargets
end

local function decideOnHostileTarget(weightedTargets)
    local targetUuid = nil
    local minWeight = nil
    if next(weightedTargets) ~= nil then
        for potentialTargetUuid, targetWeight in pairs(weightedTargets) do
            if minWeight == nil or targetWeight < minWeight then
                minWeight = targetWeight
                targetUuid = potentialTargetUuid
            end
        end
        if targetUuid then
            return targetUuid
        end
    end
    return nil
end

local function findTarget(brawler)
    local level = Osi.GetRegion(brawler.uuid)
    if level then
        local brawlersSortedByDistance = getBrawlersSortedByDistance(brawler.uuid)
        -- Healing
        if Osi.IsPlayer(brawler.uuid) == 0 then
            if Brawlers[level] then
                local minTargetHpPct = 200.0
                local friendlyTargetUuid = nil
                for targetUuid, target in pairs(Brawlers[level]) do
                    if isOnSameLevel(brawler.uuid, targetUuid) and Osi.IsAlly(brawler.uuid, targetUuid) == 1 then
                        local targetHpPct = Osi.GetHitpointsPercentage(targetUuid)
                        if targetHpPct ~= nil and targetHpPct > 0 and targetHpPct < minTargetHpPct then
                            minTargetHpPct = targetHpPct
                            friendlyTargetUuid = targetUuid
                        end
                    end
                end
                -- Arbitrary threshold for healing
                if minTargetHpPct < AI_HEALTH_PERCENTAGE_HEALING_THRESHOLD and friendlyTargetUuid and Brawlers[level][friendlyTargetUuid] then
                    debugPrint("actOnFriendlyTarget", brawler.uuid, brawler.displayName, friendlyTargetUuid, getDisplayName(friendlyTargetUuid))
                    if actOnFriendlyTarget(brawler, Brawlers[level][friendlyTargetUuid]) then
                        return true
                    end
                end
            end
        end
        -- Attacking
        local weightedTargets = getHostileWeightedTargets(brawler, Brawlers[level])
        local targetUuid = decideOnHostileTarget(weightedTargets)
        debugDump(weightedTargets)
        debugPrint("got hostile target", targetUuid)
        if targetUuid and Brawlers[level][targetUuid] then
            local result = actOnHostileTarget(brawler, Brawlers[level][targetUuid])
            debugPrint("result (hostile)", result)
            if result == true then
                brawler.targetUuid = targetUuid
                return
            end
        end
        debugPrint("can't find a target, holding position", brawler.uuid, brawler.displayName)
        holdPosition(brawler.uuid)
    end
end

local function isPlayerControllingDirectly(entityUuid)
    return Players[entityUuid] ~= nil and Players[entityUuid].isControllingDirectly == true
end

local function revertHitpoints(entityUuid)
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    local modifiedHitpoints = modVars.ModifiedHitpoints
    if modifiedHitpoints and modifiedHitpoints[entityUuid] ~= nil and Osi.IsCharacter(entityUuid) == 1 then
        -- debugPrint("Reverting hitpoints", entityUuid)
        -- debugDump(modifiedHitpoints[entityUuid])
        local entity = Ext.Entity.Get(entityUuid)
        local currentMaxHp = entity.Health.MaxHp
        local currentHp = entity.Health.Hp
        local multiplier = modifiedHitpoints[entityUuid].multiplier
        if modifiedHitpoints[entityUuid] == nil then
            modifiedHitpoints[entityUuid] = {}
        end
        modifiedHitpoints[entityUuid].updating = true
        modVars.ModifiedHitpoints = modifiedHitpoints
        entity.Health.MaxHp = math.floor(currentMaxHp/multiplier + 0.5)
        entity.Health.Hp = math.floor(currentHp/multiplier + 0.5)
        entity:Replicate("Health")
        modifiedHitpoints[entityUuid] = nil
        modVars.ModifiedHitpoints = modifiedHitpoints
        -- debugPrint("Reverted hitpoints:", entityUuid, getDisplayName(entityUuid), entity.Health.MaxHp, entity.Health.Hp)
    end
end

local function modifyHitpoints(entityUuid)
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    if modVars.ModifiedHitpoints == nil then
        modVars.ModifiedHitpoints = {}
    end
    local modifiedHitpoints = modVars.ModifiedHitpoints
    if Osi.IsCharacter(entityUuid) == 1 and Osi.IsDead(entityUuid) == 0 and modifiedHitpoints[entityUuid] == nil then
        -- debugPrint("modify hitpoints", entityUuid, HitpointsMultiplier)
        local entity = Ext.Entity.Get(entityUuid)
        local originalMaxHp = entity.Health.MaxHp
        local originalHp = entity.Health.Hp
        if modifiedHitpoints[entityUuid] == nil then
            modifiedHitpoints[entityUuid] = {}
        end
        modifiedHitpoints[entityUuid].updating = true
        modVars.ModifiedHitpoints = modifiedHitpoints
        entity.Health.MaxHp = math.floor(originalMaxHp*HitpointsMultiplier + 0.5)
        entity.Health.Hp = math.floor(originalHp*HitpointsMultiplier + 0.5)
        entity:Replicate("Health")
        modifiedHitpoints = Ext.Vars.GetModVariables(ModuleUUID).ModifiedHitpoints
        modifiedHitpoints[entityUuid].maxHp = entity.Health.MaxHp
        modifiedHitpoints[entityUuid].multiplier = HitpointsMultiplier
        modVars.ModifiedHitpoints = modifiedHitpoints
        -- debugPrint("Modified hitpoints:", entityUuid, getDisplayName(entityUuid), originalMaxHp, originalHp, entity.Health.MaxHp, entity.Health.Hp)
    end
end

local function setupPartyMembersHitpoints()
    for _, partyMember in ipairs(Osi.DB_PartyMembers:Get(nil)) do
        local partyMemberUuid = Osi.GetUUID(partyMember[1])
        revertHitpoints(partyMemberUuid)
        modifyHitpoints(partyMemberUuid)
        if PartyMembersHitpointsListeners[partyMemberUuid] ~= nil then
            Ext.Entity.Unsubscribe(PartyMembersHitpointsListeners[partyMemberUuid])
        end
        PartyMembersHitpointsListeners[partyMemberUuid] = Ext.Entity.Subscribe("Health", function (entity, _, _)
            local uuid = entity.Uuid.EntityUuid
            -- debugPrint("Health changed", uuid)
            local modVars = Ext.Vars.GetModVariables(ModuleUUID)
            local modifiedHitpoints = modVars.ModifiedHitpoints
            if modifiedHitpoints and modifiedHitpoints[uuid] ~= nil and modifiedHitpoints[uuid].maxHp ~= entity.Health.MaxHp then
                debugDump(modifiedHitpoints[uuid])
                if modifiedHitpoints[uuid].updating == false then
                    -- External change detected; re-apply modifications
                    -- debugPrint("External MaxHp change detected for", uuid, ". Re-applying hitpoint modifications.")
                    modifiedHitpoints[uuid] = nil
                    modVars.ModifiedHitpoints = modifiedHitpoints
                    modifyHitpoints(uuid)
                end
            end
            modVars = Ext.Vars.GetModVariables(ModuleUUID)
            modifiedHitpoints = modVars.ModifiedHitpoints
            modifiedHitpoints[uuid] = modifiedHitpoints[uuid] or {}
            modifiedHitpoints[uuid].updating = false
            modVars.ModifiedHitpoints = modifiedHitpoints
        end, Ext.Entity.Get(partyMemberUuid))
    end
end

local function addPlayersInEnterCombatRangeToBrawlers(brawlerUuid)
    for playerUuid, player in pairs(Players) do
        local distanceTo = Osi.GetDistanceTo(brawlerUuid, playerUuid)
        if distanceTo < ENTER_COMBAT_RANGE then
            addBrawler(playerUuid)
        end
    end
end

local function stopPulseAction(brawler, remainInBrawl)
    if not remainInBrawl then
        brawler.isInBrawl = false
    end
    if PulseActionTimers[brawler.uuid] ~= nil then
        debugPrint("stop pulse action", brawler.displayName, remainInBrawl)
        Ext.Timer.Cancel(PulseActionTimers[brawler.uuid])
        PulseActionTimers[brawler.uuid] = nil
    end
end

-- Brawlers doing dangerous stuff
local function pulseAction(brawler)
    -- Brawler is alive and able to fight: let's go!
    if brawler and brawler.uuid then
        if not brawler.isPaused and isAliveAndCanFight(brawler.uuid) and (not isPlayerControllingDirectly(brawler.uuid) or FullAuto) then
            -- NB: if we allow healing spells etc used by companions, roll this code in, instead of special-casing it here...
            if isPlayerOrAlly(brawler.uuid) then
                for playerUuid, player in pairs(Players) do
                    if not player.isBeingHelped and brawler.uuid ~= playerUuid and isDowned(playerUuid) and Osi.GetDistanceTo(playerUuid, brawler.uuid) < HELP_DOWNED_MAX_RANGE then
                        player.isBeingHelped = true
                        brawler.targetUuid = nil
                        debugPrint("Helping target", playerUuid, getDisplayName(playerUuid))
                        moveToTarget(brawler.uuid, playerUuid, "Target_Help")
                        return useSpellOnTarget(brawler.uuid, playerUuid, "Target_Help")
                    end
                end
            else
                addPlayersInEnterCombatRangeToBrawlers(brawler.uuid)
            end
            -- Doesn't currently have an attack target, so let's find one
            if brawler.targetUuid == nil then
                debugPrint("Find target 1", brawler.uuid, brawler.displayName)
                return findTarget(brawler)
            end
            -- We have a target and the target is alive
            local level = Osi.GetRegion(brawler.uuid)
            if level and isOnSameLevel(brawler.uuid, brawler.targetUuid) and Brawlers[level][brawler.targetUuid] and isAliveAndCanFight(brawler.targetUuid) and isVisible(brawler.targetUuid) then
                if Osi.GetDistanceTo(brawler.uuid, brawler.targetUuid) <= 12 or brawler.lockedOnTarget then
                    debugPrint("Attacking", brawler.displayName, brawler.uuid, "->", getDisplayName(brawler.targetUuid))
                    return actOnHostileTarget(brawler, Brawlers[level][brawler.targetUuid])
                end
            end
            -- Has an attack target but it's already dead or unable to fight, so find a new one
            debugPrint("Find target 2", brawler.uuid, brawler.displayName)
            brawler.targetUuid = nil
            return findTarget(brawler)
        end
        -- If this brawler is dead or unable to fight, stop this pulse
        stopPulseAction(brawler)
    end
end

local function startPulseAction(brawler)
    if Osi.IsPlayer(brawler.uuid) == 1 and not CompanionAIEnabled then
        return false
    end
    debugPrint("start pulse action for", brawler.displayName)
    if PulseActionTimers[brawler.uuid] == nil then
        brawler.isInBrawl = true
        local noisedActionInterval = math.floor(ActionInterval*(0.7 + math.random()*0.6) + 0.5)
        debugPrint("Using action interval", noisedActionInterval)
        PulseActionTimers[brawler.uuid] = Ext.Timer.WaitFor(0, function ()
            debugPrint("pulse action", brawler.uuid, brawler.displayName)
            pulseAction(brawler)
        end, noisedActionInterval)
    end
end

local function setPlayerRunToSprint(entityUuid)
    local entity = Ext.Entity.Get(entityUuid)
    if entity and entity.ServerCharacter then
        if Players[entityUuid].movementSpeedRun == nil then
            Players[entityUuid].movementSpeedRun = entity.ServerCharacter.Template.MovementSpeedRun
        end
        entity.ServerCharacter.Template.MovementSpeedRun = entity.ServerCharacter.Template.MovementSpeedSprint
    end
end

function addBrawler(entityUuid, isInBrawl, replaceExistingBrawler)
    if entityUuid ~= nil then
        local level = Osi.GetRegion(entityUuid)
        local okToAdd = false
        if replaceExistingBrawler then
            okToAdd = level and Brawlers[level] ~= nil and isAliveAndCanFight(entityUuid)
        else
            okToAdd = level and Brawlers[level] ~= nil and Brawlers[level][entityUuid] == nil and isAliveAndCanFight(entityUuid)
        end
        if okToAdd then
            local displayName = getDisplayName(entityUuid)
            debugPrint("Adding Brawler", entityUuid, displayName)
            local brawler = {
                uuid = entityUuid,
                displayName = displayName,
                combatGuid = Osi.CombatGetGuidFor(entityUuid),
                combatGroupId = Osi.GetCombatGroupID(entityUuid),
                isInBrawl = isInBrawl,
                isPaused = Osi.IsInForceTurnBasedMode(entityUuid) == 1,
            }
            local modVars = Ext.Vars.GetModVariables(ModuleUUID)
            modVars.ModifiedHitpoints = modVars.ModifiedHitpoints or {}
            revertHitpoints(entityUuid)
            modifyHitpoints(entityUuid)
            if Osi.IsPlayer(entityUuid) == 0 then
                -- brawler.originalCanJoinCombat = Osi.CanJoinCombat(entityUuid)
                Osi.SetCanJoinCombat(entityUuid, 0)
                -- thank u lunisole/ghostboats
                Osi.PROC_SelfHealing_Disable(entityUuid)
            elseif Players[entityUuid] then
                -- brawler.originalCanJoinCombat = 1
                setPlayerRunToSprint(entityUuid)
                Osi.SetCanJoinCombat(entityUuid, 0)
            end
            Brawlers[level][entityUuid] = brawler
            if isInBrawl and PulseActionTimers[entityUuid] == nil and Osi.IsInForceTurnBasedMode(Osi.GetHostCharacter()) == 0 then
                startPulseAction(brawler)
            end
        end
    end
end

-- NB: This should never be the first thing that happens (brawl should always kick off with an action)
local function repositionRelativeToTarget(brawlerUuid, targetUuid)
    local archetype = Osi.GetActiveArchetype(brawlerUuid)
    local distanceToTarget = Osi.GetDistanceTo(brawlerUuid, targetUuid)
    if archetype == "melee" then
        if distanceToTarget > MELEE_RANGE then
            Osi.FlushOsirisQueue(brawlerUuid)
            Osi.CharacterMoveTo(brawlerUuid, targetUuid, getMovementSpeed(brawlerUuid), "")
        else
            holdPosition(brawlerUuid)
        end
    else
        debugPrint("misc bucket reposition", brawlerUuid, getDisplayName(brawlerUuid))
        if distanceToTarget <= MELEE_RANGE then
            holdPosition(brawlerUuid)
        elseif distanceToTarget < RANGED_RANGE_MIN then
            moveToDistanceFromTarget(brawlerUuid, targetUuid, RANGED_RANGE_SWEETSPOT)
        elseif distanceToTarget < RANGED_RANGE_MAX then
            holdPosition(brawlerUuid)
        else
            moveToDistanceFromTarget(brawlerUuid, targetUuid, RANGED_RANGE_SWEETSPOT)
        end
    end
end

local function removeBrawler(level, entityUuid)
    local combatGuid = nil
    if Brawlers[level] ~= nil then
        for brawlerUuid, brawler in pairs(Brawlers[level]) do
            if brawler.targetUuid == entityUuid then
                brawler.targetUuid = nil
                brawler.lockedOnTarget = nil
                Osi.PurgeOsirisQueue(brawlerUuid, 1)
                Osi.FlushOsirisQueue(brawlerUuid)
            end
        end
        if Brawlers[level][entityUuid] then
            stopPulseAction(Brawlers[level][entityUuid])
            Brawlers[level][entityUuid] = nil
        end
        Osi.SetCanJoinCombat(entityUuid, 1)
        if Osi.IsPartyMember(entityUuid, 1) == 0 then
            revertHitpoints(entityUuid)
        else
            PlayerCurrentTarget[entityUuid] = nil
            PlayerMarkedTarget[entityUuid] = nil
            IsAttackingOrBeingAttackedByPlayer[entityUuid] = nil
        end
    end
end

local function resetPlayersMovementSpeed()
    for playerUuid, player in pairs(Players) do
        local entity = Ext.Entity.Get(playerUuid)
        if player.movementSpeedRun ~= nil and entity and entity.ServerCharacter then
            entity.ServerCharacter.Template.MovementSpeedRun = player.movementSpeedRun
            player.movementSpeedRun = nil
        end
    end
end

local function stopBrawlFizzler(level)
    if BrawlFizzler[level] ~= nil then
        -- debugPrint("Something happened, stopping brawl fizzler...")
        Ext.Timer.Cancel(BrawlFizzler[level])
        BrawlFizzler[level] = nil
    end
end

local function endBrawl(level)
    if Brawlers[level] then
        for brawlerUuid, brawler in pairs(Brawlers[level]) do
            removeBrawler(level, brawlerUuid)
        end
        debugPrint("Ended brawl")
        debugDump(Brawlers[level])
    end
    for playerUuid, player in pairs(Players) do
        if player.isPaused then
            Osi.ForceTurnBasedMode(playerUuid, 0)
            break
        end
    end
    resetPlayersMovementSpeed()
    ActiveCombatGroups = {}
    Brawlers[level] = {}
    stopBrawlFizzler(level)
end

local function startBrawlFizzler(level)
    stopBrawlFizzler(level)
    debugPrint("Starting BrawlFizzler", level)
    BrawlFizzler[level] = Ext.Timer.WaitFor(BRAWL_FIZZLER_TIMEOUT, function ()
        debugPrint("Brawl fizzled", BRAWL_FIZZLER_TIMEOUT)
        endBrawl(level)
    end)
end

-- Enemies are pugnacious jerks and looking for a fight >:(
local function checkForBrawlToJoin(brawler)
    local closestPlayerUuid, closestDistance = Osi.GetClosestAlivePlayer(brawler.uuid)
    debugPrint("Closest alive player to", brawler.uuid, brawler.displayName, "is", closestPlayerUuid, closestDistance)
    if isOnSameLevel(brawler.uuid, closestPlayerUuid) and closestDistance ~= nil and closestDistance < ENTER_COMBAT_RANGE then
        addBrawler(closestPlayerUuid)
        for playerUuid, player in pairs(Players) do
            if playerUuid ~= closestPlayerUuid then
                local distanceTo = Osi.GetDistanceTo(brawler.uuid, playerUuid)
                if distanceTo < ENTER_COMBAT_RANGE then
                    addBrawler(playerUuid)
                end
            end
        end
        local level = Osi.GetRegion(brawler.uuid)
        if level and BrawlFizzler[level] == nil then
            startBrawlFizzler(level)
        end
        startPulseAction(brawler)
    end
end

local function isBrawlingWithValidTarget(brawler)
    return brawler.isInBrawl and brawler.targetUuid ~= nil and isAliveAndCanFight(brawler.targetUuid)
end

---@class EntityDistance
---@field Entity EntityHandle
---@field Guid string GUID
---@field Distance number
---@param source string GUID
---@param radius number|nil
---@param ignoreHeight boolean|nil
---@param withComponent ExtComponentType|nil
---@return EntityDistance[]
-- thank u hippo (from hippo0o/bg3-mods & AtilioA/BG3-volition-cabinet)
function getNearby(source, radius, ignoreHeight, withComponent)
    radius = radius or 1
    withComponent = withComponent or "Uuid"

    ---@param entity string|EntityHandle GUID
    ---@return number[]|nil {x, y, z}
    local function entityPos(entity)
        entity = type(entity) == "string" and Ext.Entity.Get(entity) or entity
        local ok, pos = pcall(function ()
            return entity.Transform.Transform.Translate
        end)
        if ok then
            return {pos[1], pos[2], pos[3]}
        end
        return nil
    end

    local sourcePos = entityPos(source)
    if not sourcePos then
        return {}
    end

    ---@param target number[] {x, y, z}
    ---@return number
    local function calcDisance(target)
        return math.sqrt(
            (sourcePos[1] - target[1]) ^ 2
                + (not ignoreHeight and (sourcePos[2] - target[2]) ^ 2 or 0)
                + (sourcePos[3] - target[3]) ^ 2
        )
    end

    local nearby = {}
    for _, entity in ipairs(Ext.Entity.GetAllEntitiesWithComponent(withComponent)) do
        local pos = entityPos(entity)
        if pos then
            local distance = calcDisance(pos)
            if distance <= radius then
                table.insert(nearby, {
                    Entity = entity,
                    Guid = entity.Uuid and entity.Uuid.EntityUuid,
                    Distance = distance,
                })
            end
        end
    end
    table.sort(nearby, function (a, b) return a.Distance < b.Distance end)
    return nearby
end

local function addNearbyToBrawlers(entityUuid, nearbyRadius, combatGuid, replaceExistingBrawler)
    for _, nearby in ipairs(getNearby(entityUuid, nearbyRadius)) do
        if nearby.Entity.IsCharacter and isAliveAndCanFight(nearby.Guid) then
            if combatGuid == nil or Osi.CombatGetGuidFor(nearby.Guid) == combatGuid then
                addBrawler(nearby.Guid, true, replaceExistingBrawler)
            else
                addBrawler(nearby.Guid, false, replaceExistingBrawler)
            end
        end
    end
end

local function addNearbyEnemiesToBrawlers(entityUuid, nearbyRadius)
    for _, nearby in ipairs(getNearby(entityUuid, nearbyRadius)) do
        if nearby.Entity.IsCharacter and isAliveAndCanFight(nearby.Guid) and isPugnacious(nearby.Guid) then
            addBrawler(nearby.Guid, false, false)
        end
    end
end

local function isToT()
    return Mods.ToT ~= nil and Mods.ToT.IsActive()
end

local function stopPulseAddNearby(uuid)
    debugPrint("stopPulseAddNearby", uuid, getDisplayName(uuid))
    if PulseAddNearbyTimers[uuid] ~= nil then
        Ext.Timer.Cancel(PulseAddNearbyTimers[uuid])
        PulseAddNearbyTimers[uuid] = nil
    end
end

local function pulseAddNearby(uuid)
    addNearbyEnemiesToBrawlers(uuid, 30)
end

local function startPulseAddNearby(uuid)
    debugPrint("startPulseAddNearby", uuid, getDisplayName(uuid))
    if PulseAddNearbyTimers[uuid] == nil then
        PulseAddNearbyTimers[uuid] = Ext.Timer.WaitFor(0, function ()
            if not isToT() then
                pulseAddNearby(uuid)
            end
        end, 7500)
    end
end

local function checkForDownedOrDeadPlayers()
    if Players then
        for uuid, player in pairs(Players) do
            if Osi.IsDead(uuid) == 1 or isDowned(uuid) then
                Osi.PurgeOsirisQueue(uuid, 1)
                Osi.FlushOsirisQueue(uuid)
                Osi.LieOnGround(uuid)
            end
        end
    end
end

local function areAnyPlayersBrawling()
    if Players then
        for playerUuid, player in pairs(Players) do
            local level = Osi.GetRegion(playerUuid)
            if level and Brawlers[level] and Brawlers[level][playerUuid] then
                return true
            end
        end
    end
    return false
end

local function stopPulseReposition(level)
    debugPrint("stopPulseReposition", level)
    if PulseRepositionTimers[level] ~= nil then
        Ext.Timer.Cancel(PulseRepositionTimers[level])
        PulseRepositionTimers[level] = nil
    end
end

-- Reposition the NPC relative to the player.  This is the only place that NPCs should enter the brawl.
local function pulseReposition(level)
    checkForDownedOrDeadPlayers()
    if Brawlers[level] then
        for brawlerUuid, brawler in pairs(Brawlers[level]) do
            if isAliveAndCanFight(brawlerUuid) then
                -- Enemy units are actively looking for a fight and will attack if you get too close to them
                if isPugnacious(brawlerUuid) then
                    if brawler.isInBrawl and brawler.targetUuid ~= nil and isAliveAndCanFight(brawler.targetUuid) then
                        debugPrint("Repositioning", brawler.displayName, brawlerUuid, "->", getDisplayName(brawler.targetUuid))
                        -- repositionRelativeToTarget(brawlerUuid, brawler.targetUuid)
                        local playerUuid, closestDistance = Osi.GetClosestAlivePlayer(brawlerUuid)
                        if closestDistance > 2*ENTER_COMBAT_RANGE then
                            debugPrint("Too far away, removing brawler", brawlerUuid, getDisplayName(brawlerUuid))
                            removeBrawler(level, brawlerUuid)
                        end
                    else
                        debugPrint("Checking for a brawl to join", brawler.displayName, brawlerUuid)
                        checkForBrawlToJoin(brawler)
                    end
                -- Player, ally, and neutral units are not actively looking for a fight
                -- - Companions and allies use the same logic
                -- - Neutrals just chilling
                elseif areAnyPlayersBrawling() and isPlayerOrAlly(brawlerUuid) and not brawler.isPaused then
                    -- debugPrint("Player or ally", brawlerUuid, Osi.GetHitpoints(brawlerUuid))
                    if Players[brawlerUuid] and (isPlayerControllingDirectly(brawlerUuid) and not FullAuto) then
                        debugPrint("Player is controlling directly: do not take action!")
                        debugDump(brawler)
                        stopPulseAction(brawler, true)
                    else
                        if not brawler.isInBrawl then
                            if Osi.IsPlayer(brawlerUuid) == 0 or CompanionAIEnabled then
                                debugPrint("Not in brawl, starting pulse action for", brawler.displayName)
                                startPulseAction(brawler)
                            end
                        elseif isBrawlingWithValidTarget(brawler) and Osi.IsPlayer(brawlerUuid) == 1 and CompanionAIEnabled then
                            holdPosition(brawlerUuid)
                            -- repositionRelativeToTarget(brawlerUuid, brawler.targetUuid)
                        end
                    end
                end
            elseif Osi.IsDead(brawlerUuid) == 1 or isDowned(brawlerUuid) then
                Osi.PurgeOsirisQueue(brawlerUuid, 1)
                Osi.FlushOsirisQueue(brawlerUuid)
                Osi.LieOnGround(brawlerUuid)
            end
        end
    end
end

-- Reposition if needed every REPOSITION_INTERVAL ms
local function startPulseReposition(level)
    if PulseRepositionTimers[level] == nil then
        debugPrint("startPulseReposition", level)
        PulseRepositionTimers[level] = Ext.Timer.WaitFor(0, function ()
            pulseReposition(level)
        end, REPOSITION_INTERVAL)
    end
end

local function getNumEnemiesRemaining(level)
    local numEnemiesRemaining = 0
    for brawlerUuid, brawler in pairs(Brawlers[level]) do
        if isPugnacious(brawlerUuid) and brawler.isInBrawl then
            numEnemiesRemaining = numEnemiesRemaining + 1
        end
    end
    return numEnemiesRemaining
end

local function checkForEndOfBrawl(level)
    local numEnemiesRemaining = getNumEnemiesRemaining(level)
    debugPrint("Number of enemies remaining:", numEnemiesRemaining)
    if numEnemiesRemaining == 0 then
        endBrawl(level)
    end
end

local function setupPlayer(guid)
    local uuid = Osi.GetUUID(guid)
    if uuid then
        if not Players then
            Players = {}
        end
        Players[uuid] = {
            uuid = uuid,
            guid = guid,
            displayName = getDisplayName(uuid),
            userId = Osi.GetReservedUserID(uuid),
        }
        Osi.SetCanJoinCombat(uuid, 1)
    end
end

local function resetPlayers()
    Players = {}
    for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
        setupPlayer(player[1])
    end
end

local function setIsControllingDirectly()
    if Players ~= nil and next(Players) ~= nil then
        for playerUuid, player in pairs(Players) do
            player.isControllingDirectly = false
        end
        local entities = Ext.Entity.GetAllEntitiesWithComponent("ClientControl")
        for _, entity in ipairs(entities) do
            -- New player (client) just joined: they might not be in the Players table yet
            if Players[entity.Uuid.EntityUuid] == nil then
                resetPlayers()
            end
        end
        for _, entity in ipairs(entities) do
            Players[entity.Uuid.EntityUuid].isControllingDirectly = true
        end
    end
end

local function stopAllPulseAddNearbyTimers()
    for _, timer in pairs(PulseAddNearbyTimers) do
        Ext.Timer.Cancel(timer)
    end
end

local function stopAllPulseRepositionTimers()
    for level, timer in pairs(PulseRepositionTimers) do
        endBrawl(level)
        Ext.Timer.Cancel(timer)
    end
end

local function stopAllPulseActionTimers()
    for uuid, timer in pairs(PulseActionTimers) do
        Ext.Timer.Cancel(timer)
    end
end

local function stopAllBrawlFizzlers()
    for level, timer in pairs(BrawlFizzler) do
        endBrawl(level)
        Ext.Timer.Cancel(timer)
    end
end

local function resetSpellData()
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    if modVars and modVars.SpellRequirements then
        local spellReqs = modVars.SpellRequirements
        for spellName, req in pairs(spellReqs) do
            local spell = Ext.Stats.Get(spellName)
            if spell then
                local requirements = spell.Requirements
                table.insert(requirements, {Requirement = req.Requirement, Param = req.Param, Not = req.Not})
                spell.Requirements = requirements
                spell:Sync()
            end
        end
        modVars.SpellRequirements = nil
    end
end

local function revertAllModifiedHitpoints()
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    if modVars.ModifiedHitpoints and next(modVars.ModifiedHitpoints) ~= nil then
        for uuid, _ in pairs(modVars.ModifiedHitpoints) do
            revertHitpoints(uuid)
        end
    end
    for _, listener in pairs(PartyMembersHitpointsListeners) do
        Ext.Entity.Unsubscribe(listener)
    end
end

local function cleanupAll()
    stopAllPulseAddNearbyTimers()
    stopAllPulseRepositionTimers()
    stopAllPulseActionTimers()
    stopAllBrawlFizzlers()
    local hostCharacter = Osi.GetHostCharacter()
    if hostCharacter then
        local level = Osi.GetRegion(hostCharacter)
        if level then
            endBrawl(level)
        end
    end
    revertAllModifiedHitpoints()
    resetSpellData()
end

local function getSpellInfo(spellType, spellName)
    local spell = Ext.Stats.Get(spellName)
    if spell and spell.VerbalIntent == spellType then
        local useCosts = split(spell.UseCosts, ";")
        local costs = {
            ShortRest = spell.Cooldown == "OncePerShortRest" or spell.Cooldown == "OncePerShortRestPerItem",
            LongRest = spell.Cooldown == "OncePerRest" or spell.Cooldown == "OncePerRestPerItem",
        }
        -- local hitCost = nil -- divine smite only..?
        for _, useCost in ipairs(useCosts) do
            local useCostTable = split(useCost, ":")
            local useCostLabel = useCostTable[1]
            local useCostAmount = tonumber(useCostTable[#useCostTable])
            if useCostLabel == "SpellSlotsGroup" then
                -- e.g. SpellSlotsGroup:1:1:2
                -- NB: what are the first two numbers?
                costs.SpellSlot = useCostAmount
            else
                costs[useCostLabel] = useCostAmount
            end
        end
        local spellInfo = {
            level = spell.Level,
            areaRadius = spell.AreaRadius,
            -- targetConditions = spell.TargetConditions,
            -- damageType = spell.DamageType,
            isSpell = spell.SpellSchool ~= "None",
            targetRadius = spell.TargetRadius,
            costs = costs,
            type = spellType,
            -- need to parse this, e.g. DealDamage(LevelMapValue(D8Cantrip),Cold), DealDamage(8d6,Fire), etc
            -- damage = spell.TooltipDamageList,
        }
        if spellType == "Healing" then
            spellInfo.isDirectHeal = false
            local spellProperties = spell.SpellProperties
            if spellProperties then
                for _, spellProperty in ipairs(spellProperties) do
                    local functors = spellProperty.Functors
                    if functors then
                        for _, functor in ipairs(functors) do
                            if functor.TypeId == "RegainHitPoints" then
                                spellInfo.isDirectHeal = true
                            end
                        end
                    end
                end
            end
        end
        return spellInfo
    end
    return nil
end

local function getAllSpellsOfType(spellType)
    local allSpellsOfType = {}
    for _, spellName in ipairs(Ext.Stats.GetStats("SpellData")) do
        local spell = Ext.Stats.Get(spellName)
        if spell and spell.VerbalIntent == spellType then
            if spell.ContainerSpells and spell.ContainerSpells ~= "" then
                local containerSpellNames = split(spell.ContainerSpells, ";")
                for _, containerSpellName in ipairs(containerSpellNames) do
                    allSpellsOfType[containerSpellName] = getSpellInfo(spellType, containerSpellName)
                end
            else
                allSpellsOfType[spellName] = getSpellInfo(spellType, spellName)
                if spell.Requirements and #spell.Requirements ~= 0 then
                    local requirements = spell.Requirements
                    local removeIndex = 0
                    for i, req in ipairs(requirements) do
                        if req.Requirement == "Combat" and req.Not == false then
                            removeIndex = i
                            local removedReq = {Requirement = req.Requirement, Param = req.Param, Not = req.Not, index = i}
                            local modVars = Ext.Vars.GetModVariables(ModuleUUID)
                            modVars.SpellRequirements = modVars.SpellRequirements or {}
                            modVars.SpellRequirements[spellName] = removedReq
                            break
                        end
                    end
                    if removeIndex ~= 0 then
                        table.remove(requirements, removeIndex)
                    end
                    spell.Requirements = requirements
                    spell:Sync()
                end
            end
        end
    end
    return allSpellsOfType
end

local function buildSpellTable()
    local spellTable = {}
    for _, spellType in pairs(ALL_SPELL_TYPES) do
        spellTable[spellType] = getAllSpellsOfType(spellType)
    end
    return spellTable
end

local function isFTBAllLockedIn()
    for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
        local uuid = Osi.GetUUID(player[1])
        if not FTBLockedIn[uuid] and Osi.IsDead(uuid) == 0 and not isDowned(uuid) then
            return false
        end
    end
    return true
end

local function allEnterFTB()
    for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
        local uuid = Osi.GetUUID(player[1])
        Osi.ForceTurnBasedMode(uuid, 1)
    end
end

local function isLocked(entity)
    return entity.TurnBased.CanAct_M and entity.TurnBased.HadTurnInCombat and not entity.TurnBased.IsInCombat_M
end

local function unlock(entity)
    if isLocked(entity) then
        entity.TurnBased.IsInCombat_M = true
        entity:Replicate("TurnBased")
        local uuid = entity.Uuid.EntityUuid
        FTBLockedIn[uuid] = false
        if MovementQueue[uuid] then
            if ActionResourcesListeners[uuid] ~= nil then
                Ext.Entity.Unsubscribe(ActionResourcesListeners[uuid])
                ActionResourcesListeners[uuid] = nil
            end
            local moveTo = MovementQueue[uuid]
            Osi.CharacterMoveToPosition(uuid, moveTo[1], moveTo[2], moveTo[3], getMovementSpeed(uuid), "")
            MovementQueue[uuid] = nil
        end
    end
end

local function allExitFTB()
    for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
        local uuid = Osi.GetUUID(player[1])
        unlock(Ext.Entity.Get(uuid))
        Osi.ForceTurnBasedMode(uuid, 0)
    end
end

local function lock(entity)
    entity.TurnBased.IsInCombat_M = false
    FTBLockedIn[entity.Uuid.EntityUuid] = true
end

local function isInFTB(entity)
    return entity.FTBParticipant and entity.FTBParticipant.field_18 ~= nil
end

local function isActionFinalized(entity)
    return entity.SpellCastIsCasting and entity.SpellCastIsCasting.Cast and entity.SpellCastIsCasting.Cast.SpellCastState
end

local function midActionLock(entity)
    local spellCastState = entity.SpellCastIsCasting.Cast.SpellCastState
    if spellCastState.Targets then
        local target = spellCastState.Targets[1]
        if target and (target.Position or target.Target) then
            lock(entity)
        end
    end
end

local function startTruePause(entityUuid)
    -- eoc::ActionResourcesComponent: Replicated
    -- eoc::spell_cast::TargetsChangedEventOneFrameComponent: Created
    -- eoc::spell_cast::PreviewEndEventOneFrameComponent: Created
    -- eoc::TurnBasedComponent: Replicated (all characters)
    -- movement only triggers ActionResources
    --      only pay attention to this if it doesn't occur after a spellcastmovement
    -- move-then-act triggers SpellCastMovement, (TurnBased?), ActionResources
    --      if SpellCastMovement triggered, then ignore the next action resources trigger
    -- act (incl. jump) triggers SpellCastMovement, (TurnBased?)
    if TruePause and Osi.IsPartyMember(entityUuid, 1) == 1 then
        if SpellCastMovementListeners[entityUuid] == nil then
            local entity = Ext.Entity.Get(entityUuid)
            TurnBasedListeners[entityUuid] = Ext.Entity.Subscribe("TurnBased", function (caster, _, _)
                if caster and caster.TurnBased then
                    FTBLockedIn[entityUuid] = caster.TurnBased.RequestedEndTurn
                end
                if isFTBAllLockedIn() then
                    allExitFTB()
                end
            end, entity)
            ActionResourcesListeners[entityUuid] = Ext.Entity.Subscribe("ActionResources", function (caster, _, _)
                if isInFTB(caster) and (not isLocked(caster) or MovementQueue[entityUuid]) then
                    if LastClickPosition[entityUuid] and LastClickPosition[entityUuid].position then
                        lock(caster)
                        local position = LastClickPosition[entityUuid].position
                        MovementQueue[entityUuid] = {position[1], position[2], position[3]}
                    end
                end
            end, entity)
            -- NB: can specify only the specific cast entity?
            SpellCastMovementListeners[entityUuid] = Ext.Entity.OnCreateDeferred("SpellCastMovement", function (cast, _, _)
                local caster = cast.SpellCastState.Caster
                if caster.Uuid.EntityUuid == entityUuid then
                    if ActionResourcesListeners[entityUuid] ~= nil then
                        Ext.Entity.Unsubscribe(ActionResourcesListeners[entityUuid])
                        ActionResourcesListeners[entityUuid] = nil
                    end
                    if isInFTB(caster) and isActionFinalized(caster) then
                        midActionLock(caster)
                    end
                end
            end)
        end
    end
end

local function stopTruePause(entityUuid)
    if Osi.IsPartyMember(entityUuid, 1) == 1 then
        if ActionResourcesListeners[entityUuid] ~= nil then
            Ext.Entity.Unsubscribe(ActionResourcesListeners[entityUuid])
            ActionResourcesListeners[entityUuid] = nil
        end
        if TurnBasedListeners[entityUuid] ~= nil then
            Ext.Entity.Unsubscribe(TurnBasedListeners[entityUuid])
            TurnBasedListeners[entityUuid] = nil
        end
        if SpellCastMovementListeners[entityUuid] ~= nil then
            Ext.Entity.Unsubscribe(SpellCastMovementListeners[entityUuid])
            SpellCastMovementListeners[entityUuid] = nil
        end
    end
end

local function checkTruePauseParty()
    if TruePause then
        for uuid, _ in pairs(Players) do
            if Osi.IsInForceTurnBasedMode(uuid) == 1 then
                startTruePause(uuid)
            else
                stopTruePause(uuid)
            end
        end
    else
        for uuid, _ in pairs(Players) do
            stopTruePause(uuid)
            unlock(Ext.Entity.Get(uuid))
        end
    end
end

local function onCombatStarted(combatGuid)
    debugPrint("CombatStarted", combatGuid)
    for playerUuid, player in pairs(Players) do
        addBrawler(playerUuid, true)
    end
    debugDump(Brawlers)
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
        debugDump(Brawlers)
        if not isToT() then
            ENTER_COMBAT_RANGE = 20
            startBrawlFizzler(level)
            Ext.Timer.WaitFor(500, function ()
                addNearbyToBrawlers(Osi.GetHostCharacter(), NEARBY_RADIUS, combatGuid)
                Ext.Timer.WaitFor(1500, function ()
                    if Osi.CombatIsActive(combatGuid) then
                        Osi.EndCombat(combatGuid)
                    end
                end)
            end)
        else
            ENTER_COMBAT_RANGE = 150
            startToTTimers()
        end
    end
end

local function initBrawlers(level)
    Brawlers[level] = {}
    for playerUuid, player in pairs(Players) do
        if player.isControllingDirectly then
            startPulseAddNearby(playerUuid)
        end
        if Osi.IsInCombat(playerUuid) == 1 then
            onCombatStarted(Osi.CombatGetGuidFor(playerUuid))
            break
        end
    end
    startPulseReposition(level)
end

local function onStarted(level)
    debugPrint("onStarted")
    resetSpellData()
    SpellTable = buildSpellTable()
    resetPlayers()
    setIsControllingDirectly()
    setMovementSpeedThresholds()
    resetPlayersMovementSpeed()
    setupPartyMembersHitpoints()
    initBrawlers(level)
    checkTruePauseParty()
    debugDump(Players)
    Ext.ServerNet.BroadcastMessage("Started", level)
end

local function onResetCompleted()
    debugPrint("ResetCompleted")
    -- Printer:Start()
    -- SpellPrinter:Start()
    onStarted(Osi.GetRegion(Osi.GetHostCharacter()))
end

-- New user joined (multiplayer)
local function onUserReservedFor(entity, _, _)
    setIsControllingDirectly()
    local entityUuid = entity.Uuid.EntityUuid
    if Players and Players[entityUuid] then
        local userId = entity.UserReservedFor.UserID
        Players[entityUuid].userId = entity.UserReservedFor.UserID
    end
end

local function onLevelGameplayStarted(level, _)
    debugPrint("LevelGameplayStarted", level)
    onStarted(level)
end

local function stopToTTimers()
    if ToTRoundTimer ~= nil then
        Ext.Timer.Cancel(ToTRoundTimer)
        ToTRoundTimer = nil
    end
    if ToTTimer ~= nil then
        Ext.Timer.Cancel(ToTTimer)
        ToTTimer = nil
    end
end

local function startToTTimers()
    debugPrint("startToTTimers")
    stopToTTimers()
    if not Mods.ToT.Player.InCamp() then
        ToTRoundTimer = Ext.Timer.WaitFor(6000, function ()
            if Mods.ToT.PersistentVars.Scenario and Mods.ToT.PersistentVars.Scenario.Round < #Mods.ToT.PersistentVars.Scenario.Timeline then
                debugPrint("Moving ToT forward")
                Mods.ToT.Scenario.ForwardCombat()
                Ext.Timer.WaitFor(1500, function ()
                    addNearbyToBrawlers(Osi.GetHostCharacter(), 150)
                end)
            end
            startToTTimers()
        end)
        if Mods.ToT.PersistentVars.Scenario then
            local isPrepRound = (Mods.ToT.PersistentVars.Scenario.Round == 0) and (next(Mods.ToT.PersistentVars.Scenario.SpawnedEnemies) == nil)
            if isPrepRound then
                ToTTimer = Ext.Timer.WaitFor(0, function ()
                    debugPrint("adding nearby...")
                    addNearbyToBrawlers(Osi.GetHostCharacter(), 150)
                end, 8500)
            end
        end
    end
end

local function onCombatRoundStarted(combatGuid, round)
    debugPrint("CombatRoundStarted", combatGuid, round)
    if not isToT() then
        ENTER_COMBAT_RANGE = 20
        onCombatStarted(combatGuid)
    else
        startToTTimers()
    end
end

local function onCombatEnded(combatGuid)
    debugPrint("CombatEnded", combatGuid)
end

local function onEnteredCombat(entityGuid, combatGuid)
    debugPrint("EnteredCombat", entityGuid, combatGuid)
    addBrawler(Osi.GetUUID(entityGuid), true)
end

local function onEnteredForceTurnBased(entityGuid)
    local entityUuid = Osi.GetUUID(entityGuid)
    local level = Osi.GetRegion(entityGuid)
    if level and entityUuid and Players[entityUuid] then
        debugPrint("EnteredForceTurnBased", entityGuid)
        if Brawlers[level] and Brawlers[level][entityUuid] then
            Brawlers[level][entityUuid].isInBrawl = false
        end
        stopPulseAddNearby(entityUuid)
        stopPulseReposition(level)
        stopBrawlFizzler(level)
        if isToT() then
            stopToTTimers()
        end
        startTruePause(entityUuid)
        if Brawlers[level] then
            for brawlerUuid, brawler in pairs(Brawlers[level]) do
                if brawlerUuid ~= entityUuid and not Brawlers[level][brawlerUuid].isPaused then
                    Osi.PurgeOsirisQueue(brawlerUuid, 1)
                    Osi.FlushOsirisQueue(brawlerUuid)
                    stopPulseAction(brawler, true)
                    if Players[brawlerUuid] then
                        Brawlers[level][brawlerUuid].isPaused = true
                        Osi.ForceTurnBasedMode(brawlerUuid, 1)
                    end
                end
            end
        end
    end
end

local function onLeftForceTurnBased(entityGuid)
    local entityUuid = Osi.GetUUID(entityGuid)
    local level = Osi.GetRegion(entityGuid)
    if level and entityUuid and Players[entityUuid] then
        debugPrint("LeftForceTurnBased", entityGuid)
        if FTBLockedIn[entityUuid] then
            FTBLockedIn[entityUuid] = nil
        end
        stopTruePause(entityUuid)
        if Brawlers[level] and Brawlers[level][entityUuid] then
            Brawlers[level][entityUuid].isInBrawl = true
            if isPlayerControllingDirectly(entityUuid) then
                startPulseAddNearby(entityUuid)
            end
        end
        Ext.Timer.WaitFor(1000, function ()
            startPulseReposition(level)
        end)
        if areAnyPlayersBrawling() then
            startBrawlFizzler(level)
            if isToT() then
                startToTTimers()
            end
            if Brawlers[level] then
                for brawlerUuid, brawler in pairs(Brawlers[level]) do
                    if Players[brawlerUuid] then
                        if not isPlayerControllingDirectly(brawlerUuid) then
                            Ext.Timer.WaitFor(2000, function ()
                                Osi.FlushOsirisQueue(brawlerUuid)
                                startPulseAction(brawler)
                            end)
                        end
                        Brawlers[level][brawlerUuid].isPaused = false
                        if brawlerUuid ~= entityUuid then
                            Osi.ForceTurnBasedMode(brawlerUuid, 0)
                        end
                    else
                        startPulseAction(brawler)
                    end
                end
            end
        end
    end
end

local function onTurnEnded(entityGuid)
    -- NB: how's this work for the "environmental turn"?
    debugPrint("TurnEnded", entityGuid)
end

local function onDied(entityGuid)
    debugPrint("Died", entityGuid)
    local level = Osi.GetRegion(entityGuid)
    local entityUuid = Osi.GetUUID(entityGuid)
    if level ~= nil and entityUuid ~= nil and Brawlers[level] ~= nil and Brawlers[level][entityUuid] ~= nil then
        -- Sometimes units don't appear dead when killed out-of-combat...
        -- this at least makes them lie prone (and dead-appearing units still appear dead)
        Ext.Timer.WaitFor(LIE_ON_GROUND_TIMEOUT, function ()
            debugPrint("LieOnGround", entityUuid)
            Osi.PurgeOsirisQueue(entityUuid, 1)
            Osi.FlushOsirisQueue(entityUuid)
            Osi.LieOnGround(entityUuid)
        end)
        removeBrawler(level, entityUuid)
        checkForEndOfBrawl(level)
    end
end

-- NB: entity.ClientControl does NOT get reliably updated immediately when this fires
local function onGainedControl(targetGuid)
    debugPrint("GainedControl", targetGuid)
    local targetUuid = Osi.GetUUID(targetGuid)
    if targetUuid ~= nil then
        Osi.PurgeOsirisQueue(targetUuid, 1)
        Osi.FlushOsirisQueue(targetUuid)
        local targetUserId = Osi.GetReservedUserID(targetUuid)
        if Players[targetUuid] ~= nil and targetUserId ~= nil then
            Players[targetUuid].isControllingDirectly = true
            startPulseAddNearby(targetUuid)
            local level = Osi.GetRegion(targetUuid)
            for playerUuid, player in pairs(Players) do
                if player.userId == targetUserId and playerUuid ~= targetUuid then
                    player.isControllingDirectly = false
                    if level and Brawlers[level] and Brawlers[level][playerUuid] and Brawlers[level][playerUuid].isInBrawl then
                        stopPulseAddNearby(playerUuid)
                        startPulseAction(Brawlers[level][playerUuid])
                    end
                end
            end
            if level and Brawlers[level] and Brawlers[level][targetUuid] and not FullAuto then
                stopPulseAction(Brawlers[level][targetUuid], true)
            end
            debugDump(Players)
            Ext.ServerNet.PostMessageToUser(targetUserId, "GainedControl", targetUuid)
        end
    end
end

local function onCharacterJoinedParty(character)
    debugPrint("CharacterJoinedParty", character)
    local uuid = Osi.GetUUID(character)
    if uuid then
        if Players and not Players[uuid] then
            setupPlayer(uuid)
            setupPartyMembersHitpoints()
        end
        if areAnyPlayersBrawling() then
            addBrawler(uuid, true)
        end
    end
end

local function onCharacterLeftParty(character)
    debugPrint("CharacterLeftParty", character)
    local uuid = Osi.GetUUID(character)
    if uuid then
        if Players and Players[uuid] then
            Players[uuid] = nil
        end
        local level = Osi.GetRegion(uuid)
        if Brawlers and Brawlers[level] and Brawlers[level][uuid] then
            Brawlers[level][uuid] = nil
        end
    end
end

local function onDownedChanged(character, isDowned)
    local entityUuid = Osi.GetUUID(character)
    debugPrint("DownedChanged", character, isDowned, entityUuid)
    local player = Players[entityUuid]
    local level = Osi.GetRegion(entityUuid)
    if player then
        if isDowned == 1 and AutoPauseOnDowned and player.isControllingDirectly then
            if Brawlers[level] and Brawlers[level][entityUuid] and not Brawlers[level][entityUuid].isPaused then
                Osi.ForceTurnBasedMode(entityUuid, 1)
            end
        end
        if isDowned == 0 then
            player.isBeingHelped = false
        end
    end
end

local function onAttackedBy(defenderGuid, attackerGuid, attacker2, damageType, damageAmount, damageCause, storyActionID)
    debugPrint("AttackedBy", defenderGuid, attackerGuid, attacker2, damageType, damageAmount, damageCause, storyActionID)
    local attackerUuid = Osi.GetUUID(attackerGuid)
    local defenderUuid = Osi.GetUUID(defenderGuid)
    if attackerUuid ~= nil and defenderUuid ~= nil and Osi.IsCharacter(attackerUuid) == 1 and Osi.IsCharacter(defenderUuid) == 1 then
        if isToT() then
            addBrawler(attackerUuid, true)
            addBrawler(defenderUuid, true)
        end
        if Osi.IsPlayer(attackerUuid) == 1 then
            PlayerCurrentTarget[attackerUuid] = defenderUuid
            if Osi.IsPlayer(defenderUuid) == 0 and damageAmount > 0 then
                IsAttackingOrBeingAttackedByPlayer[defenderUuid] = attackerUuid
            end
            if isToT() then
                addNearbyToBrawlers(attackerUuid, 30, nil, true)
            end
        end
        if Osi.IsPlayer(defenderUuid) == 1 then
            if Osi.IsPlayer(attackerUuid) == 0 and damageAmount > 0 then
                IsAttackingOrBeingAttackedByPlayer[attackerUuid] = defenderUuid
            end
            if isToT() then
                addNearbyToBrawlers(defenderUuid, 30, nil, true)
            end
        end
        startBrawlFizzler(Osi.GetRegion(attackerUuid))
    end
end

local function doLocalResourceAccounting(uuid, spellName)
    if ActionsInProgress[uuid] then
        local foundActionInProgress = false
        local actionsInProgressIndex = nil
        for i, actionInProgress in ipairs(ActionsInProgress[uuid]) do
            if actionInProgress == spellName then
                foundActionInProgress = true
                actionsInProgressIndex = i
                break
            end
        end
        if foundActionInProgress then
            for i = actionsInProgressIndex, 1, -1 do
                debugPrint("remove action in progress", i, getDisplayName(uuid), ActionsInProgress[uuid])
                table.remove(ActionsInProgress[uuid], i)
            end
            return true
        end
    end
    return false
end

local function onCastedSpell(caster, spellName, spellType, spellElement, storyActionID)
    debugPrint("CastedSpell", caster, spellName, spellType, spellElement, storyActionID)
    local casterUuid = Osi.GetUUID(caster)
    local entity = Ext.Entity.Get(casterUuid)
    debugDump(ActionsInProgress[casterUuid])
    if entity and doLocalResourceAccounting(casterUuid, spellName) then
        debugPrint("using local resource accounting")
        local spell = getSpellByName(spellName)
        for costType, costValue in pairs(spell.costs) do
            if costType == "ShortRest" or costType == "LongRest" then
                if costValue then
                    if entity.SpellBook and entity.SpellBook.Spells then
                        for _, spell in ipairs(entity.SpellBook.Spells) do
                            if spell.Id.Prototype == spellName then
                                spell.Charged = false
                                entity:Replicate("SpellBook")
                                break
                            end
                        end
                    end
                end
            elseif costType ~= "ActionPoint" and costType ~= "BonusActionPoint" then
                if costType == "SpellSlot" then
                    local spellSlots = entity.ActionResources.Resources[ACTION_RESOURCES[costType]]
                    for _, spellSlot in ipairs(spellSlots) do
                        if spellSlot.Level >= costValue and spellSlot.Amount > 0 then
                            spellSlot.Amount = spellSlot.Amount - 1
                            break
                        end
                    end
                else
                    local resource = entity.ActionResources.Resources[ACTION_RESOURCES[costType]][1] -- NB: always index 1?
                    debugDump(resource)
                    resource.Amount = resource.Amount - costValue
                end
            end
        end
        entity:Replicate("ActionResources")
    end
end

local function onDialogStarted(dialog, dialogInstanceId)
    debugPrint("DialogStarted", dialog, dialogInstanceId)
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    stopPulseReposition(level)
    stopBrawlFizzler(level)
    if Brawlers[level] then
        for brawlerUuid, brawler in pairs(Brawlers[level]) do
            stopPulseAction(brawler, true)
        end
    end
end

local function onDialogEnded(dialog, dialogInstanceId)
    debugPrint("DialogEnded", dialog, dialogInstanceId)
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    startPulseReposition(level)
    if Brawlers[level] then
        for brawlerUuid, brawler in pairs(Brawlers[level]) do
            if brawler.isInBrawl and not isPlayerControllingDirectly(brawlerUuid) then
                startPulseAction(brawler)
            end
        end
    end
end

local function onDifficultyChanged(difficulty)
    debugPrint("DifficultyChanged", difficulty)
    setMovementSpeedThresholds()
end

local function onTeleportedToCamp(character)
    local entityUuid = Osi.GetUUID(character)
    if entityUuid ~= nil and Brawlers ~= nil then
        for level, brawlersInLevel in pairs(Brawlers) do
            if brawlersInLevel[entityUuid] ~= nil then
                removeBrawler(level, entityUuid)
                checkForEndOfBrawl(level)
            end
        end
    end
end

local function onTeleportedFromCamp(character)
    local entityUuid = Osi.GetUUID(character)
    if entityUuid ~= nil and areAnyPlayersBrawling() then
        addBrawler(entityUuid, false)
    end
end

-- thank u focus
local function onPROC_Subregion_Entered(characterGuid, _)
    debugPrint("PROC_Subregion_Entered", characterGuid)
    local uuid = Osi.GetUUID(characterGuid)
    local level = Osi.GetRegion(uuid)
    if level and Players and Players[uuid] then
        pulseReposition(level)
    end
end

local function onLevelUnloading(level)
    debugPrint("LevelUnloading", level)
    Brawlers[level] = nil
    stopPulseReposition(level)
end

local function stopListeners()
    cleanupAll()
    for _, listener in pairs(Listeners) do
        listener.stop(listener.handle)
    end
end

local function startListeners()
    debugPrint("Starting listeners...")
    Listeners.ResetCompleted = {}
    Listeners.ResetCompleted.handle = Ext.Events.ResetCompleted:Subscribe(onResetCompleted)
    Listeners.ResetCompleted.stop = function () Ext.Events.ResetCompleted:Unsubscribe(Listeners.ResetCompleted.handle) end
    Listeners.UserReservedFor = {
        handle = Ext.Entity.Subscribe("UserReservedFor", onUserReservedFor),
        stop = Ext.Entity.Unsubscribe,
    }
    Listeners.LevelGameplayStarted = {
        handle = Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", onLevelGameplayStarted),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.CombatStarted = {
        handle = Ext.Osiris.RegisterListener("CombatStarted", 1, "after", onCombatStarted),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.CombatEnded = {
        handle = Ext.Osiris.RegisterListener("CombatEnded", 1, "after", onCombatEnded),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.CombatRoundStarted = {
        handle = Ext.Osiris.RegisterListener("CombatRoundStarted", 2, "after", onCombatRoundStarted),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.EnteredCombat = {
        handle = Ext.Osiris.RegisterListener("EnteredCombat", 2, "after", onEnteredCombat),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.EnteredForceTurnBased = {
        handle = Ext.Osiris.RegisterListener("EnteredForceTurnBased", 1, "after", onEnteredForceTurnBased),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.LeftForceTurnBased = {
        handle = Ext.Osiris.RegisterListener("LeftForceTurnBased", 1, "after", onLeftForceTurnBased),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.TurnEnded = {
        handle = Ext.Osiris.RegisterListener("TurnEnded", 1, "after", onTurnEnded),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.Died = {
        handle = Ext.Osiris.RegisterListener("Died", 1, "after", onDied),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.GainedControl = {
        handle = Ext.Osiris.RegisterListener("GainedControl", 1, "after", onGainedControl),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.CharacterJoinedParty = {
        handle = Ext.Osiris.RegisterListener("CharacterJoinedParty", 1, "after", onCharacterJoinedParty),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.CharacterLeftParty = {
        handle = Ext.Osiris.RegisterListener("CharacterLeftParty", 1, "after", onCharacterLeftParty),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.DownedChanged = {
        handle = Ext.Osiris.RegisterListener("DownedChanged", 2, "after", onDownedChanged),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.AttackedBy = {
        handle = Ext.Osiris.RegisterListener("AttackedBy", 7, "after", onAttackedBy),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.CastedSpell = {
        handle = Ext.Osiris.RegisterListener("CastedSpell", 5, "after", onCastedSpell),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.DialogStarted = {
        handle = Ext.Osiris.RegisterListener("DialogStarted", 2, "before", onDialogStarted),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.DialogEnded = {
        handle = Ext.Osiris.RegisterListener("DialogEnded", 2, "after", onDialogEnded),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.DifficultyChanged = {
        handle = Ext.Osiris.RegisterListener("DifficultyChanged", 1, "after", onDifficultyChanged),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.TeleportedToCamp = {
        handle = Ext.Osiris.RegisterListener("TeleportedToCamp", 1, "after", onTeleportedToCamp),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.TeleportedFromCamp = {
        handle = Ext.Osiris.RegisterListener("TeleportedFromCamp", 1, "after", onTeleportedFromCamp),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.PROC_Subregion_Entered = {
        handle = Ext.Osiris.RegisterListener("PROC_Subregion_Entered", 2, "after", onPROC_Subregion_Entered),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.LevelUnloading = {
        handle = Ext.Osiris.RegisterListener("LevelUnloading", 1, "after", onLevelUnloading),
        stop = Ext.Osiris.UnregisterListener,
    }
end

local function onGameStateChanged(e)
    if e and e.ToState == "UnloadLevel" then
        cleanupAll()
    end
end

local function disableCompanionAI()
    debugPrint("companion ai disabled")
    CompanionAIEnabled = false
    for playerUuid, player in pairs(Players) do
        local level = Osi.GetRegion(playerUuid)
        if level and Brawlers and Brawlers[level] and Brawlers[level][playerUuid] then
            Osi.PurgeOsirisQueue(playerUuid, 1)
            Osi.FlushOsirisQueue(playerUuid)
            stopPulseAction(Brawlers[level][playerUuid])
        end
    end
    Osi.QuestMessageHide("ModStatusMessage")
    Osi.QuestMessageShow("ModStatusMessage", "Companion AI Disabled")
    Ext.Timer.WaitFor(3000, function ()
        Osi.QuestMessageHide("ModStatusMessage")
    end)
end

local function enableCompanionAI()
    debugPrint("companion ai enabled")
    CompanionAIEnabled = true
    if Players and areAnyPlayersBrawling() then
        for playerUuid, player in pairs(Players) do
            if not isPlayerControllingDirectly(playerUuid) then
                addBrawler(playerUuid, true, true)
            end
        end
    end
    Osi.QuestMessageHide("ModStatusMessage")
    Osi.QuestMessageShow("ModStatusMessage", "Companion AI Enabled")
    Ext.Timer.WaitFor(3000, function ()
        Osi.QuestMessageHide("ModStatusMessage")
    end)
end

local function disableFullAuto()
    debugPrint("full auto disabled")
    FullAuto = false
    for playerUuid, player in pairs(Players) do
        if isPlayerControllingDirectly(playerUuid) then
            local level = Osi.GetRegion(playerUuid)
            if level and Brawlers and Brawlers[level] and Brawlers[level][playerUuid] then
                Osi.PurgeOsirisQueue(playerUuid, 1)
                Osi.FlushOsirisQueue(playerUuid)
                stopPulseAction(Brawlers[level][playerUuid])
            end
        end
    end
    Osi.QuestMessageHide("ModStatusMessage")
    Osi.QuestMessageShow("ModStatusMessage", "Full Auto Disabled")
    Ext.Timer.WaitFor(3000, function ()
        Osi.QuestMessageHide("ModStatusMessage")
    end)
end

local function enableFullAuto()
    debugPrint("full auto enabled")
    FullAuto = true
    if Players and areAnyPlayersBrawling() then
        for playerUuid, player in pairs(Players) do
            addBrawler(playerUuid, true, true)
        end
    end
    Osi.QuestMessageHide("ModStatusMessage")
    Osi.QuestMessageShow("ModStatusMessage", "Full Auto Enabled")
    Ext.Timer.WaitFor(3000, function ()
        Osi.QuestMessageHide("ModStatusMessage")
    end)
end

local function toggleCompanionAI()
    if CompanionAIEnabled then
        disableCompanionAI()
    else
        enableCompanionAI()
    end
end

local function toggleFullAuto()
    if FullAuto then
        disableFullAuto()
    else
        enableFullAuto()
    end
end

local function disableMod()
    ModEnabled = false
    stopListeners()
    Osi.QuestMessageHide("ModStatusMessage")
    Osi.QuestMessageShow("ModStatusMessage", "Brawl Disabled")
    Ext.Timer.WaitFor(3000, function ()
        Osi.QuestMessageHide("ModStatusMessage")
    end)
end

local function enableMod()
    ModEnabled = true
    startListeners()
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
        onStarted(level)
    end
    Osi.QuestMessageHide("ModStatusMessage")
    Osi.QuestMessageShow("ModStatusMessage", "Brawl Enabled")
    Ext.Timer.WaitFor(3000, function ()
        Osi.QuestMessageHide("ModStatusMessage")
    end)
end

local function toggleMod()
    if ModEnabled then
        disableMod()
    else
        enableMod()
    end
end

local function onMCMSettingSaved(payload)
    debugDump(payload)
    if not payload or payload.modUUID ~= ModuleUUID or not payload.settingId then
        return
    end
    if payload.settingId == "mod_enabled" then
        ModEnabled = payload.value
        if ModEnabled then
            enableMod()
        else
            disableMod()
        end
    elseif payload.settingId == "companion_ai_enabled" then
        CompanionAIEnabled = payload.value
        if CompanionAIEnabled then
            enableCompanionAI()
        else
            disableCompanionAI()
        end
    elseif payload.settingId == "true_pause" then
        TruePause = payload.value
        checkTruePauseParty()
    elseif payload.settingId == "auto_pause_on_downed" then
        AutoPauseOnDowned = payload.value
    elseif payload.settingId == "action_interval" then
        ActionInterval = payload.value
    elseif payload.settingId == "hitpoints_multiplier" then
        HitpointsMultiplier = payload.value
        setupPartyMembersHitpoints()
        local level = Osi.GetRegion(Osi.GetHostCharacter())
        if Brawlers and Brawlers[level] then
            for brawlerUuid, brawler in pairs(Brawlers[level]) do
                revertHitpoints(brawlerUuid)
                modifyHitpoints(brawlerUuid)
            end
        end
    elseif payload.settingId == "full_auto" then
        FullAuto = payload.value
        if FullAuto then
            enableFullAuto()
        else
            disableFullAuto()
        end
    elseif payload.settingId == "tav_archetype" then
        TavArchetype = string.lower(payload.value)
    elseif payload.settingId == "companion_tactics" then
        CompanionTactics = payload.value
    elseif payload.settingId == "companion_ai_max_spell_level" then
        CompanionAIMaxSpellLevel = payload.value
    elseif payload.settingId == "hogwild_mode" then
        HogwildMode = payload.value
    end
end

local function targetCloserOrFartherEnemy(data, targetFartherEnemy)
    local player = getPlayerByUserId(peerToUserId(data.UserID))
    if player then
        local brawler = getBrawlerByUuid(player.uuid)
        if brawler and not brawler.isPaused then
            buildClosestEnemyBrawlers(player.uuid)
            if ClosestEnemyBrawlers[player.uuid] ~= nil and next(ClosestEnemyBrawlers[player.uuid]) ~= nil then
                debugPrint("Selecting next enemy brawler")
                selectNextEnemyBrawler(player.uuid, targetFartherEnemy)
            end
        end
    end
end

local function processActionButton(data, isController)
    local player = getPlayerByUserId(peerToUserId(data.UserID))
    if player then
        -- controllers don't have many buttons, so we only want the actionbar hotkeys to trigger actions if we're in a fight and not paused
        if isController then
            local brawler = getBrawlerByUuid(player.uuid)
            if not brawler or brawler.isPaused then
                return
            end
        end
        local actionButtonLabel = tonumber(data.Payload)
        if ACTION_BUTTON_TO_SLOT[actionButtonLabel] ~= nil and isAliveAndCanFight(player.uuid) then
            local spellName = getSpellNameBySlot(player.uuid, ACTION_BUTTON_TO_SLOT[actionButtonLabel])
            if spellName ~= nil then
                local spell = getSpellByName(spellName)
                -- NB: maintain separate friendly target list for healing/buffs?
                if spell ~= nil and (spell.type == "Buff" or spell.type == "Healing") then
                    return useSpellAndResources(player.uuid, player.uuid, spellName)
                end
                -- if isZoneSpell(spellName) or isProjectileSpell(spellName) then
                --     return useSpellAndResources(player.uuid, nil, spellName)
                -- end
                if PlayerMarkedTarget[player.uuid] == nil or Osi.IsDead(PlayerMarkedTarget[player.uuid]) == 1 then
                    buildClosestEnemyBrawlers(player.uuid)
                end
                return useSpellAndResources(player.uuid, PlayerMarkedTarget[player.uuid], spellName)
            end
        end
    end
end

local function onNetMessage(data)
    if data.Channel == "ModToggle" then
        if MCM then
            MCM.Set("mod_enabled", not ModEnabled)
        else
            toggleMod()
        end
    elseif data.Channel == "CompanionAIToggle" then
        if MCM then
            MCM.Set("companion_ai_enabled", not CompanionAIEnabled)
        else
            toggleCompanionAI()
        end
    elseif data.Channel == "FullAutoToggle" then
        if MCM then
            MCM.Set("full_auto", not FullAuto)
        else
            toggleFullAuto()
        end
    elseif data.Channel == "ExitFTB" then
        debugPrint("Got ExitFTB signal from client")
        allExitFTB()
    -- should this be per-player, or just drag everyone in at the same time?
    elseif data.Channel == "EnterFTB" then
        debugPrint("Got EnterFTB signal from client")
        allEnterFTB()
    elseif data.Channel == "ClickPosition" then
        local player = getPlayerByUserId(peerToUserId(data.UserID))
        if player and player.uuid then
            local clickPosition = Ext.Json.Parse(data.Payload)
            local validX, validY, validZ
            if clickPosition then
                if clickPosition.position then
                    local pos = clickPosition.position
                    validX, validY, validZ = Osi.FindValidPosition(pos[1], pos[2], pos[3], 0, player.uuid, 1)
                    if validX ~= nil and validY ~= nil and validZ ~= nil then
                        LastClickPosition[player.uuid] = {position = {validX, validY, validZ}}
                    end
                end
                if AwaitingTarget[player.uuid] then
                    AwaitingTarget[player.uuid] = false
                    Ext.ServerNet.PostMessageToClient(player.uuid, "AwaitingTarget", "0")
                    local level = Osi.GetRegion(player.uuid)
                    if clickPosition.uuid and level and Brawlers and Brawlers[level] then
                        local targetUuid = clickPosition.uuid
                        Osi.ApplyStatus(targetUuid, "END_HIGHHALLINTERIOR_DROPPODTARGET_VFX", 1)
                        Osi.ApplyStatus(targetUuid, "MAG_ARCANE_VAMPIRISM_VFX", 1)
                        if not Brawlers[level][targetUuid] then
                            addBrawler(targetUuid, true)
                        end
                        for uuid, _ in pairs(Players) do
                            if not isPlayerControllingDirectly(uuid) or FullAuto then
                                if not Brawlers[level][uuid] then
                                    addBrawler(uuid, true)
                                end
                                if uuid ~= targetUuid then
                                    Brawlers[level][uuid].targetUuid = targetUuid
                                    Brawlers[level][uuid].lockedOnTarget = true
                                    debugPrint("Set target to", uuid, getDisplayName(uuid), targetUuid, getDisplayName(targetUuid))
                                end
                            end
                        end
                    elseif clickPosition.position then
                        if validX ~= nil and validY ~= nil and validZ ~= nil then
                            local dummyUuid = Osi.CreateAt("c13a872b-7d9b-4c1d-8c65-f672333b0c11", validX, validY, validZ, 0, 0, "")
                            local dummyEntity = Ext.Entity.Get(dummyUuid)
                            dummyEntity.GameObjectVisual.Scale = 0.0
                            dummyEntity:Replicate("GameObjectVisual")
                            -- Osi.ApplyStatus(dummyUuid, "HEROES_FEAST_CHEST", 1)
                            Osi.ApplyStatus(dummyUuid, "END_HIGHHALLINTERIOR_DROPPODTARGET_VFX", 1)
                            Osi.ApplyStatus(dummyUuid, "MAG_ARCANE_VAMPIRISM_VFX", 1)
                            for uuid, _ in pairs(Players) do
                                if not isPlayerControllingDirectly(uuid) or FullAuto then
                                    Osi.PurgeOsirisQueue(uuid, 1)
                                    Osi.FlushOsirisQueue(uuid)
                                    Osi.CharacterMoveToPosition(uuid, validX, validY, validZ, getMovementSpeed(uuid), "")
                                end
                            end
                            Ext.Timer.WaitFor(1000, function ()
                                Osi.RequestDelete(dummyUuid)
                            end)
                        end
                    end
                end
            end
        end
    elseif data.Channel == "ActionButton" then
        processActionButton(data, false)
    elseif data.Channel == "ControllerActionButton" then
        processActionButton(data, true)
    elseif data.Channel == "TargetCloserEnemy" then
        targetCloserOrFartherEnemy(data, false)
    elseif data.Channel == "TargetFartherEnemy" then
        targetCloserOrFartherEnemy(data, true)
    elseif data.Channel == "OnMe" then
        if Players then
            local player = getPlayerByUserId(peerToUserId(data.UserID))
            if player and player.uuid and Osi.IsInForceTurnBasedMode(player.uuid) == 0 then
                Osi.ApplyStatus(player.uuid, "GUIDED_STRIKE", 1)
                Osi.ApplyStatus(player.uuid, "MAG_ARCANE_VAMPIRISM_VFX", 1)
                -- Osi.ApplyStatus(player.uuid, "END_HIGHHALLINTERIOR_DROPPODTARGET_VFX", 1)
                -- Osi.ApplyStatus(player.uuid, "PASSIVE_DISCIPLE_OF_LIFE", 1)
                for uuid, _ in pairs(Players) do
                    if not isPlayerControllingDirectly(uuid) then
                        Osi.PurgeOsirisQueue(uuid, 1)
                        Osi.FlushOsirisQueue(uuid)
                        Osi.CharacterMoveTo(uuid, player.uuid, getMovementSpeed(uuid), "")
                    end
                end
            end
        end
    elseif data.Channel == "AttackMyTarget" then
        if Players and Brawlers then
            local player = getPlayerByUserId(peerToUserId(data.UserID))
            local level = Osi.GetRegion(player.uuid)
            if level and Brawlers[level] and Osi.IsInForceTurnBasedMode(player.uuid) == 0 then
                local currentTarget
                if PlayerMarkedTarget[player.uuid] then
                    currentTarget = PlayerMarkedTarget[player.uuid]
                elseif IsAttackingOrBeingAttackedByPlayer[player.uuid] then
                    currentTarget = IsAttackingOrBeingAttackedByPlayer[player.uuid]
                elseif PlayerCurrentTarget[player.uuid] then
                    currentTarget = PlayerCurrentTarget[player.uuid]
                end
                debugPrint("Got current player's target", currentTarget)
                if currentTarget and Brawlers[level][currentTarget] and isAliveAndCanFight(currentTarget) then
                    Osi.ApplyStatus(currentTarget, "END_HIGHHALLINTERIOR_DROPPODTARGET_VFX", 1)
                    Osi.ApplyStatus(currentTarget, "MAG_ARCANE_VAMPIRISM_VFX", 1)
                    for uuid, _ in pairs(Players) do
                        if (not isPlayerControllingDirectly(uuid) or FullAuto) and Brawlers[level][uuid] then
                            Brawlers[level][uuid].targetUuid = currentTarget
                            Brawlers[level][uuid].lockedOnTarget = true
                            debugPrint("Set target to", uuid, getDisplayName(uuid), currentTarget, getDisplayName(currentTarget))
                        end
                    end
                end
            end
        end
    elseif data.Channel == "AttackMove" then
        if Players then
            local player = getPlayerByUserId(peerToUserId(data.UserID))
            if player and player.uuid and Osi.IsInForceTurnBasedMode(player.uuid) == 0 then
                AwaitingTarget[player.uuid] = true
                Ext.ServerNet.PostMessageToClient(player.uuid, "AwaitingTarget", "1")
            end
        end
    end
end

local function onSessionLoaded()
    Ext.Events.NetMessage:Subscribe(onNetMessage)
    if ModEnabled then
        startListeners()
    else
        Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", resetPlayers)
    end
end

Ext.Events.SessionLoaded:Subscribe(onSessionLoaded)
Ext.Events.GameStateChanged:Subscribe(onGameStateChanged)
Ext.ModEvents.BG3MCM["MCM_Setting_Saved"]:Subscribe(onMCMSettingSaved)
