-- [JEI] What Is This - modmain
-- 入口文件: 全局常量 + 事件注册 + 模块加载

GLOBAL.setmetatable(env, { __index = function(_, k) return GLOBAL.rawget(GLOBAL, k) end })

-- 模块依赖
GLOBAL.Widget = require("widgets/widget")
GLOBAL.Image = require("widgets/image")
GLOBAL.Text = require("widgets/text")
GLOBAL.TextButton = require("widgets/textbutton")
GLOBAL.ImageButton = require("widgets/imagebutton")

-- Widget 构造器全局别名，供拆分后的 UI 模块直接创建控件。
Widget = GLOBAL.Widget

-- Image 构造器全局别名，供 UI 模块绘制静态图片。
Image = GLOBAL.Image

-- Text 构造器全局别名，供 UI 模块绘制文本。
Text = GLOBAL.Text

-- TextButton 构造器全局别名，供 UI 模块绘制文字按钮。
TextButton = GLOBAL.TextButton

-- ImageButton 构造器全局别名，供 UI 模块绘制图片按钮。
ImageButton = GLOBAL.ImageButton

-- ============================
-- 全局常量 (WIT_ 前缀避免全局污染)
-- WIT_COOKING_ALIASES / WIT_INGREDIENT_PREFAB_MAP → wit_core.lua
-- WIT_PAGE_SIZE → wit_ui.lua

-- ============================
-- 数据层状态
-- ============================
-- WIT 数据根表：所有索引、烹饪数据和来源数据都挂在这里。
WIT = {}

-- prefab -> recipe[]，按产物反查制作配方。
WIT.by_product = {}

-- prefab -> recipe[]，按材料反查使用该材料的制作配方。
WIT.by_material = {}

-- food prefab -> cooking recipe，烹饪产物到烹饪配方的索引。
WIT.cook_foods = {}

-- ingredient prefab -> cooking recipe[]，烹饪材料到可参与菜谱的反查索引。
WIT.cook_by_ingredient = {}

-- ingredient prefab -> tags，烹饪材料标签缓存，用于菜谱 test 判定。
WIT.ingredient_tags = {}

-- BuildIndexes 是否已经执行过，避免重复构建昂贵索引。
WIT_data_built = false

-- 图鉴数据缓存：prefab -> entry
WIT_scrapbook_entry_map_by_prefab = nil

-- 图鉴数据缓存：name -> entry
WIT_scrapbook_entry_map_by_name = nil

-- ============================
-- UI 层状态
-- ============================
-- 当前打开的 WIT 弹窗 Widget；nil 表示未打开。
WIT_POPUP = nil

-- 当前弹窗展示的 prefab 名称。
WIT_NAME = nil

-- 当前弹窗打开模式：ITEM / SOURCE / USE。
WIT_MODE = nil

-- 当前选中的页签类型。
WIT_CUR_CAT = nil

-- 当前内容区页码，从 1 开始。
WIT_PAGE = 1

-- 当前 prefab 可展示的页签列表。
WIT_AVAIL_CATS = {}

-- 当前弹窗内容容器 Widget，由页签渲染函数填充。
WIT_CONTENT = nil

-- cat -> TextButton，页签按钮引用表，用于刷新选中态。
WIT_TAB_BTNS = {}

-- 分页文本 Widget，显示当前页 / 总页数。
WIT_PG_TEXT = nil

-- 上一页按钮 Widget。
WIT_PG_PREV = nil

-- 下一页按钮 Widget。
WIT_PG_NEXT = nil

-- 当前检测到的打开烹饪锅实例，自动填锅逻辑会使用。
WIT_OPEN_COOKPOT = nil

-- 是否显示槽位悬浮信息，可在配置中关闭。
WIT_HOVER_INFO = true

-- 合成菜单详情面板当前悬浮的 prefab，供 R/U 键没有鼠标物品时回退。
WIT_HOVERED_DETAIL_PREFAB = nil

-- 导航历史后退栈，元素记录 prefab 和打开模式。
WIT_BACK_STACK = {}

-- 导航历史前进栈，元素记录 prefab 和打开模式。
WIT_FORWARD_STACK = {}

-- ClosePopup 暂存的上一条目，CreatePopup 会消费并压入后退栈。
WIT_PrevHistory = nil

-- 图鉴模式下弹窗背景遮罩；当前保留给图鉴层级控制使用。
WIT_SCRAPBOOK_BG = nil

-- 前进/后退导航时闭锁 ClosePopup 的历史记录，避免重复入栈。
WIT_NAV_LOCK = false

-- ============================
-- 纯客户端实体拦截
-- ============================
-- 客户端临时生成物品用于读取组件数据时，屏蔽组件动作注册的标记。
WIT_SPAWNING_ITEM = false

-- DST API：AddGlobalClassPostConstruct 修改全局类，给 EntityScript 包一层注册逻辑。
AddGlobalClassPostConstruct("entityscript", "EntityScript", function(self)
    local oldRegisterComponentActions = self.RegisterComponentActions
    if oldRegisterComponentActions ~= nil then
        self.RegisterComponentActions = function(self, name)
            if not WIT_SPAWNING_ITEM then
                return oldRegisterComponentActions(self, name)
            end
        end
    end
end)

-- ============================
-- 加载子模块 (顺序: 国际化 → 数据层 → 表现层)
-- ============================
modimport("scripts/wit_lang")
modimport("scripts/wit_core")
modimport("scripts/wit_ui")
modimport("scripts/keybind")

-- DST API：GetModConfigData 读取 modinfo.lua 中 configuration_options 的当前配置值。
-- 读取悬浮详情配置。
WIT_HOVER_INFO = GetModConfigData("SHOW_HOVER_INFO")

-- keybind 回调：管理按键事件处理器
local key_handlers = {}
function KeyBind(name, key)
    if key_handlers[name] then key_handlers[name]:Remove() end
    if type(key) ~= "number" or key <= 0 then return end
    local fn
    if name == "KEY_R" then
        fn = WIT_DISPATCH_R
    elseif name == "KEY_U" then
        fn = WIT_DISPATCH_U
    elseif name == "KEY_NAV_BACK" then
        fn = WIT_NAV_BACK
    elseif name == "KEY_NAV_FORWARD" then
        fn = WIT_NAV_FORWARD
    end
    if fn then
        key_handlers[name] = TheInput:AddKeyDownHandler(key, fn)
    end
end

-- ============================
-- 导航键直接注册
-- ============================

-- 鼠标按键码映射（与 keybind.lua 的 Raw() 保持一致）
local _NavKeyCode = {
    ['\238\132\130'] = 1002, -- 中键
    ['\238\132\131'] = 1005, -- 后侧键
    ['\238\132\132'] = 1006, -- 前侧键
}

-- 根据配置项名称解析导航键；GetModConfigData 是 DST 提供的 Mod 配置读取函数。
local function _ResolveNavKey(name)
    -- DST API：读取玩家当前保存的按键配置值。
    local val = GetModConfigData(name)
    if type(val) == "string" then
        local code = GLOBAL.rawget(GLOBAL, val)
        if type(code) == "number" then return code end
        code = _NavKeyCode[val]
        if code then return code end
        if val:find("^KEY_KP_") then
            local numpad = {
                KP_0 = 269,
                KP_1 = 257,
                KP_2 = 258,
                KP_3 = 259,
                KP_4 = 260,
                KP_5 = 261,
                KP_6 = 262,
                KP_7 = 263,
                KP_8 = 264,
                KP_9 = 265,
                KP_PERIOD = 266,
                KP_DIVIDE = 267,
                KP_MULTIPLY = 106,
                KP_MINUS = 109,
                KP_PLUS = 107
            }
            return numpad[val:sub(5)]
        end
    elseif type(val) == "number" then
        return val
    end
    return nil
end

-- 键盘/自定义键（通过 AddKeyDownHandler，走玩家配置）
local function _RegisterNavKey(name, fn)
    local code = _ResolveNavKey(name)
    if code and type(code) == "number" and code > 0 then
        TheInput:AddKeyDownHandler(code, fn)
    end
end
_RegisterNavKey("KEY_NAV_BACK", WIT_NAV_BACK)
_RegisterNavKey("KEY_NAV_FORWARD", WIT_NAV_FORWARD)

-- 鼠标物理按键（通过 AddMouseButtonHandler，DST 的鼠标事件不走 AddKeyDownHandler）
-- 同时匹配 SDL 原生码（4=X1/后退, 5=X2/前进）和 DST 扩展码
TheInput:AddMouseButtonHandler(function(button, down)
    if not down then return end
    if button == 4 or button == 1005 then
        WIT_NAV_BACK()
    elseif button == 5 or button == 1006 then
        WIT_NAV_FORWARD()
    end
end)

-- ============================
-- 初始化事件
-- ============================

-- DST API：AddPlayerPostInit 在玩家实例创建后注册事件监听。
AddPlayerPostInit(function(inst)
    local function wit_refresh()
        WIT_OPEN_COOKPOT = GetOpenCookPot()
        BuildCookContext()
        if WIT_POPUP ~= nil and WIT_CONTENT ~= nil and WIT_CUR_CAT ~= nil then
            SelectCategory(WIT_CUR_CAT, false)
        end
    end
    inst:ListenForEvent("refreshcrafting", wit_refresh)
    inst:ListenForEvent("refreshinventory", wit_refresh)
    inst:ListenForEvent("opencontainer", wit_refresh)
    inst:ListenForEvent("closecontainer", wit_refresh)
    inst:DoTaskInTime(0, wit_refresh)
end)

-- 合成菜单联动
-- DST API：AddClassPostConstruct 修改原版合成菜单 HUD 的打开/关闭行为。
AddClassPostConstruct("widgets/redux/craftingmenu_hud", function(self)
    local orig_open = self.Open
    self.Open = function(s, ...)
        local ret = orig_open(s, ...)
        if WIT_POPUP ~= nil then
            WIT_POPUP:MoveTo(WIT_POPUP:GetPosition(), Vector3(881, 35, 0), 0.25)
        end
        return ret
    end
    local orig_close = self.Close
    self.Close = function(s, ...)
        local ret = orig_close(s, ...)
        if WIT_POPUP ~= nil then
            WIT_POPUP:MoveTo(WIT_POPUP:GetPosition(), Vector3(405, 35, 0), 0.25)
        end
        return ret
    end
end)

-- ============================
-- 合成菜单详情面板整合
-- ============================

-- 材料图标：右键 WIT 用途查询，悬浮 R/U 查询（左键保留原版合成行为）
AddClassPostConstruct("widgets/ingredientui", function(self)
    local prefab = self.recipe_type
    if type(prefab) ~= "string" then return end

    -- 右击 → WIT 用途查询
    local orig_oc = self.OnControl
    self.OnControl = function(btn, control, down)
        if down and control == CONTROL_SECONDARY then
            BuildIndexes()
            ClosePopup()
            CreatePopup(prefab, "USE")
            return true
        end

        if orig_oc ~= nil then
            return orig_oc(btn, control, down)
        end

        return false
    end

    -- 悬浮反馈 + 记录悬浮 prefab 供 R/U 键调度
    local orig_gain = self.ongainfocus
    self.ongainfocus = function()
        if orig_gain then orig_gain() end
        self:SetScale(1.08, 1.08)
        WIT_HOVERED_DETAIL_PREFAB = prefab
    end

    local orig_lose = self.onlosefocus
    self.onlosefocus = function()
        if orig_lose then orig_lose() end
        self:SetScale(1, 1)
        WIT_HOVERED_DETAIL_PREFAB = nil
    end
end)
-- 产物图标（皮肤选择器）：加透明可点击层 + 左击 WIT 来源 / 右击 WIT 用途 + 悬浮微亮
-- DST API：AddClassPostConstruct 给原版皮肤选择器追加 WIT 点击层。
AddClassPostConstruct("widgets/redux/craftingmenu_skinselector", function(self)
    local recipe = self.recipe
    local prefab = recipe and (recipe.product or recipe.name)
    if type(prefab) ~= "string" then return end

    local fg = self.spinner and self.spinner.fgimage
    if not fg then return end
    local parent = fg.parent
    if not parent then return end

    local fx, fy = fg:GetPosition()
    local btn = parent:AddChild(ImageButton("images/hud.xml", "inv_slot.tex"))
    btn:SetPosition(fx, fy)
    btn:ForceImageSize(80, 80)
    btn.image:SetTint(0, 0, 0, 0)

    -- 悬浮微亮 + 记录悬浮 prefab 供 R/U 键调度
    btn:SetOnGainFocus(function()
        btn.image:SetTint(1, 1, 1, 0.15)
        WIT_HOVERED_DETAIL_PREFAB = prefab
    end)
    btn:SetOnLoseFocus(function()
        btn.image:SetTint(0, 0, 0, 0)
        WIT_HOVERED_DETAIL_PREFAB = nil
    end)

    -- 左击 → 来源
    btn:SetOnClick(function()
        BuildIndexes()
        ClosePopup()
        CreatePopup(prefab, "SOURCE")
    end)

    -- 右击 → 用途
    local orig_oc = btn.OnControl
    btn.OnControl = function(b, control, down)
        if down and control == CONTROL_SECONDARY then
            BuildIndexes()
            ClosePopup()
            CreatePopup(prefab, "USE")
            return true
        end
        return orig_oc and orig_oc(b, control, down)
    end
end)

GLOBAL.WIT_Reload = function()
    print("[WIT] Reloading modules...")

    modimport("scripts/wit_ui.lua")
    modimport("scripts/keybind.lua")

    if WIT_POPUP ~= nil then
        ClosePopup()
    end

    WIT_data_built = false

    print("[WIT] Reload finished.")
end

GLOBAL.WIT_DumpAllInsts = function()
    local seen = {}
    local names = {}

    for guid, inst in pairs(GLOBAL.Ents) do
        if inst ~= nil and type(inst.prefab) == "string" and inst.prefab ~= "" then
            if not seen[inst.prefab] then
                seen[inst.prefab] = true
                table.insert(names, inst.prefab)
            end
        end
    end

    table.sort(names)

    GLOBAL.TheSim:SetPersistentString(
        "wit_unique_prefabs.txt",
        table.concat(names, "\n"),
        false,
        function(success)
            print("[WIT] dump unique prefabs:", success, "count:", #names)
        end
    )
end

GLOBAL.WIT_FindInstsByPrefab = function(target)
    for guid, inst in pairs(Ents) do
        if inst ~= nil and inst.prefab == target then
            local x, y, z = 0, 0, 0

            if inst.Transform ~= nil then
                x, y, z = inst.Transform:GetWorldPosition()
            end

            print("[FOUND]", guid, inst.prefab, x, y, z, inst)
        end
    end
end

GLOBAL.WIT_DebugHoveredInst = function()
    local inst = TheInput:GetWorldEntityUnderMouse()

    if inst == nil then
        print("[WIT] no world inst under mouse")
        return
    end

    print("[WIT] inst =", inst)
    print("[WIT] GUID =", inst.GUID)
    print("[WIT] prefab =", inst.prefab)

    if inst.Transform ~= nil then
        local x, y, z = inst.Transform:GetWorldPosition()
        print("[WIT] pos =", x, y, z)
    end

    print("[WIT] tags:")
    if inst.tags ~= nil then
        for tag, _ in pairs(inst.tags) do
            print("  ", tag)
        end
    end

    print("[WIT] components:")
    if inst.components ~= nil then
        for name, _ in pairs(inst.components) do
            print("  ", name)
        end
    end

    print("[WIT] replica:")
    if inst.replica ~= nil then
        for name, _ in pairs(inst.replica) do
            print("  ", name)
        end
    end
end

-- ============================
-- Debug：导出官方图鉴 scrapbookdata 所有 entry
-- ============================

local function WIT_SerializeValue(v, indent, visited)
    indent = indent or 0
    visited = visited or {}

    local t = type(v)

    if t == "nil" then
        return "nil"
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    elseif t == "string" then
        return string.format("%q", v)
    elseif t ~= "table" then
        return string.format("%q", tostring(v))
    end

    if visited[v] then
        return string.format("%q", "<cycle>")
    end

    visited[v] = true

    local pad = string.rep("    ", indent)
    local child_pad = string.rep("    ", indent + 1)
    local parts = {}

    table.insert(parts, "{")

    local keys = {}
    for k, _ in pairs(v) do
        table.insert(keys, k)
    end

    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)

    for _, k in ipairs(keys) do
        local key_str

        if type(k) == "string" and k:match("^[%a_][%w_]*$") then
            key_str = k
        else
            key_str = "[" .. WIT_SerializeValue(k, indent + 1, visited) .. "]"
        end

        local val_str = WIT_SerializeValue(v[k], indent + 1, visited)

        table.insert(parts, child_pad .. key_str .. " = " .. val_str .. ",")
    end

    table.insert(parts, pad .. "}")

    visited[v] = nil

    return table.concat(parts, "\n")
end

GLOBAL.WIT_DumpScrapbookEntries = function()
    local ok, data = pcall(
        GLOBAL.require,
        "screens/redux/scrapbookdata"
    )

    if not ok or type(data) ~= "table" then
        print("[WIT] failed to load scrapbookdata:", data)
        return
    end

    local entries = {}

    for _, entry in pairs(data) do
        if type(entry) == "table" then
            table.insert(entries, entry)
        end
    end

    table.sort(entries, function(a, b)
        return tostring(a.prefab or "") < tostring(b.prefab or "")
    end)

    local lines = {}

    table.insert(lines, "-- WIT dumped scrapbookdata")
    table.insert(lines, "-- entry count: " .. tostring(#entries))
    table.insert(lines, "")

    for i, entry in ipairs(entries) do
        table.insert(lines, "ENTRY " .. tostring(i))
        table.insert(lines, "prefab = " .. tostring(entry.prefab))
        table.insert(lines, WIT_SerializeValue(entry, 0, {}))
        table.insert(lines, "")
    end

    GLOBAL.TheSim:SetPersistentString(
        "wit_scrapbook_entries.txt",
        table.concat(lines, "\n"),
        false,
        function(success)
            print("[WIT] dump scrapbook entries:", success, "count:", #entries)
        end
    )
end

WIT_DumpScrapbookEntries = GLOBAL.WIT_DumpScrapbookEntries

-- ============================
-- Debug：导出所有“物品 prefab”中不在官方图鉴里的项目
--
-- 判断“物品”的标准：
--   SpawnPrefab(prefab) 后，
--   inst.components.inventoryitem 或 inst.replica.inventoryitem 存在
--
-- 判断“是否在图鉴里”的标准：
--   同时匹配 scrapbook entry.prefab 和 entry.name
--
-- 输出文件：
--   wit_inventory_items_not_in_scrapbook.txt
-- ============================

GLOBAL.WIT_DumpInventoryItemsNotInScrapbook = function()
    print("[WIT] scanning inventory items not in scrapbook...")

    -- 1. 读取官方图鉴数据
    local ok, scrapbookdata = pcall(
        GLOBAL.require,
        "screens/redux/scrapbookdata"
    )

    if not ok or type(scrapbookdata) ~= "table" then
        print("[WIT] failed to load scrapbookdata:", scrapbookdata)
        return
    end

    -- 图鉴中出现过的 entry.prefab
    local scrapbook_prefabs = {}

    -- 图鉴中出现过的 entry.name
    local scrapbook_names = {}

    for _, entry in pairs(scrapbookdata) do
        if type(entry) == "table" then
            if type(entry.prefab) == "string" and entry.prefab ~= "" then
                scrapbook_prefabs[entry.prefab] = true
            end

            if type(entry.name) == "string" and entry.name ~= "" then
                scrapbook_names[entry.name] = true
            end
        end
    end

    -- 2. 遍历所有 prefab，临时生成，判断是否是物品
    local item_prefabs = {}
    local failed_prefabs = {}
    local skipped_prefabs = {}

    for prefab, prefab_def in pairs(GLOBAL.Prefabs) do
        if type(prefab) == "string" and prefab ~= "" then

            -- 关键保护：
            -- 有些 Prefabs[prefab] 不是完整 prefab 定义，或者 prefab_def.fn 是 nil。
            -- 这种不能 SpawnPrefab，否则会报：
            -- attempt to call field 'fn' (a nil value)
            if type(prefab_def) ~= "table"
                or type(prefab_def.fn) ~= "function" then

                table.insert(skipped_prefabs, prefab)

            else
                local old_spawning_flag = WIT_SPAWNING_ITEM
                WIT_SPAWNING_ITEM = true

                local ok_spawn, inst = pcall(function()
                    return GLOBAL.SpawnPrefab(prefab)
                end)

                WIT_SPAWNING_ITEM = old_spawning_flag

                if ok_spawn and inst ~= nil then
                    local is_inventory_item = false

                    if inst.components ~= nil
                        and inst.components.inventoryitem ~= nil then

                        is_inventory_item = true
                    end

                    if inst.replica ~= nil
                        and inst.replica.inventoryitem ~= nil then

                        is_inventory_item = true
                    end

                    if is_inventory_item then
                        table.insert(item_prefabs, prefab)
                    end

                    if inst.Remove ~= nil then
                        inst:Remove()
                    end
                else
                    table.insert(failed_prefabs, prefab)
                end
            end
        end
    end

    table.sort(item_prefabs)
    table.sort(failed_prefabs)
    table.sort(skipped_prefabs)

    -- 3. 找出“不在图鉴里”的物品 prefab
    local missing = {}

    for _, prefab in ipairs(item_prefabs) do
        local in_scrapbook =
            scrapbook_prefabs[prefab] == true
            or scrapbook_names[prefab] == true

        if not in_scrapbook then
            table.insert(missing, prefab)
        end
    end

    table.sort(missing)

    -- 4. 保存结果
    local lines = {}

    table.insert(lines, "-- WIT inventory item prefabs not found in scrapbookdata")
    table.insert(lines, "-- Checked against both scrapbook entry.prefab and entry.name")
    table.insert(lines, "-- inventory item count: " .. tostring(#item_prefabs))
    table.insert(lines, "-- missing count: " .. tostring(#missing))
    table.insert(lines, "-- failed spawn count: " .. tostring(#failed_prefabs))
    table.insert(lines, "-- skipped no-fn count: " .. tostring(#skipped_prefabs))
    table.insert(lines, "")

    table.insert(lines, "====================")
    table.insert(lines, "MISSING FROM SCRAPBOOK")
    table.insert(lines, "====================")
    for _, prefab in ipairs(missing) do
        table.insert(lines, prefab)
    end

    table.insert(lines, "")
    table.insert(lines, "====================")
    table.insert(lines, "ALL INVENTORY ITEMS")
    table.insert(lines, "====================")
    for _, prefab in ipairs(item_prefabs) do
        table.insert(lines, prefab)
    end

    table.insert(lines, "")
    table.insert(lines, "====================")
    table.insert(lines, "FAILED TO SPAWN")
    table.insert(lines, "====================")
    for _, prefab in ipairs(failed_prefabs) do
        table.insert(lines, prefab)
    end

    table.insert(lines, "")
    table.insert(lines, "====================")
    table.insert(lines, "SKIPPED NO FN")
    table.insert(lines, "====================")
    for _, prefab in ipairs(skipped_prefabs) do
        table.insert(lines, prefab)
    end

    GLOBAL.TheSim:SetPersistentString(
        "wit_inventory_items_not_in_scrapbook.txt",
        table.concat(lines, "\n"),
        false,
        function(success)
            print(
                "[WIT] dump inventory items not in scrapbook:",
                success,
                "items:",
                #item_prefabs,
                "missing:",
                #missing,
                "failed:",
                #failed_prefabs,
                "skipped:",
                #skipped_prefabs
            )
        end
    )
end

WIT_DumpInventoryItemsNotInScrapbook =
    GLOBAL.WIT_DumpInventoryItemsNotInScrapbook