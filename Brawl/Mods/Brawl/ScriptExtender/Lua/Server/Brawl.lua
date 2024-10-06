-- MCM Settings
local ModEnabled = true
local CompanionAIEnabled = true
local AutoPauseOnDowned = true
local ActionInterval = 6000
if MCM then
    ModEnabled = MCM.Get("mod_enabled")
    CompanionAIEnabled = MCM.Get("companion_ai_enabled")
    AutoPauseOnDowned = MCM.Get("auto_pause_on_downed")
    ActionInterval = MCM.Get("action_interval")
    print("MCM action interval setting", ActionInterval)
end

-- Constants
local DEBUG_LOGGING = false
local REPOSITION_INTERVAL = 2500
local BRAWL_FIZZLER_TIMEOUT = 15000 -- if 10 seconds elapse with no attacks or pauses, end the brawl
local LIE_ON_GROUND_TIMEOUT = 3500
local ENTER_COMBAT_RANGE = 20
local NEARBY_RADIUS = 35
local MELEE_RANGE = 1.5
local RANGED_RANGE_MAX = 25
local RANGED_RANGE_SWEETSPOT = 10
local RANGED_RANGE_MIN = 10
local HELP_DOWNED_MAX_RANGE = 20
local MAX_COMPANION_DISTANCE_FROM_PLAYER = 20
local MUST_BE_AN_ERROR_MAX_DISTANCE_FROM_PLAYER = 100
local AI_HEALTH_PERCENTAGE_HEALING_THRESHOLD = 20.0
local AI_TARGET_CONCENTRATION_WEIGHT_MULTIPLIER = 3
local HITPOINTS_MULTIPLIER = 3
local MOVEMENT_DISTANCE_UUID = "d6b2369d-84f0-4ca4-a3a7-62d2d192a185"
local LOOPING_COMBAT_ANIMATION_ID = "7bb52cd4-0b1c-4926-9165-fa92b75876a3" -- monk animation, should prob be a lookup?
-- Spell list from https://fearlessrevolution.com/viewtopic.php?t=13996&start=3420
-- NB: doesn't include spells from mods, find a way to look those up at runtime?
local ALL_SPELLS = {
    "Projectile_MainHandAttack",
    "Projectile_OffhandAttack",
    "Target_MainHandAttack",
    "Target_OffhandAttack",
    "Target_Topple",
    "Target_UnarmedAttack",
    "Target_AdvancedMeleeWeaponAction",
    "Target_Charger_Attack",
    "Target_Charger_Push",
    "Target_CripplingStrike",
    "Target_DisarmingStrike",
    "Target_Flurry",
    "Target_LungingAttack",
    "Target_OpeningAttack",
    "Target_PiercingThrust",
    "Target_PommelStrike",
    "Target_Riposte",
    "Target_Shove",
    "Target_Slash",
    "Target_Smash",
    "Target_ThornWhip",
    "Target_FlurryOfBlows",
    "Target_StunningStrike",
    "Rush_Rush",
    "Rush_WEAPON_ACTION_RUSH",
    "Rush_Aggressive",
    "Rush_ForceTunnel",
    "Projectile_AcidArrow",
    "Projectile_AcidSplash",
    "Projectile_C",
    "Projectile_ChainLightning",
    "Projectile_ChromaticOrb",
    "Projectile_DisarmingAttack",
    "Projectile_Disintegrate",
    "Projectile_EldritchBlast",
    "Projectile_EnsnaringStrike_Container",
    "Projectile_FireBolt",
    "Projectile_Fireball",
    "Projectile_GuidingBolt",
    "Projectile_HailOfThorns",
    "Projectile_HordeBreaker",
    "Projectile_IceKnife",
    "Projectile_LightningArrow",
    "Projectile_MagicMissile",
    "Projectile_MenacingAttack",
    "Projectile_PoisonSpray",
    "Projectile_PushingAttack",
    "Projectile_RayOfEnfeeblement",
    "Projectile_RayOfFrost",
    "Projectile_RayOfSickness",
    "Projectile_ScorchingRay",
    "Projectile_SneakAttack",
    "Projectile_TripAttack",
    "Projectile_WitchBolt",
    "Shout_ActionSurge",
    "Shout_Aid",
    "Shout_ArcaneRecovery",
    "Shout_ArmorOfAgathys",
    "Shout_ArmsOfHadar",
    "Shout_AuraOfVitality",
    "Shout_BeaconOfHope",
    "Shout_BladeWard",
    "Shout_Blink",
    "Shout_Blur",
    "Shout_CreateSorceryPoints",
    "Shout_CreateSpellSlot",
    "Shout_CrusadersMantle",
    "Shout_Dash_CunningAction",
    "Shout_DestructiveWave",
    "Shout_DetectThoughts",
    "Shout_Disengage_CunningAction",
    "Shout_DisguiseSelf",
    "Shout_DispelEvilAndGood",
    "Shout_DivineFavor",
    "Shout_DivineSense",
    "Shout_Dreadful_Aspect",
    "Shout_ExpeditiousRetreat",
    "Shout_FalseLife",
    "Shout_FeatherFall",
    "Shout_FireShield",
    "Shout_FlameBlade",
    "Shout_FlameBlade_MephistophelesTiefling",
    "Shout_HealingRadiance",
    "Shout_HealingWord_Mass",
    "Shout_HellishRebuke",
    "Shout_HellishRebuke_AsmodeusTiefling",
    "Shout_HellishRebuke_WarlockMI",
    "Shout_HeroesFeast",
    "Shout_Hide_BonusAction",
    "Shout_MirrorImage",
    "Shout_NaturalRecovery",
    "Shout_PassWithoutTrace",
    "Shout_PrayerOfHealing",
    "Shout_ProduceFlame",
    "Shout_RadianceOfTheDawn",
    "Shout_SacredWeapon",
    "Shout_SecondWind",
    "Shout_SeeInvisibility",
    "Shout_Shield_Sorcerer",
    "Shout_Shield_Wizard",
    "Shout_Shillelagh",
    "Shout_SongOfRest",
    "Shout_SpeakWithAnimals",
    "Shout_SpeakWithAnimals_Barbarian",
    "Shout_SpeakWithAnimals_ForestGnome",
    "Shout_SpiritGuardians",
    "Shout_Thaumaturgy",
    "Shout_TurnTheFaithless",
    "Shout_TurnTheUnholy",
    "Shout_TurnUndead",
    "Shout_WildShape",
    "Shout_WildShape_Badger",
    "Shout_WildShape_Cat",
    "Shout_WildShape_Combat",
    "Shout_WildShape_Combat_Badger",
    "Shout_WildShape_Combat_Bear_Polar",
    "Shout_WildShape_Combat_Cat",
    "Shout_WildShape_Combat_DeepRothe",
    "Shout_WildShape_Combat_Raven",
    "Shout_WildShape_Combat_Spider",
    "Shout_WildShape_Combat_Wolf_Dire",
    "Shout_WildShape_DeepRothe",
    "Shout_WildShape_Spider",
    "Shout_WildShape_Wolf_Dire",
    "Shout_WindWalk",
    "Target_AnimalFriendship",
    "Target_AnimateDead",
    "Target_ArcaneEye",
    "Target_ArcaneLock",
    "Target_Bane",
    "Target_Banishment",
    "Target_Barkskin",
    "Target_BestowCurse",
    "Target_BlackTentacles",
    "Target_Bless",
    "Target_BlessingOfTheTrickster",
    "Target_Blight",
    "Target_Blindness",
    "Target_CallLightning",
    "Target_CalmEmotions",
    "Target_CharmPerson",
    "Target_ChillTouch",
    "Target_CircleOfDeath",
    "Target_CloudOfDaggers",
    "Target_Cloudkill",
    "Target_Command_Container",
    "Target_CompelledDuel",
    "Target_Confusion",
    "Target_ConjureElemental_Container",
    "Target_ConjureElementals_Minor_Container",
    "Target_ConjureWoodlandBeings",
    "Target_Contagion",
    "Target_ControlUndead",
    "Target_Counterspell",
    "Target_CreateDestroyWater",
    "Target_CreateUndead",
    "Target_CrownOfMadness",
    "Target_CureWounds",
    "Target_CureWounds_Mass",
    "Target_CuttingWords",
    "Target_DancingLights",
    "Target_Darkness",
    "Target_Darkness_DrowMagic",
    "Target_Darkvision",
    "Target_Daylight_Container",
    "Target_DeathWard",
    "Target_DisarmingAttack",
    "Target_DissonantWhispers",
    "Target_DominateBeast",
    "Target_DominatePerson",
    "Target_ElementalWeapon",
    "Target_EnhanceAbility",
    "Target_EnlargeReduce",
    "Target_Entangle",
    "Target_Enthrall",
    "Target_Eyebite",
    "Target_FaerieFire",
    "Target_FaerieFire_DrowMagic",
    "Target_FeignDeath",
    "Target_FindFamiliar",
    "Target_FlameStrike",
    "Target_FlamingSphere",
    "Target_FleshToStone",
    "Target_Fly",
    "Target_FogCloud",
    "Target_FreedomOfMovement",
    "Target_FrenziedStrike",
    "Target_Friends",
    "Target_GaseousForm",
    "Target_GlobeOfInvulnerability",
    "Target_GlyphOfWarding",
    "Target_Goodberry",
    "Target_GraspingVine",
    "Target_Grease",
    "Target_GreaterRestoration",
    "Target_GuardianOfFaith",
    "Target_Guidance",
    "Target_Harm",
    "Target_Haste",
    "Target_Heal",
    "Target_HealingWord",
    "Target_HeatMetal",
    "Target_Heroism",
    "Target_Hex",
    "Target_HideousLaughter",
    "Target_HoldMonster",
    "Target_HoldPerson",
    "Target_HolyRebuke",
    "Target_HordeBreaker",
    "Target_HungerOfHadar",
    "Target_HuntersMark",
    "Target_HypnoticGaze",
    "Target_HypnoticPattern",
    "Target_IceStorm",
    "Target_InflictWounds",
    "Target_InsectPlague",
    "Target_Invisibility",
    "Target_Invisibility_Greater",
    "Target_InvokeDuplicity",
    "Target_IrresistibleDance",
    "Target_Jump",
    "Target_Jump_Githyanki",
    "Target_Knock",
    "Target_LayOnHands",
    "Target_LesserRestoration",
    "Target_Light",
    "Target_Longstrider",
    "Target_MageArmor",
    "Target_MageHand",
    "Target_MageHand_GithyankiPsionics",
    "Target_MagicWeapon",
    "Target_MenacingAttack",
    "Target_MinorIllusion",
    "Target_MistyStep",
    "Target_MistyStep_Githyanki",
    "Target_Moonbeam",
    "Target_NaturesWrath",
    "Target_PhantasmalForce",
    "Target_PhantasmalKiller",
    "Target_PlanarBinding",
    "Target_PlantGrowth",
    "Target_Polymorph",
    "Target_ProtectionFromEnergy",
    "Target_ProtectionFromEvilAndGood",
    "Target_ProtectionFromPoison",
    "Target_PushingAttack",
    "Target_Rally",
    "Target_RangersCompanion",
    "Target_RecklessAttack",
    "Target_RemoveCurse",
    "Target_ResilientSphere",
    "Target_Resistance",
    "Target_SacredFlame",
    "Target_Sanctuary",
    "Target_Seeming",
    "Target_Shatter",
    "Target_ShieldOfFaith",
    "Target_ShockingGrasp",
    "Target_Silence",
    "Target_Sleep",
    "Target_SleetStorm",
    "Target_Slow",
    "Target_Smite_Blinding",
    "Target_Smite_Branding_Container",
    "Target_Smite_Branding_ZarielTiefling_Container",
    "Target_Smite_Divine",
    "Target_Smite_Divine_Critical_Unlock",
    "Target_Smite_Divine_Unlock",
    "Target_Smite_Searing",
    "Target_Smite_Searing_ZarielTiefling",
    "Target_Smite_Thunderous",
    "Target_Smite_Wrathful",
    "Target_SneakAttack",
    "Target_SpeakWithDead",
    "Target_SpikeGrowth",
    "Target_SpiritualWeapon",
    "Target_SpitefulSuffering",
    "Target_StinkingCloud",
    "Target_Stoneskin",
    "Target_ThornWhip",
    "Target_TripAttack",
    "Target_TrueStrike",
    "Target_VampiricTouch",
    "Target_ViciousMockery",
    "Target_WardingBond",
    "Target_Web",
    "Teleportation_ArcaneGate",
    "Teleportation_DimensionDoor",
    "Teleportation_Revivify",
    "Throw_FrenziedThrow",
    "Throw_Telekinesis",
    "Wall_WallOfFire",
    "Wall_WallOfStone",
    "Zone_BurningHands",
    "Zone_BurningHands_MephistophelesTiefling",
    "Zone_ColorSpray",
    "Zone_ConeOfCold",
    "Zone_ConjureBarrage",
    "Zone_Fear",
    "Zone_GustOfWind",
    "Zone_LightningBolt",
    "Zone_Sunbeam",
    "Zone_Thunderwave",
    "Target_LOW_RamazithsTower_Nightsong_Globe_1",
}
local ALL_SPELL_TYPES = {
    "Buff",
    "Control",
    "Damage",
    "Healing",
    "Summon",
    "Utility",
}
local ARCHETYPE_WEIGHTS = {
    caster = {
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
    melee = {
        rangedWeapon = -5,
        rangedWeaponInRange = 5,
        rangedWeaponOutOfRange = -5,
        meleeWeapon = 5,
        meleeWeaponInRange = 10,
        isSpell = -10,
        spellInRange = 5,
    },
}
local DAMAGE_TYPES = {
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
local PLAYER_MOVEMENT_SPEED_DEFAULT = {Dash = 6.0, Sprint = 6.0, Run = 3.75, Walk = 2.0, Stroll = 1.4}
local MOVEMENT_SPEED_THRESHOLDS = {
    HONOUR = {Sprint = 5, Run = 2, Walk = 1},
    HARD = {Sprint = 6, Run = 4, Walk = 2},
    MEDIUM = {Sprint = 8, Run = 5, Walk = 3},
    EASY = {Sprint = 12, Run = 9, Walk = 6},
}

-- Session state
-- SpellTable = {}
Listeners = {}
Brawlers = {}
Players = {}
PulseRepositionTimers = {}
PulseActionTimers = {}
BrawlFizzler = {}
IsAttackingOrBeingAttackedByPlayer = {}
ToTTimer = nil
FinalToTChargeTimer = nil
MovementSpeedThresholds = MOVEMENT_SPEED_THRESHOLDS.EASY
BrawlActive = false
PlayerCurrentTarget = nil
-- DynamicAnimationTagsSubscription = nil
-- IsUsingController = false

function debugPrint(...)
    if DEBUG_LOGGING then
        print(...)
    end
end

function debugDump(...)
    if DEBUG_LOGGING then
        _D(...)
    end
end

function dumpAllEntityKeys()
    local uuid = GetHostCharacter()
    local entity = Ext.Entity.Get(uuid)
    for k, _ in pairs(entity:GetAllComponents()) do
        print(k)
    end
end

function dumpEntityToFile(entityUuid)
    Ext.IO.SaveFile(entityUuid .. ".json", Ext.DumpExport(Ext.Entity.Get(entityUuid):GetAllComponents()))
end

function isDowned(entityUuid)
    return Osi.IsDead(entityUuid) == 0 and Osi.GetHitpoints(entityUuid) == 0
end

function isAliveAndCanFight(entityUuid)
    return Osi.IsDead(entityUuid) == 0 and Osi.GetHitpoints(entityUuid) > 0 and Osi.CanFight(entityUuid) == 1
end

function isPlayerOrAlly(entityUuid)
    return Osi.IsPlayer(entityUuid) == 1 or Osi.IsAlly(Osi.GetHostCharacter(), entityUuid) == 1
end

function isPugnacious(potentialEnemyUuid, uuid)
    uuid = uuid or Osi.GetHostCharacter()
    return Osi.IsEnemy(uuid, potentialEnemyUuid) == 1 or IsAttackingOrBeingAttackedByPlayer[potentialEnemyUuid] ~= nil
end

function getDisplayName(entityUuid)
    return Osi.ResolveTranslatedString(Osi.GetDisplayName(entityUuid))
end

-- thank u focus
---@return "EASY"|"MEDIUM"|"HARD"|"HONOUR"
function getDifficulty()
    local difficulty = Osi.GetRulesetModifierString("cac2d8bd-c197-4a84-9df1-f86f54ad4521")
    if difficulty == "HARD" and Osi.GetRulesetModifierBool("338450d9-d77d-4950-9e1e-0e7f12210bb3") == 1 then
        return "HONOUR"
    end
    return difficulty
end

function setMovementSpeedThresholds()
    MovementSpeedThresholds = MOVEMENT_SPEED_THRESHOLDS[getDifficulty()]
end

function enemyMovementDistanceToSpeed(movementDistance)
    if movementDistance > MovementSpeedThresholds.Sprint then
        return "Sprint"
    elseif movementDistance > MovementSpeedThresholds.Run then
        return "Run"
    elseif movementDistance > MovementSpeedThresholds.Walk then
        return "Walk"
    else
        return "Stroll"
    end
end

function playerMovementDistanceToSpeed(movementDistance)
    if movementDistance > 10 then
        return "Sprint"
    elseif movementDistance > 6 then
        return "Run"
    elseif movementDistance > 3 then
        return "Walk"
    else
        return "Stroll"
    end
end

function isBackupSpellUsable(spell, archetype)
    if spell == "Projectile_Jump" then return false end
    if spell == "Shout_Dash_NPC" then return false end
    if spell == "Target_Shove" then return false end
    if spell == "Target_CureWounds" then return false end
    if spell == "Target_HealingWord" then return false end
    if spell == "Target_CureWounds_Mass" then return false end
    if spell == "Target_Devour_Ghoul" then return false end
    if spell == "Target_Devour_ShadowMound" then return false end
    if spell == "Target_LOW_RamazithsTower_Nightsong_Globe_1" then return false end
    if archetype == "melee" then
        if spell == "Target_Dip_NPC" then return false end
        if spell == "Target_MageArmor" then return false end
        if spell == "Projectile_SneakAttack" then return false end
    elseif archetype == "ranged" then
        if spell == "Target_UnarmedAttack" then return false end
        if spell == "Target_Topple" then return false end
        if spell == "Target_Dip_NPC" then return false end
        if spell == "Target_MageArmor" then return false end
        if spell == "Projectile_SneakAttack" then return false end
    elseif archetype == "mage" then
        if spell == "Target_UnarmedAttack" then return false end
        if spell == "Target_Topple" then return false end
        if spell == "Target_Dip_NPC" then return false end
    end
    -- if spell == "Throw_Throw" then return false end
    -- if spell == "Target_MainHandAttack" then return false end
    return true
end

function getMovementSpeed(entityUuid)
    -- local statuses = Ext.Entity.Get(entityUuid).StatusContainer.Statuses
    local entity = Ext.Entity.Get(entityUuid)
    local movementDistance = entity.ActionResources.Resources[MOVEMENT_DISTANCE_UUID][1].Amount
    local movementSpeed = isPlayerOrAlly(entityUuid) and playerMovementDistanceToSpeed(movementDistance) or enemyMovementDistanceToSpeed(movementDistance)
    -- debugPrint("getMovementSpeed", entityUuid, movementDistance, movementSpeed)
    return movementSpeed
end

function calculateEnRouteCoords(moverUuid, targetUuid, goalDistance)
    local xMover, yMover, zMover = Osi.GetPosition(moverUuid)
    local xTarget, yTarget, zTarget = Osi.GetPosition(targetUuid)
    local dx = xMover - xTarget
    local dy = yMover - yTarget
    local dz = zMover - zTarget
    local fracDistance = goalDistance / math.sqrt(dx*dx + dy*dy + dz*dz)
    return xTarget + dx*fracDistance, yTarget + dy*fracDistance, zTarget + dz*fracDistance
end

function moveToDistanceFromTarget(moverUuid, targetUuid, goalDistance)
    local x, y, z = calculateEnRouteCoords(moverUuid, targetUuid, goalDistance)
    Osi.PurgeOsirisQueue(moverUuid, 1)
    Osi.FlushOsirisQueue(moverUuid)
    Osi.CharacterMoveToPosition(moverUuid, x, y, z, getMovementSpeed(moverUuid), "")
end

-- Example monk looping animations (can these be interruptable?)
-- (https://bg3.norbyte.dev/search?iid=Resource.6b05dbcc-19ef-475f-62a2-d18c1e640aa7)
-- animMK = "e85be5a8-6e48-4da4-8486-0d168159df4e"
-- animMK = "7bb52cd4-0b1c-4926-9165-fa92b75876a3"
function holdPosition(entityUuid)
    -- if not isPlayerOrAlly(entityUuid) then
    --     Osi.PlayAnimation(entityUuid, LOOPING_COMBAT_ANIMATION_ID, "")
    -- end
end

function getPlayersSortedByDistance(entityUuid)
    local playerDistances = {}
    for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
        local playerUuid = Osi.GetUUID(player[1])
        if Osi.IsDead(playerUuid) == 0 then
            table.insert(playerDistances, {playerUuid, Osi.GetDistanceTo(entityUuid, playerUuid)})
        end
    end
    table.sort(playerDistances, function (a, b) return a[2] > b[2] end)
    return playerDistances
end

-- Use CharacterMoveTo when possible to move units around so we can specify movement speeds
-- (automove using UseSpell/Attack only uses the fastest possible movement speed)
function moveThenAct(attackerUuid, targetUuid, spellName)
    -- local targetRadius = Ext.Stats.Get(spellName).TargetRadius
    -- debugPrint("moveThenAct", attackerUuid, targetUuid, spellName, targetRadius)
    -- debugDump(Players[attackerUuid])
    -- if targetRadius == "MeleeMainWeaponRange" then
    --     Osi.CharacterMoveTo(attackerUuid, targetUuid, getMovementSpeed(attackerUuid), "")
    -- else
    --     local targetRadiusNumber = tonumber(targetRadius)
    --     if targetRadiusNumber ~= nil then
    --         local distanceToTarget = Osi.GetDistanceTo(attackerUuid, targetUuid)
    --         if distanceToTarget > targetRadiusNumber then
    --             debugPrint("moveThenAct distance > targetRadius, moving to...")
    --             moveToDistanceFromTarget(attackerUuid, targetUuid, targetRadiusNumber)
    --         end
    --     end
    -- end
    debugPrint("moveThenAct", attackerUuid, targetUuid, spellName)
    Osi.PurgeOsirisQueue(attackerUuid, 1)
    Osi.FlushOsirisQueue(attackerUuid)
    Osi.UseSpell(attackerUuid, spellName, targetUuid)
end

function getSpellTypeWeight(spellType)
    if spellType == "Damage" then
        return 7
    elseif spellType == "Healing" then
        return 7
    elseif spellType == "Control" then
        return 3
    elseif spellType == "Buff" then
        return 3
    end
    return 0
end

function getResistanceWeight(spell, entity)
    if entity and entity.Resistances and entity.Resistances.Resistances then
        local resistances = entity.Resistances.Resistances
        if spell.damageType ~= "None" and resistances[DAMAGE_TYPES[spell.damageType]] and resistances[DAMAGE_TYPES[spell.damageType]][1] then
            local resistance = resistances[DAMAGE_TYPES[spell.damageType]][1]
            if resistance == "ImmuneToNonMagical" or resistance == "ImmuneToMagical" then
                return -1000
            elseif resistance == "ResistantToNonMagical" or resistance == "ResistantToMagical" then
                return -5
            elseif resistance == "VulnerableToNonMagical" or resistance == "VulnerableToMagical" then
                return 5
            end
        end
    end
    return 0
end

function getWeightedRandomSpell(weightedSpells)
    if next(weightedSpells) == nil then
        return nil
    end
    local minWeight = nil
    local totalOriginalWeight = 0
    local N = 0
    local spellList = {}
    for spellName, weight in pairs(weightedSpells) do
        totalOriginalWeight = totalOriginalWeight + weight
        N = N + 1
        if (minWeight == nil) or (weight < minWeight) then
            minWeight = weight
        end
        spellList[N] = {name = spellName, weight = weight}
    end
    local totalAdjustedWeight = totalOriginalWeight - (minWeight * N)
    if totalAdjustedWeight == 0 then
        local randomIndex = math.random(1, N)
        return spellList[randomIndex].name
    end
    local rand = math.random() * totalAdjustedWeight
    local cumulativeWeight = 0
    for i = 1, N do
        local adjustedWeight = spellList[i].weight - minWeight
        cumulativeWeight = cumulativeWeight + adjustedWeight
        if rand <= cumulativeWeight then
            return spellList[i].name
        end
    end
end

function getSpellWeight(spell, distanceToTarget, archetype, spellType)
    -- Special target radius labels (NB: are there others besides these two?)
    -- Maybe should weight proportional to distance required to get there...?
    local weight = 0
    if spell.targetRadius == "RangedMainWeaponRange" then
        weight = weight + ARCHETYPE_WEIGHTS[archetype].rangedWeapon
        if distanceToTarget > RANGED_RANGE_MIN and distanceToTarget < RANGED_RANGE_MAX then
            weight = weight + ARCHETYPE_WEIGHTS[archetype].rangedWeaponInRange
        else
            weight = weight + ARCHETYPE_WEIGHTS[archetype].rangedWeaponOutOfRange
        end
    elseif spell.targetRadius == "MeleeMainWeaponRange" then
        weight = weight + ARCHETYPE_WEIGHTS[archetype].meleeWeapon
        if distanceToTarget <= MELEE_RANGE then
            weight = weight + ARCHETYPE_WEIGHTS[archetype].meleeWeaponInRange
        end
    else
        local targetRadius = tonumber(spell.targetRadius)
        if targetRadius then
            if distanceToTarget <= targetRadius then
                weight = weight + ARCHETYPE_WEIGHTS[archetype].spellInRange
            end
        else
            debugPrint("Target radius didn't convert to number, what is this?", spell.targetRadius)
        end
    end
    -- Favor using spells or non-spells?
    if spell.isSpell then
        weight = weight + ARCHETYPE_WEIGHTS[archetype].isSpell
    end
    -- If this spell has a damage type, favor vulnerable enemies
    -- (NB: this doesn't account for physical weapon damage, which is attached to the weapon itself -- todo)
    -- weight = weight + getResistanceWeight(spell, targetEntity)
    -- Adjust by spell type (damage and healing spells are somewhat favored in general)
    weight = weight + getSpellTypeWeight(spellType)
    -- Adjust by spell level (higher level spells are disfavored)
    weight = weight - spell.level*2
    return weight
end

-- What to do?  In all cases, give extra weight to spells that you're already within range for
-- 1. Check if any players are downed and nearby, if so, help them up.
-- 2? Check if any players are badly wounded and in-range, if so, heal them? (...but this will consume resources...)
-- 3. Attack an enemy.
-- 3a. If primarily a caster class, favor spell attacks (cantrips).
-- 3b. If primarily a ranged class, favor ranged attacks.
-- 3c. If primarily a healer/melee class, favor melee abilities and attacks.
-- 3d. If primarily a melee (or other) class, favor melee attacks.
-- 4. Status effects/buffs (NYI)
function getCompanionWeightedSpells(preparedSpells, distanceToTarget, archetype, spellTypes)
    local weightedSpells = {}
    for _, preparedSpell in pairs(preparedSpells) do
        local spellName = preparedSpell.OriginatorPrototype
        local spell = nil
        for _, spellType in ipairs(spellTypes) do
            spell = SpellTable[spellType][spellName]
            if spell ~= nil then
                break
            end
        end
        -- Exclude AoE stuff and all non-cantrip spells for companions
        if spell and spell.areaRadius == 0 and spell.level == 0 then
            weightedSpells[spellName] = getSpellWeight(spell, distanceToTarget, archetype, spellType)
        end
    end
    return weightedSpells
end

-- What to do?  In all cases, give extra weight to spells that you're already within range for
-- 1. Check if any friendlies are badly wounded and in-range, if so, heal them.
-- 2. Attack an enemy.
-- 2a. If primarily a caster class, favor spell attacks (cantrips).
-- 2b. If primarily a ranged class, favor ranged attacks.
-- 2c. If primarily a healer/melee class, favor melee abilities and attacks.
-- 2d. If primarily a melee (or other) class, favor melee attacks.
-- 3. Status effects/buffs (NYI)
function getWeightedSpells(preparedSpells, distanceToTarget, archetype, spellTypes)
    local weightedSpells = {}
    for _, preparedSpell in pairs(preparedSpells) do
        local spellName = preparedSpell.OriginatorPrototype
        local spell = nil
        for _, spellType in ipairs(spellTypes) do
            spell = SpellTable[spellType][spellName]
            if spell ~= nil then
                break
            end
        end
        if spell and (spellType ~= "Healing" or spell.isDirectHeal) then
            weightedSpells[spellName] = getSpellWeight(spell, distanceToTarget, archetype, spellType)
        end
    end
    return weightedSpells
end

function decideCompanionActionOnTarget(preparedSpells, distanceToTarget, archetype, spellTypes)
    if not ARCHETYPE_WEIGHTS[archetype] then
        debugPrint("Archetype missing from the list, using melee for now", archetype)
        archetype = "melee"
    end
    local weightedSpells = getCompanionWeightedSpells(preparedSpells, distanceToTarget, archetype, spellTypes)
    return getWeightedRandomSpell(weightedSpells)
end

function decideActionOnTarget(preparedSpells, distanceToTarget, archetype, spellTypes)
    if not ARCHETYPE_WEIGHTS[archetype] then
        debugPrint("Archetype missing from the list, using melee for now", archetype)
        archetype = "melee"
    end
    local weightedSpells = getWeightedSpells(preparedSpells, distanceToTarget, archetype, spellTypes)
    return getWeightedRandomSpell(weightedSpells)
end

function actOnHostileTarget(brawler, target)
    local archetype = Osi.GetActiveArchetype(brawler.uuid)
    local distanceToTarget = Osi.GetDistanceTo(brawler.uuid, target.uuid)
    if brawler and target then
        -- todo: Utility spells
        local spellTypes = {"Control", "Damage"}
        local actionToTake = nil
        local preparedSpells = Ext.Entity.Get(brawler.uuid).SpellBookPrepares.PreparedSpells
        if Osi.IsPlayer(brawler.uuid) == 1 then
            actionToTake = decideCompanionActionOnTarget(preparedSpells, distanceToTarget, archetype, spellTypes)
            debugPrint("Companion action to take on hostile target", actionToTake, brawler.uuid, brawler.displayName)
        else
            actionToTake = decideActionOnTarget(preparedSpells, distanceToTarget, archetype, spellTypes)
            debugPrint("Action to take on hostile target", actionToTake, brawler.uuid, brawler.displayName)
        end
        if actionToTake == nil and Osi.IsPlayer(brawler.uuid) == 0 then
            local numUsableSpells = 0
            local usableSpells = {}
            for _, preparedSpell in pairs(preparedSpells) do
                local spellName = preparedSpell.OriginatorPrototype
                if isBackupSpellUsable(spellName, archetype) then
                    if not SpellTable.Healing[spellName] and not SpellTable.Buff[spellName] and not SpellTable.Utility[spellName] then
                        table.insert(usableSpells, spellName)
                        numUsableSpells = numUsableSpells + 1
                    end
                end
            end
            if numUsableSpells > 1 then
                actionToTake = usableSpells[math.random(1, numUsableSpells)]
            elseif numUsableSpells == 1 then
                actionToTake = usableSpells[1]
            else
                actionToTake = "Target_MainHandAttack"
            end
            -- print("actionToTake", actionToTake, numUsableSpells)
        end
        if actionToTake ~= nil then
            moveThenAct(brawler.uuid, target.uuid, actionToTake)
            return true
        end
        return false
    end
    return false
end

function actOnFriendlyTarget(brawler, target)
    local archetype = Osi.GetActiveArchetype(brawler.uuid)
    local distanceToTarget = Osi.GetDistanceTo(brawler.uuid, target.uuid)
    if brawler.preparedSpells ~= nil then
        -- todo: Utility/Buff spells
        local spellTypes = {"Healing"}
        debugPrint("acting on friendly target", brawler.uuid, brawler.displayName, archetype, getDisplayName(target.uuid))
        local actionToTake = decideActionOnTarget(brawler.preparedSpells, distanceToTarget, archetype, spellTypes)
        debugPrint("Action to take on friendly target", actionToTake, brawler.uuid, brawler.displayName)
        if actionToTake ~= nil then
            moveThenAct(brawler.uuid, target.uuid, actionToTake)
            return true
        end
        return false
    end
    return false
end

function getBrawlersSortedByDistance(entityUuid)
    local brawlersSortedByDistance = {}
    local level = Osi.GetRegion(entityUuid)
    if Brawlers[level] then
        for brawlerUuid, brawler in pairs(Brawlers[level]) do
            if isAliveAndCanFight(brawlerUuid) then
                table.insert(brawlersSortedByDistance, {brawlerUuid, Osi.GetDistanceTo(entityUuid, brawlerUuid)})
            end
        end
        table.sort(brawlersSortedByDistance, function (a, b) return a[2] < b[2] end)
    end
    return brawlersSortedByDistance
end

-- Attacking targets: prioritize close targets with less remaining HP
-- (Lowest weight = most desireable target)
function getHostileWeightedTargets(brawler, potentialTargets)
    local weightedTargets = {}
    for potentialTargetUuid, _ in pairs(potentialTargets) do
        if Osi.IsEnemy(brawler.uuid, potentialTargetUuid) == 1 and Osi.IsInvisible(potentialTargetUuid) == 0 and isAliveAndCanFight(potentialTargetUuid) then
            local distanceToTarget = Osi.GetDistanceTo(brawler.uuid, potentialTargetUuid)
            local targetHp = Osi.GetHitpoints(potentialTargetUuid)
            weightedTargets[potentialTargetUuid] = distanceToTarget * targetHp
            -- NB: this is too intense of a request and will crash the game :/
            -- local concentration = Ext.Entity.Get(potentialTargetUuid).Concentration
            -- if concentration and concentration.SpellId and concentration.SpellId.OriginatorPrototype ~= "" then
            --     weightedTargets[potentialTargetUuid] = weightedTargets[potentialTargetUuid] * AI_TARGET_CONCENTRATION_WEIGHT_MULTIPLIER
            -- end
        end
    end
    return weightedTargets
end

function decideOnHostileTarget(weightedTargets)
    local targetUuid = nil
    local minWeight = nil
    if next(weightedTargets) ~= nil then
        for potentialTargetUuid, targetWeight in pairs(weightedTargets) do
            if minWeight == nil or targetWeight < minWeight then
                minWeight = targetWeight
                targetUuid = potentialTargetUuid
            end
        end
        if targetUuid then
            return targetUuid
        end
    end
    return nil
end

function findTarget(brawler)
    local level = Osi.GetRegion(brawler.uuid)
    if level then
        local brawlersSortedByDistance = getBrawlersSortedByDistance(brawler.uuid)
        -- Healing (non-player only)
        if Osi.IsPlayer(brawler.uuid) == 0 then
            if Brawlers[level] then
                local minTargetHpPct = 200.0
                local friendlyTargetUuid = nil
                for targetUuid, target in pairs(Brawlers[level]) do
                    if Osi.IsAlly(brawler.uuid, targetUuid) == 1 then
                        -- print("Enemy isally check", brawler.uuid, brawler.displayName, targetUuid, getDisplayName(targetUuid), Osi.IsAlly(brawler.uuid, targetUuid))
                        local targetHpPct = Osi.GetHitpointsPercentage(targetUuid)
                        if targetHpPct ~= nil and targetHpPct > 0 and targetHpPct < minTargetHpPct then
                            minTargetHpPct = targetHpPct
                            friendlyTargetUuid = targetUuid
                        end
                    end
                end
                -- Arbitrary threshold for healing
                if minTargetHpPct < AI_HEALTH_PERCENTAGE_HEALING_THRESHOLD and friendlyTargetUuid and Brawlers[level][friendlyTargetUuid] then
                    debugPrint("actOnFriendlyTarget", brawler.uuid, brawler.displayName, friendlyTargetUuid, getDisplayName(friendlyTargetUuid))
                    local result = actOnFriendlyTarget(brawler, Brawlers[level][friendlyTargetUuid])
                    debugPrint("result", result)
                    if result == true then
                        return
                    end
                end
            end
        end
        -- Attacking
        local weightedTargets = getHostileWeightedTargets(brawler, Brawlers[level])
        local targetUuid = decideOnHostileTarget(weightedTargets)
        debugDump(weightedTargets)
        debugPrint("got hostile target", targetUuid)
        if targetUuid and Brawlers[level][targetUuid] then
            local result = actOnHostileTarget(brawler, Brawlers[level][targetUuid])
            debugPrint("result (hostile)", result)
            if result == true then
                return
            end
        end
        debugPrint("can't find a target, holding position", brawler.uuid, brawler.displayName)
        holdPosition(brawler.uuid)
    end
end

function isPlayerControllingDirectly(entityUuid)
    return Players[entityUuid] ~= nil and Players[entityUuid].isControllingDirectly == true
end

function stopPulseAction(brawler)
    brawler.isInBrawl = false
    if PulseActionTimers[brawler.uuid] ~= nil then
        debugPrint("stop pulse action", brawler.displayName)
        Ext.Timer.Cancel(PulseActionTimers[brawler.uuid])
        PulseActionTimers[brawler.uuid] = nil
    end
end

-- Brawlers doing dangerous stuff
function pulseAction(brawler)
    -- Brawler is alive and able to fight: let's go!
    if brawler and brawler.uuid then
        if not brawler.isPaused and isAliveAndCanFight(brawler.uuid) and not isPlayerControllingDirectly(brawler.uuid) then
            -- NB: if we allow healing spells etc used by companions, roll this code in, instead of special-casing it here...
            if isPlayerOrAlly(brawler.uuid) then
                for playerUuid, player in pairs(Players) do
                    if not player.isBeingHelped and brawler.uuid ~= playerUuid and isDowned(playerUuid) and Osi.GetDistanceTo(playerUuid, brawler.uuid) < HELP_DOWNED_MAX_RANGE then
                        player.isBeingHelped = true
                        brawler.isAutoAttacking = false
                        brawler.targetUuid = nil
                        debugPrint("Helping target", playerUuid, getDisplayName(playerUuid))
                        return moveThenAct(brawler.uuid, playerUuid, "Target_Help")
                    end
                end
            end
            -- Doesn't currently have an attack target, so let's find one
            if brawler.targetUuid == nil then
                debugPrint("Find target 1", brawler.uuid, brawler.displayName)
                return findTarget(brawler)
            end
            -- Already attacking a target and the target isn't dead, so just keep at it
            if isAliveAndCanFight(brawler.targetUuid) then
                debugPrint("Already attacking", brawler.displayName, brawler.uuid, "->", getDisplayName(brawler.targetUuid))
                return actOnHostileTarget(brawler, brawler.targetUuid)
            end
            -- Has an attack target but it's already dead or unable to fight, so find a new one
            debugPrint("Find target 2", brawler.uuid, brawler.displayName)
            brawler.targetUuid = nil
            return findTarget(brawler)
        end
        -- If this brawler is dead or unable to fight, stop this pulse
        stopPulseAction(brawler)
    end
end

function startPulseAction(brawler)
    debugPrint("start pulse action for", brawler.displayName)
    if PulseActionTimers[brawler.uuid] == nil then
        brawler.isInBrawl = true
        local noisedActionInterval = math.floor(ActionInterval*(0.7 + math.random()*0.6) + 0.5)
        debugPrint("Using action interval", noisedActionInterval)
        PulseActionTimers[brawler.uuid] = Ext.Timer.WaitFor(0, function ()
            debugPrint("pulse action", brawler.uuid, brawler.displayName)
            pulseAction(brawler)
        end, noisedActionInterval)
    end
end

-- NB: This should never be the first thing that happens (brawl should always kick off with an action)
function repositionRelativeToTarget(brawlerUuid, targetUuid)
    local archetype = Osi.GetActiveArchetype(brawlerUuid)
    local distanceToTarget = Osi.GetDistanceTo(brawlerUuid, targetUuid)
    if isPlayerOrAlly(brawlerUuid) then
        local hostUuid = Osi.GetHostCharacter()
        local targetDistanceFromHost = Osi.GetDistanceTo(targetUuid, hostUuid)
        -- If we're close to melee range, then advance, even if we're too far from the player
        if distanceToTarget < MELEE_RANGE*2 then
            debugPrint("inside melee x 2", brawlerUuid, targetUuid)
            Osi.PurgeOsirisQueue(brawlerUuid, 1)
            Osi.FlushOsirisQueue(brawlerUuid)
            Osi.CharacterMoveTo(brawlerUuid, targetUuid, getMovementSpeed(brawlerUuid), "")
        -- Otherwise, if the target would take us too far from the player, move halfway (?) back towards the player
        -- NB: is this causing the weird teleport bug???
        -- elseif targetDistanceFromHost > MAX_COMPANION_DISTANCE_FROM_PLAYER then
        --     debugPrint("outside max player dist", brawlerUuid, hostUuid)
        --     moveToDistanceFromTarget(brawlerUuid, hostUuid, 0.5*Osi.GetDistanceTo(brawlerUuid, hostUuid))
        else
            holdPosition(brawlerUuid)
        end
    elseif archetype == "melee" then
        if distanceToTarget > MELEE_RANGE then
            Osi.PurgeOsirisQueue(brawlerUuid, 1)
            Osi.FlushOsirisQueue(brawlerUuid)
            Osi.CharacterMoveTo(brawlerUuid, targetUuid, getMovementSpeed(brawlerUuid), "")
        else
            holdPosition(brawlerUuid)
        end
    else
        -- debugPrint("misc bucket reposition", brawlerUuid, getDisplayName(brawlerUuid))
        holdPosition(brawlerUuid)
        -- if distanceToTarget <= MELEE_RANGE then
        --     holdPosition(brawlerUuid)
        -- elseif distanceToTarget < RANGED_RANGE_MIN then
        --     moveToDistanceFromTarget(brawlerUuid, targetUuid, RANGED_RANGE_SWEETSPOT)
        -- elseif distanceToTarget < RANGED_RANGE_MAX then
        --     holdPosition(brawlerUuid)
        -- else
        --     moveToDistanceFromTarget(brawlerUuid, targetUuid, RANGED_RANGE_SWEETSPOT)
        -- end
    end
end

-- Enemies are pugnacious jerks and looking for a fight >:(
function checkForBrawlToJoin(brawler)
    local closestAlivePlayer, closestDistance = Osi.GetClosestAlivePlayer(brawler.uuid)
    -- debugPrint("Closest alive player to", brawler.uuid, brawler.displayName, "is", closestAlivePlayer, closestDistance)
    if closestDistance ~= nil and closestDistance < ENTER_COMBAT_RANGE then
        for _, target in ipairs(getBrawlersSortedByDistance(brawler.uuid)) do
            local targetUuid, distance = target[1], target[2]
            -- NB: also check for farther-away units where there's a nearby brawl happening already? hidden? line-of-sight?
            if Osi.IsEnemy(brawler.uuid, targetUuid) == 1 and Osi.IsInvisible(targetUuid) == 0 and distance < ENTER_COMBAT_RANGE then
                debugPrint("Reposition", brawler.displayName, brawler.uuid, distance, "->", getDisplayName(targetUuid))
                BrawlActive = true
                return startPulseAction(brawler)
            end
        end
    end
end

function isBrawlingWithValidTarget(brawler)
    return brawler.isInBrawl and brawler.targetUuid ~= nil and isAliveAndCanFight(brawler.targetUuid)
end

---@class EntityDistance
---@field Entity EntityHandle
---@field Guid string GUID
---@field Distance number
---@param source string GUID
---@param radius number|nil
---@param ignoreHeight boolean|nil
---@param withComponent ExtComponentType|nil
---@return EntityDistance[]
-- thank u hippo (from hippo0o/bg3-mods & AtilioA/BG3-volition-cabinet)
function getNearby(source, radius, ignoreHeight, withComponent)
    radius = radius or 1
    withComponent = withComponent or "Uuid"

    ---@param entity string|EntityHandle GUID
    ---@return number[]|nil {x, y, z}
    local function entityPos(entity)
        entity = type(entity) == "string" and Ext.Entity.Get(entity) or entity
        local ok, pos = pcall(function ()
            return entity.Transform.Transform.Translate
        end)
        if ok then
            return {pos[1], pos[2], pos[3]}
        end
        return nil
    end

    local sourcePos = entityPos(source)
    if not sourcePos then
        return {}
    end

    ---@param target number[] {x, y, z}
    ---@return number
    local function calcDisance(target)
        return math.sqrt(
            (sourcePos[1] - target[1]) ^ 2
                + (not ignoreHeight and (sourcePos[2] - target[2]) ^ 2 or 0)
                + (sourcePos[3] - target[3]) ^ 2
        )
    end

    local nearby = {}
    for _, entity in ipairs(Ext.Entity.GetAllEntitiesWithComponent(withComponent)) do
        local pos = entityPos(entity)
        if pos then
            local distance = calcDisance(pos)
            if distance <= radius then
                table.insert(nearby, {
                    Entity = entity,
                    Guid = entity.Uuid and entity.Uuid.EntityUuid,
                    Distance = distance,
                })
            end
        end
    end
    table.sort(nearby, function (a, b) return a.Distance < b.Distance end)
    return nearby
end

function addNearbyToBrawlers(entityUuid, nearbyRadius)
    for _, nearby in ipairs(getNearby(entityUuid, nearbyRadius)) do
        if nearby.Entity.IsCharacter and isAliveAndCanFight(nearby.Guid) then
            addBrawler(nearby.Guid)
        end
    end
end

function stopPulseReposition(level)
    if PulseRepositionTimers[level] ~= nil then
        Ext.Timer.Cancel(PulseRepositionTimers[level])
        PulseRepositionTimers[level] = nil
    end
end

-- Reposition the NPC relative to the player.  This is the only place that NPCs should enter the brawl!
function pulseReposition(level)
    if Brawlers[level] then
        for brawlerUuid, brawler in pairs(Brawlers[level]) do
            if isAliveAndCanFight(brawlerUuid) then
                -- Enemy units are actively looking for a fight and will attack if you get too close to them
                if isPugnacious(brawlerUuid) then
                    if brawler.isInBrawl then
                        if brawler.targetUuid ~= nil and isAliveAndCanFight(brawler.targetUuid) then
                            -- debugPrint(brawler.displayName, brawlerUuid, "->", getDisplayName(brawler.targetUuid))
                            repositionRelativeToTarget(brawlerUuid, brawler.targetUuid)
                        end
                    else
                        checkForBrawlToJoin(brawler)
                    end
                -- Player, ally, and neutral units are not actively looking for a fight
                -- - Companions and allies use the same logic
                -- - Neutrals just chilling
                elseif BrawlActive and isPlayerOrAlly(brawlerUuid) and not brawler.isPaused then
                    -- debugPrint("Player or ally", brawlerUuid, Osi.GetHitpoints(brawlerUuid))
                    if Players[brawlerUuid] and Players[brawlerUuid].isControllingDirectly == true then
                        -- debugPrint("Player is controlling directly: do not take action!")
                        -- debugDump(brawler)
                        -- debugDump(Players)
                        stopPulseAction(brawler)
                    else
                        if not brawler.isInBrawl then
                            if Osi.IsPlayer(brawlerUuid) == 0 or CompanionAIEnabled then
                                debugPrint("Not in brawl, starting pulse action for", brawler.displayName)
                                -- debugDump(brawler)
                                startPulseAction(brawler)
                            end
                        elseif isBrawlingWithValidTarget(brawler) and Osi.IsPlayer(brawlerUuid) == 1 and CompanionAIEnabled then
                            debugPrint("Reposition party member", brawlerUuid)
                            -- debugDump(brawler)
                            -- debugDump(Players)
                            repositionRelativeToTarget(brawlerUuid, brawler.targetUuid)
                        end
                    end
                end
            -- Check if this is a downed player unit and apply Osi.LieOnGround for the visual downed glitch
            elseif Osi.IsPlayer(brawlerUuid) == 1 and isDowned(brawlerUuid) then
                stopPulseReposition(brawlerUuid)
                Ext.Timer.WaitFor(LIE_ON_GROUND_TIMEOUT, function ()
                    if brawler ~= nil and isDowned(brawlerUuid) then
                        debugPrint("Player downed, applying LieOnGround to", brawlerUuid, brawler.displayName)
                        Osi.LieOnGround(brawlerUuid)
                    end
                end)
            end
        end
    end
end

-- Reposition if needed every REPOSITION_INTERVAL ms
function startPulseReposition(level)
    if PulseRepositionTimers[level] == nil then
        PulseRepositionTimers[level] = Ext.Timer.WaitFor(0, function ()
            pulseReposition(level)
        end, REPOSITION_INTERVAL)
    end
end

function setPlayerRunToSprint(entityUuid)
    local entity = Ext.Entity.Get(entityUuid)
    if Players[entityUuid].movementSpeedRun == nil then
        Players[entityUuid].movementSpeedRun = entity.ServerCharacter.Template.MovementSpeedRun
    end
    entity.ServerCharacter.Template.MovementSpeedRun = entity.ServerCharacter.Template.MovementSpeedSprint
end

-- NB: should we also index Brawlers by combatGuid?
function addBrawler(entityUuid)
    if entityUuid ~= nil then
        local level = Osi.GetRegion(entityUuid)
        if level and Brawlers[level] ~= nil and Brawlers[level][entityUuid] == nil and isAliveAndCanFight(entityUuid) then
            local displayName = getDisplayName(entityUuid)
            debugPrint("Adding Brawler", entityUuid, displayName)
            local brawler = {
                uuid = entityUuid,
                displayName = displayName,
                combatGuid = Osi.CombatGetGuidFor(entityUuid),
                isInBrawl = false,
                isPaused = Osi.IsInForceTurnBasedMode(entityUuid) == 1,
                -- preparedSpells = {},
            }
            -- local entity = Ext.Entity.Get(entityUuid)
            -- if entity then
            --     local spellBookPrepares = entity.SpellBookPrepares
            --     if spellBookPrepares and spellBookPrepares.PreparedSpells then
            --         for _, preparedSpell in ipairs(spellBookPrepares.PreparedSpells) do
            --             if preparedSpell.OriginatorPrototype then
            --                 table.insert(brawler.preparedSpells, preparedSpell.OriginatorPrototype)
            --             end
            --         end
            --         debugDump(brawler.preparedSpells)
            --     end
            -- end
            if Osi.IsPlayer(entityUuid) == 0 then
                -- brawler.originalCanJoinCombat = Osi.CanJoinCombat(entityUuid)
                Osi.SetCanJoinCombat(entityUuid, 0)
            elseif Players[entityUuid] then
                -- brawler.originalCanJoinCombat = 1
                setPlayerRunToSprint(entityUuid)
                Osi.SetCanJoinCombat(entityUuid, 0)
            end
            Brawlers[level][entityUuid] = brawler
        end
    end
end

function getNumEnemiesRemaining(level)
    local numEnemiesRemaining = 0
    for brawlerUuid, brawler in pairs(Brawlers[level]) do
        if isPugnacious(brawlerUuid) and brawler.isInBrawl then
            numEnemiesRemaining = numEnemiesRemaining + 1
        end
    end
    return numEnemiesRemaining
end

function stopBrawlFizzler(level)
    if BrawlFizzler[level] ~= nil then
        -- debugPrint("Something happened, stopping brawl fizzler...")
        Ext.Timer.Cancel(BrawlFizzler[level])
        BrawlFizzler[level] = nil
    end
end

function endBrawl(level)
    BrawlActive = false
    if Brawlers[level] then
        for brawlerUuid, brawler in pairs(Brawlers[level]) do
            stopPulseAction(brawler)
            -- Osi.SetCanJoinCombat(brawlerUuid, brawler.originalCanJoinCombat)
            Osi.FlushOsirisQueue(brawlerUuid)
            debugPrint("setCanJoinCombat to 1 for", brawlerUuid, brawler.displayName)
            Osi.SetCanJoinCombat(brawlerUuid, 1)
        end
        debugPrint("Ended brawl")
        debugDump(Brawlers[level])
    end
    resetPlayersMovementSpeed()
    Brawlers[level] = {}
    stopBrawlFizzler(level)
end

function checkForEndOfBrawl(level)
    local numEnemiesRemaining = getNumEnemiesRemaining(level)
    debugPrint("Number of enemies remaining:", numEnemiesRemaining)
    debugDump(Brawlers)
    if numEnemiesRemaining == 0 then
        endBrawl(level)
    end
end

function removeBrawler(level, entityUuid)
    local combatGuid = nil
    local brawler = Brawlers[level][entityUuid]
    stopPulseAction(brawler)
    Osi.SetCanJoinCombat(entityUuid, 1)
    Brawlers[level][entityUuid] = nil
end

function resetPlayersMovementSpeed()
    for playerUuid, player in pairs(Players) do
        local entity = Ext.Entity.Get(playerUuid)
        entity.ServerCharacter.Template.MovementSpeedRun = PLAYER_MOVEMENT_SPEED_DEFAULT.Run
        -- if player.movementSpeedRun ~= nil then
        --     entity.ServerCharacter.Template.MovementSpeedRun = player.movementSpeedRun
        -- end
    end
end

function resetPlayers()
    Players = {}
    for _, player in pairs(Osi.DB_PartyMembers:Get(nil)) do
        local uuid = Osi.GetUUID(player[1])
        Players[uuid] = {
            uuid = uuid,
            displayName = getDisplayName(uuid),
            userId = Osi.GetReservedUserID(uuid),
        }
        Osi.SetCanJoinCombat(uuid, 1)
    end
end

function setIsControllingDirectly()
    if Players ~= nil and next(Players) ~= nil then
        for playerUuid, player in pairs(Players) do
            player.isControllingDirectly = false
        end
        local entities = Ext.Entity.GetAllEntitiesWithComponent("ClientControl")
        for _, entity in ipairs(entities) do
            -- New player (client) just joined: they might not be in the Players table yet
            if Players[entity.Uuid.EntityUuid] == nil then
                resetPlayers()
            end
        end
        for _, entity in ipairs(entities) do
            Players[entity.Uuid.EntityUuid].isControllingDirectly = true
        end
        -- debugDump("setIsControllingDirectly")
        -- debugDump(Players)
    end
end

function revertHitpoints(entityUuid)
    local entity = Ext.Entity.Get(entityUuid)
    if entity.IsCharacter and ModifiedHitpoints[entityUuid] ~= nil then
        entity.Health.MaxHp = ModifiedHitpoints[entityUuid].originalMaxHp
        entity.Health.Hp = ModifiedHitpoints[entityUuid].originalHp
        entity:Replicate("Health")
        ModifiedHitpoints[entityUuid] = nil
        debugPrint("Reverted hitpoints:", entityUuid, getDisplayName(entityUuid), entity.Health.MaxHp, entity.Health.Hp)
    end
end

function modifyHitpoints(entityUuid)
    local entity = Ext.Entity.Get(entityUuid)
    if entity.IsCharacter and isAliveAndCanFight(entityUuid) and ModifiedHitpoints[entityUuid] == nil then
        local originalHp = Osi.GetHitpoints(entityUuid)
        local originalMaxHp = Osi.GetMaxHitpoints(entityUuid)
        local modifiedMaxHp = originalMaxHp * HITPOINTS_MULTIPLIER
        local modifiedHp = originalHp * HITPOINTS_MULTIPLIER
        entity.Health.MaxHp = modifiedMaxHp
        entity.Health.Hp = modifiedHp
        entity:Replicate("Health")
        ModifiedHitpoints[entityUuid] = {
            originalHp = originalHp,
            originalMaxHp = originalMaxHp,
            modifiedHp = modifiedHp,
            modifiedMaxHp = modifiedMaxHp,
        }
        debugDump(ModifiedHitpoints[entityUuid])
        debugPrint("Modified hitpoints:", entityUuid, getDisplayName(entityUuid), originalHp, modifiedHp, originalMaxHp, modifiedMaxHp)
    end
end

function checkNearby()
    for _, nearby in ipairs(getNearby(Osi.GetHostCharacter(), 50)) do
        if nearby.Entity.IsCharacter then
            local uuid = nearby.Guid
            print(getDisplayName(uuid), uuid, Osi.CanJoinCombat(uuid))
        end
    end
end

function cleanupAll()
    for level, timer in pairs(PulseRepositionTimers) do
        endBrawl(level)
        Ext.Timer.Cancel(timer)
    end
    for uuid, timer in pairs(PulseActionTimers) do
        Ext.Timer.Cancel(timer)
    end
    for level, timer in pairs(BrawlFizzler) do
        endBrawl(level)
        Ext.Timer.Cancel(timer)
    end
    local hostCharacter = Osi.GetHostCharacter()
    if hostCharacter then
        local level = Osi.GetRegion(hostCharacter)
        if level then
            endBrawl(level)
        end
    end
    BrawlActive = false
    PlayerCurrentTarget = nil
end

function split(inputstr, sep)
    if sep == nil then
        sep = "%s" -- whitespace
    else
        sep = string.gsub(sep, "([^%w])", "%%%1")
    end
    local t = {}
    for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
        table.insert(t, str)
    end
    return t
end

local function getSpellInfo(spellType, spellName)
    local spell = Ext.Stats.Get(spellName)
    if spell and spell.VerbalIntent == spellType then
        local spellInfo = {
            level = spell.Level,
            areaRadius = spell.AreaRadius,
            -- targetConditions = spell.TargetConditions,
            -- damageType = spell.DamageType,
            isSpell = spell.SpellSchool ~= "None",
            targetRadius = spell.TargetRadius,
            -- useCosts = spell.UseCosts,
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
    for _, spellName in ipairs(ALL_SPELLS) do
        local spell = Ext.Stats.Get(spellName)
        if spell and spell.VerbalIntent == spellType then
            if spell.ContainerSpells and spell.ContainerSpells ~= "" then
                local containerSpellNames = split(spell.ContainerSpells, ";")
                for _, containerSpellName in ipairs(containerSpellNames) do
                    allSpellsOfType[containerSpellName] = getSpellInfo(spellType, containerSpellName)
                end
            else
                allSpellsOfType[spellName] = getSpellInfo(spellType, spellName)
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

function onStarted(level)
    SpellTable = buildSpellTable()
    -- SpellTable = Ext.Json.Parse(Ext.IO.LoadFile("SpellTable.json"))
    resetPlayers()
    setIsControllingDirectly()
    PlayerCurrentTarget = nil
    setMovementSpeedThresholds()
    resetPlayersMovementSpeed()
    initBrawlers(level)
    debugPrint("onStarted")
    debugDump(Players)
end

function startBrawlFizzler(level)
    stopBrawlFizzler(level)
    BrawlFizzler[level] = Ext.Timer.WaitFor(BRAWL_FIZZLER_TIMEOUT, function ()
        debugPrint("Brawl fizzled", BRAWL_FIZZLER_TIMEOUT)
        endBrawl(level)
    end)
end

local function onResetCompleted()
    debugPrint("ResetCompleted")
    onStarted(Osi.GetRegion(Osi.GetHostCharacter()))
end

-- New user joined (multiplayer)
local function onUserReservedFor(entity, _, _)
    setIsControllingDirectly()
    local entityUuid = entity.Uuid.EntityUuid
    if Players and Players[entityUuid] then
        local userId = entity.UserReservedFor.UserID
        Players[entityUuid].userId = entity.UserReservedFor.UserID
    end
end

-- -- initiative: highest rolls go ASAP, everyone else gets a delay to their pulseAction initial timer?
-- local function onCombatParticipant(entity, _, _)
--     local entityUuid = entity.Uuid.EntityUuid
--     debugPrint("CombatParticipant", entityUuid, getDisplayName(entityUuid))
-- end

local function onLevelGameplayStarted(level, _)
    debugPrint("LevelGameplayStarted", level)
    onStarted(level)
end

function finalToTCharge()
    addNearbyToBrawlers(Osi.GetHostCharacter(), 150)
    Ext.Timer.WaitFor(3000, function ()
        local level = Osi.GetRegion(Osi.GetHostCharacter())
        if Brawlers[level] then
            for brawlerUuid, brawler in pairs(Brawlers[level]) do
                if isPugnacious(brawlerUuid) then
                    Osi.PurgeOsirisQueue(brawlerUuid, 1)
                    Osi.FlushOsirisQueue(brawlerUuid)
                    Osi.Attack(brawlerUuid, Osi.GetHostCharacter(), 0)
                end
            end
        end
    end)
end

local function startToTTimer()
    debugPrint("startToTTimer")
    if ToTTimer ~= nil then
        debugPrint("Cancel the old one first...")
        Ext.Timer.Cancel(ToTTimer)
        ToTTimer = nil
        FinalToTChargeTimer = nil
    end
    if Mods.ToT.Scenario and Mods.ToT.PersistentVars.Scenario.Round < #Mods.ToT.PersistentVars.Scenario.Timeline then
        ToTTimer = Ext.Timer.WaitFor(6000, function ()
            debugPrint("Moving ToT forward")
            Mods.ToT.Scenario.ForwardCombat()
            Ext.Timer.WaitFor(1500, function ()
                debugPrint("adding nearby ToT")
                addNearbyToBrawlers(Osi.GetHostCharacter(), 150)
            end)
            startToTTimer()
        end)
        FinalToTChargeTimer = Ext.Timer.WaitFor(90000, function ()
            finalToTCharge()
        end)
    end
end

local function isToT()
    return Mods.ToT ~= nil
    -- return Mods.ToT ~= nil and Mods.ToT.IsActive()
end

local function onCombatStarted(combatGuid)
    debugPrint("CombatStarted", combatGuid)
    for playerUuid, player in pairs(Players) do
        addBrawler(playerUuid)
    end
    debugDump(Brawlers)
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
        debugDump(Brawlers)
        BrawlActive = true
        if not isToT() then
            ENTER_COMBAT_RANGE = 20
            startBrawlFizzler(level)
            Ext.Timer.WaitFor(500, function ()
                addNearbyToBrawlers(Osi.GetHostCharacter(), NEARBY_RADIUS)
                Ext.Timer.WaitFor(1500, function ()
                    if Osi.CombatIsActive(combatGuid) then
                        Osi.EndCombat(combatGuid)
                    end
                end)
            end)
        else
            startToTTimer()
        end
    end
end

local function onCombatRoundStarted(combatGuid, round)
    debugPrint("CombatRoundStarted", combatGuid, round)
    if not isToT() then
        ENTER_COMBAT_RANGE = 20
        onCombatStarted(combatGuid)
    else
        startToTTimer()
    end
end

local function onCombatEnded(combatGuid)
    debugPrint("CombatEnded", combatGuid)
end

local function onEnteredCombat(entityGuid, combatGuid)
    debugPrint("EnteredCombat", entityGuid, combatGuid)
    addBrawler(Osi.GetUUID(entityGuid))
end

local function onEnteredForceTurnBased(entityGuid)
    debugPrint("EnteredForceTurnBased", entityGuid)
    local entityUuid = Osi.GetUUID(entityGuid)
    if entityUuid then
        local level = Osi.GetRegion(entityUuid)
        if level then
            stopPulseReposition(level)
            stopBrawlFizzler(level)
            if Brawlers[level] then
                for brawlerUuid, brawler in pairs(Brawlers[level]) do
                    stopPulseAction(brawler)
                    Osi.PurgeOsirisQueue(entityUuid, 1)
                    Osi.FlushOsirisQueue(entityUuid)
                    if Players and Players[brawlerUuid] then
                        Brawlers[level][brawlerUuid].isPaused = true
                        Osi.ForceTurnBasedMode(entityUuid, 1)
                    end
                end
            end
        end
    end
end

function onLeftForceTurnBased(entityGuid)
    debugPrint("LeftForceTurnBased", entityGuid)
    local entityUuid = Osi.GetUUID(entityGuid)
    if BrawlActive and entityUuid then
        local level = Osi.GetRegion(entityUuid)
        if level then
            startPulseReposition(level)
            startBrawlFizzler(level)
            if Brawlers[level] then
                for brawlerUuid, brawler in pairs(Brawlers[level]) do
                    startPulseAction(brawler)
                    Osi.PurgeOsirisQueue(entityUuid, 1)
                    Osi.FlushOsirisQueue(entityUuid)
                    if Players and Players[brawlerUuid] then
                        Brawlers[level][brawlerUuid].isPaused = false
                        Osi.ForceTurnBasedMode(entityUuid, 0)
                    end
                end
            end
        end
    end
end

local function onTurnEnded(entityGuid)
    -- NB: how's this work for the "environmental turn"?
    debugPrint("TurnEnded", entityGuid)
end

local function onDied(entityGuid)
    -- debugPrint("Died", entityGuid)
    local level = Osi.GetRegion(entityGuid)
    if level ~= nil then
        local entityUuid = Osi.GetUUID(entityGuid)
        if Brawlers[level] ~= nil and Brawlers[level][entityUuid] ~= nil then
            -- Sometimes units don't appear dead when killed out-of-combat...
            -- this at least makes them lie prone (and dead-appearing units still appear dead)
            Ext.Timer.WaitFor(LIE_ON_GROUND_TIMEOUT, function ()
                debugPrint("LieOnGround", entityGuid)
                Osi.LieOnGround(entityGuid)
            end)
            removeBrawler(level, entityUuid)
            checkForEndOfBrawl(level)
        end
    end
end

-- NB: entity.ClientControl does NOT get reliably updated immediately when this fires
local function onGainedControl(targetGuid)
    debugPrint("GainedControl", targetGuid)
    local targetUuid = Osi.GetUUID(targetGuid)
    if targetUuid ~= nil then
        Osi.PurgeOsirisQueue(targetUuid, 1)
        Osi.FlushOsirisQueue(targetUuid)
        -- local targetEntity = Ext.Entity.Get(targetUuid)
        -- local targetUserId = targetEntity.UserAvatar.UserID --buggy?? doesn't match the others??
        -- local targetUserId = targetEntity.UserReservedFor.UserID
        -- local targetUserId = targetEntity.PartyMember.UserId
        local targetUserId = Osi.GetReservedUserID(targetUuid)
        if Players[targetUuid] ~= nil and targetUserId ~= nil then
            Players[targetUuid].isControllingDirectly = true
            for playerUuid, player in pairs(Players) do
                if player.userId == targetUserId and playerUuid ~= targetUuid then
                    player.isControllingDirectly = false
                end
            end
            local level = Osi.GetRegion(targetUuid)
            if level and Brawlers[level] and Brawlers[level][targetUuid] then
                stopPulseAction(Brawlers[level][targetUuid])
            end
            debugDump(Players)
        end
    end
end

local function onCharacterJoinedParty(character)
    debugPrint("CharacterJoinedParty", character)
    onStarted(Osi.GetRegion(Osi.GetHostCharacter()))
end

local function onCharacterLeftParty(character)
    debugPrint("CharacterLeftParty", character)
    onStarted(Osi.GetRegion(Osi.GetHostCharacter()))
end

local function onDownedChanged(character, isDowned)
    local entityUuid = Osi.GetUUID(character)
    debugPrint("DownedChanged", character, isDowned, entityUuid)
    local player = Players[entityUuid]
    if player then
        if isDowned == 1 and AutoPauseOnDowned then
            if player and player.isControllingDirectly and not player.isPaused then
                Osi.ForceTurnBasedMode(entityUuid, 1)
            end
        end
    end
    if isDowned == 0 then
        local player = Players[entityUuid]
        if player then
            player.isBeingHelped = false
        end
    end
end

local function onAttackedBy(defenderGuid, attackerGuid, _, _, _, _, _)
    BrawlActive = true
    local attackerUuid = Osi.GetUUID(attackerGuid)
    local defenderUuid = Osi.GetUUID(defenderGuid)
    if isToT() then
        addBrawler(attackerUuid)
        addBrawler(defenderUuid)
    end
    if Osi.IsPlayer(attackerUuid) == 1 then
        if Osi.IsPlayer(defenderUuid) == 0 then
            IsAttackingOrBeingAttackedByPlayer[defenderUuid] = attackerUuid
        end
        if isToT() then
            addNearbyToBrawlers(attackerUuid, 100)
        end
    end
    if Osi.IsPlayer(defenderUuid) == 1 then
        if Osi.IsPlayer(attackerUuid) == 0 then
            IsAttackingOrBeingAttackedByPlayer[attackerUuid] = defenderUuid
        end
        if isToT() then
            addNearbyToBrawlers(defenderUuid, 100)
        end
    end
    startBrawlFizzler(Osi.GetRegion(attackerUuid))
end

local function onDialogStarted(dialog, dialogInstanceId)
    debugPrint("DialogStarted", dialog, dialogInstanceId)
    local dialogStopped = false
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    -- if BrawlActive then
    --     local numberOfInvolvedPlayers = Osi.DialogGetNumberOFInvolvedPlayers(dialogInstanceId)
    --     local numberOfInvolvedNpcs = Osi.DialogGetNumberOfInvolvedNPCs(dialogInstanceId)
    --     if numberOfInvolvedNpcs == 1 then
    --         if getDisplayName(Osi.DialogGetInvolvedNPC(dialogInstanceId, 1)) == "Dream Visitor" then
    --             numberOfInvolvedNpcs = 0
    --         end
    --     end
    --     debugPrint("DialogStarted...", dialog, dialogInstanceId, numberOfInvolvedPlayers, numberOfInvolvedNpcs)
    --     if numberOfInvolvedPlayers == 2 and numberOfInvolvedNpcs == 0 then
    --         local involvedPlayers = {}
    --         local isPartyMembersOnly = true
    --         for i = 1, numberOfInvolvedPlayers do
    --             local involvedPlayer = Osi.DialogGetInvolvedPlayer(dialogInstanceId, i)
    --             if Players[involvedPlayer] == nil then
    --                 isPartyMembersOnly = false
    --                 break
    --             end
    --             table.insert(involvedPlayers, involvedPlayer)
    --         end
    --         if isPartyMembersOnly then
    --             debugPrint("Stopping dialog...", dialogInstanceId)
    --             debugDump(involvedPlayers)
    --             for _, player in ipairs(involvedPlayers) do
    --                 Osi.DialogRemoveActorFromDialog(dialogInstanceId, player)
    --                 Osi.DialogRequestStopForDialog(dialog, player)
    --             end
    --             dialogStopped = true
    --         end
    --     end
    -- end
    if not dialogStopped then
        BrawlActive = false
        stopPulseReposition(level)
        stopBrawlFizzler(level)
    end
end

local function onDialogEnded(dialog, dialogInstanceId)
    debugPrint("DialogEnded", dialog, dialogInstanceId)
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    startPulseReposition(level)
end

local function onDifficultyChanged(difficulty)
    debugPrint("DifficultyChanged", difficulty)
    setMovementSpeedThresholds()
end

-- thank u focus
local function onPROC_Subregion_Entered(characterGuid, _)
    debugPrint("PROC_Subregion_Entered", characterGuid)
    local uuid = Osi.GetUUID(characterGuid)
    local level = Osi.GetRegion(uuid)
    if level and Players and Players[uuid] then
        pulseReposition(level)
    end
end

-- local function onCastedSpell(casterGuid, spell, spellType, spellSchool, id)
--     debugPrint("CastedSpell", casterGuid, spell, spellType, spellSchool, id)
-- end

local function onLevelUnloading(level)
    debugPrint("LevelUnloading", level)
    Brawlers[level] = nil
    PlayerCurrentTarget = nil
    stopPulseReposition(level)
end

function initBrawlers(level)
    debugPrint("initBrawlers", level)
    Brawlers[level] = {}
    for playerUuid, player in pairs(Players) do
        if Osi.IsInCombat(playerUuid) == 1 then
            onCombatStarted(Osi.CombatGetGuidFor(playerUuid))
            break
        end
    end
    startPulseReposition(level)
end

function stopListeners()
    cleanupAll()
    for _, listener in pairs(Listeners) do
        listener.stop(listener.handle)
    end
end

function startListeners()
    debugPrint("Starting listeners...")
    Listeners.ResetCompleted = {}
    Listeners.ResetCompleted.handle = Ext.Events.ResetCompleted:Subscribe(onResetCompleted)
    Listeners.ResetCompleted.stop = function () Ext.Events.ResetCompleted:Unsubscribe(Listeners.ResetCompleted.handle) end
    Listeners.UserReservedFor = {
        handle = Ext.Entity.Subscribe("UserReservedFor", onUserReservedFor),
        stop = Ext.Entity.Unsubscribe,
    }
    -- Listeners.CombatParticipant = {
    --     handle = Ext.Entity.Subscribe("CombatParticipant", onCombatParticipant),
    --     stop = Ext.Entity.Unsubscribe,
    -- }
    Listeners.LevelGameplayStarted = {
        handle = Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", onLevelGameplayStarted),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.CombatStarted = {
        handle = Ext.Osiris.RegisterListener("CombatStarted", 1, "after", onCombatStarted),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.CombatEnded = {
        handle = Ext.Osiris.RegisterListener("CombatEnded", 1, "after", onCombatEnded),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.CombatRoundStarted = {
        handle = Ext.Osiris.RegisterListener("CombatRoundStarted", 2, "after", onCombatRoundStarted),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.EnteredCombat = {
        handle = Ext.Osiris.RegisterListener("EnteredCombat", 2, "after", onEnteredCombat),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.EnteredForceTurnBased = {
        handle = Ext.Osiris.RegisterListener("EnteredForceTurnBased", 1, "after", onEnteredForceTurnBased),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.LeftForceTurnBased = {
        handle = Ext.Osiris.RegisterListener("LeftForceTurnBased", 1, "after", onLeftForceTurnBased),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.TurnEnded = {
        handle = Ext.Osiris.RegisterListener("TurnEnded", 1, "after", onTurnEnded),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.Died = {
        handle = Ext.Osiris.RegisterListener("Died", 1, "after", onDied),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.GainedControl = {
        handle = Ext.Osiris.RegisterListener("GainedControl", 1, "after", onGainedControl),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.CharacterJoinedParty = {
        handle = Ext.Osiris.RegisterListener("CharacterJoinedParty", 1, "after", onCharacterJoinedParty),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.CharacterLeftParty = {
        handle = Ext.Osiris.RegisterListener("CharacterLeftParty", 1, "after", onCharacterLeftParty),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.DownedChanged = {
        handle = Ext.Osiris.RegisterListener("DownedChanged", 2, "after", onDownedChanged),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.AttackedBy = {
        handle = Ext.Osiris.RegisterListener("AttackedBy", 7, "after", onAttackedBy),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.DialogStarted = {
        handle = Ext.Osiris.RegisterListener("DialogStarted", 2, "before", onDialogStarted),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.DialogEnded = {
        handle = Ext.Osiris.RegisterListener("DialogEnded", 2, "after", onDialogEnded),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.DifficultyChanged = {
        handle = Ext.Osiris.RegisterListener("DifficultyChanged", 1, "after", onDifficultyChanged),
        stop = Ext.Osiris.UnregisterListener,
    }
    Listeners.PROC_Subregion_Entered = {
        handle = Ext.Osiris.RegisterListener("PROC_Subregion_Entered", 2, "after", onPROC_Subregion_Entered),
        stop = Ext.Osiris.UnregisterListener,
    }
    -- Listeners.CastedSpell = {
    --     handle = Ext.Osiris.RegisterListener("CastedSpell", 5, "after", onCastedSpell),
    --     stop = Ext.Osiris.UnregisterListener,
    -- }
    Listeners.LevelUnloading = {
        handle = Ext.Osiris.RegisterListener("LevelUnloading", 1, "after", onLevelUnloading),
        stop = Ext.Osiris.UnregisterListener,
    }
end

local function onGameStateChanged(e)
    if e and e.ToState == "UnloadLevel" then
        cleanupAll()
    end
end

local function disableCompanionAI(hotkey)
    debugPrint("companion ai disabled, stopping pulse actions")
    CompanionAIEnabled = false
    for playerUuid, player in pairs(Players) do
        if Brawlers and Brawlers[playerUuid] then
            stopPulseAction(Brawlers[playerUuid])
            Osi.PurgeOsirisQueue(playerUuid, 1)
            Osi.FlushOsirisQueue(playerUuid)
        end
    end
    Osi.QuestMessageHide("ModStatusMessage")
    Osi.QuestMessageShow("ModStatusMessage", "Companion AI Disabled (Press " .. hotkey .. " to Enable)")
    Ext.Timer.WaitFor(3000, function ()
        Osi.QuestMessageHide("ModStatusMessage")
    end)
end

local function enableCompanionAI(hotkey)
    CompanionAIEnabled = true
    Osi.QuestMessageHide("ModStatusMessage")
    Osi.QuestMessageShow("ModStatusMessage", "Companion AI Enabled (Press " .. hotkey .. " to Disable)")
    Ext.Timer.WaitFor(3000, function ()
        Osi.QuestMessageHide("ModStatusMessage")
    end)
end

local function toggleCompanionAI(hotkey)
    if CompanionAIEnabled then
        disableCompanionAI(hotkey)
    else
        enableCompanionAI(hotkey)
    end
end

local function disableMod(hotkey)
    ModEnabled = false
    stopListeners()
    Osi.QuestMessageHide("ModStatusMessage")
    Osi.QuestMessageShow("ModStatusMessage", "Brawl Disabled (Press " .. hotkey .. " to Enable)")
    Ext.Timer.WaitFor(3000, function ()
        Osi.QuestMessageHide("ModStatusMessage")
    end)
end

local function enableMod(hotkey)
    ModEnabled = true
    startListeners()
    local level = Osi.GetRegion(Osi.GetHostCharacter())
    if level then
        onStarted(level)
    end
    Osi.QuestMessageHide("ModStatusMessage")
    Osi.QuestMessageShow("ModStatusMessage", "Brawl Enabled (Press " .. hotkey .. " to Disable)")
    Ext.Timer.WaitFor(3000, function ()
        Osi.QuestMessageHide("ModStatusMessage")
    end)
end

local function toggleMod(hotkey)
    if ModEnabled then
        disableMod(hotkey)
    else
        enableMod(hotkey)
    end
end

local function onMCMSettingSaved(payload)
    _D(payload)
    if not payload or payload.modUUID ~= ModuleUUID or not payload.settingId then
        return
    end
    if payload.settingId == "mod_enabled" then
        ModEnabled = payload.value
        local hotkey = MCM.Get("mod_toggle_hotkey")
        if ModEnabled then
            enableMod(hotkey)
        else
            disableMod(hotkey)
        end
    elseif payload.settingId == "companion_ai_enabled" then
        CompanionAIEnabled = payload.value
        local hotkey = MCM.Get("companion_ai_toggle_hotkey")
        if CompanionAIEnabled then
            enableCompanionAI(hotkey)
        else
            disableCompanionAI(hotkey)
        end
    elseif payload.settingId == "auto_pause_on_downed" then
        AutoPauseOnDowned = payload.value
    elseif payload.settingId == "action_interval" then
        ActionInterval = payload.value
    end
end

local function onNetMessage(data)
    if data.Channel == "ModToggle" then
        if MCM then
            MCM.Set("mod_enabled", not ModEnabled)
        else
            toggleMod(data.Payload)
        end
    elseif data.Channel == "CompanionAIToggle" then
        if MCM then
            MCM.Set("companion_ai_enabled", not CompanionAIEnabled)
        else
            toggleCompanionAI(data.Payload)
        end
    end
end

function onSessionLoaded()
    Ext.Events.NetMessage:Subscribe(onNetMessage)
    if ModEnabled then
        startListeners()
    else
        Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", resetPlayers)
    end
end

Ext.Events.SessionLoaded:Subscribe(onSessionLoaded)
Ext.Events.GameStateChanged:Subscribe(onGameStateChanged)
Ext.ModEvents.BG3MCM["MCM_Setting_Saved"]:Subscribe(onMCMSettingSaved)
