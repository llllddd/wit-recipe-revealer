-- wit_core: 数据层 - 所有与游戏状态/数据相关的逻辑
--
-- 职责范围:
--   - 玩家库存统一访问
--   - 配方/烹饪索引构建
--   - 客户端物品属性采集 (Pure Client-side Hack)
--   - 烹饪卡片求解器 (注入/替换/自动烹饪判定)
--   - 烹饪条件探测 + 格式化
--   - 烹饪上下文管理 (快照/缓存)
--
-- 不包含任何 UI 渲染代码。所有函数在此文件中定义为全局，
-- 上层 wit_ui.lua 或 modmain.lua 直接调用。

-- 烹饪系统内部名称 -> 实际 prefab 名称的兼容映射。
--
-- DST 的 cooking.ingredients 里有少量历史名称/内部名称，与库存里的 prefab 不完全一致。
-- 例如烹饪判定可能用 cookedmeat，但图标、库存和搬运通常需要 meat_cooked。
-- 统一通过 ResolveCookingPrefab() 进入“烹饪判定用名称”，避免各处手写特殊判断。
WIT_COOKING_ALIASES = {
    cookedsmallmeat = "smallmeat_cooked",
    cookedmonstermeat = "monstermeat_cooked",
    cookedmeat = "meat_cooked",
}

-- 烹饪 ingredient 名称 -> 实际显示/库存 prefab 名称的映射。
--
-- 这张表主要服务 UI 与库存 Has() 查询：烹饪逻辑里的 egg 实际在背包中是 bird_egg。
-- 如果之后遇到“配方名能识别，但图标/数量显示不对”的食材，优先考虑补这里。
WIT_INGREDIENT_PREFAB_MAP = {
    egg = "bird_egg",
}

-- WIT_COOKING_ALIASES 的反向表：实际 prefab -> 烹饪内部名。
-- 自动填锅时会用它做回退查找：需求是 meat_cooked，也允许从库存中找到 cookedmeat。
local WIT_REVERSE_COOKING_ALIASES = {}
for cooking_name, prefab_name in pairs(WIT_COOKING_ALIASES) do
    WIT_REVERSE_COOKING_ALIASES[prefab_name] = cooking_name
end

-- ============================
-- 统一库存遍历 (消除 3 份重复)
-- ============================

-- 取当前玩家的 replica.inventory。
--
-- 这里集中做 nil 防御：客户端刚进世界、切角色、开关洞穴/服务器同步期间，
-- ThePlayer / replica / inventory 都可能短暂为空。上层函数保持“安全返回空结果”即可。
local function _GetPlayerInventory()
    if ThePlayer == nil or ThePlayer.replica == nil then return end
    return ThePlayer.replica.inventory
end

-- 遍历单个容器 classified 里的物品。
--
-- callback(ref) 返回 true 时提前终止。
-- ref = {
--   slot   = 容器槽位号，可传给 MoveItemFromAllOfSlot，
--   item   = 物品实体，
--   owner  = 槽位所属实体；主背包为 ThePlayer，溢出背包为 overflow.inst，
--   source = "inventory" 或 "overflow"，方便调试和未来分支逻辑。
-- }
local function _IterateContainerItems(classified, owner, source, callback)
    if classified == nil or classified.GetItems == nil then return false end
    for slot, item in pairs(classified:GetItems()) do
        if callback({ slot = slot, item = item, owner = owner, source = source }) then
            return true
        end
    end
    return false
end

-- 低阶库存迭代器：统一遍历“主背包 + 溢出背包”。
--
-- 目前所有库存读操作都走这里，新增逻辑时优先复用它：
--   - 不重复写 ThePlayer/replica/classified 的 nil 判断；
--   - 不漏掉背包、切斯特类容器等 overflow；
--   - 保持提前终止语义，查找类函数不会无意义扫完整个背包。
local function _IterateInventoryRefs(callback)
    local inventory = _GetPlayerInventory()
    if inventory == nil then return end

    if _IterateContainerItems(inventory.classified, ThePlayer, "inventory", callback) then
        return
    end

    local overflow = inventory.GetOverflowContainer ~= nil and inventory:GetOverflowContainer() or nil
    if overflow ~= nil then
        _IterateContainerItems(overflow.classified, overflow.inst, "overflow", callback)
    end
end

-- 兼容旧调用形态的迭代器：callback(item, owner, slot)。
-- 新代码如需 source 字段，直接使用 _IterateInventoryRefs(callback)。
local function _IterateInventory(callback)
    _IterateInventoryRefs(function(ref)
        return callback(ref.item, ref.owner, ref.slot)
    end)
end

-- 将传入名称转换成烹饪判定使用的 prefab 名。
-- 示例：cookedmeat -> meat_cooked；普通 prefab 原样返回。
local function ResolveCookingPrefab(prefab)
    return WIT_COOKING_ALIASES[prefab] or prefab
end

-- 生成库存查找候选名。
--
-- 自动填锅时，view.need_map / view.slots 通常已经是 ResolveCookingPrefab() 后的名字；
-- 但玩家库存里可能仍暴露为旧 cooking 名。因此查找顺序是：
--   1. 原始传入名；
--   2. alias 正向解析名；
--   3. alias 反向解析名。
-- 用 seen 去重，避免同名 alias 导致重复比较。
local function _BuildInventorySearchNames(prefab)
    local names, seen = {}, {}
    local function add(name)
        if name ~= nil and not seen[name] then
            table.insert(names, name)
            seen[name] = true
        end
    end

    add(prefab)
    add(WIT_COOKING_ALIASES[prefab])
    add(WIT_REVERSE_COOKING_ALIASES[prefab])
    return names
end

-- 统计玩家库存中某物品总数。
-- 注意：这里按“真实库存 prefab”精确统计，不做 alias 回退；调用方应传库存名。
function CountPlayerItem(prefab)
    local count = 0
    _IterateInventory(function(item)
        if item ~= nil and item.prefab == prefab then
            local stack = item.replica ~= nil and item.replica.stackable or nil
            count = count + (stack and stack:StackSize() or 1)
        end
    end)
    return count
end

-- 拉平背包食材列表（自动烹饪/排序用）。
--
-- 每个堆叠物最多展开 4 个，因为烹饪锅只有 4 个槽位；这样能避免 40 个浆果把后续
-- 排序/求解循环放大很多倍，同时不影响任意一次烹饪判定。
function GetPlayerIngredientList()
    local list = {}
    _IterateInventory(function(item)
        if item ~= nil and item.replica ~= nil and item.replica.inventoryitem then
            local stackable = item.replica.stackable
            local count = stackable and stackable:StackSize() or 1
            for _ = 1, math.min(count, 4) do
                table.insert(list, item.prefab)
            end
        end
    end)
    return list
end

-- 在库存中查找某物品的槽位和所属容器。
-- 返回值保持旧接口：(slot, owner)，方便已有调用直接用于搬运。
function FindItemSlotInInventory(prefab)
    local found_slot, found_owner = nil, nil
    _IterateInventory(function(item, owner, slot)
        if item ~= nil and item.prefab == prefab then
            found_slot = slot
            found_owner = owner
            return true
        end
    end)
    return found_slot, found_owner
end

-- 统一库存引用查询：返回 { slot, item, owner, source } 或 nil。
-- 已处理 WIT_COOKING_ALIASES 的正向/反向回退，主要给 AutoFillCookPot() 使用。
function FindInventoryRefByPrefab(prefab)
    local search_names = _BuildInventorySearchNames(prefab)
    local found = nil
    _IterateInventoryRefs(function(ref)
        for _, name in ipairs(search_names) do
            if ref.item ~= nil and ref.item.prefab == name then
                found = ref
                return true
            end
        end
    end)
    return found
end

-- ============================
-- 烹饪食材 tag/name 累加 (消除 3 份重复)
-- ============================

local cooking_cache = nil
local function _GetCooking()
    if cooking_cache == nil then
        cooking_cache = GLOBAL.require("cooking")
    end
    return cooking_cache
end

-- 将预制件名（带 alias 解析）累加到 names/tags 表中。
--
-- cooking recipe.test(cooker, names, tags) 依赖这两个表：
--   - names[prefab] = 数量，用于“必须包含某物品”的判断；
--   - tags[tag] = 权重总和，用于 meat/veggie/fish/monster 等类别判断。
-- 所有模拟烹饪入口都应使用这个函数，避免 alias 解析和 tag 累加规则分叉。
local function _AccumulateIngredient(name, count, names, tags)
    local resolved = ResolveCookingPrefab(name)
    names[resolved] = (names[resolved] or 0) + count
    local cooking = _GetCooking()
    local data = cooking and cooking.ingredients and cooking.ingredients[resolved]
    if data then
        for kk, vv in pairs(data.tags) do
            tags[kk] = (tags[kk] or 0) + vv * count
        end
    end
end

-- 主力：从原始食材列表构建模拟输入 (names + tags)。
--
-- slot_list 是当前四格候选食材；slot_override 可临时替换某些槽位。
-- 求解器会用 override 试探“把第 N 格换成 X 后，recipe.test 是否成立”。
function BuildSimInput(slot_list, slot_override)
    local sim_names, sim_tags = {}, {}
    for ii, ing in ipairs(slot_list) do
        local name = slot_override and slot_override[ii] or ing
        _AccumulateIngredient(name, 1, sim_names, sim_tags)
    end
    return sim_names, sim_tags
end

-- 基础工具函数
function FlattenIngredients(ingredients)
    local list = {}
    if not ingredients then return list end
    for _, ci in ipairs(ingredients) do
        for _ = 1, ci[2] do
            table.insert(list, ci[1])
        end
    end
    return list
end

function BuildNeedMap(ingredients)
    local map = {}
    if not ingredients then return map end
    for _, ci in ipairs(ingredients) do
        map[ci[1]] = (map[ci[1]] or 0) + ci[2]
    end
    return map
end

function PadSlots(slots, count)
    -- 注意：Lua 5.1 中 # 运算符对含 nil 空洞的数组行为未定义
    -- 必须先保存初始长度再手动计数，避免 while #slots < count 死循环
    local n = #slots
    if n >= count then return slots end
    for i = n + 1, count do
        slots[i] = nil
    end
    return slots
end

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
        _AccumulateIngredient(name, 4, names, tags)
        if recipe.test("cookpot", names, tags) then
            return {ingredients = {{name, 4}}}
        end
    end
    -- 2: 1 主料 + 3 填充
    for _, name in ipairs(pool) do
        for _, filler in ipairs(fillers) do
            if filler ~= name then
                local names, tags = {}, {}
                _AccumulateIngredient(name, 1, names, tags)
                _AccumulateIngredient(filler, 3, names, tags)
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
            _AccumulateIngredient(a, 2, names, tags)
            _AccumulateIngredient(b, 2, names, tags)
            if recipe.test("cookpot", names, tags) then
                return {ingredients = {{a, 2}, {b, 2}}}
            end
        end
    end
    return nil
end

-- 构建并缓存官方图鉴数据索引
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
    local cooking = _GetCooking()
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
                                    _AccumulateIngredient(n, ci[2], names, tags)
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

-- 将 scrapbook entry 的 workable/pickable/type 映射为来源类型
-- 只对真正有"产出"的实体类型归类，排斥纯物品和食物
local function _IsSourceEntity(entry)
    -- 纯物品/食物不是"来源实体"，排除它们（如疙瘩树果 oceantreenut 是 item 类型）
    if entry.type == "item" or entry.type == "food" then return false end
    if entry.pickable then return true end
    if entry.workable == "MINE" or entry.workable == "CHOP" or entry.workable == "DIG" or entry.workable == "HAMMER" then return true end
    if entry.type == "creature" or entry.type == "giant" or entry.type == "thing" or entry.type == "pointsofinterest" then return true end
    return false
end

local function _ResolveSourceType(entry)
    if entry.pickable then return "pick" end
    if entry.workable == "MINE" then return "mine" end
    if entry.workable == "CHOP" then return "chop" end
    if entry.workable == "DIG" then return "dig" end
    if entry.workable == "HAMMER" then return "hammer" end
    return "drop"
end

function BuildSourceIndexes()
    local scrap_data_ok, scrap_data = pcall(GLOBAL.require, "screens/redux/scrapbookdata")
    if not (scrap_data_ok and type(scrap_data) == "table") then return end

    -- 通用规则：构建"该实体作为 cooking station 时能产出的全部菜肴"集合
    -- 用于过滤 deps 中的反向依赖（HAMMER/cooker 类容器实体的 deps 通常是"在自己内部做的东西"，
    -- 不是"被自己锤击后掉落的东西"，例如 cookpot 的 deps 是它能做的菜肴而不是它掉落的材料）
    local cooking = _GetCooking()
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

-- ============================
-- 客户端物品属性采集 (from wit_itemdata_client.lua)
-- ============================

-- prefab -> item info，客户端临时生成实体后采集到的物品属性缓存。
WIT_ITEM_DB = WIT_ITEM_DB or {}

-- 食物类型 → 可食用角色的映射（非玩家可食用的特殊类型）
local _EATER_HINT_MAP = {
    ROUGHAGE = WIT_TXT.EATER_BEEFALO,
    GEARS = "WX-78",
    WOOD = "",
    ELEMENTAL = "",
    HORRIBLE = WIT_TXT.EATER_SHADOW,
    BURNT = WIT_TXT.EATER_SHADOW,
}

local function CollectItemData(inst)
    local data = {}
    if inst.components.weapon ~= nil then
        if type(inst.components.weapon.damage) == "function" then
            local ran, val = pcall(inst.components.weapon.damage, inst, GLOBAL.ThePlayer)
            if ran then data.weapon = { damage = val } end
        else
            data.weapon = { damage = inst.components.weapon.damage }
        end
        if data.weapon then
            data.weapon.attackrange = inst.components.weapon.attackrange
            data.weapon.projectile = inst.components.weapon.projectile
        end
    end
    if inst.components.armor ~= nil then
        data.armor = {
            absorb_percent = inst.components.armor.absorb_percent,
            maxcondition = inst.components.armor.maxcondition,
        }
    end
    if inst.components.tool ~= nil then
        data.tools = {}
        if type(inst.components.tool.actions) == "table" then
            for act, eff in pairs(inst.components.tool.actions) do
                table.insert(data.tools, { action = act.id, efficiency = eff })
            end
        end
    end
    if inst.components.edible ~= nil then
        local ft = inst.components.edible.foodtype
        -- 检查玩家是否可食用（基于食物类型的 eater tag 体系）
        local player_can_eat = true
        local eater_hint = nil
        if ft ~= nil and ft ~= "GENERIC" then
            local eater_tag = ft .. "_eater"
            if ThePlayer ~= nil and ThePlayer:HasTag(eater_tag) then
                player_can_eat = true
            elseif _EATER_HINT_MAP[ft] ~= nil then
                player_can_eat = false
                if #_EATER_HINT_MAP[ft] > 0 then
                    eater_hint = _EATER_HINT_MAP[ft]
                end
            end
        end
        data.edible = {
            health = inst.components.edible.healthvalue,
            hunger = inst.components.edible.hungervalue,
            sanity = inst.components.edible.sanityvalue,
            foodtype = ft,
            temperaturedelta = inst.components.edible.temperaturedelta,
            temperatureduration = inst.components.edible.temperatureduration,
            player_can_eat = player_can_eat,
            eater_hint = eater_hint,
        }
    end
    if inst.components.perishable ~= nil then
        data.perishable = { perishtime = inst.components.perishable.perishtime }
    end
    if inst.components.fuel ~= nil then
        data.fuel = { fuelvalue = inst.components.fuel.fuelvalue }
    end
    if inst.components.burnable ~= nil then
        data.burnable = { burntime = inst.components.burnable.burntime }
    end
    if inst.components.finiteuses ~= nil then
        data.finiteuses = { maxuses = inst.components.finiteuses.maxuses or inst.components.finiteuses.total }
    end
    if inst.components.equippable ~= nil then
        data.equippable = {
            equipslot = inst.components.equippable.equipslot,
            walkspeedmult = inst.components.equippable.walkspeedmult,
            dapperness = inst.components.equippable.dapperness,
        }
    end
    if inst.components.sanityaura ~= nil then
        data.sanityaura = { aura = inst.components.sanityaura.aura }
    end
    if inst.components.healer ~= nil then
        data.healer = { health = inst.components.healer.health }
    end
    if inst.components.deployable ~= nil then
        data.deployable = { mode = inst.components.deployable.mode }
    end
    if inst.components.waterproofer ~= nil then
        data.waterproofer = { effectiveness = inst.components.waterproofer.effectiveness }
    end
    if inst.components.insulator ~= nil then
        data.insulator = { insulation = inst.components.insulator.insulation, type = inst.components.insulator.type }
    end
    if inst.components.stackable ~= nil then
        data.stackable = { maxsize = inst.components.stackable.maxsize }
    end
    -- Runtime component: repairable (armor, tools etc. with direct repairmaterial)
    if inst.components.repairable ~= nil then
        data.repairable = { repairmaterial = inst.components.repairable.repairmaterial }
    end

    -- Hardcoded scrapbook data: sewable + repairitems for placed entities (walls, boats)
    -- sewable is NOT a runtime component/tag; it's only defined in scrapbookdata.lua
    local sb_ok, sb_data = pcall(GLOBAL.require, "screens/redux/scrapbookdata")
    if sb_ok and type(sb_data) == "table" then
        local entry = sb_data[inst.prefab]
        if entry then
            if entry.sewable then data.sewable = true end
            -- Direct: placed things (walls, boats) list repairitems in scrapbook
            if entry.repairitems then
                data.repairable = data.repairable or {}
                data.repairable.repairitems = entry.repairitems
            -- Indirect: items (wall_stone_item) reference a placed thing via deps
            elseif entry.deps then
                for _, dep in ipairs(entry.deps) do
                    local dep_entry = sb_data[dep]
                    if dep_entry and dep_entry.repairitems then
                        data.repairable = data.repairable or {}
                        data.repairable.repairitems = dep_entry.repairitems
                        break
                    end
                end
            end
        end
    end
    if inst.components.fueled ~= nil then
        data.fueled = { maxfuel = inst.components.fueled.maxfuel, fueltype = inst.components.fueled.fueltype }
    end
    if inst.components.tradable ~= nil then
        data.tradable = { goldvalue = inst.components.tradable.goldvalue }
    end
    if inst.tags ~= nil then
        data.tags = {}
        for tag, _ in pairs(inst.tags) do
            table.insert(data.tags, tag)
        end
    end
    -- Determine which mod added this prefab (if any)
    data.mod_source = GetPrefabModName(inst.prefab)
    return data
end

-- ============================
-- Prefab 来源 Mod 查询
-- ============================

-- Iterate all enabled mods to find which one registered this prefab
function GetPrefabModName(prefab_name)
    if ModManager == nil or ModManager.enabledmods == nil then return nil end
    for _, modname in ipairs(ModManager.enabledmods) do
        local mod = ModManager:GetMod(modname)
        if mod and mod.Prefabs and mod.Prefabs[prefab_name] then
            return KnownModIndex and KnownModIndex:GetModFancyName(modname) or modname
        end
    end
    return nil
end

function GetItemInfo(prefab)
    if prefab == nil then return nil end
    if WIT_ITEM_DB[prefab] ~= nil then return WIT_ITEM_DB[prefab] end

    -- 通用蓝图（blueprint）在无玩家上下文中 SpawnPrefab 会崩溃，返回空数据
    -- 具体蓝图（xxx_blueprint）有独立 prefab 定义，可正常 SpawnPrefab
    if prefab == "blueprint" then
        WIT_ITEM_DB[prefab] = {}
        return WIT_ITEM_DB[prefab]
    end

    local IsMasterSim = GLOBAL.TheWorld.ismastersim
    GLOBAL.TheWorld.ismastersim = true
    WIT_SPAWNING_ITEM = true

    local ok, data = pcall(function()
        local inst_copy = GLOBAL.SpawnPrefab(prefab)
        if inst_copy ~= nil then
            local d = CollectItemData(inst_copy)
            inst_copy:Remove()
            return d
        end
        return nil
    end)

    WIT_SPAWNING_ITEM = false
    GLOBAL.TheWorld.ismastersim = IsMasterSim

    WIT_ITEM_DB[prefab] = (ok and data ~= nil) and data or {}
    return WIT_ITEM_DB[prefab]
end

-- ============================
-- 烹饪卡片求解器 (from wit_cook_card_resolver.lua)
-- ============================

function TryInjectFocusIngredient(recipe, slots, focus_name)
    local found = false
    for _, v in ipairs(slots) do
        if v == focus_name then found = true; break end
    end
    if found or not recipe.test then return slots end

    for try_slot = #slots, 1, -1 do
        local override = {}
        for ii = 1, #slots do override[ii] = (ii == try_slot) and focus_name or slots[ii] end
        local sim_names, sim_tags = BuildSimInput(slots, override)
        if recipe.test("cookpot", sim_names, sim_tags) then
            slots[try_slot] = focus_name
            break
        end
    end
    return slots
end

function SubstituteMissingIngredients(recipe, slots, snapshot)
    if not recipe.test or not snapshot then return slots end
    local cooking = _GetCooking()
    local bp_avail = {}
    for name, count in pairs(snapshot.counts) do
        if cooking and cooking.ingredients and cooking.ingredients[name] then
            bp_avail[name] = count
        end
    end
    for _, ing in ipairs(slots) do
        if bp_avail[ing] and bp_avail[ing] > 0 then bp_avail[ing] = bp_avail[ing] - 1 end
    end
    local focus_count = 0
    if WIT_NAME then
        for _, v in ipairs(slots) do
            if v == WIT_NAME then focus_count = focus_count + 1 end
        end
    end
    for slot_i = 1, #slots do
        local cur = slots[slot_i]
        if cur ~= nil then
            local need_count = 0
            for _, v in ipairs(slots) do if v == cur then need_count = need_count + 1 end end
            if (snapshot.counts[cur] or 0) < need_count then
                if cur == WIT_NAME and focus_count <= 1 then
                    -- 保留最后一个焦点食材
                else
                    local best_sub = nil
                    for bp_name, bp_count in pairs(bp_avail) do
                        if bp_count > 0 and bp_name ~= cur then
                            local override = {}
                            for ii = 1, #slots do override[ii] = (ii == slot_i) and bp_name or slots[ii] end
                            local sim_names, sim_tags = BuildSimInput(slots, override)
                            if recipe.test("cookpot", sim_names, sim_tags) then
                                best_sub = bp_name; break
                            end
                        end
                    end
                    if best_sub then
                        slots[slot_i] = best_sub
                        bp_avail[best_sub] = bp_avail[best_sub] - 1
                        if cur == WIT_NAME then focus_count = focus_count - 1 end
                    end
                end
            end
        end
    end
    return slots
end

-- ============================
-- 自动烹饪判定 (统一版，消除 2 份重复)
-- ============================

function CanAutoCook(view)
    if view == nil or view.need_map == nil then return false end
    local pot = WIT_OPEN_COOKPOT
    if pot == nil then return false end
    if pot.replica.stewer ~= nil then
        if pot.replica.stewer:IsCooking() or pot.replica.stewer:IsDone() then return false end
    end
    -- view.need_map uses resolved names (like meat_cooked)
    -- We need to check against actual inventory counts
    local snapshot = CollectIngredientSnapshot()
    for prefab, count in pairs(view.need_map) do
        if (snapshot.counts[prefab] or 0) < count then return false end
    end
    return true
end

function AutoFillCookPot(view)
    if ThePlayer == nil or view == nil or view.slots == nil then return end
    local pot = WIT_OPEN_COOKPOT
    if pot == nil then return end
    local classified = ThePlayer.replica.inventory and ThePlayer.replica.inventory.classified
    if classified == nil then return end

    -- 为所有需要搬运的食材统一查找库存引用（已包含 alias 回退）
    for _, prefab in ipairs(view.slots) do
        if prefab ~= nil then
            local ref = FindInventoryRefByPrefab(prefab)
            if ref and ref.slot ~= nil then
                classified:MoveItemFromAllOfSlot(ref.slot, pot)
            end
        end
    end
end

-- ============================
-- 库存快照 + 烹饪上下文管理
-- ============================

function CollectIngredientSnapshot()
    local bp_items = GetPlayerIngredientList() or {}
    local snapshot = { list = bp_items, counts = {}, tags = {} }
    for _, v in ipairs(bp_items) do
        local name = WIT_COOKING_ALIASES[v] or v
        snapshot.counts[name] = (snapshot.counts[name] or 0) + 1
        _AccumulateIngredient(v, 1, {}, snapshot.tags)
    end
    return snapshot
end

function CanAutoCookFromSnapshot(need_map, counts)
    if need_map == nil or counts == nil then return false end
    local pot = WIT_OPEN_COOKPOT
    if pot == nil then return false end
    if pot.replica.stewer ~= nil then
        if pot.replica.stewer:IsCooking() or pot.replica.stewer:IsDone() then return false end
    end
    for prefab, count in pairs(need_map) do
        if (counts[prefab] or 0) < count then return false end
    end
    return true
end

function ResolveCookingCard(recipe, focus_name, snapshot)
    if not recipe.card_def or not recipe.card_def.ingredients then return nil end
    local slots = FlattenIngredients(recipe.card_def.ingredients)
    slots = TryInjectFocusIngredient(recipe, slots, focus_name)
    local raw_need_map = {}
    for _, s in ipairs(slots) do
        if s ~= nil then raw_need_map[s] = (raw_need_map[s] or 0) + 1 end
    end
    slots = SubstituteMissingIngredients(recipe, slots, snapshot)
    slots = PadSlots(slots, 4)
    if focus_name then
        local found = false
        for _, s in ipairs(slots) do
            if s == focus_name then found = true; break end
        end
        if not found then return nil end
    end
    local need_map = {}
    for _, s in ipairs(slots) do
        if s ~= nil then need_map[s] = (need_map[s] or 0) + 1 end
    end
    return {
        slots = slots,
        need_map = need_map,
        raw_need_map = raw_need_map,
        can_auto_cook = CanAutoCookFromSnapshot(need_map, snapshot.counts),
    }
end

function BuildCookContext()
    local snapshot = CollectIngredientSnapshot()
    if WIT_COOK_CONTEXT and (not snapshot or not snapshot.list or #snapshot.list == 0) then return end
    WIT_COOK_REV = (WIT_COOK_REV or 0) + 1
    WIT_COOK_CONTEXT = {
        revision = WIT_COOK_REV,
        snapshot = snapshot,
        resolved = {},
    }
end

function GetResolvedCookingCard(recipe, focus_name)
    local ctx = WIT_COOK_CONTEXT
    if ctx == nil then return nil end
    local key = recipe.name .. "|" .. focus_name
    if ctx.resolved[key] == nil then
        ctx.resolved[key] = ResolveCookingCard(recipe, focus_name, ctx.snapshot)
    end
    return ctx.resolved[key]
end

-- ============================
-- 烹饪锅状态检测 (from wit_helpers.lua)
-- ============================

function GetOpenCookPot()
    if ThePlayer == nil or ThePlayer.replica == nil or ThePlayer.replica.inventory == nil then return nil end
    local containers = ThePlayer.replica.inventory:GetOpenContainers()
    if containers == nil then return nil end
    for ent, _ in pairs(containers) do
        if ent:HasTag("stewer") and ent.replica.container ~= nil then
            return ent
        end
    end
    return nil
end
