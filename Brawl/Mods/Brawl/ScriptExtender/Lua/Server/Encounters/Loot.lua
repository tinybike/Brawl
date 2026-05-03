Loot = Loot or {}

-- ToTR's exact rates from CombatMod/Constants.lua
local LOOT_RATES = {
    Objects  = {Common = 40, Uncommon = 20, Rare = 10, VeryRare = 5,  Legendary = 2},
    Armor    = {Common = 30, Uncommon = 65, Rare = 20, VeryRare = 10, Legendary = 2},
    Weapons  = {Common = 30, Uncommon = 65, Rare = 20, VeryRare = 10, Legendary = 2},
}

-- ToTR's exact category mix from Item.GenerateLoot rollCategory
local CATEGORY_MIX = {"CombatObject", "CombatObject", "Weapon", "Armor", "Weapon", "Armor", "Armor"}

local BLACKLIST = Ext.Require("Server/Encounters/ItemBlacklist.lua") or {}
local pools = nil

local function isBlacklisted(name)
    for _, pattern in ipairs(BLACKLIST) do
        if name:match(pattern) then return true end
    end
    return false
end

local function splitSemicolon(s)
    local out = {}
    for part in string.gmatch(s or "", "([^;]+)") do
        table.insert(out, part)
    end
    return out
end

local function hasTreasureCategory(stat, name, temp)
    if Ext.Stats.TreasureCategory.GetLegacy("I_" .. name) then return true end
    if temp and Ext.Stats.TreasureCategory.GetLegacy("I_" .. temp.Name) then return true end
    for _, v in ipairs(splitSemicolon(stat.ObjectCategory)) do
        if Ext.Stats.TreasureCategory.GetLegacy(v) then return true end
    end
    return false
end

local function getTemplate(stat)
    if not stat or stat.RootTemplate == "" then return nil end
    return Ext.Template.GetTemplate(stat.RootTemplate)
end

local function commonExclusions(stat, name)
    if not stat then return true end
    if isBlacklisted(name) then return true end
    if name:match("^_") then return true end
    if stat.Rarity == "" or stat.RootTemplate == "" then return true end
    local temp = getTemplate(stat)
    if not temp or temp.Name:match("DONOTUSE$") then return true end
    return false, temp
end

local function isValidObject(stat, name, forCombat)
    local excluded, temp = commonExclusions(stat, name)
    if excluded then return false end

    if not hasTreasureCategory(stat, name, temp) then return false end

    if forCombat then
        return stat.ItemUseType == "Potion" or stat.InventoryTab == "Magical"
    else
        local cat = stat.ObjectCategory or ""
        local foodDrink = (cat:match("^Food") or cat:match("^Drink")) and name:match("^CONS_")
        local alch = name:match("^ALCH_Ingredient")
        local soul = name:match("^GLO_SoulCoin")
        return foodDrink or alch or soul
    end
end

local function isValidArmor(stat, name)
    local excluded = commonExclusions(stat, name)
    if excluded then return false end
    local slot = stat.Slot or ""
    if slot:match("VanityBody") or slot:match("VanityBoots") or slot:match("Underwear") then
        return false
    end
    if stat.UseConditions ~= "" then return false end
    return true
end

local function isValidWeapon(stat, name)
    local excluded = commonExclusions(stat, name)
    return not excluded
end

local function emptyRarityBuckets()
    return {Common = {}, Uncommon = {}, Rare = {}, VeryRare = {}, Legendary = {}}
end

local function pushIf(bucket, rarity, rootTemplate)
    if bucket[rarity] then table.insert(bucket[rarity], rootTemplate) end
end

local function buildPools()
    pools = {
        Object       = emptyRarityBuckets(),
        CombatObject = emptyRarityBuckets(),
        Armor        = emptyRarityBuckets(),
        Weapon       = emptyRarityBuckets(),
    }

    for _, name in ipairs(Ext.Stats.GetStats("Object") or {}) do
        local stat = Ext.Stats.Get(name)
        if stat then
            if isValidObject(stat, name, false) then pushIf(pools.Object, stat.Rarity, stat.RootTemplate) end
            if isValidObject(stat, name, true)  then pushIf(pools.CombatObject, stat.Rarity, stat.RootTemplate) end
        end
    end

    for _, name in ipairs(Ext.Stats.GetStats("Armor") or {}) do
        local stat = Ext.Stats.Get(name)
        if stat and isValidArmor(stat, name) then pushIf(pools.Armor, stat.Rarity, stat.RootTemplate) end
    end

    for _, name in ipairs(Ext.Stats.GetStats("Weapon") or {}) do
        local stat = Ext.Stats.Get(name)
        if stat and isValidWeapon(stat, name) then pushIf(pools.Weapon, stat.Rarity, stat.RootTemplate) end
    end

    local function fmt(b)
        return string.format("%d/%d/%d/%d/%d", #b.Common, #b.Uncommon, #b.Rare, #b.VeryRare, #b.Legendary)
    end
    print(string.format("[Encounters] Loot pools (C/U/R/VR/L): Object=%s CombatObject=%s Weapon=%s Armor=%s",
        fmt(pools.Object), fmt(pools.CombatObject), fmt(pools.Weapon), fmt(pools.Armor)))
end

local function poolsLazy()
    if not pools then buildPools() end
    return pools
end

local function pickRarity(rates)
    local total = 0
    for _, w in pairs(rates) do total = total + w end
    if total == 0 then return "Common" end
    local r = math.random() * total
    local cum = 0
    for rarity, w in pairs(rates) do
        cum = cum + w
        if r < cum then return rarity end
    end
    return "Common"
end

local function pickFromPool(category, rarity)
    local p = poolsLazy()
    local list = p[category] and p[category][rarity]
    if not list or #list == 0 then return nil end
    return list[math.random(#list)]
end

local function pickFromPoolUniform(category)
    local p = poolsLazy()
    local cat = p[category]
    if not cat then return nil end
    local flat = {}
    for _, list in pairs(cat) do
        for _, item in ipairs(list) do table.insert(flat, item) end
    end
    if #flat == 0 then return nil end
    return flat[math.random(#flat)]
end

local function spawnItem(rootTemplate, x, y, z)
    local jx = x + (math.random() * 2 - 1) * 0.5
    local jz = z + (math.random() * 2 - 1) * 0.5
    local guid = Osi.CreateAt(rootTemplate, jx, y, jz, 0, 1, "")
    if not guid or guid == "" then return nil end
    Osi.RequestPing(jx, y, jz, guid, "")
    return guid
end

function Loot.dropOnKill(corpseGuid)
    local x, y, z = Osi.GetPosition(corpseGuid)
    if not x then return 0 end
    local rootTemplate = pickFromPoolUniform("Object")
    if not rootTemplate then
        print("[Encounters] kill loot: Object pool empty")
        return 0
    end
    if spawnItem(rootTemplate, x, y, z) then
        print(string.format("[Encounters] kill loot dropped: %s", rootTemplate))
        return 1
    end
    return 0
end

function Loot.dropEncounterPile(host, rolls)
    host = host or Osi.GetHostCharacter()
    rolls = rolls or 4
    local x, y, z = Osi.GetPosition(host)
    if not x then return 0 end

    local dropped = 0
    local lastCategory = nil
    local categoryRatesKey = {CombatObject = "Objects", Weapon = "Weapons", Armor = "Armor"}

    for _ = 1, rolls do
        local category = CATEGORY_MIX[math.random(#CATEGORY_MIX)]
        if category == lastCategory then
            category = CATEGORY_MIX[math.random(#CATEGORY_MIX)]
        end
        lastCategory = category

        local rarity = pickRarity(LOOT_RATES[categoryRatesKey[category]])
        local rootTemplate = pickFromPool(category, rarity)
        if rootTemplate and spawnItem(rootTemplate, x, y, z) then
            print(string.format("[Encounters] pile drop: %s %s %s", category, rarity, rootTemplate))
            dropped = dropped + 1
        end
    end
    print(string.format("[Encounters] pile complete: %d/%d items", dropped, rolls))
    return dropped
end
