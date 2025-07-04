local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump
local getDisplayName = Utils.getDisplayName
local isAliveAndCanFight = Utils.isAliveAndCanFight
local isToT = Utils.isToT

local function isPlayerFrozen(uuid)
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    if modVars.FrozenPlayerResources == nil then
        return false
    end
    if not modVars.FrozenPlayerResources[uuid] then
        return false
    end
    return true
end

local function freezePlayer(uuid)
    local entity = Ext.Entity.Get(uuid)
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    if modVars.FrozenPlayerResources == nil then
        modVars.FrozenPlayerResources = {}
    end
    local frozenPlayerResources = modVars.FrozenPlayerResources
    if not frozenPlayerResources[uuid] then
        frozenPlayerResources[uuid] = {}
        if entity.ActionResources and entity.ActionResources.Resources then
            local actionPoints = entity.ActionResources.Resources[Constants.ACTION_RESOURCES.ActionPoint]
            if actionPoints and actionPoints[1] and actionPoints[1].Amount ~= nil then
                frozenPlayerResources[uuid].ActionPoint = actionPoints[1].Amount
            end
            local bonusActionPoints = entity.ActionResources.Resources[Constants.ACTION_RESOURCES.BonusActionPoint]
            if bonusActionPoints and bonusActionPoints[1] and bonusActionPoints[1].Amount ~= nil then
                frozenPlayerResources[uuid].BonusActionPoint = bonusActionPoints[1].Amount
            end
        end
        if entity.CanMove and entity.CanMove.Flags ~= nil then
            frozenPlayerResources[uuid].CanMoveFlags = {}
            for _, flag in ipairs(entity.CanMove.Flags) do
               table.insert(frozenPlayerResources[uuid].CanMoveFlags, flag)
            end
        end
        modVars.FrozenPlayerResources[uuid] = frozenPlayerResources[uuid]
    end
    -- debugPrint("FREEZE: FROZEN PLAYER RESOURCES")
    -- debugDump(frozenPlayerResources)
    entity.ActionResources.Resources[Constants.ACTION_RESOURCES.ActionPoint][1].Amount = 0
    entity.ActionResources.Resources[Constants.ACTION_RESOURCES.BonusActionPoint][1].Amount = 0
    entity.CanMove.Flags = {}
    entity:Replicate("ActionResources")
    entity:Replicate("CanMove")
end

local function unfreezePlayer(uuid)
    local entity = Ext.Entity.Get(uuid)
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    if modVars.FrozenPlayerResources == nil then
        modVars.FrozenPlayerResources = {}
    end
    local frozenPlayerResources = modVars.FrozenPlayerResources
    -- debugPrint("UNFREEZE: FROZEN PLAYER RESOURCES")
    -- debugDump(frozenPlayerResources)
    if frozenPlayerResources[uuid] then
        if entity.ActionResources and entity.ActionResources.Resources then
            local actionPoints = entity.ActionResources.Resources[Constants.ACTION_RESOURCES.ActionPoint]
            if actionPoints and actionPoints[1] and frozenPlayerResources[uuid].ActionPoint ~= nil then
                entity.ActionResources.Resources[Constants.ACTION_RESOURCES.ActionPoint][1].Amount = frozenPlayerResources[uuid].ActionPoint
            end
            local bonusActionPoints = entity.ActionResources.Resources[Constants.ACTION_RESOURCES.BonusActionPoint]
            if bonusActionPoints and bonusActionPoints[1] and frozenPlayerResources[uuid].BonusActionPoint ~= nil then
                entity.ActionResources.Resources[Constants.ACTION_RESOURCES.BonusActionPoint][1].Amount = frozenPlayerResources[uuid].BonusActionPoint
            end
        end
        if entity.CanMove and frozenPlayerResources[uuid].CanMoveFlags ~= nil then
            entity.CanMove.Flags = frozenPlayerResources[uuid].CanMoveFlags
        end
        frozenPlayerResources[uuid] = nil
    end
    entity:Replicate("ActionResources")
    entity:Replicate("CanMove")
    modVars.FrozenPlayerResources = frozenPlayerResources
end

local function freezeAllPlayers(shouldFreezePlayers)
    -- debugPrint("freezeAllPlayers")
    -- debugDump(shouldFreezePlayers)
    local players = State.Session.Players
    if players then
        for playerUuid, _ in pairs(players) do
            -- Osi.SetCanJoinCombat(playerUuid, 0)
            -- Ext.Timer.WaitFor(200, function ()
            if not shouldFreezePlayers or shouldFreezePlayers[playerUuid] then
                debugPrint(getDisplayName(playerUuid), "freezing player", playerUuid)
                freezePlayer(playerUuid)
            end
            -- end)
        end
    end
end

local function unfreezeAllPlayers()
    local players = State.Session.Players
    if players then
        for playerUuid, _ in pairs(players) do
            -- Osi.SetCanJoinCombat(playerUuid, 1)
            Ext.Timer.WaitFor(200, function ()
                unfreezePlayer(playerUuid)
            end)
        end
    end
end

local function singleCharacterTurn(brawler, brawlerIndex)
    local hostCharacterUuid = Osi.GetHostCharacter()
    debugPrint("singleCharacterTurn", brawler.displayName, brawler.uuid, Utils.canAct(brawler.uuid))
    -- is this ok for non-ToT?
    if Osi.IsEnemy(brawler.uuid, hostCharacterUuid) == 0 and not Utils.isPlayerOrAlly(brawler.uuid) then
        Osi.SetRelationTemporaryHostile(brawler.uuid, hostCharacterUuid)
    end
    if State.Session.Players[brawler.uuid] or (isToT() and Mods.ToT.PersistentVars.Scenario and brawler.uuid == Mods.ToT.PersistentVars.Scenario.CombatHelper) or not Utils.canAct(brawler.uuid) then
        debugPrint("don't take turn", brawler.uuid, brawler.displayName)
        return false
    end
    debugPrint(brawler.displayName, "AI.pulseAction (bonus)", brawler.uuid, brawlerIndex)
    if State.Session.TBSMActionResourceListeners[brawler.uuid] == nil then
        State.Session.TBSMActionResourceListeners[brawler.uuid] = Ext.Entity.Subscribe("ActionResources", function (entity, _, _)
            Movement.setMovementToMax(entity)
        end, Ext.Entity.Get(brawler.uuid))
    end
    Ext.Timer.WaitFor(brawlerIndex*10, function ()
        if not AI.pulseAction(brawler, true) then
            debugPrint(brawler.displayName, "bonus action not found, immediate AI.pulseAction", brawler.uuid)
            return AI.pulseAction(brawler)
        end
        Ext.Timer.WaitFor(6000, function ()
            debugPrint(brawler.displayName, "AI.pulseAction", brawler.uuid)
            AI.pulseAction(brawler)
        end)
    end)
    return true
end

-- NB: stay in combat, adjust movement speed as needed
--     when there's only 3 or 4 enemies auto-disables
local function startEnemyTurn(canActBeforeDelay)
    debugPrint("startEnemyTurn")
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
        local brawlersInLevel = State.Session.Brawlers[level]
        if brawlersInLevel then
            local brawlerIndex = 0
            for brawlerUuid, brawler in pairs(brawlersInLevel) do
                if canActBeforeDelay[brawlerUuid] ~= false and singleCharacterTurn(brawler, brawlerIndex) then
                    brawlerIndex = brawlerIndex + 1
                end
            end
        end
    end
end

-- local function checkPlayerRejoinCombat(playerUuid)
--     if isAliveAndCanFight(playerUuid) then
--         local playerBrawler = State.getBrawlerByUuid(playerUuid)
--         if not playerBrawler and isToT() then
--             Roster.addBrawler(playerUuid, true)
--             playerBrawler = State.getBrawlerByUuid(playerUuid)
--         end
--         if playerBrawler and Osi.IsInCombat(playerUuid) == 0 then
--             debugPrint("checkPlayerRejoinCombat", playerUuid)
--             local level = Osi.GetRegion(playerUuid)
--             local brawlersInLevel = State.Session.Brawlers[level]
--             if brawlersInLevel then
--                 for brawlerUuid, _ in pairs(brawlersInLevel) do
--                     if Utils.isPugnacious(brawlerUuid, playerUuid) and isAliveAndCanFight(brawlerUuid) and Osi.GetDistanceTo(brawlerUuid, playerUuid) < 20 then
--                         debugPrint("re-entering combat", playerUuid, brawlerUuid, getDisplayName(playerUuid), getDisplayName(brawlerUuid))
--                         -- Osi.EnterCombat(playerUuid, brawlerUuid)
--                         Osi.SetRelationTemporaryHostile(playerUuid, brawlerUuid)
--                         -- NB: alternative method from Focus
--                         -- local combat = Ext.Entity.GetAllEntitiesWithComponent("ServerEnterRequest")[1]
--                         -- combat.ServerEnterRequest.EnterRequests[_C()] = true
--                         -- NB: alternative from Norb
--                         -- Ext.System.ServerCombat.JoinCombat[_C()] = combatEntity
--                         return true
--                     end
--                 end
--             end
--         end
--     end
--     return false
-- end

-- local function checkPlayersRejoinCombat()
--     local players = State.Session.Players
--     if players then
--         for playerUuid, _ in pairs(players) do
--             checkPlayerRejoinCombat(playerUuid)
--         end
--     end
-- end

local function checkAllPlayersFinishedTurns()
    local players = State.Session.Players
    if players then
        debugDump(State.Session.TurnBasedSwarmModePlayerTurnEnded)
        for playerUuid, _ in pairs(players) do
            local isUncontrolled = Utils.hasLoseControlStatus(playerUuid)
            debugPrint("Checking finished turns", playerUuid, State.Session.TurnBasedSwarmModePlayerTurnEnded[playerUuid], isAliveAndCanFight(playerUuid), isUncontrolled)
            if isAliveAndCanFight(playerUuid) and not isUncontrolled and not State.Session.TurnBasedSwarmModePlayerTurnEnded[playerUuid] then
                return false
            end
        end
        return true
    end
    return nil
end

-- local function checkEnemiesJoinCombat()
--     local hostCharacterUuid = Osi.GetHostCharacter()
--     local level = Osi.GetRegion(hostCharacterUuid)
--     if level then
--         local brawlersInLevel = State.Session.Brawlers[level]
--         if brawlersInLevel then
--             for brawlerUuid, brawler in pairs(brawlersInLevel) do
--                 debugPrint(brawler.displayName, "check for join combat")
--                 -- NB: what about withers? act 3 civilians? etc 0133f2ad-e121-4590-b5f0-a79413919805
--                 --     do we even need this apart from ToT?
--                 if Osi.IsPartyMember(brawlerUuid, 1) == 0 and not Utils.isPlayerOrAlly(brawlerUuid) then
--                     Osi.SetRelationTemporaryHostile(brawlerUuid, hostCharacterUuid)
--                 end
--             end
--         end
--     end
-- end

-- local function startNextRound(combatGuid)
--     debugPrint("startNextRound", combatGuid)
--     -- local nearbyRadius = isToT() and 150 or Constants.NEARBY_RADIUS
--     unfreezeAllPlayers()
--     -- startEnemyTurn(1)
--     -- local hostCharacter = Osi.GetHostCharacter()
--     -- if not isToT() or not Mods.ToT.Player.InCamp() then
--     --     -- checkPlayersRejoinCombat()
--     --     Roster.addNearbyToBrawlers(hostCharacter, nearbyRadius, combatGuid)
--     --     -- checkEnemiesJoinCombat()
--     -- end
-- end

local function setTurnComplete(uuid)
    local entity = Ext.Entity.Get(uuid)
    if not entity.TurnBased.TurnActionsCompleted then
        debugPrint(getDisplayName(uuid), "Setting turn complete", uuid)
        entity.TurnBased.HadTurnInCombat = true
        entity.TurnBased.RequestedEndTurn = true
        entity.TurnBased.TurnActionsCompleted = true
        -- entity.TurnBased.CanActInCombat = false
        entity:Replicate("TurnBased")
    end
end

return {
    isPlayerFrozen = isPlayerFrozen,
    freezeAllPlayers = freezeAllPlayers,
    unfreezeAllPlayers = unfreezeAllPlayers,
    -- checkPlayersRejoinCombat = checkPlayersRejoinCombat,
    checkAllPlayersFinishedTurns = checkAllPlayersFinishedTurns,
    startEnemyTurn = startEnemyTurn,
    -- startNextRound = startNextRound,
    setTurnComplete = setTurnComplete,
}
