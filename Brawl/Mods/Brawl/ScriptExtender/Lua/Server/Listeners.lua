local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump
local isToT = Utils.isToT

local function onCharacterMoveFailedUseJump(character)
    debugPrint("CharacterMoveFailedUseJump", character)
end

local function onCombatStarted(combatGuid)
    debugPrint("CombatStarted", combatGuid)
    State.Session.AutotriggeredSwarmModeCompanionAI = false
    if State.Settings.TurnBasedSwarmMode then
        Leaderboard.initialize()
    end
    -- NB: clean this up / don't reassign "constant" values
    if isToT() then
        if Mods.ToT.PersistentVars.Scenario and Mods.ToT.PersistentVars.Scenario.Round == 0 then
            State.Session.TBSMToTSkippedPrepRound = false
        else
            State.Session.TBSMToTSkippedPrepRound = true
        end
        Constants.ENTER_COMBAT_RANGE = 100
    else
        Constants.ENTER_COMBAT_RANGE = 20
    end
    for playerUuid, _ in pairs(State.Session.Players) do
        Roster.addBrawler(playerUuid, true)
    end
    local level = M.Osi.GetRegion(M.Osi.GetHostCharacter())
    if level then
        if State.Settings.TurnBasedSwarmMode then
            local serverEnterRequestEntities = Ext.Entity.GetAllEntitiesWithComponent("ServerEnterRequest")
            if serverEnterRequestEntities then
                local combatEntity = serverEnterRequestEntities[1]
                if combatEntity and combatEntity.CombatState and combatEntity.CombatState.Participants then
                    for _, participant in ipairs(combatEntity.CombatState.Participants) do
                        if not State.Session.Players[participant.Uuid.EntityUuid] then
                            Roster.addBrawler(participant.Uuid.EntityUuid, true)
                        end
                    end
                end
            end
        else
            if not isToT() then
                startBrawlFizzler(level)
                Ext.Timer.WaitFor(500, function ()
                    Roster.addNearbyToBrawlers(M.Osi.GetHostCharacter(), Constants.NEARBY_RADIUS, combatGuid)
                    Ext.Timer.WaitFor(1500, function ()
                        if M.Osi.CombatIsActive(combatGuid) then
                            -- NB: is there a way to do this less aggressively?
                            Osi.EndCombat(combatGuid)
                        end
                    end)
                end)
            else
                startToTTimers()
            end
        end
    end
end

local function onStarted(level)
    debugPrint("onStarted")
    M.memoizeAll()
    Spells.resetSpellData()
    Spells.buildSpellTable()
    State.setMaxPartySize()
    State.resetPlayers()
    State.setIsControllingDirectly()
    Movement.setMovementSpeedThresholds()
    Movement.resetPlayersMovementSpeed()
    State.setupPartyMembersHitpoints()
    Roster.initBrawlers(level)
    if State.Settings.TurnBasedSwarmMode then
        State.boostPlayerInitiatives()
        State.recapPartyMembersMovementDistances()
    else
        State.uncapPartyMembersMovementDistances()
        Pause.checkTruePauseParty()
    end
    Leaderboard.initialize()
    debugDump(State.Session.Players)
    Ext.ServerNet.BroadcastMessage("Started", level)
end

local function onResetCompleted()
    debugPrint("ResetCompleted")
    -- Printer:Start()
    -- SpellPrinter:Start()
    onStarted(Osi.GetRegion(Osi.GetHostCharacter()))
end

-- New user joined (multiplayer)
local function onUserReservedFor(entity, _, _)
    State.setIsControllingDirectly()
    local entityUuid = entity.Uuid.EntityUuid
    if State.Session.Players and State.Session.Players[entityUuid] then
        local userId = entity.UserReservedFor.UserID
        State.Session.Players[entityUuid].userId = entity.UserReservedFor.UserID
    end
end

local function onLevelGameplayStarted(level, _)
    debugPrint("LevelGameplayStarted", level)
    onStarted(level)
end

local function onCombatRoundStarted(combatGuid, round)
    debugPrint("CombatRoundStarted", combatGuid, round)
    State.Session.AutotriggeredSwarmModeCompanionAI = false
    if State.Settings.TurnBasedSwarmMode then
        Swarm.cancelTimers()
        State.Session.SwarmTurnActive = false
        State.Session.SwarmTurnTimerCombatRound = nil
        State.Session.QueuedCompanionAIAction = {}
        -- State.Session.ActionsInProgress = {}
        Swarm.unsetAllEnemyTurnsComplete()
    else
        if isToT() then
            startToTTimers()
        else
            onCombatStarted(combatGuid)
        end
    end
end

local function onCombatEnded(combatGuid)
    debugPrint("CombatEnded", combatGuid)
    if State.Settings.TurnBasedSwarmMode then
        State.Session.StoryActionIDs = {}
        State.Session.SwarmTurnComplete = {}
        Swarm.cancelTimers()
        Leaderboard.dumpToConsole()
        Leaderboard.postDataToClients()
    end
end

local function onEnteredCombat(entityGuid, combatGuid)
    debugPrint("EnteredCombat", entityGuid, combatGuid)
    local entityUuid = M.Osi.GetUUID(entityGuid)
    if entityUuid then
        Roster.addBrawler(entityUuid, true)
        if State.Settings.TurnBasedSwarmMode and M.Osi.IsPartyMember(entityUuid, 1) == 1 and State.Session.ResurrectedPlayer[entityUuid] then
            State.Session.ResurrectedPlayer[entityUuid] = nil
            local initiativeRoll = Roster.rollForInitiative(entityUuid)
            local entity = Ext.Entity.Get(entityUuid)
            if entity and entity.CombatParticipant then
                entity.CombatParticipant.InitiativeRoll = initiativeRoll
                if entity.CombatParticipant.CombatHandle and entity.CombatParticipant.CombatHandle.CombatState and entity.CombatParticipant.CombatHandle.CombatState.Initiatives then
                    entity.CombatParticipant.CombatHandle.CombatState.Initiatives[entity] = initiativeRolls
                    entity.CombatParticipant.CombatHandle:Replicate("CombatState")
                end
                entity:Replicate("CombatParticipant")
            end
        end
    end
end

local function onEnteredForceTurnBased(entityGuid)
    debugPrint("EnteredForceTurnBased", entityGuid)
    local entityUuid = M.Osi.GetUUID(entityGuid)
    local level = M.Osi.GetRegion(entityGuid)
    if level and entityUuid and not State.Settings.TurnBasedSwarmMode then
        local isPlayer = State.Session.Players and State.Session.Players[entityUuid]
        if isPlayer then
            local isHostCharacter = entityUuid == Osi.GetHostCharacter()
            if State.Session.Players[entityUuid].isFreshSummon then
                State.Session.Players[entityUuid].isFreshSummon = false
                return Osi.ForceTurnBasedMode(entityUuid, 0)
            end
            if State.Session.AwaitingTarget[entityUuid] then
                Commands.setAwaitingTarget(entityUuid, false)
            end
            Quests.stopCountdownTimer(entityUuid)
            if State.Session.Brawlers[level] and State.Session.Brawlers[level][entityUuid] then
                State.Session.Brawlers[level][entityUuid].isInBrawl = false
            end
            stopPulseAddNearby(entityUuid)
            if isHostCharacter then
                stopPulseReposition(level)
                stopBrawlFizzler(level)
                if isToT() then
                    stopToTTimers()
                end
            end
        end
        if M.Utils.isAliveAndCanFight(entityUuid) then
            Utils.clearOsirisQueue(entityUuid)
            if State.Settings.TruePause then
                Pause.startTruePause(entityUuid)
            end
        end
        if isPlayer then
            local brawlersInLevel = State.Session.Brawlers[level]
            if brawlersInLevel then
                for brawlerUuid, brawler in pairs(brawlersInLevel) do
                    if not brawlersInLevel[brawlerUuid].isPaused then
                        debugPrint("stopping pulse for", brawler.uuid, brawler.displayName)
                        stopPulseAction(brawler, true)
                        brawlersInLevel[brawlerUuid].isPaused = true
                        Osi.ForceTurnBasedMode(brawlerUuid, 1)
                        -- if brawlerUuid ~= entityUuid then
                        --     if State.Session.Players[brawlerUuid] then
                        --         brawlersInLevel[brawlerUuid].isPaused = true
                        --         Osi.ForceTurnBasedMode(brawlerUuid, 1)
                        --     end
                        -- end
                    end
                end
            end
        end
    end
end

local function onLeftForceTurnBased(entityGuid)
    debugPrint("LeftForceTurnBased", entityGuid)
    local entityUuid = M.Osi.GetUUID(entityGuid)
    local level = M.Osi.GetRegion(entityGuid)
    if level and entityUuid and State.Session.Players and State.Session.Players[entityUuid] and not State.Settings.TurnBasedSwarmMode then
        if State.Session.Players[entityUuid].isFreshSummon then
            State.Session.Players[entityUuid].isFreshSummon = false
        end
        Quests.resumeCountdownTimer(entityUuid)
        if State.Session.FTBLockedIn[entityUuid] ~= nil then
            State.Session.FTBLockedIn[entityUuid] = nil
        end
        State.Session.RemainingMovement[entityUuid] = nil
        if State.Session.Brawlers[level] and State.Session.Brawlers[level][entityUuid] then
            State.Session.Brawlers[level][entityUuid].isInBrawl = true
            if State.isPlayerControllingDirectly(entityUuid) then
                startPulseAddNearby(entityUuid)
            end
        end
        local isHostCharacter = entityUuid == Osi.GetHostCharacter()
        if isHostCharacter then
            startPulseReposition(level)
        end
        -- NB: should this logic all be in Pause.lua instead? can it get triggered incorrectly? (e.g. downed players?)
        if State.areAnyPlayersBrawling() then
            if isHostCharacter then
                startBrawlFizzler(level)
                if isToT() then
                    startToTTimers()
                end
            end
            local brawlersInLevel = State.Session.Brawlers[level]
            if brawlersInLevel then
                for brawlerUuid, brawler in pairs(brawlersInLevel) do
                    if State.Session.Players[brawlerUuid] then
                        if not State.isPlayerControllingDirectly(brawlerUuid) or State.Settings.FullAuto then
                            startPulseAction(brawler)
                            -- Ext.Timer.WaitFor(2000, function ()
                            --     Osi.FlushOsirisQueue(brawlerUuid)
                            --     startPulseAction(brawler)
                            -- end)
                        end
                        brawlersInLevel[brawlerUuid].isPaused = false
                        if brawlerUuid ~= entityUuid then
                            debugPrint("setting fTB to 0 for", brawlerUuid, entityUuid)
                            Osi.ForceTurnBasedMode(brawlerUuid, 0)
                        end
                    else
                        startPulseAction(brawler)
                    end
                end
            end
        end
    end
end

local function onTurnStarted(entityGuid)
    if State.Settings.TurnBasedSwarmMode then
        debugPrint("TurnStarted", entityGuid)
        local entityUuid = M.Osi.GetUUID(entityGuid)
        if entityUuid and M.Osi.IsPartyMember(entityUuid, 1) == 1 then
            State.Session.TurnBasedSwarmModePlayerTurnEnded[entityUuid] = false
            if State.Settings.AutotriggerSwarmModeCompanionAI and not State.Session.AutotriggeredSwarmModeCompanionAI then
                State.Session.AutotriggeredSwarmModeCompanionAI = true
                Pause.queueCompanionAIActions()
            end
        end
    end
end

local function onTurnEnded(entityGuid)
    if State.Settings.TurnBasedSwarmMode then
        -- print("TurnEnded", entityGuid)
        local entityUuid = M.Osi.GetUUID(entityGuid)
        if entityUuid and M.Roster.getBrawlerByUuid(entityUuid) then
            if M.Osi.IsPartyMember(entityUuid, 1) == 1 then
                -- print("setting turn ended", entityGuid)
                State.Session.TurnBasedSwarmModePlayerTurnEnded[entityUuid] = true
                if Swarm.checkAllPlayersFinishedTurns() then
                    -- print("Started Swarm turn!")
                    Swarm.unsetAllEnemyTurnsComplete()
                    Swarm.startSwarmTurn()
                end
            else
                Swarm.completeSwarmTurn(entityUuid)
            end
        end
    end
end

local function onDied(entityGuid)
    debugPrint("Died", entityGuid)
    local level = M.Osi.GetRegion(entityGuid)
    local entityUuid = M.Osi.GetUUID(entityGuid)
    if State.Session.SwarmTurnComplete[entityUuid] ~= nil then
        State.Session.SwarmTurnComplete[entityUuid] = nil
    end
    if level ~= nil and entityUuid ~= nil and State.Session.Brawlers[level] ~= nil and State.Session.Brawlers[level][entityUuid] ~= nil then
        -- Sometimes units don't appear dead when killed out-of-combat...
        -- this at least makes them lie prone (and dead-appearing units still appear dead)
        Ext.Timer.WaitFor(Constants.LIE_ON_GROUND_TIMEOUT, function ()
            debugPrint("LieOnGround", entityUuid)
            Utils.clearOsirisQueue(entityUuid)
            Osi.LieOnGround(entityUuid)
        end)
        Roster.removeBrawler(level, entityUuid)
        Roster.checkForEndOfBrawl(level)
    end
end

local function onResurrected(entityGuid)
    debugPrint("Resurrected", entityGuid)
    if State.Settings.TurnBasedSwarmMode then
        local entityUuid = M.Osi.GetUUID(entityGuid)
        if entityUuid and M.Osi.IsPartyMember(entityUuid, 1) == 1 then
            State.Session.ResurrectedPlayer[entityUuid] = true
            State.Session.TurnBasedSwarmModePlayerTurnEnded[entityUuid] = true
        end
    end
end

-- NB: entity.ClientControl does NOT get reliably updated immediately when this fires
local function onGainedControl(targetGuid)
    debugPrint("GainedControl", targetGuid)
    local targetUuid = M.Osi.GetUUID(targetGuid)
    if targetUuid ~= nil then
        if targetUuid == M.Osi.GetHostCharacter() then
            local modVars = Ext.Vars.GetModVariables(ModuleUUID)
            local partyArchetypes = modVars.PartyArchetypes
            if partyArchetypes == nil then
                partyArchetypes = {}
                modVars.PartyArchetypes = partyArchetypes
            end
            local archetype = ""
            if partyArchetypes[targetUuid] ~= nil then
                archetype = partyArchetypes[targetUuid]
            end
            local isValidArchetype = false
            for _, validArchetype in ipairs(Constants.PLAYER_ARCHETYPES) do
                if archetype == validArchetype then
                    isValidArchetype = true
                    break
                end
            end
            if MCM then
                MCM.Set("active_character_archetype", isValidArchetype and archetype or "")
            end
        end
        Utils.clearOsirisQueue(targetUuid)
        local targetUserId = Osi.GetReservedUserID(targetUuid)
        local players = State.Session.Players
        if players[targetUuid] ~= nil and targetUserId ~= nil then
            players[targetUuid].isControllingDirectly = true
            startPulseAddNearby(targetUuid)
            local level = M.Osi.GetRegion(targetUuid)
            local brawlersInLevel = State.Session.Brawlers[level]
            for playerUuid, player in pairs(players) do
                if player.userId == targetUserId and playerUuid ~= targetUuid then
                    player.isControllingDirectly = false
                    if not State.Settings.TurnBasedSwarmMode and level and brawlersInLevel and brawlersInLevel[playerUuid] and brawlersInLevel[playerUuid].isInBrawl then
                        stopPulseAddNearby(playerUuid)
                        startPulseAction(brawlersInLevel[playerUuid])
                    end
                end
            end
            if level and brawlersInLevel and brawlersInLevel[targetUuid] and not State.Settings.FullAuto then
                stopPulseAction(brawlersInLevel[targetUuid], true)
            end
            -- debugDump(players)
            Ext.ServerNet.PostMessageToUser(targetUserId, "GainedControl", targetUuid)
        end
    end
end

local function onCharacterJoinedParty(character)
    debugPrint("CharacterJoinedParty", character)
    local uuid = M.Osi.GetUUID(character)
    if uuid then
        if State.Session.Players and not State.Session.Players[uuid] then
            State.setupPlayer(uuid)
            State.setupPartyMembersHitpoints()
            if State.Settings.TurnBasedSwarmMode then
                State.boostPlayerInitiative(uuid)
                State.recapPartyMembersMovementDistances()
                State.Session.TurnBasedSwarmModePlayerTurnEnded[uuid] = M.Utils.isPlayerTurnEnded(uuid)
            else
                State.uncapPartyMembersMovementDistances()
                -- Pause.checkTruePauseParty()
            end
        end
        if M.Osi.IsSummon(uuid) == 1 then
            State.Session.Players[uuid].isFreshSummon = true
            local ownerUuid = Osi.CharacterGetOwner(uuid)
            if ownerUuid and not Utils.hasLoseControlStatus(uuid) then
                Osi.RequestSetSwarmGroup(ownerUuid, "PLAYER_SWARM_GROUP")
                Osi.RequestSetSwarmGroup(uuid, "PLAYER_SWARM_GROUP")
            end
        end
        if State.areAnyPlayersBrawling() then
            Roster.addBrawler(uuid, true)
        end
    end
end

local function onCharacterLeftParty(character)
    debugPrint("CharacterLeftParty", character)
    local uuid = M.Osi.GetUUID(character)
    if uuid then
        if State.Session.Players and State.Session.Players[uuid] then
            State.Session.Players[uuid] = nil
        end
        local level = M.Osi.GetRegion(uuid)
        if State.Session.Brawlers and State.Session.Brawlers[level] and State.Session.Brawlers[level][uuid] then
            State.Session.Brawlers[level][uuid] = nil
        end
    end
end

local function onRollResult(eventName, roller, rollSubject, resultType, isActiveRoll, criticality)
    debugPrint("RollResult", eventName, roller, rollSubject, resultType, isActiveRoll, criticality)
end

local function onDownedChanged(character, isDowned)
    local entityUuid = M.Osi.GetUUID(character)
    debugPrint("DownedChanged", character, isDowned, entityUuid)
    local player = State.Session.Players[entityUuid]
    local level = M.Osi.GetRegion(entityUuid)
    if player then
        if isDowned == 1 and State.Settings.AutoPauseOnDowned and player.isControllingDirectly then
            if State.Session.Brawlers[level] and State.Session.Brawlers[level][entityUuid] and not State.Session.Brawlers[level][entityUuid].isPaused then
                Osi.ForceTurnBasedMode(entityUuid, 1)
            end
        end
        if isDowned == 0 then
            player.isBeingHelped = false
        end
    end
end

local function playAttackSound(attackerUuid, defenderUuid, damageType)
    if damageType == "Slashing" then
        Osi.PlaySound(attackerUuid, "Action_Cast_Slash")
        Osi.PlaySound(defenderUuid, "Action_Impact_Slash")
    elseif damageType == "Piercing" then
        Osi.PlaySound(attackerUuid, "Action_Cast_PiercingThrust")
        Osi.PlaySound(defenderUuid, "Action_Impact_PiercingThrust")
    else
        Osi.PlaySound(attackerUuid, "Action_Cast_Smash")
        Osi.PlaySound(defenderUuid, "Action_Impact_Smash")
    end
end

local function hasExtraAttacksRemaining(uuid)
    return State.Session.ExtraAttacksRemaining[uuid] ~= nil and State.Session.ExtraAttacksRemaining[uuid] > 0
end

local function checkExtraAttacksReady(attackerUuid, defenderUuid)
    return hasExtraAttacksRemaining(attackerUuid) and M.Utils.isAliveAndCanFight(attackerUuid) and M.Utils.isAliveAndCanFight(defenderUuid)
end

local function reapplyAttackDamage(attackerUuid, defenderUuid, damageAmount, damageType)
    Ext.Timer.WaitFor(150, function ()
        if checkExtraAttacksReady(attackerUuid, defenderUuid) then
            playAttackSound(attackerUuid, defenderUuid, damageType)
            Ext.Timer.WaitFor(150, function ()
                if checkExtraAttacksReady(attackerUuid, defenderUuid) then
                    State.Session.ExtraAttacksRemaining[attackerUuid] = State.Session.ExtraAttacksRemaining[attackerUuid] - 1
                    debugPrint("Applying damage", defenderUuid, damageAmount, damageType)
                    Osi.ApplyDamage(defenderUuid, damageAmount, damageType, "")
                    Osi.ApplyStatus(defenderUuid, "INTERRUPT_RIPOSTE", 1)
                    Leaderboard.updateDamage(attackerUuid, defenderUuid, damageAmount)
                    reapplyAttackDamage(attackerUuid, defenderUuid, damageAmount, damageType)
                else
                    State.Session.ExtraAttacksRemaining[attackerUuid] = nil
                end
            end)
        else
            State.Session.ExtraAttacksRemaining[attackerUuid] = nil
        end
    end)
end

local function useActionPointSurplus(uuid, resourceType)
    local pointSurplus = math.floor(M.Osi.GetActionResourceValuePersonal(uuid, resourceType, 0) - 1)
    if pointSurplus > 0 then
        Resources.decreaseActionResource(uuid, resourceType, pointSurplus)
    end
    return pointSurplus
end

local function useBonusAttacks(uuid)
    local numBonusAttacks = 0
    if M.Osi.GetEquippedWeapon(uuid) ~= nil then
        if M.Osi.HasActiveStatus(uuid, "GREAT_WEAPON_MASTER_BONUS_ATTACK") == 1 then
            Osi.RemoveStatus(uuid, "GREAT_WEAPON_MASTER_BONUS_ATTACK", "")
            numBonusAttacks = numBonusAttacks + 1
        end
        if M.Osi.HasActiveStatus(uuid, "POLEARM_MASTER_BONUS_ATTACK") == 1 then
            Osi.RemoveStatus(uuid, "POLEARM_MASTER_BONUS_ATTACK", "")
            numBonusAttacks = numBonusAttacks + 1
        end
    else
        if M.Osi.HasActiveStatus(uuid, "MARTIAL_ARTS_BONUS_UNARMED_STRIKE") == 1 then
            Osi.RemoveStatus(uuid, "MARTIAL_ARTS_BONUS_UNARMED_STRIKE", "")
            numBonusAttacks = numBonusAttacks + 1
        end
    end
    if not State.Settings.TurnBasedSwarmMode then
        numBonusAttacks = numBonusAttacks + useActionPointSurplus(uuid, "ActionPoint")
        numBonusAttacks = numBonusAttacks + useActionPointSurplus(uuid, "BonusActionPoint")
    end
    return numBonusAttacks
end

local function handleExtraAttacks(attackerUuid, defenderUuid, storyActionID, damageType, damageAmount)
    if State.Settings.TurnBasedSwarmMode and not State.Session.SwarmTurnActive then
        return
    end
    if attackerUuid ~= nil and defenderUuid ~= nil and storyActionID ~= nil and damageAmount ~= nil and damageAmount > 0 then
        if not State.Settings.TurnBasedSwarmMode or M.Utils.isPugnacious(attackerUuid) then
            if State.Session.StoryActionIDs[storyActionID] and State.Session.StoryActionIDs[storyActionID].spellName then
                debugPrint("Handle extra attacks", spellName, attackerUuid, defenderUuid, storyActionID, damageType, damageAmount)
                State.Session.StoryActionIDs[storyActionID] = nil
                local spell = State.getSpellByName(spellName)
                if spell ~= nil and spell.triggersExtraAttack == true then
                    if State.Settings.TurnBasedSwarmMode and M.Utils.isPugnacious(attackerUuid) and spell.isBonusAction then
                        return nil
                    end
                    if State.Session.ExtraAttacksRemaining[attackerUuid] == nil then
                        local brawler = M.Roster.getBrawlerByUuid(attackerUuid)
                        if brawler and M.Utils.isAliveAndCanFight(attackerUuid) and M.Utils.isAliveAndCanFight(defenderUuid) then
                            local numBonusAttacks = useBonusAttacks(attackerUuid)
                            debugPrint("Initiating extra attacks", attackerUuid, spellName, storyActionID, brawler.numExtraAttacks, numBonusAttacks)
                            State.Session.ExtraAttacksRemaining[attackerUuid] = brawler.numExtraAttacks + numBonusAttacks
                            reapplyAttackDamage(attackerUuid, defenderUuid, damageAmount, damageType)
                        end
                    end
                end
            end
        end
    end
end

-- thank u laughingleader
---@param component EsvStatusApplyEventOneFrameComponent
local function onServerStatusApplyEvent(_, _, component)
    if State.Settings.LeaderboardEnabled then
        if component.StatusId == "HEAL" or component.Status.ServerStatus.Type == "HEAL" then
            if component.Target and component.Target.ServerCharacter then
                local statusHandle = component.Status.ServerStatus.StatusHandle
                for _, status in pairs(component.Target.ServerCharacter.StatusManager.Statuses) do
                    if status.StatusHandle == statusHandle and status.CauseGUID and status.HealAmount and not M.Leaderboard.isExcludedHeal(status) then
                        local healerUuid = status.CauseGUID
                        local targetUuid = component.Target.Uuid.EntityUuid
                        local targetMaxHp = component.Target.Health.MaxHp
                        local healAmount = (component.Target.Health.Hp == targetMaxHp) and status.HealAmount or math.min(status.HealAmount, targetMaxHp)
                        debugPrint("healed for", M.Utils.getDisplayName(healerUuid), M.Utils.getDisplayName(targetUuid), status.HealAmount, component.Target.Health.Hp, healAmount)
                        Leaderboard.updateHealing(healerUuid, targetUuid, healAmount)
                        if status.StoryActionID and State.Session.StoryActionIDs[status.StoryActionID] then
                            local spellName = State.Session.StoryActionIDs[status.StoryActionID].spellName
                            if spellName == "Target_TAD_TransfuseHealth" then
                                Leaderboard.updateDamage(healerUuid, healerUuid, healAmount)
                            end
                        end
                        break
                    end
                end
            end
        elseif component.StatusId == "QUIVERING_PALM_HP" then
            if component.Target and component.Target.ServerCharacter then
                local statusHandle = component.Status.ServerStatus.StatusHandle
                for _, status in pairs(component.Target.ServerCharacter.StatusManager.Statuses) do
                    if status.StatusHandle == statusHandle then
                        local casterUuid = status.CauseGUID
                        local targetUuid = component.Target.Uuid.EntityUuid
                        local targetInitialHp = component.Target.Health.Hp
                        if casterUuid and targetUuid and targetInitialHp then
                            Leaderboard.updateDamage(casterUuid, targetUuid, targetInitialHp)
                            Ext.Timer.WaitFor(1000, function ()
                                if M.Osi.IsDead(targetUuid) == 1 then
                                    Leaderboard.updateKills(casterUuid)
                                end
                            end)
                        end
                        break
                    end
                end
            end
        end
    end
end

local function onHitpointsChanged(guid, percentage)
    -- debugPrint("hp changed", guid, percentage)
end

local function onAttackedBy(defenderGuid, attackerGuid, attacker2, damageType, damageAmount, damageCause, storyActionID)
    debugPrint("AttackedBy", defenderGuid, attackerGuid, attacker2, damageType, damageAmount, damageCause, storyActionID)
    local attackerUuid = M.Osi.GetUUID(attackerGuid)
    local defenderUuid = M.Osi.GetUUID(defenderGuid)
    if attackerUuid ~= nil and defenderUuid ~= nil and M.Osi.IsCharacter(attackerUuid) == 1 and M.Osi.IsCharacter(defenderUuid) == 1 then
        if isToT() then
            Roster.addBrawler(attackerUuid, true)
            Roster.addBrawler(defenderUuid, true)
        end
        if M.Osi.IsPlayer(attackerUuid) == 1 then
            State.Session.PlayerCurrentTarget[attackerUuid] = defenderUuid
            if M.Osi.IsPlayer(defenderUuid) == 0 and damageAmount > 0 then
                State.Session.IsAttackingOrBeingAttackedByPlayer[defenderUuid] = attackerUuid
            end
        end
        if M.Osi.IsPlayer(defenderUuid) == 1 then
            if M.Osi.IsPlayer(attackerUuid) == 0 and damageAmount > 0 then
                State.Session.IsAttackingOrBeingAttackedByPlayer[attackerUuid] = defenderUuid
            end
        end
        Leaderboard.updateDamage(attackerUuid, defenderUuid, damageAmount)
    end
    if attackerUuid ~= nil then
        handleExtraAttacks(attackerUuid, defenderUuid, storyActionID, damageType, damageAmount)
    end
end

local function onKilledBy(defenderGuid, attackOwner, attackerGuid, storyActionID)
    debugPrint("KilledBy", defenderGuid, attackOwner, attackerGuid, storyActionID)
    -- NB: attackOwner for summons?
    local attackerUuid = M.Osi.GetUUID(attackerGuid)
    local defenderUuid = M.Osi.GetUUID(defenderGuid)
    Leaderboard.updateKills(attackerUuid)
    if State.Session.StoryActionIDs[storyActionID] then
        local spellName = State.Session.StoryActionIDs[storyActionID].spellName
        if spellName == "Target_PowerWordKill" or spellName == "Target_ATT_PowerWordKill" then
            Leaderboard.updateDamage(attackerUuid, defenderUuid, 100)
        end
    end
    State.Session.ExtraAttacksRemaining[attackerUuid] = nil
    State.Session.ExtraAttacksRemaining[defenderUuid] = nil
end

local function onUsingSpellOnTarget(casterGuid, targetGuid, spellName, spellType, spellElement, storyActionID)
    local casterUuid = M.Osi.GetUUID(casterGuid)
    local targetUuid = M.Osi.GetUUID(targetGuid)
    if casterUuid and targetUuid and spellName then
        -- print(M.Utils.getDisplayName(casterUuid), "UsingSpellOnTarget", M.Utils.getDisplayName(targetUuid), spellName, spellType, spellElement, storyActionID)
        if not State.Session.StoryActionIDs[storyActionID] then
            State.Session.StoryActionIDs[storyActionID] = {}
        end
        State.Session.StoryActionIDs[storyActionID].casterUuid = casterUuid
        State.Session.StoryActionIDs[storyActionID].spellName = spellName
        State.Session.StoryActionIDs[storyActionID].targetUuid = targetUuid
        -- NB: what other instakill effects are there? Word of Bhaal, chasms...?
        -- if spellName == "Target_PowerWordKill" or spellName == "Target_ATT_PowerWordKill" then
        --     Leaderboard.updateDamage(casterUuid, targetUuid, Osi.GetHitpoints(targetUuid))
        -- end
    end
end

local function onUsingSpellOnZoneWithTarget(casterGuid, targetGuid, spellName, spellType, spellElement, storyActionID)
    local casterUuid = M.Osi.GetUUID(casterGuid)
    local targetUuid = M.Osi.GetUUID(targetGuid)
    if casterUuid and targetUuid and spellName then
        -- print("UsingSpellOnZoneWithTarget", casterGuid, targetGuid, spell, spellType, spellElement, storyActionID)
        if not State.Session.StoryActionIDs[storyActionID] then
            State.Session.StoryActionIDs[storyActionID] = {}
        end
        State.Session.StoryActionIDs[storyActionID].casterUuid = casterUuid
        State.Session.StoryActionIDs[storyActionID].spellName = spellName
        State.Session.StoryActionIDs[storyActionID].targetUuid = targetUuid
        -- NB: what other instakill effects are there? Word of Bhaal, chasms...?
        -- if spellName == "Target_PowerWordKill" or spellName == "Target_ATT_PowerWordKill" then
        --     Leaderboard.updateDamage(casterUuid, targetUuid, Osi.GetHitpoints(targetUuid))
        -- end
    end
end

local function onUsingSpell(casterGuid, spellName, spellType, spellElement, storyActionID)
    -- print(M.Utils.getDisplayName(M.Osi.GetUUID(casterGuid)), "UsingSpell", casterGuid, spellName, spellType, spellElement, storyActionID)
    local casterUuid = M.Osi.GetUUID(casterGuid)
    if casterUuid and spellName then
        -- print("UsingSpell", casterGuid, targetGuid, spell, spellType, spellElement, storyActionID)
        if not State.Session.StoryActionIDs[storyActionID] then
            State.Session.StoryActionIDs[storyActionID] = {}
        end
        State.Session.StoryActionIDs[storyActionID].casterUuid = casterUuid
        State.Session.StoryActionIDs[storyActionID].spellName = spellName
    end
end

local function onCastedSpell(casterGuid, spellName, spellType, spellElement, storyActionID)
    local casterUuid = M.Osi.GetUUID(casterGuid)
    -- print(M.Utils.getDisplayName(casterUuid), "CastedSpell", casterGuid, spellName, spellType, spellElement, storyActionID)
    local actionInProgress = Actions.getActionInProgressByName(casterUuid, spellName)
    if actionInProgress then
        print("actionInProgress")
        _D(actionInProgress)
        local requestUuid = actionInProgress.requestUuid
        print("Spell cast succeeded! (CastedSpell)")
        Swarm.resumeTimers() -- for interrupts, does this need to be here?
        Utils.checkDivineIntervention(spellName, casterUuid)
        print("onCompleted")
        actionInProgress.onCompleted(spellName)
        Resources.deductCastedSpell(casterUuid, spellName)
        Actions.removeActionInProgress(casterUuid, requestUuid)
    end
    -- _D(State.Session.ActionsInProgress[casterUuid])
    -- Swarm.resumeTimers()
    -- if spellName == "Shout_DivineIntervention_Healing" or spellName == "Shout_DivineIntervention_Healing_Improvement" then
    --     if State.Session.Players then
    --         local areaRadius = Ext.Stats.Get(spellName).AreaRadius
    --         for uuid, _ in pairs(State.Session.Players) do
    --             if Osi.GetDistanceTo(uuid, casterUuid) <= areaRadius then
    --                 Utils.removeNegativeStatuses(uuid)
    --                 Resources.restoreActionResource(Ext.Entity.Get(uuid), "WarPriestActionPoint")
    --                 -- Resources.restoreSpellSlots(uuid)
    --             end
    --         end
    --     end
    -- end
    -- Actions.completeActionInProgress(casterUuid, spellName)
    -- if M.Utils.isCounterspell(spellName) then
    --     local originalCastInfo = State.Session.StoryActionIDs[storyActionID]
    --     debugPrint("got counterspelled", spellName, originalCastInfo.spellName, M.Utils.getDisplayName(originalCastInfo.targetUuid), M.Utils.getDisplayName(originalCastInfo.casterUuid))
    --     if originalCastInfo and originalCastInfo.casterUuid and Resources.removeActionInProgress(originalCastInfo.casterUuid, originalCastInfo.spellName) then
    --         State.Session.StoryActionIDs[storyActionID] = {}
    --         debugPrint("removed counterspelled spell from actions in progress and storyactionIDs")
    --     end
    -- end
end

-- thank u Norb and Mazzle
local function onSpellCastFinishedEvent(cast, _, _)
    if cast and cast.SpellCastState and cast.SpellCastState.Caster and cast.ServerSpellCastState and cast.ServerSpellCastState.StoryActionId then
        -- _D(cast:GetAllComponents())
        local casterUuid = cast.SpellCastState.Caster.Uuid.EntityUuid
        local requestUuid = cast.SpellCastState.SpellCastGuid
        local storyActionId = cast.ServerSpellCastState.StoryActionId
        local actionInProgress = Actions.getActionInProgress(casterUuid, requestUuid)
        if actionInProgress then
            print("SpellCastFinishedEvent", M.Utils.getDisplayName(casterUuid))
            _D(cast.SpellCastOutcome)
            print("actionInProgress")
            _D(actionInProgress)
            local outcome = cast.SpellCastOutcome.Result
            if outcome == "None" then
                local spellName = actionInProgress.spellName
                print("Spell cast succeeded!")
                Swarm.resumeTimers() -- for interrupts, does this need to be here?
                Utils.checkDivineIntervention(spellName, casterUuid)
                print("onCompleted")
                actionInProgress.onCompleted(spellName)
                Resources.deductCastedSpell(casterUuid, spellName)
                Actions.removeActionInProgress(casterUuid, requestUuid)
            else
                print("onFailed")
                if outcome == "CantSpendUseCosts" then
                    -- check for ActionResourceBlock boosts? why did this fail
                    _D(cast:GetAllComponents())
                end
                actionInProgress.onFailed(outcome)
            end
        end
    end
end

-- local function onCastSpellFailed(casterGuid, spellName, spellType, spellElement, storyActionID)
--     local casterUuid = M.Osi.GetUUID(casterGuid)
--     debugPrint(M.Utils.getDisplayName(casterUuid), "CastSpellFailed", casterGuid, spellName, spellType, spellElement, storyActionID)
-- end

local function onDialogStarted(dialog, dialogInstanceId)
    debugPrint("DialogStarted", dialog, dialogInstanceId)
    local level = M.Osi.GetRegion(M.Osi.GetHostCharacter())
    if level then
        stopPulseReposition(level)
        stopBrawlFizzler(level)
        local brawlersInLevel = State.Session.Brawlers[level]
        if brawlersInLevel then
            for brawlerUuid, brawler in pairs(brawlersInLevel) do
                stopPulseAction(brawler, true)
                Utils.clearOsirisQueue(brawlerUuid)
            end
        end
        -- NB: no way to just pause timers, and spinning up a new timer will appear to have a new maximum value...
        -- if dialog == "TUT_Helm_DragonAppears_6ffc2909-a928-4b8b-6901-02d823e68880" then
        --     if State.Session.CountdownTimer.uuid ~= nil and State.Session.CountdownTimer.timer ~= nil then
        --         Quests.stopCountdownTimer(State.Session.CountdownTimer.uuid)
        --         Quests.questTimerCancel("TUT_Helm_Timer")
        --     end
        -- end
    end
end

local function onDialogEnded(dialog, dialogInstanceId)
    debugPrint("DialogEnded", dialog, dialogInstanceId)
    local level = M.Osi.GetRegion(M.Osi.GetHostCharacter())
    if level and not State.Settings.TurnBasedSwarmMode then
        startPulseReposition(level)
        local brawlersInLevel = State.Session.Brawlers[level]
        if brawlersInLevel then
            for brawlerUuid, brawler in pairs(brawlersInLevel) do
                if brawler.isInBrawl and not State.isPlayerControllingDirectly(brawlerUuid) then
                    startPulseAction(brawler)
                end
            end
        end
        -- if dialog == "TUT_Helm_DragonAppears_6ffc2909-a928-4b8b-6901-02d823e68880" then
        --     if State.Session.CountdownTimer.uuid ~= nil and State.Session.CountdownTimer.timer == nil then
        --         Quests.resumeCountdownTimer(State.Session.CountdownTimer.uuid)
        --         Quests.questTimerLaunch("TUT_Helm_Timer", "TUT_Helm_TransponderTimer", State.Session.CountdownTimer.turnsRemaining)
        --     end
        -- end
    end
end

local function onDifficultyChanged(difficulty)
    debugPrint("DifficultyChanged", difficulty)
    Movement.setMovementSpeedThresholds()
end

local function onTeleportedToCamp(character)
    debugPrint("TeleportedToCamp", character)
    local entityUuid = M.Osi.GetUUID(character)
    -- NB: use this for RT too? why remove all?
    if State.Session.TurnBasedSwarmMode then
        if entityUuid then
            local level = M.Osi.GetRegion(entityUuid)
            local brawler = M.Roster.getBrawlerByUuid(entityUuid)
            if level and brawler then
                Roster.removeBrawler(level, entityUuid)
                Roster.checkForEndOfBrawl(level)
            end
        end
    else
        if entityUuid ~= nil and State.Session.Brawlers ~= nil then
            for level, brawlersInLevel in pairs(State.Session.Brawlers) do
                if brawlersInLevel[entityUuid] ~= nil then
                    Roster.removeBrawler(level, entityUuid)
                    Roster.checkForEndOfBrawl(level)
                end
            end
        end
    end
end

local function onTeleportedFromCamp(character)
    debugPrint("TeleportedFromCamp", character)
    local entityUuid = M.Osi.GetUUID(character)
    if entityUuid ~= nil and State.areAnyPlayersBrawling() then
        Roster.addBrawler(entityUuid, false)
    end
end

-- thank u focus
local function onPROC_Subregion_Entered(characterGuid, _)
    if not State.Settings.TurnBasedSwarmMode then
        debugPrint("PROC_Subregion_Entered", characterGuid)
        local uuid = M.Osi.GetUUID(characterGuid)
        local level = M.Osi.GetRegion(uuid)
        if level and State.Session.Players and State.Session.Players[uuid] then
            AI.pulseReposition(level)
        end
    end
end

local function onLevelUnloading(level)
    debugPrint("LevelUnloading", level)
    State.Session.Brawlers[level] = nil
    stopPulseReposition(level)
end

local function onObjectTimerFinished(objectGuid, timer)
    -- debugPrint("ObjectTimerFinished", objectGuid, timer)
    if timer == "TUT_Helm_Timer" then
        Quests.nautiloidTransponderCountdownFinished(M.Osi.GetUUID(objectGuid))
    elseif timer == "HAV_LikesideCombat_CombatRoundTimer" then
        Quests.lakesideRitualCountdownFinished(M.Osi.GetUUID(objectGuid))
    end
end

-- local function onSubQuestUpdateUnlocked(character, subQuestID, stateID)
--     debugPrint("SubQuestUpdateUnlocked", character, subQuestID, stateID)
-- end

-- local function onQuestUpdateUnlocked(character, topLevelQuestID, stateID)
--     debugPrint("QuestUpdateUnlocked", character, topLevelQuestID, stateID)
-- end

-- local function onQuestAccepted(character, questID)
--     debugPrint("QuestAccepted", character, questID)
-- end

-- local function onFlagCleared(flag, speaker, dialogInstance)
--     debugPrint("FlagCleared", flag, speaker, dialogInstance)
-- end

-- local function onFlagLoadedInPresetEvent(object, flag)
--     debugPrint("FlagLoadedInPresetEvent", object, flag)
-- end

local function onFlagSet(flag, speaker, dialogInstance)
    -- print("FlagSet", flag, speaker, dialogInstance)
    if flag == "HAV_LiftingTheCurse_State_HalsinInShadowfell_480305fb-7b0b-4267-aab6-0090ddc12322" then
        Quests.questTimerLaunch("HAV_LikesideCombat_CombatRoundTimer", "HAV_HalsinPortalTimer", Constants.LAKESIDE_RITUAL_COUNTDOWN_TURNS)
        Quests.lakesideRitualCountdown(M.Osi.GetHostCharacter(), Constants.LAKESIDE_RITUAL_COUNTDOWN_TURNS)
    elseif flag == "GLO_Halsin_State_PermaDefeated_86bc3df1-08b4-fbc4-b542-6241bcd03df1" then
        Quests.questTimerCancel("HAV_LikesideCombat_CombatRoundTimer")
        Quests.stopCountdownTimer(M.Osi.GetHostCharacter())
    elseif flag == "HAV_LiftingTheCurse_Event_HalsinClosesPortal_33aa334a-3127-4be1-ad94-518aa4f24ef4" then
        Quests.questTimerCancel("HAV_LikesideCombat_CombatRoundTimer")
        Quests.stopCountdownTimer(M.Osi.GetHostCharacter())
    elseif flag == "TUT_Helm_JoinedMindflayerFight_ec25d7dc-f9d6-47ff-92c9-8921d6e32f54" then
        Quests.questTimerLaunch("TUT_Helm_Timer", "TUT_Helm_TransponderTimer", Constants.NAUTILOID_TRANSPONDER_COUNTDOWN_TURNS)
        Quests.nautiloidTransponderCountdown(M.Osi.GetHostCharacter(), Constants.NAUTILOID_TRANSPONDER_COUNTDOWN_TURNS)
    elseif flag == "TUT_Helm_State_TutorialEnded_55073953-23b9-448c-bee8-4c44d3d67b6b" then
        Quests.questTimerCancel("TUT_Helm_Timer")
        Quests.stopCountdownTimer(M.Osi.GetHostCharacter())
    elseif flag == "DEN_RaidingParty_Event_GateIsOpened_735e0e81-bd67-eb67-87ac-40da4c3e6c49" then
        if not State.Settings.TurnBasedSwarmMode then
            State.endBrawls()
        end
    end
end

local function onStatusApplied(object, status, causee, storyActionID)
    -- debugPrint("StatusApplied", object, status, causee, storyActionID)
    -- if status == "ALCH_POTION_REST_SLEEP_GREATER_RESTORATION" then
    --     Utils.removeNegativeStatuses(M.Osi.GetUUID(object))
    -- end
end

local function onCharacterOnCrimeSensibleActionNotification(character, crimeRegion, crimeID, priortiyName, primaryDialog, criminal1, criminal2, criminal3, criminal4, isPrimary)
    debugPrint("onCharacterOnCrimeSensibleActionNotification", character, crimeRegion, crimeID, priortiyName, primaryDialog, criminal1, criminal2, criminal3, criminal4, isPrimary)
end

local function onCrimeIsRegistered(victim, crimeType, crimeID, evidence, criminal1, criminal2, criminal3, criminal4)
    debugPrint("CrimeIsRegistered", victim, crimeType, crimeID, evidence, criminal1, criminal2, criminal3, criminal4)
end

local function onCrimeProcessingStarted(crimeID, actedOnImmediately)
    debugPrint("CrimeProcessingStarted", crimeID, actedOnImmediately)
end

local function onOnCrimeConfrontationDone(crimeID, investigator, wasLead, criminal1, criminal2, criminal3, criminal4)
    debugPrint("OnCrimeConfrontationDone", crimeID, investigator, wasLead, criminal1, criminal2, criminal3, criminal4)
end

local function onOnCrimeInvestigatorSwitchedState(crimeID, investigator, fromState, toState)
    debugPrint("OnCrimeInvestigatorSwitchedState", crimeID, investigator, fromState, toState)
end

local function onOnCrimeMergedWith(oldCrimeID, newCrimeID)
    debugPrint("OnCrimeMergedWith", oldCrimeID, newCrimeID)
end

local function onOnCrimeRemoved(crimeID, victim, criminal1, criminal2, criminal3, criminal4)
    debugPrint("OnCrimeRemoved", crimeID, victim, criminal1, criminal2, criminal3, criminal4)
end

local function onOnCrimeResetInterrogationForCriminal(crimeID, criminal)
    debugPrint("OnCrimeResetInterrogationForCriminal", crimeID, criminal)
end

local function onOnCrimeResolved(crimeID, victim, criminal1, criminal2, criminal3, criminal4)
    debugPrint("OnCrimeResolved", crimeID, victim, criminal1, criminal2, criminal3, criminal4)
end

local function onOnCriminalMergedWithCrime(crimeID, criminal)
    debugPrint("OnCriminalMergedWithCrime", crimeID, criminal)
end

local function onLeveledUp(character)
    debugPrint("LeveledUp", character)
    if character ~= nil and M.Osi.IsPartyMember(character, 1) == 1 then
        Spells.buildSpellTable()
    end
end

local function onEntityEvent(characterGuid, eventUuid)
    if State.Session.ActiveMovements[eventUuid] and State.Session.ActiveMovements[eventUuid].moverUuid then
        print("EntityEvent", characterGuid, eventUuid)
        local activeMovement = State.Session.ActiveMovements[eventUuid]
        local characterUuid = M.Osi.GetUUID(characterGuid)
        if characterUuid == activeMovement.moverUuid then
            if activeMovement.onMovementCompleted and type(activeMovement.onMovementCompleted) == "function" then
                print("movement completed callback")
                activeMovement.onMovementCompleted()
            end
            State.Session.ActiveMovements[eventUuid] = nil
        end
    end
end

local function onReactionInterruptActionNeeded(characterGuid)
    if State.Settings.TurnBasedSwarmMode then
        debugPrint("ReactionInterruptActionNeeded", characterGuid)
        local uuid = M.Osi.GetUUID(characterGuid)
        if uuid and M.Osi.IsPartyMember(uuid, 1) == 1 then
            Swarm.pauseTimers()
        end
    end
end

local function onServerInterruptUsed(entity, label, component)
    if State.Settings.TurnBasedSwarmMode and component and component.Interrupts then
        for _, interrupt in pairs(component.Interrupts) do
            for interruptEvent, interruptInfo in pairs(interrupt) do
                if interruptEvent.Target and interruptEvent.Target.Uuid and interruptEvent.Target.Uuid.EntityUuid then
                    local targetUuid = interruptEvent.Target.Uuid.EntityUuid
                    debugPrint("interrupted:", M.Utils.getDisplayName(targetUuid), targetUuid)
                    if State.Session.ActionsInProgress[targetUuid] then
                        -- print("Actions In Progress")
                        -- _D(State.Session.ActionsInProgress[targetUuid])
                        local brawler = M.Roster.getBrawlerByUuid(targetUuid)
                        if brawler then
                            Swarm.swarmAction(brawler)
                        end
                    end
                end
            end
        end
    end
end

local function onReactionInterruptUsed(characterGuid, reactionInterruptPrototypeId, isAutoTriggered)
    if State.Settings.TurnBasedSwarmMode then
        debugPrint("ReactionInterruptUsed", characterGuid, reactionInterruptPrototypeId, isAutoTriggered)
        local uuid = M.Osi.GetUUID(characterGuid)
        if uuid and M.Osi.IsPartyMember(uuid, 1) == 1 and isAutoTriggered == 0 then
            Swarm.resumeTimers()
        end
    end
end

-- thank u focus
local function onServerInterruptDecision()
    for _, _ in pairs(Ext.System.ServerInterruptDecision.Decisions) do
        Swarm.resumeTimers()
    end
end

local function stopListeners()
    cleanupAll()
    local listeners = State.Session.Listeners
    for _, listener in pairs(listeners) do
        listener.stop(listener.handle)
    end
end

local function startListeners()
    debugPrint("Starting listeners...")
    State.Session.Listeners.Tick = {}
    State.Session.Listeners.Tick.handle = Ext.Events.Tick:Subscribe(M.clear)
    State.Session.Listeners.Tick.stop = function ()
        Ext.Events.Tick:Unsubscribe(State.Session.Listeners.Tick.handle)
    end
    State.Session.Listeners.ResetCompleted = {}
    State.Session.Listeners.ResetCompleted.handle = Ext.Events.ResetCompleted:Subscribe(onResetCompleted)
    State.Session.Listeners.ResetCompleted.stop = function ()
        Ext.Events.ResetCompleted:Unsubscribe(State.Session.Listeners.ResetCompleted.handle)
    end
    State.Session.Listeners.ServerStatusApplyEvent = {
        handle = Ext.Entity.OnCreateDeferred("ServerStatusApplyEvent", onServerStatusApplyEvent),
        stop = Ext.Entity.Unsubscribe,
    }
    State.Session.Listeners.ServerInterruptUsed = {
        handle = Ext.Entity.OnCreateDeferred("ServerInterruptUsed", onServerInterruptUsed),
        stop = Ext.Entity.Unsubscribe,
    }
    State.Session.Listeners.UserReservedFor = {
        handle = Ext.Entity.Subscribe("UserReservedFor", onUserReservedFor),
        stop = Ext.Entity.Unsubscribe,
    }
    State.Session.Listeners.LevelGameplayStarted = {
        handle = Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", onLevelGameplayStarted),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.CharacterMoveFailedUseJump = {
        handle = Ext.Osiris.RegisterListener("CharacterMoveFailedUseJump", 1, "after", onCharacterMoveFailedUseJump),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.CombatStarted = {
        handle = Ext.Osiris.RegisterListener("CombatStarted", 1, "after", onCombatStarted),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.CombatEnded = {
        handle = Ext.Osiris.RegisterListener("CombatEnded", 1, "after", onCombatEnded),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.CombatRoundStarted = {
        handle = Ext.Osiris.RegisterListener("CombatRoundStarted", 2, "after", onCombatRoundStarted),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.EnteredCombat = {
        handle = Ext.Osiris.RegisterListener("EnteredCombat", 2, "after", onEnteredCombat),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.EnteredForceTurnBased = {
        handle = Ext.Osiris.RegisterListener("EnteredForceTurnBased", 1, "after", onEnteredForceTurnBased),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.LeftForceTurnBased = {
        handle = Ext.Osiris.RegisterListener("LeftForceTurnBased", 1, "after", onLeftForceTurnBased),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.TurnStarted = {
        handle = Ext.Osiris.RegisterListener("TurnStarted", 1, "after", onTurnStarted),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.TurnEnded = {
        handle = Ext.Osiris.RegisterListener("TurnEnded", 1, "after", onTurnEnded),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.Died = {
        handle = Ext.Osiris.RegisterListener("Died", 1, "after", onDied),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.Resurrected = {
        handle = Ext.Osiris.RegisterListener("Resurrected", 1, "after", onResurrected),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.GainedControl = {
        handle = Ext.Osiris.RegisterListener("GainedControl", 1, "after", onGainedControl),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.CharacterJoinedParty = {
        handle = Ext.Osiris.RegisterListener("CharacterJoinedParty", 1, "after", onCharacterJoinedParty),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.CharacterLeftParty = {
        handle = Ext.Osiris.RegisterListener("CharacterLeftParty", 1, "after", onCharacterLeftParty),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.RollResult = {
        handle = Ext.Osiris.RegisterListener("RollResult", 6, "after", onRollResult),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.DownedChanged = {
        handle = Ext.Osiris.RegisterListener("DownedChanged", 2, "after", onDownedChanged),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.KilledBy = {
        handle = Ext.Osiris.RegisterListener("KilledBy", 4, "after", onKilledBy),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.AttackedBy = {
        handle = Ext.Osiris.RegisterListener("AttackedBy", 7, "after", onAttackedBy),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.UsingSpellOnTarget = {
        handle = Ext.Osiris.RegisterListener("UsingSpellOnTarget", 6, "after", onUsingSpellOnTarget),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.UsingSpellOnZoneWithTarget = {
        handle = Ext.Osiris.RegisterListener("UsingSpellOnZoneWithTarget", 6, "after", onUsingSpellOnZoneWithTarget),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.UsingSpell = {
        handle = Ext.Osiris.RegisterListener("UsingSpell", 5, "after", onUsingSpell),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.CastedSpell = {
        handle = Ext.Osiris.RegisterListener("CastedSpell", 5, "after", onCastedSpell),
        stop = Ext.Osiris.UnregisterListener,
    }
    -- State.Session.Listeners.CastSpellFailed = {
    --     handle = Ext.Osiris.RegisterListener("CastSpellFailed", 5, "after", onCastSpellFailed),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    State.Session.Listeners.SpellCastFinishedEvent = {
        handle = Ext.Entity.OnCreateDeferred("SpellCastFinishedEvent", onSpellCastFinishedEvent),
        stop = Ext.Entity.Unsubscribe,
    }
    State.Session.Listeners.DialogStarted = {
        handle = Ext.Osiris.RegisterListener("DialogStarted", 2, "before", onDialogStarted),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.DialogEnded = {
        handle = Ext.Osiris.RegisterListener("DialogEnded", 2, "after", onDialogEnded),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.DifficultyChanged = {
        handle = Ext.Osiris.RegisterListener("DifficultyChanged", 1, "after", onDifficultyChanged),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.TeleportedToCamp = {
        handle = Ext.Osiris.RegisterListener("TeleportedToCamp", 1, "after", onTeleportedToCamp),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.TeleportedFromCamp = {
        handle = Ext.Osiris.RegisterListener("TeleportedFromCamp", 1, "after", onTeleportedFromCamp),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.PROC_Subregion_Entered = {
        handle = Ext.Osiris.RegisterListener("PROC_Subregion_Entered", 2, "after", onPROC_Subregion_Entered),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.LevelUnloading = {
        handle = Ext.Osiris.RegisterListener("LevelUnloading", 1, "after", onLevelUnloading),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.ObjectTimerFinished = {
        handle = Ext.Osiris.RegisterListener("ObjectTimerFinished", 2, "after", onObjectTimerFinished),
        stop = Ext.Osiris.UnregisterListener,
    }
    -- State.Session.Listeners.HitpointsChanged = {
    --     handle = Ext.Osiris.RegisterListener("HitpointsChanged", 2, "after", onHitpointsChanged),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    -- State.Session.Listeners.SubQuestUpdateUnlocked = {
    --     handle = Ext.Osiris.RegisterListener("SubQuestUpdateUnlocked", 3, "after", onSubQuestUpdateUnlocked),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    -- State.Session.Listeners.QuestUpdateUnlocked = {
    --     handle = Ext.Osiris.RegisterListener("QuestUpdateUnlocked", 3, "after", onQuestUpdateUnlocked),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    -- State.Session.Listeners.QuestAccepted = {
    --     handle = Ext.Osiris.RegisterListener("QuestAccepted", 2, "after", onQuestAccepted),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    -- State.Session.Listeners.FlagCleared = {
    --     handle = Ext.Osiris.RegisterListener("FlagCleared", 3, "after", onFlagCleared),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    -- State.Session.Listeners.FlagLoadedInPresetEvent = {
    --     handle = Ext.Osiris.RegisterListener("FlagLoadedInPresetEvent", 2, "after", onFlagLoadedInPresetEvent),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    State.Session.Listeners.FlagSet = {
        handle = Ext.Osiris.RegisterListener("FlagSet", 3, "after", onFlagSet),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.StatusApplied = {
        handle = Ext.Osiris.RegisterListener("StatusApplied", 4, "after", onStatusApplied),
        stop = Ext.Osiris.UnregisterListener,
    }
    -- State.Session.Listeners.CharacterOnCrimeSensibleActionNotification = {
    --     handle = Ext.Osiris.RegisterListener("CharacterOnCrimeSensibleActionNotification", 10, "after", onCharacterOnCrimeSensibleActionNotification),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    -- State.Session.Listeners.CrimeIsRegistered = {
    --     handle = Ext.Osiris.RegisterListener("CrimeIsRegistered", 8, "after", onCrimeIsRegistered),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    -- State.Session.Listeners.CrimeProcessingStarted = {
    --     handle = Ext.Osiris.RegisterListener("CrimeProcessingStarted", 2, "after", onCrimeProcessingStarted),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    -- State.Session.Listeners.OnCrimeConfrontationDone = {
    --     handle = Ext.Osiris.RegisterListener("OnCrimeConfrontationDone", 7, "after", onOnCrimeConfrontationDone),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    -- State.Session.Listeners.OnCrimeInvestigatorSwitchedState = {
    --     handle = Ext.Osiris.RegisterListener("OnCrimeInvestigatorSwitchedState", 4, "after", onOnCrimeInvestigatorSwitchedState),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    -- State.Session.Listeners.OnCrimeMergedWith = {
    --     handle = Ext.Osiris.RegisterListener("OnCrimeMergedWith", 2, "after", onOnCrimeMergedWith),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    -- State.Session.Listeners.OnCrimeRemoved = {
    --     handle = Ext.Osiris.RegisterListener("OnCrimeRemoved", 6, "after", onOnCrimeRemoved),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    -- State.Session.Listeners.OnCrimeResetInterrogationForCriminal = {
    --     handle = Ext.Osiris.RegisterListener("OnCrimeResetInterrogationForCriminal", 2, "after", onOnCrimeResetInterrogationForCriminal),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    -- State.Session.Listeners.OnCrimeResolved = {
    --     handle = Ext.Osiris.RegisterListener("OnCrimeResolved", 6, "after", onOnCrimeResolved),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    -- State.Session.Listeners.OnCriminalMergedWithCrime = {
    --     handle = Ext.Osiris.RegisterListener("OnCriminalMergedWithCrime", 2, "after", onOnCriminalMergedWithCrime),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    State.Session.Listeners.LeveledUp = {
        handle = Ext.Osiris.RegisterListener("LeveledUp", 1, "after", onLeveledUp),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.EntityEvent = {
        handle = Ext.Osiris.RegisterListener("EntityEvent", 2, "after", onEntityEvent),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.ReactionInterruptActionNeeded = {
        handle = Ext.Osiris.RegisterListener("ReactionInterruptActionNeeded", 1, "after", onReactionInterruptActionNeeded),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.ReactionInterruptUsed = {
        handle = Ext.Osiris.RegisterListener("ReactionInterruptUsed", 3, "after", onReactionInterruptUsed),
        stop = Ext.Osiris.UnregisterListener,
    }
    State.Session.Listeners.ServerInterruptDecision = {
        handle = Ext.Entity.OnSystemUpdate("ServerInterruptDecision", onServerInterruptDecision),
        stop = Ext.Entity.Unsubscribe,
    }
end

return {
    onCombatStarted = onCombatStarted,
    onStarted = onStarted,
    stopListeners = stopListeners,
    startListeners = startListeners,
}
