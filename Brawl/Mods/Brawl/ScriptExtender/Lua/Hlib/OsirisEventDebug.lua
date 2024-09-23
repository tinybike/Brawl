---@type Utils
local Utils = Require("Hlib/Utils")

---@type Log
local Log = Require("Hlib/Log")

local M = {}

M.Events = {}

M.Listeners = {}

---@param events string[]|nil
function M.Attach(events)
    local eventDef = M.Events

    if type(events) == "table" then
        eventDef = Utils.Table.Filter(eventDef, function(v, k)
            return Utils.Table.Contains(events, k)
        end)
    end

    for name, params in pairs(eventDef) do
        params = Utils.String.Split(params, ",")
        if params[1] == "" then
            params = {}
        end
        table.insert(
            M.Listeners,
            Ext.Osiris.RegisterListener(name, #params, "after", function(...)
                local log = {}
                for i, v in ipairs(params) do
                    v = Utils.String.Trim(v)
                    log[v] = select(i, ...)
                end
                Log.Dump(name, log)
            end)
        )
    end
end

function M.Detach()
    for _, listener in ipairs(M.Listeners) do
        Ext.Osiris.UnregisterListener(listener)
    end
    M.Listeners = {}
end

-- copied from Osi.Events.lua

---@param object GUIDSTRING
M.Events.Activated = "object"

---@param instanceID integer
---@param player GUIDSTRING
---@param oldIndex integer
---@param newIndex integer
M.Events.ActorSpeakerIndexChanged = "instanceID, player, oldIndex, newIndex"

---@param object GUIDSTRING
---@param inventoryHolder GUIDSTRING
---@param addType string
M.Events.AddedTo = "object, inventoryHolder, addType"

M.Events.AllLoadedFlagsInPresetReceivedEvent = ""

---@param object GUIDSTRING
---@param eventName string
---@param wasFromLoad integer
M.Events.AnimationEvent = "object, eventName, wasFromLoad"

---@param character CHARACTER
---@param appearEvent string
M.Events.AppearTeleportFailed = "character, appearEvent"

---@param ratingOwner CHARACTER
---@param ratedEntity CHARACTER
---@param attemptedApprovalChange integer
---@param clampedApprovalChange integer
---@param newApproval integer
M.Events.ApprovalRatingChangeAttempt =
    "ratingOwner, ratedEntity, attemptedApprovalChange, clampedApprovalChange, newApproval"

---@param ratingOwner CHARACTER
---@param ratedEntity CHARACTER
---@param newApproval integer
M.Events.ApprovalRatingChanged = "ratingOwner, ratedEntity, newApproval"

---@param character CHARACTER
---@param item ITEM
M.Events.ArmedTrapUsed = "character, item"

---@param character CHARACTER
---@param eArmorSet ARMOURSET
M.Events.ArmorSetChanged = "character, eArmorSet"

---@param character CHARACTER
M.Events.AttachedToPartyGroup = "character"

---@param defender GUIDSTRING
---@param attackerOwner GUIDSTRING
---@param attacker2 GUIDSTRING
---@param damageType string
---@param damageAmount integer
---@param damageCause string
---@param storyActionID integer
M.Events.AttackedBy = "defender, attackerOwner, attacker2, damageType, damageAmount, damageCause, storyActionID"

---@param disarmableItem ITEM
---@param character CHARACTER
---@param itemUsedToDisarm ITEM
---@param bool integer
M.Events.AttemptedDisarm = "disarmableItem, character, itemUsedToDisarm, bool"

---@param dialog DIALOGRESOURCE
---@param instanceID integer
M.Events.AutomatedDialogEnded = "dialog, instanceID"

---@param dialog DIALOGRESOURCE
---@param instanceID integer
M.Events.AutomatedDialogForceStopping = "dialog, instanceID"

---@param dialog DIALOGRESOURCE
---@param instanceID integer
M.Events.AutomatedDialogRequestFailed = "dialog, instanceID"

---@param dialog DIALOGRESOURCE
---@param instanceID integer
M.Events.AutomatedDialogStarted = "dialog, instanceID"

---@param character CHARACTER
---@param goal GUIDSTRING
M.Events.BackgroundGoalFailed = "character, goal"

---@param character CHARACTER
---@param goal GUIDSTRING
M.Events.BackgroundGoalRewarded = "character, goal"

---@param target CHARACTER
---@param oldFaction FACTION
---@param newFaction FACTION
M.Events.BaseFactionChanged = "target, oldFaction, newFaction"

---@param spline SPLINE
---@param character CHARACTER
---@param event string
---@param index integer
---@param last integer
M.Events.CameraReachedNode = "spline, character, event, index, last"

---@param lootingTarget GUIDSTRING
---@param canBeLooted integer
M.Events.CanBeLootedCapabilityChanged = "lootingTarget, canBeLooted"

---@param caster GUIDSTRING
---@param spell string
---@param spellType string
---@param spellElement string
---@param storyActionID integer
M.Events.CastSpell = "caster, spell, spellType, spellElement, storyActionID"

---@param caster GUIDSTRING
---@param spell string
---@param spellType string
---@param spellElement string
---@param storyActionID integer
M.Events.CastSpellFailed = "caster, spell, spellType, spellElement, storyActionID"

---@param caster GUIDSTRING
---@param spell string
---@param spellType string
---@param spellElement string
---@param storyActionID integer
M.Events.CastedSpell = "caster, spell, spellType, spellElement, storyActionID"

---@param character CHARACTER
M.Events.ChangeAppearanceCancelled = "character"

---@param character CHARACTER
M.Events.ChangeAppearanceCompleted = "character"

M.Events.CharacterCreationFinished = ""

M.Events.CharacterCreationStarted = ""

---@param character CHARACTER
---@param item ITEM
---@param slotName EQUIPMENTSLOTNAME
M.Events.CharacterDisarmed = "character, item, slotName"

---@param character CHARACTER
M.Events.CharacterJoinedParty = "character"

---@param character CHARACTER
M.Events.CharacterLeftParty = "character"

---@param character CHARACTER
M.Events.CharacterLoadedInPreset = "character"

---@param player CHARACTER
---@param lootedCharacter CHARACTER
M.Events.CharacterLootedCharacter = "player, lootedCharacter"

---@param character CHARACTER
M.Events.CharacterMadePlayer = "character"

---@param character CHARACTER
M.Events.CharacterMoveFailedUseJump = "character"

---@param character CHARACTER
---@param target GUIDSTRING
---@param moveID string
---@param failureReason string
M.Events.CharacterMoveToAndTalkFailed = "character, target, moveID, failureReason"

---@param character CHARACTER
---@param target GUIDSTRING
---@param dialog DIALOGRESOURCE
---@param moveID string
M.Events.CharacterMoveToAndTalkRequestDialog = "character, target, dialog, moveID"

---@param character CHARACTER
---@param moveID integer
M.Events.CharacterMoveToCancelled = "character, moveID"

---@param character CHARACTER
---@param crimeRegion string
---@param crimeID integer
---@param priortiyName string
---@param primaryDialog DIALOGRESOURCE
---@param criminal1 CHARACTER
---@param criminal2 CHARACTER
---@param criminal3 CHARACTER
---@param criminal4 CHARACTER
---@param isPrimary integer
M.Events.CharacterOnCrimeSensibleActionNotification =
    "character, crimeRegion, crimeID, priortiyName, primaryDialog, criminal1, criminal2, criminal3, criminal4, isPrimary"

---@param player CHARACTER
---@param npc CHARACTER
M.Events.CharacterPickpocketFailed = "player, npc"

---@param player CHARACTER
---@param npc CHARACTER
---@param item ITEM
---@param itemTemplate GUIDSTRING
---@param amount integer
---@param goldValue integer
M.Events.CharacterPickpocketSuccess = "player, npc, item, itemTemplate, amount, goldValue"

---@param character CHARACTER
---@param oldUserID integer
---@param newUserID integer
M.Events.CharacterReservedUserIDChanged = "character, oldUserID, newUserID"

---@param character CHARACTER
---@param crimeRegion string
---@param unavailableForCrimeID integer
---@param busyCrimeID integer
M.Events.CharacterSelectedAsBestUnavailableFallbackLead = "character, crimeRegion, unavailableForCrimeID, busyCrimeID"

---@param character CHARACTER
M.Events.CharacterSelectedClimbOn = "character"

---@param character CHARACTER
---@param userID integer
M.Events.CharacterSelectedForUser = "character, userID"

---@param character CHARACTER
---@param item ITEM
---@param itemRootTemplate GUIDSTRING
---@param x number
---@param y number
---@param z number
---@param oldOwner CHARACTER
---@param srcContainer ITEM
---@param amount integer
---@param goldValue integer
M.Events.CharacterStoleItem = "character, item, itemRootTemplate, x, y, z, oldOwner, srcContainer, amount, goldValue"

---@param character CHARACTER
---@param tag TAG
---@param event string
M.Events.CharacterTagEvent = "character, tag, event"

---@param item ITEM
M.Events.Closed = "item"

---@param combatGuid GUIDSTRING
M.Events.CombatEnded = "combatGuid"

---@param combatGuid GUIDSTRING
M.Events.CombatPaused = "combatGuid"

---@param combatGuid GUIDSTRING
M.Events.CombatResumed = "combatGuid"

---@param combatGuid GUIDSTRING
---@param round integer
M.Events.CombatRoundStarted = "combatGuid, round"

---@param combatGuid GUIDSTRING
M.Events.CombatStarted = "combatGuid"

---@param item1 ITEM
---@param item2 ITEM
---@param item3 ITEM
---@param item4 ITEM
---@param item5 ITEM
---@param character CHARACTER
---@param newItem ITEM
M.Events.Combined = "item1, item2, item3, item4, item5, character, newItem"

---@param character CHARACTER
---@param userID integer
M.Events.CompanionSelectedForUser = "character, userID"

M.Events.CreditsEnded = ""

---@param character CHARACTER
---@param crime string
M.Events.CrimeDisabled = "character, crime"

---@param character CHARACTER
---@param crime string
M.Events.CrimeEnabled = "character, crime"

---@param victim CHARACTER
---@param crimeType string
---@param crimeID integer
---@param evidence GUIDSTRING
---@param criminal1 CHARACTER
---@param criminal2 CHARACTER
---@param criminal3 CHARACTER
---@param criminal4 CHARACTER
M.Events.CrimeIsRegistered = "victim, crimeType, crimeID, evidence, criminal1, criminal2, criminal3, criminal4"

---@param crimeID integer
---@param actedOnImmediately integer
M.Events.CrimeProcessingStarted = "crimeID, actedOnImmediately"

---@param defender CHARACTER
---@param attackOwner CHARACTER
---@param attacker CHARACTER
---@param storyActionID integer
M.Events.CriticalHitBy = "defender, attackOwner, attacker, storyActionID"

---@param character CHARACTER
---@param bookName string
M.Events.CustomBookUIClosed = "character, bookName"

---@param dlc DLC
---@param userID integer
---@param installed integer
M.Events.DLCUpdated = "dlc, userID, installed"

---@param object GUIDSTRING
M.Events.Deactivated = "object"

---@param character CHARACTER
M.Events.DeathSaveStable = "character"

---@param item ITEM
---@param destroyer CHARACTER
---@param destroyerOwner CHARACTER
---@param storyActionID integer
M.Events.DestroyedBy = "item, destroyer, destroyerOwner, storyActionID"

---@param item ITEM
---@param destroyer CHARACTER
---@param destroyerOwner CHARACTER
---@param storyActionID integer
M.Events.DestroyingBy = "item, destroyer, destroyerOwner, storyActionID"

---@param character CHARACTER
M.Events.DetachedFromPartyGroup = "character"

---@param dialog DIALOGRESOURCE
---@param instanceID integer
---@param actor GUIDSTRING
M.Events.DialogActorJoinFailed = "dialog, instanceID, actor"

---@param dialog DIALOGRESOURCE
---@param instanceID integer
---@param actor GUIDSTRING
---@param speakerIndex integer
M.Events.DialogActorJoined = "dialog, instanceID, actor, speakerIndex"

---@param dialog DIALOGRESOURCE
---@param instanceID integer
---@param actor GUIDSTRING
---@param instanceEnded integer
M.Events.DialogActorLeft = "dialog, instanceID, actor, instanceEnded"

---@param target CHARACTER
---@param player CHARACTER
M.Events.DialogAttackRequested = "target, player"

---@param dialog DIALOGRESOURCE
---@param instanceID integer
M.Events.DialogEnded = "dialog, instanceID"

---@param dialog DIALOGRESOURCE
---@param instanceID integer
M.Events.DialogForceStopping = "dialog, instanceID"

---@param dialog DIALOGRESOURCE
---@param instanceID integer
M.Events.DialogRequestFailed = "dialog, instanceID"

---@param character CHARACTER
---@param success integer
---@param dialog DIALOGRESOURCE
---@param isDetectThoughts integer
---@param criticality CRITICALITYTYPE
M.Events.DialogRollResult = "character, success, dialog, isDetectThoughts, criticality"

---@param target GUIDSTRING
---@param player GUIDSTRING
M.Events.DialogStartRequested = "target, player"

---@param dialog DIALOGRESOURCE
---@param instanceID integer
M.Events.DialogStarted = "dialog, instanceID"

---@param character CHARACTER
---@param isEnabled integer
M.Events.DialogueCapabilityChanged = "character, isEnabled"

---@param character CHARACTER
M.Events.Died = "character"

---@param difficultyLevel integer
M.Events.DifficultyChanged = "difficultyLevel"

---@param character CHARACTER
---@param moveID integer
M.Events.DisappearOutOfSightToCancelled = "character, moveID"

---@param itemTemplate ITEMROOT
---@param item2 ITEM
---@param character CHARACTER
M.Events.DoorTemplateClosing = "itemTemplate, item2, character"

---@param character CHARACTER
---@param isDowned integer
M.Events.DownedChanged = "character, isDowned"

---@param object GUIDSTRING
---@param mover CHARACTER
M.Events.DroppedBy = "object, mover"

---@param object1 GUIDSTRING
---@param object2 GUIDSTRING
---@param event string
M.Events.DualEntityEvent = "object1, object2, event"

---@param character CHARACTER
M.Events.Dying = "character"

---@param character CHARACTER
M.Events.EndTheDayRequested = "character"

---@param opponentLeft GUIDSTRING
---@param opponentRight GUIDSTRING
M.Events.EnterCombatFailed = "opponentLeft, opponentRight"

---@param object GUIDSTRING
---@param cause GUIDSTRING
---@param chasm GUIDSTRING
---@param fallbackPosX number
---@param fallbackPosY number
---@param fallbackPosZ number
M.Events.EnteredChasm = "object, cause, chasm, fallbackPosX, fallbackPosY, fallbackPosZ"

---@param object GUIDSTRING
---@param combatGuid GUIDSTRING
M.Events.EnteredCombat = "object, combatGuid"

---@param object GUIDSTRING
M.Events.EnteredForceTurnBased = "object"

---@param object GUIDSTRING
---@param objectRootTemplate ROOT
---@param level string
M.Events.EnteredLevel = "object, objectRootTemplate, level"

---@param object GUIDSTRING
---@param zoneId GUIDSTRING
M.Events.EnteredSharedForceTurnBased = "object, zoneId"

---@param character CHARACTER
---@param trigger TRIGGER
M.Events.EnteredTrigger = "character, trigger"

---@param object GUIDSTRING
---@param event string
M.Events.EntityEvent = "object, event"

---@param item ITEM
---@param character CHARACTER
M.Events.EquipFailed = "item, character"

---@param item ITEM
---@param character CHARACTER
M.Events.Equipped = "item, character"

---@param oldLeader GUIDSTRING
---@param newLeader GUIDSTRING
---@param group string
M.Events.EscortGroupLeaderChanged = "oldLeader, newLeader, group"

---@param character CHARACTER
---@param originalItem ITEM
---@param level string
---@param newItem ITEM
M.Events.FailedToLoadItemInPreset = "character, originalItem, level, newItem"

---@param entity GUIDSTRING
---@param cause GUIDSTRING
M.Events.Falling = "entity, cause"

---@param entity GUIDSTRING
---@param cause GUIDSTRING
M.Events.Fell = "entity, cause"

---@param flag FLAG
---@param speaker GUIDSTRING
---@param dialogInstance integer
M.Events.FlagCleared = "flag, speaker, dialogInstance"

---@param object GUIDSTRING
---@param flag FLAG
M.Events.FlagLoadedInPresetEvent = "object, flag"

---@param flag FLAG
---@param speaker GUIDSTRING
---@param dialogInstance integer
M.Events.FlagSet = "flag, speaker, dialogInstance"

---@param participant GUIDSTRING
---@param combatGuid GUIDSTRING
M.Events.FleeFromCombat = "participant, combatGuid"

---@param character CHARACTER
M.Events.FollowerCantUseItem = "character"

---@param companion CHARACTER
M.Events.ForceDismissCompanion = "companion"

---@param source GUIDSTRING
---@param target GUIDSTRING
---@param storyActionID integer
M.Events.ForceMoveEnded = "source, target, storyActionID"

---@param source GUIDSTRING
---@param target GUIDSTRING
---@param storyActionID integer
M.Events.ForceMoveStarted = "source, target, storyActionID"

---@param target CHARACTER
M.Events.GainedControl = "target"

---@param item ITEM
---@param character CHARACTER
M.Events.GameBookInterfaceClosed = "item, character"

---@param gameMode string
---@param isEditorMode integer
---@param isStoryReload integer
M.Events.GameModeStarted = "gameMode, isEditorMode, isStoryReload"

---@param key string
---@param value string
M.Events.GameOption = "key, value"

---@param inventoryHolder GUIDSTRING
---@param changeAmount integer
M.Events.GoldChanged = "inventoryHolder, changeAmount"

---@param target CHARACTER
M.Events.GotUp = "target"

---@param character CHARACTER
---@param trader CHARACTER
---@param characterValue integer
---@param traderValue integer
M.Events.HappyWithDeal = "character, trader, characterValue, traderValue"

---@param player CHARACTER
M.Events.HenchmanAborted = "player"

---@param player CHARACTER
---@param hireling CHARACTER
M.Events.HenchmanSelected = "player, hireling"

---@param proxy GUIDSTRING
---@param target GUIDSTRING
---@param attackerOwner GUIDSTRING
---@param attacker2 GUIDSTRING
---@param storyActionID integer
M.Events.HitProxy = "proxy, target, attackerOwner, attacker2, storyActionID"

---@param entity GUIDSTRING
---@param percentage number
M.Events.HitpointsChanged = "entity, percentage"

---@param instanceID integer
---@param oldDialog DIALOGRESOURCE
---@param newDialog DIALOGRESOURCE
---@param oldDialogStopping integer
M.Events.InstanceDialogChanged = "instanceID, oldDialog, newDialog, oldDialogStopping"

---@param character CHARACTER
---@param isEnabled integer
M.Events.InteractionCapabilityChanged = "character, isEnabled"

---@param character CHARACTER
---@param item ITEM
M.Events.InteractionFallback = "character, item"

---@param item ITEM
---@param isBoundToInventory integer
M.Events.InventoryBoundChanged = "item, isBoundToInventory"

---@param character CHARACTER
---@param sharingEnabled integer
M.Events.InventorySharingChanged = "character, sharingEnabled"

---@param item ITEM
---@param trigger TRIGGER
---@param mover GUIDSTRING
M.Events.ItemEnteredTrigger = "item, trigger, mover"

---@param item ITEM
---@param trigger TRIGGER
---@param mover GUIDSTRING
M.Events.ItemLeftTrigger = "item, trigger, mover"

---@param target ITEM
---@param oldX number
---@param oldY number
---@param oldZ number
---@param newX number
---@param newY number
---@param newZ number
M.Events.ItemTeleported = "target, oldX, oldY, oldZ, newX, newY, newZ"

---@param defender CHARACTER
---@param attackOwner GUIDSTRING
---@param attacker GUIDSTRING
---@param storyActionID integer
M.Events.KilledBy = "defender, attackOwner, attacker, storyActionID"

---@param character CHARACTER
---@param spell string
M.Events.LearnedSpell = "character, spell"

---@param object GUIDSTRING
---@param combatGuid GUIDSTRING
M.Events.LeftCombat = "object, combatGuid"

---@param object GUIDSTRING
M.Events.LeftForceTurnBased = "object"

---@param object GUIDSTRING
---@param level string
M.Events.LeftLevel = "object, level"

---@param character CHARACTER
---@param trigger TRIGGER
M.Events.LeftTrigger = "character, trigger"

---@param levelName string
---@param isEditorMode integer
M.Events.LevelGameplayStarted = "levelName, isEditorMode"

---@param newLevel string
M.Events.LevelLoaded = "newLevel"

---@param levelTemplate LEVELTEMPLATE
M.Events.LevelTemplateLoaded = "levelTemplate"

---@param level string
M.Events.LevelUnloading = "level"

---@param character CHARACTER
M.Events.LeveledUp = "character"

M.Events.LongRestCancelled = ""

M.Events.LongRestFinished = ""

M.Events.LongRestStartFailed = ""

M.Events.LongRestStarted = ""

---@param character CHARACTER
---@param targetCharacter CHARACTER
M.Events.LostSightOf = "character, targetCharacter"

---@param character CHARACTER
---@param event string
M.Events.MainPerformerStarted = "character, event"

---@param character CHARACTER
---@param message string
---@param resultChoice string
M.Events.MessageBoxChoiceClosed = "character, message, resultChoice"

---@param character CHARACTER
---@param message string
M.Events.MessageBoxClosed = "character, message"

---@param character CHARACTER
---@param message string
---@param result integer
M.Events.MessageBoxYesNoClosed = "character, message, result"

---@param defender CHARACTER
---@param attackOwner CHARACTER
---@param attacker CHARACTER
---@param storyActionID integer
M.Events.MissedBy = "defender, attackOwner, attacker, storyActionID"

---@param name string
---@param major integer
---@param minor integer
---@param revision integer
---@param build integer
M.Events.ModuleLoadedinSavegame = "name, major, minor, revision, build"

---@param character CHARACTER
---@param isEnabled integer
M.Events.MoveCapabilityChanged = "character, isEnabled"

---@param item ITEM
M.Events.Moved = "item"

---@param movedEntity GUIDSTRING
---@param character CHARACTER
M.Events.MovedBy = "movedEntity, character"

---@param movedObject GUIDSTRING
---@param fromObject GUIDSTRING
---@param toObject GUIDSTRING
---@param isTrade integer
M.Events.MovedFromTo = "movedObject, fromObject, toObject, isTrade"

---@param movieName string
M.Events.MovieFinished = "movieName"

---@param movieName string
M.Events.MoviePlaylistFinished = "movieName"

---@param dialog DIALOGRESOURCE
---@param instanceID integer
M.Events.NestedDialogPlayed = "dialog, instanceID"

---@param character CHARACTER
---@param oldLevel integer
---@param newLevel integer
M.Events.ObjectAvailableLevelChanged = "character, oldLevel, newLevel"

---@param object GUIDSTRING
---@param timer string
M.Events.ObjectTimerFinished = "object, timer"

---@param object GUIDSTRING
---@param toTemplate GUIDSTRING
M.Events.ObjectTransformed = "object, toTemplate"

---@param object GUIDSTRING
---@param obscuredState string
M.Events.ObscuredStateChanged = "object, obscuredState"

---@param crimeID integer
---@param investigator CHARACTER
---@param wasLead integer
---@param criminal1 CHARACTER
---@param criminal2 CHARACTER
---@param criminal3 CHARACTER
---@param criminal4 CHARACTER
M.Events.OnCrimeConfrontationDone = "crimeID, investigator, wasLead, criminal1, criminal2, criminal3, criminal4"

---@param crimeID integer
---@param investigator CHARACTER
---@param fromState string
---@param toState string
M.Events.OnCrimeInvestigatorSwitchedState = "crimeID, investigator, fromState, toState"

---@param oldCrimeID integer
---@param newCrimeID integer
M.Events.OnCrimeMergedWith = "oldCrimeID, newCrimeID"

---@param crimeID integer
---@param victim CHARACTER
---@param criminal1 CHARACTER
---@param criminal2 CHARACTER
---@param criminal3 CHARACTER
---@param criminal4 CHARACTER
M.Events.OnCrimeRemoved = "crimeID, victim, criminal1, criminal2, criminal3, criminal4"

---@param crimeID integer
---@param criminal CHARACTER
M.Events.OnCrimeResetInterrogationForCriminal = "crimeID, criminal"

---@param crimeID integer
---@param victim CHARACTER
---@param criminal1 CHARACTER
---@param criminal2 CHARACTER
---@param criminal3 CHARACTER
---@param criminal4 CHARACTER
M.Events.OnCrimeResolved = "crimeID, victim, criminal1, criminal2, criminal3, criminal4"

---@param crimeID integer
---@param criminal CHARACTER
M.Events.OnCriminalMergedWithCrime = "crimeID, criminal"

---@param isEditorMode integer
M.Events.OnShutdown = "isEditorMode"

---@param carriedObject GUIDSTRING
---@param carriedObjectTemplate ROOT
---@param carrier GUIDSTRING
---@param storyActionID integer
---@param pickupPosX number
---@param pickupPosY number
---@param pickupPosZ number
M.Events.OnStartCarrying =
    "carriedObject, carriedObjectTemplate, carrier, storyActionID, pickupPosX, pickupPosY, pickupPosZ"

---@param target CHARACTER
M.Events.OnStoryOverride = "target"

---@param thrownObject GUIDSTRING
---@param thrownObjectTemplate ROOT
---@param thrower GUIDSTRING
---@param storyActionID integer
---@param throwPosX number
---@param throwPosY number
---@param throwPosZ number
M.Events.OnThrown = "thrownObject, thrownObjectTemplate, thrower, storyActionID, throwPosX, throwPosY, throwPosZ"

---@param item ITEM
M.Events.Opened = "item"

---@param partyPreset string
---@param levelName string
M.Events.PartyPresetLoaded = "partyPreset, levelName"

---@param character CHARACTER
---@param item ITEM
M.Events.PickupFailed = "character, item"

---@param character CHARACTER
M.Events.PingRequested = "character"

---@param object GUIDSTRING
M.Events.PlatformDestroyed = "object"

---@param object GUIDSTRING
---@param eventId string
M.Events.PlatformMovementCanceled = "object, eventId"

---@param object GUIDSTRING
---@param eventId string
M.Events.PlatformMovementFinished = "object, eventId"

---@param item ITEM
---@param character CHARACTER
M.Events.PreMovedBy = "item, character"

---@param character CHARACTER
---@param uIInstance string
---@param type integer
M.Events.PuzzleUIClosed = "character, uIInstance, type"

---@param character CHARACTER
---@param uIInstance string
---@param type integer
---@param command string
---@param elementId integer
M.Events.PuzzleUIUsed = "character, uIInstance, type, command, elementId"

---@param character CHARACTER
---@param questID string
M.Events.QuestAccepted = "character, questID"

---@param questID string
M.Events.QuestClosed = "questID"

---@param character CHARACTER
---@param topLevelQuestID string
---@param stateID string
M.Events.QuestUpdateUnlocked = "character, topLevelQuestID, stateID"

---@param object GUIDSTRING
M.Events.QueuePurged = "object"

---@param caster GUIDSTRING
---@param storyActionID integer
---@param spellID string
---@param rollResult integer
---@param randomCastDC integer
M.Events.RandomCastProcessed = "caster, storyActionID, spellID, rollResult, randomCastDC"

---@param object GUIDSTRING
M.Events.ReactionInterruptActionNeeded = "object"

---@param character CHARACTER
---@param reactionInterruptName string
M.Events.ReactionInterruptAdded = "character, reactionInterruptName"

---@param object GUIDSTRING
---@param reactionInterruptPrototypeId string
---@param isAutoTriggered integer
M.Events.ReactionInterruptUsed = "object, reactionInterruptPrototypeId, isAutoTriggered"

---@param id string
M.Events.ReadyCheckFailed = "id"

---@param id string
M.Events.ReadyCheckPassed = "id"

---@param sourceFaction FACTION
---@param targetFaction FACTION
---@param newRelation integer
---@param permanent integer
M.Events.RelationChanged = "sourceFaction, targetFaction, newRelation, permanent"

---@param object GUIDSTRING
---@param inventoryHolder GUIDSTRING
M.Events.RemovedFrom = "object, inventoryHolder"

---@param entity GUIDSTRING
---@param onEntity GUIDSTRING
M.Events.ReposeAdded = "entity, onEntity"

---@param entity GUIDSTRING
---@param onEntity GUIDSTRING
M.Events.ReposeRemoved = "entity, onEntity"

---@param character CHARACTER
---@param item1 ITEM
---@param item2 ITEM
---@param item3 ITEM
---@param item4 ITEM
---@param item5 ITEM
---@param requestID integer
M.Events.RequestCanCombine = "character, item1, item2, item3, item4, item5, requestID"

---@param character CHARACTER
---@param item ITEM
---@param requestID integer
M.Events.RequestCanDisarmTrap = "character, item, requestID"

---@param character CHARACTER
---@param item ITEM
---@param requestID integer
M.Events.RequestCanLockpick = "character, item, requestID"

---@param looter CHARACTER
---@param target CHARACTER
M.Events.RequestCanLoot = "looter, target"

---@param character CHARACTER
---@param item ITEM
---@param requestID integer
M.Events.RequestCanMove = "character, item, requestID"

---@param character CHARACTER
---@param object GUIDSTRING
---@param requestID integer
M.Events.RequestCanPickup = "character, object, requestID"

---@param character CHARACTER
---@param item ITEM
---@param requestID integer
M.Events.RequestCanUse = "character, item, requestID"

M.Events.RequestEndTheDayFail = ""

M.Events.RequestEndTheDaySuccess = ""

---@param character CHARACTER
M.Events.RequestGatherAtCampFail = "character"

---@param character CHARACTER
M.Events.RequestGatherAtCampSuccess = "character"

---@param player CHARACTER
---@param npc CHARACTER
M.Events.RequestPickpocket = "player, npc"

---@param character CHARACTER
---@param trader CHARACTER
---@param tradeMode TRADEMODE
---@param itemsTagFilter string
M.Events.RequestTrade = "character, trader, tradeMode, itemsTagFilter"

---@param character CHARACTER
M.Events.RespecCancelled = "character"

---@param character CHARACTER
M.Events.RespecCompleted = "character"

---@param character CHARACTER
M.Events.Resurrected = "character"

---@param eventName string
---@param roller CHARACTER
---@param rollSubject GUIDSTRING
---@param resultType integer
---@param isActiveRoll integer
---@param criticality CRITICALITYTYPE
M.Events.RollResult = "eventName, roller, rollSubject, resultType, isActiveRoll, criticality"

---@param modifier RULESETMODIFIER
---@param old integer
---@param new integer
M.Events.RulesetModifierChangedBool = "modifier, old, new"

---@param modifier RULESETMODIFIER
---@param old number
---@param new number
M.Events.RulesetModifierChangedFloat = "modifier, old, new"

---@param modifier RULESETMODIFIER
---@param old integer
---@param new integer
M.Events.RulesetModifierChangedInt = "modifier, old, new"

---@param modifier RULESETMODIFIER
---@param old string
---@param new string
M.Events.RulesetModifierChangedString = "modifier, old, new"

---@param userID integer
---@param state integer
M.Events.SafeRomanceOptionChanged = "userID, state"

M.Events.SavegameLoadStarted = ""

M.Events.SavegameLoaded = ""

---@param character CHARACTER
---@param targetCharacter CHARACTER
---@param targetWasSneaking integer
M.Events.Saw = "character, targetCharacter, targetWasSneaking"

---@param item ITEM
---@param x number
---@param y number
---@param z number
M.Events.ScatteredAt = "item, x, y, z"

---@param userID integer
---@param fadeID string
M.Events.ScreenFadeCleared = "userID, fadeID"

---@param userID integer
---@param fadeID string
M.Events.ScreenFadeDone = "userID, fadeID"

---@param character CHARACTER
---@param race string
---@param gender string
---@param shapeshiftStatus string
M.Events.ShapeshiftChanged = "character, race, gender, shapeshiftStatus"

---@param entity GUIDSTRING
---@param percentage number
M.Events.ShapeshiftedHitpointsChanged = "entity, percentage"

---@param object GUIDSTRING
M.Events.ShareInitiative = "object"

---@param character CHARACTER
---@param capable integer
M.Events.ShortRestCapable = "character, capable"

---@param character CHARACTER
M.Events.ShortRestProcessing = "character"

---@param character CHARACTER
M.Events.ShortRested = "character"

---@param item ITEM
---@param stackedWithItem ITEM
M.Events.StackedWith = "item, stackedWithItem"

---@param defender GUIDSTRING
---@param attackOwner CHARACTER
---@param attacker GUIDSTRING
---@param storyActionID integer
M.Events.StartAttack = "defender, attackOwner, attacker, storyActionID"

---@param x number
---@param y number
---@param z number
---@param attackOwner CHARACTER
---@param attacker GUIDSTRING
---@param storyActionID integer
M.Events.StartAttackPosition = "x, y, z, attackOwner, attacker, storyActionID"

---@param character CHARACTER
---@param item ITEM
M.Events.StartedDisarmingTrap = "character, item"

---@param character CHARACTER
M.Events.StartedFleeing = "character"

---@param character CHARACTER
---@param item ITEM
M.Events.StartedLockpicking = "character, item"

---@param caster GUIDSTRING
---@param spell string
---@param isMostPowerful integer
---@param hasMultipleLevels integer
M.Events.StartedPreviewingSpell = "caster, spell, isMostPowerful, hasMultipleLevels"

---@param object GUIDSTRING
---@param status string
---@param causee GUIDSTRING
---@param storyActionID integer
M.Events.StatusApplied = "object, status, causee, storyActionID"

---@param object GUIDSTRING
---@param status string
---@param causee GUIDSTRING
---@param storyActionID integer
M.Events.StatusAttempt = "object, status, causee, storyActionID"

---@param object GUIDSTRING
---@param status string
---@param causee GUIDSTRING
---@param storyActionID integer
M.Events.StatusAttemptFailed = "object, status, causee, storyActionID"

---@param object GUIDSTRING
---@param status string
---@param causee GUIDSTRING
---@param applyStoryActionID integer
M.Events.StatusRemoved = "object, status, causee, applyStoryActionID"

---@param target GUIDSTRING
---@param tag TAG
---@param sourceOwner GUIDSTRING
---@param source2 GUIDSTRING
---@param storyActionID integer
M.Events.StatusTagCleared = "target, tag, sourceOwner, source2, storyActionID"

---@param target GUIDSTRING
---@param tag TAG
---@param sourceOwner GUIDSTRING
---@param source2 GUIDSTRING
---@param storyActionID integer
M.Events.StatusTagSet = "target, tag, sourceOwner, source2, storyActionID"

---@param character CHARACTER
---@param item1 ITEM
---@param item2 ITEM
---@param item3 ITEM
---@param item4 ITEM
---@param item5 ITEM
M.Events.StoppedCombining = "character, item1, item2, item3, item4, item5"

---@param character CHARACTER
---@param item ITEM
M.Events.StoppedDisarmingTrap = "character, item"

---@param character CHARACTER
---@param item ITEM
M.Events.StoppedLockpicking = "character, item"

---@param character CHARACTER
M.Events.StoppedSneaking = "character"

---@param character CHARACTER
---@param subQuestID string
---@param stateID string
M.Events.SubQuestUpdateUnlocked = "character, subQuestID, stateID"

---@param templateId GUIDSTRING
---@param amount integer
M.Events.SupplyTemplateSpent = "templateId, amount"

---@param object GUIDSTRING
---@param group string
M.Events.SwarmAIGroupJoined = "object, group"

---@param object GUIDSTRING
---@param group string
M.Events.SwarmAIGroupLeft = "object, group"

---@param object GUIDSTRING
---@param oldCombatGuid GUIDSTRING
---@param newCombatGuid GUIDSTRING
M.Events.SwitchedCombat = "object, oldCombatGuid, newCombatGuid"

---@param character CHARACTER
---@param power string
M.Events.TadpolePowerAssigned = "character, power"

---@param target GUIDSTRING
---@param tag TAG
M.Events.TagCleared = "target, tag"

---@param tag TAG
---@param event string
M.Events.TagEvent = "tag, event"

---@param target GUIDSTRING
---@param tag TAG
M.Events.TagSet = "target, tag"

---@param character CHARACTER
---@param trigger TRIGGER
M.Events.TeleportToFleeWaypoint = "character, trigger"

---@param character CHARACTER
M.Events.TeleportToFromCamp = "character"

---@param character CHARACTER
---@param trigger TRIGGER
M.Events.TeleportToWaypoint = "character, trigger"

---@param target CHARACTER
---@param cause CHARACTER
---@param oldX number
---@param oldY number
---@param oldZ number
---@param newX number
---@param newY number
---@param newZ number
---@param spell string
M.Events.Teleported = "target, cause, oldX, oldY, oldZ, newX, newY, newZ, spell"

---@param character CHARACTER
M.Events.TeleportedFromCamp = "character"

---@param character CHARACTER
M.Events.TeleportedToCamp = "character"

---@param objectTemplate ROOT
---@param object2 GUIDSTRING
---@param inventoryHolder GUIDSTRING
---@param addType string
M.Events.TemplateAddedTo = "objectTemplate, object2, inventoryHolder, addType"

---@param itemTemplate ITEMROOT
---@param item2 ITEM
---@param destroyer CHARACTER
---@param destroyerOwner CHARACTER
---@param storyActionID integer
M.Events.TemplateDestroyedBy = "itemTemplate, item2, destroyer, destroyerOwner, storyActionID"

---@param itemTemplate ITEMROOT
---@param item2 ITEM
---@param trigger TRIGGER
---@param owner CHARACTER
---@param mover GUIDSTRING
M.Events.TemplateEnteredTrigger = "itemTemplate, item2, trigger, owner, mover"

---@param itemTemplate ITEMROOT
---@param character CHARACTER
M.Events.TemplateEquipped = "itemTemplate, character"

---@param characterTemplate CHARACTERROOT
---@param defender CHARACTER
---@param attackOwner GUIDSTRING
---@param attacker GUIDSTRING
---@param storyActionID integer
M.Events.TemplateKilledBy = "characterTemplate, defender, attackOwner, attacker, storyActionID"

---@param itemTemplate ITEMROOT
---@param item2 ITEM
---@param trigger TRIGGER
---@param owner CHARACTER
---@param mover GUIDSTRING
M.Events.TemplateLeftTrigger = "itemTemplate, item2, trigger, owner, mover"

---@param itemTemplate ITEMROOT
---@param item2 ITEM
---@param character CHARACTER
M.Events.TemplateOpening = "itemTemplate, item2, character"

---@param objectTemplate ROOT
---@param object2 GUIDSTRING
---@param inventoryHolder GUIDSTRING
M.Events.TemplateRemovedFrom = "objectTemplate, object2, inventoryHolder"

---@param itemTemplate ITEMROOT
---@param character CHARACTER
M.Events.TemplateUnequipped = "itemTemplate, character"

---@param character CHARACTER
---@param itemTemplate ITEMROOT
---@param item2 ITEM
---@param sucess integer
M.Events.TemplateUseFinished = "character, itemTemplate, item2, sucess"

---@param character CHARACTER
---@param itemTemplate ITEMROOT
---@param item2 ITEM
M.Events.TemplateUseStarted = "character, itemTemplate, item2"

---@param template1 ITEMROOT
---@param template2 ITEMROOT
---@param template3 ITEMROOT
---@param template4 ITEMROOT
---@param template5 ITEMROOT
---@param character CHARACTER
---@param newItem ITEM
M.Events.TemplatesCombined = "template1, template2, template3, template4, template5, character, newItem"

---@param enemy CHARACTER
---@param sourceFaction FACTION
---@param targetFaction FACTION
M.Events.TemporaryHostileRelationRemoved = "enemy, sourceFaction, targetFaction"

---@param character1 CHARACTER
---@param character2 CHARACTER
---@param success integer
M.Events.TemporaryHostileRelationRequestHandled = "character1, character2, success"

---@param event string
M.Events.TextEvent = "event"

---@param userID integer
---@param dialogInstanceId integer
---@param dialog2 DIALOGRESOURCE
M.Events.TimelineScreenFadeStarted = "userID, dialogInstanceId, dialog2"

---@param timer string
M.Events.TimerFinished = "timer"

---@param character CHARACTER
---@param trader CHARACTER
M.Events.TradeEnds = "character, trader"

---@param trader CHARACTER
M.Events.TradeGenerationEnded = "trader"

---@param trader CHARACTER
M.Events.TradeGenerationStarted = "trader"

---@param object GUIDSTRING
M.Events.TurnEnded = "object"

---@param object GUIDSTRING
M.Events.TurnStarted = "object"

---@param character CHARACTER
---@param message string
M.Events.TutorialBoxClosed = "character, message"

---@param userId integer
---@param entryId GUIDSTRING
M.Events.TutorialClosed = "userId, entryId"

---@param entity CHARACTER
---@param event TUTORIALEVENT
M.Events.TutorialEvent = "entity, event"

---@param item ITEM
---@param character CHARACTER
M.Events.UnequipFailed = "item, character"

---@param item ITEM
---@param character CHARACTER
M.Events.Unequipped = "item, character"

---@param item ITEM
---@param character CHARACTER
---@param key ITEM
M.Events.Unlocked = "item, character, key"

---@param character CHARACTER
---@param recipe string
M.Events.UnlockedRecipe = "character, recipe"

---@param character CHARACTER
---@param item ITEM
---@param sucess integer
M.Events.UseFinished = "character, item, sucess"

---@param character CHARACTER
---@param item ITEM
M.Events.UseStarted = "character, item"

---@param userID integer
---@param avatar CHARACTER
---@param daisy CHARACTER
M.Events.UserAvatarCreated = "userID, avatar, daisy"

---@param userID integer
---@param chest ITEM
M.Events.UserCampChestChanged = "userID, chest"

---@param character CHARACTER
---@param isFullRest integer
M.Events.UserCharacterLongRested = "character, isFullRest"

---@param userID integer
---@param userName string
---@param userProfileID string
M.Events.UserConnected = "userID, userName, userProfileID"

---@param userID integer
---@param userName string
---@param userProfileID string
M.Events.UserDisconnected = "userID, userName, userProfileID"

---@param userID integer
---@param userEvent string
M.Events.UserEvent = "userID, userEvent"

---@param sourceUserID integer
---@param targetUserID integer
---@param war integer
M.Events.UserMakeWar = "sourceUserID, targetUserID, war"

---@param caster GUIDSTRING
---@param spell string
---@param spellType string
---@param spellElement string
---@param storyActionID integer
M.Events.UsingSpell = "caster, spell, spellType, spellElement, storyActionID"

---@param caster GUIDSTRING
---@param x number
---@param y number
---@param z number
---@param spell string
---@param spellType string
---@param spellElement string
---@param storyActionID integer
M.Events.UsingSpellAtPosition = "caster, x, y, z, spell, spellType, spellElement, storyActionID"

---@param caster GUIDSTRING
---@param spell string
---@param spellType string
---@param spellElement string
---@param trigger TRIGGER
---@param storyActionID integer
M.Events.UsingSpellInTrigger = "caster, spell, spellType, spellElement, trigger, storyActionID"

---@param caster GUIDSTRING
---@param target GUIDSTRING
---@param spell string
---@param spellType string
---@param spellElement string
---@param storyActionID integer
M.Events.UsingSpellOnTarget = "caster, target, spell, spellType, spellElement, storyActionID"

---@param caster GUIDSTRING
---@param target GUIDSTRING
---@param spell string
---@param spellType string
---@param spellElement string
---@param storyActionID integer
M.Events.UsingSpellOnZoneWithTarget = "caster, target, spell, spellType, spellElement, storyActionID"

---@param bark VOICEBARKRESOURCE
---@param instanceID integer
M.Events.VoiceBarkEnded = "bark, instanceID"

---@param bark VOICEBARKRESOURCE
M.Events.VoiceBarkFailed = "bark"

---@param bark VOICEBARKRESOURCE
---@param instanceID integer
M.Events.VoiceBarkStarted = "bark, instanceID"

---@param object GUIDSTRING
---@param isOnStageNow integer
M.Events.WentOnStage = "object, isOnStageNow"

return M
