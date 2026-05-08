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
            if entity and entity.CombatParticipant and entity.CombatParticipant.InitiativeRoll and entity.CombatParticipant.InitiativeRoll > 0 then
                totalInitiativeRoll = totalInitiativeRoll + entity.CombatParticipant.InitiativeRoll
                numInitiativeRolls = numInitiativeRolls + 1
            end
        end
    end
    if numInitiativeRolls == 0 then
        return nil
    end
    return math.floor(totalInitiativeRoll/numInitiativeRolls + 0.5)
end

-- Highest InitiativeRoll among non-player, non-helper combat participants.
-- Used to keep party initiative just-above-enemy without arbitrary inflation.
local function calculateMaxEnemyInitiativeRoll()
    local maxRoll
    for uuid, _ in pairs(M.Roster.getBrawlers()) do
        if not State.Session.Players[uuid] and not M.Utils.isCombatHelper(uuid) then
            local roll = getInitiativeRoll(uuid)
            if roll and (not maxRoll or roll > maxRoll) then
                maxRoll = roll
            end
        end
    end
    return maxRoll
end

local function calculateActionInterval(initiative)
    if not initiative then
        return math.floor(1000*State.Settings.ActionInterval + 0.5)
    end
    local r = Constants.ACTION_INTERVAL_RESCALING
    local scale = 1 + r - 4*r*initiative/(2*math.abs(initiative) + M.Utils.getInitiativeDie() + 1)
    return math.max(Constants.MINIMUM_ACTION_INTERVAL, math.floor(1000*State.Settings.ActionInterval*scale + 0.5))
end

local function setInitiativeRoll(uuid, roll)
    local entity = Ext.Entity.Get(uuid)
    if entity.CombatParticipant and entity.CombatParticipant.InitiativeRoll then
        local oldRoll = entity.CombatParticipant.InitiativeRoll
        if oldRoll == roll then
            return
        end
        debugPrint(string.format("[setInitiativeRoll] %s %d -> %d (replicating CombatState + CombatParticipant)",
            M.Utils.getDisplayName(uuid) or uuid, oldRoll, roll))
        entity.CombatParticipant.InitiativeRoll = roll
        if entity.CombatParticipant.CombatHandle and entity.CombatParticipant.CombatHandle.CombatState and entity.CombatParticipant.CombatHandle.CombatState.Initiatives then
            entity.CombatParticipant.CombatHandle.CombatState.Initiatives[entity] = roll
            entity.CombatParticipant.CombatHandle:Replicate("CombatState")
        end
        entity:Replicate("CombatParticipant")
    end
end

local function setPartyInitiativeRollToMean()
    if State.Session.MeanInitiativeRoll then
        return
    end
    debugPrint("setting party init roll to mean...")
    local mean = calculateMeanInitiativeRoll()
    if mean then
        State.Session.MeanInitiativeRoll = mean
    end
end

-- -100 = engine "not yet rolled" / dead. -99 = bugged value
local function isValidInitRoll(roll)
    return roll ~= nil and roll ~= -100 and roll ~= -99
end

local function getNaturalInitiativeCache()
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    modVars.NaturalInitiative = modVars.NaturalInitiative or {}
    return modVars.NaturalInitiative
end

local function cacheNaturalInitiativeIfMissing(uuid)
    local cache = getNaturalInitiativeCache()
    if cache[uuid] then return end
    local roll = getInitiativeRoll(uuid)
    if isValidInitRoll(roll) then
        cache[uuid] = roll
    end
end

local function restoreNaturalInitiative()
    local cache = getNaturalInitiativeCache()
    local count = 0
    for _ in pairs(cache) do count = count + 1 end
    debugPrint("[restoreNaturalInitiative] called, cache size =", count)
    for uuid, roll in pairs(cache) do
        if isValidInitRoll(roll) and Utils.isAliveAndCanFight(uuid) then
            setInitiativeRoll(uuid, roll)
        end
    end
end

local function clearNaturalInitiativeFor(uuid)
    local cache = getNaturalInitiativeCache()
    cache[uuid] = nil
end

local function clearAllNaturalInitiative()
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    modVars.NaturalInitiative = nil
end

-- Captures pre-mutate values into the natural-init cache before forcing the mean
local function equalizePartyInitiative()
    if not State.Session.MeanInitiativeRoll then
        return
    end
    for uuid, _ in pairs(State.Session.Players) do
        if Utils.isAliveAndCanFight(uuid) then
            cacheNaturalInitiativeIfMissing(uuid)
            setInitiativeRoll(uuid, State.Session.MeanInitiativeRoll)
        end
    end
end

local function bumpNpcInitiativeRoll(uuid)
    local initiativeRoll = getInitiativeRoll(uuid)
    if initiativeRoll then
        cacheNaturalInitiativeIfMissing(uuid)
        local bumpedInitiativeRoll = math.random() > 0.5 and initiativeRoll + 1 or initiativeRoll - 1
        debugPrint(M.Utils.getDisplayName(uuid), "might split group, bumping roll", initiativeRoll, "->", bumpedInitiativeRoll)
        setInitiativeRoll(uuid, bumpedInitiativeRoll)
    end
end

local function bumpNpcInitiativeRolls()
    if State.Session.MeanInitiativeRoll then
        for uuid, _ in pairs(M.Roster.getBrawlers()) do
            if not State.Session.Players[uuid] and not M.Utils.isCombatHelper(uuid) and getInitiativeRoll(uuid) == State.Session.MeanInitiativeRoll then
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
    for uuid, _ in pairs(M.Roster.getBrawlers()) do
        print(M.Utils.getDisplayName(uuid), getInitiativeRoll(uuid))
    end
end

local function getCurrentCombatRound()
    local combatEntity = Utils.getCombatEntity()
    if combatEntity and combatEntity.TurnOrder and combatEntity.TurnOrder.field_40 then
        return combatEntity.TurnOrder.field_40
    end
end

local function formatGroupStr(i, group)
    local groupStr = tostring(i) .. " init=" .. tostring(group.Initiative) .. " IsPlayer=" .. tostring(group.IsPlayer) .. " Round=" .. tostring(group.Round) .. " Team=" .. tostring(group.Team)
    if group.Members and #group.Members > 0 then
        for j, member in ipairs(group.Members) do
            if member.Entity and member.Entity.Uuid and member.Entity.Uuid.EntityUuid then
                groupStr = groupStr .. (j == 1 and " " or " +") .. " " .. M.Utils.getDisplayName(member.Entity.Uuid.EntityUuid)
            else
                groupStr = groupStr .. " [nil-entity]"
            end
        end
    else
        groupStr = groupStr .. " [empty]"
    end
    if not group.IsPlayer then
        -- thank u hippo
        groupStr = string.format("\x1b[38;2;%d;%d;%dm%s\x1b[0m", 110, 150, 90, groupStr)
    end
    return groupStr
end

local function showTurnOrderGroups()
    local combatEntity = Utils.getCombatEntity()
    if combatEntity and combatEntity.TurnOrder and combatEntity.TurnOrder.Groups then
        print("currentCombatRound =", getCurrentCombatRound())
        for i, group in ipairs(combatEntity.TurnOrder.Groups) do
            print(formatGroupStr(i, group))
        end
    end
end

local function showTurnOrderGroups2()
    local combatEntity = Utils.getCombatEntity()
    if combatEntity and combatEntity.TurnOrder and combatEntity.TurnOrder.Groups2 then
        print("currentCombatRound =", getCurrentCombatRound())
        for i, group in ipairs(combatEntity.TurnOrder.Groups2) do
            print(formatGroupStr(i, group))
        end
    end
end

-- thank u hippo
local function spawnCombatHelper(combatGuid, isRefreshOnly)
    if not State.Session.CombatHelper or isRefreshOnly then
        debugPrint("Spawn combat helper", combatGuid, isRefreshOnly)
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
        local narrativeCombatLabel = Utils.getNarrativeCombatLabel(combatGuid)
        if narrativeCombatLabel then
            Osi.PROC_GLO_NarrativeCombat_JoinCombat(narrativeCombatLabel, combatHelper)
        end
        return combatHelper
    end
end

local function getNewInitiativeRolls(groups)
    local newInitiativeRolls = {}
    for i, info in ipairs(groups) do
        if info.Members and info.Members[1] and info.Members[1].Entity then
            -- Sparse indexing: skipped groups stay nil at their original index so
            -- callers can detect-and-skip without losing alignment with `groups`.
            newInitiativeRolls[i] = getInitiativeRoll(info.Members[1].Entity.Uuid.EntityUuid)
        end
    end
    return newInitiativeRolls
end

local function reorderByInitiativeRoll(doNotReplicate)
    local combatEntity = Utils.getCombatEntity()
    if combatEntity and combatEntity.TurnOrder and combatEntity.TurnOrder.Groups then
        local groups = combatEntity.TurnOrder.Groups
        local newInitiativeRolls = getNewInitiativeRolls(groups)
        local reorderedGroups = {}
        -- Numeric for (not ipairs) because newInitiativeRolls may be sparse
        for i = 1, #groups do
            local newInitiative = newInitiativeRolls[i]
            if newInitiative then
                local group = groups[i]
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
        end
        table.sort(reorderedGroups, function (a, b) return a.Initiative > b.Initiative end)
        combatEntity.TurnOrder.Groups = reorderedGroups
        if not doNotReplicate then
            combatEntity:Replicate("TurnOrder")
        end
        -- showAllInitiativeRolls()
        -- showTurnOrderGroups()
    end
end

-- Bump party initiative just above the highest enemy roll.  Every char marked isControllingDirectly (any user's selection) gets target+1, all other
-- party chars get target.  The flat assignment is critical: when control moves, the previously-controlled char must actually drop from target+1 back
-- to target, otherwise old + new sit tied at target+1 with no clear "first" for the engine.  Multiple users tied at target+1 is fine in MP since
-- each user's GainedControl is a separate per-user event and users can't select each other's characters anyway.
local function bumpInitiativeRolls(intendedSet)
    local maxEnemy = calculateMaxEnemyInitiativeRoll()
    if not maxEnemy then
        debugPrint("[bumpInitiativeRolls] skipped (no enemy init found)")
        return
    end
    -- Skip if maxEnemy is a known sentinel (-100, -99, -20); bumping would propagate garbage to the party.
    if not isValidInitRoll(maxEnemy) then
        debugPrint(string.format("[bumpInitiativeRolls] skipped (maxEnemy=%d is sentinel)", maxEnemy))
        return
    end
    local target = maxEnemy + 1
    -- Diagnostic: each setInitiativeRoll below replicates CombatState -- engine may reassign ClientControl
    local controllingNames = {}
    for uuid, player in pairs(State.Session.Players) do
        if player.isControllingDirectly then
            table.insert(controllingNames, M.Utils.getDisplayName(uuid) or uuid)
        end
    end
    debugPrint(string.format("[bumpInitiativeRolls] maxEnemy=%d target=%d (controlling=%s, intendedSet=%s)",
        maxEnemy, target,
        #controllingNames > 0 and table.concat(controllingNames, ",") or "<none>",
        intendedSet and "explicit" or "nil"))
    for uuid, player in pairs(State.Session.Players) do
        local controlled = player.isControllingDirectly or (intendedSet and intendedSet[uuid])
        if controlled then
            setInitiativeRoll(uuid, target + 1)
        else
            setInitiativeRoll(uuid, target)
        end
    end
end

local function bumpDirectlyControlledInitiativeRolls()
    debugPrint("bumpDirectlyControlledInitiativeRolls")
    bumpInitiativeRolls(nil)
end

-- Use this when we know the intended controlled char (e.g. pre-emptively at FTB entry) but the engine hasn't yet fired GainedControl to flip
-- our state flags.  Accepts either a single uuid string or a set table of {[uuid]=true} (preferred for MP where multiple users have intended chars).
local function bumpInitiativeRollsFor(intended)
    if type(intended) == "string" then
        bumpInitiativeRolls({[intended] = true})
    else
        bumpInitiativeRolls(intended)
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
        for _, refresherUuid in ipairs(State.Session.RefresherCombatHelper[combatGuid]) do
            Utils.remove(refresherUuid)
        end
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

-- Rebuild TurnOrder.Groups from Session.Players (controlled first), splitting the consolidated party group into single-member groups so the controlled
-- character occupies the first slot. Existing enemy groups are preserved verbatim after the player block.  After the Replicate, a refresher combat
-- helper is spawned so the topbar re-sorts.
local function setPlayerTurnsActive()
    local combatEntity = Utils.getCombatEntity()
    if not (combatEntity and combatEntity.TurnOrder and combatEntity.TurnOrder.Groups) then
        return
    end
    local round, team
    for _, group in ipairs(combatEntity.TurnOrder.Groups) do
        if group.IsPlayer then
            round = group.Round
            team = group.Team
            break
        end
    end
    -- Collect all directly-controlled chars (in MP each user has their own).
    local controlledSet = {}
    local controlledList = {}
    for uuid, player in pairs(State.Session.Players) do
        if player.isControllingDirectly then
            controlledSet[uuid] = true
            table.insert(controlledList, uuid)
        end
    end
    -- Fallback: at round turnover the engine transiently deselects the controlled character (ClientControl component removed), so no player
    -- has isControllingDirectly=true when we run.  Use the cached last-known controlled uuids (per-user) so the player ordering still puts
    -- the right chars first.
    if #controlledList == 0 and State.Session.LastControlledUuid then
        for _, cachedUuid in pairs(State.Session.LastControlledUuid) do
            if State.Session.Players[cachedUuid] and not controlledSet[cachedUuid] then
                controlledSet[cachedUuid] = true
                table.insert(controlledList, cachedUuid)
            end
        end
    end
    local otherUuids = {}
    for uuid, _ in pairs(State.Session.Players) do
        if not controlledSet[uuid] then
            table.insert(otherUuids, uuid)
        end
    end
    local groupsPlayers = {}
    local function addGroup(uuid)
        local entity = Ext.Entity.Get(uuid)
        if entity then
            local initiative = getInitiativeRoll(uuid)
            table.insert(groupsPlayers, {
                Initiative = initiative,
                IsPlayer = true,
                Round = round,
                Team = team,
                Members = {{Entity = entity, Initiative = initiative}},
            })
        end
    end
    for _, uuid in ipairs(controlledList) do
        addGroup(uuid)
    end
    for _, uuid in ipairs(otherUuids) do
        addGroup(uuid)
    end
    -- Whole-table assignment: replaces Groups with EXACTLY the player single-member groups, no enemies, no duplicate ghost entries.
    -- (Per-index writes leave behind duplicate-player ghosts in the slots originally held by enemies - see prior memory.)
    combatEntity.TurnOrder.Groups = groupsPlayers
    local uuid = combatEntity.CombatState.MyGuid
    if State.Session.TurnOrderListener[uuid] then
        Ext.Entity.Unsubscribe(State.Session.TurnOrderListener[uuid])
        State.Session.TurnOrderListener[uuid] = nil
    end
    State.Session.TurnOrderListener[uuid] = Ext.Entity.Subscribe("TurnOrder", function (entity, _, _)
        if entity and entity.CombatState and entity.CombatState.MyGuid then
            Ext.Entity.Unsubscribe(State.Session.TurnOrderListener[uuid])
            local refresher = spawnCombatHelper(uuid, true)
            if refresher then
                if not State.Session.RefresherCombatHelper[uuid] then
                    State.Session.RefresherCombatHelper[uuid] = {}
                end
                table.insert(State.Session.RefresherCombatHelper[uuid], refresher)
            end
        end
    end, combatEntity)
    combatEntity:Replicate("TurnOrder")
end

local function dumpTurnOrderState(label)
    print("[ROUND_DEBUG] ===== " .. tostring(label) .. " =====")
    print("[ROUND_DEBUG] currentCombatRound =", getCurrentCombatRound())
    local combatEntity = Utils.getCombatEntity()
    if not combatEntity or not combatEntity.TurnOrder then
        print("[ROUND_DEBUG] no combat entity / no TurnOrder")
        return
    end
    if combatEntity.TurnOrder.Groups then
        print("[ROUND_DEBUG] -- Groups --")
        for i, group in ipairs(combatEntity.TurnOrder.Groups) do
            print("[ROUND_DEBUG] " .. formatGroupStr(i, group))
        end
    end
    if combatEntity.TurnOrder.Groups2 then
        print("[ROUND_DEBUG] -- Groups2 --")
        for i, group in ipairs(combatEntity.TurnOrder.Groups2) do
            print("[ROUND_DEBUG] " .. formatGroupStr(i, group))
        end
    end
    -- Per-brawler TurnBased state. Helps identify which fields differ between entities that get TurnStarted vs those that don't.
    print("[ROUND_DEBUG] -- TurnBased per brawler --")
    for uuid, _ in pairs(M.Roster.getBrawlers()) do
        local entity = Ext.Entity.Get(uuid)
        local tb = entity and entity.TurnBased
        if tb then
            print("[ROUND_DEBUG]",
                M.Utils.getDisplayName(uuid), uuid,
                "isPlayer=" .. tostring(M.Osi.IsPartyMember(uuid, 1) == 1),
                "IsActive=" .. tostring(tb.IsActiveCombatTurn),
                "HadTurn=" .. tostring(tb.HadTurnInCombat),
                "Acted=" .. tostring(tb.ActedThisRoundInCombat),
                "ActionsCompleted=" .. tostring(tb.TurnActionsCompleted),
                "RequestedEnd=" .. tostring(tb.RequestedEndTurn),
                "CanAct=" .. tostring(tb.CanActInCombat),
                "Team=" .. tostring(tb.CombatTeam))
        else
            print("[ROUND_DEBUG]", M.Utils.getDisplayName(uuid), uuid, "NO TurnBased")
        end
    end
end

return {
    getInitiativeRoll = getInitiativeRoll,
    calculateActionInterval = calculateActionInterval,
    setInitiativeRoll = setInitiativeRoll,
    setPartyInitiativeRollToMean = setPartyInitiativeRollToMean,
    restoreNaturalInitiative = restoreNaturalInitiative,
    clearNaturalInitiativeFor = clearNaturalInitiativeFor,
    clearAllNaturalInitiative = clearAllNaturalInitiative,
    equalizePartyInitiative = equalizePartyInitiative,
    bumpNpcInitiativeRolls = bumpNpcInitiativeRolls,
    setPlayersSwarmGroup = setPlayersSwarmGroup,
    showAllInitiativeRolls = showAllInitiativeRolls,
    showTurnOrderGroups = showTurnOrderGroups,
    showTurnOrderGroups2 = showTurnOrderGroups2,
    getCurrentCombatRound = getCurrentCombatRound,
    spawnCombatHelper = spawnCombatHelper,
    reorderByInitiativeRoll = reorderByInitiativeRoll,
    bumpDirectlyControlledInitiativeRolls = bumpDirectlyControlledInitiativeRolls,
    bumpInitiativeRolls = bumpInitiativeRolls,
    bumpInitiativeRollsFor = bumpInitiativeRollsFor,
    stopListeners = stopListeners,
    setTurnActive = setTurnActive,
    setPlayerTurnsActive = setPlayerTurnsActive,
    dumpTurnOrderState = dumpTurnOrderState,
}
