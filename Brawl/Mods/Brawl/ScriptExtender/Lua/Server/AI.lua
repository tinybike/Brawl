local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump
local isPlayerControllingDirectly = State.isPlayerControllingDirectly
local clearOsirisQueue = Utils.clearOsirisQueue
local isToT = Utils.isToT
local noop = Utils.noop

local function actOnHostileTarget(brawler, target, bonusActionOnly, excludedSpells, onSubmitted, onCompleted, onFailed)
    local distanceToTarget = M.Osi.GetDistanceTo(brawler.uuid, target.uuid)
    if not brawler or not target then
        return onFailed("brawler/target not found")
    end
    local actionToTake = nil
    local spellTypes = {"Control", "Damage"}
    local preparedSpells = Ext.Entity.Get(brawler.uuid).SpellBookPrepares.PreparedSpells
    if M.Osi.IsPlayer(brawler.uuid) == 1 then
        local allowAoE = M.Osi.HasPassive(brawler.uuid, "SculptSpells") == 1
        local playerClosestToTarget = M.Osi.GetClosestAlivePlayer(target.uuid) or brawler.uuid
        local targetDistanceToParty = M.Osi.GetDistanceTo(target.uuid, playerClosestToTarget)
        -- debugPrint("target distance to party", targetDistanceToParty, playerClosestToTarget)
        actionToTake = Pick.decideCompanionActionOnTarget(brawler, target.uuid, preparedSpells, excludedSpells, distanceToTarget, {"Damage"}, targetDistanceToParty, allowAoE, bonusActionOnly)
        debugPrint(brawler.displayName, "Companion action to take on hostile target", actionToTake, brawler.uuid, target.uuid, target.displayName, bonusActionOnly)
    else
        actionToTake = Pick.decideActionOnTarget(brawler, target.uuid, preparedSpells, excludedSpells, distanceToTarget, spellTypes, bonusActionOnly)
        debugPrint(brawler.displayName, "Action to take on hostile target", actionToTake, brawler.uuid, target.uuid, target.displayName, brawler.archetype, bonusActionOnly)
    end
    if not actionToTake then
        print("***No hostile actions available for", brawler.uuid, brawler.displayName, bonusActionOnly)
        return onFailed("no hostile actions found")
        -- TODO do we need this fallback...?
        -- if M.Osi.IsPlayer(brawler.uuid) == 1 or State.Settings.TurnBasedSwarmMode then
        --     return onFailed()
        -- end
        -- actionToTake = selectRandomSpell(preparedSpells)
        -- debugPrint(brawler.displayName, "backup ActionToTake", actionToTake, numUsableSpells)
        -- if not actionToTake then
        --     return onFailed()
        -- end
    end
    if not Pick.checkConditions({caster = brawler.uuid, target = target.uuid}, M.Spells.getSpellByName(actionToTake)) then
        excludedSpells = excludedSpells or {}
        table.insert(excludedSpells, actionToTake)
        if #excludedSpells > Constants.MAX_SPELL_EXCLUSIONS then
            return onFailed("too many exclusions")
        end
        return actOnHostileTarget(brawler, target, bonusActionOnly, excludedSpells, onSubmitted, onCompleted, onFailed)
    end
    Movement.moveIntoPositionForSpell(brawler.uuid, target.uuid, actionToTake, bonusActionOnly, function ()
        -- print(brawler.displayName, "movement completed (hostile)", target.displayName, actionToTake)
        Actions.useSpellOnTarget(brawler.uuid, target.uuid, actionToTake, false, onSubmitted, function ()
            debugPrint(brawler.displayName, "complete (hostile)", bonusActionOnly)
            if not bonusActionOnly then
                brawler.targetUuid = targetUuid
            end
            onCompleted()
        end, onFailed)
    end, onFailed)
end

local function actOnFriendlyTarget(brawler, target, bonusActionOnly, excludedSpells, onSubmitted, onCompleted, onFailed)
    local distanceToTarget = M.Osi.GetDistanceTo(brawler.uuid, target.uuid)
    local preparedSpells = Ext.Entity.Get(brawler.uuid).SpellBookPrepares.PreparedSpells
    if not preparedSpells then
        return onFailed("no prepared spells")
    end
    -- todo: Utility/Buff spells
    debugPrint(brawler.displayName, "acting on friendly target", brawler.uuid, target.displayName, bonusActionOnly)
    local spellTypes = {"Healing"}
    if brawler.uuid == target.uuid and not M.State.hasDirectHeal(brawler.uuid, preparedSpells, false, bonusActionOnly) then
        debugPrint(brawler.displayName, "No direct heals found (self)", bonusActionOnly)
        return onFailed("no direct heals found (self)")
    end
    if brawler.uuid ~= target.uuid and not M.State.hasDirectHeal(brawler.uuid, preparedSpells, true, bonusActionOnly) then
        debugPrint(brawler.displayName, "No direct heals found (other)", bonusActionOnly)
        return onFailed("no direct heals found (other)")
    end
    local actionToTake = nil
    if M.Osi.IsPlayer(brawler.uuid) == 1 then
        actionToTake = Pick.decideCompanionActionOnTarget(brawler, target.uuid, preparedSpells, excludedSpells, distanceToTarget, spellTypes, 0, true, bonusActionOnly)
    else
        actionToTake = Pick.decideActionOnTarget(brawler, target.uuid, preparedSpells, excludedSpells, distanceToTarget, spellTypes, bonusActionOnly)
    end
    debugPrint(brawler.displayName, "Action to take on friendly target", actionToTake, brawler.uuid, bonusActionOnly)
    if not actionToTake then
        debugPrint(brawler.displayName, "No friendly actions available for", brawler.uuid, bonusActionOnly)
        return onFailed("no friendly actions available")
        -- if not bonusActionOnly then
        --     return onFailed()
        -- end
        -- return onSubmitted()
    end
    if not Pick.checkConditions({caster = brawler.uuid, target = target.uuid}, M.Spells.getSpellByName(actionToTake)) then
        excludedSpells = excludedSpells or {}
        table.insert(excludedSpells, actionToTake)
        if #excludedSpells > Constants.MAX_SPELL_EXCLUSIONS then
            return onFailed("too many exclusions")
        end
        return actOnFriendlyTarget(brawler, target, bonusActionOnly, excludedSpells, onSubmitted, onCompleted, onFailed)
    end
    Movement.moveIntoPositionForSpell(brawler.uuid, target.uuid, actionToTake, bonusActionOnly, function ()
        Actions.useSpellOnTarget(brawler.uuid, target.uuid, actionToTake, true, onSubmitted, onCompleted, onFailed)
    end, onFailed)
end

local function findTarget(brawler, bonusActionOnly, onSubmitted, onCompleted, onFailed)
    local level = M.Osi.GetRegion(brawler.uuid)
    if level then
        local brawlersSortedByDistance = M.Roster.getBrawlersSortedByDistance(brawler.uuid)
        -- Healing
        local isPlayer = M.Osi.IsPlayer(brawler.uuid) == 1
        local wasHealRequested = false
        local userId
        if isPlayer then
            userId = Osi.GetReservedUserID(brawler.uuid)
            wasHealRequested = State.Session.HealRequested[userId]
        end
        local brawlersInLevel = State.Session.Brawlers[level]
        if wasHealRequested then
            if brawlersInLevel then
                local friendlyTargetUuid = M.Pick.whoNeedsHealing(brawler.uuid, level)
                if friendlyTargetUuid and brawlersInLevel[friendlyTargetUuid] then
                    debugPrint(brawler.displayName, "actOnFriendlyTarget", brawler.uuid, friendlyTargetUuid, M.Utils.getDisplayName(friendlyTargetUuid), bonusActionOnly)
                    return actOnFriendlyTarget(brawler, brawlersInLevel[friendlyTargetUuid], bonusActionOnly, nil, function (request)
                        State.Session.HealRequested[userId] = false
                        onSubmitted(request)
                    end, onFailed)
                end
            end
        end
        if brawlersInLevel then
            local weightedTargets = M.Pick.getWeightedTargets(brawler, brawlersInLevel, bonusActionOnly, M.Pick.whoNeedsHealing(brawler.uuid, level))
            debugDump(weightedTargets)
            local targetUuid = M.Pick.decideOnTarget(weightedTargets)
            if targetUuid then
                local targetBrawler = brawlersInLevel[targetUuid]
                if targetBrawler then
                    local result
                    if M.Utils.isHostileTarget(brawler.uuid, targetUuid) then
                        return actOnHostileTarget(brawler, targetBrawler, bonusActionOnly, nil, onSubmitted, onCompleted, onFailed)
                    else
                        return actOnFriendlyTarget(brawler, targetBrawler, bonusActionOnly, nil, onSubmitted, onCompleted, onFailed)
                    end
                end
            end
        end
        if not bonusActionOnly then
            debugPrint(brawler.displayName, "can't find a target, holding position", brawler.uuid, bonusActionOnly)
            Movement.holdPosition(brawler.uuid)
        end
        return onFailed("can't find target")
    end
end

-- Enemies are pugnacious jerks and looking for a fight >:(
local function checkForBrawlToJoin(brawler)
    local closestPlayerUuid, closestDistance = M.Osi.GetClosestAlivePlayer(brawler.uuid)
    local enterCombatRange = Constants.ENTER_COMBAT_RANGE
    if State.Settings.TurnBasedSwarmMode then
        enterCombatRange = 30
    end
    if closestPlayerUuid ~= nil and closestDistance ~= nil and closestDistance < enterCombatRange then
        debugPrint(brawler.displayName, "Closest alive player to", brawler.uuid, "is", closestPlayerUuid, closestDistance)
        Roster.addBrawler(closestPlayerUuid)
        local players = State.Session.Players
        for playerUuid, player in pairs(players) do
            if playerUuid ~= closestPlayerUuid then
                local distanceTo = M.Osi.GetDistanceTo(brawler.uuid, playerUuid)
                if distanceTo < enterCombatRange then
                    Roster.addBrawler(playerUuid)
                end
            end
        end
        -- local level = M.Osi.GetRegion(brawler.uuid)
        -- if level and State.Session.BrawlFizzler[level] == nil then
        --     debugPrint("check for brawl to join: start fizz")
        --     startBrawlFizzler(level)
        -- end
        debugPrint("check for", brawler.uuid, brawler.displayName)
        startPulseAction(brawler)
    end
end

local function act(brawler, bonusActionOnly, onSubmitted, onCompleted, onFailed)
    onSubmitted = onSubmitted or noop
    onCompleted = onCompleted or noop
    onFailed = onFailed or noop
    if not brawler or not brawler.uuid then
        return onFailed("brawler not found")
    end
    -- NB: should this change depending on offensive/defensive tactics? should this be a setting to enable disable?
    --     should this generally be handled by the healing logic, instead of special-casing it here?
    if M.Utils.isPlayerOrAlly(brawler.uuid) and not bonusActionOnly then
        local players = State.Session.Players
        for playerUuid, player in pairs(players) do
            if not player.isBeingHelped and brawler.uuid ~= playerUuid and M.Utils.isDowned(playerUuid) and M.Osi.GetDistanceTo(playerUuid, brawler.uuid) < Constants.HELP_DOWNED_MAX_RANGE then
                player.isBeingHelped = true
                brawler.targetUuid = nil
                debugPrint(brawler.displayName, "Helping target", playerUuid, M.Utils.getDisplayName(playerUuid))
                return Movement.moveIntoPositionForSpell(brawler.uuid, playerUuid, "Target_Help", bonusActionOnly, function ()
                    Actions.useSpellOnTarget(brawler.uuid, playerUuid, "Target_Help", true, onSubmitted, onCompleted, onFailed)
                end, onFailed)
            end
        end
    end
    -- Rage check for barbarians: if rage is available and we're not already raging, then we should use it
    if State.Settings.TurnBasedSwarmMode and Pick.shouldRage(brawler.uuid, brawler.rage) then
        return Actions.startRage(brawler.uuid, brawler.rage, onSubmitted, onCompleted, onFailed)
    end
    -- Doesn't currently have an attack target, so let's find one
    if brawler.targetUuid == nil then
        debugPrint(brawler.displayName, "Find target (no current target)", brawler.uuid, bonusActionOnly)
        return findTarget(brawler, bonusActionOnly, onSubmitted, onCompleted, onFailed)
    end
    -- We have a target and the target is alive
    local brawlersInLevel = State.Session.Brawlers[M.Osi.GetRegion(brawler.uuid)]
    if brawlersInLevel and brawlersInLevel[brawler.targetUuid] and M.Utils.isAliveAndCanFight(brawler.targetUuid) and M.Utils.isVisible(brawler.uuid, brawler.targetUuid) then
        if not State.Settings.TurnBasedSwarmMode or M.Movement.findPathToTargetUuid(brawler.uuid, brawler.targetUuid) then
            if brawler.lockedOnTarget and M.Utils.isValidHostileTarget(brawler.uuid, brawler.targetUuid) then
                debugPrint(brawler.displayName, "Locked-on target, attacking", M.Utils.getDisplayName(brawler.targetUuid), bonusActionOnly)
                return actOnHostileTarget(brawler, brawlersInLevel[brawler.targetUuid], bonusActionOnly, nil, onSubmitted, onCompleted, onFailed)
            end
            if M.Utils.isPlayerOrAlly(brawler.uuid) and State.Settings.CompanionTactics == "Defense" then
                debugPrint(brawler.displayName, "Find target (defense tactics)", brawler.uuid, bonusActionOnly)
                return findTarget(brawler, bonusActionOnly, onSubmitted, onCompleted, onFailed)
            end
            if M.Utils.isValidHostileTarget(brawler.uuid, brawler.targetUuid) and M.Osi.GetDistanceTo(brawler.uuid, brawler.targetUuid) <= M.Utils.getTrackingDistance() then
                debugPrint(brawler.displayName, "Remaining on target, attacking", M.Utils.getDisplayName(brawler.targetUuid), bonusActionOnly)
                return actOnHostileTarget(brawler, brawlersInLevel[brawler.targetUuid], bonusActionOnly, nil, onSubmitted, onCompleted, onFailed)
            end
        end
    end
    -- Has an attack target but it's already dead or unable to fight, so find a new one
    debugPrint(brawler.displayName, "Find target (current target invalid)", brawler.uuid, bonusActionOnly)
    brawler.targetUuid = nil
    return findTarget(brawler, bonusActionOnly, onSubmitted, onCompleted, onFailed)
end

-- Brawlers doing dangerous stuff
local function pulseAction(brawler, bonusActionOnly, onSubmitted, onCompleted, onFailed)
    onSubmitted = onSubmitted or noop
    onCompleted = onCompleted or noop
    onFailed = onFailed or noop
    -- If this brawler is dead or unable to fight, stop this pulse
    if not brawler or not brawler.uuid or not Utils.canAct(brawler.uuid) then
        stopPulseAction(brawler)
        return onFailed("can't fight")
    end
    if brawler.isPaused then
        return onFailed("paused")
    end
    if isPlayerControllingDirectly(brawler.uuid) and not State.Settings.FullAuto then
        return onFailed("player control")
    end
    -- Brawler is alive and able to fight: let's go!
    if not State.Settings.TurnBasedSwarmMode then
        Roster.addPlayersInEnterCombatRangeToBrawlers(brawler.uuid)
    end
    return act(brawler, bonusActionOnly, onSubmitted, onCompleted, onFailed)
end

-- Reposition the NPC relative to the player.  This is the only place that NPCs should enter the brawl.
local function pulseReposition(level)
    State.checkForDownedOrDeadPlayers()
    local brawlersInLevel = State.Session.Brawlers[level]
    if brawlersInLevel and not State.Settings.TurnBasedSwarmMode then
        for brawlerUuid, brawler in pairs(brawlersInLevel) do
            if not Constants.IS_TRAINING_DUMMY[brawlerUuid] then
                if M.Utils.isAliveAndCanFight(brawlerUuid) and M.Utils.canMove(brawlerUuid) then
                    -- Enemy units are actively looking for a fight and will attack if you get too close to them
                    if M.Utils.isPugnacious(brawlerUuid) then
                        if brawler.isInBrawl and brawler.targetUuid ~= nil and M.Utils.isAliveAndCanFight(brawler.targetUuid) then
                            local _, closestDistance = M.Osi.GetClosestAlivePlayer(brawlerUuid)
                            if closestDistance > 2*Constants.ENTER_COMBAT_RANGE then
                                debugPrint(brawler.displayName, "Too far away, removing brawler", brawlerUuid)
                                Roster.removeBrawler(level, brawlerUuid)
                            else
                                debugPrint(brawler.displayName, "Repositioning", brawlerUuid, "->", brawler.targetUuid)
                                -- Movement.repositionRelativeToTarget(brawlerUuid, brawler.targetUuid)
                            end
                        else
                            -- debugPrint(brawler.displayName, "Checking for a brawl to join", brawlerUuid)
                            checkForBrawlToJoin(brawler)
                        end
                    -- Player, ally, and neutral units are not actively looking for a fight
                    -- - Companions and allies use the same logic
                    -- - Neutrals just chilling
                    elseif M.State.areAnyPlayersBrawling() and M.Utils.isPlayerOrAlly(brawlerUuid) and not brawler.isPaused then
                        -- debugPrint(brawler.displayName, "Player or ally", brawlerUuid, M.Osi.GetHitpoints(brawlerUuid))
                        if State.Session.Players[brawlerUuid] and (isPlayerControllingDirectly(brawlerUuid) and not State.Settings.FullAuto) then
                            debugPrint(brawler.displayName, "Player is controlling directly: do not take action!")
                            -- debugDump(brawler)
                            stopPulseAction(brawler, true)
                        else
                            if not brawler.isInBrawl then
                                if M.Osi.IsPlayer(brawlerUuid) == 0 or State.Settings.CompanionAIEnabled then
                                    debugPrint(brawler.displayName, "Not in brawl, starting pulse action for")
                                    startPulseAction(brawler)
                                end
                            elseif M.Utils.isBrawlingWithValidTarget(brawler) and M.Osi.IsPlayer(brawlerUuid) == 1 and State.Settings.CompanionAIEnabled then
                                Movement.holdPosition(brawlerUuid)
                                -- Movement.repositionRelativeToTarget(brawlerUuid, brawler.targetUuid)
                            end
                        end
                    end
                elseif M.Osi.IsDead(brawlerUuid) == 1 or M.Utils.isDowned(brawlerUuid) then
                    clearOsirisQueue(brawlerUuid)
                    Osi.LieOnGround(brawlerUuid)
                end
            end
        end
    end
end

local function pulseAddNearby(uuid)
    Roster.addNearbyEnemiesToBrawlers(uuid, 30)
end

return {
    actOnHostileTarget = actOnHostileTarget,
    actOnFriendlyTarget = actOnFriendlyTarget,
    findTarget = findTarget,
    act = act,
    pulseAction = pulseAction,
    pulseReposition = pulseReposition,
    pulseAddNearby = pulseAddNearby,
}
