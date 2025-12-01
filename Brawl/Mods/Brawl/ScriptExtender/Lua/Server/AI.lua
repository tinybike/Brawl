local debugPrint = Utils.debugPrint
local debugDump = Utils.debugDump

local function actOnHostileTarget(brawler, target, bonusActionOnly, excludedSpells, onSubmitted, onCompleted, onFailed)
    local distanceToTarget = M.Osi.GetDistanceTo(brawler.uuid, target.uuid)
    if not brawler or not target then
        return onFailed("brawler/target not found")
    end
    local actionToTake = nil
    local spellTypes = {"Control", "Damage"}
    local preparedSpells = Ext.Entity.Get(brawler.uuid).SpellBookPrepares.PreparedSpells
    local damageAmountNeeded = M.Osi.GetHitpoints(target.uuid)
    if M.Osi.IsPlayer(brawler.uuid) == 1 then
        local allowAoE = M.Osi.HasPassive(brawler.uuid, "SculptSpells") == 1
        local playerClosestToTarget = M.Osi.GetClosestAlivePlayer(target.uuid) or brawler.uuid
        local targetDistanceToParty = M.Osi.GetDistanceTo(target.uuid, playerClosestToTarget)
        -- debugPrint("target distance to party", targetDistanceToParty, playerClosestToTarget)
        actionToTake = Pick.decideCompanionActionOnTarget(brawler, target.uuid, preparedSpells, excludedSpells, distanceToTarget, {"Damage"}, damageAmountNeeded, targetDistanceToParty, allowAoE, bonusActionOnly)
        debugPrint(brawler.displayName, "Companion action to take on hostile target", actionToTake, brawler.uuid, target.uuid, target.displayName, bonusActionOnly)
    else
        actionToTake = Pick.decideActionOnTarget(brawler, target.uuid, preparedSpells, excludedSpells, distanceToTarget, spellTypes, damageAmountNeeded, bonusActionOnly)
        debugPrint(brawler.displayName, "Action to take on hostile target", actionToTake, brawler.uuid, target.uuid, target.displayName, brawler.archetype, bonusActionOnly)
    end
    if not actionToTake then
        debugPrint("***No hostile actions available for", brawler.uuid, brawler.displayName, bonusActionOnly)
        return onFailed("no hostile actions found")
    end
    if not Pick.checkConditions({caster = brawler.uuid, target = target.uuid}, M.Spells.getSpellByName(actionToTake)) then
        excludedSpells = excludedSpells or {}
        debugPrint(brawler.displayName, "checkConditions failed, exlcuding", actionToTake, #excludedSpells)
        table.insert(excludedSpells, actionToTake)
        if #excludedSpells > Constants.MAX_SPELL_EXCLUSIONS then
            return onFailed("too many exclusions")
        end
        return actOnHostileTarget(brawler, target, bonusActionOnly, excludedSpells, onSubmitted, onCompleted, onFailed)
    end
    brawler.targetUuid = target.uuid -- or in onSubmitted?
    Movement.moveIntoPositionForSpell(brawler.uuid, target.uuid, actionToTake, bonusActionOnly, function ()
        debugPrint(brawler.displayName, "movement completed (hostile)", target.displayName, actionToTake)
        local targetUuid = M.Spells.isShout(actionToTake) and brawler.uuid or target.uuid
        Actions.useSpellOnTarget(brawler.uuid, targetUuid, actionToTake, false, onSubmitted, function ()
            debugPrint(brawler.displayName, "complete (hostile)", bonusActionOnly)
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
    local healingAmountNeeded = M.Osi.GetMaxHitpoints(target.uuid) - M.Osi.GetHitpoints(target.uuid)
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
        actionToTake = Pick.decideCompanionActionOnTarget(brawler, target.uuid, preparedSpells, excludedSpells, distanceToTarget, spellTypes, healingAmountNeeded, 0, true, bonusActionOnly)
    else
        actionToTake = Pick.decideActionOnTarget(brawler, target.uuid, preparedSpells, excludedSpells, distanceToTarget, spellTypes, healingAmountNeeded, bonusActionOnly)
    end
    debugPrint(brawler.displayName, "Action to take on friendly target", actionToTake, brawler.uuid, bonusActionOnly)
    if not actionToTake then
        debugPrint(brawler.displayName, "No friendly actions available for", brawler.uuid, bonusActionOnly)
        return onFailed("no friendly actions available")
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
        local targetUuid = M.Spells.isShout(actionToTake) and brawler.uuid or target.uuid
        Actions.useSpellOnTarget(brawler.uuid, targetUuid, actionToTake, true, onSubmitted, onCompleted, onFailed)
    end, onFailed)
end

local function findTarget(brawler, bonusActionOnly, onSubmitted, onCompleted, onFailed)
    local brawlers = M.Roster.getBrawlers()
    if brawlers and next(brawlers) then
        local userId
        local wasHealRequested = false
        if M.Osi.IsPlayer(brawler.uuid) == 1 then
            userId = Osi.GetReservedUserID(brawler.uuid)
            wasHealRequested = State.Session.HealRequested[userId]
        end
        if wasHealRequested then
            local friendlyTargetUuid = M.Pick.whoNeedsHealing(brawler.uuid)
            if friendlyTargetUuid and brawlers[friendlyTargetUuid] then
                debugPrint(brawler.displayName, "actOnFriendlyTarget", brawler.uuid, friendlyTargetUuid, M.Utils.getDisplayName(friendlyTargetUuid), bonusActionOnly)
                return actOnFriendlyTarget(brawler, brawlers[friendlyTargetUuid], bonusActionOnly, nil, function (request)
                    State.Session.HealRequested[userId] = false
                    onSubmitted(request)
                end, onFailed)
            end
        end
        local weightedTargets = M.Pick.getWeightedTargets(brawler, brawlers, bonusActionOnly, M.Pick.whoNeedsHealing(brawler.uuid))
        debugDump(weightedTargets)
        local targetUuid = M.Pick.decideOnTarget(weightedTargets)
        if targetUuid then
            local targetBrawler = brawlers[targetUuid]
            if targetBrawler then
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
        debugPrint("check for", brawler.uuid, brawler.displayName)
        RT.Timers.startPulseAction(brawler)
    end
end

local function act(brawler, bonusActionOnly, onSubmitted, onCompleted, onFailed)
    onSubmitted = onSubmitted or Utils.noop
    onCompleted = onCompleted or Utils.noop
    onFailed = onFailed or Utils.noop
    if not brawler or not brawler.uuid or not Utils.canAct(brawler.uuid) then
        return onFailed("can't act or brawler not found")
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
    -- Aura check for Paladins: auras should always be on, if available
    if Pick.shouldUseAuras(brawler.uuid, brawler.auras) then
        return Actions.startAuras(brawler.uuid, brawler.auras, onSubmitted, onCompleted, onFailed)
    end
    -- Doesn't currently have an attack target, so let's find one
    if brawler.targetUuid == nil then
        debugPrint(brawler.displayName, "Find target (no current target)", brawler.uuid, bonusActionOnly)
        return findTarget(brawler, bonusActionOnly, onSubmitted, onCompleted, onFailed)
    end
    -- We have a target and the target is alive
    local brawlers = M.Roster.getBrawlers()
    if brawlers[brawler.targetUuid] and M.Utils.isAliveAndCanFight(brawler.targetUuid) and M.Utils.isVisible(brawler.uuid, brawler.targetUuid) then
        local target = brawlers[brawler.targetUuid]
        if not State.Settings.TurnBasedSwarmMode or M.Movement.findPathToTargetUuid(brawler.uuid, brawler.targetUuid) then
            if brawler.lockedOnTarget and M.Utils.isValidHostileTarget(brawler.uuid, brawler.targetUuid) then
                debugPrint(brawler.displayName, "Locked-on target, attacking", M.Utils.getDisplayName(brawler.targetUuid), bonusActionOnly)
                return actOnHostileTarget(brawler, target, bonusActionOnly, nil, onSubmitted, onCompleted, onFailed)
            end
            if M.Utils.isPlayerOrAlly(brawler.uuid) and State.Settings.CompanionTactics == "Defense" then
                debugPrint(brawler.displayName, "Find target (defense tactics)", brawler.uuid, bonusActionOnly)
                return findTarget(brawler, bonusActionOnly, onSubmitted, onCompleted, onFailed)
            end
            if M.Utils.isValidHostileTarget(brawler.uuid, brawler.targetUuid) and M.Osi.GetDistanceTo(brawler.uuid, brawler.targetUuid) <= M.Utils.getTrackingDistance() then
                debugPrint(brawler.displayName, "Remaining on target, attacking", M.Utils.getDisplayName(brawler.targetUuid), bonusActionOnly)
                return actOnHostileTarget(brawler, target, bonusActionOnly, nil, onSubmitted, onCompleted, onFailed)
            end
        end
    end
    -- Has an attack target but it's already dead or unable to fight, so find a new one
    debugPrint(brawler.displayName, "Find target (current target invalid)", brawler.uuid, bonusActionOnly)
    brawler.targetUuid = nil
    return findTarget(brawler, bonusActionOnly, onSubmitted, onCompleted, onFailed)
end

return {
    actOnHostileTarget = actOnHostileTarget,
    actOnFriendlyTarget = actOnFriendlyTarget,
    findTarget = findTarget,
    act = act,
}
