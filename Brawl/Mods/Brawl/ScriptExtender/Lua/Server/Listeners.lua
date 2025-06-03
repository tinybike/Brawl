-- local Constants = require("Server/Constants.lua")
-- local Utils = require("Server/Utils.lua")
-- local State = require("Server/State.lua")
-- local Resources = require("Server/Resources.lua")
-- local Movement = require("Server/Movement.lua")
-- local Roster = require("Server/Roster.lua")
-- local AI = require("Server/AI.lua")
-- local Pause = require("Server/Pause.lua")
-- local Quests = require("Server/Quests.lua")
-- local Commands = require("Server/Commands.lua")

local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump
local getDisplayName = Utils.getDisplayName
local isToT = Utils.isToT

local function onCombatStarted(combatGuid)
    debugPrint("CombatStarted", combatGuid)
    local players = State.Session.Players
    for playerUuid, _ in pairs(players) do
        Roster.addBrawler(playerUuid, true)
    end
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
        -- debugDump(State.Session.Brawlers)
        if not isToT() then
            Constants.ENTER_COMBAT_RANGE = 20
            startBrawlFizzler(level)
            Ext.Timer.WaitFor(500, function ()
                Roster.addNearbyToBrawlers(Osi.GetHostCharacter(), Constants.NEARBY_RADIUS, combatGuid)
                Ext.Timer.WaitFor(1500, function ()
                    if Osi.CombatIsActive(combatGuid) then
                        Osi.EndCombat(combatGuid)
                    end
                end)
            end)
        else
            Constants.ENTER_COMBAT_RANGE = 100
            startToTTimers()
        end
    end
end

local function onStarted(level)
    debugPrint("onStarted")
    State.resetSpellData()
    State.buildSpellTable()
    State.setMaxPartySize()
    State.resetPlayers()
    State.setIsControllingDirectly()
    Movement.setMovementSpeedThresholds()
    Movement.resetPlayersMovementSpeed()
    State.setupPartyMembersHitpoints()
    State.uncapPartyMembersMovementDistances()
    Roster.initBrawlers(level)
    Pause.checkTruePauseParty()
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
    if not isToT() then
        Constants.ENTER_COMBAT_RANGE = 20
        onCombatStarted(combatGuid)
    else
        startToTTimers()
    end
end

local function onCombatEnded(combatGuid)
    debugPrint("CombatEnded", combatGuid)
end

local function onEnteredCombat(entityGuid, combatGuid)
    debugPrint("EnteredCombat", entityGuid, combatGuid)
    Roster.addBrawler(Osi.GetUUID(entityGuid), true)
end

local function onEnteredForceTurnBased(entityGuid)
    local entityUuid = Osi.GetUUID(entityGuid)
    local level = Osi.GetRegion(entityGuid)
    if level and entityUuid then
        local isPlayer = State.Session.Players and State.Session.Players[entityUuid]
        if isPlayer then
            debugPrint("EnteredForceTurnBased", entityGuid)
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
            stopPulseReposition(level)
            stopBrawlFizzler(level)
            if isToT() then
                stopToTTimers()
            end
        end
        if State.Settings.TruePause then
            Pause.startTruePause(entityUuid)
        end
        if isPlayer then
            local brawlersInLevel = State.Session.Brawlers[level]
            if brawlersInLevel then
                for brawlerUuid, brawler in pairs(brawlersInLevel) do
                    if brawlerUuid ~= entityUuid and not brawlersInLevel[brawlerUuid].isPaused then
                        stopPulseAction(brawler, true)
                        if State.Session.Players[brawlerUuid] then
                            brawlersInLevel[brawlerUuid].isPaused = true
                            Osi.ForceTurnBasedMode(brawlerUuid, 1)
                        end
                    end
                end
            end
        end
    end
end

local function onLeftForceTurnBased(entityGuid)
    debugPrint("LeftForceTurnBased", entityGuid)
    local entityUuid = Osi.GetUUID(entityGuid)
    local level = Osi.GetRegion(entityGuid)
    if level and entityUuid and State.Session.Players and State.Session.Players[entityUuid] then
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

local function onTurnEnded(entityGuid)
    -- NB: how's this work for the "environmental turn"?
    debugPrint("TurnEnded", entityGuid)
end

local function onDied(entityGuid)
    debugPrint("Died", entityGuid)
    local level = Osi.GetRegion(entityGuid)
    local entityUuid = Osi.GetUUID(entityGuid)
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

-- NB: entity.ClientControl does NOT get reliably updated immediately when this fires
local function onGainedControl(targetGuid)
    debugPrint("GainedControl", targetGuid)
    local targetUuid = Osi.GetUUID(targetGuid)
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
        Utils.clearOsirisQueue(targetUuid)
        local targetUserId = Osi.GetReservedUserID(targetUuid)
        local players = State.Session.Players
        if players[targetUuid] ~= nil and targetUserId ~= nil then
            players[targetUuid].isControllingDirectly = true
            startPulseAddNearby(targetUuid)
            local level = Osi.GetRegion(targetUuid)
            local brawlersInLevel = State.Session.Brawlers[level]
            for playerUuid, player in pairs(players) do
                if player.userId == targetUserId and playerUuid ~= targetUuid then
                    player.isControllingDirectly = false
                    if level and brawlersInLevel and brawlersInLevel[playerUuid] and brawlersInLevel[playerUuid].isInBrawl then
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
    local uuid = Osi.GetUUID(character)
    if uuid then
        if State.Session.Players and not State.Session.Players[uuid] then
            State.setupPlayer(uuid)
            State.setupPartyMembersHitpoints()
            State.uncapPartyMembersMovementDistances()
        end
        if State.areAnyPlayersBrawling() then
            Roster.addBrawler(uuid, true)
        end
        if Osi.IsSummon(uuid) == 1 then
            State.Session.Players[uuid].isFreshSummon = true
        end
    end
end

local function onCharacterLeftParty(character)
    debugPrint("CharacterLeftParty", character)
    local uuid = Osi.GetUUID(character)
    if uuid then
        if State.Session.Players and State.Session.Players[uuid] then
            State.Session.Players[uuid] = nil
        end
        local level = Osi.GetRegion(uuid)
        if State.Session.Brawlers and State.Session.Brawlers[level] and State.Session.Brawlers[level][uuid] then
            State.Session.Brawlers[level][uuid] = nil
        end
    end
end

local function onRollResult(eventName, roller, rollSubject, resultType, isActiveRoll, criticality)
    debugPrint("RollResult", eventName, roller, rollSubject, resultType, isActiveRoll, criticality)
end

local function onDownedChanged(character, isDowned)
    local entityUuid = Osi.GetUUID(character)
    debugPrint("DownedChanged", character, isDowned, entityUuid)
    local player = State.Session.Players[entityUuid]
    local level = Osi.GetRegion(entityUuid)
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
    return hasExtraAttacksRemaining(attackerUuid) and Utils.isAliveAndCanFight(attackerUuid) and Utils.isAliveAndCanFight(defenderUuid)
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

local function decreaseActionResource(uuid, resourceType, amount)
    local entity = Ext.Entity.Get(uuid)
    if entity and entity.ActionResources and entity.ActionResources.Resources then
        local resources = entity.ActionResources.Resources[Constants.ACTION_RESOURCES[resourceType]]
        if resources then
            resources[1].Amount = resources[1].Amount - amount
        end
    end
    entity:Replicate("ActionResources")
end

local function useActionPointSurplus(uuid, resourceType)
    local pointSurplus = math.floor(Osi.GetActionResourceValuePersonal(uuid, resourceType, 0) - 1)
    if pointSurplus > 0 then
        decreaseActionResource(uuid, resourceType, pointSurplus)
    end
    return pointSurplus
end

local function useBonusAttacks(uuid)
    local numBonusAttacks = 0
    if Osi.GetEquippedWeapon(uuid) ~= nil then
        if Osi.HasActiveStatus(uuid, "GREAT_WEAPON_MASTER_BONUS_ATTACK") == 1 then
            Osi.RemoveStatus(uuid, "GREAT_WEAPON_MASTER_BONUS_ATTACK", "")
            numBonusAttacks = numBonusAttacks + 1
        end
        if Osi.HasActiveStatus(uuid, "POLEARM_MASTER_BONUS_ATTACK") == 1 then
            Osi.RemoveStatus(uuid, "POLEARM_MASTER_BONUS_ATTACK", "")
            numBonusAttacks = numBonusAttacks + 1
        end
    else
        if Osi.HasActiveStatus(uuid, "MARTIAL_ARTS_BONUS_UNARMED_STRIKE") == 1 then
            Osi.RemoveStatus(uuid, "MARTIAL_ARTS_BONUS_UNARMED_STRIKE", "")
            numBonusAttacks = numBonusAttacks + 1
        end
    end
    return numBonusAttacks + useActionPointSurplus(uuid, "ActionPoint") + useActionPointSurplus(uuid, "BonusActionPoint")
end

local function handleExtraAttacks(attackerUuid, defenderUuid, storyActionID, damageType, damageAmount)
    if attackerUuid ~= nil and defenderUuid ~= nil and storyActionID ~= nil and damageAmount ~= nil and damageAmount > 0 then
        local spellName = State.Session.StoryActionIDSpellName[storyActionID]
        if spellName ~= nil then
            debugPrint("Handle extra attacks", spellName, attackerUuid, defenderUuid, storyActionID, damageType, damageAmount)
            State.Session.StoryActionIDSpellName[storyActionID] = nil
            local spell = State.getSpellByName(spellName)
            if spell ~= nil and spell.triggersExtraAttack == true then
                if State.Session.ExtraAttacksRemaining[attackerUuid] == nil then
                    local brawler = State.getBrawlerByUuid(attackerUuid)
                    if brawler and Utils.isAliveAndCanFight(attackerUuid) and Utils.isAliveAndCanFight(defenderUuid) then
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

local function onAttackedBy(defenderGuid, attackerGuid, attacker2, damageType, damageAmount, damageCause, storyActionID)
    debugPrint("AttackedBy", defenderGuid, attackerGuid, attacker2, damageType, damageAmount, damageCause, storyActionID)
    local attackerUuid = Osi.GetUUID(attackerGuid)
    local defenderUuid = Osi.GetUUID(defenderGuid)
    if attackerUuid ~= nil and defenderUuid ~= nil and Osi.IsCharacter(attackerUuid) == 1 and Osi.IsCharacter(defenderUuid) == 1 then
        if isToT() then
            Roster.addBrawler(attackerUuid, true)
            Roster.addBrawler(defenderUuid, true)
        end
        if Osi.IsPlayer(attackerUuid) == 1 then
            State.Session.PlayerCurrentTarget[attackerUuid] = defenderUuid
            if Osi.IsPlayer(defenderUuid) == 0 and damageAmount > 0 then
                State.Session.IsAttackingOrBeingAttackedByPlayer[defenderUuid] = attackerUuid
            end
            -- NB: is this needed?
            if isToT() then
                -- Roster.addNearbyToBrawlers(attackerUuid, 30, nil, true)
                Roster.addNearbyToBrawlers(attackerUuid, 30)
            end
        end
        if Osi.IsPlayer(defenderUuid) == 1 then
            if Osi.IsPlayer(attackerUuid) == 0 and damageAmount > 0 then
                State.Session.IsAttackingOrBeingAttackedByPlayer[attackerUuid] = defenderUuid
            end
            -- NB: is this needed?
            if isToT() then
                -- Roster.addNearbyToBrawlers(defenderUuid, 30, nil, true)
                Roster.addNearbyToBrawlers(defenderUuid, 30)
            end
        end
        -- print("attacked by fizz")
        -- startBrawlFizzler(Osi.GetRegion(attackerUuid))
    end
    if attackerUuid ~= nil then
        handleExtraAttacks(attackerUuid, defenderUuid, storyActionID, damageType, damageAmount)
    end
end

local function onUsingSpellOnTarget(casterGuid, targetGuid, spellName, spellType, spellElement, storyActionID)
    debugPrint("UsingSpellOnTarget", casterGuid, targetGuid, spellName, spellType, spellElement, storyActionID)
    if spellName ~= nil then
        State.Session.StoryActionIDSpellName[storyActionID] = spellName
    end
end

local function onKilledBy(defenderGuid, attackOwner, attackerGuid, storyActionID)
    debugPrint("KilledBy", defenderGuid, attackOwner, attackerGuid, storyActionID)
    State.Session.ExtraAttacksRemaining[Osi.GetUUID(attackerGuid)] = nil
    State.Session.ExtraAttacksRemaining[Osi.GetUUID(defenderGuid)] = nil
end

local function onUsingSpellOnZoneWithTarget(caster, target, spell, spellType, spellElement, storyActionID)
    debugPrint("UsingSpellOnZoneWithTarget", caster, target, spell, spellType, spellElement, storyActionID)
end

local function onUsingSpell(caster, spell, spellType, spellElement, storyActionID)
    debugPrint("UsingSpell", caster, spell, spellType, spellElement, storyActionID)
end

local function onCastedSpell(casterGuid, spellName, spellType, spellElement, storyActionID)
    debugPrint("CastedSpell", casterGuid, spellName, spellType, spellElement, storyActionID)
    local casterUuid = Osi.GetUUID(casterGuid)
    debugDump(State.Session.ActionsInProgress[casterUuid])
    if Resources.removeActionInProgress(casterUuid, spellName) then
        Resources.deductCastedSpell(casterUuid, spellName)
    end
end

local function onDialogStarted(dialog, dialogInstanceId)
    debugPrint("DialogStarted", dialog, dialogInstanceId)
    local level = Osi.GetRegion(Osi.GetHostCharacter())
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
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
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
    local entityUuid = Osi.GetUUID(character)
    if entityUuid ~= nil and State.Session.Brawlers ~= nil then
        for level, brawlersInLevel in pairs(State.Session.Brawlers) do
            if brawlersInLevel[entityUuid] ~= nil then
                Roster.removeBrawler(level, entityUuid)
                Roster.checkForEndOfBrawl(level)
            end
        end
    end
end

local function onTeleportedFromCamp(character)
    local entityUuid = Osi.GetUUID(character)
    if entityUuid ~= nil and State.areAnyPlayersBrawling() then
        Roster.addBrawler(entityUuid, false)
    end
end

-- thank u focus
local function onPROC_Subregion_Entered(characterGuid, _)
    debugPrint("PROC_Subregion_Entered", characterGuid)
    local uuid = Osi.GetUUID(characterGuid)
    local level = Osi.GetRegion(uuid)
    if level and State.Session.Players and State.Session.Players[uuid] then
        AI.pulseReposition(level)
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
        Quests.nautiloidTransponderCountdownFinished(Osi.GetUUID(objectGuid))
    elseif timer == "HAV_LikesideCombat_CombatRoundTimer" then
        Quests.lakesideRitualCountdownFinished(Osi.GetUUID(objectGuid))
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
    debugPrint("FlagSet", flag, speaker, dialogInstance)
    if flag == "HAV_LiftingTheCurse_State_HalsinInShadowfell_480305fb-7b0b-4267-aab6-0090ddc12322" then
        Quests.questTimerLaunch("HAV_LikesideCombat_CombatRoundTimer", "HAV_HalsinPortalTimer", Constants.LAKESIDE_RITUAL_COUNTDOWN_TURNS)
        Quests.lakesideRitualCountdown(Osi.GetHostCharacter(), Constants.LAKESIDE_RITUAL_COUNTDOWN_TURNS)
    elseif flag == "GLO_Halsin_State_PermaDefeated_86bc3df1-08b4-fbc4-b542-6241bcd03df1" then
        Quests.questTimerCancel("HAV_LikesideCombat_CombatRoundTimer")
        Quests.stopCountdownTimer(Osi.GetHostCharacter())
    elseif flag == "HAV_LiftingTheCurse_Event_HalsinClosesPortal_33aa334a-3127-4be1-ad94-518aa4f24ef4" then
        Quests.questTimerCancel("HAV_LikesideCombat_CombatRoundTimer")
        Quests.stopCountdownTimer(Osi.GetHostCharacter())
    elseif flag == "TUT_Helm_JoinedMindflayerFight_ec25d7dc-f9d6-47ff-92c9-8921d6e32f54" then
        Quests.questTimerLaunch("TUT_Helm_Timer", "TUT_Helm_TransponderTimer", Constants.NAUTILOID_TRANSPONDER_COUNTDOWN_TURNS)
        Quests.nautiloidTransponderCountdown(Osi.GetHostCharacter(), Constants.NAUTILOID_TRANSPONDER_COUNTDOWN_TURNS)
    elseif flag == "TUT_Helm_State_TutorialEnded_55073953-23b9-448c-bee8-4c44d3d67b6b" then
        Quests.questTimerCancel("TUT_Helm_Timer")
        Quests.stopCountdownTimer(Osi.GetHostCharacter())
    end
end

-- local function onStatusApplied(object, status, causee, storyActionID)
--     debugPrint("StatusApplied", object, status, causee, storyActionID)
-- end

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
    if character ~= nil and Osi.GetUUID(character) == Osi.GetHostCharacter() then
        State.buildSpellTable()
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
    State.Session.Listeners.ResetCompleted = {}
    State.Session.Listeners.ResetCompleted.handle = Ext.Events.ResetCompleted:Subscribe(onResetCompleted)
    State.Session.Listeners.ResetCompleted.stop = function ()
        Ext.Events.ResetCompleted:Unsubscribe(State.Session.Listeners.ResetCompleted.handle)
    end
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
    -- State.Session.Listeners.TurnEnded = {
    --     handle = Ext.Osiris.RegisterListener("TurnEnded", 1, "after", onTurnEnded),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    State.Session.Listeners.Died = {
        handle = Ext.Osiris.RegisterListener("Died", 1, "after", onDied),
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
    -- State.Session.Listeners.StatusApplied = {
    --     handle = Ext.Osiris.RegisterListener("StatusApplied", 4, "after", onStatusApplied),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
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
end

return {
    onCombatStarted = onCombatStarted,
    onStarted = onStarted,
    stopListeners = stopListeners,
    startListeners = startListeners,
}
