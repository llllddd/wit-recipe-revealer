-- wit_core_itemdata: 客户端物品属性采集
--
-- 这部分会短暂 SpawnPrefab 来读取组件数值，并缓存到 WIT_ITEM_DB。
-- 调用前请注意：它用于“单个当前查看物品”的详情读取，不用于全 prefab 扫描。

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

-- 从已生成的 prefab 实例上读取 UI 详情页需要的组件数据。
--
-- 参数:
--   inst SpawnPrefab(prefab) 得到的临时实体。
--
-- 返回:
--   data 表。只写入实际存在的组件字段，例如:
--     data.weapon      武器伤害/攻击距离/弹射物
--     data.armor       护甲吸收率/耐久
--     data.edible      三维、食物类型、温度效果、玩家可食用提示
--     data.repairable  可修理材料或图鉴 repairitems
--     data.tags        实体 tag 列表
--
-- 注意:
--   这个函数只做“读组件并转成轻量表”，不负责 Spawn/Remove。
--   外层 GetItemInfo() 会用 pcall 包住 SpawnPrefab，避免单个 prefab 出错拖垮 UI。
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
        -- edible 字段对应信息页的食物属性图标。
        -- player_can_eat/eater_hint 是展示用提示：某些食物类型只给牛、WX、暗影等特殊对象食用。
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

-- 查询某个 prefab 来自哪个启用中的 Mod。
--
-- 参数:
--   prefab_name 要查询的 prefab 名称。
--
-- 返回:
--   找到时返回 Mod 显示名；找不到或原版 prefab 返回 nil。
--
-- 用途:
--   弹窗标题下方显示“来自某 Mod”，帮助区分原版与模组物品。
--
-- 注意:
--   这里只遍历 ModManager.enabledmods，不扫描原版 Prefabs。
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

-- 获取单个 prefab 的详细组件信息，并缓存结果。
--
-- 参数:
--   prefab 当前 UI 正在查看的 prefab。
--
-- 返回:
--   WIT_ITEM_DB[prefab]，即 CollectItemData() 产生的轻量数据表。
--   采集失败时返回空表，避免 UI 层反复 Spawn 同一个坏 prefab。
--
-- 流程:
--   1. 命中缓存则直接返回。
--   2. 对 blueprint 做特殊保护。
--   3. 临时切到 master sim，设置 WIT_SPAWNING_ITEM，SpawnPrefab 并读取组件。
--   4. Remove 临时实体，恢复 world 状态，把结果写入缓存。
--
-- 注意:
--   这是“单物品详情读取”入口，不应用于全量导出或遍历所有 prefab；
--   全量导出请使用 no-spawn 方案，避免触发实体初始化逻辑。
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
