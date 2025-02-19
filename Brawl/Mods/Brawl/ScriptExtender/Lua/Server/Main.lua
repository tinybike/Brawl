Constants = require("Server/Constants.lua")
Utils = require("Server/Utils.lua")
State = require("Server/State.lua")
Resources = require("Server/Resources.lua")
Movement = require("Server/Movement.lua")
Roster = require("Server/Roster.lua")
AI = require("Server/AI.lua")
Pause = require("Server/Pause.lua")
Quests = require("Server/Quests.lua")
Commands = require("Server/Commands.lua")
Listeners = require("Server/Listeners.lua")

local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump
local getDisplayName = Utils.getDisplayName
local isToT = Utils.isToT

function stopPulseAction(brawler, remainInBrawl)
    if not remainInBrawl then
        brawler.isInBrawl = false
    end
    if State.Session.PulseActionTimers[brawler.uuid] ~= nil then
        debugPrint("stop pulse action", brawler.displayName, remainInBrawl)
        Ext.Timer.Cancel(State.Session.PulseActionTimers[brawler.uuid])
        State.Session.PulseActionTimers[brawler.uuid] = nil
    end
end

function startPulseAction(brawler)
    if Osi.IsPlayer(brawler.uuid) == 1 and not State.Settings.CompanionAIEnabled then
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
        Ext.Timer.Cancel(State.Session.BrawlFizzler[level])
        State.Session.BrawlFizzler[level] = nil
    end
end

function startBrawlFizzler(level)
    stopBrawlFizzler(level)
    debugPrint("Starting BrawlFizzler", level)
    State.Session.BrawlFizzler[level] = Ext.Timer.WaitFor(Constants.BRAWL_FIZZLER_TIMEOUT, function ()
        debugPrint("Brawl fizzled", Constants.BRAWL_FIZZLER_TIMEOUT)
        Roster.endBrawl(level)
    end)
end

function stopPulseAddNearby(uuid)
    debugPrint("stopPulseAddNearby", uuid, getDisplayName(uuid))
    if State.Session.PulseAddNearbyTimers[uuid] ~= nil then
        Ext.Timer.Cancel(State.Session.PulseAddNearbyTimers[uuid])
        State.Session.PulseAddNearbyTimers[uuid] = nil
    end
end

function startPulseAddNearby(uuid)
    debugPrint("startPulseAddNearby", uuid, getDisplayName(uuid))
    if State.Session.PulseAddNearbyTimers[uuid] == nil then
        State.Session.PulseAddNearbyTimers[uuid] = Ext.Timer.WaitFor(0, function ()
            if not isToT() then
                AI.pulseAddNearby(uuid)
            end
        end, 7500)
    end
end

function stopPulseReposition(level)
    debugPrint("stopPulseReposition", level)
    if State.Session.PulseRepositionTimers[level] ~= nil then
        Ext.Timer.Cancel(State.Session.PulseRepositionTimers[level])
        State.Session.PulseRepositionTimers[level] = nil
    end
end

-- Reposition if needed every REPOSITION_INTERVAL ms
function startPulseReposition(level, skipCompanions)
    if State.Session.PulseRepositionTimers[level] == nil then
        debugPrint("startPulseReposition", level, skipCompanions)
        State.Session.PulseRepositionTimers[level] = Ext.Timer.WaitFor(0, function ()
            AI.pulseReposition(level, skipCompanions)
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
        Roster.endBrawl(level)
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
        Roster.endBrawl(level)
        Ext.Timer.Cancel(timer)
    end
end

function cleanupAll()
    stopAllPulseAddNearbyTimers()
    stopAllPulseRepositionTimers()
    stopAllPulseActionTimers()
    stopAllBrawlFizzlers()
    local hostCharacter = Osi.GetHostCharacter()
    if hostCharacter then
        local level = Osi.GetRegion(hostCharacter)
        if level then
            Roster.endBrawl(level)
        end
    end
    State.revertAllModifiedHitpoints()
    State.resetSpellData()
end

function stopToTTimers()
    if State.Session.ToTRoundTimer ~= nil then
        Ext.Timer.Cancel(State.Session.ToTRoundTimer)
        State.Session.ToTRoundTimer = nil
    end
    if State.Session.ToTTimer ~= nil then
        Ext.Timer.Cancel(State.Session.ToTTimer)
        State.Session.ToTTimer = nil
    end
end

function startToTTimers()
    debugPrint("startToTTimers")
    stopToTTimers()
    if not Mods.ToT.Player.InCamp() then
        State.Session.ToTRoundTimer = Ext.Timer.WaitFor(6000, function ()
            if Mods.ToT.PersistentVars.Scenario and Mods.ToT.PersistentVars.Scenario.Round < #Mods.ToT.PersistentVars.Scenario.Timeline then
                debugPrint("Moving ToT forward")
                Mods.ToT.Scenario.ForwardCombat()
                Ext.Timer.WaitFor(1500, function ()
                    Roster.addNearbyToBrawlers(Osi.GetHostCharacter(), 150)
                end)
            end
            startToTTimers()
        end)
        if Mods.ToT.PersistentVars.Scenario then
            local isPrepRound = (Mods.ToT.PersistentVars.Scenario.Round == 0) and (next(Mods.ToT.PersistentVars.Scenario.SpawnedEnemies) == nil)
            if isPrepRound then
                State.Session.ToTTimer = Ext.Timer.WaitFor(0, function ()
                    debugPrint("adding nearby...")
                    Roster.addNearbyToBrawlers(Osi.GetHostCharacter(), 150)
                end, 8500)
            end
        end
    end
end

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
        print("State not loaded, retrying...")
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
