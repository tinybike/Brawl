local Constants = {}

Constants.DEBUG_LOGGING = false
Constants.REPOSITION_INTERVAL = 2500
Constants.ACTION_INTERVAL_RESCALING = 0.3
Constants.MINIMUM_ACTION_INTERVAL = 1000
Constants.BRAWL_FIZZLER_TIMEOUT = 30000 -- if 30 seconds elapse with no attacks or pauses, end the brawl
Constants.LIE_ON_GROUND_TIMEOUT = 3500
Constants.LEADERBOARD_UPDATE_TIMEOUT = 100
Constants.SWARM_TURN_TIMEOUT = 10000
Constants.SWARM_CHUNK_SIZE = 20
Constants.COUNTDOWN_TURN_INTERVAL = 6000
Constants.MOD_STATUS_MESSAGE_DURATION = 2000
Constants.ENTER_COMBAT_RANGE = 20
Constants.TRACKING_DISTANCE_RT = 12
Constants.TRACKING_DISTANCE_TBSM = 20
Constants.NEARBY_RADIUS = 35
Constants.MELEE_RANGE = 1.5
Constants.GAP_CLOSER_DISTANCE = 5
Constants.RANGED_RANGE_MAX = 25
Constants.RANGED_RANGE_SWEETSPOT = 10
Constants.RANGED_RANGE_MIN = 10
Constants.THROWN_RANGE_MAX = 18
Constants.THROWN_RANGE_MIN = 8
Constants.HELP_DOWNED_MAX_RANGE = 20
Constants.AI_TARGET_CONCENTRATION_WEIGHT_FACTOR = 1.1
Constants.NAUTILOID_TRANSPONDER_COUNTDOWN_TURNS = 15
Constants.LAKESIDE_RITUAL_COUNTDOWN_TURNS = 5
Constants.UNCAPPED_MOVEMENT_DISTANCE = 1000
Constants.NULL_UUID = "00000000-0000-0000-0000-000000000000"
Constants.LOOPING_COMBAT_ANIMATION_ID = "7bb52cd4-0b1c-4926-9165-fa92b75876a3" -- monk animation, should prob be a lookup?
Constants.ABILITIES = {
    Strength = 2,
    Dexterity = 3,
    Constitution = 4,
    Intelligence = 5,
    Wisdom = 6,
    Charisma = 7,
}
Constants.ACTION_RESOURCES = {
    ActionPoint = "734cbcfb-8922-4b6d-8330-b2a7e4c14b6a",
    ArcaneRecoveryPoint = "74737a08-7a77-457b-9740-ae363be2b80f",
    ArcaneShot = "2de674bc-8f69-4b57-8fea-ca7632f20935",
    AstralPlanePoint = "5b85d943-5735-4469-bcce-401526ca1fe2",
    BardicInspiration = "46bbeb43-9973-40fb-a11f-e386bc425a8e",
    Bladesong = "3e3ca2c7-358a-447a-bde6-2ed59cb80213",
    BonusActionPoint = "420c8df5-45c2-4253-93c2-7ec44e127930",
    ChannelDivinity = "028304ef-e4b7-4dfb-a7ec-cd87865cdb16",
    ChannelOath = "c0503ecf-c3cd-4719-9cfd-05460a1db95a",
    CosmicOmen = "e02b29c7-37df-4170-8978-99310518cdb0",
    CurvingShot_Charge = "5c13dffd-c0cd-494d-9955-f8fefd3e99dd",
    DeflectMissiles_Charge = "2b8021f4-99ac-42d4-87ce-96a7c5505aee",
    ExtraActionPoint = "5a7331f8-e08f-4810-84f7-6d4d7bd1516e",
    EyeStalkActionPoint = "e92b57fe-78c0-4eb1-a92f-833aa2c20df2",
    FungalInfestationCharge = "281f289d-3c0b-433a-a7ed-0505be88ec9e",
    HitDice = "d59999b2-3e77-42f6-96e8-b021a17a9e1c",
    InspirationPoint = "a9c98304-08e7-44b5-aaf9-da2ef5a50672",
    Interrupt_AbsorbElements = "6275ca19-95d9-469c-a649-b26f990882fa",
    Interrupt_DivineStrike = "666eed8f-adb0-4805-a6a8-abd90ae5c7f1",
    Interrupt_EntropicWard_Charge = "89c063f2-dadf-49e4-830b-ceb9f50f3538",
    Interrupt_HellishRebukeTiefling_Charge = "b399bf6b-0294-4a92-b81c-7a711da2a315",
    Interrupt_HellishRebukeWarlockMI_Charge = "ed49e9a0-8730-4df2-b113-cda9dca68fe3",
    Interrupt_IllusorySelf_Charge = "af221a83-7ac8-4ee2-8cbe-2ff437711205",
    Interrupt_Indomitable = "8052b721-3a96-4baf-82c0-6dfa27da6c05",
    Interrupt_Legendary_InfernalResistance = "67581067-020c-4e0d-814f-963714479f8a",
    Interrupt_LegendaryEvasion_Protection = "4ebba3a3-f42e-42a6-87af-d36592ba8d49",
    Interrupt_LuckOfTheFarRealms_Charge = "621126c6-a9f7-422c-9a0c-822503719ce4",
    Interrupt_Scarab_Of_Protection = "c55c135f-4e35-42f8-9ebd-a11e890def01",
    Interrupt_MAG_CriticalExecution = "cb54a933-4e77-4e6f-8b7a-9b6b4082f4a2",
    Interrupt_MAG_Counterspell = "1c188f7f-556e-4d2e-b1b2-e239fc2d79d3",
    Interrupt_MAG_ParalyzingCritical = "78236f5a-94d5-4f8b-bb54-16f5508723e6",
    Interrupt_MAG_SecondChance = "7410e905-71a2-483d-8689-57b6e5b7d534",
    Interrupt_MAG_Shield = "c6eb8069-00e5-4b46-869c-6f1c542d6427",
    Interrupt_MAG_Shield_HarpersAmulet = "0d157939-3ede-45aa-a153-e8c2e47edb74",
    Interrupt_MAG_Shield_LeatherArmor = "6f74ea30-96c3-45e4-9820-fbb3cc16b9bc",
    Interrupt_MistyEscape = "668207a2-5f4b-401c-a12f-b180cc81cd5e",
    Interrupt_Portent_1 = "9192ed73-bb9f-4fe3-b437-a45c1c205580",
    Interrupt_Portent_2 = "12cd6971-2efd-4780-b7a0-0cdba87045b9",
    Interrupt_Portent_3 = "aac1dc3f-1334-4f6e-9dd1-40629edaf3cd",
    Interrupt_Portent_4 = "efe9e301-bcd3-43df-b192-4ecc5e106d29",
    Interrupt_Portent_5 = "24001acb-b1e8-43c8-b6e4-011873f6e049",
    Interrupt_Portent_6 = "12ec676a-00cf-4ff8-ae6f-2193a00606eb",
    Interrupt_Portent_7 = "504b4d64-5832-45f7-b09a-ba994b0939ce",
    Interrupt_Portent_8 = "0287dbc3-575e-4476-8045-7890b69f71f6",
    Interrupt_Portent_9 = "edf90ccc-d8d0-426b-925f-3cd78b85f397",
    Interrupt_Portent_10 = "b79a0c10-d83d-4b77-ae23-45f736e9e054",
    Interrupt_Portent_11 = "05a3ed67-d31d-4c1b-ab71-81627440976f",
    Interrupt_Portent_12 = "3d1663d2-311f-499b-909c-7d22221af59e",
    Interrupt_Portent_13 = "1ca1fc70-22ee-4177-87b7-f0c904ce7d48",
    Interrupt_Portent_14 = "6caf524a-f46a-4e55-b725-2aa9a79f7083",
    Interrupt_Portent_15 = "700f2c7b-f7d9-48e8-ad12-b34d7996ca67",
    Interrupt_Portent_16 = "0622ec54-6f4f-41cb-a3be-3312d193ed93",
    Interrupt_Portent_17 = "2871ea7b-f9e7-47d8-9e2d-819f8841a06b",
    Interrupt_Portent_18 = "1d766f02-04e4-4086-9b75-cb0621130e06",
    Interrupt_Portent_19 = "32dc0c71-b26e-482c-b439-4b261823373f",
    Interrupt_Portent_20 = "42bef9f7-1a38-4e2e-99dd-37d08f75ec45",
    Interrupt_TAD_PsionicDominance_Charge = "d1b02f9c-9d6e-4eac-905d-ccd9e7876c7c",
    Interupt_CounterSpell_MindFlayer = "6195dce8-d706-4671-9de3-d85ad25968f8",
    Interupt_Shield_MindFlayer = "7bd0ceb4-9191-4208-b924-909897948fb6",
    KiPoint = "46d3d228-04e0-4a43-9a2e-78137e858c14",
    LayOnHandsCharge = "c2d059f8-7369-4701-9a4c-f85c55d04db3",
    LegendaryResistanceCharge = "732e23a8-bb1d-4bec-a4df-1dd0e03b56c4",
    LuckPoint = "754141b8-98d5-4345-8031-eaa5a0df214d",
    Movement = "d6b2369d-84f0-4ca4-a3a7-62d2d192a185",
    NaturalRecoveryPoint = "d1abb9dc-817c-4a4c-8044-d86c6670b937",
    Passive_MAG_ClosQuarterRangedSpell = "a8770e1c-7fed-443e-9927-4c305535e87d",
    Passive_MAG_Extended_Target_Cantrip = "f3ef1ec5-ca2f-48f6-9317-25bf50e1ef39",
    Passive_MAG_Warlock_Quickened_Cantrips = "dc2cfa76-6a9d-4a9c-8a79-cbb12adcd34b",
    Rage = "6740f9f4-125d-4321-89e0-771fccd64622",
    ReactionActionPoint = "45ff0f48-b210-4024-972f-b64a44dc6985",
    RitualPoint = "ae36a457-2903-4142-a266-c9c71e096e1d",
    ShadowSpellSlot = "77fcde9b-9cda-4fbc-8806-393e26b2f3e1",
    ShortRestPoint = "a24ca5e2-01e1-48fd-a4c8-79b8817f0a18",
    SneakAttack_Charge = "1531b6ec-4ba8-4b0d-8411-422d8f51855f",
    SorceryPoint = "46886ba5-6505-4875-a747-ac14118e1e08",
    SpellSlot = "d136c5d9-0ff0-43da-acce-a74a07f8d6bf",
    StarMapPoint = "f86ca432-354f-4298-b7d0-0949eff3aa48",
    SuperiorityDie = "f82e9e53-1391-4555-95b3-ad52c3b8e259",
    SwarmCharge = "c39fb087-520e-4448-9106-b846115f5a87",
    TadpolePowerPoint = "8b047f9c-ed68-4e00-87e0-c7eded6dcf09",
    TidesOfChaos = "733e3365-082c-4a0a-8df9-98273c23186e",
    TwinklingConstitution_Charge = "df9dfa40-5f22-4e21-bf49-c4b709ece2ee",
    WarlockSpellSlot = "e9127b70-22b7-42a1-b172-d02f828f260a",
    WarPriestActionPoint = "30cca4c5-a808-4c96-bd1c-f57bbb92dc1d",
    WeaponActionPoint = "efd09352-551d-4f4f-9382-2e510a0f6dba",
    WildShape = "68542019-178b-4f43-b9d3-51ab8e7b286b",
    WrithingTidePoint = "87320825-1771-4fa1-8689-ef7636e304dd",
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
Constants.PLAYER_ARCHETYPES = {"", "melee", "mage", "ranged", "healer", "healer_melee", "melee_magic", "monk"}
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
Constants.ARCHETYPE_WEIGHTS.ranged_stupid = Constants.ARCHETYPE_WEIGHTS.ranged
Constants.ARCHETYPE_WEIGHTS.melee_magic_smart = Constants.ARCHETYPE_WEIGHTS.melee_magic
Constants.ARCHETYPE_WEIGHTS.act3_LOW_ghost_nurse = Constants.ARCHETYPE_WEIGHTS.melee
Constants.ARCHETYPE_WEIGHTS.ogre_melee = Constants.ARCHETYPE_WEIGHTS.melee
Constants.ARCHETYPE_WEIGHTS.beholder = Constants.ARCHETYPE_WEIGHTS.melee_magic
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
    "Shout_SpiritGuardians",
    "Target_GuardianOfFaith",
    "Target_KiResonation_Blast",
}
Constants.RAGE_BOOSTS = {"RAGE", "RAGE_FRENZY", "RAGE_GIANT"}
Constants.SPELL_REQUEST_FLAGS = {
    IgnoreHasSpell = 0x1,
    IgnoreCastChecks = 0x2,
    IgnoreSpellRolls = 0x4,
    IsReaction = 0x8,
    NoMovement = 0x10,
    AvoidAoO = 0x20,
    DestroySource = 0x40,
    Immediate = 0x80,
    Silent = 0x100,
    IgnoreTargetChecks = 0x200,
    IsPreview = 0x400,
    IsHoverPreview = 0x800,
    ShowPrepareAnimation = 0x1000,
    Forced = 0x2000,
    IsRoll = 0x4000,
    IsInterrupt = 0x8000,
    FromClient = 0x10000,
    NoUnsheath = 0x20000,
    CheckProjectileTargets = 0x40000,
    AvoidDangerousAuras = 0x80000,
    Unknown100000 = 0x100000,
}
Constants.NO_ACTION_STATUSES = {
    "COMMAND_GROVEL",
    "COMMAND_HALT",
    "COMMAND_APPROACH",
    "COMMAND_FLEE",
    "SLEEP",
    "SLEEPING",
    "INCAPACITATED",
    "STUNNED",
    "STUNNED_STUNNINGGAZE",
    "PETRIFIED",
    "HOLD_PERSON",
    "HOLD_PERSON_MONK",
    "PARALYZED",
    "HOLD_MONSTER",
    "FROZEN",
    "SG_Incapacitated",
    "SG_Stunned",
    "SG_Unconscious",
}
Constants.UNUSABLE_NPC_SPELLS = {
    "Throw_Throw",
    "Target_Devour_Ghoul",
    "Target_Devour_ShadowMound",
    "Target_LOW_RamazithsTower_Nightsong_Globe_1",
    "Target_Dip_NPC",
    "Target_QuiveringPalm",
    "Target_TAD_ConcentratedBlast",
    "Projectile_SneakAttack",
    -- "Target_Shove",
    -- "Rush_Charger_Push",
    -- "Projectile_Jump",
    -- "Shout_Dash_NPC",
}
Constants.LEADERBOARD_EXCLUDED_HEALS = {
    "ShortResting",
    "TimelessBody",
}
Constants.COUNTERSPELLS = {
    "Target_Counterspell",
    "Target_MAG_CounterSpell",
    "Target_Counterspell_Success",
    "Target_CounterSpell_Mindflayer",
    "Target_Counterspell_4",
    "Target_Counterspell_5",
    "Target_Counterspell_6",
    "Target_MOD_Dread_Counterspell",
}
Constants.PER_TURN_ACTION_RESOURCES = {"ActionPoint", "BonusActionPoint", "ReactionActionPoint"}
Constants.MAGIC_MISSILE_PATHFIND_UUID = "7bff57fa-fd21-4ab3-9384-83fb14237690"

return Constants
