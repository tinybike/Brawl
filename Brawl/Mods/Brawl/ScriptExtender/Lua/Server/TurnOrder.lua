local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump

local function setPlayersSwarmGroup(swarmGroupLabel)
    if State.Session.Players then
        for uuid, _ in pairs(State.Session.Players) do
            Osi.RequestSetSwarmGroup(uuid, swarmGroupLabel or "PLAYER_SWARM_GROUP")
        end
    end
end

local function showAllInitiativeRolls()
    print("***********Initiative rolls************")
    for uuid, _ in pairs(M.Roster.getBrawlers()) do
        print(M.Utils.getDisplayName(uuid), Swarm.getInitiativeRoll(uuid))
    end
    print("***************************************")
end

local function showTurnOrderGroups()
    local combatEntity = getCombatEntity()
    if combatEntity and combatEntity.TurnOrder and combatEntity.TurnOrder.Groups then
        for i, group in ipairs(combatEntity.TurnOrder.Groups) do
            if group.Members and group.Initiative ~= -20 then
                local groupStr = ""
                groupStr = groupStr .. tostring(i) .. " " .. tostring(group.Initiative)
                if #group.Members then
                    for j, member in ipairs(group.Members) do
                        if member.Entity and member.Entity.Uuid and member.Entity.Uuid.EntityUuid then
                            if j > 1 then
                                groupStr = groupStr .. " +"
                            end
                            groupStr = groupStr .. " " .. M.Utils.getDisplayName(member.Entity.Uuid.EntityUuid)
                        end
                    end
                end
                if not group.IsPlayer then
                    -- thank u hippo
                    groupStr = string.format("\x1b[38;2;%d;%d;%dm%s\x1b[0m", 110, 150, 90, groupStr)
                end
                print(groupStr)
            end
        end
    end
end

local function getCurrentCombatRound()
    local combatEntity = getCombatEntity()
    if combatEntity and combatEntity.TurnOrder and combatEntity.TurnOrder.field_40 then
        return combatEntity.TurnOrder.field_40
    end
end

-- thank u hippo
local function spawnCombatHelper(combatGuid, isRefreshOnly)
    if not State.Session.CombatHelper or isRefreshOnly then
        local playerUuid = Osi.CombatGetInvolvedPlayer(combatGuid, 1) or M.Osi.GetHostCharacter()
        local x, y, z = Osi.GetPosition(playerUuid)
        local combatHelper = Osi.CreateAt(Constants.COMBAT_HELPER.templateId, x, y, z, 0, 1, "")
        if not combatHelper then
            error("couldn't create combat helper")
            return
        end
        Osi.SetTag(combatHelper, "9787450d-f34d-43bd-be88-d2bac00bb8ee") -- AI_UNPREFERRED_TARGET
        Osi.SetFaction(combatHelper, Constants.COMBAT_HELPER.faction)
        if not isRefreshOnly then
            State.Session.CombatHelper = combatHelper
        end
        Ext.Loca.UpdateTranslatedString(Constants.COMBAT_HELPER.handle, "Combat Helper")
        Osi.SetHostileAndEnterCombat(Constants.COMBAT_HELPER.faction, Osi.GetFaction(playerUuid), combatHelper, playerUuid)
        return combatHelper
    end
end

-- NB: this makes an absolute mess of combatEntity.TurnOrder.Groups, but it seems to work as intended
local function setPlayerTurnsActive()
    print("set player turns active")
    local combatEntity = Utils.getCombatEntity()
    if combatEntity and combatEntity.TurnOrder and combatEntity.TurnOrder.Groups then
        print("********init***********")
        showTurnOrderGroups()
        local groupsPlayers = {}
        local groupsEnemies = {}
        for _, group in ipairs(combatEntity.TurnOrder.Groups) do
            if group.IsPlayer then
                -- if a player is assigned 2+ characters, re-order them in the topbar so that the currently controlled one is first,
                -- so the re-selection on round start doesn't jerk the screen around
                -- (then reorder every time GainedControl happens)
                -- split into single-member groups
                for _, member in ipairs(group.Members) do
                    if member.Entity and member.Entity and member.Entity.Uuid and member.Entity.Uuid.EntityUuid and State.isPlayerControllingDirectly(member.Entity.Uuid.EntityUuid) then
                        -- NB: don't just add 1000, do this in a smarter way
                        newInitiative = member.Initiative + 1000
                        Swarm.setInitiativeRoll(member.Entity.Uuid.EntityUuid, newInitiative)
                        table.insert(groupsPlayers, {
                            Initiative = newInitiative,
                            IsPlayer = group.IsPlayer,
                            Round = group.Round,
                            Team = group.Team,
                            Members = {{Entity = member.Entity, Initiative = newInitiative}},
                        })
                    end
                end
                for _, member in ipairs(group.Members) do
                    if member.Entity and member.Entity and member.Entity.Uuid and member.Entity.Uuid.EntityUuid and not State.isPlayerControllingDirectly(member.Entity.Uuid.EntityUuid) then
                        table.insert(groupsPlayers, {
                            Initiative = group.Initiative,
                            IsPlayer = group.IsPlayer,
                            Round = group.Round,
                            Team = group.Team,
                            Members = {{Entity = member.Entity, Initiative = member.Initiative}},
                        })
                    end
                end
            else
                table.insert(groupsEnemies, group)
            end
        end
        local numPlayerGroups = #groupsPlayers
        for i = 1, numPlayerGroups do
            combatEntity.TurnOrder.Groups[i] = groupsPlayers[i]
        end
        for i = 1, #groupsEnemies do
            combatEntity.TurnOrder.Groups[i + numPlayerGroups] = groupsEnemies[i]
        end
        local turnOrderListener
        turnOrderListener = Ext.Entity.Subscribe("TurnOrder", function (entity, _, _)
            if entity and entity.CombatState and entity.CombatState.MyGuid then
                Ext.Entity.Unsubscribe(turnOrderListener)
                local refresherCombatHelper = spawnCombatHelper(entity.CombatState.MyGuid, true)
                local boostChangedEventListener
                boostChangedEventListener = Ext.Entity.OnCreateDeferred("BoostChangedEvent", function (_, _, _)
                    Ext.Entity.Unsubscribe(boostChangedEventListener)
                    Utils.remove(refresherCombatHelper)
                    print("********after*********")
                    showTurnOrderGroups()
                end, Ext.Entity.Get(refresherCombatHelper))
            end
        end, combatEntity)
        combatEntity:Replicate("TurnOrder")
    end
end

return {
    setPlayersSwarmGroup = setPlayersSwarmGroup,
    showAllInitiativeRolls = showAllInitiativeRolls,
    showTurnOrderGroups = showTurnOrderGroups,
    getCurrentCombatRound = getCurrentCombatRound,
    spawnCombatHelper = spawnCombatHelper,
    setPlayerTurnsActive = setPlayerTurnsActive,
}
