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
    local WIT_DUMMY_TASK = {
        Cancel = function() end,
    }

    local oldRegisterComponentActions = self.RegisterComponentActions
    if oldRegisterComponentActions ~= nil then
        self.RegisterComponentActions = function(self, name)
            if not WIT_SPAWNING_ITEM then
                return oldRegisterComponentActions(self, name)
            end
        end
    end

    local oldDoTaskInTime = self.DoTaskInTime
    if oldDoTaskInTime ~= nil then
        self.DoTaskInTime = function(self, time, fn, ...)
            if WIT_SPAWNING_ITEM then
                return WIT_DUMMY_TASK
            end

            return oldDoTaskInTime(self, time, fn, ...)
        end
    end

    local oldDoPeriodicTask = self.DoPeriodicTask
    if oldDoPeriodicTask ~= nil then
        self.DoPeriodicTask = function(self, time, fn, initialdelay, ...)
            if WIT_SPAWNING_ITEM then
                return WIT_DUMMY_TASK
            end

            return oldDoPeriodicTask(self, time, fn, initialdelay, ...)
        end
    end
end)

AddComponentPostInit("timer", function(self)
    local oldStartTimer = self.StartTimer
    if oldStartTimer ~= nil then
        self.StartTimer = function(self, name, time, ...)
            if WIT_SPAWNING_ITEM and time == nil then
                print(
                    "[WIT] skipped nil timer while spawning item:",
                    self.inst and self.inst.prefab or nil,
                    name
                )
                return
            end

            return oldStartTimer(self, name, time, ...)
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
    modimport("scripts/wit_core.lua")
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

local function WIT_GetSortedKeys(source)
    local keys = {}

    if type(source) == "table" then
        for key, _ in pairs(source) do
            table.insert(keys, tostring(key))
        end
    end

    table.sort(keys)

    return keys
end

local function WIT_ToExportScalar(value)
    local value_type = type(value)

    if value_type == "nil"
        or value_type == "string"
        or value_type == "boolean" then
        return value
    end

    if value_type == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return tostring(value)
        end

        return value
    end

    return tostring(value)
end

local WIT_INVENTORY_EXPORT_SKIP_PREFABS =
{
    quagmirestage_dialog = true,
    lavaarena_portal = true,
    lavaarena_bernie = true,
}

local WIT_INVENTORY_EXPORT_SKIP_PREFIXES =
{
    "quagmirestage_",
    "lavaarena_endofmatch_",
}

local WIT_INVENTORY_EXPORT_SKIP_PATTERNS =
{
    "_parkspike$",
}

local function WIT_ShouldSkipInventoryExportPrefab(prefab)
    if WIT_INVENTORY_EXPORT_SKIP_PREFABS[prefab] == true then
        return true
    end

    for _, prefix in ipairs(WIT_INVENTORY_EXPORT_SKIP_PREFIXES) do
        if string.sub(prefab, 1, #prefix) == prefix then
            return true
        end
    end

    for _, pattern in ipairs(WIT_INVENTORY_EXPORT_SKIP_PATTERNS) do
        if string.match(prefab, pattern) ~= nil then
            return true
        end
    end

    return false
end

local function WIT_LoadChineseNames()
    local chinese_names = {}

    local ok_translator = pcall(GLOBAL.require, "translator")
    if not ok_translator
        or GLOBAL.LanguageTranslator == nil
        or GLOBAL.LanguageTranslator.LoadPOFile == nil
        or GLOBAL.LanguageTranslator.GetTranslatedString == nil then
        return chinese_names
    end

    local language_id = "wit_chinese_s"
    local old_default_language = GLOBAL.LanguageTranslator.defaultlang
    local ok_load = pcall(function()
        GLOBAL.LanguageTranslator:LoadPOFile("languages/chinese_s.po", language_id)
    end)
    GLOBAL.LanguageTranslator.defaultlang = old_default_language

    if not ok_load then
        return chinese_names
    end

    return setmetatable(chinese_names, {
        __index = function(cache, name_key)
            local translated = GLOBAL.LanguageTranslator:GetTranslatedString(
                "STRINGS.NAMES." .. tostring(name_key),
                language_id
            )

            if translated == "" then
                translated = nil
            end

            rawset(cache, name_key, translated or false)

            return translated
        end,
    })
end

local function WIT_GetInventoryImage(inst, inventoryitem)
    local image = inventoryitem ~= nil
        and inventoryitem.imagename ~= nil
        and inventoryitem.imagename ~= ""
        and inventoryitem.imagename
        or inst.prefab

    if image ~= nil and not string.match(image, "%.tex$") then
        image = image .. ".tex"
    end

    local atlas = inventoryitem ~= nil
        and inventoryitem.atlasname ~= nil
        and inventoryitem.atlasname ~= ""
        and inventoryitem.atlasname
        or nil

    if atlas == nil and image ~= nil and GLOBAL.GetInventoryItemAtlas ~= nil then
        local ok_atlas, resolved_atlas = pcall(GLOBAL.GetInventoryItemAtlas, image)
        if ok_atlas then
            atlas = resolved_atlas
        end
    end

    return image, atlas
end

local function WIT_BuildRecipeIndex()
    local recipe_index = {}

    if type(GLOBAL.AllRecipes) ~= "table" then
        return recipe_index
    end

    for recipe_name, recipe in pairs(GLOBAL.AllRecipes) do
        if type(recipe) == "table" then
            local product = recipe.product or recipe.name or recipe_name

            if type(product) == "string" and product ~= "" then
                if recipe_index[product] == nil then
                    recipe_index[product] = {}
                end

                table.insert(recipe_index[product], recipe)
            end
        end
    end

    for _, recipes in pairs(recipe_index) do
        table.sort(recipes, function(left, right)
            return tostring(left.name or "") < tostring(right.name or "")
        end)
    end

    return recipe_index
end

local function WIT_SerializeIngredients(ingredients)
    local result = {}

    if type(ingredients) ~= "table" then
        return result
    end

    for _, ingredient in ipairs(ingredients) do
        if type(ingredient) == "table" then
            local image = ingredient.image
            local atlas = ingredient.atlas

            if ingredient.GetImage ~= nil then
                local ok_image, resolved_image = pcall(function()
                    return ingredient:GetImage()
                end)
                if ok_image then
                    image = resolved_image
                end
            end

            if ingredient.GetAtlas ~= nil then
                local ok_atlas, resolved_atlas = pcall(function()
                    return ingredient:GetAtlas()
                end)
                if ok_atlas then
                    atlas = resolved_atlas
                end
            end

            table.insert(result, {
                type = WIT_ToExportScalar(ingredient.type),
                amount = WIT_ToExportScalar(ingredient.amount),
                image = WIT_ToExportScalar(image),
                atlas = WIT_ToExportScalar(atlas),
            })
        end
    end

    return result
end

local function WIT_SerializeRecipes(recipes)
    local result = {}

    if type(recipes) ~= "table" then
        return result
    end

    for _, recipe in ipairs(recipes) do
        table.insert(result, {
            name = WIT_ToExportScalar(recipe.name),
            product = WIT_ToExportScalar(recipe.product or recipe.name),
            numtogive = WIT_ToExportScalar(recipe.numtogive),
            builder_tag = WIT_ToExportScalar(recipe.builder_tag),
            builder_skill = WIT_ToExportScalar(recipe.builder_skill),
            placer = WIT_ToExportScalar(recipe.placer),
            ingredients = WIT_SerializeIngredients(recipe.ingredients),
        })
    end

    return result
end

local function WIT_CollectInventoryItemData(inst, scrapbook_prefabs, scrapbook_names, chinese_names, recipe_index)
    local inventoryitem = inst.components ~= nil and inst.components.inventoryitem or nil
    local image, atlas = WIT_GetInventoryImage(inst, inventoryitem)
    local name_key = string.upper(tostring(inst.nameoverride or inst.prefab))
    local display_name = GLOBAL.STRINGS ~= nil
        and GLOBAL.STRINGS.NAMES ~= nil
        and GLOBAL.STRINGS.NAMES[name_key]
        or inst.name
    local chinese_name = chinese_names[name_key]

    if chinese_name == false then
        chinese_name = nil
    end

    local entry = {
        prefab = inst.prefab,
        name_key = name_key,
        display_name = display_name ~= "MISSING NAME" and display_name or nil,
        chinese_name = chinese_name or (display_name ~= "MISSING NAME" and display_name or nil),
        inventory_image = image,
        inventory_atlas = atlas,
        in_scrapbook = scrapbook_prefabs[inst.prefab] == true or scrapbook_names[inst.prefab] == true,
        tags = WIT_GetSortedKeys(inst.tags),
        components = WIT_GetSortedKeys(inst.components),
        recipe = WIT_SerializeRecipes(recipe_index[inst.prefab]),
    }

    if inventoryitem ~= nil then
        entry.inventory = {
            can_be_picked_up = inventoryitem.canbepickedup == true,
            can_be_picked_up_alive = inventoryitem.canbepickedupalive == true,
            can_go_in_container = inventoryitem.cangoincontainer == true,
            can_only_go_in_pocket = inventoryitem.canonlygoinpocket == true,
            can_only_go_in_pocket_or_pocket_containers = inventoryitem.canonlygoinpocketorpocketcontainers == true,
            is_locked_in_slot = inventoryitem.islockedinslot == true,
            keep_on_death = inventoryitem.keepondeath == true,
            sinks = inventoryitem.sinks == true,
        }
    end

    if inst.components ~= nil then
        if inst.components.stackable ~= nil then
            entry.stackable = {
                stack_size = WIT_ToExportScalar(inst.components.stackable.stacksize),
                max_size = WIT_ToExportScalar(inst.components.stackable.maxsize),
            }
        end

        if inst.components.equippable ~= nil then
            entry.equippable = {
                equip_slot = WIT_ToExportScalar(inst.components.equippable.equipslot),
                walk_speed_mult = WIT_ToExportScalar(inst.components.equippable.walkspeedmult),
                dapperness = WIT_ToExportScalar(inst.components.equippable.dapperness),
                insulated = inst.components.equippable.insulated == true,
            }
        end

        if inst.components.edible ~= nil then
            entry.edible = {
                food_type = WIT_ToExportScalar(inst.components.edible.foodtype),
                secondary_food_type = WIT_ToExportScalar(inst.components.edible.secondaryfoodtype),
                health = WIT_ToExportScalar(inst.components.edible.healthvalue),
                hunger = WIT_ToExportScalar(inst.components.edible.hungervalue),
                sanity = WIT_ToExportScalar(inst.components.edible.sanityvalue),
                temperature_delta = WIT_ToExportScalar(inst.components.edible.temperaturedelta),
                temperature_duration = WIT_ToExportScalar(inst.components.edible.temperatureduration),
                spice = WIT_ToExportScalar(inst.components.edible.spice),
            }
        end

        if inst.components.perishable ~= nil then
            entry.perishable = {
                perish_time = WIT_ToExportScalar(inst.components.perishable.perishtime),
                perish_remaining_time = WIT_ToExportScalar(inst.components.perishable.perishremainingtime),
                percent = WIT_ToExportScalar(nil),
            }
            if inst.components.perishable.GetPercent ~= nil then
                local ok_percent, percent = pcall(function()
                    return inst.components.perishable:GetPercent()
                end)
                if ok_percent then
                    entry.perishable.percent = WIT_ToExportScalar(percent)
                end
            end
        end

        if inst.components.fuel ~= nil then
            entry.fuel = {
                fuel_type = WIT_ToExportScalar(inst.components.fuel.fueltype),
                fuel_value = WIT_ToExportScalar(inst.components.fuel.fuelvalue),
            }
        end

        if inst.components.weapon ~= nil then
            entry.weapon = {
                damage = WIT_ToExportScalar(type(inst.components.weapon.damage) == "number" and
                    inst.components.weapon.damage or nil),
                attack_range = WIT_ToExportScalar(inst.components.weapon.attackrange),
                hit_range = WIT_ToExportScalar(inst.components.weapon.hitrange),
                projectile = WIT_ToExportScalar(inst.components.weapon.projectile),
            }
        end

        if inst.components.armor ~= nil then
            entry.armor = {
                condition = WIT_ToExportScalar(inst.components.armor.condition),
                max_condition = WIT_ToExportScalar(inst.components.armor.maxcondition),
                absorb_percent = WIT_ToExportScalar(inst.components.armor.absorb_percent),
                indestructible = inst.components.armor.indestructible == true,
            }
        end

        if inst.components.finiteuses ~= nil then
            entry.finiteuses = {
                current = WIT_ToExportScalar(inst.components.finiteuses.current),
                total = WIT_ToExportScalar(inst.components.finiteuses.total),
            }
        end
    end

    return entry
end

local function WIT_AddNoSpawnCandidate(candidates, prefab, source)
    if type(prefab) ~= "string" or prefab == "" then
        return
    end

    if GLOBAL.IsCharacterIngredient ~= nil and GLOBAL.IsCharacterIngredient(prefab) then
        return
    end

    if candidates[prefab] == nil then
        candidates[prefab] = {
            prefab = prefab,
            sources = {},
        }
    end

    candidates[prefab].sources[source] = true
end

local function WIT_AddNoSpawnScrapbookCandidate(candidates, entry)
    if type(entry) ~= "table" then
        return
    end

    local prefab = entry.prefab or entry.name
    WIT_AddNoSpawnCandidate(candidates, prefab, "scrapbook")

    if type(prefab) == "string" and prefab ~= "" and candidates[prefab] ~= nil then
        candidates[prefab].scrapbook_entry = entry
    end
end

local function WIT_BuildNoSpawnCandidates(scrapbookdata)
    local candidates = {}

    if type(scrapbookdata) == "table" then
        for _, entry in pairs(scrapbookdata) do
            WIT_AddNoSpawnScrapbookCandidate(candidates, entry)
        end
    end

    if type(GLOBAL.AllRecipes) == "table" then
        for recipe_name, recipe in pairs(GLOBAL.AllRecipes) do
            if type(recipe) == "table" then
                WIT_AddNoSpawnCandidate(
                    candidates,
                    recipe.product or recipe.name or recipe_name,
                    "recipe_product"
                )

                if type(recipe.ingredients) == "table" then
                    for _, ingredient in ipairs(recipe.ingredients) do
                        if type(ingredient) == "table" then
                            WIT_AddNoSpawnCandidate(
                                candidates,
                                ingredient.type,
                                "recipe_ingredient"
                            )
                        end
                    end
                end
            end
        end
    end

    return candidates
end

local function WIT_CollectNoSpawnInventoryItemData(prefab, candidate, scrapbook_prefabs, scrapbook_names, chinese_names,
                                                   recipe_index)
    local name_key = string.upper(tostring(prefab))
    local scrapbook_entry = candidate.scrapbook_entry
    local scrapbook_name = type(scrapbook_entry) == "table" and scrapbook_entry.name or nil
    local scrapbook_name_key = type(scrapbook_name) == "string"
        and string.upper(scrapbook_name)
        or nil
    local display_name = GLOBAL.STRINGS ~= nil
        and GLOBAL.STRINGS.NAMES ~= nil
        and (GLOBAL.STRINGS.NAMES[name_key] or (scrapbook_name_key ~= nil and GLOBAL.STRINGS.NAMES[scrapbook_name_key] or nil))
        or nil
    local chinese_name = chinese_names[name_key]
    local image = type(scrapbook_entry) == "table"
        and type(scrapbook_entry.tex) == "string"
        and scrapbook_entry.tex
        or prefab .. ".tex"
    local atlas = nil

    if chinese_name == false then
        chinese_name = nil
    end

    if GLOBAL.GetInventoryItemAtlas ~= nil then
        local ok_atlas, resolved_atlas = pcall(GLOBAL.GetInventoryItemAtlas, image)
        if ok_atlas then
            atlas = resolved_atlas
        end
    end

    return {
        prefab = prefab,
        name = scrapbook_name,
        name_key = name_key,
        scrapbook_name = scrapbook_name,
        scrapbook_name_key = scrapbook_name_key,
        scrapbook_type = type(scrapbook_entry) == "table" and scrapbook_entry.type or nil,
        scrapbook_subcat = type(scrapbook_entry) == "table" and scrapbook_entry.subcat or nil,
        scrapbook_specialinfo = type(scrapbook_entry) == "table" and scrapbook_entry.specialinfo or nil,
        display_name = display_name,
        inventory_image = image,
        inventory_atlas = atlas,
        in_scrapbook = scrapbook_prefabs[prefab] == true or scrapbook_names[prefab] == true,
        sources = WIT_GetSortedKeys(candidate.sources),
        recipe = WIT_SerializeRecipes(recipe_index[prefab]),
        no_spawn = true,
        note = "No-spawn candidate from recipes and/or scrapbook; component data is unavailable without SpawnPrefab.",
    }
end

local function WIT_WriteAllInventoryItemExports(entries, missing, failed_prefabs, skipped_prefabs, mode)
    local metadata = {
        mode = mode or "spawn",
        item_count = #entries,
        missing_from_scrapbook_count = #missing,
        failed_spawn_count = #failed_prefabs,
        skipped_no_fn_count = #skipped_prefabs,
    }

    local export_data = {
        metadata = metadata,
        items = entries,
        missing_from_scrapbook = missing,
        failed_to_spawn = failed_prefabs,
        skipped_no_fn = skipped_prefabs,
    }

    local ok_lua, lua_body = pcall(function()
        return WIT_SerializeValue(export_data, 0, {})
    end)

    if ok_lua then
        local lua_lines = {
            "-- WIT all inventory item prefab database",
            "-- Generated by WIT_DumpAllInventoryItems()",
            "return " .. lua_body,
        }

        GLOBAL.TheSim:SetPersistentString(
            "wit_all_inventory_items.lua",
            table.concat(lua_lines, "\n"),
            false,
            function(success)
                print("[WIT] dump all inventory items lua:", success, "items:", #entries)
            end
        )
    else
        print("[WIT] failed to serialize lua export:", lua_body)
    end

    local ok_json, json_module = pcall(GLOBAL.require, "json")
    if not ok_json
        or type(json_module) ~= "table"
        or json_module.encode_compliant == nil then
        json_module = GLOBAL.json
    end

    if json_module ~= nil and json_module.encode_compliant ~= nil then
        local ok_encode, json_text = pcall(json_module.encode_compliant, export_data)

        if ok_encode then
            GLOBAL.TheSim:SetPersistentString(
                "wit_all_inventory_items.json",
                json_text,
                false,
                function(success)
                    print("[WIT] dump all inventory items json:", success, "items:", #entries)
                end
            )
        else
            print("[WIT] failed to serialize json export:", json_text)
        end
    else
        print("[WIT] failed to load json encoder; lua export was still written")
    end
end

-- ============================
-- Debug：Spawn 版导出所有“物品 prefab”的结构化数据库
--
-- 判断“物品”的标准：
--   SpawnPrefab(prefab) 后，
--   inst.components.inventoryitem 或 inst.replica.inventoryitem 存在
--
-- 输出文件：
--   wit_all_inventory_items.lua
--   wit_all_inventory_items.json
-- ============================

GLOBAL.WIT_DumpAllInventoryItemsWithSpawn = function()
    print("[WIT] scanning all inventory items with SpawnPrefab...")

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

    local chinese_names = WIT_LoadChineseNames()
    local recipe_index = WIT_BuildRecipeIndex()

    -- 2. 遍历所有 prefab，临时生成，判断是否是物品
    local entries = {}
    local failed_prefabs = {}
    local skipped_prefabs = {}

    for prefab, prefab_def in pairs(GLOBAL.Prefabs) do
        if type(prefab) == "string" and prefab ~= "" then
            -- 关键保护：
            -- 有些 Prefabs[prefab] 不是完整 prefab 定义，或者 prefab_def.fn 是 nil。
            -- 这种不能 SpawnPrefab，否则会报：
            -- attempt to call field 'fn' (a nil value)
            if WIT_ShouldSkipInventoryExportPrefab(prefab) then
                table.insert(skipped_prefabs, prefab)
            elseif type(prefab_def) ~= "table"
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
                        local ok_collect, item_entry = pcall(function()
                            return WIT_CollectInventoryItemData(
                                inst,
                                scrapbook_prefabs,
                                scrapbook_names,
                                chinese_names,
                                recipe_index
                            )
                        end)

                        if ok_collect and item_entry ~= nil then
                            table.insert(entries, item_entry)
                        else
                            table.insert(
                                failed_prefabs,
                                prefab .. " [collect: " .. tostring(item_entry) .. "]"
                            )
                        end
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

    table.sort(entries, function(left, right)
        return tostring(left.prefab or "") < tostring(right.prefab or "")
    end)
    table.sort(failed_prefabs)
    table.sort(skipped_prefabs)

    -- 3. 找出“不在图鉴里”的物品 prefab
    local missing = {}

    for _, entry in ipairs(entries) do
        if not entry.in_scrapbook then
            table.insert(missing, entry.prefab)
        end
    end

    table.sort(missing)

    -- 4. 保存结果
    WIT_WriteAllInventoryItemExports(
        entries,
        missing,
        failed_prefabs,
        skipped_prefabs,
        "spawn"
    )
end

GLOBAL.WIT_DumpAllInventoryItemsNoSpawn = function()
    print("[WIT] scanning inventory item candidates without SpawnPrefab...")

    local ok, scrapbookdata = pcall(
        GLOBAL.require,
        "screens/redux/scrapbookdata"
    )

    if not ok or type(scrapbookdata) ~= "table" then
        print("[WIT] failed to load scrapbookdata:", scrapbookdata)
        return
    end

    local scrapbook_prefabs = {}
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

    local chinese_names = WIT_LoadChineseNames()
    local recipe_index = WIT_BuildRecipeIndex()
    local candidates = WIT_BuildNoSpawnCandidates(scrapbookdata)
    local entries = {}
    local missing = {}
    local failed_prefabs = {}
    local skipped_prefabs = {}

    for prefab, candidate in pairs(candidates) do
        table.insert(
            entries,
            WIT_CollectNoSpawnInventoryItemData(
                prefab,
                candidate,
                scrapbook_prefabs,
                scrapbook_names,
                chinese_names,
                recipe_index
            )
        )
    end

    table.sort(entries, function(left, right)
        return tostring(left.prefab or "") < tostring(right.prefab or "")
    end)

    for _, entry in ipairs(entries) do
        if not entry.in_scrapbook then
            table.insert(missing, entry.prefab)
        end
    end

    table.sort(missing)

    WIT_WriteAllInventoryItemExports(
        entries,
        missing,
        failed_prefabs,
        skipped_prefabs,
        "no_spawn"
    )
end

-- Debug：生成某个 prefab，打印它的实体结构摘要，然后自动移除。
GLOBAL.WIT_DumpPrefabInst = function(prefab)
    if type(prefab) ~= "string" or prefab == "" then
        print("[WIT] WIT_DumpPrefabInst requires a prefab string")
        return
    end

    local prefab_def = GLOBAL.Prefabs and GLOBAL.Prefabs[prefab] or nil
    if type(prefab_def) ~= "table" or type(prefab_def.fn) ~= "function" then
        print("[WIT] prefab is not spawnable:", prefab)
        return
    end

    local old_spawning_flag = WIT_SPAWNING_ITEM
    WIT_SPAWNING_ITEM = true

    local ok_spawn, inst = pcall(function()
        return GLOBAL.SpawnPrefab(prefab)
    end)

    WIT_SPAWNING_ITEM = old_spawning_flag

    if not ok_spawn or inst == nil then
        print("[WIT] failed to spawn prefab:", prefab, inst)
        return
    end

    print("[WIT] ===== PREFAB INST =====")
    print("[WIT] prefab =", tostring(inst.prefab))
    print("[WIT] name =", tostring(inst.name))
    print("[WIT] nameoverride =", tostring(inst.nameoverride))
    print("[WIT] GUID =", tostring(inst.GUID))

    if inst.Transform ~= nil then
        local x, y, z = inst.Transform:GetWorldPosition()
        print("[WIT] position =", tostring(x), tostring(y), tostring(z))
    end

    print("[WIT] -- tags --")
    for tag, _ in pairs(inst.tags or {}) do
        print("[WIT] tag:", tag)
    end

    print("[WIT] -- components --")
    for name, component in pairs(inst.components or {}) do
        print("[WIT] component:", name, component)
    end

    print("[WIT] -- replica --")
    for name, replica in pairs(inst.replica or {}) do
        print("[WIT] replica:", name, replica)
    end

    print("[WIT] -- raw table depth 1 --")
    if GLOBAL.dumptable ~= nil then
        GLOBAL.dumptable(inst, 1, 1)
    else
        for key, value in pairs(inst) do
            print("[WIT] field:", key, value)
        end
    end

    if inst.Remove ~= nil then
        local ok_remove, remove_error = pcall(function()
            inst:Remove()
        end)
        if not ok_remove then
            print("[WIT] failed to remove prefab dump inst:", prefab, remove_error)
        end
    end
end


local skiplist = {}
skiplist["blossom_hit_fx"] = true
skiplist["quagmire_parkspike"] = true
skiplist["quagmire_spotspice_shrub"] = true
skiplist["lavaarena_elemental"] = true
skiplist["lavaarena"] = true
skiplist["fireball_hit_fx"] = true
skiplist["quagmire_coin_fx"] = true
skiplist["lavaarena_spectator"] = true
skiplist["global"] = true
skiplist["audio_test_prefab"] = true
skiplist["peghook_hitfx"] = true
skiplist["quagmire_coin4"] = true
skiplist["quagmire_food"] = true
skiplist["lavaarena_boarlord"] = true
skiplist["quagmire"] = true
skiplist["world"] = true
skiplist["shard_network"] = true
skiplist["cave_network"] = true
skiplist["cave"] = true
skiplist["gooball_hit_fx"] = true
skiplist["forest_network"] = true
skiplist["peghook_splashfx"] = true
skiplist["quagmire_network"] = true
skiplist["lavaarena_network"] = true
skiplist["quagmire_mushroomstump"] = true
skiplist["forest"] = true
skiplist["quagmire_parkspike_short"] = true
skiplist["reticulearc"] = true
skiplist["reticuleline"] = true
skiplist["reticulelong"] = true
skiplist["reticuleaoe"] = true
skiplist["reticule"] = true
skiplist["MOD_wit-recipe-revealer"] = true
skiplist["quagmirestage_dialog"] = true
skiplist["quagmirestage_wait"] = true
skiplist["lavaarenastage_dialog"] = true
skiplist["lavaarenastage_endofround"] = true
skiplist["lavaarenastage_allplayersspawned"] = true
skiplist["vault_invalidtile"] = true

-- 大型活动 prefab 在普通世界里经常缺 event server 资源，Spawn 会刷大量警告。
local function WIT_ShouldSkipDumpSpawnPrefab(prefab)
    return type(prefab) == "string"
        and (prefab:match("^quagmire") ~= nil or prefab:match("^lavaarena") ~= nil)
end

-- 导出带生命和伤害信息的生物清单。
function d_dumpCreatureTXT()
    local f = io.open("creatures.txt", "w")
    local total = 0
    local str = ""
    if f then
        --"PREFAB","NAME", "HEALTH", "DAMAGE"
        str = str .. string.format("%s;%s;%s;%s\n", "PREFAB", "NAME", "HEALTH", "DAMAGE")
        for i, data in pairs(GLOBAL.Prefabs) do
            print("=====>", i)
            -- dumptable(data,1,1)
            if not data.base_prefab and not skiplist[i] then -- not a skin
                local t = GLOBAL.SpawnPrefab(i)
                if t and t.components.health then
                    --if t and (t:HasTag("smallcreature") or t:HasTag("monster") or t:HasTag("animal")) then

                    local name = t.name or "---"
                    local health = t.components.health and t.components.health.maxhealth or 0
                    local damage = t.components.combat and t.components.combat.defaultdamage or 0

                    str = str .. string.format("%s;%s;%s;%s\n", i, name, tostring(health), tostring(damage))
                end
                t:Remove()
                total = total + 1
            else
                print("Skipping")
            end
        end

        f:write(str)
    end
end

-- 导出物品预制体清单。
GLOBAL.d_dumpAItemsTXT = function()
    print("[WIT] dumping item list with SpawnPrefab...")

    local checked = 0
    local failed = 0
    local total = 0
    local lines = {
        string.format(
            "%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s",
            "PREFAB",
            "NAME",
            "STACKSIZE",
            "DURABILITY",
            "SPOILTIME",
            "FOOD-HEALTH",
            "FOOD-HUNGER",
            "FOOD-SANITY",
            "DAMAGE",
            "PLANAR DAMAGE",
            "ARMOR-%",
            "ARMOR-HEALTH"
        ),
    }

    for prefab, data in pairs(GLOBAL.Prefabs) do
        print("=====>", prefab)
        if type(data) == "table"
            and type(data.fn) == "function"
            and not data.base_prefab
            and not skiplist[prefab]
            and not WIT_ShouldSkipDumpSpawnPrefab(prefab) then -- not a skin
            checked = checked + 1

            local old_spawning_flag = WIT_SPAWNING_ITEM
            WIT_SPAWNING_ITEM = true

            local ok_spawn, inst = pcall(function()
                return GLOBAL.SpawnPrefab(prefab)
            end)

            WIT_SPAWNING_ITEM = old_spawning_flag

            if ok_spawn and inst ~= nil then
                if inst.components ~= nil then
                    local name = inst.name or "---"
                    local stack = inst.components.stackable and inst.components.stackable.maxsize or 1
                    local durability = inst.components.finiteuses and inst.components.finiteuses.total or 0
                    local spoiltime = inst.components.perishable and inst.components.perishable.perishtime or 0

                    local food_health = inst.components.edible and inst.components.edible.healthvalue or "-"
                    local food_hunger = inst.components.edible and inst.components.edible.hungervalue or "-"
                    local food_sanity = inst.components.edible and inst.components.edible.sanityvalue or "-"

                    local weapondamage = inst.components.weapon and inst.components.weapon.damage or "-"
                    local planardamage = inst.components.planardamage and inst.components.planardamage.basedamage or "-"
                    local absorb_percent = inst.components.armor and inst.components.armor.absorb_percent or "-"
                    local condition = inst.components.armor and inst.components.armor.condition or "-"

                    table.insert(
                        lines,
                        string.format(
                            "%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s",
                            tostring(prefab),
                            tostring(name),
                            tostring(stack),
                            tostring(durability),
                            tostring(spoiltime),
                            tostring(food_health),
                            tostring(food_hunger),
                            tostring(food_sanity),
                            tostring(weapondamage),
                            tostring(planardamage),
                            tostring(absorb_percent),
                            tostring(condition)
                        )
                    )
                    total = total + 1
                end

                if inst.Remove ~= nil then
                    local ok_remove, remove_error = pcall(function()
                        inst:Remove()
                    end)
                    if not ok_remove then
                        print("[WIT] failed to remove spawned item candidate:", prefab, remove_error)
                    end
                end
            else
                failed = failed + 1
                print("[WIT] failed to spawn item candidate:", prefab, inst)
            end
        end
    end

    table.sort(lines)

    GLOBAL.TheSim:SetPersistentString(
        "items.txt",
        table.concat(lines, "\n") .. "\n",
        false,
        function(success)
            print(
                "[WIT] dump items.txt:",
                success,
                "items:",
                total,
                "checked:",
                checked,
                "failed:",
                failed
            )
        end
    )
end

GLOBAL.WIT_DumpAllInventoryItems = GLOBAL.WIT_DumpAllInventoryItemsNoSpawn

WIT_DumpAllInventoryItems = GLOBAL.WIT_DumpAllInventoryItems

GLOBAL.WIT_DumpInventoryItemsNotInScrapbook = GLOBAL.WIT_DumpAllInventoryItems

WIT_DumpInventoryItemsNotInScrapbook =
    GLOBAL.WIT_DumpInventoryItemsNotInScrapbook

WIT_DumpAllInventoryItemsNoSpawn = GLOBAL.WIT_DumpAllInventoryItemsNoSpawn
WIT_DumpAllInventoryItemsWithSpawn = GLOBAL.WIT_DumpAllInventoryItemsWithSpawn
