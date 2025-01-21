local function disableCompanionAI()
    debugPrint("companion ai disabled")
    CompanionAIEnabled = false
    for playerUuid, player in pairs(Players) do
        local level = Osi.GetRegion(playerUuid)
        if level and Brawlers and Brawlers[level] and Brawlers[level][playerUuid] then
            Osi.PurgeOsirisQueue(playerUuid, 1)
            Osi.FlushOsirisQueue(playerUuid)
            stopPulseAction(Brawlers[level][playerUuid])
        end
    end
    modStatusMessage("Companion AI Disabled")
end
local function enableCompanionAI()
    debugPrint("companion ai enabled")
    CompanionAIEnabled = true
    if Players and areAnyPlayersBrawling() then
        for playerUuid, player in pairs(Players) do
            if not isPlayerControllingDirectly(playerUuid) then
                addBrawler(playerUuid, true, true)
            end
        end
    end
    modStatusMessage("Companion AI Enabled")
end
local function disableFullAuto()
    debugPrint("full auto disabled")
    FullAuto = false
    for playerUuid, player in pairs(Players) do
        if isPlayerControllingDirectly(playerUuid) then
            local level = Osi.GetRegion(playerUuid)
            if level and Brawlers and Brawlers[level] and Brawlers[level][playerUuid] then
                Osi.PurgeOsirisQueue(playerUuid, 1)
                Osi.FlushOsirisQueue(playerUuid)
                stopPulseAction(Brawlers[level][playerUuid])
            end
        end
    end
    modStatusMessage("Full Auto Disabled")
end
local function enableFullAuto()
    debugPrint("full auto enabled")
    FullAuto = true
    if Players and areAnyPlayersBrawling() then
        for playerUuid, player in pairs(Players) do
            addBrawler(playerUuid, true, true)
        end
    end
    modStatusMessage("Full Auto Enabled")
end
local function toggleCompanionAI()
    if CompanionAIEnabled then
        disableCompanionAI()
    else
        enableCompanionAI()
    end
end
local function toggleFullAuto()
    if FullAuto then
        disableFullAuto()
    else
        enableFullAuto()
    end
end
local function disableMod()
    ModEnabled = false
    stopListeners()
    modStatusMessage("Brawl Disabled")
end
local function enableMod()
    ModEnabled = true
    startListeners()
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
        onStarted(level)
    end
    modStatusMessage("Brawl Enabled")
end
local function toggleMod()
    if ModEnabled then
        disableMod()
    else
        enableMod()
    end
end

local function targetCloserOrFartherEnemy(data, targetFartherEnemy)
    local player = getPlayerByUserId(peerToUserId(data.UserID))
    if player then
        local brawler = getBrawlerByUuid(player.uuid)
        if brawler and not brawler.isPaused then
            buildClosestEnemyBrawlers(player.uuid)
            if ClosestEnemyBrawlers[player.uuid] ~= nil and next(ClosestEnemyBrawlers[player.uuid]) ~= nil then
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
    if level and targetUuid and not isPlayerOrAlly(targetUuid) and Brawlers and Brawlers[level] then
        applyAttackMoveTargetVfx(targetUuid)
        if not Brawlers[level][targetUuid] then
            addBrawler(targetUuid, true)
        end
        lockCompanionsOnTarget(level, targetUuid)
    end
end
local function onActionButton(data, isController)
    local player = getPlayerByUserId(peerToUserId(data.UserID))
    if player then
        -- controllers don't have many buttons, so we only want the actionbar hotkeys to trigger actions if we're in a fight and not paused
        if isController then
            local brawler = getBrawlerByUuid(player.uuid)
            if not brawler or brawler.isPaused then
                return
            end
        end
        local actionButtonLabel = tonumber(data.Payload)
        if ACTION_BUTTON_TO_SLOT[actionButtonLabel] ~= nil and isAliveAndCanFight(player.uuid) then
            local spellName = getSpellNameBySlot(player.uuid, ACTION_BUTTON_TO_SLOT[actionButtonLabel])
            if spellName ~= nil then
                local spell = getSpellByName(spellName)
                -- NB: maintain separate friendly target list for healing/buffs?
                if spell ~= nil and (spell.type == "Buff" or spell.type == "Healing") then
                    return useSpellAndResources(player.uuid, player.uuid, spellName)
                end
                -- if isZoneSpell(spellName) or isProjectileSpell(spellName) then
                --     return useSpellAndResources(player.uuid, nil, spellName)
                -- end
                if PlayerMarkedTarget[player.uuid] == nil or Osi.IsDead(PlayerMarkedTarget[player.uuid]) == 1 then
                    buildClosestEnemyBrawlers(player.uuid)
                end
                return useSpellAndResources(player.uuid, PlayerMarkedTarget[player.uuid], spellName)
            end
        end
    end
end
local function onAttackMyTarget(data)
    if Players and Brawlers then
        local player = getPlayerByUserId(peerToUserId(data.UserID))
        local level = Osi.GetRegion(player.uuid)
        if level and Brawlers[level] and Osi.IsInForceTurnBasedMode(player.uuid) == 0 then
            local currentTarget
            if PlayerMarkedTarget[player.uuid] then
                currentTarget = PlayerMarkedTarget[player.uuid]
            elseif IsAttackingOrBeingAttackedByPlayer[player.uuid] then
                currentTarget = IsAttackingOrBeingAttackedByPlayer[player.uuid]
            elseif PlayerCurrentTarget[player.uuid] then
                currentTarget = PlayerCurrentTarget[player.uuid]
            end
            debugPrint("Got current player's target", currentTarget)
            setAttackMoveTarget(player.uuid, currentTarget)
        end
    end
end
local function onClickPosition(data)
    local player = getPlayerByUserId(peerToUserId(data.UserID))
    if player and player.uuid then
        local playerUuid = player.uuid
        local clickPosition = Ext.Json.Parse(data.Payload)
        if clickPosition then
            if AwaitingTarget[playerUuid] and clickPosition.uuid then
                setAttackMoveTarget(playerUuid, clickPosition.uuid)
            elseif clickPosition.position then
                findPathToPosition(playerUuid, clickPosition.position, function (validPosition)
                    if MovementQueue[playerUuid] ~= nil then
                        enqueueMovement(Ext.Entity.Get(playerUuid))
                    elseif AwaitingTarget[playerUuid] then
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
    local player = getPlayerByUserId(peerToUserId(data.UserID))
    if player and player.uuid then
        cancelQueuedMovement(player.uuid)
    end
end
local function onOnMe(data)
    if Players then
        local player = getPlayerByUserId(peerToUserId(data.UserID))
        if player and player.uuid and Osi.IsInForceTurnBasedMode(player.uuid) == 0 then
            applyOnMeTargetVfx(player.uuid)
            moveCompanionsToPlayer(player.uuid)
        end
    end
end
local function onAttackMove(data)
    if Players then
        local player = getPlayerByUserId(peerToUserId(data.UserID))
        if player and player.uuid and Osi.IsInForceTurnBasedMode(player.uuid) == 0 then
            setAwaitingTarget(player.uuid, true)
        end
    end
end
local function onRequestHeal(data)
    debugPrint("Requesting Heal")
    local userId = peerToUserId(data.UserID)
    if userId then
        if HealRequestedTimer[userId] then
            Ext.Timer.Cancel(HealRequestedTimer[userId])
            HealRequestedTimer[userId] = nil
        end
        local player = getPlayerByUserId(userId)
        if player and player.uuid then
            HealRequested[userId] = true
            addPlayersInEnterCombatRangeToBrawlers(player.uuid)
            HealRequestedTimer[userId] = Ext.Timer.WaitFor(9000, function ()
                HealRequested[userId] = false
            end)
        end
    end
end
local function onChangeTactics(data)
    for i, tactics in ipairs(COMPANION_TACTICS) do
        if CompanionTactics == tactics then
            CompanionTactics = i < #COMPANION_TACTICS and COMPANION_TACTICS[i + 1] or COMPANION_TACTICS[1]
            if MCM then
                MCM.Set("companion_tactics", CompanionTactics)
            end
            break
        end
    end
    modStatusMessage(CompanionTactics .. " Tactics")
end
local function onModToggle(data)
    if MCM then
        MCM.Set("mod_enabled", not ModEnabled)
    else
        toggleMod()
    end
end
local function onCompanionAIToggle(data)
    if MCM then
        MCM.Set("companion_ai_enabled", not CompanionAIEnabled)
    else
        toggleCompanionAI()
    end
end
local function onFullAutoToggle(data)
    if MCM then
        MCM.Set("full_auto", not FullAuto)
    else
        toggleFullAuto()
    end
end

local function onMCMModEnabled(value)
    ModEnabled = value
    if ModEnabled then
        enableMod()
    else
        disableMod()
    end
end
local function onMCMCompanionAIEnabled(value)
    CompanionAIEnabled = value
    if CompanionAIEnabled then
        enableCompanionAI()
    else
        disableCompanionAI()
    end
end
local function onMCMTruePause(value)
    TruePause = value
    checkTruePauseParty()
end
local function onMCMHitpointsMultiplier(value)
    HitpointsMultiplier = value
    setupPartyMembersHitpoints()
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if Brawlers and Brawlers[level] then
        for brawlerUuid, brawler in pairs(Brawlers[level]) do
            revertHitpoints(brawlerUuid)
            modifyHitpoints(brawlerUuid)
        end
    end
end
local function onMCMFullAuto(value)
    FullAuto = value
    if FullAuto then
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
        local brawler = getBrawlerByUuid(uuid)
        if brawler ~= nil then
            brawler.archetype = archetype
        end
    end
end
local function onMCMMaxPartySize(maxPartySize)
    MaxPartySize = maxPartySize
    setMaxPartySize()
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
    auto_pause_on_downed = function (v) AutoPauseOnDowned = v end,
    action_interval = function (v) ActionInterval = v end,
    hitpoints_multiplier = onMCMHitpointsMultiplier,
    full_auto = onMCMFullAuto,
    active_character_archetype = onMCMActiveCharacterArchetype,
    companion_tactics = function (v) CompanionTactics = v end,
    companion_ai_max_spell_level = function (v) CompanionAIMaxSpellLevel = v end,
    hogwild_mode = function (v) HogwildMode = v end,
    max_party_size = onMCMMaxPartySize,
    murderhobo_mode = function (v) MurderhoboMode = v end,
    turn_based_swarm_mode = function (v) TurnBasedSwarmMode = v end,
}
