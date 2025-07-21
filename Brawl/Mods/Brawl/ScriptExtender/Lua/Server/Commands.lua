-- local Constants = require("Server/Constants.lua")
-- local Utils = require("Server/Utils.lua")
-- local State = require("Server/State.lua")
-- local Resources = require("Server/Resources.lua")
-- local Movement = require("Server/Movement.lua")
-- local Roster = require("Server/Roster.lua")
-- local Pause = require("Server/Pause.lua")
-- local Listeners = require("Server/Listeners.lua")

local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump
local getDisplayName = Utils.getDisplayName
local isAliveAndCanFight = Utils.isAliveAndCanFight
local isOnSameLevel = Utils.isOnSameLevel
local isPugnacious = Utils.isPugnacious

local function modStatusMessage(message)
    Osi.QuestMessageHide("ModStatusMessage")
    if State.Session.ModStatusMessageTimer ~= nil then
        Ext.Timer.Cancel(State.Session.ModStatusMessageTimer)
        State.Session.ModStatusMessageTimer = nil
    end
    Ext.Timer.WaitFor(50, function ()
        Osi.QuestMessageShow("ModStatusMessage", message)
        State.Session.ModStatusMessageTimer = Ext.Timer.WaitFor(Constants.MOD_STATUS_MESSAGE_DURATION, function ()
            Osi.QuestMessageHide("ModStatusMessage")
        end)
    end)
end

local function setAwaitingTarget(uuid, isAwaitingTarget)
    if uuid ~= nil then
        State.Session.AwaitingTarget[uuid] = isAwaitingTarget
        Ext.ServerNet.PostMessageToClient(uuid, "AwaitingTarget", (isAwaitingTarget == true) and "1" or "0")
    end
end

local function disableCompanionAI()
    debugPrint("companion ai disabled")
    State.Settings.CompanionAIEnabled = false
    local players = State.Session.Players
    for playerUuid, player in pairs(players) do
        local level = Osi.GetRegion(playerUuid)
        if level and State.Session.Brawlers and State.Session.Brawlers[level] and State.Session.Brawlers[level][playerUuid] then
            Utils.clearOsirisQueue(playerUuid)
            stopPulseAction(State.Session.Brawlers[level][playerUuid])
        end
    end
    modStatusMessage("Companion AI Disabled")
end

local function enableCompanionAI()
    debugPrint("companion ai enabled")
    State.Settings.CompanionAIEnabled = true
    local players = State.Session.Players
    if players and State.areAnyPlayersBrawling() then
        for playerUuid, player in pairs(players) do
            if not State.isPlayerControllingDirectly(playerUuid) then
                Roster.addBrawler(playerUuid, true, true)
            end
        end
    end
    modStatusMessage("Companion AI Enabled")
end

local function disableFullAuto()
    debugPrint("full auto disabled")
    State.Settings.FullAuto = false
    local players = State.Session.Players
    for playerUuid, player in pairs(players) do
        if State.isPlayerControllingDirectly(playerUuid) then
            local level = Osi.GetRegion(playerUuid)
            if level and State.Session.Brawlers and State.Session.Brawlers[level] and State.Session.Brawlers[level][playerUuid] then
                Utils.clearOsirisQueue(playerUuid)
                stopPulseAction(State.Session.Brawlers[level][playerUuid])
            end
        end
    end
    modStatusMessage("Full Auto Disabled")
end

local function enableFullAuto()
    debugPrint("full auto enabled")
    State.Settings.FullAuto = true
    local players = State.Session.Players
    if players and State.areAnyPlayersBrawling() then
        for playerUuid, player in pairs(players) do
            Roster.addBrawler(playerUuid, true, true)
        end
    end
    modStatusMessage("Full Auto Enabled")
end

local function toggleCompanionAI()
    if State.Settings.CompanionAIEnabled then
        disableCompanionAI()
    else
        enableCompanionAI()
    end
end

local function toggleFullAuto()
    if State.Settings.FullAuto then
        disableFullAuto()
    else
        enableFullAuto()
    end
end

local function disableMod()
    State.Settings.ModEnabled = false
    Listeners.stopListeners()
    if State.Settings.TurnBasedSwarmMode then
        State.removeBoostPlayerInitiatives()
    end
    modStatusMessage("Brawl Disabled")
end

local function enableMod()
    State.Settings.ModEnabled = true
    Listeners.startListeners()
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
        Listeners.onStarted(level)
    end
    modStatusMessage("Brawl Enabled")
end

local function toggleMod()
    if State.Settings.ModEnabled then
        disableMod()
    else
        enableMod()
    end
end

local function getAdjustedDistanceTo(sourcePos, targetPos, sourceForwardX, sourceForwardY, sourceForwardZ)
    local deltaX = targetPos[1] - sourcePos[1]
    local deltaY = targetPos[2] - sourcePos[2]
    local deltaZ = targetPos[3] - sourcePos[3]
    local squaredDistance = deltaX*deltaX + deltaY*deltaY + deltaZ*deltaZ
    if squaredDistance < 1600 then -- 40^2 = 1600
        local distance = math.sqrt(squaredDistance)
        local vecToTargetX = deltaX/distance
        local vecToTargetY = deltaY/distance
        local vecToTargetZ = deltaZ/distance
        local dotProduct = sourceForwardX*vecToTargetX + sourceForwardY*vecToTargetY + sourceForwardZ*vecToTargetZ
        local weight = 0.5 -- on (0, 1)
        local adjustedDistance = distance*(1 + dotProduct*weight)
        if adjustedDistance < 0 then
            adjustedDistance = 0
        end
        debugPrint("Raw distance", distance, "dotProduct", dotProduct, "adjustedDistance", adjustedDistance)
        return adjustedDistance
    end
    return nil
end

local function buildClosestEnemyBrawlers(playerUuid)
    if State.Session.PlayerMarkedTarget[playerUuid] and not isAliveAndCanFight(State.Session.PlayerMarkedTarget[playerUuid]) then
        State.Session.PlayerMarkedTarget[playerUuid] = nil
    end
    local playerEntity = Ext.Entity.Get(playerUuid)
    local playerPos = playerEntity.Transform.Transform.Translate
    local playerForwardX, playerForwardY, playerForwardZ = Utils.getForwardVector(playerUuid)
    local maxTargets = 10
    local topTargets = {}
    local level = Osi.GetRegion(playerUuid)
    local brawlersInLevel = State.Session.Brawlers[level]
    if brawlersInLevel then
        for brawlerUuid, brawler in pairs(brawlersInLevel) do
            if isOnSameLevel(brawlerUuid, playerUuid) and isAliveAndCanFight(brawlerUuid) and isPugnacious(brawlerUuid, playerUuid) then
                local brawlerEntity = Ext.Entity.Get(brawlerUuid)
                if brawlerEntity then
                    local adjustedDistance = getAdjustedDistanceTo(playerPos, brawlerEntity.Transform.Transform.Translate, playerForwardX, playerForwardY, playerForwardZ)
                    if adjustedDistance ~= nil then
                        local inserted = false
                        for i = 1, #topTargets do
                            if adjustedDistance < topTargets[i].adjustedDistance then
                                table.insert(topTargets, i, {uuid = brawlerUuid, adjustedDistance = adjustedDistance})
                                inserted = true
                                break
                            end
                        end
                        if not inserted and #topTargets < maxTargets then
                            table.insert(topTargets, {uuid = brawlerUuid, adjustedDistance = adjustedDistance})
                        end
                        if #topTargets > maxTargets then
                            topTargets[#topTargets] = nil
                        end
                    end
                end
            end
        end
    end
    State.Session.ClosestEnemyBrawlers[playerUuid] = {}
    for i, target in ipairs(topTargets) do
        State.Session.ClosestEnemyBrawlers[playerUuid][i] = target.uuid
    end
    if #State.Session.ClosestEnemyBrawlers[playerUuid] > 0 and State.Session.PlayerMarkedTarget[playerUuid] == nil then
        State.Session.PlayerMarkedTarget[playerUuid] = State.Session.ClosestEnemyBrawlers[playerUuid][1]
    end
    debugPrint("Closest enemy brawlers to player", playerUuid, getDisplayName(playerUuid))
    debugDump(State.Session.ClosestEnemyBrawlers)
    debugPrint("Current target:", State.Session.PlayerMarkedTarget[playerUuid])
    Ext.Timer.WaitFor(3000, function ()
        State.Session.ClosestEnemyBrawlers[playerUuid] = nil
    end)
end

local function selectNextEnemyBrawler(playerUuid, isNext)
    local nextTargetIndex = nil
    local nextTargetUuid = nil
    local closestEnemyBrawlers = State.Session.ClosestEnemyBrawlers[playerUuid]
    for enemyBrawlerIndex, enemyBrawlerUuid in ipairs(closestEnemyBrawlers) do
        if State.Session.PlayerMarkedTarget[playerUuid] == enemyBrawlerUuid then
            debugPrint("found current target", State.Session.PlayerMarkedTarget[playerUuid], enemyBrawlerUuid, enemyBrawlerIndex, closestEnemyBrawlers[enemyBrawlerIndex])
            if isNext then
                debugPrint("getting NEXT target")
                if enemyBrawlerIndex < #closestEnemyBrawlers then
                    nextTargetIndex = enemyBrawlerIndex + 1
                else
                    nextTargetIndex = 1
                end
            else
                debugPrint("getting PREVIOUS target")
                if enemyBrawlerIndex > 1 then
                    nextTargetIndex = enemyBrawlerIndex - 1
                else
                    nextTargetIndex = #closestEnemyBrawlers
                end
            end
            debugPrint("target index", nextTargetIndex)
            debugDump(State.Session.ClosestEnemyBrawlers)
            nextTargetUuid = closestEnemyBrawlers[nextTargetIndex]
            debugPrint("target uuid", nextTargetUuid)
            break
        end
    end
    if nextTargetUuid then
        if State.Session.PlayerMarkedTarget[playerUuid] ~= nil then
            Osi.RemoveStatus(State.Session.PlayerMarkedTarget[playerUuid], "LOW_HAG_MUSHROOM_VFX")
        end
        debugPrint("pinging next target", nextTargetUuid)
        local x, y, z = Osi.GetPosition(nextTargetUuid)
        Osi.RequestPing(x, y, z, nextTargetUuid, playerUuid)
        Osi.ApplyStatus(nextTargetUuid, "LOW_HAG_MUSHROOM_VFX", -1)
        State.Session.PlayerMarkedTarget[playerUuid] = nextTargetUuid
    end
end

local function targetCloserOrFartherEnemy(data, targetFartherEnemy)
    local player = State.getPlayerByUserId(Utils.peerToUserId(data.UserID))
    if player then
        local brawler = Roster.getBrawlerByUuid(player.uuid)
        if brawler and not brawler.isPaused then
            buildClosestEnemyBrawlers(player.uuid)
            if State.Session.ClosestEnemyBrawlers[player.uuid] ~= nil and next(State.Session.ClosestEnemyBrawlers[player.uuid]) ~= nil then
                debugPrint("Selecting next enemy brawler")
                selectNextEnemyBrawler(player.uuid, targetFartherEnemy)
            end
        end
    end
end

local function lockCompanionsOnTarget(level, targetUuid)
    if targetUuid and isAliveAndCanFight(targetUuid) then
        local players = State.Session.Players
        local brawlersInLevel = State.Session.Brawlers[level]
        for uuid, _ in pairs(players) do
            if isAliveAndCanFight(uuid) and (not State.isPlayerControllingDirectly(uuid) or State.Settings.FullAuto) then
                if not brawlersInLevel[uuid] then
                    Roster.addBrawler(uuid, true)
                end
                if brawlersInLevel[uuid] and uuid ~= targetUuid then
                    brawlersInLevel[uuid].targetUuid = targetUuid
                    brawlersInLevel[uuid].lockedOnTarget = true
                    debugPrint("Set target to", uuid, getDisplayName(uuid), targetUuid, getDisplayName(targetUuid))
                end
            end
        end
    end
end

local function allCompanionsDisableLockedOnTarget()
    local players = State.Session.Players
    if players then
        for uuid, _ in pairs(players) do
            Roster.disableLockedOnTarget(uuid)
        end
    end
end

local function setAttackMoveTarget(playerUuid, targetUuid)
    debugPrint("Set attack-move target", playerUuid, targetUuid)
    setAwaitingTarget(playerUuid, false)
    local level = Osi.GetRegion(playerUuid)
    if level and targetUuid and not Utils.isPlayerOrAlly(targetUuid) and State.Session.Brawlers and State.Session.Brawlers[level] then
        Utils.applyAttackMoveTargetVfx(targetUuid)
        if not State.Session.Brawlers[level][targetUuid] then
            Roster.addBrawler(targetUuid, true)
        end
        lockCompanionsOnTarget(level, targetUuid)
    end
end

local function getSpellNameBySlot(uuid, slot)
    local entity = Ext.Entity.Get(uuid)
    -- NB: is this always index 6?
    if entity and entity.HotbarContainer and entity.HotbarContainer.Containers and entity.HotbarContainer.Containers.DefaultBarContainer then
        local customBar = entity.HotbarContainer.Containers.DefaultBarContainer[6]
        local spellName = nil
        for _, element in ipairs(customBar.Elements) do
            if element.Slot == slot then
                if element.SpellId then
                    return element.SpellId.OriginatorPrototype
                else
                    return nil
                end
            end
        end
    end
end

local function onActionButton(data, isController)
    local player = State.getPlayerByUserId(Utils.peerToUserId(data.UserID))
    if player then
        -- controllers don't have many buttons, so we only want the actionbar hotkeys to trigger actions if we're in a fight and not paused
        if isController then
            local brawler = Roster.getBrawlerByUuid(player.uuid)
            if not brawler or brawler.isPaused then
                return
            end
        end
        local actionButtonLabel = tonumber(data.Payload)
        if Constants.ACTION_BUTTON_TO_SLOT[actionButtonLabel] ~= nil and isAliveAndCanFight(player.uuid) then
            local spellName = getSpellNameBySlot(player.uuid, Constants.ACTION_BUTTON_TO_SLOT[actionButtonLabel])
            if spellName ~= nil then
                local spell = State.getSpellByName(spellName)
                -- NB: maintain separate friendly target list for healing/buffs?
                if spell ~= nil and (spell.type == "Buff" or spell.type == "Healing") then
                    return Resources.useSpellAndResources(player.uuid, player.uuid, spellName)
                end
                -- if Utils.isZoneSpell(spellName) or Utils.isProjectileSpell(spellName) then
                --     return Resources.useSpellAndResources(player.uuid, nil, spellName)
                -- end
                if State.Session.PlayerMarkedTarget[player.uuid] == nil or Osi.IsDead(State.Session.PlayerMarkedTarget[player.uuid]) == 1 then
                    buildClosestEnemyBrawlers(player.uuid)
                end
                return Resources.useSpellAndResources(player.uuid, State.Session.PlayerMarkedTarget[player.uuid], spellName)
            end
        end
    end
end

local function onAttackMyTarget(data)
    if State.Session.Players and State.Session.Brawlers then
        local player = State.getPlayerByUserId(Utils.peerToUserId(data.UserID))
        local level = Osi.GetRegion(player.uuid)
        if level and State.Session.Brawlers[level] and Osi.IsInForceTurnBasedMode(player.uuid) == 0 then
            local currentTarget
            if State.Session.PlayerMarkedTarget[player.uuid] then
                currentTarget = State.Session.PlayerMarkedTarget[player.uuid]
            elseif State.Session.IsAttackingOrBeingAttackedByPlayer[player.uuid] then
                currentTarget = State.Session.IsAttackingOrBeingAttackedByPlayer[player.uuid]
            elseif State.Session.PlayerCurrentTarget[player.uuid] then
                currentTarget = State.Session.PlayerCurrentTarget[player.uuid]
            end
            debugPrint("Got current player's target", currentTarget)
            setAttackMoveTarget(player.uuid, currentTarget)
        end
    end
end

local function onClickPosition(data)
    local player = State.getPlayerByUserId(Utils.peerToUserId(data.UserID))
    if player and player.uuid then
        local playerUuid = player.uuid
        local clickPosition = Ext.Json.Parse(data.Payload)
        if clickPosition then
            State.Session.LastClickPosition[playerUuid] = {position = clickPosition.position}
            if State.Session.AwaitingTarget[playerUuid] and clickPosition.uuid then
                setAttackMoveTarget(playerUuid, clickPosition.uuid)
            elseif clickPosition.position and State.Session.AwaitingTarget[playerUuid] then
                Movement.findPathToPosition(playerUuid, clickPosition.position, function (err, validPosition)
                    if err then
                        return Utils.showNotification(playerUuid, err, 2)
                    end
                    setAwaitingTarget(playerUuid, false)
                    allCompanionsDisableLockedOnTarget()
                    Utils.applyAttackMoveTargetVfx(Utils.createDummyObject(validPosition))
                    Movement.moveCompanionsToPosition(validPosition)
                end)
            end
        end
    end
end

local function onCancelQueuedMovement(data)
    local player = State.getPlayerByUserId(Utils.peerToUserId(data.UserID))
    if player and player.uuid then
        Pause.cancelQueuedMovement(player.uuid)
    end
end

local function onOnMe(data)
    if State.Session.Players then
        local player = State.getPlayerByUserId(Utils.peerToUserId(data.UserID))
        if player and player.uuid and Osi.IsInForceTurnBasedMode(player.uuid) == 0 then
            Utils.applyOnMeTargetVfx(player.uuid)
            Movement.moveCompanionsToPlayer(player.uuid)
        end
    end
end

local function onAttackMove(data)
    if State.Session.Players then
        local player = State.getPlayerByUserId(Utils.peerToUserId(data.UserID))
        if player and player.uuid and Osi.IsInForceTurnBasedMode(player.uuid) == 0 then
            setAwaitingTarget(player.uuid, true)
        end
    end
end

local function onRequestHeal(data)
    debugPrint("Requesting Heal")
    local userId = Utils.peerToUserId(data.UserID)
    if userId then
        if State.Session.HealRequestedTimer[userId] then
            Ext.Timer.Cancel(State.Session.HealRequestedTimer[userId])
            State.Session.HealRequestedTimer[userId] = nil
        end
        local player = State.getPlayerByUserId(userId)
        if player and player.uuid then
            State.Session.HealRequested[userId] = true
            Roster.addPlayersInEnterCombatRangeToBrawlers(player.uuid)
            State.Session.HealRequestedTimer[userId] = Ext.Timer.WaitFor(9000, function ()
                State.Session.HealRequested[userId] = false
            end)
        end
    end
end

local function onChangeTactics(data)
    for i, tactics in ipairs(Constants.COMPANION_TACTICS) do
        if tactics == State.Settings.CompanionTactics then
            State.Settings.CompanionTactics = Constants.COMPANION_TACTICS[(i % #Constants.COMPANION_TACTICS) + 1]
            break
        end
    end
    if MCM then
        MCM.Set("companion_tactics", State.Settings.CompanionTactics)
    end
    modStatusMessage(State.Settings.CompanionTactics .. " Tactics")
end

local function onModToggle(data)
    if MCM then
        MCM.Set("mod_enabled", not State.Settings.ModEnabled)
    end
    toggleMod()
end

local function onCompanionAIToggle(data)
    if MCM then
        MCM.Set("companion_ai_enabled", not State.Settings.CompanionAIEnabled)
    end
    toggleCompanionAI()
end

local function onQueueCompanionAIActions(data)
    Pause.queueCompanionAIActions()
end

local function onFullAutoToggle(data)
    if MCM then
        MCM.Set("full_auto", not State.Settings.FullAuto)
    end
    toggleFullAuto()
end

local function onLeaderboardToggle(data)
    Leaderboard.showForUser(data.UserID)
end

local function onMCMModEnabled(value)
    State.Settings.ModEnabled = value
    if State.Settings.ModEnabled then
        enableMod()
    else
        disableMod()
    end
end

local function onMCMCompanionAIEnabled(value)
    State.Settings.CompanionAIEnabled = value
    if State.Settings.CompanionAIEnabled then
        enableCompanionAI()
    else
        disableCompanionAI()
    end
end

local function onMCMTruePause(value)
    State.Settings.TruePause = value
    Pause.checkTruePauseParty()
end

local function onMCMHitpointsMultiplier(value)
    State.Settings.HitpointsMultiplier = value
    State.setupPartyMembersHitpoints()
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if State.Session.Brawlers then
        local brawlersInLevel = State.Session.Brawlers[level]
        if brawlersInLevel then
            for brawlerUuid, brawler in pairs(brawlersInLevel) do
                State.revertHitpoints(brawlerUuid)
                State.modifyHitpoints(brawlerUuid)
            end
        end
    end
end

local function onMCMFullAuto(value)
    State.Settings.FullAuto = value
    if State.Settings.FullAuto then
        enableFullAuto()
    else
        disableFullAuto()
    end
end

local function onMCMActiveCharacterArchetype(archetype)
    local uuid = Osi.GetHostCharacter()
    if uuid ~= nil and archetype ~= nil and archetype ~= "" then
        local modVars = Ext.Vars.GetModVariables(ModuleUUID)
        if modVars.PartyArchetypes == nil then
            modVars.PartyArchetypes = {}
        end
        local partyArchetypes = modVars.PartyArchetypes
        partyArchetypes[uuid] = archetype
        modVars.PartyArchetypes = partyArchetypes
        local brawler = Roster.getBrawlerByUuid(uuid)
        if brawler ~= nil then
            brawler.archetype = archetype
        end
    end
end

local function onMCMMaxPartySize(maxPartySize)
    State.Settings.MaxPartySize = maxPartySize
    State.setMaxPartySize()
end

local function onMCMTurnBasedSwarmMode(value)
    State.Settings.TurnBasedSwarmMode = value
    if value == true then
        stopAllPulseAddNearbyTimers()
        stopAllPulseRepositionTimers()
        stopAllPulseActionTimers()
        stopAllBrawlFizzlers()
        local hostCharacter = Osi.GetHostCharacter()
        if hostCharacter then
            local level = Osi.GetRegion(hostCharacter)
            if level then
                Roster.endBrawl(level)
            end
        end
        State.boostPlayerInitiatives()
        State.recapPartyMembersMovementDistances()
    else
        State.removeBoostPlayerInitiatives()
        State.uncapPartyMembersMovementDistances()
        disableMod()
        enableMod()
    end
end

return {
    setAwaitingTarget = setAwaitingTarget,
    enableMod = enableMod,
    disableMod = disableMod,
    NetMessage = {
        ModToggle = onModToggle,
        CompanionAIToggle = onCompanionAIToggle,
        QueueCompanionAIActions = onQueueCompanionAIActions,
        FullAutoToggle = onFullAutoToggle,
        LeaderboardToggle = onLeaderboardToggle,
        ExitFTB = function (_) Pause.allExitFTB() end,
        EnterFTB = function (_) Pause.allEnterFTB() end,
        ClickPosition = onClickPosition,
        CancelQueuedMovement = onCancelQueuedMovement,
        ActionButton = function (data) onActionButton(data, false) end,
        ControllerActionButton = function (data) onActionButton(data, true) end,
        TargetCloserEnemy = function (data) targetCloserOrFartherEnemy(data, false) end,
        TargetFartherEnemy = function (data) targetCloserOrFartherEnemy(data, true) end,
        OnMe = onOnMe,
        AttackMyTarget = onAttackMyTarget,
        AttackMove = onAttackMove,
        RequestHeal = onRequestHeal,
        ChangeTactics = onChangeTactics,
    },
    MCMSettingSaved = {
        mod_enabled = onMCMModEnabled,
        companion_ai_enabled = onMCMCompanionAIEnabled,
        true_pause = onMCMTruePause,
        auto_pause_on_downed = function (v) State.Settings.AutoPauseOnDowned = v end,
        action_interval = function (v) State.Settings.ActionInterval = v end,
        initiative_die = function (v) State.Settings.InitiativeDie = v end,
        hitpoints_multiplier = onMCMHitpointsMultiplier,
        full_auto = onMCMFullAuto,
        active_character_archetype = onMCMActiveCharacterArchetype,
        companion_tactics = function (v) State.Settings.CompanionTactics = v end,
        defensive_tactics_max_distance = function (v) State.Settings.DefensiveTacticsMaxDistance = v end,
        companion_ai_max_spell_level = function (v) State.Settings.CompanionAIMaxSpellLevel = v end,
        hogwild_mode = function (v) State.Settings.HogwildMode = v end,
        max_party_size = onMCMMaxPartySize,
        turn_based_swarm_mode = onMCMTurnBasedSwarmMode,
        leaderboard_enabled = function (v) State.Settings.LeaderboardEnabled = v end,
    },
}
