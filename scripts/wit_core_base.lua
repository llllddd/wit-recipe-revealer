-- wit_core_base: 数据层基础设施
--
-- 职责范围:
--   - 玩家库存统一访问
--   - 烹饪 alias 兼容映射
--   - cooking.lua 缓存入口
--   - 模拟烹饪 names/tags 累加 helper
--
-- 本文件必须最先加载。后续 wit_core_* 模块会通过 WIT_CORE 复用这里的 helper。

WIT_CORE = WIT_CORE or {}

-- 烹饪系统内部名称 -> 实际 prefab 名称的兼容映射。
--
-- DST 的 cooking.ingredients 里有少量历史名称/内部名称，与库存里的 prefab 不完全一致。
-- 例如烹饪判定可能用 cookedmeat，但图标、库存和搬运通常需要 meat_cooked。
-- 统一通过 WIT_CORE.ResolveCookingPrefab() 进入“烹饪判定用名称”，避免各处手写特殊判断。
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
function WIT_CORE.ResolveCookingPrefab(prefab)
    return WIT_COOKING_ALIASES[prefab] or prefab
end

-- 生成库存查找候选名。
--
-- 自动填锅时，view.need_map / view.slots 通常已经是 WIT_CORE.ResolveCookingPrefab() 后的名字；
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
function WIT_CORE.GetCooking()
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
function WIT_CORE.AccumulateIngredient(name, count, names, tags)
    local resolved = WIT_CORE.ResolveCookingPrefab(name)
    names[resolved] = (names[resolved] or 0) + count
    local cooking = WIT_CORE.GetCooking()
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
        WIT_CORE.AccumulateIngredient(name, 1, sim_names, sim_tags)
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

-- 兼容旧代码/控制台调试：保留原函数名。
ResolveCookingPrefab = WIT_CORE.ResolveCookingPrefab
