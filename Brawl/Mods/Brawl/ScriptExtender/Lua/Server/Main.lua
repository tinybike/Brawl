Constants = require("Server/Constants.lua")
Utils = require("Server/Utils.lua")
State = require("Server/State.lua")
Spells = require("Server/Spells.lua")
Resources = require("Server/Resources.lua")
Movement = require("Server/Movement.lua")
Leaderboard = require("Server/Leaderboard.lua")
Roster = require("Server/Roster.lua")
Actions = require("Server/Actions.lua")
Pick = require("Server/Pick.lua")
AI = require("Server/AI.lua")
Pause = require("Server/Pause.lua")
Quests = require("Server/Quests.lua")
Commands = require("Server/Commands.lua")
Listeners = require("Server/Listeners.lua")
Swarm = require("Server/Swarm.lua")
M = require("Server/Memo.lua")
-- ECSPrinter = require("Server/ECSPrinter.lua")

local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump

function stopPulseAction(brawler, remainInBrawl)
    debugPrint("Stop Pulse Action for brawler", brawler.uuid, brawler.displayName)
    if not remainInBrawl then
        brawler.isInBrawl = false
    end
    if State.Session.PulseActionTimers[brawler.uuid] ~= nil then
        debugPrint("stop pulse action", brawler.displayName, remainInBrawl)
        Ext.Timer.Cancel(State.Session.PulseActionTimers[brawler.uuid])
        State.Session.PulseActionTimers[brawler.uuid] = nil
    end
end

function stopAllPulseActions(remainInBrawl)
    for uuid, timer in pairs(State.Session.PulseActionTimers) do
        stopPulseAction(M.Roster.getBrawlerByUuid(uuid), remainInBrawl)
    end
end

function startPulseAction(brawler)
    if M.Osi.IsPlayer(brawler.uuid) == 1 and not State.Settings.CompanionAIEnabled then
        return false
    end
    if Constants.IS_TRAINING_DUMMY[brawler.uuid] then
        return false
    end
    if State.Session.PulseActionTimers[brawler.uuid] == nil then
        brawler.isInBrawl = true
        debugPrint("Starting pulse action", brawler.displayName, brawler.uuid, brawler.actionInterval)
        State.Session.PulseActionTimers[brawler.uuid] = Ext.Timer.WaitFor(0, function ()
            AI.pulseAction(brawler)
        end, brawler.actionInterval)
    end
end

function stopBrawlFizzler(level)
    if State.Session.BrawlFizzler[level] ~= nil then
        debugPrint("stopping brawl fizz")
        Ext.Timer.Cancel(State.Session.BrawlFizzler[level])
        State.Session.BrawlFizzler[level] = nil
    end
end

function startBrawlFizzler(level)
    stopBrawlFizzler(level)
    if not State.Settings.TurnBasedSwarmMode then
        -- debugPrint("Starting BrawlFizzler", level)
        -- State.Session.BrawlFizzler[level] = Ext.Timer.WaitFor(Constants.BRAWL_FIZZLER_TIMEOUT, function ()
        --     debugPrint("Brawl fizzled", Constants.BRAWL_FIZZLER_TIMEOUT)
        --     Roster.endBrawl(level)
        -- end)
    end
end

function stopPulseAddNearby(uuid)
    debugPrint("stopPulseAddNearby", uuid, M.Utils.getDisplayName(uuid))
    if State.Session.PulseAddNearbyTimers[uuid] ~= nil then
        Ext.Timer.Cancel(State.Session.PulseAddNearbyTimers[uuid])
        State.Session.PulseAddNearbyTimers[uuid] = nil
    end
end

function startPulseAddNearby(uuid)
    debugPrint("startPulseAddNearby", uuid, Utils.getDisplayName(uuid))
    if State.Session.PulseAddNearbyTimers[uuid] == nil then
        State.Session.PulseAddNearbyTimers[uuid] = Ext.Timer.WaitFor(0, function ()
            AI.pulseAddNearby(uuid)
        end, 7500)
    end
end

function stopPulseReposition()
    debugPrint("stopPulseReposition")
    for level, timer in pairs(State.Session.PulseRepositionTimers) do
        Ext.Timer.Cancel(timer)
        State.Session.PulseRepositionTimers[level] = nil
    end
end

-- Reposition if needed every REPOSITION_INTERVAL ms
function startPulseReposition(level)
    if State.Session.PulseRepositionTimers[level] == nil then
        debugPrint("startPulseReposition", level)
        State.Session.PulseRepositionTimers[level] = Ext.Timer.WaitFor(0, function ()
            AI.pulseReposition(level)
        end, Constants.REPOSITION_INTERVAL)
    end
end

function stopAllPulseAddNearbyTimers()
    local pulseAddNearbyTimers = State.Session.PulseAddNearbyTimers
    for _, timer in pairs(pulseAddNearbyTimers) do
        Ext.Timer.Cancel(timer)
    end
end

function stopAllPulseRepositionTimers()
    local pulseRepositionTimers = State.Session.PulseRepositionTimers
    for level, timer in pairs(pulseRepositionTimers) do
        Ext.Timer.Cancel(timer)
    end
end

function stopAllPulseActionTimers()
    local pulseActionTimers = State.Session.PulseActionTimers
    for _, timer in pairs(pulseActionTimers) do
        Ext.Timer.Cancel(timer)
    end
end

function stopAllBrawlFizzlers()
    local brawlFizzler = State.Session.BrawlFizzler
    for level, timer in pairs(brawlFizzler) do
        Ext.Timer.Cancel(timer)
    end
end

function cleanupAll()
    stopAllPulseAddNearbyTimers()
    stopAllPulseRepositionTimers()
    stopAllPulseActionTimers()
    stopAllBrawlFizzlers()
    State.endBrawls()
    State.revertAllModifiedHitpoints()
    State.recapPartyMembersMovementDistances()
    Spells.resetSpellData()
end

function pauseCombatRoundTimer(combatGuid)
    if State.Session.CombatRoundTimer and State.Session.CombatRoundTimer[combatGuid] then
        Ext.Timer.Pause(State.Session.CombatRoundTimer[combatGuid])
    end
end

function resumeCombatRoundTimer(combatGuid)
    if State.Session.CombatRoundTimer and State.Session.CombatRoundTimer[combatGuid] then
        Ext.Timer.Resume(State.Session.CombatRoundTimer[combatGuid])
    end
end

function cancelCombatRoundTimer(combatGuid)
    if State.Session.CombatRoundTimer and State.Session.CombatRoundTimer[combatGuid] then
        Ext.Timer.Cancel(State.Session.CombatRoundTimer[combatGuid])
        State.Session.CombatRoundTimer[combatGuid] = nil
    end
end

function pauseCombatRoundTimers()
    if State.Session.CombatRoundTimer and next(State.Session.CombatRoundTimer) then
        for combatGuid, timer in pairs(State.Session.CombatRoundTimer) do
            Ext.Timer.Pause(timer)
        end
    end
end

function resumeCombatRoundTimers()
    if State.Session.CombatRoundTimer and next(State.Session.CombatRoundTimer) then
        for combatGuid, timer in pairs(State.Session.CombatRoundTimer) do
            Ext.Timer.Resume(timer)
        end
    end
end

function cancelCombatRoundTimers()
    if State.Session.CombatRoundTimer and next(State.Session.CombatRoundTimer) then
        for combatGuid, timer in pairs(State.Session.CombatRoundTimer) do
            Ext.Timer.Cancel(timer)
            State.Session.CombatRoundTimer[combatGuid] = nil
        end
    end
end

-- NB: is the wrapping timer getting paused correctly during pause?
function nextCombatRound()
    print("nextCombatRound")
    Ext.ServerNet.BroadcastMessage("NextCombatRound", "")
    if not Pause.isPartyInFTB() then
        for uuid, _ in pairs(M.Roster.getBrawlers()) do
            local entity = Ext.Entity.Get(uuid)
            if entity and entity.TurnBased then
                if M.Osi.IsPartyMember(uuid, 1) == 0 then
                    entity.TurnBased.HadTurnInCombat = true
                    entity.TurnBased.TurnActionsCompleted = true
                end
                entity.TurnBased.RequestedEndTurn = true
                entity:Replicate("TurnBased")
            end
        end
    end
end

function startCombatRoundTimer(combatGuid)
    -- if not State.isInCombat() then
    --     Osi.PauseCombat(combatGuid)
    -- end
    local turnDuration = State.Settings.ActionInterval*1000
    if not Utils.isToT() then
        State.Session.CombatRoundTimer[combatGuid] = Ext.Timer.WaitFor(turnDuration, nextCombatRound)
    else
        State.Session.CombatRoundTimer[combatGuid] = Ext.Timer.WaitFor(turnDuration, function ()
            nextCombatRound()
            if Mods.ToT.PersistentVars.Scenario and Mods.ToT.PersistentVars.Scenario.Round < #Mods.ToT.PersistentVars.Scenario.Timeline then
                debugPrint("ToT advancing scenario", Mods.ToT.PersistentVars.Scenario.Round, #Mods.ToT.PersistentVars.Scenario.Timeline)
                Mods.ToT.Scenario.ForwardCombat()
            end
            -- if State.Session.ToTRoundAddNearbyTimer then
            --     Ext.Timer.Cancel(State.Session.ToTRoundAddNearbyTimer)
            --     State.Session.ToTRoundAddNearbyTimer = nil
            -- end
            -- State.Session.ToTRoundAddNearbyTimer = Ext.Timer.WaitFor(1500, function ()
            --     if Osi.IsInForceTurnBasedMode(hostCharacter) == 0 then
            --         Roster.addNearbyToBrawlers(hostCharacter, 150)
            --     end
            -- end)
            -- if Mods.ToT.PersistentVars.Scenario.Round < #Mods.ToT.PersistentVars.Scenario.Timeline then
            --     if Osi.IsInForceTurnBasedMode(hostCharacter) == 0 then
            --         startToTTimers(combatGuid)
            --     end
            -- end
        end)
    end
end

-- function pauseToTTimers()
--     if State.Session.ToTTimer then
--         Ext.Timer.Pause(State.Session.ToTTimer)
--     end
--     if State.Session.ToTRoundAddNearbyTimer then
--         Ext.Timer.Pause(State.Session.ToTRoundAddNearbyTimer)
--     end
-- end

-- function resumeToTTimers()
--     if State.Session.ToTTimer then
--         Ext.Timer.Resume(State.Session.ToTTimer)
--     end
--     if State.Session.ToTRoundAddNearbyTimer then
--         Ext.Timer.Resume(State.Session.ToTRoundAddNearbyTimer)
--     end
-- end

-- function stopToTTimers()
--     cancelCombatRoundTimers()
--     if State.Session.ToTTimer then
--         Ext.Timer.Cancel(State.Session.ToTTimer)
--         State.Session.ToTTimer = nil
--     end
--     if State.Session.ToTRoundAddNearbyTimer then
--         Ext.Timer.Cancel(State.Session.ToTRoundAddNearbyTimer)
--         State.Session.ToTRoundAddNearbyTimer = nil
--     end
-- end

-- function startToTTimers(combatGuid)
--     debugPrint("startToTTimers")
--     stopToTTimers()
--     if not Mods.ToT.Player.InCamp() then
--         startCombatRoundTimer(combatGuid)
--         -- if Mods.ToT.PersistentVars.Scenario then
--         --     local isPrepRound = (Mods.ToT.PersistentVars.Scenario.Round == 0) and (next(Mods.ToT.PersistentVars.Scenario.SpawnedEnemies) == nil)
--         --     if isPrepRound then
--         --         local hostCharacter = M.Osi.GetHostCharacter()
--         --         local turnDuration = State.Settings.ActionInterval*1000
--         --         State.Session.ToTTimer = Ext.Timer.WaitFor(0, function ()
--         --             if Osi.IsInForceTurnBasedMode(hostCharacter) == 0 then
--         --                 Roster.addNearbyToBrawlers(hostCharacter, 150)
--         --             end
--         --         end, turnDuration + math.floor(turnDuration*0.25))
--         --     end
--         -- end
--     end
-- end

local function onGameStateChanged(e)
    if e and e.ToState == "UnloadLevel" then
        cleanupAll()
    end
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
        debugPrint("State not loaded, retrying...")
        return Ext.Timer.WaitFor(250, startSession)
    end
    if State.Settings.ModEnabled then
        Listeners.startListeners()
    else
        Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", State.resetPlayers)
    end
end

local function onSessionLoaded()
    Ext.Events.NetMessage:Subscribe(onNetMessage)
    startSession()
end

Ext.Events.SessionLoaded:Subscribe(onSessionLoaded)
Ext.Events.GameStateChanged:Subscribe(onGameStateChanged)
if MCM then
    Ext.ModEvents.BG3MCM["MCM_Setting_Saved"]:Subscribe(onMCMSettingSaved)
end
