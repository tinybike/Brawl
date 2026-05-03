Compositions = Compositions or {}

-- Templates organized by their actual character Level (from ToTR's Enemies.json).
-- All MOD_*-prefixed (the TOT_<arena>_* family is scenario-coupled and unreliable).
-- (V) = empirically validated 2026-05-02 in Encounters smoke tests.
-- Others are plausible-but-unverified — if any fail CreateAt at runtime, prune them.
Compositions.templatesByLevel = {
    [1] = {
        "7204bb7f-320b-4a73-b21a-7e12f8363f4d",  -- MOD_AgileSkeleton (V)
        "59723fe3-e81e-4feb-bd9e-b32343a709da",  -- MOD_RobustSkeleton (V)
        "bbbce2b8-9bdc-44c5-917f-f39af2ce6cd4",  -- MOD_Rothe
    },
    [2] = {
        "e64816a9-dad4-4d7b-aa36-b09cb97077eb",  -- MOD_EntombedSkeleton (V)
    },
    [3] = {
        "a60a7476-e5ad-47c3-aaa5-e6b5ed2ce9af",  -- MOD_Falxugon (V)
        "cc35a307-014c-460d-8b38-1ff8682aca33",  -- MOD_Harpy_Combat
        "34aeab13-5298-4c66-a4c6-362c80813a4f",  -- MOD_Harpy_CombatB
    },
    [5] = {
        "399e7864-a949-4d2f-81ea-a2504eabe5d5",  -- MOD_Displacer_Beast (V)
    },
    [10] = {
        "837aee98-23e1-49c3-9dea-cef2f42fe684",  -- MOD_Hollyphant
    },
    [12] = {
        "9caf9031-fd9b-4e1a-a275-4cbeac1ae07f",  -- MOD_Delilah (legendary)
        "5e1eb8e2-ec15-4228-aab2-8b8d27151ea2",  -- MOD_Sylas (legendary)
        "1e25d287-1eb1-4b89-ac0c-e3d4b03097f6",  -- MOD_Orthax (epic)
        "b1d45242-e99e-4760-80da-889b2ae6e7b4",  -- MOD_Mizora (epic)
    },
    [16] = {
        "b4054d11-e06f-4c11-96b6-4b96a29c3afc",  -- MOD_Ukotoalock
        "06b43605-6ecd-43ca-b1e3-d4f9d3430f63",  -- MOD_KrynWarrior (ultra)
        "f7e06442-9b05-4796-84b9-4d0b780330c5",  -- MOD_KrynWizard (ultra)
        "4b9ede4c-0d6f-49ab-bb43-2760da1a7790",  -- MOD_Gorgon (ultra)
        "c35f0df8-c19d-48fc-85d5-3f562cd4919d",  -- MOD_Gloomstalker (ultra)
        "35dc0b28-8e4b-43bf-a7b8-301c8f57e5c8",  -- MOD_Brimscythe (epic)
        "34c1c71f-5cd0-4824-b1dc-3076a5df0100",  -- MOD_Avantika (epic)
        "5eb397d6-1e72-4ea2-a0d9-ea5fb366b2b4",  -- MOD_Astrid (epic)
        "26949ee0-7407-4fde-a967-9764ed7e8996",  -- MOD_MagmaShark (epic)
        "0381cc1f-cdda-466f-8ea6-b886ca365d4d",  -- MOD_EmberRoc (epic)
        "f7d4c47e-3223-481b-bbb2-2f40048ff902",  -- MOD_Kevdak (legendary)
        "21a451f6-a911-415a-9fe0-e7b30ef83b23",  -- MOD_Vespin (legendary)
        "37c6c618-b07b-499f-8542-3f322a1339c3",  -- MOD_Jourrael (legendary)
        "9ba470fa-059c-462b-8b71-7b9e3d821901",  -- MOD_Lorenzo (ultra)
    },
    [20] = {
        "efb9861b-8214-4d66-be5f-4a87b53d5154",  -- MOD_Lucien (mythical)
        "f7e56aa4-f824-4185-b62c-0ebb700d7169",  -- MOD_Elminster (mythical)
        "e3adba3f-742b-4024-8375-ef33349aa915",  -- MOD_Netherbrain (mythical)
    },
    [23] = {
        "e0a624a2-55b3-4438-96b5-59de300940ac",  -- MOD_Vlaakith
        "8a678d84-13df-4e13-8258-cea2ca291cd1",  -- MOD_Ludinus
        "ae24b762-570b-4216-8e14-13f17248fc3c",  -- MOD_Otohan
        "c4a91261-06f8-444c-8444-97287e287e0c",  -- MOD_Vaxildan
        "3e629445-9953-418e-9fc6-803188184dbc",  -- MOD_Groon
    },
}

local function allLevels()
    local levels = {}
    for L in pairs(Compositions.templatesByLevel) do
        table.insert(levels, L)
    end
    table.sort(levels)
    return levels
end

function Compositions.templatesInRange(minLevel, maxLevel)
    local results = {}
    for L, list in pairs(Compositions.templatesByLevel) do
        if L >= minLevel and L <= maxLevel then
            for _, uuid in ipairs(list) do
                table.insert(results, uuid)
            end
        end
    end
    return results
end

function Compositions.compositionForLevel(playerLevel, difficultyOffset)
    playerLevel = (playerLevel or 1) + (difficultyOffset or 0)
    if playerLevel < 1 then playerLevel = 1 end

    local count = 3
    if playerLevel >= 8 then count = count + 1 end
    if playerLevel >= 14 then count = count + 1 end

    local templates = {}

    -- Lead slot: at-level, sometimes slightly above
    local bossPool = Compositions.templatesInRange(playerLevel - 2, playerLevel + 1)
    if #bossPool == 0 then
        bossPool = Compositions.templatesInRange(math.max(1, playerLevel - 4), playerLevel + 3)
    end
    if #bossPool > 0 then
        table.insert(templates, bossPool[math.random(1, #bossPool)])
    end

    -- Filler slots: a few levels below. ToTR's template pool is gappy at L4-L9; if the narrow
    -- range yields only 1-2 templates we'd over-concentrate on tough mid-tiers (e.g. all displacer
    -- beasts), so fall back to all-at-or-below for variety.
    local fillerMin = math.max(1, playerLevel - 5)
    local fillerMax = math.max(1, playerLevel - 2)
    local fillerPool = Compositions.templatesInRange(fillerMin, fillerMax)
    if #fillerPool < 3 then
        fillerPool = Compositions.templatesInRange(1, math.max(1, playerLevel - 1))
    end

    for _ = 1, count - 1 do
        if #fillerPool > 0 then
            table.insert(templates, fillerPool[math.random(1, #fillerPool)])
        end
    end
    return templates
end

function Compositions.hostLevel(host)
    host = host or Osi.GetHostCharacter()
    local entity = Ext.Entity.Get(host)
    if entity and entity.EocLevel and entity.EocLevel.Level then
        return entity.EocLevel.Level
    end
    return 1
end
