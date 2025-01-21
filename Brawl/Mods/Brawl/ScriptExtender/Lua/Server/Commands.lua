local function disableCompanionAI()
    debugPrint("companion ai disabled")
    State.Settings.CompanionAIEnabled = false
    for playerUuid, player in pairs(State.Session.Players) do
        local level = Osi.GetRegion(playerUuid)
        if level and State.Session.Brawlers and State.Session.Brawlers[level] and State.Session.Brawlers[level][playerUuid] then
            Osi.PurgeOsirisQueue(playerUuid, 1)
            Osi.FlushOsirisQueue(playerUuid)
            stopPulseAction(State.Session.Brawlers[level][playerUuid])
        end
    end
    modStatusMessage("Companion AI Disabled")
end
local function enableCompanionAI()
    debugPrint("companion ai enabled")
    State.Settings.CompanionAIEnabled = true
    if State.Session.Players and areAnyState.Session.PlayersBrawling() then
        for playerUuid, player in pairs(State.Session.Players) do
            if not State.isPlayerControllingDirectly(playerUuid) then
                addBrawler(playerUuid, true, true)
            end
        end
    end
    modStatusMessage("Companion AI Enabled")
end
local function disableFullAuto()
    debugPrint("full auto disabled")
    State.Settings.FullAuto = false
    for playerUuid, player in pairs(State.Session.Players) do
        if State.isPlayerControllingDirectly(playerUuid) then
            local level = Osi.GetRegion(playerUuid)
            if level and State.Session.Brawlers and State.Session.Brawlers[level] and State.Session.Brawlers[level][playerUuid] then
                Osi.PurgeOsirisQueue(playerUuid, 1)
                Osi.FlushOsirisQueue(playerUuid)
                stopPulseAction(State.Session.Brawlers[level][playerUuid])
            end
        end
    end
    modStatusMessage("Full Auto Disabled")
end
local function enableFullAuto()
    debugPrint("full auto enabled")
    State.Settings.FullAuto = true
    if State.Session.Players and State.areAnyPlayersBrawling() then
        for playerUuid, player in pairs(State.Session.Players) do
            addBrawler(playerUuid, true, true)
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
    stopListeners()
    modStatusMessage("Brawl Disabled")
end
local function enableMod()
    State.Settings.ModEnabled = true
    startListeners()
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
        onStarted(level)
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

local function targetCloserOrFartherEnemy(data, targetFartherEnemy)
    local player = State.getPlayerByUserId(peerToUserId(data.UserID))
    if player then
        local brawler = State.getBrawlerByUuid(player.uuid)
        if brawler and not brawler.isPaused then
            buildClosestEnemyBrawlers(player.uuid)
            if State.Session.ClosestEnemyBrawlers[player.uuid] ~= nil and next(State.Session.ClosestEnemyBrawlers[player.uuid]) ~= nil then
                debugPrint("Selecting next enemy brawler")
                selectNextEnemyBrawler(player.uuid, targetFartherEnemy)
            end
        end
    end
end
local function setAttackMoveTarget(playerUuid, targetUuid)
    debugPrint("Set attack-move target", playerUuid, targetUuid)
    setAwaitingTarget(playerUuid, false)
    local level = Osi.GetRegion(playerUuid)
    if level and targetUuid and not isPlayerOrAlly(targetUuid) and State.Session.Brawlers and State.Session.Brawlers[level] then
        applyAttackMoveTargetVfx(targetUuid)
        if not State.Session.Brawlers[level][targetUuid] then
            addBrawler(targetUuid, true)
        end
        lockCompanionsOnTarget(level, targetUuid)
    end
end
local function onActionButton(data, isController)
    local player = State.getPlayerByUserId(peerToUserId(data.UserID))
    if player then
        -- controllers don't have many buttons, so we only want the actionbar hotkeys to trigger actions if we're in a fight and not paused
        if isController then
            local brawler = State.getBrawlerByUuid(player.uuid)
            if not brawler or brawler.isPaused then
                return
            end
        end
        local actionButtonLabel = tonumber(data.Payload)
        if ACTION_BUTTON_TO_SLOT[actionButtonLabel] ~= nil and isAliveAndCanFight(player.uuid) then
            local spellName = getSpellNameBySlot(player.uuid, ACTION_BUTTON_TO_SLOT[actionButtonLabel])
            if spellName ~= nil then
                local spell = State.getSpellByName(spellName)
                -- NB: maintain separate friendly target list for healing/buffs?
                if spell ~= nil and (spell.type == "Buff" or spell.type == "Healing") then
                    return useSpellAndResources(player.uuid, player.uuid, spellName)
                end
                -- if isZoneSpell(spellName) or isProjectileSpell(spellName) then
                --     return useSpellAndResources(player.uuid, nil, spellName)
                -- end
                if State.Session.PlayerMarkedTarget[player.uuid] == nil or Osi.IsDead(State.Session.PlayerMarkedTarget[player.uuid]) == 1 then
                    buildClosestEnemyBrawlers(player.uuid)
                end
                return useSpellAndResources(player.uuid, State.Session.PlayerMarkedTarget[player.uuid], spellName)
            end
        end
    end
end
local function onAttackMyTarget(data)
    if State.Session.Players and State.Session.Brawlers then
        local player = State.getPlayerByUserId(peerToUserId(data.UserID))
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
    local player = State.getPlayerByUserId(peerToUserId(data.UserID))
    if player and player.uuid then
        local playerUuid = player.uuid
        local clickPosition = Ext.Json.Parse(data.Payload)
        if clickPosition then
            if State.Session.AwaitingTarget[playerUuid] and clickPosition.uuid then
                setAttackMoveTarget(playerUuid, clickPosition.uuid)
            elseif clickPosition.position then
                findPathToPosition(playerUuid, clickPosition.position, function (validPosition)
                    if State.Session.MovementQueue[playerUuid] ~= nil then
                        enqueueMovement(Ext.Entity.Get(playerUuid))
                    elseif State.Session.AwaitingTarget[playerUuid] then
                        setAwaitingTarget(playerUuid, false)
                        applyAttackMoveTargetVfx(createDummyObject(validPosition))
                        moveCompanionsToPosition(validPosition)
                    end
                end)
            end
        end
    end
end
local function onCancelQueuedMovement(data)
    local player = State.getPlayerByUserId(peerToUserId(data.UserID))
    if player and player.uuid then
        cancelQueuedMovement(player.uuid)
    end
end
local function onOnMe(data)
    if State.Session.Players then
        local player = State.getPlayerByUserId(peerToUserId(data.UserID))
        if player and player.uuid and Osi.IsInForceTurnBasedMode(player.uuid) == 0 then
            applyOnMeTargetVfx(player.uuid)
            moveCompanionsToPlayer(player.uuid)
        end
    end
end
local function onAttackMove(data)
    if State.Session.Players then
        local player = State.getPlayerByUserId(peerToUserId(data.UserID))
        if player and player.uuid and Osi.IsInForceTurnBasedMode(player.uuid) == 0 then
            setAwaitingTarget(player.uuid, true)
        end
    end
end
local function onRequestHeal(data)
    debugPrint("Requesting Heal")
    local userId = peerToUserId(data.UserID)
    if userId then
        if State.Session.HealRequestedTimer[userId] then
            Ext.Timer.Cancel(State.Session.HealRequestedTimer[userId])
            State.Session.HealRequestedTimer[userId] = nil
        end
        local player = State.getPlayerByUserId(userId)
        if player and player.uuid then
            State.Session.HealRequested[userId] = true
            addPlayersInEnterCombatRangeToBrawlers(player.uuid)
            State.Session.HealRequestedTimer[userId] = Ext.Timer.WaitFor(9000, function ()
                State.Session.HealRequested[userId] = false
            end)
        end
    end
end
local function onChangeTactics(data)
    for i, tactics in ipairs(COMPANION_TACTICS) do
        if State.Settings.CompanionTactics == tactics then
            State.Settings.CompanionTactics = i < #COMPANION_TACTICS and COMPANION_TACTICS[i + 1] or COMPANION_TACTICS[1]
            if MCM then
                MCM.Set("companion_tactics", State.Settings.CompanionTactics)
            end
            break
        end
    end
    modStatusMessage(State.Settings.CompanionTactics .. " Tactics")
end
local function onModToggle(data)
    if MCM then
        MCM.Set("mod_enabled", not State.Settings.ModEnabled)
    else
        toggleMod()
    end
end
local function onCompanionAIToggle(data)
    if MCM then
        MCM.Set("companion_ai_enabled", not State.Settings.CompanionAIEnabled)
    else
        toggleCompanionAI()
    end
end
local function onFullAutoToggle(data)
    if MCM then
        MCM.Set("full_auto", not State.Settings.FullAuto)
    else
        toggleFullAuto()
    end
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
    checkTruePauseParty()
end
local function onMCMHitpointsMultiplier(value)
    State.Settings.HitpointsMultiplier = value
    State.setupPartyMembersHitpoints()
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if State.Session.Brawlers and State.Session.Brawlers[level] then
        for brawlerUuid, brawler in pairs(State.Session.Brawlers[level]) do
            State.revertHitpoints(brawlerUuid)
            State.modifyHitpoints(brawlerUuid)
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
        local brawler = State.getBrawlerByUuid(uuid)
        if brawler ~= nil then
            brawler.archetype = archetype
        end
    end
end
local function onMCMMaxPartySize(maxPartySize)
    State.Settings.MaxPartySize = maxPartySize
    State.setMaxPartySize()
end

NetMessage = {
    ModToggle = onModToggle,
    CompanionAIToggle = onCompanionAIToggle,
    FullAutoToggle = onFullAutoToggle,
    ExitFTB = function (_) allExitFTB() end,
    EnterFTB = function (_) allEnterFTB() end,
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
}
MCMSettingSaved = {
    mod_enabled = onMCMModEnabled,
    companion_ai_enabled = onMCMCompanionAIEnabled,
    true_pause = onMCMTruePause,
    auto_pause_on_downed = function (v) State.Settings.AutoPauseOnDowned = v end,
    action_interval = function (v) State.Settings.ActionInterval = v end,
    hitpoints_multiplier = onMCMHitpointsMultiplier,
    full_auto = onMCMFullAuto,
    active_character_archetype = onMCMActiveCharacterArchetype,
    companion_tactics = function (v) State.Settings.CompanionTactics = v end,
    companion_ai_max_spell_level = function (v) State.Settings.CompanionAIMaxSpellLevel = v end,
    hogwild_mode = function (v) State.Settings.HogwildMode = v end,
    max_party_size = onMCMMaxPartySize,
    murderhobo_mode = function (v) State.Settings.MurderhoboMode = v end,
    turn_based_swarm_mode = function (v) State.Settings.TurnBasedSwarmMode = v end,
}
