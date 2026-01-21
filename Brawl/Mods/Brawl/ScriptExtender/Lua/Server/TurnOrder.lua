local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump

local function getInitiativeRoll(uuid)
    local entity = Ext.Entity.Get(uuid)
    if entity and entity.CombatParticipant then
        return entity.CombatParticipant.InitiativeRoll
    end
end

local function calculateMeanInitiativeRoll()
    local totalInitiativeRoll = 0
    local numInitiativeRolls = 0
    for uuid, _ in pairs(State.Session.Players) do
        if Utils.isAliveAndCanFight(uuid) then
            local entity = Ext.Entity.Get(uuid)
            if entity and entity.CombatParticipant and entity.CombatParticipant.InitiativeRoll then
                totalInitiativeRoll = totalInitiativeRoll + entity.CombatParticipant.InitiativeRoll
                numInitiativeRolls = numInitiativeRolls + 1
            end
        end
    end
    return math.floor(totalInitiativeRoll/numInitiativeRolls + 0.5)
end

local function calculateActionInterval(initiative)
    local r = Constants.ACTION_INTERVAL_RESCALING
    local scale = 1 + r - 4*r*initiative/(2*initiative + M.Utils.getInitiativeDie() + 1)
    return math.max(Constants.MINIMUM_ACTION_INTERVAL, math.floor(1000*State.Settings.ActionInterval*scale + 0.5))
end

local function rollForInitiative(uuid)
    local initiative = math.random(1, M.Utils.getInitiativeDie())
    local entity = Ext.Entity.Get(uuid)
    if entity and entity.Stats and entity.Stats.InitiativeBonus ~= nil then
        initiative = initiative + entity.Stats.InitiativeBonus
    end
    return initiative
end

local function setInitiativeRoll(uuid, roll)
    local entity = Ext.Entity.Get(uuid)
    if entity.CombatParticipant and entity.CombatParticipant.InitiativeRoll then
        entity.CombatParticipant.InitiativeRoll = roll
        if entity.CombatParticipant.CombatHandle and entity.CombatParticipant.CombatHandle.CombatState and entity.CombatParticipant.CombatHandle.CombatState.Initiatives then
            entity.CombatParticipant.CombatHandle.CombatState.Initiatives[entity] = roll
            entity.CombatParticipant.CombatHandle:Replicate("CombatState")
        end
        entity:Replicate("CombatParticipant")
    end
end

local function setPartyInitiativeRollToMean()
    State.Session.MeanInitiativeRoll = calculateMeanInitiativeRoll()
    for uuid, _ in pairs(State.Session.Players) do
        if Utils.isAliveAndCanFight(uuid) then
            setInitiativeRoll(uuid, State.Session.MeanInitiativeRoll)
        end
    end
end

local function bumpNpcInitiativeRoll(uuid)
    local entity = Ext.Entity.Get(uuid)
    local initiativeRoll = getInitiativeRoll(uuid)
    local bumpedInitiativeRoll = math.random() > 0.5 and initiativeRoll + 1 or initiativeRoll - 1
    debugPrint(M.Utils.getDisplayName(uuid), "might split group, bumping roll", initiativeRoll, "->", bumpedInitiativeRoll)
    setInitiativeRoll(uuid, bumpedInitiativeRoll)
end

local function bumpNpcInitiativeRolls()
    if State.Session.MeanInitiativeRoll ~= -100 then
        for uuid, _ in pairs(M.Roster.getBrawlers()) do
            if not State.Session.Players[uuid] and getInitiativeRoll(uuid) == State.Session.MeanInitiativeRoll then
                bumpNpcInitiativeRoll(uuid)
            end
        end
    end
end

local function setPlayersSwarmGroup(swarmGroupLabel)
    debugPrint("setPlayersSwarmGroup", swarmGroupLabel)
    if State.Session.Players then
        for uuid, _ in pairs(State.Session.Players) do
            Osi.RequestSetSwarmGroup(uuid, swarmGroupLabel or "PLAYER_SWARM_GROUP")
        end
    end
end

local function showAllInitiativeRolls()
    print("***********Initiative rolls************")
    for uuid, _ in pairs(M.Roster.getBrawlers()) do
        print(M.Utils.getDisplayName(uuid), getInitiativeRoll(uuid))
    end
    print("***************************************")
end

local function showTurnOrderGroups()
    local combatEntity = Utils.getCombatEntity()
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
    local combatEntity = Utils.getCombatEntity()
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

local function getNewInitiativeRolls(groups)
    local newInitiativeRolls = {}
    for _, info in ipairs(groups) do
        if info.Members and info.Members[1] and info.Members[1].Entity then
            table.insert(newInitiativeRolls, getInitiativeRoll(info.Members[1].Entity.Uuid.EntityUuid))
        end
    end
    return newInitiativeRolls
end

local function reorderByInitiativeRoll(doNotReplicate)
    local combatEntity = Utils.getCombatEntity()
    if combatEntity and combatEntity.TurnOrder and combatEntity.TurnOrder.Groups then
        local reorderedGroups = {}
        for i, newInitiative in ipairs(getNewInitiativeRolls(combatEntity.TurnOrder.Groups)) do
            local group = combatEntity.TurnOrder.Groups[i]
            local members = {}
            for _, member in ipairs(group.Members) do
                -- NB: should this be newInitiative, vs member.Initiative...?
                table.insert(members, {Entity = member.Entity, Initiative = member.Initiative})
            end
            table.insert(reorderedGroups, {
                Initiative = newInitiative,
                IsPlayer = group.IsPlayer,
                Round = group.Round,
                Team = group.Team,
                Members = members,
            })
        end
        table.sort(reorderedGroups, function (a, b) return a.Initiative > b.Initiative end)
        combatEntity.TurnOrder.Groups = reorderedGroups
        if not doNotReplicate then
            combatEntity:Replicate("TurnOrder")
        end
        showAllInitiativeRolls()
        showTurnOrderGroups()
    end
end

local function bumpDirectlyControlledInitiativeRolls()
    debugPrint("bumpDirectlyControlledInitiativeRolls")
    for uuid, player in pairs(State.Session.Players) do
        if player.isControllingDirectly then
            setInitiativeRoll(uuid, State.Session.MeanInitiativeRoll + 1)
        else
            setInitiativeRoll(uuid, State.Session.MeanInitiativeRoll)
        end
    end
end

-- if a player is assigned 2+ characters, re-order them in the topbar so that the currently controlled one is first,
-- so the re-selection on round start doesn't jerk the screen around
-- (then reorder every time GainedControl happens)
-- split into single-member groups
local function reorderPlayersByControl(reorderedGroups, group, isDirectlyControlled)
    for _, member in ipairs(group.Members) do
        if member.Entity and member.Entity and member.Entity.Uuid then
            local uuid = member.Entity.Uuid.EntityUuid
            if uuid and State.isPlayerControllingDirectly(uuid) == isDirectlyControlled then
                local initiative = getInitiativeRoll(uuid)
                table.insert(reorderedGroups, {
                    Initiative = initiative,
                    IsPlayer = group.IsPlayer,
                    Round = group.Round,
                    Team = group.Team,
                    Members = {{Entity = member.Entity, Initiative = initiative}},
                })
            end
        end
    end
end

local function stopListeners(combatGuid)
    if State.Session.TurnOrderListener[combatGuid] then
        Ext.Entity.Unsubscribe(State.Session.TurnOrderListener[combatGuid])
        State.Session.TurnOrderListener[combatGuid] = nil
    end
    if State.Session.BoostChangedEventListener[combatGuid] then
        Ext.Entity.Unsubscribe(State.Session.BoostChangedEventListener[combatGuid])
        State.Session.BoostChangedEventListener[combatGuid] = nil
    end
    if State.Session.RefresherCombatHelper[combatGuid] then
        Utils.remove(State.Session.RefresherCombatHelper[combatGuid])
        State.Session.RefresherCombatHelper[combatGuid] = nil
    end
end

local function isInGroup(group, uuid)
    if group.Members then
        for _, member in ipairs(group.Members) do
            if member.Entity and member.Entity.Uuid and member.Entity.Uuid.EntityUuid == uuid then
                return true
            end
        end
    end
end

local function setTurnActive(uuid)
    local combatEntity = Utils.getCombatEntity()
    if combatEntity and combatEntity.TurnOrder and combatEntity.TurnOrder.Groups then
        local groupSpecial = nil
        local groupsPlayers = {}
        local groupsEnemies = {}
        for _, group in ipairs(combatEntity.TurnOrder.Groups) do
            if isInGroup(group, uuid) then
                groupSpecial = group
            else
                if group.IsPlayer then
                    reorderPlayersByControl(groupsPlayers, group, true)
                    reorderPlayersByControl(groupsPlayers, group, false)
                else
                    table.insert(groupsEnemies, group)
                end
            end
        end
        if groupSpecial then
            combatEntity.TurnOrder.Groups[1] = groupSpecial
            local numPlayerGroups = #groupsPlayers
            for i = 1, numPlayerGroups do
                combatEntity.TurnOrder.Groups[1 + i] = groupsPlayers[i]
            end
            for i = 1, #groupsEnemies do
                combatEntity.TurnOrder.Groups[1 + i + numPlayerGroups] = groupsEnemies[i]
            end
            combatEntity:Replicate("TurnOrder")
        end
    end
end

-- NB: this makes an absolute mess of combatEntity.TurnOrder.Groups, but it seems to work as intended
local function setPlayerTurnsActive()
    local combatEntity = Utils.getCombatEntity()
    if combatEntity and combatEntity.TurnOrder and combatEntity.TurnOrder.Groups then
        -- print("********init***********")
        -- showTurnOrderGroups()
        local groupsPlayers = {}
        local groupsEnemies = {}
        for _, group in ipairs(combatEntity.TurnOrder.Groups) do
            if group.IsPlayer then
                reorderPlayersByControl(groupsPlayers, group, true)
                reorderPlayersByControl(groupsPlayers, group, false)
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
        local uuid = combatEntity.CombatState.MyGuid
        if State.Session.TurnOrderListener[uuid] then
            Ext.Entity.Unsubscribe(State.Session.TurnOrderListener[uuid])
            State.Session.TurnOrderListener[uuid] = nil
        end
        State.Session.TurnOrderListener[uuid] = Ext.Entity.Subscribe("TurnOrder", function (entity, _, _)
            if entity and entity.CombatState and entity.CombatState.MyGuid then
                Ext.Entity.Unsubscribe(State.Session.TurnOrderListener[uuid])
                if State.Session.RefresherCombatHelper[uuid] then
                    Utils.remove(State.Session.RefresherCombatHelper[uuid])
                    State.Session.RefresherCombatHelper[uuid] = nil
                end
                State.Session.RefresherCombatHelper[uuid] = spawnCombatHelper(uuid, true)
                if State.Session.BoostChangedEventListener[uuid] then
                    Ext.Entity.Unsubscribe(State.Session.BoostChangedEventListener[uuid])
                    State.Session.BoostChangedEventListener[uuid] = nil
                end
                State.Session.BoostChangedEventListener[uuid] = Ext.Entity.OnCreateDeferred("BoostChangedEvent", function (_, _, _)
                    Ext.Entity.Unsubscribe(State.Session.BoostChangedEventListener[uuid])
                    Utils.remove(State.Session.RefresherCombatHelper[uuid])
                    -- print("********after*********")
                    -- showTurnOrderGroups()
                end, Ext.Entity.Get(State.Session.RefresherCombatHelper[uuid]))
            end
        end, combatEntity)
        combatEntity:Replicate("TurnOrder")
    end
end

return {
    getInitiativeRoll = getInitiativeRoll,
    calculateActionInterval = calculateActionInterval,
    rollForInitiative = rollForInitiative,
    setInitiativeRoll = setInitiativeRoll,
    setPartyInitiativeRollToMean = setPartyInitiativeRollToMean,
    bumpNpcInitiativeRolls = bumpNpcInitiativeRolls,
    setPlayersSwarmGroup = setPlayersSwarmGroup,
    showAllInitiativeRolls = showAllInitiativeRolls,
    showTurnOrderGroups = showTurnOrderGroups,
    getCurrentCombatRound = getCurrentCombatRound,
    spawnCombatHelper = spawnCombatHelper,
    reorderByInitiativeRoll = reorderByInitiativeRoll,
    bumpDirectlyControlledInitiativeRolls = bumpDirectlyControlledInitiativeRolls,
    stopListeners = stopListeners,
    setTurnActive = setTurnActive,
    setPlayerTurnsActive = setPlayerTurnsActive,
}
