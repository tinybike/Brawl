DEBUG_LOGGING = true
REPOSITION_INTERVAL = 2500
BRAWL_FIZZLER_TIMEOUT = 30000 -- if 30 seconds elapse with no attacks or pauses, end the brawl
LIE_ON_GROUND_TIMEOUT = 3500
COUNTDOWN_TURN_INTERVAL = 6000
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
NAUTILOID_TRANSPONDER_COUNTDOWN_TURNS = 15
LAKESIDE_RITUAL_COUNTDOWN_TURNS = 5
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
AUNTIE_ETHEL_UUID = "c457d064-83fb-4ec6-b74d-1f30dfafd12d"
TUT_ZHALK_UUID = "ed103005-fd71-457d-ae6c-39654bbd8f2e"
TUT_MIND_FLAYER_UUID = "22a400ec-5f01-4659-82e1-aed0b203c846"
INVISIBLE_TEMPLATE_UUID = "c13a872b-7d9b-4c1d-8c65-f672333b0c11"
MAKESHIFT_TRAINING_DUMMY_UUID = "9819c93a-fd5e-474a-b1b8-7ee0cc3a19a7"
HALSIN_PORTAL_UUID = "f2b5ad7f-013c-4c9e-a755-5fe9ff3287f6"
IS_TRAINING_DUMMY = {}
IS_TRAINING_DUMMY[MAKESHIFT_TRAINING_DUMMY_UUID] = true
IS_TRAINING_DUMMY[HALSIN_PORTAL_UUID] = true
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
