Brawlers = {}
Players = {}
StopPulseReposition = {}
StopPulseAction = {}
PlayerCurrentTarget = nil
BrawlActive = false

local ACTION_INTERVAL = 6000
local REPOSITION_INTERVAL = 2500
local ENTER_COMBAT_RANGE = 20
local MELEE_RANGE = 1.5
local RANGED_RANGE_MAX = 25
local RANGED_RANGE_SWEETSPOT = 10
local RANGED_RANGE_MIN = 5
local MOVEMENT_DISTANCE_UUID = "d6b2369d-84f0-4ca4-a3a7-62d2d192a185"
local LOOPING_COMBAT_ANIMATION_ID = "7bb52cd4-0b1c-4926-9165-fa92b75876a3" -- this should be a whole hash table...
local DEBUG_LOGGING = true

local USABLE_COMPANION_SPELLS = {
    Shout_BladeWard = true,
    Target_MainHandAttack = true,
    Target_OffhandAttack = true,
    Target_Topple = true,
    Target_UnarmedAttack = true,
    Target_AdvancedMeleeWeaponAction = true,
    -- Target_Counterspell = true,
    Target_CripplingStrike = true,
    Target_CuttingWords = true,
    Target_DisarmingAttack = true,
    Target_DisarmingStrike = true,
    Target_Flurry = true,
    Target_LungingAttack = true,
    Target_OpeningAttack = true,
    Target_PiercingThrust = true,
    Target_PommelStrike = true,
    Target_PushingAttack = true,
    Target_RecklessAttack = true,
    -- Target_Riposte = true,
    Target_SacredFlame = true,
    Target_ShockingGrasp = true,
    -- Target_Shove = true,
    Target_Slash = true,
    Target_Smash = true,
    Target_ThornWhip = true,
    Target_TripAttack = true,
    Target_TrueStrike = true,
    Target_ViciousMockery = true,
    Target_FlurryOfBlows = true,
    Target_StunningStrike = true,
    Rush_Rush = true,
    Rush_WEAPON_ACTION_RUSH = true,
    Rush_Aggressive = true,
    Rush_ForceTunnel = true,
}

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

local function getCurrentHp(entityUuid)
    local entity = Ext.Entity.Get(entityUuid)
    if entity and entity.Health and entity.Health.Hp ~= nil then
        return entity.Health.Hp
    end
    return 0
end

local function isAliveAndCanFight(entityUuid)
    return Osi.IsDead(entityUuid) == 0 and Osi.CanFight(entityUuid) == 1 and getCurrentHp(entityUuid) > 0
end

local function isPlayerOrAlly(entityUuid)
    return Osi.IsPlayer(entityUuid) == 1 or Osi.IsAlly(Osi.GetHostCharacter(), entityUuid) == 1
end

local function isPugnacious(entityUuid)
    return Osi.IsEnemy(Osi.GetHostCharacter(), entityUuid) == 1
end

-- NB: tune this...
local function convertMovementDistanceToSpeed(movementDistance)
    if movementDistance > 12 then
        return "Sprint"
    elseif movementDistance > 8 then
        return "Run"
    elseif movementDistance > 5 then
        return "Walk"
    else
        return "Stroll"
    end
end

local function getMovementSpeed(entityUuid)
    -- local statuses = Ext.Entity.Get(entityUuid).StatusContainer.Statuses
    local entity = Ext.Entity.Get(entityUuid)
    local movementDistance = entity.ActionResources.Resources[MOVEMENT_DISTANCE_UUID][1].Amount
    local movementSpeed = convertMovementDistanceToSpeed(movementDistance)
    debugPrint("getMovementSpeed", entityUuid, movementDistance, movementSpeed)
    return movementSpeed
end

-- Example monk looping animations (can these be interruptable?)
-- from https://bg3.norbyte.dev/search?iid=Resource.6b05dbcc-19ef-475f-62a2-d18c1e640aa7
-- animMK = "e85be5a8-6e48-4da4-8486-0d168159df4e"
-- animMK = "7bb52cd4-0b1c-4926-9165-fa92b75876a3"
-- Osi.PlayAnimation(uuid, animMK, "")
-- Osi.PlayLoopingAnimation(uuid, animMK, animMK, animMK, animMK, animMK, animMK, animMK)
local function holdPosition(entityUuid)
    if not isPlayerOrAlly(entityUuid) then
        Osi.PlayAnimation(entityUuid, LOOPING_COMBAT_ANIMATION_ID, "")
    end
end

local function getPlayersSortedByDistance(entityUuid)
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

local function isCompanionSpellUsable(spell)
    return USABLE_COMPANION_SPELLS[spell.OriginatorPrototype]
end

local function isSpellUsable(spell, archetype)
    if spell.OriginatorPrototype == "Projectile_Jump" then return false end
    if spell.OriginatorPrototype == "Shout_Dash_NPC" then return false end
    if spell.OriginatorPrototype == "Target_Shove" then return false end
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

-- NB: create a better system than this lol
local function actOnTarget(brawler, targetUuid)
    local brawlerEntity = Ext.Entity.Get(brawler.uuid)
    local actionToTake = nil
    local archetype = Osi.GetActiveArchetype(brawler.uuid)
    -- debugPrint("ServerAiArchetype", brawler.uuid, Osi.ResolveTranslatedString(Osi.GetDisplayName(brawler.uuid)), archetype)
    -- debugDump(brawlerEntity.ServerAiArchetype)
    -- melee units should just autoattack sometimes
    if archetype == "melee" then
        local autoAttackRand = math.random()
        -- 50% chance to start autoattacking if they're not already
        if not brawler.isAutoAttacking then
            if autoAttackRand < 0.5 then
                brawler.isAutoAttacking = true
                debugPrint("Start autoattacking", brawler.uuid, targetUuid)
                return Osi.Attack(brawler.uuid, targetUuid, 0)
            end
        -- 20% chance to stop autoattacking if they're already doing it
        else
            if autoAttackRand > 0.2 then
                debugDump(brawler)
                return Osi.Attack(brawler.uuid, targetUuid, 0)
            end
            brawler.isAutoAttacking = false
        end
    end
    if brawlerEntity.SpellBookPrepares ~= nil then
        -- if they're already in melee range, they should do melee stuff
        local numUsableSpells = 0
        local usableSpells = {}
        for _, preparedSpell in pairs(brawlerEntity.SpellBookPrepares.PreparedSpells) do
            -- NB: Figure out if we want to track spell slots or just do weighted RNG or...?
            -- local spellStats = Ext.Stats.Get(preparedSpell.OriginatorPrototype)
            -- local targetRadius = tonumber(spellStats.TargetRadius)
            -- if targetRadius ~= nil then
            -- -- nb: targetRadius is a string, either a stringified number or an actual descriptive string :/
            -- end
            -- spellStats.TargetRadius == "MeleeMainWeaponRange"
            -- -- random examples: Projectile_RayOfFrost, Projectile_Fireball, Target_CHA_FogCloud_Skeleton, Target_CHA_Silence_Skeleton
            -- local useCosts = spellStats.UseCosts
            -- Just randomize for now... :(
            -- Keep it basic for the companions for now...
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
        debugPrint("Action to take:")
        debugDump(actionToTake)
    end
    if actionToTake == nil then
        return Osi.Attack(brawler.uuid, targetUuid, 0)
    end
    Osi.UseSpell(brawler.uuid, actionToTake.OriginatorPrototype, targetUuid)
end

local function getBrawlersSortedByDistance(entityUuid)
    local brawlersSortedByDistance = {}
    local level = Osi.GetRegion(entityUuid)
    for brawlerUuid, brawler in pairs(Brawlers[level]) do
        if isAliveAndCanFight(brawlerUuid) then
            debugPrint("distance:", brawlerUuid, Osi.GetDistanceTo(entityUuid, brawlerUuid))
            table.insert(brawlersSortedByDistance, {brawlerUuid, Osi.GetDistanceTo(entityUuid, brawlerUuid)})
        end
    end
    table.sort(brawlersSortedByDistance, function (a, b) return a[2] < b[2] end)
    return brawlersSortedByDistance
end

local function findTargetToAttack(brawler)
    for _, target in ipairs(getBrawlersSortedByDistance(brawler.uuid)) do
        local targetUuid, distanceToTarget = target[1], target[2]
        if Osi.IsEnemy(brawler.uuid, targetUuid) == 1 and Osi.IsInvisible(targetUuid) == 0 and isAliveAndCanFight(targetUuid) then
            debugPrint("Attack", brawler.displayName, brawler.uuid, distanceToTarget, "->", Osi.ResolveTranslatedString(Osi.GetDisplayName(targetUuid)))
            brawler.targetUuid = targetUuid
            return actOnTarget(brawler, targetUuid)
        end
    end
    holdPosition(brawler.uuid)
end

-- Brawlers doing dangerous stuff
local function pulseAction(brawler)
    if not StopPulseAction[brawler.uuid] then
        -- Brawler is alive and able to fight: let's go!
        if isAliveAndCanFight(brawler.uuid) then
            -- Doesn't currently have an attack target, so let's find one
            if brawler.targetUuid == nil then
                findTargetToAttack(brawler)
            else
                -- Already attacking a target and the target isn't dead, so just keep at it
                if isAliveAndCanFight(brawler.targetUuid) then
                    debugPrint("Already attacking", brawler.displayName, brawler.uuid, "->", Osi.ResolveTranslatedString(Osi.GetDisplayName(brawler.targetUuid)))
                    actOnTarget(brawler, brawler.targetUuid)
                -- Has an attack target but it's already dead or unable to fight, so find a new one
                else
                    brawler.targetUuid = nil
                    findTargetToAttack(brawler)
                end
            end
        -- If this brawler is dead or unable to fight, stop this pulse
        else
            brawler.isInBrawl = false
            StopPulseAction[brawler.uuid] = true
        end
        -- Check for actions every ACTION_INTERVAL ms
        Ext.Timer.WaitFor(ACTION_INTERVAL, function ()
            pulseAction(brawler)
        end)
    end
end

local function moveIntoRangedSweetSpot(brawlerUuid, targetUuid, distance)
    local xEntity, yEntity, zEntity = Osi.GetPosition(brawlerUuid)
    local xTarget, yTarget, zTarget = Osi.GetPosition(targetUuid)
    debugPrint("Ranged/caster unit wrong distance from target", distance, xTarget, yTarget, zTarget)
    local ux = (xEntity - xTarget)/distance
    local uy = (yEntity - yTarget)/distance
    local uz = (zEntity - zTarget)/distance
    local xNew = xTarget + ux*RANGED_RANGE_SWEETSPOT
    local yNew = yTarget + uy*RANGED_RANGE_SWEETSPOT
    local zNew = zTarget + uz*RANGED_RANGE_SWEETSPOT
    debugPrint("Moving into the sweet spot", brawlerUuid, xNew, yNew, zNew)
    Osi.CharacterMoveToPosition(brawlerUuid, xNew, yNew, zNew, getMovementSpeed(brawlerUuid), "")
end

-- NB: This should never be the first thing that happens (brawl should always kick off with an action)
local function repositionRelativeToTarget(brawlerUuid, targetUuid)
    local archetype = Osi.GetActiveArchetype(brawlerUuid)
    local distanceToTarget = Osi.GetDistanceTo(brawlerUuid, targetUuid)
    if archetype == "melee" then
        if distanceToTarget > MELEE_RANGE then
            Osi.CharacterMoveTo(brawlerUuid, targetUuid, getMovementSpeed(brawlerUuid), "")
        else
            holdPosition(brawlerUuid)
        end
    else
        if distanceToTarget <= MELEE_RANGE then
            holdPosition(brawlerUuid)
        elseif distanceToTarget < RANGED_RANGE_MIN then
            moveIntoRangedSweetSpot(brawlerUuid, targetUuid, distanceToTarget)
        elseif distanceToTarget < RANGED_RANGE_MAX then
            holdPosition(brawlerUuid)
        else
            moveIntoRangedSweetSpot(brawlerUuid, targetUuid, distanceToTarget)
        end
    end
end

-- Enemies are pugnacious jerks and looking for a fight >:(
local function checkForBrawlToJoin(brawler)
    local closestAlivePlayer, closestDistance = Osi.GetClosestAlivePlayer(brawler.uuid)
    -- debugPrint("Closest alive player to", brawler.uuid, brawler.displayName, "is", closestAlivePlayer, closestDistance)
    if closestDistance < ENTER_COMBAT_RANGE then
        for _, target in ipairs(getBrawlersSortedByDistance(brawler.uuid)) do
            local targetUuid, distance = target[1], target[2]
            -- NB: also check for farther-away units where there's a nearby brawl happening already? hidden? line-of-sight?
            if Osi.IsEnemy(brawler.uuid, targetUuid) == 1 and Osi.IsInvisible(targetUuid) == 0 and distance < ENTER_COMBAT_RANGE then
                -- debugPrint("Reposition", brawler.displayName, brawler.uuid, distance, "->", Osi.ResolveTranslatedString(Osi.GetDisplayName(targetUuid)))
                brawler.isInBrawl = true
                StopPulseAction[brawler.uuid] = false
                return pulseAction(brawler, true)
            end
        end
    end
end

local function isBrawlingWithValidTarget(brawler)
    return brawler.isInBrawl and brawler.targetUuid ~= nil and isAliveAndCanFight(brawler.targetUuid)
end

-- Reposition the NPC relative to the player.  This is the only place that NPCs should enter the brawl!
local function pulseReposition(level, isRepeating)
    if not StopPulseReposition[level] and Brawlers[level] then
        for brawlerUuid, brawler in pairs(Brawlers[level]) do
            if isAliveAndCanFight(brawlerUuid) then
                -- Enemy units are actively looking for a fight and will attack if you get too close to them
                if isPugnacious(brawlerUuid) then
                    if brawler.isInBrawl and brawler.targetUuid ~= nil and isAliveAndCanFight(brawler.targetUuid) then
                        -- debugPrint(brawler.displayName, brawlerUuid, "->", Osi.ResolveTranslatedString(Osi.GetDisplayName(brawler.targetUuid)))
                        repositionRelativeToTarget(brawlerUuid, brawler.targetUuid)
                    else
                        checkForBrawlToJoin(brawler)
                    end
                -- Player, ally, and neutral units are not actively looking for a fight
                -- Companions and allies use the same logic
                -- (Neutrals do nothing I guess...?)
                elseif BrawlActive and isPlayerOrAlly(brawlerUuid) and not StopPulseAction[brawlerUuid] then
                    if not Players[brawlerUuid] then
                        debugPrint("Late addition to the team (who is this?)", brawlerUuid)
                        Players[brawlerUuid] = {
                            uuid = uuid,
                            isControllingDirectly = false,
                            isInBrawl = false,
                        }
                    end
                    local partyMember = Players[brawlerUuid]
                    if partyMember.isControllingDirectly then
                        brawler.isInBrawl = false
                        StopPulseAction[brawlerUuid] = true
                    else
                        StopPulseAction[brawlerUuid] = false
                        if not brawler.isInBrawl then
                            brawler.isInBrawl = true
                            pulseAction(brawler)
                        elseif isBrawlingWithValidTarget(brawler) and Osi.IsPlayer(brawlerUuid) == 1 then
                            debugPrint("Reposition party member", brawlerUuid)
                            repositionRelativeToTarget(brawlerUuid, brawler.targetUuid)
                        end
                    end
                end
            end
        end
    end
    if isRepeating then
        -- Reposition if needed every REPOSITION_INTERVAL ms
        Ext.Timer.WaitFor(REPOSITION_INTERVAL, function ()
            pulseReposition(level, true)
        end)
    end
end

local function onStarted(level)
    for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
        local uuid = Osi.GetUUID(player[1])
        -- NB: should this always be GetHostCharacter?
        Players[uuid] = {
            uuid = uuid,
            isControllingDirectly = uuid == Osi.GetHostCharacter(),
        }
    end
    Brawlers[level] = {}
    StopPulseReposition[level] = false
    PlayerCurrentTarget = nil
    pulseReposition(level, true)
end

Ext.Events.SessionLoaded:Subscribe(function ()

    -- NB: limit this by distance or smth? lots of units in the main regions...
    Ext.Entity.Subscribe("CombatParticipant", function (entity, _, _)
        local entityUuid = entity.Uuid.EntityUuid
        -- debugPrint("CombatParticipant", entityUuid)
        if entityUuid ~= nil then
            local level = Osi.GetRegion(Osi.GetHostCharacter())
            if Brawlers[level] ~= nil and Brawlers[level][entityUuid] == nil then
                local combatGuid = Osi.CombatGetGuidFor(entityUuid)
                local displayName = Osi.ResolveTranslatedString(Osi.GetDisplayName(entityUuid))
                -- if Osi.IsDead(entityUuid) == 0 and Osi.IsEnemy(entityUuid, Osi.GetHostCharacter()) == 1 then
                if Osi.IsDead(entityUuid) == 0 then
                    debugPrint("Adding Brawler", entityUuid, displayName)
                    Brawlers[level][entityUuid] = {
                        uuid = entityUuid,
                        displayName = displayName,
                        entity = entity,
                        combatGuid = combatGuid,
                        isInBrawl = false,
                        originalCanJoinCombat = Osi.CanJoinCombat(entityUuid),
                    }
                    -- Remove the CanJoinCombat flag from all non-player units (even allies)
                    if Osi.IsPlayer(entityUuid) == 0 then
                        Osi.SetCanJoinCombat(entityUuid, 0)
                    end
                end
            end
        end
    end)

    Ext.Osiris.RegisterListener("CombatStarted", 1, "after", function (combatGuid)
        BrawlActive = true
        Ext.Timer.WaitFor(2000, function ()
            Osi.EndCombat(combatGuid)
        end)
    end)

    Ext.Osiris.RegisterListener("EnteredCombat", 2, "after", function (entityGuid, _)
        local entityUuid = Osi.GetUUID(entityGuid)
        if entityUuid ~= nil and Osi.IsPlayer(entityUuid) == 1 then
            local entity = Ext.Entity.Get(entityUuid)
            if not Players[entityUuid] then
                Players[entityUuid] = {
                    uuid = entityUuid,
                    isControllingDirectly = uuid == Osi.GetHostCharacter(),
                }
            end
            Players[entityUuid].movementSpeedRun = entity.ServerCharacter.Template.MovementSpeedRun
            entity.ServerCharacter.Template.MovementSpeedRun = entity.ServerCharacter.Template.MovementSpeedSprint
        end
    end)

    Ext.Osiris.RegisterListener("Died", 1, "after", function (entityGuid)
        debugPrint("Died", entityGuid)
        local level = Osi.GetRegion(entityGuid)
        local entityUuid = Osi.GetUUID(entityGuid)
        local combatGuid = nil
        if Brawlers[level] ~= nil then
            if Brawlers[level][entityUuid] ~= nil then
                combatGuid = Brawlers[level][entityUuid].combatGuid
                Osi.SetCanJoinCombat(entityUuid, Brawlers[level][entityUuid].originalCanJoinCombat)
            end
            Brawlers[level][entityUuid] = nil
            local numBrawlersRemaining = 0
            for _ in pairs(Brawlers[level]) do
                numBrawlersRemaining = numBrawlersRemaining + 1
            end
            debugPrint("Number of brawlers remaining:", numBrawlersRemaining)
            debugDump(Brawlers)
            if combatGuid ~= nil and numBrawlersRemaining == 0 then
                for playerUuid, player in pairs(Players) do
                    local entity = Ext.Entity.Get(playerUuid)
                    if player.movementSpeedRun ~= nil then
                        entity.ServerCharacter.Template.MovementSpeedRun = player.movementSpeedRun
                    end
                    PlayerCurrentTarget = nil
                    BrawlActive = false
                end
            end
            -- Sometimes units don't appear dead when killed out-of-combat...
            -- this at least makes them lie prone (and dead-appearing units still appear dead)
            Ext.Timer.WaitFor(1200, function ()
                Osi.LieOnGround(entityGuid)
            end)
        end
    end)

    Ext.Osiris.RegisterListener("GainedControl", 1, "after", function (targetGuid)
        debugPrint("GainedControl", targetGuid)
        local targetUuid = Osi.GetUUID(targetGuid)
        for playerUuid, player in pairs(Players) do
            player.isControllingDirectly = playerUuid == targetUuid
        end
    end)

    Ext.Osiris.RegisterListener("AttackedBy", 7, "after", function (defenderGuid, attackerGuid, attacker2Guid, damageType, damageAmount, damageCause, storyActionID)
        local level = Osi.GetRegion(Osi.GetHostCharacter())
        local defenderUuid = Osi.GetUUID(defenderGuid)
        local attackerUuid = Osi.GetUUID(attackerGuid)
        if Osi.IsPlayer(attackerUuid) == 1 then
            PlayerCurrentTarget = defenderUuid
        end
    end)

    Ext.Osiris.RegisterListener("DialogStarted", 2, "before", function (dialog, dialogInstanceId)
        debugPrint("DialogStarted", dialog, dialogInstanceId)
        StopPulseReposition[Osi.GetRegion(Osi.GetHostCharacter())] = true
        PlayerCurrentTarget = nil
        -- local numberOfInvolvedNpcs = Osi.DialogGetNumberOfInvolvedNPCs(dialogInstanceId)
        -- for i = 1, numberOfInvolvedNpcs do
        --     local involvedNpcUuid = Osi.DialogGetInvolvedNPC(dialogInstanceId, i)
        --     debugPrint("involvedNpcUuid", involvedNpcUuid, Osi.ResolveTranslatedString(Osi.GetDisplayName(involvedNpcUuid)), Osi.CanJoinCombat(involvedNpcUuid))
        -- end
    end)

    Ext.Osiris.RegisterListener("DialogEnded", 2, "after", function (dialog, dialogInstanceId)
        debugPrint("DialogEnded", dialog, dialogInstanceId)
        local level = Osi.GetRegion(Osi.GetHostCharacter())
        StopPulseReposition[level] = false
        PlayerCurrentTarget = nil
        pulseReposition(level, false)
    end)

    -- thank u focus
    Ext.Osiris.RegisterListener("PROC_Subregion_Entered", 2, "after", function (characterGuid, _)
        debugPrint("PROC_Subregion_Entered", characterGuid)
        local level = Osi.GetRegion(characterGuid)
        StopPulseReposition[level] = false
        PlayerCurrentTarget = nil
        pulseReposition(level, false)
    end)

    Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", function (level, _)
        debugPrint("LevelGameplayStarted", level)
        onStarted(level)
    end)

    Ext.Osiris.RegisterListener("LevelUnloading", 1, "after", function (level)
        debugPrint("LevelUnloading", level)
        Brawlers[level] = nil
        StopPulseReposition[level] = nil
        PlayerCurrentTarget = nil
    end)
end)

Ext.Events.ResetCompleted:Subscribe(function ()
    print("ResetCompleted")
    onStarted(Osi.GetRegion(Osi.GetHostCharacter()))
end)
