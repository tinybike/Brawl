---@class Constants
local M = {
    OriginCharactersStarter = {
        Karlach = "S_Player_Karlach_2c76687d-93a2-477b-8b18-8a14b549304c",
        Gale = "S_Player_Gale_ad9af97d-75da-406a-ae13-7071c563f604",
        Astarion = "S_Player_Astarion_c7c13742-bacd-460a-8f65-f864fe41f255",
        Laezel = "S_Player_Laezel_58a69333-40bf-8358-1d17-fff240d7fb12",
        Wyll = "S_Player_Wyll_c774d764-4a17-48dc-b470-32ace9ce447d",
        ShadowHeart = "S_Player_ShadowHeart_3ed74f06-3c60-42dc-83f6-f034cb47c679",
    },
    OriginCharactersSpecial = {
        Halsin = "S_GLO_Halsin_7628bc0e-52b8-42a7-856a-13a6fd413323",
        Minthara = "S_GOB_DrowCommander_25721313-0c15-4935-8176-9f134385451b",
        Jaheira = "S_Player_Jaheira_91b6b200-7d00-4d62-8dc9-99e8339dfa1a",
        Minsc = "S_Player_Minsc_0de603c5-42e2-4811-9dad-f652de080eba",
    },
    NPCCharacters = {
        -- TODO: Add more NPCs
        Volo = "S_GLO_Volo_2af25a85-5b9a-4794-85d3-0bd4c4d262fa",
        Jergal = "S_GLO_JergalAvatar_0133f2ad-e121-4590-b5f0-a79413919805",
        Orin = "S_GLO_Orin_bf24e0ec-a3a6-4905-bd2d-45dc8edf8101",
        Gortash = "S_GLO_Gortash_b878a854-f790-4999-95c4-3f20f00f65ac",
        Oathbreaker = "S_GLO_OathbreakerKnight_3939625d-86cc-4395-9d50-4f8b846c4231",
        Isobel = "S_GLO_Isobel_263bfbfc-6160-46f4-a9e1-1089cdb5c211",
        Nightsong = "S_GLO_Nightsong_6c55edb0-901b-4ba4-b9e8-3475a8392d9b",
        Emperor = "S_GLO_Emperor_73d49dc5-8b8b-45dc-a98c-927bb4e3169b",
    },
    Regions = {
        Act0 = "TUT_Avernus_C",
        Act1 = "WLD_Main_A",
        Act1b = "CRE_Main_A",
        Act2 = "SCL_Main_A",
        Act2b = "INT_Main_A",
        Act3 = "BGO_Main_A",
        Act3b = "CTY_Main_A",
        Act3c = "END_Main",
    },
    Waypoints = { -- BG3-Community-Library-Team/BG3-Community-Library
        Act1 = { -- WLD_Main_A
            OverGrownRuins = "S_CHA_WaypointTrigger_5e857e93-203a-4d4a-bd29-8e97eb34dec6",
            RoadsideCliffs = "S_CHA_WaypointTrigger_Top_4141c0a2-5ba9-42c0-ab18-082426df45e7",
            EmeraldGroveEnvirons = "S_DEN_WaypointPos_cdd91969-67d0-454e-b27b-cf34e542956b",
            BlightedVillage = "S_FOR_WaypointTrigger_e44f372c-b335-4dc8-8864-f2111c83c6a6",
            RiversideTeahouse = "S_HAG_WaypointPos_4c92d6c3-055f-40f1-b76b-a3540ffe32ee",
            GoblinCamp = "S_GOB_WaypointTrigger_3b1b1ab2-1962-47cc-8e25-5cfde2a6c32f",
            WaukeensRest = "S_PLA_Tavern_WaypointTrigger_7044aaf2-7ab9-43f6-96f0-08a173fa08b9",
            ZhentarimHideout = "S_PLA_WaypointTrigger_ZhentDungeon_f3cf2ab0-4b05-45e4-b2c8-2dda305ac47e",
            SeluniteOutpost = "S_UND_Fort_WaypointTrigger_dddb39d6-c5ac-4470-98c5-395ce81af017",
            UnderdarkBeach = "S_UND_Beach_WaypointTrigger_91c3fe06-7d44-4f35-a88a-ea5eb303bb70",
            SussurTree = "S_UND_Sussur_WaypointTrigger_d24b2d8c-a4dc-4367-8da2-c6fa75baa61c",
            MyconidColony = "S_UND_Myconid_WaypointTrigger_b83f13a0-e988-48f1-9068-ea9be2adffb2",
            GrymForge = "S_UND_Duergar_WaypointTrigger_01d43e65-d370-46c6-9998-a9f7523221eb",
            RisenRoad = "S_PLA_WaypointShrine_f68dedbb-a256-40f6-a01e-ab261851df5d",
            WisperingDepth = "S_FOR_Bottomless_WaypointTrigger_ad3614e0-8895-45dd-a05d-a78eba584202",
        },
        Act1b = { -- CRE_Main_A
            TrieltaCrags = "S_CRE_Exterior_Waypoint_Pos_00abc10c-921d-46f9-80e0-2b8f92f884c7",
            Monastery = "S_CRE_Monastery_Waypoint_Pos_6b587ee7-5767-4d3e-8ef4-270976e63ad5",
            Creche = "S_CRE_Creche_Waypoint_Pos_4324dbaf-6533-4b0f-8c99-de4e2adbd4ec",
        },
        Act2 = { -- SCL_Main_A
            LastLight = "S_HAV_Waypoint_Pos_94b462c2-9290-4d4d-8bf4-fbf559f03c3f",
            ShadowedBattlefield = "S_SCL_OliverHouse_Waypoint_Pos_7c083353-7e5c-4cb7-ac3e-42fc3a19807f",
            ReithwinTown = "S_TWN_Waypoint_Pos_488ce3e4-2239-4623-9aeb-d34cc18bec58",
            MoonriseTowers = "S_MOO_TowerExterior_Waypoint_Pos_8fd66a2b-7b29-44f9-b6dd-cd957c91d19c",
            GrandMausoleum = "S_TWN_Mausoleum_Waypoint_Pos_c6faa212-fb0f-4fc5-a011-662a03a3b09a",
            GauntletOfShar = "S_SHA_Temple_Waypoint_Pos_7d5d94c7-fa75-41f2-9aef-06b9d42757ea",
            NightsongPrison = "S_SHA_NightsongPrison_EntranceWaypoint_Pos_9b2081b4-d7dd-43ac-8ef0-4acda40379ae",
            RoadToBaldursGate = "S_SCL_RoadToBaldursGate_Waypoint_Pos_ef45338c-09c7-4904-998f-32c0ad1165b6",
        },
        Act3 = { -- BGO_Main_A
            Rivington = "S_WYR_Rivington_WaypointTrigger_016ac9ad-ac85-49a0-a6be-e24fdb0de2bb",
            SharessCaress = "S_WYR_SharessCaress_WaypointTrigger_5561c476-c82d-4239-b4a3-baaf2985ef71",
        },
        Act3b = { -- CTY_Main_A
            BasiliskGate = "S_LOW_Waypoint_HeapsideBarracksTrigger_f0a45122-eca3-4b8f-ad86-c429ca305b3d",
            Heapside = "S_LOW_Waypoint_CityBeachTrigger_f6611899-85b6-45e3-8c1e-3b61590a621f",
            LowerCity = "S_LOW_Waypoint_CentralWallTrigger_97bdf561-7f2b-4618-89ca-5cad0729bd01",
            BaldursGate = "S_LOW_Waypoint_BaldursGateArea_daabc785-6c47-4b5c-a3d8-d4bea24128b7",
            GreyHarbor = "S_LOW_Waypoint_DocksAreaTrigger_1e27d7c2-0914-4717-9a70-37bdcdb3b80b",
            Undercity = "S_LOW_Waypoint_UndercityRuinsTrigger_3e423e81-8d84-463e-b50e-ab8c5869bdf6",
            CazadorsPalace = "S_LOW_CazadorsPalace_Dungeon_WaypointTrigger_717c1fd4-290a-4fb7-9282-dbcdd17a274b",
            BhaalTemple = "S_LOW_Waypoint_BhaalTempleTrigger_807163bb-8341-49da-a074-c5926bfedf1b",
            MorphicDocks = "S_LOW_Waypoint_MorphicPoolDockTrigger_c1ea6981-cfce-495c-8405-3b503df268fd",
        },
    },
    NullGuid = "00000000-0000-0000-0000-000000000000",
}

M.OriginCharacters = {}
for k, v in pairs(M.OriginCharactersStarter) do
    M.OriginCharacters[k] = v
end
for k, v in pairs(M.OriginCharactersSpecial) do
    M.OriginCharacters[k] = v
end

return M
