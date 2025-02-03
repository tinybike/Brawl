-- local Constants = require("Server/Constants.lua")
-- local Utils = require("Server/Utils.lua")
-- local State = require("Server/State.lua")
-- local Roster = require("Server/Roster.lua")

local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump
local isAliveAndCanFight = Utils.isAliveAndCanFight
local onLakesideRitualTurn
local onNautiloidTransponderTurn

local function questTimerCancel(timer)
    local players = State.Session.Players
    if players then
        for uuid, _ in pairs(players) do
            Osi.ObjectTimerCancel(uuid, timer)
        end
    end
end

local function questTimerLaunch(timer, textKey, numRounds)
    local players = State.Session.Players
    if players then
        for uuid, _ in pairs(players) do
            Osi.ObjectQuestTimerLaunch(uuid, timer, textKey, Constants.COUNTDOWN_TURN_INTERVAL*numRounds, 1)
        end
    end
end

local function setCountdownTimer(uuid, turnsRemaining, onNextTurn)
    State.Session.CountdownTimer = {
        uuid = uuid,
        turnsRemaining = turnsRemaining,
        resume = onNextTurn,
        timer = Ext.Timer.WaitFor(Constants.COUNTDOWN_TURN_INTERVAL, function ()
            onNextTurn(uuid, turnsRemaining - 1)
        end)
    }
end

local function lakesideRitualCountdown(uuid, turnsRemaining)
    if turnsRemaining == Constants.LAKESIDE_RITUAL_COUNTDOWN_TURNS then
        Roster.addBrawler(Constants.HALSIN_PORTAL_UUID, true)
    end
    setCountdownTimer(uuid, turnsRemaining, onLakesideRitualTurn)
end

local function nautiloidTransponderCountdown(uuid, turnsRemaining)
    setCountdownTimer(uuid, turnsRemaining, onNautiloidTransponderTurn)
end

onLakesideRitualTurn = function (uuid, turnsRemaining)
    debugPrint("onLakesideRitualTurn", turnsRemaining, Osi.QRY_HAV_IsRitualActive())
    if Osi.QRY_HAV_IsRitualActive() and turnsRemaining > 0 then
        if Osi.IsInForceTurnBasedMode(uuid) == 0 then
            local currentTurn = Constants.LAKESIDE_RITUAL_COUNTDOWN_TURNS - turnsRemaining
            Osi.PROC_HAV_LiftingTheCurse_SpawnWave(currentTurn)
            Osi.PROC_HAV_LiftingTheCurse_DeclareRound(currentTurn)
            Ext.Timer.WaitFor(200, function ()
                if Osi.IsInForceTurnBasedMode(uuid) == 0 then
                    Roster.addNearbyToBrawlers(uuid, 30)
                    local level = Osi.GetRegion(uuid)
                    if level and State.Session.Brawlers then
                        local brawlersInLevel = State.Session.Brawlers[level]
                        if brawlersInLevel then
                            for brawlerUuid, brawler in pairs(brawlersInLevel) do
                                if Osi.IsEnemy(uuid, brawlerUuid) == 1 then
                                    if math.random() > 0.85 then
                                        brawler.targetUuid = Constants.HALSIN_PORTAL_UUID
                                        brawler.lockedOnTarget = true
                                    end
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
        Roster.removeBrawler(level, Constants.HALSIN_PORTAL_UUID)
        Roster.checkForEndOfBrawl(level)
    end
end

onNautiloidTransponderTurn = function (uuid, turnsRemaining)
    debugPrint("onNautiloidTransponderTurn", turnsRemaining)
    if turnsRemaining > 0 and Osi.IsInForceTurnBasedMode(uuid) == 0 then
        local level = Osi.GetRegion(uuid)
        if level == "TUT_Avernus_C" then
            Roster.addNearbyToBrawlers(uuid, 30)
            if State.Session.Brawlers then
                local brawlersInLevel = State.Session.Brawlers[level]
                if brawlersInLevel and isAliveAndCanFight(Constants.TUT_ZHALK_UUID) and isAliveAndCanFight(Constants.TUT_MIND_FLAYER_UUID) then
                    if not brawlersInLevel[Constants.TUT_ZHALK_UUID] then
                        Roster.addBrawler(Constants.TUT_ZHALK_UUID, true)
                    end
                    if not brawlersInLevel[Constants.TUT_MIND_FLAYER_UUID] then
                        Roster.addBrawler(Constants.TUT_MIND_FLAYER_UUID, true)
                    end
                    brawlersInLevel[Constants.TUT_ZHALK_UUID].targetUuid = Constants.TUT_MIND_FLAYER_UUID
                    brawlersInLevel[Constants.TUT_ZHALK_UUID].lockedOnTarget = true
                    brawlersInLevel[Constants.TUT_MIND_FLAYER_UUID].targetUuid = Constants.TUT_ZHALK_UUID
                    brawlersInLevel[Constants.TUT_MIND_FLAYER_UUID].lockedOnTarget = true
                end
            end
            nautiloidTransponderCountdown(uuid, turnsRemaining)
        else
            questTimerCancel("TUT_Helm_Timer")
        end
    end
end

local function nautiloidTransponderCountdownFinished(uuid)
    if uuid ~= nil and uuid == Osi.GetHostCharacter() then
        Osi.PROC_TUT_Helm_GameOver()
    end
end

local function lakesideRitualCountdownFinished(uuid)
    if uuid ~= nil and uuid == Osi.GetHostCharacter() and Osi.GetHitpoints(Constants.HALSIN_PORTAL_UUID) ~= nil and Osi.QRY_HAV_IsRitualActive() then
        Osi.PROC_HAV_LiftingTheCurse_CheckRound(0)
    end
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

return {
    nautiloidTransponderCountdownFinished = nautiloidTransponderCountdownFinished,
    lakesideRitualCountdownFinished = lakesideRitualCountdownFinished,
    lakesideRitualCountdown = lakesideRitualCountdown,
    nautiloidTransponderCountdown = nautiloidTransponderCountdown,
    questTimerCancel = questTimerCancel,
    questTimerLaunch = questTimerLaunch,
    stopCountdownTimer = stopCountdownTimer,
    resumeCountdownTimer = resumeCountdownTimer,
}
