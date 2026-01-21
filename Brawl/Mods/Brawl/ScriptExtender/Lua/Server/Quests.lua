local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump

local function nautiloidTransponderEvent()
    local brawlers = M.Roster.getBrawlers()
    if brawlers and brawlers[Constants.TUT_ZHALK_UUID] and brawlers[Constants.TUT_MIND_FLAYER_UUID] and M.Utils.isAliveAndCanFight(Constants.TUT_ZHALK_UUID) and M.Utils.isAliveAndCanFight(Constants.TUT_MIND_FLAYER_UUID) then
        brawlers[Constants.TUT_ZHALK_UUID].targetUuid = Constants.TUT_MIND_FLAYER_UUID
        brawlers[Constants.TUT_ZHALK_UUID].lockedOnTarget = true
        brawlers[Constants.TUT_MIND_FLAYER_UUID].targetUuid = Constants.TUT_ZHALK_UUID
        brawlers[Constants.TUT_MIND_FLAYER_UUID].lockedOnTarget = true
    end
end

local function hagTeahouseEvent()
    local function clearIllusion()
        Osi.SetEntityEvent(Constants.AUNTIE_ETHEL_UUID, "HAG_LairEntrance_Event_IllusionDispelCast")
        Osi.PROC_HAG_ForestIllusion_ClearFireplaceIllusion()
        Osi.CharacterMoveTo(Constants.AUNTIE_ETHEL_UUID, Constants.ETHEL_ILLUSION, "Run", Constants.NULL_UUID)
    end
    local function fleeToLair()
        if Osi.GetFlag("HAG_Hagspawn_State_SkipAD_58c3b07f-db26-4101-996d-752f24767e7c", Constants.AUNTIE_ETHEL_UUID) == 0 then
            Osi.SetFlag("HAG_Hag_State_InCombatWhileLeavingWithMayrina_dcc3ae1c-b5df-4b1a-82d8-ea94e9f3a37c")
            Osi.PROC_TryStartAD("HAG_Hag_AD_TeleportSurrogateMother_d32494d4-0658-adb7-4433-82486e723607", Constants.AUNTIE_ETHEL_UUID)
        end
        Osi.SetFlag("HAG_Hag_State_TeleportSurrogateMotherToLair_3da9b42e-a6e8-471f-9f12-87c2c8cf3885")
        Osi.Use(Constants.AUNTIE_ETHEL_UUID, "S_HAG_HagLair_PortalToLair_b9e148b4-7b9b-45e5-bef4-f0673fffc93e", Constants.NULL_UUID)
        Osi.SetEntityEvent(Constants.AUNTIE_ETHEL_UUID, "HAG_Hag_HagEscape_PastBrambles")
        Osi.SetEntityEvent(Constants.AUNTIE_ETHEL_UUID, "HAG_Hag_HagEscape_PastAtHatch")
    end
    local function cleanUp()
        Roster.checkForEndOfBrawl("WLD_Main_A")
        Roster.setExcludedFromAI(Constants.AUNTIE_ETHEL_UUID, false)
    end
    Roster.setExcludedFromAI(Constants.AUNTIE_ETHEL_UUID, true)
    Osi.RemoveStatus(Constants.AUNTIE_ETHEL_UUID, "HAG_MASK_ILLUSION")
    Osi.UseSpell(Constants.AUNTIE_ETHEL_UUID, "Target_HAG_ClearIllusion", Constants.ETHEL_ILLUSION)
    Ext.Timer.WaitFor(500, function ()
        clearIllusion()        
        Ext.Timer.WaitFor(500, function ()
            fleeToLair()
            Ext.Timer.WaitFor(6000, cleanUp)
        end)
    end)
end

local function halsinPortalEvent()
    local combatRoundStartedListener, enteredCombatListener
    local function stopListeners()
        Ext.Osiris.UnregisterListener(combatRoundStartedListener)
        Ext.Osiris.UnregisterListener(enteredCombatListener)
    end
    local function targetHalsinPortal(brawler)
        if brawler then
            brawler.targetUuid = Constants.HALSIN_PORTAL_UUID
            if math.random() > 0.85 then
                brawler.lockedOnTarget = true
            end
        end
    end
    local function checkTargetHalsinPortal()
        if Osi.QRY_HAV_IsRitualActive() then
            for uuid, brawler in pairs(M.Roster.getBrawlers()) do
                if not brawler.targetUuid and M.Utils.isPugnacious(uuid) then
                    targetHalsinPortal(brawler)
                end
            end
        end
    end
    local function onCombatRoundStarted(_, round)
        if not Osi.QRY_HAV_IsRitualActive() then
            return stopListeners()
        end
        if State.Session.TurnBasedSwarmMode then
            if round > Constants.LAKESIDE_RITUAL_COUNTDOWN_TURNS then
                return stopListeners()
            end
            return checkTargetHalsinPortal()
        end
        if round > Constants.LAKESIDE_RITUAL_COUNTDOWN_TURNS then
            if Osi.GetHitpoints(Constants.HALSIN_PORTAL_UUID) ~= nil then
                Osi.PROC_HAV_LiftingTheCurse_CheckRound(0)
            end
            return stopListeners()
        end
        Osi.PROC_HAV_LiftingTheCurse_SpawnWave(round)
        Osi.PROC_HAV_LiftingTheCurse_DeclareRound(round)
        Ext.Timer.WaitFor(200, checkTargetHalsinPortal)
    end
    local function onEnteredCombat(entityGuid, _)
        if not Osi.QRY_HAV_IsRitualActive() then
            return stopListeners()
        end
        local uuid = M.Osi.GetUUID(entityGuid)
        if uuid and M.Utils.isPugnacious(uuid) then
            targetHalsinPortal(M.Roster.getBrawlerByUuid(uuid))
        end
    end
    combatRoundStartedListener = Ext.Osiris.RegisterListener("CombatRoundStarted", 2, "after", onCombatRoundStarted)
    enteredCombatListener = Ext.Osiris.RegisterListener("EnteredCombat", 2, "after", onEnteredCombat)
end

return {
    nautiloidTransponderEvent = nautiloidTransponderEvent,
    hagTeahouseEvent = hagTeahouseEvent,
    halsinPortalEvent = halsinPortalEvent,
}
