-- [JEI] What Is This - modmain
-- 入口文件: 全局常量 + 事件注册 + 模块加载

GLOBAL.setmetatable(env, { __index = function(_, k) return GLOBAL.rawget(GLOBAL, k) end })

-- 模块依赖
GLOBAL.Widget = require("widgets/widget")
GLOBAL.Image = require("widgets/image")
GLOBAL.Text = require("widgets/text")
GLOBAL.TextButton = require("widgets/textbutton")
GLOBAL.ImageButton = require("widgets/imagebutton")

Widget = GLOBAL.Widget
Image = GLOBAL.Image
Text = GLOBAL.Text
TextButton = GLOBAL.TextButton
ImageButton = GLOBAL.ImageButton

-- ============================
-- 全局常量 (WIT_ 前缀避免全局污染)
-- WIT_COOKING_ALIASES / WIT_INGREDIENT_PREFAB_MAP → wit_core.lua
-- WIT_PAGE_SIZE → wit_ui.lua

-- ============================
-- 数据层状态
-- ============================
WIT = {}
WIT.by_product = {}
WIT.by_material = {}
WIT.cook_foods = {}
WIT.cook_by_ingredient = {}
WIT.ingredient_tags = {}
WIT_data_built = false

-- ============================
-- UI 层状态
-- ============================
WIT_POPUP = nil
WIT_NAME = nil
WIT_MODE = nil
WIT_CUR_CAT = nil
WIT_PAGE = 1
WIT_AVAIL_CATS = {}
WIT_CONTENT = nil
WIT_TAB_BTNS = {}
WIT_PG_TEXT = nil
WIT_PG_PREV = nil
WIT_PG_NEXT = nil
WIT_OPEN_COOKPOT = nil
WIT_HOVER_INFO = true  -- 可在配置中关闭，wit_ui.lua 读取
WIT_HOVERED_DETAIL_PREFAB = nil  -- 合成菜单详情面板当前悬浮的 prefab，供 R/U 键回退
WIT_BACK_STACK = {}  -- 导航历史栈：后退
WIT_FORWARD_STACK = {}  -- 导航历史栈：前进
WIT_PrevHistory = nil  -- ClosePopup 暂存的上一条目，CreatePopup 消费入栈
WIT_SCRAPBOOK_BG = nil  -- 图鉴模式下弹窗背景遮罩

-- ============================
-- 纯客户端实体拦截
-- ============================
WIT_SPAWNING_ITEM = false
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

-- 读取悬浮详情配置
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
    ['\238\132\130'] = 1002,  -- 中键
    ['\238\132\131'] = 1005,  -- 后侧键
    ['\238\132\132'] = 1006,  -- 前侧键
}
local function _ResolveNavKey(name)
    local val = GetModConfigData(name)
    if type(val) == "string" then
        local code = GLOBAL.rawget(GLOBAL, val)
        if type(code) == "number" then return code end
        code = _NavKeyCode[val]
        if code then return code end
        if val:find("^KEY_KP_") then
            local numpad = { KP_0 = 269, KP_1 = 257, KP_2 = 258, KP_3 = 259, KP_4 = 260,
                KP_5 = 261, KP_6 = 262, KP_7 = 263, KP_8 = 264, KP_9 = 265,
                KP_PERIOD = 266, KP_DIVIDE = 267, KP_MULTIPLY = 106,
                KP_MINUS = 109, KP_PLUS = 107 }
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
        return orig_oc and orig_oc(btn, control, down)
    end

    -- 悬浮反馈 + 记录悬浮 prefab 供 R/U 键调度
    local orig_gain = self.ongainfocus
    self.ongainfocus = function()
        self:SetScale(1.08, 1.08)
        WIT_HOVERED_DETAIL_PREFAB = prefab
        if orig_gain then orig_gain() end
    end
    local orig_lose = self.onlosefocus
    self.onlosefocus = function()
        self:SetScale(1, 1)
        WIT_HOVERED_DETAIL_PREFAB = nil
        if orig_lose then orig_lose() end
    end
end)

-- 产物图标（皮肤选择器）：加透明可点击层 + 左击 WIT 来源 / 右击 WIT 用途 + 悬浮微亮
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
