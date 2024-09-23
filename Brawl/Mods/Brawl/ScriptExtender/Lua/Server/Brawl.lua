local GameUtils = Require("Hlib/GameUtils")

Brawlers = {}
StopPulse = {}

local IsDialogActive = false
local ACTION_INTERVAL = 2000
local CAN_JOIN_COMBAT_INTERVAL = 10000
local ENTER_COMBAT_RANGE = 25
local DEBUG_LOGGING = true

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

-- todo: only set combat flag to false RIGHT WHEN combat starts, so it won't fuck w/ the campaign's flow too much

-- thank u hippo
local function flagCannotJoinCombat(entity)
    return entity.IsCharacter
        and GameUtils.Character.IsNonPlayer(entity.Uuid.EntityUuid)
        and not GameUtils.Object.IsOwned(entity.Uuid.EntityUuid)
        and not entity.PartyMember
        and not (entity.ServerCharacter and entity.ServerCharacter.Template.Name:match("Player"))
end

local function getPlayersSortedByDistance(entityUuid)
    local playerDistances = {}
    for _, player in pairs(Osi.DB_Players:Get(nil)) do
        local playerUuid = Osi.GetUUID(player[1])
        if Osi.IsDead(playerUuid) == 0 then
            table.insert(playerDistances, {playerUuid, Osi.GetDistanceTo(entityUuid, playerUuid)})
        end
    end
    table.sort(playerDistances, function (a, b) return a[2] > b[2] end)
    return playerDistances
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
local function actOnTarget(entityUuid, targetUuid)
    local entity = Ext.Entity.Get(entityUuid)
    local actionToTake = nil
    local archetype = Osi.GetActiveArchetype(entityUuid)
    -- local archetype = Osi.GetBaseArchetype(entityUuid)
    debugPrint("ServerAiArchetype", entityUuid, Osi.ResolveTranslatedString(Osi.GetDisplayName(entityUuid)), archetype)
    debugDump(entity.ServerAiArchetype)
    -- melee units should just autoattack sometimes
    if archetype == "melee" then
        local autoAttackRand = math.random()
        -- 50% chance to start autoattacking if they're not already
        if not Brawlers[Osi.GetRegion(entityUuid)][entityUuid].isAutoAttacking then
            if autoAttackRand < 0.5 then
                Brawlers[Osi.GetRegion(entityUuid)][entityUuid].isAutoAttacking = true
                debugPrint("Start autoattacking", entityUuid, targetUuid)
                return Osi.Attack(entityUuid, targetUuid, 0)
            end
        -- 20% chance to stop autoattacking if they're already doing it
        else
            if autoAttackRand > 0.2 then
                debugDump(Brawlers[Osi.GetRegion(entityUuid)][entityUuid])
                return Osi.Attack(entityUuid, targetUuid, 0)
            end
            Brawlers[Osi.GetRegion(entityUuid)][entityUuid].isAutoAttacking = false
        end
    end
    if entity.SpellBookPrepares ~= nil then
        local numUsableSpells = 0
        local usableSpells = {}
        for _, preparedSpell in pairs(entity.SpellBookPrepares.PreparedSpells) do
            if isSpellUsable(preparedSpell, archetype) then
                table.insert(usableSpells, preparedSpell)
                numUsableSpells = numUsableSpells + 1
            end
        end
        actionToTake = usableSpells[math.random(1, numUsableSpells)]
        debugPrint("Action to take:")
        debugDump(actionToTake)
    end
    if actionToTake == nil then
        return Osi.CharacterMoveTo(entityUuid, targetUuid, "Sprint", "event")
    end
    Osi.UseSpell(entityUuid, actionToTake.OriginatorPrototype, targetUuid)
end

local function pulseAction(level, isRepeating)
    debugPrint("pulseAction", level, isRepeating, IsDialogActive, StopPulse[level])
    if not StopPulse[level] then
        if not IsDialogActive then
            for entityUuid, brawler in pairs(Brawlers[level]) do
                if Osi.CanFight(entityUuid) == 1 then
                    if brawler.attackTarget ~= nil and Osi.IsDead(brawler.attackTarget) == 0 then
                        debugPrint("Already attacking", brawler.displayName, entityUuid, "->", Osi.ResolveTranslatedString(Osi.GetDisplayName(brawler.attackTarget)))
                        actOnTarget(entityUuid, brawler.attackTarget)
                    else
                        local closestAlivePlayer, closestDistance = Osi.GetClosestAlivePlayer(entityUuid)
                        debugPrint("Closest alive player to", brawler.entityUuid, brawler.displayName, "is", closestAlivePlayer, closestDistance)
                        if closestDistance < ENTER_COMBAT_RANGE then
                            local playersSortedByDistance = getPlayersSortedByDistance(entityUuid)
                            for _, pair in ipairs(playersSortedByDistance) do
                                local playerUuid, distance = pair[1], pair[2]
                                -- if Osi.CanSee(entityUuid, playerUuid) == 1 then
                                if Osi.IsInvisible(playerUuid) == 0 then -- also check for hidden?
                                    debugPrint("Attack", brawler.displayName, entityUuid, distance, "->", Osi.ResolveTranslatedString(Osi.GetDisplayName(playerUuid)))
                                    brawler.attackTarget = playerUuid
                                    actOnTarget(entityUuid, playerUuid)
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
        if isRepeating then
            -- Check for nearby unit actions every ACTION_INTERVAL ms
            Ext.Timer.WaitFor(ACTION_INTERVAL, function ()
                pulseAction(level, true)
            end)
        end
    end
end

local function pulseCanJoinCombat(level, isRepeating)
    debugPrint("pulseCanJoinCombat", level, isRepeating, IsDialogActive, StopPulse[level])
    if not StopPulse[level] then
        -- thank u hippo
        local nearbies = GameUtils.Entity.GetNearby(Osi.GetHostCharacter(), 50)
        local toFlagCannotJoinCombat = {}
        for _, nearby in ipairs(nearbies) do
            if flagCannotJoinCombat(nearby.Entity) then
                table.insert(toFlagCannotJoinCombat, nearby)
            end
        end
        for _, toFlag in pairs(toFlagCannotJoinCombat) do
            local entityUuid = toFlag.Guid
            if entityUuid ~= nil then
                -- thank u focus
                if Osi.CanJoinCombat(entityUuid) == 1 then
                    Osi.SetCanJoinCombat(entityUuid, 0)
                    debugPrint("Set CanJoinCombat to 0 for", entityUuid, Osi.ResolveTranslatedString(Osi.GetDisplayName(entityUuid)))
                end
                if Osi.CanFight(entityUuid) == 1 and Osi.IsDead(entityUuid) == 0 and Osi.IsEnemy(entityUuid, Osi.GetHostCharacter()) == 1 then
                    if not Brawlers[level][entityUuid] then
                        Brawlers[level][entityUuid] = {}
                    end
                    Brawlers[level][entityUuid].uuid = entityUuid
                    Brawlers[level][entityUuid].displayName = Osi.ResolveTranslatedString(Osi.GetDisplayName(entityUuid))
                    Brawlers[level][entityUuid].entity = Ext.Entity.Get(entityUuid)
                end
            end
        end
        if isRepeating then
            -- Check for units that need to be flagged every CAN_JOIN_COMBAT_INTERVAL ms
            Ext.Timer.WaitFor(CAN_JOIN_COMBAT_INTERVAL, function ()
                pulseCanJoinCombat(level, true)
            end)
        end
    end
end

local function startPulse(level, isRepeating)
    pulseCanJoinCombat(level, isRepeating)
    pulseAction(level, isRepeating)
end

Ext.Events.SessionLoaded:Subscribe(function ()
    Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", function (level, _)
        debugPrint("LevelGameplayStarted", level)
        Brawlers[level] = {}
        StopPulse[level] = false
        startPulse(level, true)
    end)
    Ext.Osiris.RegisterListener("Died", 1, "after", function (entityGuid)
        debugPrint("Died", entityGuid)
        Brawlers[Osi.GetRegion(entityGuid)][Osi.GetUUID(entityGuid)] = nil
        -- Sometimes units don't appear dead when killed out-of-combat...
        -- this at least makes them lie prone (and dead-appearing units still appear dead)
        Ext.Timer.WaitFor(1000, function ()
            Osi.LieOnGround(entityGuid)
        end)
    end)
    Ext.Osiris.RegisterListener("LevelUnloading", 1, "after", function (level)
        debugPrint("LevelUnloading", level)
        Brawlers[level] = nil
        StopPulse[level] = nil
    end)
    -- Ext.Osiris.RegisterListener("Teleported", 9, "after", function (target, cause, oldX, oldY, oldZ, newX, newY, newZ, spell)
    --     debugPrint("Teleported", target, cause, oldX, oldY, oldZ, newX, newY, newZ, spell)
    -- end)
    -- thank u focus
    Ext.Osiris.RegisterListener("PROC_Subregion_Entered", 2, "after", function (characterGuid, triggerGuid)
        debugPrint("PROC_Subregion_Entered", characterGuid, triggerGuid)
        StopPulse[Osi.GetRegion(Osi.GetHostCharacter())] = false
        startPulse(Osi.GetRegion(characterGuid), false)
    end)
    Ext.Osiris.RegisterListener("DialogStarted", 2, "before", function (dialog, instanceId)
        debugPrint("DialogStarted", dialog, instanceId)
        IsDialogActive = true
        StopPulse[Osi.GetRegion(Osi.GetHostCharacter())] = true
    end)
    Ext.Osiris.RegisterListener("DialogEnded", 2, "after", function (dialog, instanceId)
        debugPrint("DialogEnded", dialog, instanceId)
        IsDialogActive = false
        StopPulse[Osi.GetRegion(Osi.GetHostCharacter())] = false
        startPulse(Osi.GetRegion(Osi.GetHostCharacter()), false)
    end)
end)

Ext.Events.ResetCompleted:Subscribe(function ()
    print("ResetCompleted")
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    Brawlers[level] = {}
    StopPulse[level] = false
    startPulse(level, true)
end)