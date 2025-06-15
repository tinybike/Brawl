local Constants = {}

Constants.DEBUG_LOGGING = true
Constants.REPOSITION_INTERVAL = 2500
Constants.ACTION_INTERVAL_RESCALING = 0.3
Constants.MINIMUM_ACTION_INTERVAL = 1000
Constants.BRAWL_FIZZLER_TIMEOUT = 30000 -- if 30 seconds elapse with no attacks or pauses, end the brawl
Constants.LIE_ON_GROUND_TIMEOUT = 3500
Constants.COUNTDOWN_TURN_INTERVAL = 6000
Constants.MOD_STATUS_MESSAGE_DURATION = 2000
Constants.ENTER_COMBAT_RANGE = 20
Constants.NEARBY_RADIUS = 35
Constants.MELEE_RANGE = 1.5
Constants.GAP_CLOSER_DISTANCE = 5
Constants.RANGED_RANGE_MAX = 25
Constants.RANGED_RANGE_SWEETSPOT = 10
Constants.RANGED_RANGE_MIN = 10
Constants.THROWN_RANGE_MAX = 18
Constants.THROWN_RANGE_MIN = 8
Constants.HELP_DOWNED_MAX_RANGE = 20
Constants.AI_TARGET_CONCENTRATION_WEIGHT_FACTOR = 2
Constants.NAUTILOID_TRANSPONDER_COUNTDOWN_TURNS = 15
Constants.LAKESIDE_RITUAL_COUNTDOWN_TURNS = 5
Constants.UNCAPPED_MOVEMENT_DISTANCE = 1000
Constants.LOOPING_COMBAT_ANIMATION_ID = "7bb52cd4-0b1c-4926-9165-fa92b75876a3" -- monk animation, should prob be a lookup?
Constants.ACTION_RESOURCES = {
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
    SuperiorityDie = "f82e9e53-1391-4555-95b3-ad52c3b8e259",
}
Constants.AUNTIE_ETHEL_UUID = "c457d064-83fb-4ec6-b74d-1f30dfafd12d"
Constants.TUT_ZHALK_UUID = "ed103005-fd71-457d-ae6c-39654bbd8f2e"
Constants.TUT_MIND_FLAYER_UUID = "22a400ec-5f01-4659-82e1-aed0b203c846"
Constants.INVISIBLE_TEMPLATE_UUID = "c13a872b-7d9b-4c1d-8c65-f672333b0c11"
Constants.MAKESHIFT_TRAINING_DUMMY_UUID = "9819c93a-fd5e-474a-b1b8-7ee0cc3a19a7"
Constants.HALSIN_PORTAL_UUID = "f2b5ad7f-013c-4c9e-a755-5fe9ff3287f6"
Constants.IS_TRAINING_DUMMY = {}
Constants.IS_TRAINING_DUMMY[Constants.MAKESHIFT_TRAINING_DUMMY_UUID] = true
Constants.IS_TRAINING_DUMMY[Constants.HALSIN_PORTAL_UUID] = true
Constants.PLAYER_ARCHETYPES = {"", "melee", "mage", "ranged", "healer", "healer_melee", "melee_magic"}
Constants.COMPANION_TACTICS = {"Offense", "Balanced", "Defense"}
Constants.ALL_SPELL_TYPES = {"Buff", "Debuff", "Control", "Damage", "Healing", "Summon", "Utility"}
Constants.ARCHETYPE_WEIGHTS = {
    mage = {
        rangedWeapon = -5,
        rangedWeaponInRange = 5,
        rangedWeaponOutOfRange = -5,
        meleeWeapon = -5,
        meleeWeaponInRange = 5,
        isSpell = 10,
        spellInRange = 10,
        triggersExtraAttack = 0,
        weaponOrUnarmedDamage = -10,
        unarmedDamage = 0,
        spellDamage = 3,
        gapCloser = 0,
        applyDebuff = 5,
    },
    ranged = {
        rangedWeapon = 10,
        rangedWeaponInRange = 10,
        rangedWeaponOutOfRange = 5,
        meleeWeapon = -2,
        meleeWeaponInRange = 5,
        isSpell = -5,
        spellInRange = 5,
        triggersExtraAttack = 5,
        weaponOrUnarmedDamage = 5,
        unarmedDamage = 0,
        spellDamage = 0,
        gapCloser = 0,
        applyDebuff = 5,
    },
    healer_melee = {
        rangedWeapon = -5,
        rangedWeaponInRange = 5,
        rangedWeaponOutOfRange = -5,
        meleeWeapon = 2,
        meleeWeaponInRange = 8,
        isSpell = 4,
        spellInRange = 8,
        triggersExtraAttack = 2,
        weaponOrUnarmedDamage = 3,
        unarmedDamage = 0,
        spellDamage = 1,
        gapCloser = 2,
        applyDebuff = 5,
    },
    healer = {
        rangedWeapon = 3,
        rangedWeaponInRange = 3,
        rangedWeaponOutOfRange = 3,
        meleeWeapon = -2,
        meleeWeaponInRange = 4,
        isSpell = 8,
        spellInRange = 8,
        triggersExtraAttack = 0,
        weaponOrUnarmedDamage = 0,
        unarmedDamage = 0,
        spellDamage = 2,
        gapCloser = 0,
        applyDebuff = 5,
    },
    melee = {
        rangedWeapon = -5,
        rangedWeaponInRange = 5,
        rangedWeaponOutOfRange = -5,
        meleeWeapon = 5,
        meleeWeaponInRange = 10,
        isSpell = -10,
        spellInRange = 5,
        triggersExtraAttack = 10,
        weaponOrUnarmedDamage = 10,
        unarmedDamage = 0,
        spellDamage = 0,
        gapCloser = 10,
        applyDebuff = 1,
    },
    melee_magic = {
        rangedWeapon = -5,
        rangedWeaponInRange = 5,
        rangedWeaponOutOfRange = -5,
        meleeWeapon = 5,
        meleeWeaponInRange = 10,
        isSpell = 5,
        spellInRange = 5,
        triggersExtraAttack = 5,
        weaponOrUnarmedDamage = 5,
        unarmedDamage = 0,
        spellDamage = 1,
        gapCloser = 10,
        applyDebuff = 5,
    },
    monk = {
        rangedWeapon = -5,
        rangedWeaponInRange = 5,
        rangedWeaponOutOfRange = -5,
        meleeWeapon = 0,
        meleeWeaponInRange = 10,
        isSpell = 0,
        spellInRange = 5,
        triggersExtraAttack = 2,
        weaponOrUnarmedDamage = 0,
        unarmedDamage = 20,
        spellDamage = 1,
        gapCloser = 10,
        applyDebuff = 5,
    },
    barbarian = {
        rangedWeapon = -5,
        rangedWeaponInRange = 5,
        rangedWeaponOutOfRange = -5,
        meleeWeapon = 5,
        meleeWeaponInRange = 10,
        isSpell = -10,
        spellInRange = 5,
        triggersExtraAttack = 10,
        weaponOrUnarmedDamage = 10,
        unarmedDamage = 0,
        spellDamage = 0,
        gapCloser = 10,
        applyDebuff = 1,
    },
}
Constants.ARCHETYPE_WEIGHTS.beast = Constants.ARCHETYPE_WEIGHTS.melee
Constants.ARCHETYPE_WEIGHTS.goblin_melee = Constants.ARCHETYPE_WEIGHTS.melee
Constants.ARCHETYPE_WEIGHTS.goblin_ranged = Constants.ARCHETYPE_WEIGHTS.ranged
Constants.ARCHETYPE_WEIGHTS.mage = Constants.ARCHETYPE_WEIGHTS.mage
Constants.ARCHETYPE_WEIGHTS.koboldinventor_drunk = Constants.ARCHETYPE_WEIGHTS.melee
Constants.ARCHETYPE_WEIGHTS.ranged_stupid = Constants.ARCHETYPE_WEIGHTS.ranged
Constants.ARCHETYPE_WEIGHTS.melee_magic_smart = Constants.ARCHETYPE_WEIGHTS.melee_magic
Constants.ARCHETYPE_WEIGHTS.merregon = Constants.ARCHETYPE_WEIGHTS.melee
Constants.ARCHETYPE_WEIGHTS.act3_LOW_ghost_nurse = Constants.ARCHETYPE_WEIGHTS.melee
Constants.ARCHETYPE_WEIGHTS.ogre_melee = Constants.ARCHETYPE_WEIGHTS.melee
Constants.ARCHETYPE_WEIGHTS.beholder = Constants.ARCHETYPE_WEIGHTS.melee_magic
Constants.ARCHETYPE_WEIGHTS.minotaur = Constants.ARCHETYPE_WEIGHTS.melee
Constants.ARCHETYPE_WEIGHTS.steel_watcher_biped = Constants.ARCHETYPE_WEIGHTS.melee
Constants.DAMAGE_TYPES = {
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
Constants.PLAYER_MOVEMENT_SPEED_DEFAULT = {Dash = 6.0, Sprint = 6.0, Run = 3.75, Walk = 2.0, Stroll = 1.4}
Constants.MOVEMENT_SPEED_THRESHOLDS = {
    HONOUR = {Sprint = 5, Run = 2, Walk = 1},
    HARD = {Sprint = 6, Run = 4, Walk = 2},
    MEDIUM = {Sprint = 8, Run = 5, Walk = 3},
    EASY = {Sprint = 12, Run = 9, Walk = 6},
}
Constants.ACTION_BUTTON_TO_SLOT = {0, 2, 4, 6, 8, 10, 12, 14, 16}
Constants.SAFE_AOE_SPELLS = {
    "Target_Volley",
    "Shout_Whirlwind",
    "Shout_DestructiveWave",
    "Shout_DestructiveWave_Radiant",
    "Shout_DestructiveWave_Necrotic",
    "Shout_DivineIntervention_Attack",
    "Shout_SpiritGuardians",
    "Target_GuardianOfFaith",
    "Target_KiResonation_Blast",
}
Constants.RAGE_BOOSTS = {"RAGE", "RAGE_FRENZY", "RAGE_GIANT"}
Constants.LOSE_CONTROL_STATUSES = {
    "GUARDIAN_OF_FAITH_AURA",
    "LOW_SORCEROUSSUNDRIES_MINORILLUSION",
    "MINOR_ILLUSION",
    "HOUNDOFILLOMEN_TECHNICAL",
    "CREATEILLUSION_DISPLACERBEAST",
    "SHA_TRIALS_TELEPORT_TECHNICAL",
    "DOMINATE_BEAST_PLAYER",
    "SWARM_BEAR",
    "SWARM_WAKETHEDEAD_GHOUL",
    "TAUNTED",
    "SWARM_RAVEN",
    "HAG_INSANITYS_KISS",
    "HAG_MASK_CONTROLLED",
    "ORI_KARLACH_ENRAGE",
    "COMPELLED_DUEL",
    "MADNESS",
    "TIMMASK_SPORES",
    "ZOMBIE_DECAY",
    "LOW_FATHERCARRION_FATHEROFTHEDEAD",
    "COMMAND_APPROACH",
    "MAG_DEATH_DO_SHADOW_POSSESION",
    "DOMINATE_PERSON",
    "PLANAR_BINDING",
    "ACCURSED_SPECTER",
    "CHAMPION_CHALLENGE",
    "MIND_MASTERY",
    "DOMINATE_BEAST",
    "UND_NERE_COERCION",
    "SCL_SHADOW_CURSE_UNDEAD",
    "LURING_SONG",
    "SCL_SHADOW_CURSE_UNDEAD_NEW",
    "SHA_NECROMANCER_FLESH_BERSERK",
}

return Constants
