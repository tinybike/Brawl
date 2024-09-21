local GameUtils = Require("Hlib/GameUtils")

local Brawlers = {}
local DEBUG_LOGGING = true

local function debugPrint(...) if DEBUG_LOGGING then print(...) end end
local function debugDump(...) if DEBUG_LOGGING then _D(...) end end

local function heartbeat(level)
    --thank u hippo
    local nearby = GameUtils.Entity.GetNearby(Osi.GetHostCharacter(), 150)
    local toFlagCannotJoinCombat = table.filter(nearby, function (v)
        return v.Entity.IsCharacter
            and GameUtils.Character.IsNonPlayer(v.Entity.Uuid.EntityUuid)
            and not GameUtils.Object.IsOwned(v.Entity.Uuid.EntityUuid)
            and not v.Entity.PartyMember
            and not (v.Entity.ServerCharacter and v.Entity.ServerCharacter.Template.Name:match("Player"))
    end)
    for _, toFlag in pairs(toFlagCannotJoinCombat) do
        local entityUuid = toFlag.Guid
        if entityUuid ~= nil then
            debugPrint("display name", Osi.ResolveTranslatedString(Osi.GetDisplayName(entityUuid)))
            local entity = Ext.Entity.Get(entityUuid)
            --thank u focus
            if Osi.CanJoinCombat(entityUuid) == 1 then
                Osi.SetCanJoinCombat(entityUuid, 0)
                entity:Replicate("CombatParticipant")
            end
            if Osi.CanFight(entityUuid) == 1 then
                local closestAlivePlayer, distance = Osi.GetClosestAlivePlayer(entityUuid)
                debugPrint("closest alive player", closestAlivePlayer, distance)
                Brawlers[level][entityUuid] = {
                    uuid=entityUuid,
                    level=level,
                    displayName=Osi.ResolveTranslatedString(Osi.GetDisplayName(entityUuid)),
                    entity=entity,
                    closestAlivePlayer=closestAlivePlayer,
                    distance=distance
                }
                -- local enterCombatRange = Osi.GetEnterCombatRange()
                local enterCombatRange = 15
                if distance < enterCombatRange then
                    debugPrint("attack!")
                    Osi.Attack(entityUuid, closestAlivePlayer, 0)
                    --Osi.UseSpell(entityUuid, spellID, target, target2)
                elseif distance > enterCombatRange*3 then
                    debugPrint("stop attacking")
                    --do this somehow /thinking emoji
                end
            end
        end
    end
    Ext.Timer.WaitFor(2000, function ()
        heartbeat(level)
    end)
end

Ext.Events.SessionLoaded:Subscribe(function ()
    Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", function (level, _)
        debugPrint("LevelGameplayStarted", level)
        Brawlers[level] = {}
        heartbeat(level)
    end)
    Ext.Osiris.RegisterListener("LevelUnloading", 1, "after", function (level)
        debugPrint("LevelUnloading", level)
        Brawlers[level] = nil
    end)
end)
