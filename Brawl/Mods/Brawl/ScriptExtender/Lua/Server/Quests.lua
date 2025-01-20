function nautiloidTransponderCountdownFinished(uuid)
    if uuid ~= nil and uuid == Osi.GetHostCharacter() then
        Osi.PROC_TUT_Helm_GameOver()
    end
end

function lakesideRitualCountdownFinished(uuid)
    if uuid ~= nil and uuid == Osi.GetHostCharacter() and Osi.GetHitpoints(HALSIN_PORTAL_UUID) ~= nil and Osi.QRY_HAV_IsRitualActive() then
        Osi.PROC_HAV_LiftingTheCurse_CheckRound(0)
    end
end

function onLakesideRitualTurn(uuid, turnsRemaining)
    debugPrint("onLakesideRitualTurn", turnsRemaining)
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
                    if level and Brawlers and Brawlers[level] then
                        for brawlerUuid, brawler in pairs(Brawlers[level]) do
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
        removeBrawler(HALSIN_PORTAL_UUID, level)
        checkForEndOfBrawl(level)
    end
end

function onNautiloidTransponderTurn(uuid, turnsRemaining)
    debugPrint("onNautiloidTransponderTurn", turnsRemaining)
    if turnsRemaining > 0 and Osi.IsInForceTurnBasedMode(uuid) == 0 then
        local level = Osi.GetRegion(uuid)
        if level == "TUT_Avernus_C" then
            addNearbyToBrawlers(uuid, 30)
            if Brawlers and Brawlers[level] and isAliveAndCanFight(TUT_ZHALK_UUID) and isAliveAndCanFight(TUT_MIND_FLAYER_UUID) then
                if not Brawlers[level][TUT_ZHALK_UUID] then
                    addBrawler(TUT_ZHALK_UUID, true)
                end
                if not Brawlers[level][TUT_MIND_FLAYER_UUID] then
                    addBrawler(TUT_MIND_FLAYER_UUID, true)
                end
                Brawlers[level][TUT_ZHALK_UUID].targetUuid = TUT_MIND_FLAYER_UUID
                Brawlers[level][TUT_ZHALK_UUID].lockedOnTarget = true
                Brawlers[level][TUT_MIND_FLAYER_UUID].targetUuid = TUT_ZHALK_UUID
                Brawlers[level][TUT_MIND_FLAYER_UUID].lockedOnTarget = true
            end
            nautiloidTransponderCountdown(uuid, turnsRemaining)
        else
            questTimerCancel("TUT_Helm_Timer")
        end
    end
end

function lakesideRitualCountdown(uuid, turnsRemaining)
    if turnsRemaining == LAKESIDE_RITUAL_COUNTDOWN_TURNS then
        addBrawler(HALSIN_PORTAL_UUID, true)
    end
    setCountdownTimer(uuid, turnsRemaining, onLakesideRitualTurn)
end

function nautiloidTransponderCountdown(uuid, turnsRemaining)
    setCountdownTimer(uuid, turnsRemaining, onNautiloidTransponderTurn)
end

function questTimerCancel(timer)
    if Players then
        for uuid, _ in pairs(Players) do
            Osi.ObjectTimerCancel(uuid, timer)
        end
    end
end

function questTimerLaunch(timer, textKey, numRounds)
    if Players then
        for uuid, _ in pairs(Players) do
            Osi.ObjectQuestTimerLaunch(uuid, timer, textKey, COUNTDOWN_TURN_INTERVAL*numRounds, 1)
        end
    end
end

function setCountdownTimer(uuid, turnsRemaining, onNextTurn)
    CountdownTimer = {
        uuid = uuid,
        turnsRemaining = turnsRemaining,
        resume = onNextTurn,
        timer = Ext.Timer.WaitFor(COUNTDOWN_TURN_INTERVAL, function ()
            onNextTurn(uuid, turnsRemaining - 1)
        end)
    }
end

function stopCountdownTimer(uuid)
    if CountdownTimer.uuid ~= nil and uuid == CountdownTimer.uuid and CountdownTimer.timer ~= nil then
        debugPrint("Stopping countdown", CountdownTimer.uuid, CountdownTimer.turnsRemaining)
        Ext.Timer.Cancel(CountdownTimer.timer)
        CountdownTimer.timer = nil
    end
end

function resumeCountdownTimer(uuid)
    if CountdownTimer.uuid ~= nil and uuid == CountdownTimer.uuid then
        debugPrint("Resuming countdown", CountdownTimer.uuid, CountdownTimer.turnsRemaining)
        CountdownTimer.resume(CountdownTimer.uuid, CountdownTimer.turnsRemaining)
    end
end