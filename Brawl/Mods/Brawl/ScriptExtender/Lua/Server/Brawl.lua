-- MCM Settings
ModEnabled = true
CompanionAIEnabled = true
if MCM then
    ModEnabled = MCM.Get("mod_enabled")
    CompanionAIEnabled = MCM.Get("companion_ai_enabled")
end

-- Constants
local DEBUG_LOGGING = true
local ACTION_INTERVAL = 6000
local REPOSITION_INTERVAL = 2500
local BRAWL_FIZZLER_TIMEOUT = 15000 -- if 10 seconds elapse with no attacks or pauses, end the brawl
local LIE_ON_GROUND_TIMEOUT = 2500
local ENTER_COMBAT_RANGE = 20
local NEARBY_RADIUS = 35
local MELEE_RANGE = 1.5
local RANGED_RANGE_MAX = 25
local RANGED_RANGE_SWEETSPOT = 10
local RANGED_RANGE_MIN = 5
local MAX_COMPANION_DISTANCE_FROM_PLAYER = 20
local MUST_BE_AN_ERROR_MAX_DISTANCE_FROM_PLAYER = 100
local HITPOINTS_MULTIPLIER = 3
local MOVEMENT_DISTANCE_UUID = "d6b2369d-84f0-4ca4-a3a7-62d2d192a185"
local LOOPING_COMBAT_ANIMATION_ID = "7bb52cd4-0b1c-4926-9165-fa92b75876a3" -- monk animation, should prob be a lookup?
local USABLE_COMPANION_SPELLS = {
    Shout_BladeWard = true,
    Projectile_RayOfFrost = true,
    Projectile_FireBolt = true,
    Projectile_EldritchBlast = true,
    -- Projectile_MagicMissile = true,
    Target_MainHandAttack = true,
    Target_OffhandAttack = true,
    Target_Topple = true,
    Target_UnarmedAttack = true,
    Target_AdvancedMeleeWeaponAction = true,
    -- Target_Counterspell = true,
    -- Target_CripplingStrike = true,
    Target_CuttingWords = true,
    -- Target_DisarmingAttack = true,
    -- Target_DisarmingStrike = true,
    -- Target_Flurry = true,
    Target_LungingAttack = true,
    Target_OpeningAttack = true,
    Target_PiercingThrust = true,
    -- Target_PommelStrike = true,
    Target_PushingAttack = true,
    Target_RecklessAttack = true,
    -- Target_Riposte = true,
    Target_SacredFlame = true,
    Target_ShockingGrasp = true,
    -- Target_Shove = true,
    Target_Slash = true,
    Target_Smash = true,
    Target_ThornWhip = true,
    -- Target_TripAttack = true,
    Target_TrueStrike = true,
    Target_ViciousMockery = true,
    -- Target_FlurryOfBlows = true,
    -- Target_StunningStrike = true,
    Rush_Rush = true,
    Rush_WEAPON_ACTION_RUSH = true,
    Rush_Aggressive = true,
    -- Rush_ForceTunnel = true,
}
-- NB: Is "Dash" different from "Sprint"?
local PLAYER_MOVEMENT_SPEED_DEFAULT = {Dash = 6.0, Sprint = 6.0, Run = 3.75, Walk = 2.0, Stroll = 1.4}
local MOVEMENT_SPEED_THRESHOLDS = {
    HONOUR = {Sprint = 5, Run = 2, Walk = 1},
    HARD = {Sprint = 6, Run = 4, Walk = 2},
    MEDIUM = {Sprint = 8, Run = 5, Walk = 3},
    EASY = {Sprint = 12, Run = 9, Walk = 6},
}

-- Session state
Listeners = {}
Brawlers = {}
Players = {}
PulseRepositionTimers = {}
PulseActionTimers = {}
BrawlFizzler = {}
ModifiedHitpoints = {}
-- DynamicAnimationTagsSubscription = nil
MovementSpeedThresholds = MOVEMENT_SPEED_THRESHOLDS.EASY
BrawlActive = false
PlayerCurrentTarget = nil
IsUsingController = false

function debugPrint(...)
    if DEBUG_LOGGING then
        print(...)
    end
end

function debugDump(...)
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

function isDowned(entityUuid)
    return Osi.IsDead(entityUuid) == 0 and Osi.GetHitpoints(entityUuid) == 0
end

function isAliveAndCanFight(entityUuid)
    return Osi.IsDead(entityUuid) == 0 and Osi.GetHitpoints(entityUuid) > 0 and Osi.CanFight(entityUuid) == 1
end

function isPlayerOrAlly(entityUuid)
    return Osi.IsPlayer(entityUuid) == 1 or Osi.IsAlly(Osi.GetHostCharacter(), entityUuid) == 1
end

function isPugnacious(entityUuid)
    return Osi.IsEnemy(Osi.GetHostCharacter(), entityUuid) == 1
end

function getDisplayName(entityUuid)
    return Osi.ResolveTranslatedString(Osi.GetDisplayName(entityUuid))
end

-- thank u focus
---@return "EASY"|"MEDIUM"|"HARD"|"HONOUR"
function getDifficulty()
    local difficulty = Osi.GetRulesetModifierString("cac2d8bd-c197-4a84-9df1-f86f54ad4521")
    if difficulty == "HARD" and Osi.GetRulesetModifierBool("338450d9-d77d-4950-9e1e-0e7f12210bb3") == 1 then
        return "HONOUR"
    end
    return difficulty
end

function setMovementSpeedThresholds()
    MovementSpeedThresholds = MOVEMENT_SPEED_THRESHOLDS[getDifficulty()]
end

function enemyMovementDistanceToSpeed(movementDistance)
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

function playerMovementDistanceToSpeed(movementDistance)
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

function getMovementSpeed(entityUuid)
    -- local statuses = Ext.Entity.Get(entityUuid).StatusContainer.Statuses
    local entity = Ext.Entity.Get(entityUuid)
    local movementDistance = entity.ActionResources.Resources[MOVEMENT_DISTANCE_UUID][1].Amount
    local movementSpeed = isPlayerOrAlly(entityUuid) and playerMovementDistanceToSpeed(movementDistance) or enemyMovementDistanceToSpeed(movementDistance)
    -- debugPrint("getMovementSpeed", entityUuid, movementDistance, movementSpeed)
    return movementSpeed
end

function calculateEnRouteCoords(moverUuid, targetUuid, goalDistance)
    local xMover, yMover, zMover = Osi.GetPosition(moverUuid)
    local xTarget, yTarget, zTarget = Osi.GetPosition(targetUuid)
    local dx = xMover - xTarget
    local dy = yMover - yTarget
    local dz = zMover - zTarget
    local fracDistance = goalDistance / math.sqrt(dx*dx + dy*dy + dz*dz)
    return xTarget + dx*fracDistance, yTarget + dy*fracDistance, zTarget + dz*fracDistance
end

function moveToDistanceFromTarget(moverUuid, targetUuid, goalDistance)
    local x, y, z = calculateEnRouteCoords(moverUuid, targetUuid, goalDistance)
    Osi.CharacterMoveToPosition(moverUuid, x, y, z, getMovementSpeed(moverUuid), "")
end

-- Example monk looping animations (can these be interruptable?)
-- (https://bg3.norbyte.dev/search?iid=Resource.6b05dbcc-19ef-475f-62a2-d18c1e640aa7)
-- animMK = "e85be5a8-6e48-4da4-8486-0d168159df4e"
-- animMK = "7bb52cd4-0b1c-4926-9165-fa92b75876a3"
function holdPosition(entityUuid)
    if not isPlayerOrAlly(entityUuid) then
        Osi.PlayAnimation(entityUuid, LOOPING_COMBAT_ANIMATION_ID, "")
    end
end

function getPlayersSortedByDistance(entityUuid)
    local playerDistances = {}
    for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
        local playerUuid = Osi.GetUUID(player[1])
        if Osi.IsDead(playerUuid) == 0 then
            table.insert(playerDistances, {playerUuid, Osi.GetDistanceTo(entityUuid, playerUuid)})
        end
    end
    table.sort(playerDistances, function (a, b) return a[2] > b[2] end)
    return playerDistances
end

function isCompanionSpellUsable(spell)
    return USABLE_COMPANION_SPELLS[spell.OriginatorPrototype]
end

function isSpellUsable(spell, archetype)
    if spell.OriginatorPrototype == "Projectile_Jump" then return false end
    if spell.OriginatorPrototype == "Shout_Dash_NPC" then return false end
    if spell.OriginatorPrototype == "Target_Shove" then return false end
    if spell.OriginatorPrototype == "Target_CureWounds" then return false end
    if spell.OriginatorPrototype == "Target_HealingWord" then return false end
    if spell.OriginatorPrototype == "Target_CureWounds_Mass" then return false end
    if archetype == "melee" then
        if spell.OriginatorPrototype == "Target_Dip_NPC" then return false end
        if spell.OriginatorPrototype == "Target_MageArmor" then return false end
        if spell.OriginatorPrototype == "Projectile_SneakAttack" then return false end
    elseif archetype == "ranged" then
        if spell.OriginatorPrototype == "Target_UnarmedAttack" then return false end
        if spell.OriginatorPrototype == "Target_Topple" then return false end
        if spell.OriginatorPrototype == "Target_Dip_NPC" then return false end
        if spell.OriginatorPrototype == "Target_MageArmor" then return false end
        if spell.OriginatorPrototype == "Projectile_SneakAttack" then return false end
    elseif archetype == "mage" then
        if spell.OriginatorPrototype == "Target_UnarmedAttack" then return false end
        if spell.OriginatorPrototype == "Target_Topple" then return false end
        if spell.OriginatorPrototype == "Target_Dip_NPC" then return false end
    end
    -- if spell.OriginatorPrototype == "Throw_Throw" then return false end
    -- if spell.OriginatorPrototype == "Target_MainHandAttack" then return false end
    return true
end

-- Use CharacterMoveTo when possible to move units around so we can specify movement speeds
-- (automove using UseSpell/Attack only uses the fastest possible movement speed)
function moveThenAct(attackerUuid, targetUuid, spell)
    -- local targetRadius = Ext.Stats.Get(spell).TargetRadius
    -- debugPrint("moveThenAct", attackerUuid, targetUuid, spell, targetRadius)
    -- debugDump(Players[attackerUuid])
    -- if targetRadius == "MeleeMainWeaponRange" then
    --     Osi.CharacterMoveTo(attackerUuid, targetUuid, getMovementSpeed(attackerUuid), "")
    -- else
    --     local targetRadiusNumber = tonumber(targetRadius)
    --     if targetRadiusNumber ~= nil then
    --         local distanceToTarget = Osi.GetDistanceTo(attackerUuid, targetUuid)
    --         if distanceToTarget > targetRadiusNumber then
    --             debugPrint("moveThenAct distance > targetRadius, moving to...")
    --             moveToDistanceFromTarget(attackerUuid, targetUuid, targetRadiusNumber)
    --         end
    --     end
    -- end
    -- debugPrint("moveThenAct UseSpell", attackerUuid, spell, targetUuid)
    Osi.UseSpell(attackerUuid, spell, targetUuid)
end

-- NB: create a better system than this lol
function actOnTarget(brawler, targetUuid)
    local brawlerEntity = Ext.Entity.Get(brawler.uuid)
    local actionToTake = nil
    local archetype = Osi.GetActiveArchetype(brawler.uuid)
    -- melee units should just autoattack sometimes
    if archetype == "melee" then
        local autoAttackRand = math.random()
        -- 50% chance to start autoattacking if they're not already
        if not brawler.isAutoAttacking then
            if autoAttackRand < 0.5 then
                brawler.isAutoAttacking = true
                debugPrint("Start autoattacking", brawler.uuid, targetUuid)
                -- return Osi.Attack(brawler.uuid, targetUuid, 0)
                return moveThenAct(brawler.uuid, targetUuid, "Target_MainHandAttack")
            end
        -- 20% chance to stop autoattacking if they're already doing it
        else
            if autoAttackRand > 0.2 then
                debugDump(brawler)
                -- return Osi.Attack(brawler.uuid, targetUuid, 0)
                return moveThenAct(brawler.uuid, targetUuid, "Target_MainHandAttack")
            end
            brawler.isAutoAttacking = false
        end
    end
    if brawlerEntity.SpellBookPrepares ~= nil then
        -- if they're already in melee range, they should do melee stuff
        local numUsableSpells = 0
        local usableSpells = {}
        for _, preparedSpell in pairs(brawlerEntity.SpellBookPrepares.PreparedSpells) do
            -- local spellStats = Ext.Stats.Get(preparedSpell.OriginatorPrototype)
            -- local useCosts = spellStats.UseCosts
            if Osi.IsPlayer(brawler.uuid) == 1 then
                if isCompanionSpellUsable(preparedSpell) then
                    table.insert(usableSpells, preparedSpell)
                    numUsableSpells = numUsableSpells + 1
                end
            else
                if isSpellUsable(preparedSpell, archetype) then
                    table.insert(usableSpells, preparedSpell)
                    numUsableSpells = numUsableSpells + 1
                end
            end
        end
        actionToTake = usableSpells[math.random(1, numUsableSpells)]
        -- debugPrint("Action to take:")
        -- debugDump(actionToTake)
    end
    if actionToTake == nil then
        return moveThenAct(brawler.uuid, targetUuid, "Target_MainHandAttack")
        -- return Osi.Attack(brawler.uuid, targetUuid, 0)
    end
    moveThenAct(brawler.uuid, targetUuid, actionToTake.OriginatorPrototype)
end

function getBrawlersSortedByDistance(entityUuid)
    local brawlersSortedByDistance = {}
    local level = Osi.GetRegion(entityUuid)
    if Brawlers[level] then
        for brawlerUuid, brawler in pairs(Brawlers[level]) do
            if isAliveAndCanFight(brawlerUuid) then
                -- debugPrint("distance:", brawlerUuid, Osi.GetDistanceTo(entityUuid, brawlerUuid))
                table.insert(brawlersSortedByDistance, {brawlerUuid, Osi.GetDistanceTo(entityUuid, brawlerUuid)})
            end
        end
        table.sort(brawlersSortedByDistance, function (a, b) return a[2] < b[2] end)
    end
    return brawlersSortedByDistance
end

function findTargetToAttack(brawler)
    for _, target in ipairs(getBrawlersSortedByDistance(brawler.uuid)) do
        local targetUuid, distanceToTarget = target[1], target[2]
        if Osi.IsEnemy(brawler.uuid, targetUuid) == 1 and Osi.IsInvisible(targetUuid) == 0 and isAliveAndCanFight(targetUuid) then
            debugPrint("Attack", brawler.displayName, brawler.uuid, distanceToTarget, "->", getDisplayName(targetUuid))
            brawler.targetUuid = targetUuid
            return actOnTarget(brawler, targetUuid)
        end
    end
    holdPosition(brawler.uuid)
end

function isPlayerControllingDirectly(entityUuid)
    return Players[entityUuid] ~= nil and Players[entityUuid].isControllingDirectly == true
end

function stopPulseAction(brawler)
    brawler.isInBrawl = false
    if PulseActionTimers[brawler.uuid] ~= nil then
        debugPrint("stop pulse action", brawler.displayName)
        Ext.Timer.Cancel(PulseActionTimers[brawler.uuid])
        PulseActionTimers[brawler.uuid] = nil
    end
end

function aiCompanionNeedsTeleport(entityUuid)
    if Osi.IsPlayer(entityUuid) == 1 and Players[entityUuid] ~= nil then
        local potentialCompanion = Players[entityUuid]
        if not potentialCompanion.isControllingDirectly then
            for playerUuid, player in pairs(Players) do
                if playerUuid ~= potentialCompanion.uuid then
                    if potentialCompanion.userId == player.userId and player.isControllingDirectly then
                        if Osi.GetDistanceTo(entityUuid, playerUuid) > MUST_BE_AN_ERROR_MAX_DISTANCE_FROM_PLAYER then
                            return playerUuid
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- Brawlers doing dangerous stuff
function pulseAction(brawler)
    -- Brawler is alive and able to fight: let's go!
    if brawler and brawler.uuid and not brawler.isPaused and isAliveAndCanFight(brawler.uuid) and not isPlayerControllingDirectly(brawler.uuid) then
        -- If this unit is extremely far from the player, and it's an AI-controlled unit, it's probably the teleport bug, so warp them back
        local teleportBuggedAiCompanionToPlayer = aiCompanionNeedsTeleport(brawler.uuid)
        if teleportBuggedAiCompanionToPlayer ~= nil then
            Osi.TeleportTo(brawler.uuid, teleportBuggedAiCompanionToPlayer, "", 0, 0, 0, 0, 1)
        -- Doesn't currently have an attack target, so let's find one
        elseif brawler.targetUuid == nil then
            findTargetToAttack(brawler)
        else
            -- Already attacking a target and the target isn't dead, so just keep at it
            if isAliveAndCanFight(brawler.targetUuid) then
                -- debugPrint("Already attacking", brawler.displayName, brawler.uuid, "->", getDisplayName(brawler.targetUuid))
                actOnTarget(brawler, brawler.targetUuid)
            -- Has an attack target but it's already dead or unable to fight, so find a new one
            else
                brawler.targetUuid = nil
                findTargetToAttack(brawler)
            end
        end
    -- If this brawler is dead or unable to fight, stop this pulse
    else
        stopPulseAction(brawler)
    end
end

function startPulseAction(brawler)
    debugPrint("start pulse action for", brawler.displayName)
    if PulseActionTimers[brawler.uuid] ~= nil then
        stopPulseAction(brawler)
    end
    brawler.isInBrawl = true
    PulseActionTimers[brawler.uuid] = Ext.Timer.WaitFor(0, function ()
        pulseAction(brawler)
    end, ACTION_INTERVAL)
end

-- NB: This should never be the first thing that happens (brawl should always kick off with an action)
function repositionRelativeToTarget(brawlerUuid, targetUuid)
    local archetype = Osi.GetActiveArchetype(brawlerUuid)
    local distanceToTarget = Osi.GetDistanceTo(brawlerUuid, targetUuid)
    if isPlayerOrAlly(brawlerUuid) then
        local hostUuid = Osi.GetHostCharacter()
        local targetDistanceFromHost = Osi.GetDistanceTo(targetUuid, hostUuid)
        -- If we're close to melee range, then advance, even if we're too far from the player
        if distanceToTarget < MELEE_RANGE*2 then
            debugPrint("inside melee x 2", brawlerUuid, targetUuid)
            Osi.CharacterMoveTo(brawlerUuid, targetUuid, getMovementSpeed(brawlerUuid), "")
        -- Otherwise, if the target would take us too far from the player, move halfway (?) back towards the player
        -- NB: is this causing the weird teleport bug???
        -- elseif targetDistanceFromHost > MAX_COMPANION_DISTANCE_FROM_PLAYER then
        --     debugPrint("outside max player dist", brawlerUuid, hostUuid)
        --     moveToDistanceFromTarget(brawlerUuid, hostUuid, 0.5*Osi.GetDistanceTo(brawlerUuid, hostUuid))
        else
            holdPosition(brawlerUuid)
        end
    elseif archetype == "melee" then
        if distanceToTarget > MELEE_RANGE then
            Osi.CharacterMoveTo(brawlerUuid, targetUuid, getMovementSpeed(brawlerUuid), "")
        else
            holdPosition(brawlerUuid)
        end
    else
        -- debugPrint("misc bucket reposition", brawlerUuid, getDisplayName(brawlerUuid))
        holdPosition(brawlerUuid)
        -- if distanceToTarget <= MELEE_RANGE then
        --     holdPosition(brawlerUuid)
        -- elseif distanceToTarget < RANGED_RANGE_MIN then
        --     moveToDistanceFromTarget(brawlerUuid, targetUuid, RANGED_RANGE_SWEETSPOT)
        -- elseif distanceToTarget < RANGED_RANGE_MAX then
        --     holdPosition(brawlerUuid)
        -- else
        --     moveToDistanceFromTarget(brawlerUuid, targetUuid, RANGED_RANGE_SWEETSPOT)
        -- end
    end
end

-- Enemies are pugnacious jerks and looking for a fight >:(
function checkForBrawlToJoin(brawler)
    local closestAlivePlayer, closestDistance = Osi.GetClosestAlivePlayer(brawler.uuid)
    -- debugPrint("Closest alive player to", brawler.uuid, brawler.displayName, "is", closestAlivePlayer, closestDistance)
    if closestDistance ~= nil and closestDistance < ENTER_COMBAT_RANGE then
        for _, target in ipairs(getBrawlersSortedByDistance(brawler.uuid)) do
            local targetUuid, distance = target[1], target[2]
            -- NB: also check for farther-away units where there's a nearby brawl happening already? hidden? line-of-sight?
            if Osi.IsEnemy(brawler.uuid, targetUuid) == 1 and Osi.IsInvisible(targetUuid) == 0 and distance < ENTER_COMBAT_RANGE then
                -- debugPrint("Reposition", brawler.displayName, brawler.uuid, distance, "->", getDisplayName(targetUuid))
                BrawlActive = true
                return startPulseAction(brawler)
            end
        end
    end
end

function isBrawlingWithValidTarget(brawler)
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

function addNearbyToBrawlers(entityUuid, nearbyRadius)
    for _, nearby in ipairs(getNearby(entityUuid, nearbyRadius)) do
        if nearby.Entity.IsCharacter and isAliveAndCanFight(nearby.Guid) then
            addBrawler(nearby.Guid)
        end
    end
end

function stopPulseReposition(level)
    if PulseRepositionTimers[level] ~= nil then
        Ext.Timer.Cancel(PulseRepositionTimers[level])
        PulseRepositionTimers[level] = nil
    end
end

-- Reposition the NPC relative to the player.  This is the only place that NPCs should enter the brawl!
function pulseReposition(level)
    if Brawlers[level] then
        for brawlerUuid, brawler in pairs(Brawlers[level]) do
            if isAliveAndCanFight(brawlerUuid) then
                -- Enemy units are actively looking for a fight and will attack if you get too close to them
                if isPugnacious(brawlerUuid) then
                    if brawler.isInBrawl and brawler.targetUuid ~= nil and isAliveAndCanFight(brawler.targetUuid) then
                        -- debugPrint(brawler.displayName, brawlerUuid, "->", getDisplayName(brawler.targetUuid))
                        repositionRelativeToTarget(brawlerUuid, brawler.targetUuid)
                    else
                        checkForBrawlToJoin(brawler)
                    end
                -- Player, ally, and neutral units are not actively looking for a fight
                -- - Companions and allies use the same logic
                -- - Neutrals just chilling
                elseif BrawlActive and isPlayerOrAlly(brawlerUuid) and not brawler.isPaused then
                    -- debugPrint("Player or ally", brawlerUuid, Osi.GetHitpoints(brawlerUuid))
                    if Players[brawlerUuid] and Players[brawlerUuid].isControllingDirectly == true then
                        -- debugPrint("Player is controlling directly: do not take action!")
                        -- debugDump(brawler)
                        -- debugDump(Players)
                        stopPulseAction(brawler)
                    else
                        if not brawler.isInBrawl then
                            if Osi.IsPlayer(brawlerUuid) == 0 or CompanionAIEnabled then
                                debugPrint("Not in brawl, starting pulse action for", brawler.displayName)
                                -- debugDump(brawler)
                                startPulseAction(brawler)
                            end
                        elseif isBrawlingWithValidTarget(brawler) and Osi.IsPlayer(brawlerUuid) == 1 and CompanionAIEnabled then
                            debugPrint("Reposition party member", brawlerUuid)
                            -- debugDump(brawler)
                            -- debugDump(Players)
                            repositionRelativeToTarget(brawlerUuid, brawler.targetUuid)
                        end
                    end
                end
            -- Check if this is a downed player unit and apply Osi.LieOnGround for the visual downed glitch
            elseif Osi.IsPlayer(brawlerUuid) == 1 and isDowned(brawlerUuid) then
                stopPulseReposition(brawlerUuid)
                Ext.Timer.WaitFor(LIE_ON_GROUND_TIMEOUT, function ()
                    if brawler ~= nil and isDowned(brawlerUuid) then
                        debugPrint("Player downed, applying LieOnGround to", brawlerUuid, brawler.displayName)
                        Osi.LieOnGround(brawlerUuid)
                    end
                end)
            end
        end
    end
end

-- Reposition if needed every REPOSITION_INTERVAL ms
function startPulseReposition(level)
    if PulseRepositionTimers[level] ~= nil then
        stopPulseReposition(level)
    end
    PulseRepositionTimers[level] = Ext.Timer.WaitFor(0, function ()
        pulseReposition(level)
    end, REPOSITION_INTERVAL)
end

function setPlayerRunToSprint(entityUuid)
    local entity = Ext.Entity.Get(entityUuid)
    if Players[entityUuid].movementSpeedRun == nil then
        Players[entityUuid].movementSpeedRun = entity.ServerCharacter.Template.MovementSpeedRun
    end
    entity.ServerCharacter.Template.MovementSpeedRun = entity.ServerCharacter.Template.MovementSpeedSprint
end

-- NB: should we also index Brawlers by combatGuid?
function addBrawler(entityUuid)
    if entityUuid ~= nil then
        -- Add a short delay so users have a second to think
        Ext.Timer.WaitFor(1500, function ()
            local level = Osi.GetRegion(entityUuid)
            if level and Brawlers[level] ~= nil and Brawlers[level][entityUuid] == nil and Osi.IsDead(entityUuid) == 0 then
                local displayName = getDisplayName(entityUuid)
                debugPrint("Adding Brawler", entityUuid, displayName)
                Brawlers[level][entityUuid] = {
                    uuid = entityUuid,
                    displayName = displayName,
                    combatGuid = Osi.CombatGetGuidFor(entityUuid),
                    isInBrawl = false,
                    isPaused = Osi.IsInForceTurnBasedMode(entityUuid) == 1,
                }
                if Osi.IsPlayer(entityUuid) == 0 then
                    Brawlers[level][entityUuid].originalCanJoinCombat = Osi.CanJoinCombat(entityUuid),
                    Osi.SetCanJoinCombat(entityUuid, 0)
                elseif Players[entityUuid] then
                    Brawlers[level][entityUuid].originalCanJoinCombat = 1
                    setPlayerRunToSprint(entityUuid)
                end
            end
        end)
    end
end

function getNumEnemiesRemaining(level)
    local numEnemiesRemaining = 0
    for brawlerUuid, brawler in pairs(Brawlers[level]) do
        if isPugnacious(brawlerUuid) and brawler.isInBrawl then
            numEnemiesRemaining = numEnemiesRemaining + 1
        end
    end
    return numEnemiesRemaining
end

function stopBrawlFizzler(level)
    if BrawlFizzler[level] ~= nil then
        debugPrint("Something happened, stopping brawl fizzler...")
        Ext.Timer.Cancel(BrawlFizzler[level])
    end
end

function endBrawl(level)
    BrawlActive = false
    if Brawlers[level] then
        for brawlerUuid, brawler in pairs(Brawlers[level]) do
            stopPulseAction(brawler)
            -- revertHitpoints(brawlerUuid)
            Osi.SetCanJoinCombat(brawlerUuid, brawler.originalCanJoinCombat)
            Osi.FlushOsirisQueue(brawlerUuid)
        end
        debugPrint("Ended brawl")
        debugDump(Brawlers[level])
    end
    resetPlayersMovementSpeed()
    Brawlers[level] = {}
    stopBrawlFizzler(level)
end

function checkForEndOfBrawl(level)
    local numEnemiesRemaining = getNumEnemiesRemaining(level)
    debugPrint("Number of enemies remaining:", numEnemiesRemaining)
    debugDump(Brawlers)
    if numEnemiesRemaining == 0 then
        endBrawl(level)
    end
end

function removeBrawler(level, entityUuid)
    local combatGuid = nil
    local brawler = Brawlers[level][entityUuid]
    stopPulseAction(brawler)
    if Osi.IsPlayer(entityUuid) == 0 then
        Osi.SetCanJoinCombat(entityUuid, brawler.originalCanJoinCombat)
    end
    -- revertHitpoints(entityUuid)
    Brawlers[level][entityUuid] = nil
end

function resetPlayersMovementSpeed()
    for playerUuid, player in pairs(Players) do
        local entity = Ext.Entity.Get(playerUuid)
        entity.ServerCharacter.Template.MovementSpeedRun = PLAYER_MOVEMENT_SPEED_DEFAULT.Run
        -- if player.movementSpeedRun ~= nil then
        --     entity.ServerCharacter.Template.MovementSpeedRun = player.movementSpeedRun
        -- end
    end
end

function resetPlayers()
    Players = {}
    for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
        local uuid = Osi.GetUUID(player[1])
        Players[uuid] = {
            uuid = uuid,
            displayName = getDisplayName(uuid),
            userId = Osi.GetReservedUserID(uuid),
        }
        Osi.SetCanJoinCombat(uuid, 1)
    end
end

function setIsControllingDirectly()
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
        -- debugDump("setIsControllingDirectly")
        -- debugDump(Players)
    end
end

function revertHitpoints(entityUuid)
    local entity = Ext.Entity.Get(entityUuid)
    if entity.IsCharacter and ModifiedHitpoints[entityUuid] ~= nil then
        entity.Health.MaxHp = ModifiedHitpoints[entityUuid].originalMaxHp
        entity.Health.Hp = ModifiedHitpoints[entityUuid].originalHp
        entity:Replicate("Health")
        ModifiedHitpoints[entityUuid] = nil
        debugPrint("Reverted hitpoints:", entityUuid, getDisplayName(entityUuid), entity.Health.MaxHp, entity.Health.Hp)
    end
end

function modifyHitpoints(entityUuid)
    local entity = Ext.Entity.Get(entityUuid)
    if entity.IsCharacter and isAliveAndCanFight(entityUuid) and ModifiedHitpoints[entityUuid] == nil then
        local originalHp = Osi.GetHitpoints(entityUuid)
        local originalMaxHp = Osi.GetMaxHitpoints(entityUuid)
        local modifiedMaxHp = originalMaxHp * HITPOINTS_MULTIPLIER
        local modifiedHp = originalHp * HITPOINTS_MULTIPLIER
        entity.Health.MaxHp = modifiedMaxHp
        entity.Health.Hp = modifiedHp
        entity:Replicate("Health")
        ModifiedHitpoints[entityUuid] = {
            originalHp = originalHp,
            originalMaxHp = originalMaxHp,
            modifiedHp = modifiedHp,
            modifiedMaxHp = modifiedMaxHp,
        }
        debugDump(ModifiedHitpoints[entityUuid])
        debugPrint("Modified hitpoints:", entityUuid, getDisplayName(entityUuid), originalHp, modifiedHp, originalMaxHp, modifiedMaxHp)
    end
end

function cleanupAll()
    for level, timer in pairs(PulseRepositionTimers) do
        Ext.Timer.Cancel(timer)
    end
    for uuid, timer in pairs(PulseActionTimers) do
        Ext.Timer.Cancel(timer)
    end
    for level, timer in pairs(BrawlFizzler) do
        endBrawl(level)
        Ext.Timer.Cancel(timer)
    end
    BrawlActive = false
    PlayerCurrentTarget = nil
end

function onStarted(level)
    resetPlayers()
    setIsControllingDirectly()
    PlayerCurrentTarget = nil
    setMovementSpeedThresholds()
    resetPlayersMovementSpeed() -- NB: not clear why this is needed :/
    initBrawlers(level)
    debugPrint("onStarted")
    debugDump(Players)
end

function startBrawlFizzler(level)
    stopBrawlFizzler(level)
    BrawlFizzler[level] = Ext.Timer.WaitFor(BRAWL_FIZZLER_TIMEOUT, function ()
        debugPrint("Brawl fizzled", BRAWL_FIZZLER_TIMEOUT)
        endBrawl(level)
    end)
end

local function onResetCompleted()
    debugPrint("ResetCompleted")
    onStarted(Osi.GetRegion(Osi.GetHostCharacter()))
end

-- local function onNetMessage(data)
--     debugDump(data)
--     if data.Channel == "IsUsingController" then
--         -- NB: attach this to the player, rather than just a single value for all players?
--         IsUsingController = data.Payload == "1"
--         if IsUsingController and DynamicAnimationTagsSubscription ~= nil then
--             Ext.Entity.Unsubscribe(DynamicAnimationTagsSubscription)
--             DynamicAnimationTagsSubscription = nil
--         end
--     elseif data.Channel == "Clicked" and data.Payload == "ExitFTBButton" then
--         -- data.UserID
--         for playerUuid, player in pairs(Players) do
--             if player.isPaused then
--                 player.isWindingUp = false
--                 local entity = Ext.Entity.Get(playerUuid)
--                 entity.TurnBased.IsInCombat_M = true
--                 entity:Replicate("TurnBased")
--             end
--         end
--     end
-- end

-- New user joined (multiplayer)
local function onUserReservedFor(entity, _, _)
    setIsControllingDirectly()
    local entityUuid = entity.Uuid.EntityUuid
    if Players and Players[entityUuid] then
        local userId = entity.UserReservedFor.UserID
        Players[entityUuid].userId = entity.UserReservedFor.UserID
    end
end

-- -- initiative: highest rolls go ASAP, everyone else gets a delay to their pulseAction initial timer?
-- local function onCombatParticipant(entity, _, _)
--     local entityUuid = entity.Uuid.EntityUuid
--     debugPrint("CombatParticipant", entityUuid, getDisplayName(entityUuid))
-- end

local function onLevelGameplayStarted(level, _)
    debugPrint("LevelGameplayStarted", level)
    onStarted(level)
end

local function onCombatStarted(combatGuid)
    debugPrint("CombatStarted", combatGuid)
    for playerUuid, player in pairs(Players) do
        addBrawler(playerUuid)
    end
    debugDump(Brawlers)
    BrawlActive = true
    addNearbyToBrawlers(Osi.GetHostCharacter(), NEARBY_RADIUS)
end

local function onCombatRoundStarted(combatGuid, round)
    debugPrint("CombatRoundStarted", combatGuid, round)
    for playerUuid, player in pairs(Players) do
        addBrawler(playerUuid)
    end
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
        debugDump(Brawlers)
        BrawlActive = true
        startBrawlFizzler(level)
        Ext.Timer.WaitFor(500, function ()
            addNearbyToBrawlers(Osi.GetHostCharacter(), NEARBY_RADIUS)
            Ext.Timer.WaitFor(1500, function ()
                -- do we need this?  will probably cause story-related problems or at least awkwardness :/
                Osi.EndCombat(combatGuid)
            end)
        end)
    end
end

local function onEnteredCombat(entityGuid, combatGuid)
    debugPrint("EnteredCombat", entityGuid, combatGuid)
    addBrawler(Osi.GetUUID(entityGuid))
end

local function onEnteredForceTurnBased(entityGuid)
    debugPrint("EnteredForceTurnBased", entityGuid)
    local entityUuid = Osi.GetUUID(entityGuid)
    if entityUuid then
        local level = Osi.GetRegion(entityUuid)
        if level then
            for playerUuid, player in pairs(Players) do
                if Brawlers[level][playerUuid] ~= nil and Osi.IsDead(playerUuid) == 0 then
                    Brawlers[level][playerUuid].isPaused = true
                    stopPulseAction(Brawlers[level][playerUuid])
                end
            end
            stopBrawlFizzler(level)
            Osi.PurgeOsirisQueue(entityUuid, 1)
            Osi.FlushOsirisQueue(entityUuid)
            -- if DynamicAnimationTagsSubscription == nil and not IsUsingController then
            --     DynamicAnimationTagsSubscription = Ext.Entity.Subscribe("DynamicAnimationTags", function (entity, _, _)
            --         if entity.SpellCastIsCasting ~= nil and entity.SpellCastIsCasting.Cast ~= nil then
            --             if entity.Uuid.EntityUuid and Players[entity.Uuid.EntityUuid] and not Players[entity.Uuid.EntityUuid].isWindingUp then
            --                 Players[entity.Uuid.EntityUuid].isWindingUp = true
            --                 entity.TurnBased.IsInCombat_M = false
            --                 entity:Replicate("TurnBased")
            --             end
            --         end
            --     end)
            -- end
        end
    end
end

local function onLeftForceTurnBased(entityGuid)
    debugPrint("LeftForceTurnBased", entityGuid)
    local entityUuid = Osi.GetUUID(entityGuid)
    -- if DynamicAnimationTagsSubscription ~= nil then
    --     Ext.Entity.Unsubscribe(DynamicAnimationTagsSubscription)
    -- end
    -- DynamicAnimationTagsSubscription = nil
    -- Ext.Entity.Get(entityUuid).TurnBased.IsInCombat_M = true
    if BrawlActive then
        local level = Osi.GetRegion(entityUuid)
        startBrawlFizzler(level)
        if Brawlers[level] ~= nil then
            local brawler = Brawlers[level][entityUuid]
            if brawler ~= nil then
                brawler.isPaused = false
                if brawler.isInBrawl then
                    startPulseAction(brawler)
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
    -- debugPrint("Died", entityGuid)
    local level = Osi.GetRegion(entityGuid)
    if level ~= nil then
        local entityUuid = Osi.GetUUID(entityGuid)
        if Brawlers[level] ~= nil and Brawlers[level][entityUuid] ~= nil then
            -- Sometimes units don't appear dead when killed out-of-combat...
            -- this at least makes them lie prone (and dead-appearing units still appear dead)
            Ext.Timer.WaitFor(LIE_ON_GROUND_TIMEOUT, function ()
                debugPrint("LieOnGround", entityGuid)
                Osi.LieOnGround(entityGuid)
            end)
            removeBrawler(level, entityUuid)
            checkForEndOfBrawl(level)
        end
    end
end

-- NB: entity.ClientControl does NOT get reliably updated immediately when this fires
local function onGainedControl(targetGuid)
    debugPrint("GainedControl", targetGuid)
    local targetUuid = Osi.GetUUID(targetGuid)
    if targetUuid ~= nil then
        Osi.FlushOsirisQueue(targetUuid)
        -- local targetEntity = Ext.Entity.Get(targetUuid)
        -- local targetUserId = targetEntity.UserAvatar.UserID --buggy?? doesn't match the others??
        -- local targetUserId = targetEntity.UserReservedFor.UserID
        -- local targetUserId = targetEntity.PartyMember.UserId
        local targetUserId = Osi.GetReservedUserID(targetUuid)
        if Players[targetUuid] ~= nil and targetUserId ~= nil then
            Osi.PurgeOsirisQueue(targetUuid, 1)
            Osi.FlushOsirisQueue(targetUuid)
            Players[targetUuid].isControllingDirectly = true
            for playerUuid, player in pairs(Players) do
                if player.userId == targetUserId and playerUuid ~= targetUuid then
                    player.isControllingDirectly = false
                end
            end
            local level = Osi.GetRegion(targetUuid)
            if level and Brawlers[level] and Brawlers[level][targetUuid] then
                stopPulseAction(Brawlers[level][targetUuid])
            end
            debugDump(Players)
        end
    end
end

local function onCharacterJoinedParty(character)
    debugPrint("CharacterJoinedParty", character)
    onStarted(Osi.GetRegion(Osi.GetHostCharacter()))
end

local function onCharacterLeftParty(character)
    debugPrint("CharacterLeftParty", character)
    onStarted(Osi.GetRegion(Osi.GetHostCharacter()))
end

local function onAttackedBy(defenderGuid, attackerGuid, _, _, _, _, _)
    BrawlActive = true
    local attackerUuid = Osi.GetUUID(attackerGuid)
    local defenderUuid = Osi.GetUUID(defenderGuid)
    addBrawler(attackerUuid)
    addBrawler(defenderUuid)
    if Osi.IsPlayer(attackerUuid) == 1 then
        addNearbyToBrawlers(attackerUuid, NEARBY_RADIUS)
    end
    if Osi.IsPlayer(defenderUuid) == 1 then
        addNearbyToBrawlers(defenderUuid, NEARBY_RADIUS)
    end
    startBrawlFizzler(Osi.GetRegion(attackerUuid))
end

local function onDialogStarted(dialog, dialogInstanceId)
    debugPrint("DialogStarted", dialog, dialogInstanceId)
    local dialogStopped = false
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    -- if BrawlActive then
    --     local numberOfInvolvedPlayers = Osi.DialogGetNumberOFInvolvedPlayers(dialogInstanceId)
    --     local numberOfInvolvedNpcs = Osi.DialogGetNumberOfInvolvedNPCs(dialogInstanceId)
    --     if numberOfInvolvedNpcs == 1 then
    --         if getDisplayName(Osi.DialogGetInvolvedNPC(dialogInstanceId, 1)) == "Dream Visitor" then
    --             numberOfInvolvedNpcs = 0
    --         end
    --     end
    --     debugPrint("DialogStarted...", dialog, dialogInstanceId, numberOfInvolvedPlayers, numberOfInvolvedNpcs)
    --     if numberOfInvolvedPlayers == 2 and numberOfInvolvedNpcs == 0 then
    --         local involvedPlayers = {}
    --         local isPartyMembersOnly = true
    --         for i = 1, numberOfInvolvedPlayers do
    --             local involvedPlayer = Osi.DialogGetInvolvedPlayer(dialogInstanceId, i)
    --             if Players[involvedPlayer] == nil then
    --                 isPartyMembersOnly = false
    --                 break
    --             end
    --             table.insert(involvedPlayers, involvedPlayer)
    --         end
    --         if isPartyMembersOnly then
    --             debugPrint("Stopping dialog...", dialogInstanceId)
    --             debugDump(involvedPlayers)
    --             for _, player in ipairs(involvedPlayers) do
    --                 Osi.DialogRemoveActorFromDialog(dialogInstanceId, player)
    --                 Osi.DialogRequestStopForDialog(dialog, player)
    --             end
    --             dialogStopped = true
    --         end
    --     end
    -- end
    if not dialogStopped then
        BrawlActive = false
        stopPulseReposition(level)
        stopBrawlFizzler(level)
    end
end

local function onDialogEnded(dialog, dialogInstanceId)
    debugPrint("DialogEnded", dialog, dialogInstanceId)
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    startPulseReposition(level)
end

local function onDifficultyChanged(difficulty)
    debugPrint("DifficultyChanged", difficulty)
    setMovementSpeedThresholds()
end

-- thank u focus
local function onPROC_Subregion_Entered(characterGuid, _)
    debugPrint("PROC_Subregion_Entered", characterGuid)
    pulseReposition(Osi.GetRegion(characterGuid))
end

-- local function onCastedSpell(casterGuid, spell, spellType, spellSchool, id)
--     debugPrint("CastedSpell", casterGuid, spell, spellType, spellSchool, id)
-- end

local function onLevelUnloading(level)
    debugPrint("LevelUnloading", level)
    Brawlers[level] = nil
    PlayerCurrentTarget = nil
    stopPulseReposition(level)
end

function initBrawlers(level)
    debugPrint("initBrawlers", level)
    Brawlers[level] = {}
    for playerUuid, player in pairs(Players) do
        if Osi.IsInCombat(playerUuid) == 1 then
            onCombatStarted(Osi.CombatGetGuidFor(playerUuid))
            break
        end
    end
    startPulseReposition(level)
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
    -- Listeners.NetMessage = {}
    -- Listeners.NetMessage.handle = Ext.Events.NetMessage:Subscribe(onNetMessage)
    -- Listeners.NetMessage.stop = function () Ext.Events.NetMessage:Unsubscribe(Listeners.NetMessage.handle) end
    Listeners.UserReservedFor = {
        handle = Ext.Entity.Subscribe("UserReservedFor", onUserReservedFor),
        stop = Ext.Entity.Unsubscribe,
    }
    -- Listeners.CombatParticipant = {
    --     handle = Ext.Entity.Subscribe("CombatParticipant", onCombatParticipant),
    --     stop = Ext.Entity.Unsubscribe,
    -- }
    Listeners.LevelGameplayStarted = {
        handle = Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", onLevelGameplayStarted),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.CombatStarted = {
        handle = Ext.Osiris.RegisterListener("CombatStarted", 1, "after", onCombatStarted),
        stop = Ext.Osiris.UnregisterListener,
    }
    -- Listeners.CombatRoundStarted = {
    --     handle = Ext.Osiris.RegisterListener("CombatRoundStarted", 2, "after", onCombatRoundStarted),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
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
    Listeners.AttackedBy = {
        handle = Ext.Osiris.RegisterListener("AttackedBy", 7, "after", onAttackedBy),
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
    Listeners.PROC_Subregion_Entered = {
        handle = Ext.Osiris.RegisterListener("PROC_Subregion_Entered", 2, "after", onPROC_Subregion_Entered),
        stop = Ext.Osiris.UnregisterListener,
    }
    -- Listeners.CastedSpell = {
    --     handle = Ext.Osiris.RegisterListener("CastedSpell", 5, "after", onCastedSpell),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    Listeners.LevelUnloading = {
        handle = Ext.Osiris.RegisterListener("LevelUnloading", 1, "after", onLevelUnloading),
        stop = Ext.Osiris.UnregisterListener,
    }
end

local function onMCMSettingSaved(payload)
    _D(payload)
    if not payload or payload.modUUID ~= ModuleUUID or not payload.settingId then
        return
    end
    if payload.settingId == "mod_enabled" then
        ModEnabled = payload.value
        if ModEnabled then
            startListeners()
            local level = Osi.GetRegion(Osi.GetHostCharacter())
            if level then
                onStarted(level)
            end
        else
            stopListeners()
        end
    elseif payload.settingId == "companion_ai_enabled" then
        CompanionAIEnabled = payload.value
        if not CompanionAIEnabled then
            print("companion ai disabled, stopping pulse actions")
            for playerUuid, player in pairs(Players) do
                if Brawlers and Brawlers[playerUuid] then
                    Osi.PurgeOsirisQueue(playerUuid, 1)
                    Osi.FlushOsirisQueue(playerUuid)
                    stopPulseAction(Brawlers[playerUuid])
                end
            end
        end
    end
end

local function onGameStateChanged(e)
    if e and e.ToState == "UnloadLevel" then
        cleanupAll()
    end
end

local function onSessionLoaded()
    if ModEnabled then
        startListeners()
    else
        Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", resetPlayers)
    end
end

Ext.Events.SessionLoaded:Subscribe(onSessionLoaded)
Ext.Events.GameStateChanged:Subscribe(onGameStateChanged)
Ext.ModEvents.BG3MCM["MCM_Setting_Saved"]:Subscribe(onMCMSettingSaved)
