-- ECSPrinter = require("Server/ECSPrinter.lua")

local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump

local function cleanupAll()
    RT.Timers.stopAllPulseAddNearbyTimers()
    RT.Timers.stopAllPulseRepositionTimers()
    RT.Timers.stopAllPulseActionTimers()
    State.endBrawls()
    State.revertAllModifiedHitpoints()
    State.recapPartyMembersMovementDistances()
    Spells.resetSpellData()
end

local function onGameStateChanged(e)
    if e and e.ToState == "UnloadLevel" then
        cleanupAll()
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
        Swarm.Listeners.onStarted()
    else
        RT.Listeners.onStarted()
    end
    Leaderboard.initialize()
    debugDump(State.Session.Players)
    Ext.ServerNet.BroadcastMessage("Started", level)
end

local function onCombatStarted(combatGuid)
    print("CombatStarted", combatGuid)
    if State.Settings.TurnBasedSwarmMode then
        Swarm.Listeners.onCombatStarted()
    end
    -- NB: clean this up / don't reassign "constant" values
    if Utils.isToT() then
        if Mods.ToT.PersistentVars.Scenario and Mods.ToT.PersistentVars.Scenario.Round == 0 then
            State.Session.TBSMToTSkippedPrepRound = false
        else
            State.Session.TBSMToTSkippedPrepRound = true
        end
        Constants.ENTER_COMBAT_RANGE = 100
    else
        Constants.ENTER_COMBAT_RANGE = 20
    end
    Roster.addCombatParticipantsToBrawlers()
    if not State.Settings.TurnBasedSwarmMode then
        RT.Listeners.onCombatStarted(combatGuid)
    end
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
    print("CombatRoundStarted", combatGuid, round)
    Roster.addCombatParticipantsToBrawlers()
    if State.Settings.TurnBasedSwarmMode then
        Swarm.Listeners.onCombatRoundStarted(round)
    else
        RT.Listeners.onCombatRoundStarted(combatGuid, round)
    end
end

-- NB: move all of the endBrawl stuff to here
local function onCombatEnded(combatGuid)
    print("CombatEnded", combatGuid)
    State.Session.StoryActionIDs = {}
    State.Session.MeanInitiativeRoll = nil
    if State.Settings.TurnBasedSwarmMode then
        Swarm.Listeners.onCombatEnded()
    else
        RT.Listeners.onCombatEnded(combatGuid)
    end
end

local function onEnteredCombat(entityGuid, combatGuid)
    debugPrint("EnteredCombat", entityGuid, combatGuid)
    local uuid = M.Osi.GetUUID(entityGuid)
    if uuid then
        Roster.addBrawler(uuid, true)
        if State.Session.Players and State.Session.Players[uuid] then
            debugPrint("initiative roll", TurnOrder.getInitiativeRoll(uuid))
            if State.Session.ResurrectedPlayer[uuid] then
                State.Session.ResurrectedPlayer[uuid] = nil
                TurnOrder.setInitiativeRoll(uuid, TurnOrder.rollForInitiative(uuid))
                debugPrint("updated initiative roll for resurrected player", TurnOrder.getInitiativeRoll(uuid))
                TurnOrder.setPartyInitiativeRollToMean()
            end
        end
        if not State.Settings.TurnBasedSwarmMode then
            RT.Listeners.onEnteredCombat(uuid)
        end
    end
end

local function onEnteredForceTurnBased(entityGuid)
    if not State.Settings.TurnBasedSwarmMode then
        RT.Listeners.onEnteredForceTurnBased(M.Osi.GetUUID(entityGuid))
    end
end

local function onLeftForceTurnBased(entityGuid)
    if not State.Settings.TurnBasedSwarmMode then
        RT.Listeners.onLeftForceTurnBased(M.Osi.GetUUID(entityGuid))
    end
end

local function onTurnStarted(entityGuid)
    print("TurnStarted", entityGuid)
    if State.Settings.TurnBasedSwarmMode then
        Swarm.Listeners.onTurnStarted(M.Osi.GetUUID(entityGuid))
    else
        -- if M.Osi.GetUUID(entityGuid) == State.Session.CombatHelper then
        --     local combatGuid = M.Osi.GetCombatGuidFor(entityGuid)
        --     if combatGuid then
        --         print("got guid, pausing combat...", combatGuid, entityGuid)
        --         Osi.PauseCombat(combatGuid)
        --         Ext.Timer.WaitFor(1000, function ()
        --             print("resming")
        --             Osi.ResumeCombat(combatGuid)
        --             Osi.EndTurn(State.Session.CombatHelper)
        --         end)
        --     end
        -- end 
    end
end

local function onTurnEnded(entityGuid)
    debugPrint("TurnEnded", entityGuid)
    if State.Settings.TurnBasedSwarmMode then
        Swarm.Listeners.onTurnEnded(M.Osi.GetUUID(entityGuid))
    end
end

local function onDied(entityGuid)
    debugPrint("Died", entityGuid)
    local level = M.Osi.GetRegion(entityGuid)
    local entityUuid = M.Osi.GetUUID(entityGuid)
    if State.Settings.TurnBasedSwarmMode then
        Swarm.Listeners.onDied(entityUuid)
    end
    if level and entityUuid and State.Session.Brawlers[level] and State.Session.Brawlers[level][entityUuid] then
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
        Swarm.Listeners.onResurrected(M.Osi.GetUUID(entityGuid))
    end
end

-- NB: entity.ClientControl does NOT get reliably updated immediately when this fires
local function onGainedControl(targetGuid)
    debugPrint("GainedControl", targetGuid)
    local targetUuid = M.Osi.GetUUID(targetGuid)
    if targetUuid ~= nil then
        if targetUuid == Osi.GetHostCharacter() then
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
        if State.Session.Players[targetUuid] then
            local targetUserId = Osi.GetReservedUserID(targetUuid)
            if targetUserId then
                State.Session.Players[targetUuid].isControllingDirectly = true
                for playerUuid, player in pairs(State.Session.Players) do
                    if player.userId == targetUserId and playerUuid ~= targetUuid then
                        player.isControllingDirectly = false
                    end
                end
            end
            if not State.Settings.FullAuto then
                Utils.clearOsirisQueue(targetUuid)
                RT.Timers.stopPulseAction(Roster.getBrawlerByUuid(targetUuid), true)
            end
            if not State.Settings.TurnBasedSwarmMode then
                RT.Listeners.onGainedControl(targetUuid)
            end
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
                Swarm.Listeners.onCharacterJoinedParty(uuid)
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
        -- NB: can remove this??
        -- local level = M.Osi.GetRegion(uuid)
        -- if State.Session.Brawlers and State.Session.Brawlers[level] and State.Session.Brawlers[level][uuid] then
        --     State.Session.Brawlers[level][uuid] = nil
        -- end
    end
end

local function onRollResult(eventName, roller, rollSubject, resultType, isActiveRoll, criticality)
    debugPrint("RollResult", eventName, roller, rollSubject, resultType, isActiveRoll, criticality)
end

local function onDownedChanged(character, isDowned)
    local uuid = M.Osi.GetUUID(character)
    debugPrint("DownedChanged", character, isDowned, uuid)
    local player = State.Session.Players[uuid]
    if player then
        if isDowned == 1 and State.Settings.AutoPauseOnDowned and player.isControllingDirectly then
            local brawler = M.Roster.getBrawlerByUuid(uuid)
            if brawler and not brawler.isPaused then
                Osi.ForceTurnBasedMode(uuid, 1)
            end
        end
        if isDowned == 0 then
            player.isBeingHelped = false
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

local function onAttackedBy(defenderGuid, attackerGuid, attacker2, damageType, damageAmount, damageCause, storyActionID)
    debugPrint("AttackedBy", defenderGuid, attackerGuid, attacker2, damageType, damageAmount, damageCause, storyActionID)
    local attackerUuid = M.Osi.GetUUID(attackerGuid)
    local defenderUuid = M.Osi.GetUUID(defenderGuid)
    if attackerUuid ~= nil and defenderUuid ~= nil and M.Osi.IsCharacter(attackerUuid) == 1 and M.Osi.IsCharacter(defenderUuid) == 1 then
        if M.Utils.isToT() then
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
        Actions.handleExtraAttacks(attackerUuid, defenderUuid, storyActionID, damageType, damageAmount)
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

local function onSpellSyncTargeting(cast, _, _)
    if not State.Settings.TurnBasedSwarmMode then
        RT.Listeners.onSpellSyncTargeting(cast.SpellCastState)
    end
end

local function onDestroySpellSyncTargeting(cast, _, _)
    if not State.Settings.TurnBasedSwarmMode then
        RT.Listeners.onDestroySpellSyncTargeting(cast.SpellCastState)
    end
end

local function onUsingSpellOnTarget(casterGuid, targetGuid, spellName, spellType, spellElement, storyActionID)
    local casterUuid = M.Osi.GetUUID(casterGuid)
    local targetUuid = M.Osi.GetUUID(targetGuid)
    if casterUuid and targetUuid and spellName then
        -- debugPrint(M.Utils.getDisplayName(casterUuid), "UsingSpellOnTarget", M.Utils.getDisplayName(targetUuid), spellName, spellType, spellElement, storyActionID)
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
        -- debugPrint("UsingSpellOnZoneWithTarget", casterGuid, targetGuid, spell, spellType, spellElement, storyActionID)
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
    -- debugPrint(M.Utils.getDisplayName(M.Osi.GetUUID(casterGuid)), "UsingSpell", casterGuid, spellName, spellType, spellElement, storyActionID)
    local casterUuid = M.Osi.GetUUID(casterGuid)
    if casterUuid and spellName then
        -- debugPrint("UsingSpell", casterGuid, targetGuid, spell, spellType, spellElement, storyActionID)
        if not State.Session.StoryActionIDs[storyActionID] then
            State.Session.StoryActionIDs[storyActionID] = {}
        end
        State.Session.StoryActionIDs[storyActionID].casterUuid = casterUuid
        State.Session.StoryActionIDs[storyActionID].spellName = spellName
    end
end

local function onCastedSpell(casterGuid, spellName, spellType, spellElement, storyActionID)
    local casterUuid = M.Osi.GetUUID(casterGuid)
    local actionInProgress = Actions.getActionInProgressByName(casterUuid, spellName)
    if actionInProgress then
        debugPrint(M.Utils.getDisplayName(casterUuid), "CastedSpell", casterGuid, spellName, spellType, spellElement, storyActionID)
        -- debugPrint("actionInProgress")
        -- debugDump(actionInProgress)
        local requestUuid = actionInProgress.requestUuid
        -- debugPrint("Spell cast succeeded! (CastedSpell)")
        Swarm.resumeTimers() -- for interrupts, does this need to be here?
        debugPrint("onCompleted onCastedSpell")
        local onCompleted = actionInProgress.onCompleted
        Actions.removeActionInProgress(casterUuid, requestUuid)
        if not State.Settings.TurnBasedSwarmMode and not State.Settings.HogwildMode then
            Resources.deductCastedSpell(casterUuid, spellName, requestUuid)
        end
        onCompleted(spellName)
    end
    if M.Utils.isCounterspell(spellName) then
        local originalCastInfo = State.Session.StoryActionIDs[storyActionID]
        debugPrint("got counterspelled!", spellName, originalCastInfo.spellName, M.Utils.getDisplayName(originalCastInfo.targetUuid), M.Utils.getDisplayName(originalCastInfo.casterUuid))
        if originalCastInfo and originalCastInfo.casterUuid then
            local actionInProgress = Actions.getActionInProgressByName(casterUuid, spellName)
            if actionInProgress then
                actionInProgress.onFailed("counterspelled")
                Actions.removeActionInProgress(originalCastInfo.casterUuid, originalCastInfo.spellName)
                State.Session.StoryActionIDs[storyActionID] = {}
            end
        end
    end
    Utils.checkDivineIntervention(spellName, casterUuid)
end

-- thank u Norb and Mazzle
local function onSpellCastFinishedEvent(cast, _, _)
    if cast and cast.SpellCastState and cast.SpellCastState.Caster and cast.ServerSpellCastState and cast.ServerSpellCastState.StoryActionId then
        -- _D(cast.SpellCastState)
        -- _D(cast.ServerSpellCastState)
        -- _D(cast:GetAllComponents())
        local casterUuid = cast.SpellCastState.Caster.Uuid.EntityUuid
        local requestUuid = cast.SpellCastState.SpellCastGuid
        local storyActionId = cast.ServerSpellCastState.StoryActionId
        local actionInProgress = Actions.getActionInProgress(casterUuid, requestUuid)
        if actionInProgress then
            debugPrint("SpellCastFinishedEvent", M.Utils.getDisplayName(casterUuid), cast.SpellCastOutcome.Result)
            -- _D(actionInProgress)
            local outcome = cast.SpellCastOutcome.Result
            local spellName = actionInProgress.spellName
            local onCompleted = actionInProgress.onCompleted
            local onFailed = actionInProgress.onFailed
            Actions.removeActionInProgress(casterUuid, requestUuid)
            if outcome == "None" then
                debugPrint("Spell cast succeeded")
                Swarm.resumeTimers() -- for interrupts, does this need to be here?
                debugPrint("onCompleted")
                if not State.Settings.TurnBasedSwarmMode and not State.Settings.HogwildMode then
                    Resources.deductCastedSpell(casterUuid, spellName, requestUuid)
                end
                onCompleted(spellName)
            else
                if outcome == "CantSpendUseCosts" then
                    -- check for ActionResourceBlock boosts? why did this fail
                    debugDump(cast:GetAllComponents())
                end
                debugPrint("onFailed")
                onFailed(outcome)
            end
        end
    end
end

local function onCastSpellFailed(casterGuid, spellName, spellType, spellElement, storyActionID)
    debugPrint(M.Utils.getDisplayName(M.Osi.GetUUID(casterGuid)), "CastSpellFailed", casterGuid, spellName, spellType, spellElement, storyActionID)
end

local function onDialogStarted(...)
    if not State.Settings.TurnBasedSwarmMode then
        RT.Listeners.onDialogStarted()
    end
end

local function onDialogEnded(...)
    if not State.Settings.TurnBasedSwarmMode then
        RT.Listeners.onDialogEnded()
    end
end

-- NB: get rid of this??
local function onDifficultyChanged(difficulty)
    debugPrint("DifficultyChanged", difficulty)
    Movement.setMovementSpeedThresholds()
end

local function onTeleportedToCamp(character)
    debugPrint("TeleportedToCamp", character)
    local uuid = M.Osi.GetUUID(character)
    if State.Settings.TurnBasedSwarmMode then
        Swarm.Listeners.onTeleportedToCamp(uuid)
    else
        RT.Listeners.onTeleportedToCamp(uuid)
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
        RT.Listeners.onPROC_Subregion_Entered(M.Osi.GetUUID(characterGuid))
    end
end

local function onLevelUnloading(level)
    debugPrint("LevelUnloading", level)
    State.Session.Brawlers[level] = nil
    RT.Timers.stopPulseReposition(level)
end

local function onObjectTimerFinished(objectGuid, timer)
    -- debugPrint("ObjectTimerFinished", objectGuid, timer)
    -- if timer == "TUT_Helm_Timer" then
    --     Quests.nautiloidTransponderCountdownFinished(M.Osi.GetUUID(objectGuid))
    -- elseif timer == "HAV_LikesideCombat_CombatRoundTimer" then
    --     Quests.lakesideRitualCountdownFinished(M.Osi.GetUUID(objectGuid))
    -- end
end

-- NB: can remove this??
local function onFlagSet(flag, speaker, dialogInstance)
    -- debugPrint("FlagSet", flag, speaker, dialogInstance)
    -- if flag == "HAV_LiftingTheCurse_State_HalsinInShadowfell_480305fb-7b0b-4267-aab6-0090ddc12322" then
    --     Quests.questTimerLaunch("HAV_LikesideCombat_CombatRoundTimer", "HAV_HalsinPortalTimer", Constants.LAKESIDE_RITUAL_COUNTDOWN_TURNS)
    --     Quests.lakesideRitualCountdown(M.Osi.GetHostCharacter(), Constants.LAKESIDE_RITUAL_COUNTDOWN_TURNS)
    -- elseif flag == "GLO_Halsin_State_PermaDefeated_86bc3df1-08b4-fbc4-b542-6241bcd03df1" then
    --     Quests.questTimerCancel("HAV_LikesideCombat_CombatRoundTimer")
    --     Quests.stopCountdownTimer(M.Osi.GetHostCharacter())
    -- elseif flag == "HAV_LiftingTheCurse_Event_HalsinClosesPortal_33aa334a-3127-4be1-ad94-518aa4f24ef4" then
    --     Quests.questTimerCancel("HAV_LikesideCombat_CombatRoundTimer")
    --     Quests.stopCountdownTimer(M.Osi.GetHostCharacter())
    -- elseif flag == "TUT_Helm_JoinedMindflayerFight_ec25d7dc-f9d6-47ff-92c9-8921d6e32f54" then
    --     Quests.questTimerLaunch("TUT_Helm_Timer", "TUT_Helm_TransponderTimer", Constants.NAUTILOID_TRANSPONDER_COUNTDOWN_TURNS)
    --     Quests.nautiloidTransponderCountdown(M.Osi.GetHostCharacter(), Constants.NAUTILOID_TRANSPONDER_COUNTDOWN_TURNS)
    -- elseif flag == "TUT_Helm_State_TutorialEnded_55073953-23b9-448c-bee8-4c44d3d67b6b" then
    --     Quests.questTimerCancel("TUT_Helm_Timer")
    --     Quests.stopCountdownTimer(M.Osi.GetHostCharacter())
    -- elseif flag == "DEN_RaidingParty_Event_GateIsOpened_735e0e81-bd67-eb67-87ac-40da4c3e6c49" then
    --     if not State.Settings.TurnBasedSwarmMode then
    --         State.endBrawls()
    --     end
    -- end
end

local function onLeveledUp(character)
    debugPrint("LeveledUp", character)
    if character ~= nil and M.Osi.IsPartyMember(character, 1) == 1 then
        Spells.buildSpellTable()
    end
end

local function onEntityEvent(characterGuid, eventUuid)
    if State.Session.ActiveMovements[eventUuid] then
        debugPrint("EntityEvent", characterGuid, eventUuid)
        Movement.finishMovement(M.Osi.GetUUID(characterGuid), eventUuid, State.Session.ActiveMovements[eventUuid])
    end
end

local function onReactionInterruptActionNeeded(characterGuid)
    debugPrint("ReactionInterruptActionNeeded", characterGuid)
    if State.Settings.TurnBasedSwarmMode then
        Swarm.Listeners.onReactionInterruptActionNeeded(M.Osi.GetUUID(characterGuid))
    end
    Movement.pauseTimers()
end

local function onServerInterruptUsed(entity, label, component)
    if State.Settings.TurnBasedSwarmMode then
        Swarm.Listeners.onServerInterruptUsed(entity, label, component)
    end
end

local function onReactionInterruptUsed(characterGuid, reactionInterruptPrototypeId, isAutoTriggered)
    debugPrint("ReactionInterruptUsed", characterGuid, reactionInterruptPrototypeId, isAutoTriggered)
    if State.Settings.TurnBasedSwarmMode then
        Swarm.Listeners.onReactionInterruptUsed(M.Osi.GetUUID(characterGuid), isAutoTriggered)
    end
    Movement.resumeTimers()
end

local function onServerInterruptDecision()
    if State.Settings.TurnBasedSwarmMode then
        Swarm.Listeners.onServerInterruptDecision()
    end
    Movement.resumeTimers()
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
    State.Session.Listeners.SpellSyncTargeting = {
        handle = Ext.Entity.OnCreateDeferred("SpellSyncTargeting", onSpellSyncTargeting),
        stop = Ext.Entity.Unsubscribe,
    }
    State.Session.Listeners.DestroySpellSyncTargeting = {
        handle = Ext.Entity.OnDestroy("SpellSyncTargeting", onDestroySpellSyncTargeting),
        stop = Ext.Entity.Unsubscribe,
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

local function onMCMSettingSaved(payload)
    if payload and payload.modUUID == ModuleUUID and payload.settingId and Commands.MCMSettingSaved[payload.settingId] then
        Commands.MCMSettingSaved[payload.settingId](payload.value)
    end
end

local function onNetMessage(data)
    if Commands.NetMessage[data.Channel] then
        Commands.NetMessage[data.Channel](data)
    end
end

local function startSession()
    if not State or not State.Settings then
        return Ext.Timer.WaitFor(250, startSession)
    end
    if State.Settings.ModEnabled then
        startListeners()
    else
        Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", State.resetPlayers)
    end
end

local function onSessionLoaded()
    Ext.Events.GameStateChanged:Subscribe(onGameStateChanged)
    if MCM then
        Ext.ModEvents.BG3MCM["MCM_Setting_Saved"]:Subscribe(onMCMSettingSaved)
    end
    Ext.Events.NetMessage:Subscribe(onNetMessage)
    startSession()
end

return {
    onCombatStarted = onCombatStarted,
    onStarted = onStarted,
    stopListeners = stopListeners,
    startListeners = startListeners,
    onSessionLoaded = onSessionLoaded,
}
