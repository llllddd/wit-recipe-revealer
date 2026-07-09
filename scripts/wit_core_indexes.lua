-- wit_core_indexes: 配方、烹饪、图鉴与来源索引
--
-- 这里集中构建 WIT.by_product / WIT.by_material / WIT.cook_* / WIT.entity_loot。
-- UI 层只读这些索引，不直接扫描 AllRecipes、scrapbookdata 或 LootTables。

-- ============================
-- 索引构建 (from wit_build.lua)
-- ============================

local FALLBACK_CARD_DEF = {
    ["asparagussoup"] = {ingredients = {{"asparagus",1}, {"carrot",2}, {"corn",1}} },
    ["baconeggs"] = {ingredients = {{"monstermeat",1}, {"smallmeat",1}, {"egg",2}} },
    ["bananajuice"] = {ingredients = {{"cave_banana",2}, {"berries",2}} },
    ["barnaclepita"] = {ingredients = {{"barnacle",1}, {"carrot",1}, {"berries",2}} },
    ["barnaclinguine"] = {ingredients = {{"barnacle",2}, {"carrot",1}, {"corn",1}} },
    ["beefalotreat"] = {ingredients = {{"twigs",1}, {"forgetmelots",1}, {"acorn",1}, {"twigs",1}} },
    ["bonestew"] = {ingredients = {{"meat",3}, {"berries",1}} },
    ["bunnystew"] = {ingredients = {{"smallmeat",1}, {"ice",2}, {"berries",1}} },
    ["ceviche"] = {ingredients = {{"fishmeat",2}, {"ice",2}} },
    ["batnosehat"] = {ingredients = {{"batnose",1}, {"kelp",1}, {"butter",1}, {"berries",1}} },
    ["dustmeringue"] = {ingredients = {{"refined_dust",1}, {"berries",3}} },
    ["figatoni"] = {ingredients = {{"fig",1}, {"carrot",1}, {"corn",1}, {"berries",1}} },
    ["flowersalad"] = {ingredients = {{"cactus_flower",1}, {"carrot",2}, {"corn",1}} },
    ["frognewton"] = {ingredients = {{"fig",1}, {"froglegs",1}, {"berries",2}} },
    ["frozenbananadaiquiri"] = {ingredients = {{"cave_banana",1}, {"ice",1}, {"berries",2}} },
    ["fruitmedley"] = {ingredients = {{"dragonfruit",3}, {"berries",1}} },
    ["icecream"] = {ingredients = {{"ice",1}, {"butter",1}, {"honey",1}, {"berries",1}} },
    ["jammypreserves"] = {ingredients = {{"berries",4}} },
    ["jellybean"] = {ingredients = {{"royal_jelly",1}, {"berries",3}} },
    ["justeggs"] = {ingredients = {{"egg",3}, {"berries",1}} },
    ["koalefig_trunk"] = {ingredients = {{"trunk_summer",1}, {"fig",1}, {"berries",2}} },
    ["leafloaf"] = {ingredients = {{"plantmeat",2}, {"berries",2}} },
    ["leafymeatburger"] = {ingredients = {{"plantmeat",1}, {"onion",1}, {"carrot",1}, {"corn",1}} },
    ["leafymeatsouffle"] = {ingredients = {{"plantmeat",2}, {"honey",2}} },
    ["lobsterbisque"] = {ingredients = {{"wobster_sheller_land",1}, {"ice",1}, {"berries",2}} },
    ["lobsterdinner"] = {ingredients = {{"wobster_sheller_land",1}, {"butter",1}, {"smallmeat",1}, {"berries",1}} },
    ["mandrakesoup"] = {ingredients = {{"mandrake",1}, {"berries",3}} },
    ["mashedpotatoes"] = {ingredients = {{"potato",2}, {"garlic",1}, {"berries",1}} },
    ["meatballs"] = {ingredients = {{"monstermeat",1}, {"red_cap",3}} },
    ["meatysalad"] = {ingredients = {{"plantmeat",1}, {"carrot",1}, {"corn",1}, {"asparagus",1}} },
    ["monsterlasagna"] = {ingredients = {{"monstermeat",2}, {"berries",2}} },
    ["perogies"] = {ingredients = {{"smallmeat",1}, {"egg",1}, {"carrot",1}, {"berries",1}} },
    ["potatotornado"] = {ingredients = {{"potato",1}, {"twigs",1}, {"berries",2}} },
    ["ratatouille"] = {ingredients = {{"carrot",1}, {"berries",3}} },
    ["salsa"] = {ingredients = {{"tomato",1}, {"onion",1}, {"berries",2}} },
    ["seafoodgumbo"] = {ingredients = {{"fishmeat",2}, {"fishmeat_small",1}, {"ice",1}} },
    ["shroombait"] = {ingredients = {{"moon_cap",2}, {"monstermeat",1}, {"berries",1}} },
    ["shroomcake"] = {ingredients = {{"moon_cap",1}, {"red_cap",1}, {"blue_cap",1}, {"green_cap",1}} },
    ["surfnturf"] = {ingredients = {{"meat",2}, {"fishmeat",2}} },
    ["talleggs"] = {ingredients = {{"tallbirdegg",1}, {"carrot",1}, {"berries",2}} },
    ["unagi"] = {ingredients = {{"eel",1}, {"cutlichen",1}, {"berries",2}} },
    ["veggieomlet"] = {ingredients = {{"egg",2}, {"carrot",1}, {"corn",1}} },
    ["vegstinger"] = {ingredients = {{"tomato",1}, {"asparagus",1}, {"carrot",1}, {"ice",1}} },
    ["waffles"] = {ingredients = {{"butter",1}, {"egg",1}, {"berries",2}} },
    ["watermelonicle"] = {ingredients = {{"watermelon",1}, {"ice",1}, {"twigs",1}, {"berries",1}} },
    ["wetgoop"] = {ingredients = {{"monstermeat",1}, {"twigs",3}} },
}

-- 为没有 card_def 的烹饪配方推断一个可展示的四格食材组合。
--
-- 参数:
--   recipe  cooking.recipes[cooker_type][food] 中的配方对象，必须带 test 函数。
--   cooking cooking.lua 模块，提供 ingredients tag 数据。
--
-- 返回:
--   成功时返回 { ingredients = { {prefab, count}, ... } }，失败返回 nil。
--
-- 说明:
--   这是 UI 展示用的启发式推断，不是官方配方数据。它依次尝试：
--   1. 单种食材 x4；
--   2. 1 个主料 + 3 个常用填充物；
--   3. 两种食材各 x2。
--   如果未来某道菜显示不准，优先在 FALLBACK_CARD_DEF 里写死，而不是扩大这里的搜索空间。
function GenerateCardDef(recipe, cooking)
    if not recipe.test or not cooking or not cooking.ingredients then return nil end

    local fillers = {"berries", "ice", "twigs", "carrot", "corn", "red_cap", "honey"}
    local pool = {}
    for name, _ in pairs(cooking.ingredients) do
        if not name:match("_cooked$") and not name:match("_dried$") then
            table.insert(pool, name)
        end
    end
    -- 1: 单种食材 x4
    for _, name in ipairs(pool) do
        local names, tags = {[name]=4}, {}
        WIT_CORE.AccumulateIngredient(name, 4, names, tags)
        if recipe.test("cookpot", names, tags) then
            return {ingredients = {{name, 4}}}
        end
    end
    -- 2: 1 主料 + 3 填充
    for _, name in ipairs(pool) do
        for _, filler in ipairs(fillers) do
            if filler ~= name then
                local names, tags = {}, {}
                WIT_CORE.AccumulateIngredient(name, 1, names, tags)
                WIT_CORE.AccumulateIngredient(filler, 3, names, tags)
                if recipe.test("cookpot", names, tags) then
                    return {ingredients = {{name, 1}, {filler, 3}}}
                end
            end
        end
    end
    -- 3: 两两组合
    for idx1 = 1, #pool do
        for idx2 = idx1, #pool do
            local a, b = pool[idx1], pool[idx2]
            local names, tags = {}, {}
            WIT_CORE.AccumulateIngredient(a, 2, names, tags)
            WIT_CORE.AccumulateIngredient(b, 2, names, tags)
            if recipe.test("cookpot", names, tags) then
                return {ingredients = {{a, 2}, {b, 2}}}
            end
        end
    end
    return nil
end

-- 构建并缓存官方图鉴数据索引。
--
-- 生成:
--   WIT_scrapbook_entry_map_by_prefab[prefab] = entry
--   WIT_scrapbook_entry_map_by_name[name] = entry
--
-- 用途:
--   图标解析、来源页、no-spawn 导出都需要从 prefab/name 快速找到 scrapbook entry。
--
-- 注意:
--   entry.prefab 和 entry.name 不一定相同，例如:
--     prefab = "evergreen_sparse_tall"
--     name   = "evergreen_sparse"
--   所以两个索引都要保留。
function WIT_BuildScrapbookEntryMaps()
    if WIT_scrapbook_entry_map_by_prefab ~= nil
        and WIT_scrapbook_entry_map_by_name ~= nil then
        return
    end

    WIT_scrapbook_entry_map_by_prefab = {}
    WIT_scrapbook_entry_map_by_name = {}

    local ok, data = pcall(
        GLOBAL.require,
        "screens/redux/scrapbookdata"
    )

    if not ok or type(data) ~= "table" then
        print("[WIT] failed to load scrapbookdata:", data)
        return
    end

    for _, entry in pairs(data) do
        if type(entry) == "table" then

            -- prefab 索引：
            -- entry.prefab = "evergreen_sparse_tall"
            if type(entry.prefab) == "string"
                and entry.prefab ~= "" then

                WIT_scrapbook_entry_map_by_prefab[entry.prefab] = entry
            end

            -- name 索引：
            -- entry.name = "evergreen_sparse"
            if type(entry.name) == "string"
                and entry.name ~= "" then

                -- 同一个 name 可能对应多个 entry。
                -- 默认保留第一个，避免后面的随机覆盖前面的。
                if WIT_scrapbook_entry_map_by_name[entry.name] == nil then
                   WIT_scrapbook_entry_map_by_name[entry.name] = entry
                end
            end
        end
    end
end


-- 构建 WIT 运行期核心索引。
--
-- 生成:
--   WIT.by_product[product]      -> recipe[]
--   WIT.by_material[ingredient]  -> recipe[]
--   WIT.cook_foods[food]         -> cooking recipe
--   WIT.cook_by_ingredient[item] -> cooking recipe[]
--   WIT.ingredient_tags[item]    -> cooking tag table
--
-- 调用时机:
--   UI 打开、点击来源/用途、自动填锅前都会调用。函数内部用 WIT_data_built 防止重复构建。
--
-- 注意:
--   wetgoop 不是 cooking.recipes 里的普通配方，所以这里会手动注入一个 frecipe-like 对象，
--   让“湿腻焦糊”也能出现在用途/来源查询里。
function BuildIndexes()
    WIT_BuildScrapbookEntryMaps()
    if WIT_data_built then return end
    WIT_data_built = true
    for rname, recipe in pairs(AllRecipes) do
        local prod = recipe.product or rname
        WIT.by_product[prod] = WIT.by_product[prod] or {}
        table.insert(WIT.by_product[prod], recipe)
        for _, ing in ipairs(recipe.ingredients or {}) do
            if type(ing.type) == "string" then
                WIT.by_material[ing.type] = WIT.by_material[ing.type] or {}
                table.insert(WIT.by_material[ing.type], recipe)
            end
        end
    end
    local cooking = WIT_CORE.GetCooking()
    if cooking ~= nil then
        for _, recipes in pairs(cooking.cookbook_recipes or {}) do
            for fname, frecipe in pairs(recipes) do
                WIT.cook_foods[fname] = frecipe
            end
        end
        for iname, idata in pairs(cooking.ingredients or {}) do
            WIT.ingredient_tags[iname] = idata.tags
        end
        for _, cooker_type in ipairs({"cookpot", "portablecookpot"}) do
            for fname, frecipe in pairs(cooking.recipes[cooker_type] or {}) do
                if frecipe.test and not frecipe.card_def then
                    frecipe.card_def = FALLBACK_CARD_DEF[fname]
                end
                if frecipe.test and not frecipe.card_def then
                    frecipe.card_def = GenerateCardDef(frecipe, cooking)
                end
                if not WIT.cook_foods[fname] then
                    WIT.cook_foods[fname] = frecipe
                end
                if frecipe.test and frecipe.card_def and frecipe.card_def.ingredients then
                    for iname, _ in pairs(cooking.ingredients or {}) do
                        local item_tags = WIT.ingredient_tags[iname]
                        if item_tags then
                            for slot_idx = 1, #frecipe.card_def.ingredients do
                                local names, tags = {}, {}
                                for j, ci in ipairs(frecipe.card_def.ingredients) do
                                    local n = ci[1]
                                    if j == slot_idx then n = iname end
                                    WIT_CORE.AccumulateIngredient(n, ci[2], names, tags)
                                end
                                if frecipe.test("cookpot", names, tags) then
                                    WIT.cook_by_ingredient[iname] = WIT.cook_by_ingredient[iname] or {}
                                    local exists = false
                                    for _, r in ipairs(WIT.cook_by_ingredient[iname]) do
                                        if r.name == fname then exists = true; break end
                                    end
                                    if not exists then table.insert(WIT.cook_by_ingredient[iname], frecipe) end
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end

        -- 潮湿黏糊：cookpot 的"无匹配兜底"产物
        -- cooking.recipes 中没有 wetgoop 的 recipe 定义（cookpot 自己在 cookfn 中处理），
        -- 因此不会被上面的遍历自动收录。手动注入 frecipe-like 对象，
        -- 让它进入 WIT.cook_foods 与食材反查表。
        local wetgoop_def = FALLBACK_CARD_DEF["wetgoop"]
        if wetgoop_def and wetgoop_def.ingredients and not WIT.cook_foods["wetgoop"] then
            local wetgoop_frecipe = { name = "wetgoop", card_def = wetgoop_def }
            WIT.cook_foods["wetgoop"] = wetgoop_frecipe
            for _, ci in ipairs(wetgoop_def.ingredients) do
                WIT.cook_by_ingredient[ci[1]] = WIT.cook_by_ingredient[ci[1]] or {}
                local exists = false
                for _, r in ipairs(WIT.cook_by_ingredient[ci[1]]) do
                    if r.name == "wetgoop" then exists = true; break end
                end
                if not exists then table.insert(WIT.cook_by_ingredient[ci[1]], wetgoop_frecipe) end
            end
        end
    end
    BuildSourceIndexes()
end

-- ============================
-- 来源索引构建 (SOURCES tab data)
-- ============================
-- WIT.entity_loot[entity_prefab] = { {prefab, count, chance, type}, ... }
-- 数据来源：图鉴数据 deps + GLOBAL.LootTables（含概率）
-- 不硬编码、不主动 SpawnPrefab、不运行时钩子
WIT.entity_loot = {}

-- 判断 scrapbook entry 是否应该作为“来源实体”参与 SOURCES 页。
--
-- 参数:
--   entry scrapbookdata 中的一条记录。
--
-- 返回:
--   true  表示它可能产生掉落/采集/工作产物。
--   false 表示它只是物品/食物/纯展示条目，不应作为来源。
--
-- 注意:
--   图鉴 type 很宽泛，thing/pointsofinterest 不一定都有掉落；这里偏宽松，
--   后续 BuildSourceIndexes 会再根据 LootTables/deps 过滤出真正有产物的条目。
local function _IsSourceEntity(entry)
    -- 纯物品/食物不是"来源实体"，排除它们（如疙瘩树果 oceantreenut 是 item 类型）
    if entry.type == "item" or entry.type == "food" then return false end
    if entry.pickable then return true end
    if entry.workable == "MINE" or entry.workable == "CHOP" or entry.workable == "DIG" or entry.workable == "HAMMER" then return true end
    if entry.type == "creature" or entry.type == "giant" or entry.type == "thing" or entry.type == "pointsofinterest" then return true end
    return false
end

-- 把 scrapbook entry 的交互信息归一化成 WIT 使用的来源类型。
--
-- 返回值用于 UI 图标/文本展示:
--   pick   可采集
--   mine   可挖矿
--   chop   可砍伐
--   dig    可挖掘
--   hammer 可锤拆
--   drop   生物/其它掉落
--
-- 注意:
--   pickable 优先级最高，因为有些可采集实体也可能带其它分类字段。
local function _ResolveSourceType(entry)
    if entry.pickable then return "pick" end
    if entry.workable == "MINE" then return "mine" end
    if entry.workable == "CHOP" then return "chop" end
    if entry.workable == "DIG" then return "dig" end
    if entry.workable == "HAMMER" then return "hammer" end
    return "drop"
end

-- 构建“实体来源 -> 产物列表”的索引。
--
-- 生成:
--   WIT.entity_loot[source_prefab] = {
--       { prefab = product_prefab, count = n, chance = p, type = "drop/chop/..." },
--       ...
--   }
--
-- 数据来源优先级:
--   1. GLOBAL.LootTables：最可靠，包含概率。
--   2. SETLOOT_LOOT 手动补丁：处理使用 SetLoot 但不进 LootTables 的实体。
--   3. 可制作建筑锤拆返还：按配方材料 50% 估算。
--   4. scrapbook deps：兜底固定产物，过滤 cooking station 的“内部产物”反向依赖。
--
-- 注意:
--   这个函数不 SpawnPrefab，只读静态数据，避免触发世界逻辑。
--   如果来源页误把“能制作的菜”当成“锤掉落”，优先检查 cooker_outputs 过滤逻辑。
function BuildSourceIndexes()
    local scrap_data_ok, scrap_data = pcall(GLOBAL.require, "screens/redux/scrapbookdata")
    if not (scrap_data_ok and type(scrap_data) == "table") then return end

    -- 通用规则：构建"该实体作为 cooking station 时能产出的全部菜肴"集合
    -- 用于过滤 deps 中的反向依赖（HAMMER/cooker 类容器实体的 deps 通常是"在自己内部做的东西"，
    -- 不是"被自己锤击后掉落的东西"，例如 cookpot 的 deps 是它能做的菜肴而不是它掉落的材料）
    local cooking = WIT_CORE.GetCooking()
    local cooker_outputs = {}  -- cooker_type -> {food1, food2, ...}
    if cooking and cooking.recipes then
        for cooker_type, recipes in pairs(cooking.recipes) do
            if type(recipes) == "table" then
                for fname, _ in pairs(recipes) do
                    if type(fname) == "string" then
                        cooker_outputs[cooker_type] = cooker_outputs[cooker_type] or {}
                        table.insert(cooker_outputs[cooker_type], fname)
                    end
                end
            end
        end
    end

    for _, entry in pairs(scrap_data) do
        if type(entry) == "table" and entry.prefab and entry.tex then
            local prefab = entry.prefab

            -- 优先用 GLOBAL.LootTables（含精确概率，来源可靠）
            local lt = GLOBAL.LootTables and GLOBAL.LootTables[prefab]
            if lt and #lt > 0 then
                local src_type = _ResolveSourceType(entry)
                -- 合并同一 prefab 的多次掉落（DST 用重复条目表示数量）
                local merged = {}
                for _, v in ipairs(lt) do
                    local prod, chance = v[1], v[2]
                    if prod and chance and chance > 0 then
                        if not merged[prod] then merged[prod] = {} end
                        table.insert(merged[prod], chance)
                    end
                end
                local loots = {}
                for prod, chances in pairs(merged) do
                    local guaranteed = 0
                    for _, c in ipairs(chances) do
                        if c >= 1.0 then guaranteed = guaranteed + 1
                        else table.insert(loots, { prefab = prod, count = 1, chance = c, type = src_type }) end
                    end
                    if guaranteed > 0 then
                        table.insert(loots, { prefab = prod, count = guaranteed, chance = 1.0, type = src_type })
                    end
                end
                if #loots > 0 then WIT.entity_loot[prefab] = loots end
            elseif ({ koalefant_summer = true, koalefant_winter = true, tallbird = true, grassgator = true,
                leif = true, leif_sparse = true, spiderqueen = true, perd = true, pigman = true,
                beehive = true, wasphive = true, hotspring = true, pigtorch = true,
                mermking = true, gnarwail = true, rocky = true, babybeefalo = true,
                bunnyman = true, beardlord = true, spiderden = true, livingtree = true,
                gingerbreadpig = true, cave_entrance = true, resurrectionstone = true,
                oceantree_pillar = true, fence = true, perdshrine = true, frog = true,
                mole = true, smallbird = true, ghost = true, knight = true,
                bishop = true, rook = true, nightmarecreature = true,
                merm = true, mermguard = true, monkey = true, rabbit = true,
                rock_avocado_fruit = true, moon_altar = true, moon_altar_pieces = true,
                moondial = true, rubble = true, driftwood_trees = true,
                marsh_tree = true, statueruins = true, lureplant = true,
                decor_flowervase = true, endtable = true, canary_poisoned = true,
                lunarthrall_plant = true, iceboxtest = true, dragonfly_chest = true,
                shadowcreature = true, oceanshadowcreature = true })[prefab] then
                -- SetLoot 修正：使用 inst.components.lootdropper:SetLoot 的实体
                -- 数据不进入 GLOBAL.LootTables，scrapbook deps 又只列一次丢失实际数量
                local SETLOOT_LOOT = {
                    koalefant_summer = { { prefab = "meat", count = 8 }, { prefab = "trunk_summer", count = 1 } },
                    koalefant_winter = { { prefab = "meat", count = 8 }, { prefab = "trunk_winter", count = 1 } },
                    tallbird = { { prefab = "meat", count = 2 } },
                    grassgator = { { prefab = "plantmeat", count = 7 }, { prefab = "cutgrass", count = 2 }, { prefab = "twigs", count = 2 } },
                    leif = { { prefab = "livinglog", count = 6 }, { prefab = "monstermeat", count = 1 } },
                    leif_sparse = { { prefab = "livinglog", count = 6 }, { prefab = "monstermeat", count = 1 } },
                    spiderqueen = { { prefab = "monstermeat", count = 4 }, { prefab = "silk", count = 4 }, { prefab = "spidereggsack", count = 1 }, { prefab = "spiderhat", count = 1 } },
                    perd = { { prefab = "drumstick", count = 2 } },
                    pigman = { { prefab = "meat", count = 2 }, { prefab = "pigskin", count = 1 } },
                    beehive = { { prefab = "honey", count = 3 }, { prefab = "honeycomb", count = 1 } },
                    wasphive = { { prefab = "honey", count = 3 }, { prefab = "honeycomb", count = 1 } },
                    hotspring = { { prefab = "moonglass", count = 5 } },
                    pigtorch = { { prefab = "log", count = 3 }, { prefab = "poop", count = 1 } },
                    mermking = { { prefab = "pondfish", count = 1 }, { prefab = "froglegs", count = 1 }, { prefab = "kelp", count = 4 } },
                    gnarwail = { { prefab = "fishmeat", count = 4 } },
                    rocky = { { prefab = "rocks", count = 2 }, { prefab = "meat", count = 1 }, { prefab = "flint", count = 2 } },
                    babybeefalo = { { prefab = "smallmeat", count = 3 }, { prefab = "beefalowool", count = 1 } },
                    bunnyman = { { prefab = "smallmeat", count = 1 } },
                    beardlord = { { prefab = "beardhair", count = 2 }, { prefab = "monstermeat", count = 1 } },
                    spiderden = { { prefab = "silk", count = 4 }, { prefab = "spidereggsack", count = 1 } },
                    livingtree = { { prefab = "livinglog", count = 2 } },
                    gingerbreadpig = { { prefab = "wintersfeastfuel", count = 1 }, { prefab = "crumbs", count = 3 } },
                    cave_entrance = { { prefab = "rocks", count = 2 }, { prefab = "flint", count = 3 } },
                    resurrectionstone = { { prefab = "rocks", count = 2 }, { prefab = "marble", count = 2 }, { prefab = "nightmarefuel", count = 1 } },
                    oceantree_pillar = { { prefab = "log", count = 4 }, { prefab = "twigs", count = 3 } },
                    fence = { { prefab = "twigs", count = 1 } },
                    perdshrine = { { prefab = "ash", count = 1 } },
                    frog = { { prefab = "froglegs", count = 1 } },
                    mole = { { prefab = "smallmeat", count = 1 } },
                    smallbird = { { prefab = "smallmeat", count = 1 } },
                    ghost = { { prefab = "nightmarefuel", count = 1 } },
                    knight = { { prefab = "gears", count = 1 } },
                    bishop = { { prefab = "gears", count = 1 } },
                    rook = { { prefab = "gears", count = 1 } },
                    nightmarecreature = { { prefab = "nightmarefuel", count = 1 } },
                    merm = { { prefab = "pondfish", count = 1 }, { prefab = "froglegs", count = 1 } },
                    mermguard = { { prefab = "pondfish", count = 1 }, { prefab = "froglegs", count = 1 } },
                    monkey = { { prefab = "smallmeat", count = 1 }, { prefab = "cave_banana", count = 1 } },
                    rabbit = { { prefab = "smallmeat", count = 1 } },
                    rock_avocado_fruit = { { prefab = "rock_avocado_fruit_sprout", count = 1 } },
                    moondial = { { prefab = "moonglass", count = 1 } },
                    rubble = { { prefab = "rocks", count = 1 } },
                    driftwood_trees = { { prefab = "charcoal", count = 1 } },
                    marsh_tree = { { prefab = "charcoal", count = 1 } },
                    statueruins = { { prefab = "thulecite", count = 1 } },
                    lureplant = { { prefab = "lureplantbulb", count = 1 } },
                    decor_flowervase = { { prefab = "spoiled_food", count = 1 } },
                    endtable = { { prefab = "spoiled_food", count = 1 } },
                    canary_poisoned = { { prefab = "spoiled_food", count = 1 } },
                    lunarthrall_plant = { { prefab = "lunarplant_husk", count = 2 }, { prefab = "plantmeat", count = 2 } },
                    dragonfly_chest = { { prefab = "alterguardianhatshard", count = 1 } },
                    shadowcreature = { { prefab = "nightmarefuel", count = 1 } },
                    oceanshadowcreature = { { prefab = "nightmarefuel", count = 1 } },
                }
                local sll = SETLOOT_LOOT[prefab]
                if sll then
                    local src_type = _ResolveSourceType(entry)
                    local loots = {}
                    for _, item in ipairs(sll) do
                        table.insert(loots, { prefab = item.prefab, count = item.count, chance = 1.0, type = src_type })
                    end
                    if #loots > 0 then WIT.entity_loot[prefab] = loots end
                end
            elseif GLOBAL.AllRecipes[prefab] and _ResolveSourceType(entry) == "hammer" then
                -- 锤拆返还：可制作建筑被锤拆后返还 50% 制作材料（四舍五入取整）
                local recipe = GLOBAL.AllRecipes[prefab]
                local loots = {}
                for _, ing in ipairs(recipe.ingredients or {}) do
                    local ing_type = type(ing) == "table" and ing.type or ing
                    local ing_amount = type(ing) == "table" and (ing.amount or 1) or 1
                    if type(ing_type) == "string" and ing_type ~= "" then
                        local count = math.max(1, math.floor(ing_amount * 0.5 + 0.5))
                        table.insert(loots, { prefab = ing_type, count = count, chance = 1.0, type = "hammer" })
                    end
                end
                if #loots > 0 then WIT.entity_loot[prefab] = loots end
            elseif entry.deps and type(entry.deps) == "table" and #entry.deps > 0 and _IsSourceEntity(entry) then
                -- 无 LootTables 时使用 deps，合并重复的固定掉落
                -- 通用规则：若该实体是某个 cooking station 类型（HAMMER 容器类），
                -- 过滤掉"作为该 station 产物"的反向依赖，避免把"内部能做的菜肴"当作"锤击掉落"
                local src_type = _ResolveSourceType(entry)
                local filtered_deps = {}
                if src_type == "hammer" and cooker_outputs[prefab] then
                    local outputs = {}
                    for _, f in ipairs(cooker_outputs[prefab]) do outputs[f] = true end
                    for _, dep in ipairs(entry.deps) do
                        if type(dep) == "string" and not outputs[dep] then
                            table.insert(filtered_deps, dep)
                        end
                    end
                else
                    for _, dep in ipairs(entry.deps) do
                        if type(dep) == "string" then table.insert(filtered_deps, dep) end
                    end
                end
                local merged = {}
                for _, dep in ipairs(filtered_deps) do
                    merged[dep] = (merged[dep] or 0) + 1
                end
                local loots = {}
                for dep, count in pairs(merged) do
                    table.insert(loots, { prefab = dep, count = count, type = src_type })
                end
                if #loots > 0 then WIT.entity_loot[prefab] = loots end
            end
        end
    end

    local count = 0; for _ in pairs(WIT.entity_loot) do count = count + 1 end
    print("[WIT] BuildSourceIndexes done, entities:", count)
end

-- 硬编码烹饪条件表（基于玩家提供的精确数据）
local HARDCODED_CONDITIONS = {
    ["baconeggs"] = {{"meat",">1.0"}, {"egg",">1.0"}, {"veggie","=="}},
    ["bananajuice"] = {{"cave_banana/cave_banana_cooked","×2"}, {"meat","=="}, {"monster","=="}, {"fish","=="}},
    ["barnaclepita"] = {{"barnacle/barnacle_cooked","+1"}, {"veggie","≥0.5"}},
    ["barnaclesushi"] = {{"barnacle/barnacle_cooked","+1"}, {"kelp/kelp_cooked","+1"}, {"egg","≥1.0"}},
    ["barnaclinguine"] = {{"barnacle/barnacle_cooked","×2"}, {"veggie","≥2.0"}},
    ["bananapop"] = {{"cave_banana/cave_banana_cooked","+1"}, {"frozen",">0"}, {"twigs","+1"}, {"meat","=="}, {"fish","=="}},
    ["barnaclestuffedfishhead"] = {{"barnacle/barnacle_cooked","+1"}, {"fish","≥1.25"}},
    ["batnosehat"] = {{"batnose","+1"}, {"kelp","+1"}, {"dairy","≥1.0"}},
    ["beefalofeed"] = {{"inedible",">0"}, {"monster","=="}, {"meat","=="}, {"fish","=="}, {"egg","=="}, {"fat","=="}, {"dairy","=="}, {"magic","=="}},
    ["beefalotreat"] = {{"forgetmelots/forgetmelots_dried","+1"}, {"seed",">0"}, {"monster","=="}, {"meat","=="}, {"fish","=="}, {"egg","=="}, {"fat","=="}, {"dairy","=="}, {"magic","=="}},
    ["bonestew"] = {{"meat","≥3.0"}, {"inedible","=="}},
    ["bunnystew"] = {{"meat",">0"}, {"meat","<1.0"}, {"frozen","≥2"}, {"inedible","=="}},
    ["butterflymuffin"] = {{"butterflywings/moonbutterflywings","+1"}, {"veggie","≥0.5"}, {"meat","=="}},
    ["californiaroll"] = {{"kelp/kelp_cooked/kelp_dried","×2"}, {"fish","≥1.0"}},
    ["dragonpie"] = {{"dragonfruit/dragonfruit_cooked","+1"}, {"meat","=="}},
    ["figkabab"] = {{"fig/fig_cooked","+1"}, {"meat","≥1.0"}, {"twigs","+1"}, {"monster","≤1"}},
    ["fishtacos"] = {{"corn/corn_cooked/oceanfish_small_5_inv/oceanfish_medium_5_inv","+1"}, {"fish",">0"}},
    ["fishsticks"] = {{"fish",">0"}, {"twigs","+1"}, {"inedible",">0"}, {"inedible","≤1"}},
    ["flowersalad"] = {{"cactus_flower","+1"}, {"veggie","≥2.0"}, {"meat","=="}, {"fruit","=="}, {"egg","=="}, {"sweetener","=="}, {"inedible","=="}},
    ["frogglebunwich"] = {{"froglegs/froglegs_cooked","+1"}, {"veggie","≥0.5"}},
    ["fruitmedley"] = {{"fruit","≥3.0"}, {"meat","=="}, {"veggie","=="}},
    ["guacamole"] = {{"mole","+1"}, {"cactus_meat/rock_avocado_fruit_ripe","+1"}, {"fruit","=="}},
    ["honeyham"] = {{"honey","+1"}, {"meat",">1.5"}, {"inedible","=="}},
    ["honeynuggets"] = {{"honey","+1"}, {"meat",">0"}, {"meat","≤1.5"}, {"inedible","=="}},
    ["hotchili"] = {{"meat","≥1.5"}, {"veggie","≥1.5"}},
    ["icecream"] = {{"sweetener",">0"}, {"dairy",">0"}, {"frozen",">0"}, {"meat","=="}, {"veggie","=="}, {"egg","=="}, {"inedible","=="}},
    ["jammypreserves"] = {{"fruit",">0"}, {"meat","=="}, {"veggie","=="}, {"inedible","=="}},
    ["jellybean"] = {{"royal_jelly","+1"}, {"monster","=="}, {"inedible","=="}},
    ["justeggs"] = {{"egg","≥3.0"}},
    ["kabobs"] = {{"twigs","+1"}, {"meat",">0"}, {"monster","≤1"}, {"inedible","≤1"}},
    ["koalefig_trunk"] = {{"trunk_summer/trunk_winter/trunk_cooked","+1"}, {"fig/fig_cooked","+1"}},
    ["leafloaf"] = {{"plantmeat/plantmeat_cooked","×2"}},
    ["leafymeatburger"] = {{"plantmeat/plantmeat_cooked","+1"}, {"onion/onion_cooked","+1"}, {"veggie","≥2.0"}},
    ["leafymeatsouffle"] = {{"plantmeat/plantmeat_cooked","×2"}, {"sweetener","≥2.0"}},
    ["lobsterbisque"] = {{"wobster_sheller_land","+1"}, {"ice","+1"}},
    ["lobsterdinner"] = {{"wobster_sheller_land","+1"}, {"butter","+1"}, {"meat","≥1.0"}, {"fish","≥1.0"}, {"frozen","=="}},
    ["mandrakesoup"] = {{"mandrake","+1"}},
    ["mashedpotatoes"] = {{"potato/potato_cooked","×2"}, {"garlic/garlic_cooked","+1"}, {"meat","=="}, {"inedible","=="}},
    ["meatballs"] = {{"meat",">0"}, {"inedible","=="}},
    ["meatysalad"] = {{"plantmeat/plantmeat_cooked","+1"}, {"veggie","≥3.0"}},
    ["monsterlasagna"] = {{"monster","≥2"}, {"inedible","=="}},
    ["pepperpopper"] = {{"pepper/pepper_cooked","+1"}, {"meat",">0"}, {"meat","≤1.5"}, {"inedible","=="}},
    ["perogies"] = {{"egg",">0"}, {"meat",">0"}, {"veggie","≥0.5"}, {"inedible","=="}},
    ["potatotornado"] = {{"potato/potato_cooked","+1"}, {"twigs","+1"}, {"monster","≤1"}, {"inedible","≤2"}, {"meat","=="}},
    ["powcake"] = {{"twigs","+1"}, {"honey","+1"}, {"corn/corn_cooked/oceanfish_small_5_inv/oceanfish_medium_5_inv","+1"}},
    ["pumpkincookie"] = {{"pumpkin/pumpkin_cooked","+1"}, {"sweetener","≥2.0"}},
    ["ratatouille"] = {{"veggie","≥0.5"}, {"meat","=="}, {"inedible","=="}},
    ["salsa"] = {{"tomato/tomato_cooked","+1"}, {"onion/onion_cooked","+1"}, {"meat","=="}, {"egg","=="}, {"inedible","=="}},
    ["shroomcake"] = {{"moon_cap","+1"}, {"red_cap","+1"}, {"blue_cap","+1"}, {"green_cap","+1"}},
    ["stuffedeggplant"] = {{"eggplant/eggplant_cooked","+1"}, {"veggie",">1.0"}},
    ["surfnturf"] = {{"meat","≥2.5"}, {"fish","≥1.5"}, {"frozen","=="}},
    ["sweettea"] = {{"forgetmelots/forgetmelots_dried","+1"}, {"sweetener",">0"}, {"frozen",">0"}, {"monster","=="}, {"veggie","=="}, {"meat","=="}, {"fish","=="}, {"egg","=="}, {"fat","=="}, {"dairy","=="}, {"inedible","=="}},
    ["taffy"] = {{"sweetener","≥3.0"}, {"meat","=="}},
    ["trailmix"] = {{"acorn/acorn_cooked","+1"}, {"seed","≥1"}, {"berries/berries_cooked/berries_juicy/berries_juicy_cooked","+1"}, {"fruit","≥1.0"}, {"meat","=="}, {"veggie","=="}, {"egg","=="}, {"dairy","=="}},
    ["turkeydinner"] = {{"drumstick","×2"}, {"meat",">1.0"}, {"fruit/veggie",">0"}},
    ["unagi"] = {{"eel/eel_cooked/pondeel","+1"}, {"cutlichen/kelp/kelp_cooked/kelp_dried","+1"}},
    ["vegstinger"] = {{"asparagus/asparagus_cooked/tomato/tomato_cooked","+1"}, {"veggie",">2.0"}, {"frozen","≥1.0"}, {"meat","=="}, {"egg","=="}, {"inedible","=="}},
    ["waffles"] = {{"butter","+1"}, {"berries/berries_cooked/berries_juicy/berries_juicy_cooked","+1"}, {"egg",">0"}},
    ["watermelonicle"] = {{"watermelon","+1"}, {"twigs","+1"}, {"frozen",">0"}, {"meat","=="}, {"veggie","=="}, {"egg","=="}},
    ["frognewton"] = {{"fig/fig_cooked","+1"}, {"froglegs/froglegs_cooked","+1"}},
    ["figatoni"] = {{"fig/fig_cooked","+1"}, {"veggie","≥2.0"}, {"meat","=="}},
    ["frozenbananadaiquiri"] = {{"cave_banana/cave_banana_cooked","+1"}, {"frozen","≥1.0"}, {"meat","=="}, {"fish","=="}},
    ["asparagussoup"] = {{"asparagus/asparagus_cooked","+1"}, {"veggie",">2.0"}, {"meat","=="}, {"inedible","=="}},
    ["ceviche"] = {{"fish","≥2.0"}, {"frozen",">0"}, {"egg","=="}, {"inedible","=="}},
    ["seafoodgumbo"] = {{"fish",">2.0"}},
    ["talleggs"] = {{"tallbirdegg","+1"}, {"veggie","≥1.0"}},
    ["veggieomlet"] = {{"egg","≥1.0"}, {"veggie","≥1.0"}, {"meat","=="}, {"dairy","=="}},
    -- wetgoop 不在此处占位：它本身无 cooking 配方（不是 cooking.lua 中的产物），
    -- 玩家按 U 查询时会走 turfcraftingstation 的制作路径，不依赖此处的硬编码
    ["dustmeringue"] = {{"refined_dust","+1"}},
    ["shroombait"] = {{"moon_cap","×2"}, {"monstermeat","+1"}},
    -- 沃利便携锅专属
    ["voltgoatjelly"] = {{"lightninggoathorn","+1"}, {"sweetener","≥2.0"}, {"meat","=="}},
    ["glowberrymousse"] = {{"wormlight/wormlight_lesser","+1"}, {"fruit","≥2.0"}, {"meat","=="}, {"inedible","=="}},
    ["frogfishbowl"] = {{"froglegs/froglegs_cooked","×2"}, {"fish","≥1.0"}, {"inedible","=="}},
    ["gazpacho"] = {{"asparagus/asparagus_cooked","×2"}, {"frozen","≥2.0"}},
    ["potatosouffle"] = {{"potato/potato_cooked","×2"}, {"egg",">0"}, {"meat","=="}, {"inedible","=="}},
    ["monstertartare"] = {{"monster","≥2.0"}, {"inedible","=="}},
    ["freshfruitcrepes"] = {{"honey","+1"}, {"butter","+1"}, {"fruit","≥1.5"}},
    ["bonesoup"] = {{"boneshard","×2"}, {"onion/onion_cooked","+1"}, {"inedible",">0"}, {"inedible","<3"}},
    ["moqueca"] = {{"fish",">0"}, {"onion/onion_cooked","+1"}, {"tomato/tomato_cooked","+1"}, {"inedible","=="}},
    ["nightmarepie"] = {{"nightmarefuel","×2"}, {"potato/potato_cooked","+1"}, {"onion/onion_cooked","+1"}},
    ["dragonchilisalad"] = {{"dragonfruit/dragonfruit_cooked","+1"}, {"pepper/pepper_cooked","+1"}, {"meat","=="}, {"egg","=="}, {"inedible","=="}},
}

-- 格式化硬编码烹饪条件里的比较符和值。
--
-- 参数:
--   v 形如 "==", ">1.0", "≥2", "×2", "+1"。
--
-- 返回:
--   UI 可直接显示的中文/符号字符串，例如:
--     "=="  -> WIT_TXT.FMT_COND_ZERO
--     ">1"  -> "＞1"
--     "+1"  -> "≥1"
--
-- 注意:
--   这里只处理显示，不参与 recipe.test 判定。
local function FormatCondValue(v)
    if v == nil then return "" end
    if v == "==" then return WIT_TXT.FMT_COND_ZERO end
    local prefix = v:match("^([^%d.]+)")
    local num_str = v:match("([%d.]+)$")
    if num_str then
        local n = tonumber(num_str)
        if n ~= nil and n == math.floor(n) then num_str = tostring(math.floor(n)) end
        local mapped = {["≥"]="≥", [">"]="＞", ["×"]="＝", ["+"]="≥", ["-"]=""}
        local p = mapped[prefix] or prefix
        return p .. num_str
    end
    return v
end

-- 把某道料理的硬编码条件转换成 UI 文本列表。
--
-- 参数:
--   recipe cooking recipe，使用 recipe.name 查 HARDCODED_CONDITIONS。
--
-- 返回:
--   字符串数组，例如 { "肉度 ＞1", "蛋度 ＞1", "蔬菜度 为0" }。
--   没有硬编码条件时返回空表。
--
-- 注意:
--   这里调用 CN() 本地化标签/食材名，所以此函数依赖 wit_lang.lua 已加载。
function FormatCookCondition(recipe, _)
    local conds = HARDCODED_CONDITIONS[recipe.name]
    if conds then
        local parts = {}
        for _, c in ipairs(conds) do
            if c[1] ~= nil then
                table.insert(parts, CN(c[1]) .. " " .. FormatCondValue(c[2]))
            end
        end
        return parts
    end
    return {}
end
