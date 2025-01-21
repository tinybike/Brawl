local function nautiloidTransponderCountdownFinished(uuid)
    if uuid ~= nil and uuid == Osi.GetHostCharacter() then
        Osi.PROC_TUT_Helm_GameOver()
    end
end
local function lakesideRitualCountdownFinished(uuid)
    if uuid ~= nil and uuid == Osi.GetHostCharacter() and Osi.GetHitpoints(HALSIN_PORTAL_UUID) ~= nil and Osi.QRY_HAV_IsRitualActive() then
        Osi.PROC_HAV_LiftingTheCurse_CheckRound(0)
    end
end
local function onLakesideRitualTurn(uuid, turnsRemaining)
    debugPrint("onLakesideRitualTurn", turnsRemaining, Osi.QRY_HAV_IsRitualActive())
    -- 1. enemies need to attack portal sometimes
    -- 2. during pause the timer needs to stop counting down
    if Osi.QRY_HAV_IsRitualActive() and turnsRemaining > 0 then
        if Osi.IsInForceTurnBasedMode(uuid) == 0 then
            local currentTurn = LAKESIDE_RITUAL_COUNTDOWN_TURNS - turnsRemaining
            Osi.PROC_HAV_LiftingTheCurse_SpawnWave(currentTurn)
            Osi.PROC_HAV_LiftingTheCurse_DeclareRound(currentTurn)
            Ext.Timer.WaitFor(200, function ()
                if Osi.IsInForceTurnBasedMode(uuid) == 0 then
                    addNearbyToBrawlers(uuid, 30)
                    local level = Osi.GetRegion(uuid)
                    if level and State.Session.Brawlers and State.Session.Brawlers[level] then
                        for brawlerUuid, brawler in pairs(State.Session.Brawlers[level]) do
                            if Osi.IsEnemy(uuid, brawlerUuid) == 1 then
                                if math.random() > 0.85 then
                                    brawler.targetUuid = HALSIN_PORTAL_UUID
                                    brawler.lockedOnTarget = true
                                end
                            end
                        end
                    end
                end
            end)
            lakesideRitualCountdown(uuid, turnsRemaining)
        end
    else
        local level = Osi.GetRegion(uuid)
        removeBrawler(level, HALSIN_PORTAL_UUID)
        checkForEndOfBrawl(level)
    end
end
local function onNautiloidTransponderTurn(uuid, turnsRemaining)
    debugPrint("onNautiloidTransponderTurn", turnsRemaining)
    if turnsRemaining > 0 and Osi.IsInForceTurnBasedMode(uuid) == 0 then
        local level = Osi.GetRegion(uuid)
        if level == "TUT_Avernus_C" then
            addNearbyToBrawlers(uuid, 30)
            if State.Session.Brawlers and State.Session.Brawlers[level] and isAliveAndCanFight(TUT_ZHALK_UUID) and isAliveAndCanFight(TUT_MIND_FLAYER_UUID) then
                if not State.Session.Brawlers[level][TUT_ZHALK_UUID] then
                    addBrawler(TUT_ZHALK_UUID, true)
                end
                if not State.Session.Brawlers[level][TUT_MIND_FLAYER_UUID] then
                    addBrawler(TUT_MIND_FLAYER_UUID, true)
                end
                State.Session.Brawlers[level][TUT_ZHALK_UUID].targetUuid = TUT_MIND_FLAYER_UUID
                State.Session.Brawlers[level][TUT_ZHALK_UUID].lockedOnTarget = true
                State.Session.Brawlers[level][TUT_MIND_FLAYER_UUID].targetUuid = TUT_ZHALK_UUID
                State.Session.Brawlers[level][TUT_MIND_FLAYER_UUID].lockedOnTarget = true
            end
            nautiloidTransponderCountdown(uuid, turnsRemaining)
        else
            questTimerCancel("TUT_Helm_Timer")
        end
    end
end
local function lakesideRitualCountdown(uuid, turnsRemaining)
    if turnsRemaining == LAKESIDE_RITUAL_COUNTDOWN_TURNS then
        addBrawler(HALSIN_PORTAL_UUID, true)
    end
    setCountdownTimer(uuid, turnsRemaining, onLakesideRitualTurn)
end
local function nautiloidTransponderCountdown(uuid, turnsRemaining)
    setCountdownTimer(uuid, turnsRemaining, onNautiloidTransponderTurn)
end
local function questTimerCancel(timer)
    if State.Session.Players then
        for uuid, _ in pairs(State.Session.Players) do
            Osi.ObjectTimerCancel(uuid, timer)
        end
    end
end
local function questTimerLaunch(timer, textKey, numRounds)
    if State.Session.Players then
        for uuid, _ in pairs(State.Session.Players) do
            Osi.ObjectQuestTimerLaunch(uuid, timer, textKey, COUNTDOWN_TURN_INTERVAL*numRounds, 1)
        end
    end
end
local function setCountdownTimer(uuid, turnsRemaining, onNextTurn)
    State.Session.CountdownTimer = {
        uuid = uuid,
        turnsRemaining = turnsRemaining,
        resume = onNextTurn,
        timer = Ext.Timer.WaitFor(COUNTDOWN_TURN_INTERVAL, function ()
            onNextTurn(uuid, turnsRemaining - 1)
        end)
    }
end
local function stopCountdownTimer(uuid)
    if State.Session.CountdownTimer.uuid ~= nil and uuid == State.Session.CountdownTimer.uuid and State.Session.CountdownTimer.timer ~= nil then
        debugPrint("Stopping countdown", State.Session.CountdownTimer.uuid, State.Session.CountdownTimer.turnsRemaining)
        Ext.Timer.Cancel(State.Session.CountdownTimer.timer)
        State.Session.CountdownTimer.timer = nil
    end
end
local function resumeCountdownTimer(uuid)
    if State.Session.CountdownTimer.uuid ~= nil and uuid == State.Session.CountdownTimer.uuid then
        debugPrint("Resuming countdown", State.Session.CountdownTimer.uuid, State.Session.CountdownTimer.turnsRemaining)
        State.Session.CountdownTimer.resume(State.Session.CountdownTimer.uuid, State.Session.CountdownTimer.turnsRemaining)
    end
end

Quests = {
    nautiloidTransponderCountdownFinished = nautiloidTransponderCountdownFinished,
    lakesideRitualCountdownFinished = lakesideRitualCountdownFinished,
    lakesideRitualCountdown = lakesideRitualCountdown,
    nautiloidTransponderCountdown = nautiloidTransponderCountdown,
    questTimerCancel = questTimerCancel,
    questTimerLaunch = questTimerLaunch,
    stopCountdownTimer = stopCountdownTimer,
    resumeCountdownTimer = resumeCountdownTimer,
}
