local GameUtils = Require("Hlib/GameUtils")

local Brawlers = {}
local ACTION_INTERVAL = 5000
local CAN_JOIN_COMBAT_INTERVAL = 10000
local DEBUG_LOGGING = true

local function debugPrint(...) if DEBUG_LOGGING then print(...) end end
local function debugDump(...) if DEBUG_LOGGING then _D(...) end end

-- thank u hippo
local function flagCannotJoinCombat(entity)
    return entity.IsCharacter
        and GameUtils.Character.IsNonPlayer(entity.Uuid.EntityUuid)
        and not GameUtils.Object.IsOwned(entity.Uuid.EntityUuid)
        and not entity.PartyMember
        and not (entity.ServerCharacter and entity.ServerCharacter.Template.Name:match("Player"))
end

local function pulseCanJoinCombat(level)
    -- thank u hippo
    local nearbies = GameUtils.Entity.GetNearby(Osi.GetHostCharacter(), 150)
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
                Brawlers[level][entityUuid].level = level
                Brawlers[level][entityUuid].displayName = Osi.ResolveTranslatedString(Osi.GetDisplayName(entityUuid))
                Brawlers[level][entityUuid].entity = Ext.Entity.Get(entityUuid)
                Brawlers[level][entityUuid].attackTarget = nil
            end
        end
    end
    -- Check for units that need to be flagged every CAN_JOIN_COMBAT_INTERVAL ms
    Ext.Timer.WaitFor(CAN_JOIN_COMBAT_INTERVAL, function () pulseCanJoinCombat(level) end)
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

local function pulseAction(level)
    for entityUuid, brawler in pairs(Brawlers[level]) do
        if Osi.CanFight(entityUuid) == 1 then
            if brawler.attackTarget ~= nil and Osi.IsDead(brawler.attackTarget) == 0 then
                debugPrint("Already attacking", brawler.displayName, entityUuid, "->", Osi.ResolveTranslatedString(Osi.GetDisplayName(brawler.attackTarget)))
                -- NB: create a better system than this lol
                local randomNumber = math.random()
                if randomNumber > 0.5 then -- attack the target
                    Osi.Attack(entityUuid, brawler.attackTarget, 0)
                elseif randomNumber > 0.25 then -- cast fireball at the target
                    Osi.UseSpell(entityUuid, "Projectile_Fireball", brawler.attackTarget)
                elseif randomNumber > 0.15 then -- cast ray of frost at the target
                    Osi.UseSpell(entityUuid, "Projectile_RayOfFrost", brawler.attackTarget)
                else -- run to the target and don't do anything else
                    Osi.CharacterMoveTo(entityUuid, brawler.attackTarget, "Run", "1")
                end
            else
                local closestAlivePlayer, closestDistance = Osi.GetClosestAlivePlayer(entityUuid)
                -- debugPrint("Closest alive player to", brawler.entityUuid, brawler.displayName, "is", closestAlivePlayer, closestDistance)
                -- local enterCombatRange = Osi.GetEnterCombatRange()
                local enterCombatRange = 20
                if closestDistance < enterCombatRange then
                    local playersSortedByDistance = getPlayersSortedByDistance(entityUuid)
                    for _, pair in ipairs(playersSortedByDistance) do
                        local playerUuid, distance = pair[1], pair[2]
                        -- print("getPlayersSortedByDistance iterate", entityUuid, playerUuid, distance, Osi.HasLineOfSight(entityUuid, playerUuid), Osi.CanSee(entityUuid, playerUuid))
                        if Osi.HasLineOfSight(entityUuid, playerUuid) == 1 and Osi.CanSee(entityUuid, playerUuid) == 1 then
                            debugPrint("Attack", brawler.displayName, entityUuid, distance, "->", Osi.ResolveTranslatedString(Osi.GetDisplayName(playerUuid)))
                            brawler.attackTarget = playerUuid
                            -- NB: create a better system than this lol
                            local randomNumber = math.random()
                            if randomNumber > 0.5 then -- attack the target
                                Osi.Attack(entityUuid, playerUuid, 0)
                            elseif randomNumber > 0.25 then -- cast fireball at the target
                                Osi.UseSpell(entityUuid, "Projectile_Fireball", playerUuid)
                            else -- cast ray of frost at the target
                                Osi.UseSpell(entityUuid, "Projectile_RayOfFrost", brawler.attackTarget)
                            end
                            break
                        end
                    end
                end
            end
        end
    end
    -- Check for nearby unit actions every ACTION_INTERVAL ms
    Ext.Timer.WaitFor(ACTION_INTERVAL, function () pulseAction(level) end)
end

Ext.Events.SessionLoaded:Subscribe(function ()
    Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", function (level, _)
        debugPrint("LevelGameplayStarted", level)
        Brawlers[level] = {}
        pulseCanJoinCombat(level)
        pulseAction(level)
    end)
    Ext.Osiris.RegisterListener("Died", 1, "after", function (entityGuid)
        debugPrint("Died", entityGuid)
        Brawlers[Osi.GetRegion(entityGuid)][Osi.GetUUID(entityGuid)] = nil
    end)
    Ext.Osiris.RegisterListener("LevelUnloading", 1, "after", function (level)
        debugPrint("LevelUnloading", level)
        Brawlers[level] = nil
    end)
end)

Ext.Events.ResetCompleted:Subscribe(function ()
    print("ResetCompleted")
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    Brawlers[level] = {}
    pulseCanJoinCombat(level)
    pulseAction(level)
end)
