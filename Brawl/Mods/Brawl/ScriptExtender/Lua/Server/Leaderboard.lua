local function initialize()
    State.Session.Leaderboard = {}
    local players = State.Session.Players
    if players then
        for uuid, player in pairs(players) do
            State.Session.Leaderboard[uuid] = {
                name = player.displayName or "",
                kills = 0,
                damageDone = 0,
                damageTaken = 0,
                healingDone = 0,
                healingTaken = 0,
            }
        end
    end
end

local function showForUser(userId)
    if State.Settings.LeaderboardEnabled then
        Ext.ServerNet.PostMessageToUser(userId, "Leaderboard", Ext.Json.Stringify(State.Session.Leaderboard))
    end
end

local function postDataToClients(updateOnly)
    if State.Settings.LeaderboardEnabled and not State.Session.LeaderboardUpdateTimer then
        local leaderboardData = Ext.Json.Stringify(State.Session.Leaderboard)
        if updateOnly then
            Ext.ServerNet.BroadcastMessage("UpdateLeaderboard", leaderboardData)
        else
            Ext.ServerNet.BroadcastMessage("Leaderboard", leaderboardData)
        end
        State.Session.LeaderboardUpdateTimer = Ext.Timer.WaitFor(Constants.LEADERBOARD_UPDATE_TIMEOUT, function ()
            State.Session.LeaderboardUpdateTimer = nil
        end)
    end
end

local function isExcludedHeal(status)
    if status.Originator and status.Originator.PassiveId then
        for _, excludedHeal in ipairs(Constants.LEADERBOARD_EXCLUDED_HEALS) do
            if status.Originator.PassiveId == excludedHeal then
                return true
            end
        end
    end
    return false
end

local function updateKills(uuid)
    if State.Settings.LeaderboardEnabled and Osi.IsCharacter(uuid) == 1 then
        State.Session.Leaderboard[uuid] = State.Session.Leaderboard[uuid] or {}
        State.Session.Leaderboard[uuid].name = State.Session.Leaderboard[uuid].name or (M.Utils.getDisplayName(uuid) or "")
        State.Session.Leaderboard[uuid].kills = State.Session.Leaderboard[uuid].kills or 0
        State.Session.Leaderboard[uuid].kills = State.Session.Leaderboard[uuid].kills + 1
        postDataToClients(true)
    end
end

local function updateHealing(healerUuid, targetUuid, amount)
    if State.Settings.LeaderboardEnabled and Osi.IsCharacter(targetUuid) == 1 then
        State.Session.Leaderboard[targetUuid] = State.Session.Leaderboard[targetUuid] or {}
        State.Session.Leaderboard[targetUuid].name = State.Session.Leaderboard[targetUuid].name or (M.Utils.getDisplayName(targetUuid) or "")
        State.Session.Leaderboard[targetUuid].healingTaken = State.Session.Leaderboard[targetUuid].healingTaken or 0
        State.Session.Leaderboard[targetUuid].healingTaken = State.Session.Leaderboard[targetUuid].healingTaken + amount
        State.Session.Leaderboard[healerUuid] = State.Session.Leaderboard[healerUuid] or {}
        State.Session.Leaderboard[healerUuid].name = State.Session.Leaderboard[healerUuid].name or (M.Utils.getDisplayName(healerUuid) or "")
        State.Session.Leaderboard[healerUuid].healingDone = State.Session.Leaderboard[healerUuid].healingDone or 0
        if Osi.IsEnemy(healerUuid, targetUuid) == 1 then
            amount = -amount
        end
        State.Session.Leaderboard[healerUuid].healingDone = State.Session.Leaderboard[healerUuid].healingDone + amount
        postDataToClients(true)
    end
end

local function updateDamage(attackerUuid, defenderUuid, amount)
    if State.Settings.LeaderboardEnabled and Osi.IsCharacter(defenderUuid) == 1 then
        State.Session.Leaderboard[defenderUuid] = State.Session.Leaderboard[defenderUuid] or {}
        State.Session.Leaderboard[defenderUuid].name = State.Session.Leaderboard[defenderUuid].name or (M.Utils.getDisplayName(defenderUuid) or "")
        State.Session.Leaderboard[defenderUuid].damageTaken = State.Session.Leaderboard[defenderUuid].damageTaken or 0
        State.Session.Leaderboard[defenderUuid].damageTaken = State.Session.Leaderboard[defenderUuid].damageTaken + amount
        if attackerUuid ~= defenderUuid then
            State.Session.Leaderboard[attackerUuid] = State.Session.Leaderboard[attackerUuid] or {}
            State.Session.Leaderboard[attackerUuid].name = State.Session.Leaderboard[attackerUuid].name or (M.Utils.getDisplayName(attackerUuid) or "")
            State.Session.Leaderboard[attackerUuid].damageDone = State.Session.Leaderboard[attackerUuid].damageDone or 0
            if Osi.IsEnemy(attackerUuid, defenderUuid) == 0 then
                amount = -amount
            end
            State.Session.Leaderboard[attackerUuid].damageDone = State.Session.Leaderboard[attackerUuid].damageDone + amount
        end
        postDataToClients(true)
    end
end

local function dumpToConsole()
    local nameColWidth, ddW, dtW, kW, hdW, htW = 0, #("Damage"), #("Taken"), #("Kills"), #("Healing"), #("Healed")
    for uuid, stats in pairs(State.Session.Leaderboard) do
        nameColWidth = math.max(nameColWidth, #stats.name)
        ddW = math.max(ddW, #tostring(stats.damageDone or 0))
        dtW = math.max(dtW, #tostring(stats.damageTaken or 0))
        kW  = math.max(kW, #tostring(stats.kills or 0))
        hdW = math.max(hdW, #tostring(stats.healingDone or 0))
        htW = math.max(htW, #tostring(stats.healingTaken or 0))
    end
    local nameFmt = "%-" .. nameColWidth .. "s"
    local ddFmt = "%"  .. ddW   .. "d"
    local dtFmt = "%"  .. dtW   .. "d"
    local kFmt = "%"  .. kW    .. "d"
    local hdFmt = "%"  .. hdW   .. "d"
    local htFmt = "%"  .. htW   .. "d"
    local colSep = "  "
    local fmt = table.concat({nameFmt, ddFmt, dtFmt, kFmt, hdFmt, htFmt}, colSep)
    local hdrFmt = table.concat({nameFmt, "%-" .. ddW .. "s", "%-" .. dtW .. "s", "%-" .. kW  .. "s", "%-" .. hdW .. "s", "%-" .. htW .. "s" }, colSep)
    local totalWidth = nameColWidth + #colSep + ddW + #colSep + dtW + #colSep + kW + #colSep + hdW + #colSep + htW
    local function makeSep(title)
        local txt = "| " .. title .. " |"
        local pad = totalWidth - #txt
        local left = math.floor(pad/2)
        local right = pad - left
        return string.rep("=", left) .. txt .. string.rep("=", right)
    end
    local party, enemy = {}, {}
    for uuid, stats in pairs(State.Session.Leaderboard) do
        local row = {
            uuid = uuid,
            name = stats.name,
            damageDone = stats.damageDone or 0,
            damageTaken = stats.damageTaken or 0,
            kills = stats.kills or 0,
            healingDone = stats.healingDone or 0,
            healingTaken = stats.healingTaken or 0,
        }
        if Osi.IsPartyMember(uuid, 1) == 1 then
            party[#party + 1] = row
        else
            enemy[#enemy + 1] = row
        end
    end
    table.sort(party, function (a, b) return a.damageDone > b.damageDone end)
    table.sort(enemy, function (a, b) return a.damageDone > b.damageDone end)
    _P(makeSep("PARTY TOTALS"))
    _P(string.format(hdrFmt, "Name", "Damage", "Taken", "Kills", "Healing", "Healed"))
    for _, e in ipairs(party) do
        _P(string.format(fmt, e.name, e.damageDone, e.damageTaken, e.kills, e.healingDone, e.healingTaken))
    end
    _P(makeSep("ENEMY TOTALS"))
    _P(string.format(hdrFmt, "Name", "Damage", "Taken", "Kills", "Healing", "Healed"))
    for _, e in ipairs(enemy) do
        _P(string.format(fmt, e.name, e.damageDone, e.damageTaken, e.kills, e.healingDone, e.healingTaken))
    end
    _P(string.rep("=", totalWidth))
end

return {
    initialize = initialize,
    showForUser = showForUser,
    postDataToClients = postDataToClients,
    isExcludedHeal = isExcludedHeal,
    updateKills = updateKills,
    updateDamage = updateDamage,
    updateHealing = updateHealing,
    dumpToConsole = dumpToConsole,
}
