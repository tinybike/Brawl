local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump

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

local function setAwaitingTarget(uuid, awaitingTarget)
    if uuid ~= nil then
        State.Session.AwaitingTarget[uuid] = awaitingTarget
        Ext.ServerNet.PostMessageToClient(uuid, "AwaitingTarget", awaitingTarget and "1" or "0")
    end
end

local function disableCompanionAI()
    debugPrint("companion ai disabled")
    State.Settings.CompanionAIEnabled = false
    local players = State.Session.Players
    for playerUuid, player in pairs(players) do
        local level = M.Osi.GetRegion(playerUuid)
        if level and State.Session.Brawlers and State.Session.Brawlers[level] and State.Session.Brawlers[level][playerUuid] then
            Utils.clearOsirisQueue(playerUuid)
            RT.Timers.stopPulseAction(State.Session.Brawlers[level][playerUuid])
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
                Roster.addBrawler(playerUuid, true)
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
            local level = M.Osi.GetRegion(playerUuid)
            if level and State.Session.Brawlers and State.Session.Brawlers[level] and State.Session.Brawlers[level][playerUuid] then
                Utils.clearOsirisQueue(playerUuid)
                RT.Timers.stopPulseAction(State.Session.Brawlers[level][playerUuid])
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
            Roster.addBrawler(playerUuid, true)
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

local function disableMod(noNotify)
    State.Settings.ModEnabled = false
    Listeners.stopListeners()
    Movement.removeAllDashSpeedBoosts()
    if Printer then Printer:Stop() end
    if not noNotify then
        modStatusMessage("Brawl Disabled")
    end
end

local function enableMod(noNotify)
    State.Settings.ModEnabled = true
    Listeners.startListeners()
    local level = M.Osi.GetRegion(M.Osi.GetHostCharacter())
    if level then
        Listeners.onStarted(level)
    end
    -- if Printer then Printer:Start() end
    if not noNotify then
        modStatusMessage("Brawl Enabled")
    end
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
    local maxTargets = 10
    if State.Session.PlayerMarkedTarget[playerUuid] and not M.Utils.isAliveAndCanFight(State.Session.PlayerMarkedTarget[playerUuid]) then
        State.Session.PlayerMarkedTarget[playerUuid] = nil
    end
    local playerEntity = Ext.Entity.Get(playerUuid)
    local playerPos = playerEntity.Transform.Transform.Translate
    local playerForwardX, playerForwardY, playerForwardZ = M.Utils.getForwardVector(playerUuid)
    local topTargets = {}
    local level = M.Osi.GetRegion(playerUuid)
    local brawlersInLevel = State.Session.Brawlers[level]
    if brawlersInLevel then
        for brawlerUuid, brawler in pairs(brawlersInLevel) do
            if M.Utils.isAliveAndCanFight(brawlerUuid) and M.Utils.isPugnacious(brawlerUuid, playerUuid) then
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
    debugPrint("Closest enemy brawlers to player", playerUuid, M.Utils.getDisplayName(playerUuid))
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
    if not closestEnemyBrawlers then return end
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
        local x, y, z = M.Osi.GetPosition(nextTargetUuid)
        Osi.RequestPing(x, y, z, nextTargetUuid, playerUuid)
        Osi.ApplyStatus(nextTargetUuid, "LOW_HAG_MUSHROOM_VFX", -1)
        State.Session.PlayerMarkedTarget[playerUuid] = nextTargetUuid
    end
end

local function targetCloserOrFartherEnemy(data, targetFartherEnemy)
    local player = State.getPlayerByUserId(Utils.peerToUserId(data.UserID))
    if player then
        local brawler = M.Roster.getBrawlerByUuid(player.uuid)
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
    if targetUuid and M.Utils.isAliveAndCanFight(targetUuid) then
        local players = State.Session.Players
        local brawlersInLevel = State.Session.Brawlers[level]
        for uuid, _ in pairs(players) do
            if M.Utils.isAliveAndCanFight(uuid) and (not State.isPlayerControllingDirectly(uuid) or State.Settings.FullAuto) then
                if not brawlersInLevel[uuid] then
                    Roster.addBrawler(uuid)
                end
                if brawlersInLevel[uuid] and uuid ~= targetUuid then
                    brawlersInLevel[uuid].targetUuid = targetUuid
                    brawlersInLevel[uuid].lockedOnTarget = true
                    -- New explicit attack-move overrides any in-flight strict-move suppression.
                    brawlersInLevel[uuid].suppressPulseEventUuid = nil
                    debugPrint("Set target to", uuid, M.Utils.getDisplayName(uuid), targetUuid, M.Utils.getDisplayName(targetUuid))
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
    local level = M.Osi.GetRegion(playerUuid)
    if level and targetUuid and not M.Utils.isPlayerOrAlly(targetUuid) and State.Session.Brawlers and State.Session.Brawlers[level] then
        Utils.applyAttackMoveTargetVfx(targetUuid)
        if not State.Session.Brawlers[level][targetUuid] then
            Roster.addBrawler(targetUuid)
        end
        lockCompanionsOnTarget(level, targetUuid)
    end
end

local function onActionButton(data, isController)
    local player = State.getPlayerByUserId(Utils.peerToUserId(data.UserID))
    if player then
        -- controllers don't have many buttons, so we only want the actionbar hotkeys to trigger actions if we're in a fight and not paused
        if isController then
            local brawler = M.Roster.getBrawlerByUuid(player.uuid)
            if not brawler or brawler.isPaused then
                return
            end
        end
        local actionButtonLabel = tonumber(data.Payload)
        if Constants.ACTION_BUTTON_TO_SLOT[actionButtonLabel] ~= nil and M.Utils.isAliveAndCanFight(player.uuid) then
            local spellName = M.Utils.getSpellNameBySlot(player.uuid, Constants.ACTION_BUTTON_TO_SLOT[actionButtonLabel])
            if spellName ~= nil then
                local spell = M.Spells.getSpellByName(spellName)
                -- NB: maintain separate friendly target list for healing/buffs?
                if spell ~= nil and (spell.type == "Buff" or spell.type == "Healing") then
                    return Actions.useSpellOnTarget(player.uuid, player.uuid, spellName, true)
                end
                -- TODO need zone logic here
                -- if M.Utils.isZoneSpell(spellName) or M.Utils.isProjectileSpell(spellName) then
                --     return Actions.useSpellOnTarget(player.uuid, nil, spellName)
                -- end
                local target = State.Session.PlayerMarkedTarget[player.uuid]
                if target == nil or M.Osi.IsDead(target) == 1 then
                    buildClosestEnemyBrawlers(player.uuid)
                    target = State.Session.PlayerMarkedTarget[player.uuid]
                end
                if target == nil then return end
                return Actions.useSpellOnTarget(player.uuid, target, spellName, M.Utils.isPugnacious(player.uuid, target))
            end
        end
    end
end

local function onAttackMyTarget(data)
    if State.Settings.TurnBasedSwarmMode and Utils.getCombatEntity() then
        return false
    end
    if State.Session.Players and State.Session.Brawlers then
        local player = State.getPlayerByUserId(Utils.peerToUserId(data.UserID))
        if not player or not player.uuid then return end
        local level = M.Osi.GetRegion(player.uuid)
        if level and State.Session.Brawlers[level] and M.Osi.IsInForceTurnBasedMode(player.uuid) == 0 then
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

-- Strict click-to-move: every companion converges on the validated position with pulse-suppression in flight
local function executeMoveParty(playerUuid, position)
    M.Movement.findPathToPosition(playerUuid, position, function (err, validPosition)
        if err then
            return Utils.showNotification(playerUuid, err)
        end
        Utils.applyAttackMoveTargetVfx(Utils.createDummyObject(validPosition))
        local level = M.Osi.GetRegion(playerUuid)
        local brawlersInLevel = level and State.Session.Brawlers[level]
        -- Collect companions and spread them in a semicircle behind the leader so the active char ends up at the front of the formation.
        local companions = {}
        for uuid, _ in pairs(State.Session.Players) do
            if not State.isPlayerControllingDirectly(uuid) then
                companions[#companions + 1] = uuid
            end
        end
        local n = #companions
        local fx, fz = Movement.computeForwardVector(playerUuid, validPosition)
        for i, uuid in ipairs(companions) do
            local brawler = brawlersInLevel and brawlersInLevel[uuid]
            if brawler then
                brawler.lockedOnTarget = false
            end
            local target = Movement.getRearGuardPosition(validPosition, fx, fz, i, n, Constants.COMPANION_FORMATION_RADIUS)
            local companionUuid = uuid
            local eventUuid = Movement.moveToPosition(uuid, target, true, function ()
                local b = M.Roster.getBrawlerByUuid(companionUuid)
                if b then
                    RT.Timers.stopPulseAction(b)
                    RT.Timers.startPulseAction(b, 0)
                end
            end)
            if brawler and eventUuid then
                brawler.suppressPulseEventUuid = eventUuid
            end
        end
        if not State.Settings.FullAuto then
            Movement.moveToPosition(playerUuid, validPosition, true)
        end
    end)
end

local function onClickPosition(data)
    local player = State.getPlayerByUserId(Utils.peerToUserId(data.UserID))
    if player and player.uuid then
        local playerUuid = player.uuid
        local clickPosition = Ext.Json.Parse(data.Payload)
        if clickPosition then
            State.Session.LastClickPosition[playerUuid] = {position = clickPosition.position}
            -- Don't process pending command-confirm clicks while paused (and clear awaiting target, if it's already set)
            if M.Osi.IsInForceTurnBasedMode(playerUuid) == 1 then
                if State.Session.AwaitingTarget[playerUuid] then
                    setAwaitingTarget(playerUuid, false)
                end
                return
            end
            local awaiting = State.Session.AwaitingTarget[playerUuid]
            if awaiting == "move_party" and clickPosition.position then
                setAwaitingTarget(playerUuid, false)
                executeMoveParty(playerUuid, clickPosition.position)
            elseif awaiting and clickPosition.uuid then
                -- setAttackMoveTarget only actually engages companions on valid enemies;
                -- regardless of validity, everyone (companions + active char) should still
                -- move toward the clicked target.
                setAttackMoveTarget(playerUuid, clickPosition.uuid)
                Movement.moveCompanionsToTargetUuid(clickPosition.uuid)
                if not State.Settings.FullAuto then
                    Movement.moveToTargetUuid(playerUuid, clickPosition.uuid, true)
                end
            elseif clickPosition.position and awaiting then
                M.Movement.findPathToPosition(playerUuid, clickPosition.position, function (err, validPosition)
                    if err then
                        return Utils.showNotification(playerUuid, err)
                    end
                    setAwaitingTarget(playerUuid, false)
                    allCompanionsDisableLockedOnTarget()
                    -- Open-ground attack-move overrides any in-flight strict-move suppression.
                    local level = M.Osi.GetRegion(playerUuid)
                    local brawlersInLevel = level and State.Session.Brawlers[level]
                    if brawlersInLevel then
                        for uuid, _ in pairs(State.Session.Players) do
                            if brawlersInLevel[uuid] then
                                brawlersInLevel[uuid].suppressPulseEventUuid = nil
                            end
                        end
                    end
                    Utils.applyAttackMoveTargetVfx(Utils.createDummyObject(validPosition))
                    Movement.moveCompanionsToPosition(validPosition, playerUuid)
                    -- Also move the active character to the position
                    if not State.Settings.FullAuto then
                        Movement.moveToPosition(playerUuid, validPosition, true)
                    end
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
    if State.Settings.TurnBasedSwarmMode and Utils.getCombatEntity() then
        return false
    end
    if State.Session.Players then
        local player = State.getPlayerByUserId(Utils.peerToUserId(data.UserID))
        if player and player.uuid and M.Osi.IsInForceTurnBasedMode(player.uuid) == 0 then
            Utils.applyOnMeTargetVfx(player.uuid)
            -- Strict move: pulse must not engage en route.  Clear any prior locked-on so post-arrival the AI re-evaluates fresh rather than peeling
            -- back to a stale lock.  Per-companion eventUuid tags the in-flight move so the suppression auto-clears when the move ends.
            local level = M.Osi.GetRegion(player.uuid)
            local brawlersInLevel = level and State.Session.Brawlers[level]
            for uuid, _ in pairs(State.Session.Players) do
                if not State.isPlayerControllingDirectly(uuid) then
                    local brawler = brawlersInLevel and brawlersInLevel[uuid]
                    if brawler then
                        brawler.lockedOnTarget = false
                    end
                    -- onCompleted: stop the (suppressed, mid-cycle) pulse timer and restart it with delay 0, so the AI doesn't sit idle waiting
                    -- for the next periodic tick.  finishMovement clears ActiveMovements[eventUuid] first, so the restarted pulse's suppression
                    -- check falls through and AI.act runs.  Re-phases the periodic cadence to the arrival moment.
                    local companionUuid = uuid
                    local eventUuid = Movement.moveToTargetUuid(uuid, player.uuid, true, function ()
                        local b = M.Roster.getBrawlerByUuid(companionUuid)
                        if b then
                            RT.Timers.stopPulseAction(b)
                            RT.Timers.startPulseAction(b, 0)
                        end
                    end)
                    if brawler and eventUuid then
                        brawler.suppressPulseEventUuid = eventUuid
                    end
                end
            end
        end
    end
end

local function onAttackMove(data)
    if State.Settings.TurnBasedSwarmMode and Utils.getCombatEntity() then
        return false
    end
    if State.Session.Players then
        local player = State.getPlayerByUserId(Utils.peerToUserId(data.UserID))
        if player and player.uuid and M.Osi.IsInForceTurnBasedMode(player.uuid) == 0 then
            setAwaitingTarget(player.uuid, true)
        end
    end
end

-- Empty payload = hotkey press (set AwaitingTarget, next click confirms)
-- Position payload = chord/follow-up click (execute now)
local function onMoveParty(data)
    if State.Settings.TurnBasedSwarmMode and Utils.getCombatEntity() then
        return false
    end
    if State.Session.Players then
        local player = State.getPlayerByUserId(Utils.peerToUserId(data.UserID))
        if player and player.uuid and M.Osi.IsInForceTurnBasedMode(player.uuid) == 0 then
            if data.Payload and data.Payload ~= "" then
                local positionInfo = Ext.Json.Parse(data.Payload)
                if positionInfo and positionInfo.position then
                    -- Chord supersedes any pending AwaitingTarget so a stale primed command can't fire on the next click.
                    if State.Session.AwaitingTarget[player.uuid] then
                        setAwaitingTarget(player.uuid, false)
                    end
                    executeMoveParty(player.uuid, positionInfo.position)
                end
            else
                setAwaitingTarget(player.uuid, "move_party")
            end
        end
    end
end

local function onRequestHeal(data)
    if State.Settings.TurnBasedSwarmMode and Utils.getCombatEntity() then
        return false
    end
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

local function onLeaderboardSetEnabled(data)
    local enabled = (data.Payload == "true")
    State.Settings.LeaderboardEnabled = enabled
    MCM.Set("leaderboard_enabled", enabled)
    Leaderboard.showForUser(data.UserID)
end

-- Find the character a given user is currently controlling.
local function getControlledForUser(userId)
    if not State.Session.Players then return nil end
    for uuid, player in pairs(State.Session.Players) do
        if player.userId == userId and player.isControllingDirectly then
            return uuid
        end
    end
    return nil
end

-- Set the stored archetype override for any character (mod var + live brawler if present).  Empty string clears the override.
local function setCharacterArchetype(uuid, archetype)
    if not uuid then return end
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    if modVars.PartyArchetypes == nil then modVars.PartyArchetypes = {} end
    local partyArchetypes = modVars.PartyArchetypes
    partyArchetypes[uuid] = archetype  -- "" means cleared
    modVars.PartyArchetypes = partyArchetypes
    local brawler = M.Roster.getBrawlerByUuid(uuid)
    if brawler then
        if archetype == "" or archetype == nil then
            brawler.rage = nil
            brawler.archetype = State.getArchetype(uuid)
        else
            brawler.rage = (archetype == "barbarian") and Spells.getRageAbility(uuid) or nil
            brawler.archetype = archetype
        end
    end
end

local function getCharacterArchetype(uuid)
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    if not modVars.PartyArchetypes then return "" end
    return modVars.PartyArchetypes[uuid] or ""
end

local function postLoadoutsToUser(userId)
    local activeUuid = getControlledForUser(userId)
    -- Party-order map: lower index = earlier in topbar.  Summons aren't in DB_PartyMembers so they get a high sentinel and sort after.
    local partyOrder = {}
    local partyMembers = Osi.DB_PartyMembers:Get(nil)
    if partyMembers then
        for i, row in ipairs(partyMembers) do
            local uuid = M.Osi.GetUUID(row[1])
            if uuid then partyOrder[uuid] = i end
        end
    end
    local characters = {}
    if State.Session.Players then
        for uuid, player in pairs(State.Session.Players) do
            -- MP scoping: each user only sees/edits the characters they own.  Summons inherit ReservedUserID from their summoner so they
            -- naturally land in the correct user's bucket.
            if player.userId == userId then
                characters[#characters + 1] = {
                    uuid = uuid,
                    name = M.Utils.getDisplayName(uuid) or "",
                    isSummon = M.Osi.IsSummon(uuid) == 1,
                    isActive = uuid == activeUuid,
                    archetype = getCharacterArchetype(uuid),
                    loadouts = Loadouts.getClientLoadoutsForCharacter(uuid),
                    _order = partyOrder[uuid] or 9999,  -- sort key only, not sent
                }
            end
        end
    end
    -- Party position first; summons (no party order) fall to the end and sort alpha among themselves.
    table.sort(characters, function (a, b)
        if a._order ~= b._order then return a._order < b._order end
        return (a.name or "") < (b.name or "")
    end)
    for _, c in ipairs(characters) do c._order = nil end
    -- Only the host edits the global summon mode; other users get isHost=false and the client hides those checkboxes.
    local hostUuid = M.Osi.GetHostCharacter()
    local hostUserId = hostUuid and State.Session.Players and State.Session.Players[hostUuid] and State.Session.Players[hostUuid].userId
    local payload = {
        characters = characters,
        summonMode = Loadouts.getSummonReactionMode(),
        sharedCampChestAccess = Loadouts.getSharedCampChestAccess(),
        isHost = userId == hostUserId,
    }
    Ext.ServerNet.PostMessageToUser(userId, "Loadouts", Ext.Json.Stringify(payload))
end

local function onRequestLoadouts(data)
    postLoadoutsToUser(Utils.peerToUserId(data.UserID))
end

-- Loadout-mutation payloads are JSON {characterUuid, index?}; index is nil for Save (which appends a new slot).
local function parseLoadoutPayload(payloadStr)
    if not payloadStr or payloadStr == "" then return nil end
    local ok, parsed = pcall(Ext.Json.Parse, payloadStr)
    if not ok or type(parsed) ~= "table" then return nil end
    return parsed
end

-- MP ownership check: refuse mutations on characters not owned by the requesting user.
local function userOwnsCharacter(userId, characterUuid)
    return characterUuid
        and State.Session.Players
        and State.Session.Players[characterUuid]
        and State.Session.Players[characterUuid].userId == userId
end

local function onSaveLoadout(data)
    local userId = Utils.peerToUserId(data.UserID)
    local p = parseLoadoutPayload(data.Payload)
    if not p or not userOwnsCharacter(userId, p.characterUuid) then return end
    Loadouts.saveLoadout(p.characterUuid)
    postLoadoutsToUser(userId)
end

local function onLoadLoadout(data)
    local userId = Utils.peerToUserId(data.UserID)
    local p = parseLoadoutPayload(data.Payload)
    if not p or not p.index or not userOwnsCharacter(userId, p.characterUuid) then return end
    Loadouts.loadLoadout(p.characterUuid, p.index)
    postLoadoutsToUser(userId)
end

local function onOverwriteLoadout(data)
    local userId = Utils.peerToUserId(data.UserID)
    local p = parseLoadoutPayload(data.Payload)
    if not p or not p.index or not userOwnsCharacter(userId, p.characterUuid) then return end
    Loadouts.overwriteLoadout(p.characterUuid, p.index)
    postLoadoutsToUser(userId)
end

local function onDeleteLoadout(data)
    local userId = Utils.peerToUserId(data.UserID)
    local p = parseLoadoutPayload(data.Payload)
    if not p or not p.index or not userOwnsCharacter(userId, p.characterUuid) then return end
    Loadouts.deleteLoadout(p.characterUuid, p.index)
    postLoadoutsToUser(userId)
end

local function onRenameLoadout(data)
    local userId = Utils.peerToUserId(data.UserID)
    local p = parseLoadoutPayload(data.Payload)
    if not p or not p.index or not userOwnsCharacter(userId, p.characterUuid) then return end
    Loadouts.renameLoadout(p.characterUuid, p.index, p.name or "")
    postLoadoutsToUser(userId)
end

local function onSetSummonReactionMode(data)
    local userId = Utils.peerToUserId(data.UserID)
    local mode = data.Payload
    if mode ~= "manual" and mode ~= "all_on" and mode ~= "all_off" then return end
    -- Host-only: silently drop attempts from other users.
    local hostUuid = M.Osi.GetHostCharacter()
    local hostUserId = hostUuid and State.Session.Players and State.Session.Players[hostUuid] and State.Session.Players[hostUuid].userId
    if userId ~= hostUserId then return end
    Loadouts.setSummonReactionMode(mode)
    Loadouts.applySummonOverrideToAll()
    postLoadoutsToUser(userId)
end

local function onSetSharedCampChestAccess(data)
    local userId = Utils.peerToUserId(data.UserID)
    local hostUuid = M.Osi.GetHostCharacter()
    local hostUserId = hostUuid and State.Session.Players and State.Session.Players[hostUuid] and State.Session.Players[hostUuid].userId
    if userId ~= hostUserId then return end
    Loadouts.setSharedCampChestAccess(data.Payload == "1")
    postLoadoutsToUser(userId)
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
    local level = M.Osi.GetRegion(M.Osi.GetHostCharacter())
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
    -- Legacy MCM hook still applies to the host character.
    if archetype and archetype ~= "" then
        setCharacterArchetype(M.Osi.GetHostCharacter(), archetype)
    end
end

local function onSetCharacterArchetype(data)
    local userId = Utils.peerToUserId(data.UserID)
    local p = parseLoadoutPayload(data.Payload)
    if not p or not p.archetype or not userOwnsCharacter(userId, p.characterUuid) then return end
    setCharacterArchetype(p.characterUuid, p.archetype)
    postLoadoutsToUser(userId)
end

local function onMCMMaxPartySize(maxPartySize)
    State.Settings.MaxPartySize = maxPartySize
    State.setMaxPartySize()
end

local function onMCMTurnBasedSwarmMode(value)
    State.Settings.TurnBasedSwarmMode = value
    if value == true then
        RT.Timers.stopAllPulseActionTimers()
        Movement.removeAllDashSpeedBoosts()
        State.endBrawls()
        State.recapMovementDistances()
        Swarm.resetChunkState()
        modStatusMessage("Swarm Mode")
    else
        State.uncapMovementDistances()
        State.disableDynamicCombatCamera()
        disableMod(true)
        enableMod(true)
        modStatusMessage("Real-Time Mode")
    end
end

local function onModeToggle(data)
    local toggle = not State.Settings.TurnBasedSwarmMode
    if MCM then
        MCM.Set("turn_based_swarm_mode", toggle)
    end
    onMCMTurnBasedSwarmMode(toggle)
end

local function onMCMExcludeEnemyTiers(excludeEnemyTier)
    State.Settings.ExcludeEnemyTiers = (excludeEnemyTier ~= "") and excludeEnemyTier or nil
    State.Session.ExcludeEnemyTierIndex = M.Utils.getTierIndex(excludeEnemyTier)
end

-- TEMP DEBUG: dump state of ALL brawlers for grey-out / stuck-enemy investigation
local function dumpBrawlerState(uuid, label)
    local name = M.Utils.getDisplayName(uuid)
    local entity = Ext.Entity.Get(uuid)
    if not entity then
        print("[DebugDump]", label, name, "no entity")
        return
    end
    local combatGuid = M.Osi.CombatGetGuidFor(uuid) or "<nil>"
    print("[DebugDump] === " .. label .. " " .. name .. " (" .. uuid .. ") combatGuid=" .. tostring(combatGuid) .. " ===")
    print(string.format("[DebugDump]   IsInCombat=%s IsInFTB=%s CanAct=%s",
        tostring(M.Osi.IsInCombat(uuid)), tostring(M.Osi.IsInForceTurnBasedMode(uuid)),
        tostring(M.Utils.canAct(uuid))))
    if entity.TurnBased then
        local tb = entity.TurnBased
        print(string.format("[DebugDump]   TurnBased: IsActive=%s ReqEnd=%s HadTurn=%s TurnDone=%s CanActInCombat=%s",
            tostring(tb.IsActiveCombatTurn), tostring(tb.RequestedEndTurn),
            tostring(tb.HadTurnInCombat), tostring(tb.TurnActionsCompleted),
            tostring(tb.CanActInCombat)))
    end
    local castComp = entity.SpellCastIsCasting
    if castComp then
        local hasCast = castComp.Cast and true or false
        local hasState = castComp.Cast and castComp.Cast.SpellCastState and true or false
        local spell = hasState and castComp.Cast.SpellCastState.SpellId and castComp.Cast.SpellCastState.SpellId.OriginatorPrototype or "<nil>"
        print(string.format("[DebugDump]   SpellCastIsCasting: present hasCast=%s hasState=%s spell=%s",
            tostring(hasCast), tostring(hasState), tostring(spell)))
    end
    print(string.format("[DebugDump]   FTBLockedIn=%s MovementQueue=%s",
        tostring(State.Session.FTBLockedIn[uuid]),
        tostring(State.Session.MovementQueue[uuid] ~= nil)))
    if entity.ServerCharacter and entity.ServerCharacter.StatusManager and entity.ServerCharacter.StatusManager.Statuses then
        local statusIds = {}
        for _, status in ipairs(entity.ServerCharacter.StatusManager.Statuses) do
            if status.StatusId then table.insert(statusIds, status.StatusId) end
        end
        if #statusIds > 0 then
            print("[DebugDump]   Statuses: " .. table.concat(statusIds, ", "))
        end
    end
    if entity.ActionResources and entity.ActionResources.Resources then
        local parts = {}
        for _, rt in ipairs({"ActionPoint", "BonusActionPoint", "ReactionActionPoint", "Movement"}) do
            local ruuid = Constants.ACTION_RESOURCES[rt]
            local r = ruuid and entity.ActionResources.Resources[ruuid]
            if r and r[1] then
                table.insert(parts, rt .. "=" .. tostring(r[1].Amount) .. "/" .. tostring(r[1].MaxAmount))
            end
        end
        if #parts > 0 then print("[DebugDump]   Resources: " .. table.concat(parts, " ")) end
    end
    local brawler = M.Roster.getBrawlerByUuid(uuid)
    if brawler then
        print(string.format("[DebugDump]   Brawler: isPaused=%s actionInterval=%s targetUuid=%s hasPulseTimer=%s",
            tostring(brawler.isPaused), tostring(brawler.actionInterval),
            tostring(brawler.targetUuid and M.Utils.getDisplayName(brawler.targetUuid) or "<nil>"),
            tostring(State.Session.PulseActionTimers[uuid] ~= nil)))
    end
end

local function dumpFullState(label)
    print("[DebugDump] ======== DUMP START (" .. tostring(label or "manual") .. ") ========")
    -- Dump the currently-controlled character first
    if State.Session.Players then
        for uuid, player in pairs(State.Session.Players) do
            if player.isControllingDirectly then
                dumpBrawlerState(uuid, "CONTROLLED")
                break
            end
        end
    end
    -- Dump all brawlers
    for uuid, _ in pairs(M.Roster.getBrawlers()) do
        if not (State.Session.Players[uuid] and State.Session.Players[uuid].isControllingDirectly) then
            local label2 = State.Session.Players[uuid] and "PLAYER" or "NPC"
            dumpBrawlerState(uuid, label2)
        end
    end
    print("[DebugDump] -------- TurnOrder.Groups --------")
    TurnOrder.showTurnOrderGroups()
    print("[DebugDump] -------- TurnOrder.Groups2 --------")
    TurnOrder.showTurnOrderGroups2()
    print("[DebugDump] ======== DUMP END ========")
end

return {
    setAwaitingTarget = setAwaitingTarget,
    enableMod = enableMod,
    disableMod = disableMod,
    dumpFullState = dumpFullState,
    setCharacterArchetype = setCharacterArchetype,
    getCharacterArchetype = getCharacterArchetype,
    postLoadoutsToUser = postLoadoutsToUser,
    NetMessage = {
        ModToggle = onModToggle,
        ModeToggle = onModeToggle,
        CompanionAIToggle = onCompanionAIToggle,
        QueueCompanionAIActions = onQueueCompanionAIActions,
        FullAutoToggle = onFullAutoToggle,
        LeaderboardToggle = onLeaderboardToggle,
        LeaderboardSetEnabled = onLeaderboardSetEnabled,
        RequestLoadouts = onRequestLoadouts,
        SaveLoadout = onSaveLoadout,
        LoadLoadout = onLoadLoadout,
        OverwriteLoadout = onOverwriteLoadout,
        DeleteLoadout = onDeleteLoadout,
        RenameLoadout = onRenameLoadout,
        SetSummonReactionMode = onSetSummonReactionMode,
        SetSharedCampChestAccess = onSetSharedCampChestAccess,
        SetCharacterArchetype = onSetCharacterArchetype,
        ExitFTB = function (_) Pause.allExitFTB() end,
        EnterFTB = function (_) Pause.allEnterFTB() end,
        APoCSCameraReady = function (_) RT.onAPoCSCameraReady() end,
        ClickPosition = onClickPosition,
        CancelQueuedMovement = onCancelQueuedMovement,
        ActionButton = function (data) onActionButton(data, false) end,
        ControllerActionButton = function (data) onActionButton(data, true) end,
        TargetCloserEnemy = function (data) targetCloserOrFartherEnemy(data, false) end,
        TargetFartherEnemy = function (data) targetCloserOrFartherEnemy(data, true) end,
        OnMe = onOnMe,
        AttackMyTarget = onAttackMyTarget,
        AttackMove = onAttackMove,
        MoveParty = onMoveParty,
        RequestHeal = onRequestHeal,
        ChangeTactics = onChangeTactics,
    },
    MCMSettingSaved = {
        mod_enabled = onMCMModEnabled,
        companion_ai_enabled = onMCMCompanionAIEnabled,
        true_pause = onMCMTruePause,
        auto_pause_on_downed = function (v) State.Settings.AutoPauseOnDowned = v end,
        auto_pause_on_combat_start = function (v) State.Settings.AutoPauseOnCombatStart = v end,
        action_interval = function (v) State.Settings.ActionInterval = v end,
        combat_round_duration = function (v) State.Settings.CombatRoundDuration = v end,
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
        no_freeze_on_bonus_actions_during_pause = function (v) State.Settings.NoFreezeOnBonusActionsDuringPause = v end,
        players_go_together = function (v) State.Settings.PlayersGoTogether = v end,
        swarm_turn_timeout = function (v) State.Settings.SwarmTurnTimeout = v end,
        swarm_chunk_size = function (v) State.Settings.SwarmChunkSize = v end,
        autotrigger_swarm_mode_companion_ai = function (v) State.Settings.AutotriggerSwarmModeCompanionAI = v end,
        exclude_enemy_tiers = onMCMExcludeEnemyTiers,
    },
}
