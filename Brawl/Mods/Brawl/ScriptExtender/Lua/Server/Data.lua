-- Constants
DEBUG_LOGGING = false
REPOSITION_INTERVAL = 2500
BRAWL_FIZZLER_TIMEOUT = 30000 -- if 30 seconds elapse with no attacks or pauses, end the brawl
LIE_ON_GROUND_TIMEOUT = 3500
MOD_STATUS_MESSAGE_DURATION = 2000
ENTER_COMBAT_RANGE = 20
NEARBY_RADIUS = 35
MELEE_RANGE = 1.5
RANGED_RANGE_MAX = 25
RANGED_RANGE_SWEETSPOT = 10
RANGED_RANGE_MIN = 10
HELP_DOWNED_MAX_RANGE = 20
MUST_BE_AN_ERROR_MAX_DISTANCE_FROM_PLAYER = 100
-- AI_TARGET_CONCENTRATION_WEIGHT_MULTIPLIER = 3
DEFENSE_TACTICS_MAX_DISTANCE = 15
MOVEMENT_DISTANCE_UUID = "d6b2369d-84f0-4ca4-a3a7-62d2d192a185"
LOOPING_COMBAT_ANIMATION_ID = "7bb52cd4-0b1c-4926-9165-fa92b75876a3" -- monk animation, should prob be a lookup?
ACTION_RESOURCES = {
    ActionPoint = "734cbcfb-8922-4b6d-8330-b2a7e4c14b6a",
    BonusActionPoint = "420c8df5-45c2-4253-93c2-7ec44e127930",
    ReactionActionPoint = "45ff0f48-b210-4024-972f-b64a44dc6985",
    SpellSlot = "d136c5d9-0ff0-43da-acce-a74a07f8d6bf",
    ChannelDivinity = "028304ef-e4b7-4dfb-a7ec-cd87865cdb16",
    ChannelOath = "c0503ecf-c3cd-4719-9cfd-05460a1db95a",
    KiPoint = "46d3d228-04e0-4a43-9a2e-78137e858c14",
    DeflectMissiles_Charge = "2b8021f4-99ac-42d4-87ce-96a7c5505aee",
    SneakAttack_Charge = "1531b6ec-4ba8-4b0d-8411-422d8f51855f",
    Movement = "d6b2369d-84f0-4ca4-a3a7-62d2d192a185",
}
PLAYER_ARCHETYPES = {"", "melee", "mage", "ranged", "healer", "healer_melee", "melee_magic"}
COMPANION_TACTICS = {"Offense", "Defense"}
ALL_SPELL_TYPES = {"Buff", "Debuff", "Control", "Damage", "Healing", "Summon", "Utility"}
ARCHETYPE_WEIGHTS = {
    mage = {
        rangedWeapon = -5,
        rangedWeaponInRange = 5,
        rangedWeaponOutOfRange = -5,
        meleeWeapon = -5,
        meleeWeaponInRange = 5,
        isSpell = 10,
        spellInRange = 10,
    },
    ranged = {
        rangedWeapon = 10,
        rangedWeaponInRange = 10,
        rangedWeaponOutOfRange = 5,
        meleeWeapon = -2,
        meleeWeaponInRange = 5,
        isSpell = -5,
        spellInRange = 5,
    },
    healer_melee = {
        rangedWeapon = -5,
        rangedWeaponInRange = 5,
        rangedWeaponOutOfRange = -5,
        meleeWeapon = 2,
        meleeWeaponInRange = 8,
        isSpell = 4,
        spellInRange = 8,
    },
    healer = {
        rangedWeapon = 3,
        rangedWeaponInRange = 3,
        rangedWeaponOutOfRange = 3,
        meleeWeapon = -2,
        meleeWeaponInRange = 4,
        isSpell = 8,
        spellInRange = 8,
    },
    melee = {
        rangedWeapon = -5,
        rangedWeaponInRange = 5,
        rangedWeaponOutOfRange = -5,
        meleeWeapon = 5,
        meleeWeaponInRange = 10,
        isSpell = -10,
        spellInRange = 5,
    },
    melee_magic = {
        rangedWeapon = -5,
        rangedWeaponInRange = 5,
        rangedWeaponOutOfRange = -5,
        meleeWeapon = 5,
        meleeWeaponInRange = 10,
        isSpell = 5,
        spellInRange = 5,
    },
}
ARCHETYPE_WEIGHTS.beast = ARCHETYPE_WEIGHTS.melee
ARCHETYPE_WEIGHTS.goblin_melee = ARCHETYPE_WEIGHTS.melee
ARCHETYPE_WEIGHTS.goblin_ranged = ARCHETYPE_WEIGHTS.ranged
ARCHETYPE_WEIGHTS.mage = ARCHETYPE_WEIGHTS.mage
ARCHETYPE_WEIGHTS.koboldinventor_drunk = ARCHETYPE_WEIGHTS.melee
ARCHETYPE_WEIGHTS.ranged_stupid = ARCHETYPE_WEIGHTS.ranged
ARCHETYPE_WEIGHTS.melee_magic_smart = ARCHETYPE_WEIGHTS.melee_magic
ARCHETYPE_WEIGHTS.merregon = ARCHETYPE_WEIGHTS.melee
ARCHETYPE_WEIGHTS.act3_LOW_ghost_nurse = ARCHETYPE_WEIGHTS.melee
ARCHETYPE_WEIGHTS.ogre_melee = ARCHETYPE_WEIGHTS.melee
ARCHETYPE_WEIGHTS.beholder = ARCHETYPE_WEIGHTS.melee_magic
ARCHETYPE_WEIGHTS.minotaur = ARCHETYPE_WEIGHTS.melee
ARCHETYPE_WEIGHTS.steel_watcher_biped = ARCHETYPE_WEIGHTS.melee
DAMAGE_TYPES = {
    Slashing = 2,
    Piercing = 3,
    Bludgeoning = 4,
    Acid = 5,
    Thunder = 6,
    Necrotic = 7,
    Fire = 8,
    Lightning = 9,
    Cold = 10,
    Psychic = 11,
    Poison = 12,
    Radiant = 13,
    Force = 14,
}
-- NB: Is "Dash" different from "Sprint"?
PLAYER_MOVEMENT_SPEED_DEFAULT = {Dash = 6.0, Sprint = 6.0, Run = 3.75, Walk = 2.0, Stroll = 1.4}
MOVEMENT_SPEED_THRESHOLDS = {
    HONOUR = {Sprint = 5, Run = 2, Walk = 1},
    HARD = {Sprint = 6, Run = 4, Walk = 2},
    MEDIUM = {Sprint = 8, Run = 5, Walk = 3},
    EASY = {Sprint = 12, Run = 9, Walk = 6},
}
ACTION_BUTTON_TO_SLOT = {0, 2, 4, 6, 8, 10, 12, 14, 16}
SAFE_AOE_SPELLS = {
    "Target_Volley",
    "Shout_Whirlwind",
    "Shout_DestructiveWave",
    "Shout_DestructiveWave_Radiant",
    "Shout_DestructiveWave_Necrotic",
    "Shout_DivineIntervention_Attack",
    "Shout_SpiritGuardians",
    "Target_GuardianOfFaith",
}

-- Session state
SpellTable = {}
Listeners = {}
Brawlers = {}
Players = {}
PulseAddNearbyTimers = {}
PulseRepositionTimers = {}
PulseActionTimers = {}
BrawlFizzler = {}
IsAttackingOrBeingAttackedByPlayer = {}
ClosestEnemyBrawlers = {}
PlayerMarkedTarget = {}
PlayerCurrentTarget = {}
ActionsInProgress = {}
MovementQueue = {}
PartyMembersHitpointsListeners = {}
ActionResourcesListeners = {}
TurnBasedListeners = {}
SpellCastMovementListeners = {}
FTBLockedIn = {}
LastClickPosition = {}
ActiveCombatGroups = {}
AwaitingTarget = {}
HealRequested = {}
HealRequestedTimer = {}
ToTTimer = nil
ToTRoundTimer = nil
FinalToTChargeTimer = nil
ModStatusMessageTimer = nil
MovementSpeedThresholds = MOVEMENT_SPEED_THRESHOLDS.EASY

-- Persistent state
Ext.Vars.RegisterModVariable(ModuleUUID, "SpellRequirements", {Server = true, Client = false, SyncToClient = false})
Ext.Vars.RegisterModVariable(ModuleUUID, "ModifiedHitpoints", {Server = true, Client = false, SyncToClient = false})
Ext.Vars.RegisterModVariable(ModuleUUID, "PartyArchetypes", {Server = true, Client = false, SyncToClient = false})

local function hasTargetCondition(targetConditionString, condition)
    local parts = {}
    for part in targetConditionString:gmatch("%S+") do
        table.insert(parts, part)
    end
    for i, p in ipairs(parts) do
        if p == condition then
            if i == 1 or parts[i - 1] ~= "not" then
                return true
            end
        end
    end
    return false
end

local function isSafeAoESpell(spellName)
    for _, safeAoESpell in ipairs(SAFE_AOE_SPELLS) do
        if spellName == safeAoESpell then
            return true
        end
    end
    return false
end

local function getSpellInfo(spellType, spellName)
    local spell = Ext.Stats.Get(spellName)
    if spell and spell.VerbalIntent == spellType then
        local useCosts = split(spell.UseCosts, ";")
        local costs = {
            ShortRest = spell.Cooldown == "OncePerShortRest" or spell.Cooldown == "OncePerShortRestPerItem",
            LongRest = spell.Cooldown == "OncePerRest" or spell.Cooldown == "OncePerRestPerItem",
        }
        -- local hitCost = nil -- divine smite only..?
        for _, useCost in ipairs(useCosts) do
            local useCostTable = split(useCost, ":")
            local useCostLabel = useCostTable[1]
            local useCostAmount = tonumber(useCostTable[#useCostTable])
            if useCostLabel == "SpellSlotsGroup" then
                -- e.g. SpellSlotsGroup:1:1:2
                -- NB: what are the first two numbers?
                costs.SpellSlot = useCostAmount
            else
                costs[useCostLabel] = useCostAmount
            end
        end
        local outOfCombatOnly = false
        for _, req in ipairs(spell.Requirements) do
            if req.Requirement == "Combat" and req.Not == true then
                outOfCombatOnly = true
            end
        end
        local hasVerbalComponent = false
        for _, flag in ipairs(spell.SpellFlags) do
            if flag == "HasVerbalComponent" then
                hasVerbalComponent = true
            end
        end
        local spellInfo = {
            level = spell.Level,
            areaRadius = spell.AreaRadius,
            isSelfOnly = hasTargetCondition(spell.TargetConditions, "Self()"),
            isCharacterOnly = hasTargetCondition(spell.TargetConditions, "Character()"),
            outOfCombatOnly = outOfCombatOnly,
            -- damageType = spell.DamageType,
            isSpell = spell.SpellSchool ~= "None",
            isEvocation = spell.SpellSchool == "Evocation",
            isSafeAoE = isSafeAoESpell(spellName),
            targetRadius = spell.TargetRadius,
            costs = costs,
            type = spellType,
            hasVerbalComponent = hasVerbalComponent,
            -- need to parse this, e.g. DealDamage(LevelMapValue(D8Cantrip),Cold), DealDamage(8d6,Fire), etc
            -- damage = spell.TooltipDamageList,
        }
        if spellType == "Healing" then
            spellInfo.isDirectHeal = false
            local spellProperties = spell.SpellProperties
            if spellProperties then
                for _, spellProperty in ipairs(spellProperties) do
                    local functors = spellProperty.Functors
                    if functors then
                        for _, functor in ipairs(functors) do
                            if functor.TypeId == "RegainHitPoints" then
                                spellInfo.isDirectHeal = true
                            end
                        end
                    end
                end
            end
        end
        return spellInfo
    end
    return nil
end

local function getAllSpellsOfType(spellType)
    local allSpellsOfType = {}
    for _, spellName in ipairs(Ext.Stats.GetStats("SpellData")) do
        local spell = Ext.Stats.Get(spellName)
        if spell and spell.VerbalIntent == spellType then
            if spell.ContainerSpells and spell.ContainerSpells ~= "" then
                local containerSpellNames = split(spell.ContainerSpells, ";")
                for _, containerSpellName in ipairs(containerSpellNames) do
                    allSpellsOfType[containerSpellName] = getSpellInfo(spellType, containerSpellName)
                end
            else
                allSpellsOfType[spellName] = getSpellInfo(spellType, spellName)
                if spell.Requirements and #spell.Requirements ~= 0 then
                    local requirements = spell.Requirements
                    local removeIndex = 0
                    for i, req in ipairs(requirements) do
                        if req.Requirement == "Combat" and req.Not == false then
                            removeIndex = i
                            local removedReq = {Requirement = req.Requirement, Param = req.Param, Not = req.Not, index = i}
                            local modVars = Ext.Vars.GetModVariables(ModuleUUID)
                            modVars.SpellRequirements = modVars.SpellRequirements or {}
                            modVars.SpellRequirements[spellName] = removedReq
                            break
                        end
                    end
                    if removeIndex ~= 0 then
                        table.remove(requirements, removeIndex)
                    end
                    spell.Requirements = requirements
                    spell:Sync()
                end
            end
        end
    end
    return allSpellsOfType
end

function buildSpellTable()
    local spellTable = {}
    for _, spellType in pairs(ALL_SPELL_TYPES) do
        spellTable[spellType] = getAllSpellsOfType(spellType)
    end
    return spellTable
end

function resetSpellData()
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    if modVars and modVars.SpellRequirements then
        local spellReqs = modVars.SpellRequirements
        for spellName, req in pairs(spellReqs) do
            local spell = Ext.Stats.Get(spellName)
            if spell then
                local requirements = spell.Requirements
                table.insert(requirements, {Requirement = req.Requirement, Param = req.Param, Not = req.Not})
                spell.Requirements = requirements
                spell:Sync()
            end
        end
        modVars.SpellRequirements = nil
    end
end

function revertHitpoints(entityUuid)
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    local modifiedHitpoints = modVars.ModifiedHitpoints
    if modifiedHitpoints and modifiedHitpoints[entityUuid] ~= nil and Osi.IsCharacter(entityUuid) == 1 then
        -- debugPrint("Reverting hitpoints", entityUuid)
        -- debugDump(modifiedHitpoints[entityUuid])
        local entity = Ext.Entity.Get(entityUuid)
        local currentMaxHp = entity.Health.MaxHp
        local currentHp = entity.Health.Hp
        local multiplier = modifiedHitpoints[entityUuid].multiplier or HitpointsMultiplier
        if modifiedHitpoints[entityUuid] == nil then
            modifiedHitpoints[entityUuid] = {}
        end
        modifiedHitpoints[entityUuid].updating = true
        modVars.ModifiedHitpoints = modifiedHitpoints
        entity.Health.MaxHp = math.floor(currentMaxHp/multiplier + 0.5)
        entity.Health.Hp = math.floor(currentHp/multiplier + 0.5)
        entity:Replicate("Health")
        modifiedHitpoints[entityUuid] = nil
        modVars.ModifiedHitpoints = modifiedHitpoints
        -- debugPrint("Reverted hitpoints:", entityUuid, getDisplayName(entityUuid), entity.Health.MaxHp, entity.Health.Hp)
    end
end

function modifyHitpoints(entityUuid)
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    if modVars.ModifiedHitpoints == nil then
        modVars.ModifiedHitpoints = {}
    end
    local modifiedHitpoints = modVars.ModifiedHitpoints
    if Osi.IsCharacter(entityUuid) == 1 and Osi.IsDead(entityUuid) == 0 and modifiedHitpoints[entityUuid] == nil then
        -- debugPrint("modify hitpoints", entityUuid, HitpointsMultiplier)
        local entity = Ext.Entity.Get(entityUuid)
        local originalMaxHp = entity.Health.MaxHp
        local originalHp = entity.Health.Hp
        if modifiedHitpoints[entityUuid] == nil then
            modifiedHitpoints[entityUuid] = {}
        end
        modifiedHitpoints[entityUuid].updating = true
        modVars.ModifiedHitpoints = modifiedHitpoints
        entity.Health.MaxHp = math.floor(originalMaxHp*HitpointsMultiplier + 0.5)
        entity.Health.Hp = math.floor(originalHp*HitpointsMultiplier + 0.5)
        entity:Replicate("Health")
        modifiedHitpoints = Ext.Vars.GetModVariables(ModuleUUID).ModifiedHitpoints
        modifiedHitpoints[entityUuid].maxHp = entity.Health.MaxHp
        modifiedHitpoints[entityUuid].multiplier = HitpointsMultiplier
        modVars.ModifiedHitpoints = modifiedHitpoints
        -- debugPrint("Modified hitpoints:", entityUuid, getDisplayName(entityUuid), originalMaxHp, originalHp, entity.Health.MaxHp, entity.Health.Hp)
    end
end

function setupPartyMembersHitpoints()
    for _, partyMember in ipairs(Osi.DB_PartyMembers:Get(nil)) do
        local partyMemberUuid = Osi.GetUUID(partyMember[1])
        revertHitpoints(partyMemberUuid)
        modifyHitpoints(partyMemberUuid)
        if PartyMembersHitpointsListeners[partyMemberUuid] ~= nil then
            Ext.Entity.Unsubscribe(PartyMembersHitpointsListeners[partyMemberUuid])
        end
        PartyMembersHitpointsListeners[partyMemberUuid] = Ext.Entity.Subscribe("Health", function (entity, _, _)
            local uuid = entity.Uuid.EntityUuid
            -- debugPrint("Health changed", uuid)
            local modVars = Ext.Vars.GetModVariables(ModuleUUID)
            local modifiedHitpoints = modVars.ModifiedHitpoints
            if modifiedHitpoints and modifiedHitpoints[uuid] ~= nil and modifiedHitpoints[uuid].maxHp ~= entity.Health.MaxHp then
                debugDump(modifiedHitpoints[uuid])
                if modifiedHitpoints[uuid].updating == false then
                    -- External change detected; re-apply modifications
                    -- debugPrint("External MaxHp change detected for", uuid, ". Re-applying hitpoint modifications.")
                    modifiedHitpoints[uuid] = nil
                    modVars.ModifiedHitpoints = modifiedHitpoints
                    modifyHitpoints(uuid)
                end
            end
            modVars = Ext.Vars.GetModVariables(ModuleUUID)
            modifiedHitpoints = modVars.ModifiedHitpoints
            modifiedHitpoints[uuid] = modifiedHitpoints[uuid] or {}
            modifiedHitpoints[uuid].updating = false
            modVars.ModifiedHitpoints = modifiedHitpoints
        end, Ext.Entity.Get(partyMemberUuid))
    end
end

function revertAllModifiedHitpoints()
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    if modVars.ModifiedHitpoints and next(modVars.ModifiedHitpoints) ~= nil then
        for uuid, _ in pairs(modVars.ModifiedHitpoints) do
            revertHitpoints(uuid)
        end
    end
    for _, listener in pairs(PartyMembersHitpointsListeners) do
        Ext.Entity.Unsubscribe(listener)
    end
end

function resetPlayersMovementSpeed()
    for playerUuid, player in pairs(Players) do
        local entity = Ext.Entity.Get(playerUuid)
        if player.movementSpeedRun ~= nil and entity and entity.ServerCharacter then
            entity.ServerCharacter.Template.MovementSpeedRun = player.movementSpeedRun
            player.movementSpeedRun = nil
        end
    end
end
