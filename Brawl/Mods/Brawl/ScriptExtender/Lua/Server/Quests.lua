local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump

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

local function halsinPortalEvent()
    local combatRoundStartedListener, enteredCombatListener
    local function stopListeners()
        Ext.Osiris.UnregisterListener(combatRoundStartedListener)
        Ext.Osiris.UnregisterListener(enteredCombatListener)
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
    checkTargetHalsinPortal = checkTargetHalsinPortal,
    halsinPortalEvent = halsinPortalEvent,
}
