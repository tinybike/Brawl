local GameUtils = Require("Hlib/GameUtils")

local Brawlers = {}
local ACTION_INTERVAL = 3000
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
            debugPrint("display name", entityUuid, Osi.ResolveTranslatedString(Osi.GetDisplayName(entityUuid)))
            -- thank u focus
            if Osi.CanJoinCombat(entityUuid) == 1 then
                Osi.SetCanJoinCombat(entityUuid, 0)
            end
            if Osi.CanFight(entityUuid) == 1 then
                if not Brawlers[level][entityUuid] then
                    Brawlers[level][entityUuid] = {}
                end
                Brawlers[level][entityUuid].uuid = entityUuid
                Brawlers[level][entityUuid].level = level
                Brawlers[level][entityUuid].displayName = Osi.ResolveTranslatedString(Osi.GetDisplayName(entityUuid))
                Brawlers[level][entityUuid].entity = Ext.Entity.Get(entityUuid)
            end
        end
    end
    -- Check for units that need to be flagged every CAN_JOIN_COMBAT_INTERVAL ms
    Ext.Timer.WaitFor(CAN_JOIN_COMBAT_INTERVAL, function () pulseCanJoinCombat(level) end)
end

local function pulseAction(level)
    for entityUuid, brawler in pairs(Brawlers[level]) do
        if Osi.CanFight(entityUuid) == 1 then
            local closestAlivePlayer, distance = Osi.GetClosestAlivePlayer(entityUuid)
            debugPrint("Closest alive player to", brawler.entityUuid, brawler.displayName, "is", closestAlivePlayer, distance)
            brawler.closestAlivePlayer = closestAlivePlayer
            brawler.distance = distance
            -- local enterCombatRange = Osi.GetEnterCombatRange()
            local enterCombatRange = 20
            if distance < enterCombatRange then
                debugPrint("Attack", entityUuid, closestAlivePlayer)
                Osi.Attack(entityUuid, closestAlivePlayer, 0)
                --Osi.UseSpell(entityUuid, spellID, target, target2)
            -- elseif distance > enterCombatRange*3 then
            --     debugPrint("stop attacking")
            --     --do this somehow /thinking emoji
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
